import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:file_selector/file_selector.dart';

typedef SftpDownloadToPath = Future<void> Function(String localPath);
typedef SftpUploadFromPath = Future<void> Function(String localPath);

enum SftpFileActionEventKind { downloaded, editOpened, uploaded, failed }

final class SftpRemotePathBusyEvent {
  const SftpRemotePathBusyEvent({
    required this.sessionId,
    required this.remotePath,
    required this.isBusy,
  });

  final String sessionId;
  final String remotePath;
  final bool isBusy;
}

final class SftpFileActionEvent {
  const SftpFileActionEvent({
    required this.sessionId,
    required this.remotePath,
    required this.kind,
    required this.message,
  });

  final String sessionId;
  final String remotePath;
  final SftpFileActionEventKind kind;
  final String message;
}

abstract interface class SftpFileActionPlatform {
  Future<String?> chooseSaveLocation(String suggestedName);

  Future<Directory> createEditDirectory();

  Future<void> openFile(String path);

  Stream<FileSystemEvent> watchDirectory(String path);
}

final class IoSftpFileActionPlatform implements SftpFileActionPlatform {
  const IoSftpFileActionPlatform();

  @override
  Future<String?> chooseSaveLocation(String suggestedName) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      canCreateDirectories: true,
    );
    return location?.path;
  }

  @override
  Future<Directory> createEditDirectory() {
    return Directory.systemTemp.createTemp('ianvs-sftp-edit-');
  }

  @override
  Future<void> openFile(String path) async {
    final (executable, arguments) = switch (Platform.operatingSystem) {
      'macos' => ('open', <String>[path]),
      'linux' => ('xdg-open', <String>[path]),
      'windows' => (null, const <String>[]),
      _ => throw UnsupportedError(
        'Opening the default editor is unsupported on this platform.',
      ),
    };
    if (Platform.isWindows) {
      _openFileWithWindowsShell(path);
      return;
    }
    await Process.start(
      executable!,
      arguments,
      mode: ProcessStartMode.detached,
    );
  }

  @override
  Stream<FileSystemEvent> watchDirectory(String path) {
    return Directory(path).watch(
      events:
          FileSystemEvent.create |
          FileSystemEvent.modify |
          FileSystemEvent.move |
          FileSystemEvent.delete,
    );
  }
}

/// Coordinates user-owned downloads and long-lived "Edit locally" sessions.
///
/// Edit sessions intentionally outlive the SFTP side panel. Closing the panel
/// must not stop a later editor save from being uploaded to the original path.
final class SftpFileActions {
  SftpFileActions({
    SftpFileActionPlatform platform = const IoSftpFileActionPlatform(),
    Duration settleDelay = const Duration(milliseconds: 350),
  }) : _platform = platform,
       _settleDelay = settleDelay;

  final SftpFileActionPlatform _platform;
  final Duration _settleDelay;
  final Map<String, _SftpEditSession> _editSessions =
      <String, _SftpEditSession>{};
  final Map<String, Future<void>> _operationTails = <String, Future<void>>{};
  final Map<String, SftpFileActionEvent> _unresolvedFailures =
      <String, SftpFileActionEvent>{};
  final StreamController<SftpFileActionEvent> _events =
      StreamController<SftpFileActionEvent>.broadcast(sync: true);
  final StreamController<SftpRemotePathBusyEvent> _busyEvents =
      StreamController<SftpRemotePathBusyEvent>.broadcast(sync: true);
  bool _disposed = false;

  Stream<SftpFileActionEvent> get events => _events.stream;

  Stream<SftpRemotePathBusyEvent> get busyEvents => _busyEvents.stream;

  bool isRemotePathBusy(String sessionId, String remotePath) {
    return _operationTails.containsKey(_editKey(sessionId, remotePath));
  }

  Iterable<SftpFileActionEvent> unresolvedFailuresForSession(
    String sessionId,
  ) sync* {
    for (final event in _unresolvedFailures.values) {
      if (event.sessionId == sessionId) {
        yield event;
      }
    }
  }

  Future<T> runRemoteOperation<T>({
    required String sessionId,
    required String remotePath,
    required Future<T> Function() operation,
  }) async {
    if (_disposed) {
      throw StateError('SFTP file actions have been disposed.');
    }
    final key = _editKey(sessionId, remotePath);
    final previous = _operationTails[key];
    final completion = Completer<void>();
    _operationTails[key] = completion.future;
    if (previous == null) {
      _busyEvents.add(
        SftpRemotePathBusyEvent(
          sessionId: sessionId,
          remotePath: remotePath,
          isBusy: true,
        ),
      );
    } else {
      await previous.catchError((Object _) {});
    }
    try {
      return await operation();
    } finally {
      completion.complete();
      if (identical(_operationTails[key], completion.future)) {
        unawaited(_operationTails.remove(key));
        if (!_disposed) {
          _busyEvents.add(
            SftpRemotePathBusyEvent(
              sessionId: sessionId,
              remotePath: remotePath,
              isBusy: false,
            ),
          );
        }
      }
    }
  }

