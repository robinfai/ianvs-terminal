import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'native_pty_backend.dart' show resolveNativePtyLibraryPath;

final class RecordingFileCancelled implements Exception {
  const RecordingFileCancelled();
  @override
  String toString() => 'Recording file operation cancelled';
}

final class RecordingFileCancellation {
  bool _cancelled = false;
  final Set<void Function()> _listeners = <void Function()>{};
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList(growable: false)) {
      listener();
    }
    _listeners.clear();
  }

  void _listen(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void _check() {
    if (_cancelled) throw const RecordingFileCancelled();
  }
}

/// Returns bounded recording data. Frame and RGBA payloads are Uint8List values
/// decoded on the worker isolate, under `frame_bytes` and `rgba_bytes`.
abstract interface class RecordingFileApi {
  Future<Map<String, Object?>> run(
    String operation,
    Map<String, Object?> payload, {
    RecordingFileCancellation? cancellation,
  });
}

/// Recording file work never creates a terminal session or forwards host
/// actions. Two workers per instance and a bounded queue prevent seek storms
/// and graphics loading from spawning an unbounded number of isolates.
final class NativeRecordingFileApi implements RecordingFileApi {
  NativeRecordingFileApi({String? libraryPath}) : _libraryPath = libraryPath;

  String? _libraryPath;
  _RecordingFileBindings? _bindings;
  final Queue<_PendingRead> _queue = Queue<_PendingRead>();
  final Map<RecordingFileCancellation, int> _active =
      <RecordingFileCancellation, int>{};
  int _running = 0;
  bool _disposed = false;

  @override
  Future<Map<String, Object?>> run(
    String operation,
    Map<String, Object?> payload, {
    RecordingFileCancellation? cancellation,
  }) {
    if (_disposed) return Future.error(StateError('Recording reader disposed'));
    if (!const <String>{
      'inspect',
      'metadata',
      'seek',
      'timeline',
      'asset',
      'search',
      'sync_directory',
    }.contains(operation)) {
      return Future.error(ArgumentError.value(operation, 'operation'));
    }
    if (_queue.length >= 256) {
      return Future.error(StateError('Recording reader queue is full'));
    }
    // Snapshot JSON before queuing; callers cannot mutate an in-flight request.
    final encoded = jsonEncode(payload);
    if (utf8.encode(encoded).length > 60 * 1024) {
      return Future.error(ArgumentError('Recording file request is too large'));
    }
    final pending = _PendingRead(
      operation,
      encoded,
      cancellation ?? RecordingFileCancellation(),
    );
    _queue.add(pending);
    _pump();
    return pending.completer.future;
  }

  void dispose() {
    _disposed = true;
    for (final pending in _queue) {
      pending.cancellation.cancel();
    }
    for (final cancellation in _active.keys.toList(growable: false)) {
      cancellation.cancel();
    }
    _pump();
  }

  void _pump() {
    while (_running < 2 && _queue.isNotEmpty) {
      final pending = _queue.removeFirst();
      if (pending.cancellation.isCancelled) {
        pending.completer.completeError(const RecordingFileCancelled());
        continue;
      }
      _running++;
      _active.update(
        pending.cancellation,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      unawaited(
        _execute(pending)
            .then<void>(
              pending.completer.complete,
              onError: pending.completer.completeError,
            )
            .whenComplete(() {
              _running--;
              final count = _active[pending.cancellation]! - 1;
              if (count == 0) {
                _active.remove(pending.cancellation);
              } else {
                _active[pending.cancellation] = count;
              }
              _pump();
            }),
      );
    }
  }

  Future<Map<String, Object?>> _execute(_PendingRead pending) async {
    pending.cancellation._check();
    if (_libraryPath == null && !Platform.isIOS) {
      _libraryPath = resolveNativePtyLibraryPath();
    }
    final bindings = _bindings ??= _RecordingFileBindings(_libraryPath);
    final reserved = bindings.call('reserve', null, const <String, Object?>{});
    final jobId = reserved['job_id']! as String;
    void cancelNative() {
      try {
        bindings.call('cancel', jobId, const <String, Object?>{});
      } on Object {
        /* Completion still owns release even if cancel transport fails. */
      }
    }

    pending.cancellation._listen(cancelNative);
    try {
      pending.cancellation._check();
      final request = jsonEncode(<String, Object?>{
        'schema_version': 2,
        'job_id': jobId,
        'operation': pending.operation,
        'payload': jsonDecode(pending.payloadJson),
      });
      final result = await _spawnFileRead((
        _libraryPath,
        request,
        jobId,
        pending.operation,
      ));
      pending.cancellation._check();
      return result;
    } on Object {
      pending.cancellation._check();
      rethrow;
    } finally {
      pending.cancellation._listeners.remove(cancelNative);
      // Worker future completes only after its synchronous native read returns.
      // A UI cancellation never frees a still-running native job.
      bindings.call('release', jobId, const <String, Object?>{});
    }
  }
}

final class _PendingRead {
  _PendingRead(this.operation, this.payloadJson, this.cancellation);
  final String operation;
  final String payloadJson;
  final RecordingFileCancellation cancellation;
  final Completer<Map<String, Object?>> completer =
      Completer<Map<String, Object?>>();
}

typedef _ReadNative = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);
typedef _FreeNative = void Function(ffi.Pointer<Utf8>);

