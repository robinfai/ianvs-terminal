import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:path_provider/path_provider.dart';

/// Claims live in the UI isolate. Disk workers never open these lock files:
/// POSIX process-scoped locks must not be accidentally closed by another owner.
final Map<String, Object> _processClaims = <String, Object>{};

final class RecordingLibraryBusy implements Exception {
  const RecordingLibraryBusy(this.path);
  final String path;
  @override
  String toString() => 'Recording is in use: $path';
}

final class SampledRecordingEntry {
  const SampledRecordingEntry({
    required this.id,
    required this.path,
    required this.displayName,
    required this.createdAtUtc,
    required this.duration,
    required this.state,
    required this.sessionId,
    required this.keep,
    this.hostname,
    this.error,
  });
  final String id;
  final String path;
  final String displayName;
  final DateTime createdAtUtc;
  final Duration duration;
  final String state;
  final String? sessionId;
  final bool keep;
  final String? hostname;
  final String? error;
  bool get isReadable =>
      const <String>{'finished', 'interrupted', 'damaged_tail'}.contains(state);
  bool get isActive => const <String>{
    'reserved',
    'starting',
    'capturing',
    'stopping',
    'unknown',
  }.contains(state);

  SampledRecordingEntry copyWith({
    Duration? duration,
    String? state,
    bool? keep,
    String? error,
  }) => SampledRecordingEntry(
    id: id,
    path: path,
    displayName: displayName,
    createdAtUtc: createdAtUtc,
    duration: duration ?? this.duration,
    state: state ?? this.state,
    sessionId: sessionId,
    keep: keep ?? this.keep,
    hostname: hostname,
    error: error,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'schema_version': 2,
    'id': id,
    'display_name': displayName,
    'created_at_millis': createdAtUtc.millisecondsSinceEpoch,
    'duration_micros': duration.inMicroseconds,
    'state': state,
    'session_id': sessionId,
    'keep': keep,
    'hostname': hostname,
    'error': error,
  };
}

final class SampledRecordingClaim {
  SampledRecordingClaim._(
    this.entry,
    this.handle,
    this._lease,
    this.sessionEpoch,
  );
  SampledRecordingEntry entry;
  final SampledCaptureHandle handle;
  final _Lease _lease;
  final int sessionEpoch;
  bool dispatched = false;
  bool settled = false;
  Future<String>? finishing;
  Future<void> _updates = Future<void>.value();
}

final class SampledOpenedRecording {
  SampledOpenedRecording._(this.entry, this.recording, this._lease);
  final SampledRecordingEntry entry;
  final SampledRecordingFile recording;
  final _Lease _lease;
  Future<void> close() async {
    await recording.close();
    await _lease.close();
  }
}

final class SampledRecordingRecovery {
  const SampledRecordingRecovery(this.recovered, this.busy, this.errors);
  final int recovered;
  final int busy;
  final List<String> errors;
}

/// Owns only a distinct schema-2 library. Existing NDJSON directories and legacy
/// indexes are never enumerated, imported, migrated or cleaned by this class.
class SampledRecordingLibrary {
  SampledRecordingLibrary({
    required this.files,
    Future<Directory> Function()? directoryResolver,
    this.maximumAge = const Duration(days: 30),
    this.maximumBytes = 20 * 1024 * 1024 * 1024,
  }) : _directoryResolver = directoryResolver ?? _defaultDirectory {
    if (maximumAge <= Duration.zero || maximumBytes <= 0) {
      throw ArgumentError('Recording retention limits must be positive');
    }
  }