  Future<String?> downloadAs({
    required String sessionId,
    required String remotePath,
    required String suggestedName,
    required SftpDownloadToPath download,
  }) async {
    try {
      final destination = await _platform.chooseSaveLocation(suggestedName);
      if (destination == null) {
        return null;
      }
      await runRemoteOperation(
        sessionId: sessionId,
        remotePath: remotePath,
        operation: () => download(destination),
      );
      _emit(
        SftpFileActionEvent(
          sessionId: sessionId,
          remotePath: remotePath,
          kind: SftpFileActionEventKind.downloaded,
          message: 'Downloaded $suggestedName',
        ),
      );
      return destination;
    } on Object {
      _emit(
        SftpFileActionEvent(
          sessionId: sessionId,
          remotePath: remotePath,
          kind: SftpFileActionEventKind.failed,
          message: 'Could not download $suggestedName.',
        ),
      );
      rethrow;
    }
  }

  Future<String> editLocally({
    required String sessionId,
    required String remotePath,
    required String fileName,
    required SftpDownloadToPath download,
    required SftpUploadFromPath upload,
  }) async {
    final key = _editKey(sessionId, remotePath);
    final existing = _editSessions[key];
    if (existing != null) {
      try {
        await _platform.openFile(existing.localPath);
        return existing.localPath;
      } on Object {
        _emit(
          SftpFileActionEvent(
            sessionId: sessionId,
            remotePath: remotePath,
            kind: SftpFileActionEventKind.failed,
            message: 'Could not reopen $fileName in the default editor.',
          ),
        );
        rethrow;
      }
    }

    Directory? directory;
    _SftpEditSession? editSession;
    try {
      directory = await _platform.createEditDirectory();
      final safeFileName = _safeLocalEditFileName(fileName);
      final localPath =
          '${directory.path}${Platform.pathSeparator}$safeFileName';
      await runRemoteOperation(
        sessionId: sessionId,
        remotePath: remotePath,
        operation: () => download(localPath),
      );
      final initialSignature = await _fileSignature(File(localPath));
      if (initialSignature == null) {
        throw FileSystemException(
          'The downloaded edit is not a readable file.',
          localPath,
        );
      }
      final newSession = _SftpEditSession(
        key: key,
        sessionId: sessionId,
        remotePath: remotePath,
        fileName: fileName,
        directory: directory,
        localPath: localPath,
        upload: upload,
        lastSyncedSignature: initialSignature,
      );
      editSession = newSession;
      _attachEditWatcher(newSession);
      _editSessions[key] = newSession;
      await _platform.openFile(localPath);
      _emit(
        SftpFileActionEvent(
          sessionId: sessionId,
          remotePath: remotePath,
          kind: SftpFileActionEventKind.editOpened,
          message: 'Editing $fileName locally',
        ),
      );
      return localPath;
    } on Object {
      if (identical(_editSessions[key], editSession)) {
        _editSessions.remove(key);
      }
      editSession?.settleTimer?.cancel();
      editSession?.watchRestartTimer?.cancel();
      await editSession?.subscription?.cancel();
      if (directory != null) {
        await directory
            .delete(recursive: true)
            .catchError((Object _) => directory!);
      }
      _emit(
        SftpFileActionEvent(
          sessionId: sessionId,
          remotePath: remotePath,
          kind: SftpFileActionEventKind.failed,
          message: 'Could not open $fileName for local editing.',
        ),
      );
      rethrow;
    }
  }

  void _onEditFileEvent(_SftpEditSession editSession, FileSystemEvent event) {
    if (!_eventTouchesPath(event, editSession.localPath)) {
      return;
    }
    editSession.dirtyGeneration += 1;
    editSession.pendingUpload = true;
    editSession.hasUnsyncedChanges = true;
    editSession.uploadFailures = 0;
    editSession.watchRestartAttempts = 0;
    editSession.settleTimer?.cancel();
    editSession.settleTimer = Timer(_settleDelay, () {
      unawaited(_flushEditSession(editSession));
    });
  }