final class _RecordingFileBindings {
  _RecordingFileBindings(String? libraryPath) {
    final library = libraryPath == null
        ? ffi.DynamicLibrary.process()
        : ffi.DynamicLibrary.open(libraryPath);
    _request = library
        .lookupFunction<
          ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>),
          _ReadNative
        >('ianvs_recording_file_request_v2_json');
    _free = library
        .lookupFunction<ffi.Void Function(ffi.Pointer<Utf8>), _FreeNative>(
          'ianvs_string_free',
        );
  }
  late final _ReadNative _request;
  late final _FreeNative _free;

  Map<String, Object?> call(
    String operation,
    String? jobId,
    Map<String, Object?> payload,
  ) => callEncoded(
    jsonEncode(<String, Object?>{
      'schema_version': 2,
      'job_id': jobId,
      'operation': operation,
      'payload': payload,
    }),
    operation,
    jobId,
  );

  Map<String, Object?> callEncoded(
    String request,
    String operation,
    String? jobId,
  ) {
    final pointer = request.toNativeUtf8();
    ffi.Pointer<Utf8> response = ffi.nullptr;
    try {
      response = _request(pointer);
      if (response == ffi.nullptr) {
        throw const FormatException('No recording file response');
      }
      final decoded = jsonDecode(response.toDartString());
      if (decoded is! Map<String, Object?> ||
          decoded['schema_version'] is! int ||
          decoded['schema_version'] != 2 ||
          decoded['operation'] != operation ||
          decoded['ok'] is! bool ||
          (operation != 'reserve' && decoded['job_id'] != jobId)) {
        throw const FormatException(
          'Recording file response identity mismatch',
        );
      }
      if (decoded['ok'] == false) {
        throw FormatException(
          'Recording file operation failed: ${decoded['error']}',
        );
      }
      if (decoded.keys.toSet().difference(const <String>{
            'schema_version',
            'operation',
            'job_id',
            'ok',
            'result',
          }).isNotEmpty ||
          decoded.length != 5 ||
          decoded['result'] is! Map<String, Object?> ||
          decoded['job_id'] is! String ||
          !RegExp(
            r'^[1-9][0-9]{0,19}$',
          ).hasMatch(decoded['job_id']! as String)) {
        throw const FormatException('Invalid recording file result');
      }
      return decoded;
    } finally {
      malloc.free(pointer);
      if (response != ffi.nullptr) _free(response);
    }
  }
}

Future<Map<String, Object?>> _spawnFileRead(
  (String?, String, String, String) request,
) => Isolate.run(() => _readFileOnWorker(request));

Map<String, Object?> _readFileOnWorker(
  (String?, String, String, String) request,
) {
  final (libraryPath, encoded, jobId, operation) = request;
  final result =
      _RecordingFileBindings(
            libraryPath,
          ).callEncoded(encoded, operation, jobId)['result']!
          as Map<String, Object?>;
  void decodeBytes(
    Map<String, Object?> value,
    String source,
    String destination,
    int maxBytes,
  ) {
    final encoded = value.remove(source);
    if (encoded is! String || encoded.length > ((maxBytes + 2) ~/ 3) * 4) {
      throw const FormatException('Invalid recording byte payload');
    }
    final bytes = base64Decode(encoded);
    if (bytes.length > maxBytes) {
      throw const FormatException('Recording byte payload too large');
    }
    value[destination] = bytes;
  }

  if (operation == 'seek' && result['screen'] != null) {
    final screen = result['screen'];
    if (screen is! Map<String, Object?>) {
      throw const FormatException('Invalid recording screen');
    }
    decodeBytes(screen, 'frame_base64', 'frame_bytes', 16 * 1024 * 1024);
  }
  if (operation == 'asset') {
    decodeBytes(result, 'rgba_base64', 'rgba_bytes', 32 * 1024 * 1024);
  }
  return result;
}