  final RecordingFileApi files;
  final Future<Directory> Function() _directoryResolver;
  final Duration maximumAge;
  final int maximumBytes;
  Future<Directory>? _rootFuture;
  Future<void> _tail = Future<void>.value();
  final Map<String, SampledRecordingClaim> _active =
      <String, SampledRecordingClaim>{};
  Iterable<SampledRecordingClaim> get activeClaims =>
      List<SampledRecordingClaim>.unmodifiable(_active.values);
  static Future<Directory> _defaultDirectory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/recordings-v2',
  );

  Future<Directory> ensureRecordingDirectory() => _rootFuture ??= () async {
    final directory = await _directoryResolver();
    await directory.create(recursive: true);
    final root = Directory(await directory.resolveSymbolicLinks());
    await Directory('${root.path}/entries').create();
    await Directory('${root.path}/claims').create();
    return root;
  }();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<T> _withLibraryLock<T>(Future<T> Function(Directory root) action) =>
      _serial(() async {
        final root = await ensureRecordingDirectory();
        final lease = await _Lease.acquire('${root.path}/claims/library.lock');
        try {
          return await action(root);
        } finally {
          await lease.close();
        }
      });

  Future<SampledRecordingClaim> reserve({
    required String sessionId,
    required int sessionEpoch,
    required String title,
    String? hostname,
  }) => _withLibraryLock((root) async {
    if (_active.containsKey(sessionId)) {
      throw StateError('Session already owns a recording');
    }
    await _retain(root);
    final entries = await _list(root);
    if (entries.length >= 1000) {
      throw StateError('Recording library entry limit reached');
    }
    final bytes = await _libraryBytes(root);
    if (bytes >= maximumBytes) {
      throw StateError('Protected recordings occupy the storage budget');
    }
    final random = Random.secure();
    final id = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    final entry = SampledRecordingEntry(
      id: id,
      path: '${root.path}/$id.trailrec',
      displayName: title,
      createdAtUtc: DateTime.now().toUtc(),
      duration: Duration.zero,
      state: 'reserved',
      sessionId: sessionId,
      keep: false,
      hostname: hostname,
    );
    final handle = SampledCaptureHandle(
      sessionId: sessionId,
      captureId: id,
      bundlePath: entry.path,
    );
    SampledCaptureStart(
      handle: handle,
      startedAtUnixMillis: entry.createdAtUtc.millisecondsSinceEpoch,
      title: title,
      hostname: hostname,
    );
    final lease = await _Lease.acquire('${root.path}/claims/$id.lock');
    try {
      await _write(root, entry);
      final claim = SampledRecordingClaim._(entry, handle, lease, sessionEpoch);
      _active[sessionId] = claim;
      return claim;
    } on Object {
      await lease.close();
      rethrow;
    }
  });

  Future<SampledCaptureStatus> start(
    SampledRecordingClaim claim,
    SampledRecordingCaptureClient client,
  ) async {
    final root = await ensureRecordingDirectory();
    if (claim.dispatched) {
      throw StateError('Capture was already dispatched; query its identity');
    }
    claim.entry = claim.entry.copyWith(state: 'starting');
    await _write(root, claim.entry);
    // Set before crossing the native boundary; a lost reply retains the lease.
    claim.dispatched = true;
    final status = client.start(
      SampledCaptureStart(
        handle: claim.handle,
        startedAtUnixMillis: claim.entry.createdAtUtc.millisecondsSinceEpoch,
        title: claim.entry.displayName,
        hostname: claim.entry.hostname,
      ),
    );
    await update(claim, status);
    return status;
  }

  Future<void> update(
    SampledRecordingClaim claim,
    SampledCaptureStatus status,
  ) async {
    final update = claim._updates.then((_) => _update(claim, status));
    claim._updates = update.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return update;
  }

  Future<void> _update(
    SampledRecordingClaim claim,
    SampledCaptureStatus status,
  ) async {
    if (claim.settled && !status.settled) return;
    if (!identical(_active[claim.handle.sessionId], claim) ||
        status.handle.captureId != claim.handle.captureId ||
        status.handle.sessionId != claim.handle.sessionId ||
        status.handle.bundlePath != claim.handle.bundlePath) {
      throw StateError('Recording ownership mismatch');
    }
    claim.entry = claim.entry.copyWith(
      duration: Duration(microseconds: status.committed.durationMicros),
      state: status.settled
          ? (status.phase == SampledCapturePhase.finished
                ? 'finished'
                : 'interrupted')
          : status.phase == SampledCapturePhase.failed
          ? 'unknown'
          : status.phase.name,
      error: status.error,
    );
    await _write(await ensureRecordingDirectory(), claim.entry);
    claim.settled = status.settled;
  }

  /// Only for a reservation that never crossed the native start boundary.
  Future<void> abandonUndispatched(SampledRecordingClaim claim) async {
    if (claim.dispatched) {
      throw StateError('Cannot abandon native capture ownership');
    }
    final root = await ensureRecordingDirectory();
    await File('${root.path}/entries/${claim.entry.id}.json').delete();
    _active.remove(claim.handle.sessionId);
    await claim._lease.close();
  }

  Future<String> finish(
    SampledRecordingClaim claim,
    SampledRecordingCaptureClient client, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    final existing = claim.finishing;
    if (existing != null) return existing;
    final future = _finish(claim, client, timeout);
    claim.finishing = future;
    return future.whenComplete(() {
      if (identical(claim.finishing, future)) claim.finishing = null;
    });
  }

  Future<String> _finish(
    SampledRecordingClaim claim,
    SampledRecordingCaptureClient client,
    Duration timeout,
  ) async {
    if (!claim.dispatched) throw StateError('Capture has not started');
    final requested = client.stop(claim.handle);
    await update(claim, requested);
    final status = requested.settled
        ? requested
        : await client.waitUntilSettled(claim.handle, timeout: timeout);
    await update(claim, status);
    // Final metadata is durable before registry ownership and the file claim end.
    try {
      client.release(claim.handle);
    } on SampledCaptureRequestException {
      // Settlement was already verified and persisted. A registry cleanup
      // failure does not make the native writer own the files again.
    } finally {
      if (identical(_active[claim.handle.sessionId], claim)) {
        _active.remove(claim.handle.sessionId);
      }
      await claim._lease.close();
    }
    return claim.entry.path;
  }

  Future<List<SampledRecordingEntry>> listRecordings() async =>
      _list(await ensureRecordingDirectory());

  Future<List<SampledRecordingEntry>> _list(Directory root) async {
    final entries = <SampledRecordingEntry>[];
    await for (final file in Directory(
      '${root.path}/entries',
    ).list(followLinks: false)) {
      if (file is! File ||
          !RegExp(r'/[0-9a-f]{32}\.json$').hasMatch(file.path)) {
        continue;
      }
      if (entries.length >= 1000) {
        throw StateError('Recording library exceeds entry limit');
      }
      try {
        entries.add(await _read(root, file));
      } on Object catch (error) {
        // Keep a visible, protected placeholder. Never rewrite an unknown schema
        // or a corrupt manifest merely to let other recordings recover.
        final id = file.uri.pathSegments.last.split('.').first;
        entries.add(
          SampledRecordingEntry(
            id: id,
            path: '${root.path}/$id.trailrec',
            displayName: id,
            createdAtUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            duration: Duration.zero,
            state: 'unavailable',
            sessionId: null,
            keep: true,
            error: 'Cannot read recording metadata: $error',
          ),
        );
      }
    }
    entries.sort((a, b) => b.createdAtUtc.compareTo(a.createdAtUtc));
    return List<SampledRecordingEntry>.unmodifiable(entries);
  }

  Future<SampledOpenedRecording> openRecording(
    String path, {
    RecordingFileCancellation? cancellation,
  }) async {
    final root = await ensureRecordingDirectory();
    final id = _ownedId(root, path);
    final lease = await _Lease.acquire('${root.path}/claims/$id.lock');
    try {
      var entry = await _read(root, File('${root.path}/entries/$id.json'));
      final file = await SampledRecordingFile.open(
        path,
        api: files,
        cancellation: cancellation,
      );
      if (file.info.id != id) {
        throw const FormatException('Recording manifest identity mismatch');
      }
      entry = _fromInfo(file.info, entry);
      await _write(root, entry);
      return SampledOpenedRecording._(entry, file, lease);
    } on Object {
      await lease.close();
      rethrow;
    }
  }

  Future<SampledRecordingRecovery> recover() => _withLibraryLock((root) async {
    var recovered = 0;
    var busy = 0;
    final errors = <String>[];
    final ids = <String>{};
    for (final entry in await _list(root)) {
      if (entry.isActive) ids.add(entry.id);
      if (entry.state == 'unavailable' && entry.error != null) {
        errors.add('${entry.id}: ${entry.error}');
      }
    }
    // A bundle can outlive a lost manifest publication. Discover only new-format
    // bundle names in this library, never legacy files or directories elsewhere.
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory &&
          RegExp(r'/[0-9a-f]{32}\.trailrec$').hasMatch(entity.path)) {
        final id = entity.path.split('/').last.split('.').first;
        if (!await File('${root.path}/entries/$id.json').exists()) ids.add(id);
      }
    }
    for (final id in ids) {
      _Lease? lease;
      try {
        lease = await _Lease.acquire('${root.path}/claims/$id.lock');
        final path = '${root.path}/$id.trailrec';
        final manifest = File('${root.path}/entries/$id.json');
        final prior = await manifest.exists()
            ? await _read(root, manifest)
            : null;
        if (!await Directory(path).exists()) {
          if (prior != null) {
            await _write(
              root,
              prior.copyWith(
                state: 'unavailable',
                error: 'Capture ended before a readable bundle was created',
              ),
            );
          }
          continue;
        }
        final recording = await SampledRecordingFile.open(path, api: files);
        if (recording.info.id != id) {
          throw const FormatException('Recovered recording identity mismatch');
        }
        await _write(root, _fromInfo(recording.info, prior));
        recovered++;
      } on RecordingLibraryBusy {
        busy++;
      } on Object catch (error) {
        errors.add('$id: $error');
      } finally {
        await lease?.close();
      }
    }
    return SampledRecordingRecovery(
      recovered,
      busy,
      List<String>.unmodifiable(errors),
    );
  });

  Future<void> setKeep(String path, bool keep) => _withLibraryLock((
    root,
  ) async {
    final id = _ownedId(root, path);
    final lease = await _Lease.acquire('${root.path}/claims/$id.lock');
    try {
      final entry = await _read(root, File('${root.path}/entries/$id.json'));
      await _write(root, entry.copyWith(keep: keep, error: entry.error));
    } finally {
      await lease.close();
    }
  });
  Future<void> deleteRecording(String path) => _withLibraryLock((root) async {
    final id = _ownedId(root, path);
    final lease = await _Lease.acquire('${root.path}/claims/$id.lock');
    try {
      final entry = await _read(root, File('${root.path}/entries/$id.json'));
      if (entry.isActive) throw RecordingLibraryBusy(path);
      await _delete(root, entry);
    } finally {
      await lease.close();
    }
  });
  Future<void> applyRetention() => _withLibraryLock(_retain);
  Future<void> _retain(Directory root) async {
    var total = await _libraryBytes(root);
    final cutoff = DateTime.now().toUtc().subtract(maximumAge);
    final entries = (await _list(root)).reversed;
    for (final entry in entries) {
      if (entry.keep || entry.isActive || !entry.isReadable) continue;
      if (!entry.createdAtUtc.isBefore(cutoff) && total < maximumBytes) {
        continue;
      }
      _Lease? lease;
      try {
        lease = await _Lease.acquire('${root.path}/claims/${entry.id}.lock');
        // Re-read after locking: another owner may have set Keep or opened it.
        final fresh = await _read(
          root,
          File('${root.path}/entries/${entry.id}.json'),
        );
        if (fresh.keep || fresh.isActive || !fresh.isReadable) continue;
        final bytes = await _treeBytes(Directory(fresh.path));
        await _delete(root, fresh);
        total -= bytes;
      } on RecordingLibraryBusy {
        continue;
      } finally {
        await lease?.close();
      }
    }
  }

  Future<int> _libraryBytes(Directory root) async {
    var bytes = 0;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory &&
          RegExp(r'/[0-9a-f]{32}\.trailrec$').hasMatch(entity.path)) {
        bytes += await _treeBytes(entity);
      }
    }
    return bytes;
  }

  Future<int> _treeBytes(Directory root) async {
    if (!await root.exists()) return 0;
    var bytes = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) bytes += (await entity.stat()).size;
    }
    return bytes;
  }

  Future<void> _delete(Directory root, SampledRecordingEntry entry) async {
    final directory = Directory(entry.path);
    if (await directory.exists()) {
      // Verify the native header before deleting; a swapped/foreign file is not
      // eligible merely because an old manifest once referred to this name.
      final result = await files.run('metadata', <String, Object?>{
        'bundle_path': entry.path,
        'recording_id': entry.id,
      });
      if (result['metadata'] is! Map ||
          (result['metadata']! as Map)['recording_id'] != entry.id) {
        throw const FormatException(
          'Recording identity changed before deletion',
        );
      }
      await directory.delete(recursive: true);
    }
    final manifest = File('${root.path}/entries/${entry.id}.json');
    if (await manifest.exists()) await manifest.delete();
    // Lock files are permanent: unlinking them could split lock authority.
  }

  String _ownedId(Directory root, String path) {
    final prefix = '${root.path}/';
    if (!path.startsWith(prefix)) {
      throw ArgumentError('Recording is outside the managed library');
    }
    final name = path.substring(prefix.length);
    if (!RegExp(r'^[0-9a-f]{32}\.trailrec$').hasMatch(name)) {
      throw ArgumentError('Expected a managed new-format recording');
    }
    return name.substring(0, 32);
  }

  SampledRecordingEntry _fromInfo(
    SampledRecordingInfo info,
    SampledRecordingEntry? prior,
  ) => SampledRecordingEntry(
    id: info.id,
    path: info.path,
    displayName: info.title,
    createdAtUtc: info.startedAtUtc,
    duration: info.duration,
    state: switch (info.completion) {
      SampledRecordingCompletion.finished => 'finished',
      SampledRecordingCompletion.interrupted => 'interrupted',
      SampledRecordingCompletion.damagedTail => 'damaged_tail',
    },
    sessionId: prior?.sessionId,
    keep: prior?.keep ?? true,
    hostname: info.hostname,
    error: info.error ?? prior?.error,
  );
  Future<SampledRecordingEntry> _read(Directory root, File file) async {
    if ((await file.length()) > 64 * 1024) {
      throw const FormatException('Recording manifest exceeds size limit');
    }
    final raw = jsonDecode(await file.readAsString());
    const fields = <String>{
      'schema_version',
      'id',
      'display_name',
      'created_at_millis',
      'duration_micros',
      'state',
      'session_id',
      'keep',
      'hostname',
      'error',
    };
    bool boundedText(Object? value, int maximum, {bool optional = false}) =>
        (optional && value == null) ||
        (value is String && utf8.encode(value).length <= maximum);
    if (raw is! Map<String, dynamic> ||
        raw.length != fields.length ||
        raw.keys.any((key) => !fields.contains(key)) ||
        raw['schema_version'] is! int ||
        raw['schema_version'] != 2 ||
        raw['id'] is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(raw['id'] as String) ||
        file.path != '${root.path}/entries/${raw['id']}.json' ||
        !boundedText(raw['display_name'], 8192) ||
        raw['created_at_millis'] is! int ||
        (raw['created_at_millis'] as int) < 0 ||
        (raw['created_at_millis'] as int) > 8640000000000000 ||
        raw['duration_micros'] is! int ||
        (raw['duration_micros'] as int) < 0 ||
        !const <String>{
          'reserved',
          'starting',
          'capturing',
          'stopping',
          'unknown',
          'finished',
          'interrupted',
          'damaged_tail',
          'unavailable',
        }.contains(raw['state']) ||
        !(raw['session_id'] == null ||
            (raw['session_id'] is String &&
                RegExp(
                  r'^[1-9][0-9]{0,19}$',
                ).hasMatch(raw['session_id'] as String))) ||
        raw['keep'] is! bool ||
        !boundedText(raw['hostname'], 8192, optional: true) ||
        !boundedText(raw['error'], 8192, optional: true)) {
      throw const FormatException('Invalid or unsupported recording manifest');
    }
    return SampledRecordingEntry(
      id: raw['id'] as String,
      path: '${root.path}/${raw['id']}.trailrec',
      displayName: raw['display_name'] as String,
      createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
        raw['created_at_millis'] as int,
        isUtc: true,
      ),
      duration: Duration(microseconds: raw['duration_micros'] as int),
      state: raw['state'] as String,
      sessionId: raw['session_id'] as String?,
      keep: raw['keep'] as bool,
      hostname: raw['hostname'] as String?,
      error: raw['error'] as String?,
    );
  }

  Future<void> _write(Directory root, SampledRecordingEntry entry) async {
    final destination = File('${root.path}/entries/${entry.id}.json');
    final temporary = File(
      '${destination.path}.${Random.secure().nextInt(1 << 32)}.tmp',
    );
    try {
      await temporary.writeAsString(jsonEncode(entry.toJson()), flush: true);
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

final class _Lease {
  _Lease(this.path, this.file, this.owner);
  final String path;
  final RandomAccessFile file;
  final Object owner;
  bool _closed = false;
  static Future<_Lease> acquire(String path) async {
    if (_processClaims.containsKey(path)) throw RecordingLibraryBusy(path);
    final owner = Object();
    _processClaims[path] = owner;
    RandomAccessFile? file;
    try {
      file = await File(path).open(mode: FileMode.append);
      await file.lock(FileLock.exclusive);
      return _Lease(path, file, owner);
    } on Object catch (error) {
      await file?.close();
      if (identical(_processClaims[path], owner)) _processClaims.remove(path);
      // EAGAIN/EACCES on Unix and lock-violation on Windows indicate contention.
      // Preserve other filesystem failures so the UI can explain them.
      if (error is FileSystemException &&
          const <int>{11, 13, 33, 35}.contains(error.osError?.errorCode)) {
        throw RecordingLibraryBusy(path);
      }
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await file.unlock();
    } finally {
      await file.close();
      if (identical(_processClaims[path], owner)) _processClaims.remove(path);
    }
  }
}