  Future<void> _flushEditSession(_SftpEditSession editSession) async {
    if (_disposed || editSession.uploading) {
      return;
    }
    editSession.uploading = true;
    try {
      while (editSession.pendingUpload && !_disposed) {
        editSession.pendingUpload = false;
        final generation = editSession.dirtyGeneration;
        final signature = await _waitForStableFile(editSession.localPath);
        if (signature != null &&
            editSession.dirtyGeneration == generation &&
            signature == editSession.lastSyncedSignature) {
          editSession.uploadFailures = 0;
          editSession.hasUnsyncedChanges = false;
          _unresolvedFailures.remove(editSession.key);
          continue;
        }
        final snapshot = signature == null
            ? null
            : await _createStableUploadSnapshot(
                editSession,
                generation,
                signature,
              );
        if (snapshot == null) {
          if (editSession.dirtyGeneration != generation) {
            editSession.pendingUpload = true;
            continue;
          }
          await _retryOrRecordFailure(editSession);
          continue;
        }
        try {
          await runRemoteOperation(
            sessionId: editSession.sessionId,
            remotePath: editSession.remotePath,
            operation: () => editSession.upload(snapshot.path),
          );
          editSession.uploadFailures = 0;
          editSession.lastSyncedSignature = signature!;
          if (editSession.dirtyGeneration == generation) {
            editSession.hasUnsyncedChanges = false;
            _unresolvedFailures.remove(editSession.key);
          } else {
            editSession.pendingUpload = true;
          }
          _emit(
            SftpFileActionEvent(
              sessionId: editSession.sessionId,
              remotePath: editSession.remotePath,
              kind: SftpFileActionEventKind.uploaded,
              message: 'Uploaded changes to ${editSession.fileName}',
            ),
          );
        } on Object {
          await _retryOrRecordFailure(editSession);
        } finally {
          await snapshot.delete().catchError((Object _) => snapshot);
        }
      }
    } finally {
      editSession.uploading = false;
      if (editSession.pendingUpload && !_disposed) {
        editSession.settleTimer?.cancel();
        editSession.settleTimer = Timer(_settleDelay, () {
          unawaited(_flushEditSession(editSession));
        });
      }
    }
  }

  Future<File?> _createStableUploadSnapshot(
    _SftpEditSession editSession,
    int generation,
    _SftpFileSignature signature,
  ) async {
    if (editSession.dirtyGeneration != generation) {
      return null;
    }
    final snapshot = File(
      '${editSession.directory.path}${Platform.pathSeparator}'
      '.ianvs-upload-$generation',
    );
    try {
      await File(editSession.localPath).copy(snapshot.path);
      final sourceAfter = await _fileSignature(File(editSession.localPath));
      final snapshotSignature = await _fileSignature(snapshot);
      if (sourceAfter != signature ||
          snapshotSignature?.size != signature.size ||
          editSession.dirtyGeneration != generation) {
        await snapshot.delete().catchError((Object _) => snapshot);
        return null;
      }
      return snapshot;
    } on FileSystemException {
      await snapshot.delete().catchError((Object _) => snapshot);
      return null;
    }
  }

  void _attachEditWatcher(
    _SftpEditSession editSession, {
    bool recovering = false,
  }) {
    if (_disposed) {
      return;
    }
    try {
      editSession.subscription = _platform
          .watchDirectory(editSession.directory.path)
          .listen(
            (event) => _onEditFileEvent(editSession, event),
            onError: (Object _) => _handleEditWatcherFailure(editSession),
            onDone: () => _handleEditWatcherFailure(editSession),
          );
      editSession.watchRestartScheduled = false;
      if (recovering) {
        editSession.dirtyGeneration += 1;
        editSession.pendingUpload = true;
        editSession.hasUnsyncedChanges = true;
        editSession.settleTimer?.cancel();
        editSession.settleTimer = Timer(_settleDelay, () {
          unawaited(_flushEditSession(editSession));
        });
      }
    } on Object {
      _handleEditWatcherFailure(editSession);
    }
  }

  void _handleEditWatcherFailure(_SftpEditSession editSession) {
    if (_disposed || editSession.watchRestartScheduled) {
      return;
    }
    editSession.hasUnsyncedChanges = true;
    _emitEditFailure(editSession);
    if (editSession.watchRestartAttempts >= 4) {
      return;
    }
    editSession.watchRestartAttempts += 1;
    editSession.watchRestartScheduled = true;
    editSession.watchRestartTimer?.cancel();
    editSession.watchRestartTimer = Timer(
      Duration(seconds: editSession.watchRestartAttempts),
      () async {
        await editSession.subscription?.cancel();
        editSession.subscription = null;
        editSession.watchRestartScheduled = false;
        _attachEditWatcher(editSession, recovering: true);
      },
    );
  }

  Future<void> _retryOrRecordFailure(_SftpEditSession editSession) async {
    editSession.uploadFailures += 1;
    if (editSession.uploadFailures <= 4 && !_disposed) {
      editSession.pendingUpload = true;
      await Future<void>.delayed(
        Duration(
          milliseconds:
              _settleDelay.inMilliseconds * editSession.uploadFailures,
        ),
      );
      return;
    }
    _emitEditFailure(editSession);
  }

