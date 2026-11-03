part of 'sampled_recording_library.dart';

extension _SampledRecordingImport on SampledRecordingLibrary {
  void _checkImport(RecordingFileCancellation cancellation) {
    if (cancellation.isCancelled) throw const RecordingFileCancelled();
  }

  Future<String> _importRecording(
    String sourcePath,
    RecordingFileCancellation cancellation,
  ) => _withLibraryLock((root) async {
    _checkImport(cancellation);
    await _retain(root);
    if ((await _list(root)).length >= 1000) {
      throw StateError('Recording library entry limit reached');
    }
    final available = maximumBytes - await _libraryBytes(root);
    if (available <= 0) {
      throw StateError('Protected recordings occupy the storage budget');
    }
    final imports = Directory('${root.path}/.imports');
    final random = Random.secure();
    late String nonce;
    late File journal;
    late Directory staging;
    do {
      nonce = List<int>.generate(
        16,
        (_) => random.nextInt(256),
      ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
      journal = File('${imports.path}/$nonce.json');
      staging = Directory('${imports.path}/$nonce.trailrec');
    } while (await FileSystemEntity.type(journal.path, followLinks: false) !=
            FileSystemEntityType.notFound ||
        await FileSystemEntity.type(staging.path, followLinks: false) !=
            FileSystemEntityType.notFound);
    _Lease? lease;
    try {
      // Publish ownership before any worker can create a partial destination.
      await _writeJson(journal, {'schema_version': 2, 'import_id': nonce});
      _checkImport(cancellation);
      final copy = await SampledRecordingFile.copyBundle(
        sourcePath,
        staging.path,
        api: files,
        maximumBytes: available,
        cancellation: cancellation,
      );
      final id = copy.info.id;
      lease = await _Lease.acquire('${root.path}/claims/$id.lock');
      final destination = '${root.path}/$id.trailrec';
      if (await FileSystemEntity.type(destination, followLinks: false) !=
              FileSystemEntityType.notFound ||
          await FileSystemEntity.type(
                '${root.path}/entries/$id.json',
                followLinks: false,
              ) !=
              FileSystemEntityType.notFound) {
        throw StateError('This recording already exists in the library');
      }
      // Build caches only in our copy. A read-only source needs no cache writes.
      final prepared = await SampledRecordingFile.open(
        staging.path,
        api: files,
        cancellation: cancellation,
      );
      try {
        if (prepared.info.id != id) {
          throw const FormatException('Copied recording identity changed');
        }
        // Includes staging indexes and growth of any live recordings since admission.
        if (await _libraryBytes(root) > maximumBytes) {
          throw StateError('Recording and indexes exceed the storage budget');
        }
        _checkImport(cancellation);
        // Cancellation after this boundary cannot undo an acknowledged publication.
        await SampledRecordingFile.publishBundle(
          staging.path,
          destination,
          recordingId: id,
          api: files,
        );
        await _write(root, _fromInfo(prepared.info, null, path: destination));
        return destination;
      } finally {
        await prepared.close();
      }
    } finally {
      try {
        // The worker future has settled before this runs, even after cancellation.
        // A publication with a lost acknowledgement may already be in the root:
        // clean only staging, leaving that protected orphan for recovery.
        await _cleanImport(journal);
      } finally {
        await lease?.close();
      }
    }
  });

  Future<void> _cleanImports(Directory root) async {
    await for (final entity in Directory(
      '${root.path}/.imports',
    ).list(followLinks: false)) {
      if (entity is File &&
          RegExp(r'/[0-9a-f]{32}\.json$').hasMatch(entity.path)) {
        await _cleanImport(entity);
      }
    }
  }

  Future<void> _cleanImport(File journal) async {
    // Unknown, corrupt, future-version and non-regular journals do not confer
    // ownership. Preserve them and their data as protected capacity.
    if (await FileSystemEntity.type(journal.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await journal.length() > 4096) {
      return;
    }
    Object? value;
    try {
      value = jsonDecode(await journal.readAsString());
    } on FormatException {
      return;
    }
    final nonce = journal.uri.pathSegments.last.split('.').first;
    if (value is! Map<String, dynamic> ||
        value.length != 2 ||
        value['schema_version'] is! int ||
        value['schema_version'] != 2 ||
        value['import_id'] != nonce ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(nonce)) {
      return;
    }
    final staging = Directory('${journal.parent.path}/$nonce.trailrec');
    final type = await FileSystemEntity.type(staging.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Import staging is not a directory',
        staging.path,
      );
    }
    if (type == FileSystemEntityType.directory) {
      await staging.delete(recursive: true);
    }
    // Retain the journal until removal of staging has a durable acknowledgement.
    await _syncDirectory(journal.parent);
    await _removeManifest(journal);
  }
}