  Future<_SftpFileSignature?> _waitForStableFile(String path) async {
    for (var attempt = 0; attempt < 8; attempt += 1) {
      final before = await _fileSignature(File(path));
      if (before == null) {
        await Future<void>.delayed(_settleDelay);
        continue;
      }
      await Future<void>.delayed(_settleDelay);
      final after = await _fileSignature(File(path));
      if (before == after) {
        return after;
      }
    }
    return null;
  }

  void _emitEditFailure(_SftpEditSession editSession) {
    final event = SftpFileActionEvent(
      sessionId: editSession.sessionId,
      remotePath: editSession.remotePath,
      kind: SftpFileActionEventKind.failed,
      message:
          'Could not upload changes to ${editSession.fileName}. '
          'The local copy is kept at ${editSession.localPath}.',
    );
    _unresolvedFailures[editSession.key] = event;
    _emit(event);
  }

  void _emit(SftpFileActionEvent event) {
    if (!_disposed) {
      _events.add(event);
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final editSession in _editSessions.values) {
      editSession.settleTimer?.cancel();
      editSession.watchRestartTimer?.cancel();
      unawaited(editSession.subscription?.cancel());
      // A filesystem notification can lag behind the editor's final write.
      // Keep active edit directories on shutdown so dispose can never erase a
      // save that has not yet advanced hasUnsyncedChanges.
    }
    _editSessions.clear();
    unawaited(_events.close());
    unawaited(_busyEvents.close());
  }
}

final class _SftpEditSession {
  _SftpEditSession({
    required this.key,
    required this.sessionId,
    required this.remotePath,
    required this.fileName,
    required this.directory,
    required this.localPath,
    required this.upload,
    required this.lastSyncedSignature,
  });

  final String key;
  final String sessionId;
  final String remotePath;
  final String fileName;
  final Directory directory;
  final String localPath;
  final SftpUploadFromPath upload;
  _SftpFileSignature lastSyncedSignature;
  // Cancelled by SftpFileActions.dispose after sessions outlive panel widgets.
  // ignore: cancel_subscriptions
  StreamSubscription<FileSystemEvent>? subscription;
  Timer? settleTimer;
  Timer? watchRestartTimer;
  bool pendingUpload = false;
  bool uploading = false;
  bool hasUnsyncedChanges = false;
  int uploadFailures = 0;
  int dirtyGeneration = 0;
  int watchRestartAttempts = 0;
  bool watchRestartScheduled = false;
}

final class _SftpFileSignature {
  const _SftpFileSignature(this.size, this.modifiedMicros);

  final int size;
  final int modifiedMicros;

  @override
  bool operator ==(Object other) {
    return other is _SftpFileSignature &&
        other.size == size &&
        other.modifiedMicros == modifiedMicros;
  }

  @override
  int get hashCode => Object.hash(size, modifiedMicros);
}

Future<_SftpFileSignature?> _fileSignature(File file) async {
  try {
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      return null;
    }
    return _SftpFileSignature(stat.size, stat.modified.microsecondsSinceEpoch);
  } on FileSystemException {
    return null;
  }
}

bool _eventTouchesPath(FileSystemEvent event, String localPath) {
  if (event.path == localPath) {
    return true;
  }
  return event is FileSystemMoveEvent && event.destination == localPath;
}

String _editKey(String sessionId, String remotePath) =>
    '$sessionId\u0000$remotePath';

String _safeLocalEditFileName(String remoteName) {
  final sanitized = StringBuffer();
  const forbidden = r'<>:"/\|?*&^%!';
  for (final rune in remoteName.runes) {
    final character = String.fromCharCode(rune);
    sanitized.write(
      rune < 32 || forbidden.contains(character) ? '_' : character,
    );
  }
  var name = sanitized.toString().replaceFirst(RegExp(r'[. ]+$'), '');
  if (name.isEmpty || name == '.' || name == '..') {
    name = 'remote-file';
  }
  final stem = name.split('.').first.toUpperCase();
  if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem)) {
    name = '_$name';
  }
  return name;
}

void _openFileWithWindowsShell(String path) {
  final shellExecute = DynamicLibrary.open('shell32.dll')
      .lookupFunction<
        IntPtr Function(
          Pointer<Void>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Int32,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          int,
        )
      >('ShellExecuteW');
  final operation = 'open'.toNativeUtf16();
  final file = path.toNativeUtf16();
  try {
    final result = shellExecute(nullptr, operation, file, nullptr, nullptr, 1);
    if (result <= 32) {
      throw ProcessException(
        'ShellExecuteW',
        <String>[path],
        'Windows could not open the local edit (code $result).',
        result,
      );
    }
  } finally {
    calloc
      ..free(operation)
      ..free(file);
  }
}
