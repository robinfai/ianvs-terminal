import 'dart:async';
import 'dart:typed_data';

import 'package:ianvs_terminal_core/src/pty/ianvs_pty.dart';

import '../terminal/terminal_graphics_cache.dart';
import '../terminal/terminal_models.dart';
import '../transport/terminal_protobuf_frame_codec.dart';

export 'package:ianvs_terminal_core/src/pty/ianvs_pty.dart'
    show
        NativeRecordingFileApi,
        RecordingFileApi,
        RecordingFileCancellation,
        RecordingFileCancelled;

enum SampledRecordingCompletion { finished, interrupted, damagedTail }

final class SampledRecordingInfo {
  SampledRecordingInfo._(this.path, Map<String, Object?> result)
    : id = _string(_map(result['metadata']), 'recording_id'),
      title = _string(_map(result['metadata']), 'title'),
      hostname = _optionalString(_map(result['metadata']), 'hostname'),
      startedAtUtc = DateTime.fromMillisecondsSinceEpoch(
        _number(_map(result['metadata']), 'started_at_unix_millis'),
        isUtc: true,
      ),
      duration = Duration(
        microseconds: _number(_map(result['summary']), 'duration_micros'),
      ),
      visualCount = _number(_map(result['summary']), 'visual_count'),
      semanticCount = _number(_map(result['summary']), 'semantic_count'),
      sourceBytes = _number(result, 'source_bytes'),
      verifiedBytes = _number(result, 'verified_bytes'),
      error = _optionalString(result, 'error'),
      completion = switch (result['completion']) {
        'finished' => SampledRecordingCompletion.finished,
        'interrupted' => SampledRecordingCompletion.interrupted,
        'damaged_tail' => SampledRecordingCompletion.damagedTail,
        _ => throw const FormatException(
          'Invalid sampled recording completion',
        ),
      } {
    if (verifiedBytes > sourceBytes ||
        _number(_map(result['summary']), 'record_count') !=
            visualCount + semanticCount) {
      throw const FormatException('Invalid sampled recording summary');
    }
  }
  final String path;
  final String id;
  final String title;
  final String? hostname;
  final DateTime startedAtUtc;
  final Duration duration;
  final int visualCount;
  final int semanticCount;
  final int sourceBytes;
  final int verifiedBytes;
  final SampledRecordingCompletion completion;
  final String? error;
}

final class SampledRecordingAsset {
  SampledRecordingAsset._(Map<String, Object?> value)
    : key = TerminalGraphicAssetKey(
        id: _number(value, 'asset_id'),
        version: _number(value, 'asset_version'),
      ),
      width = _number(value, 'width'),
      height = _number(value, 'height'),
      digest = List<int>.unmodifiable((value['digest']! as List).cast<int>()) {
    if (width == 0 ||
        height == 0 ||
        width * height * 4 > 32 * 1024 * 1024 ||
        digest.length != 32 ||
        digest.any((b) => b < 0 || b > 255)) {
      throw const FormatException('Invalid recording asset binding');
    }
  }
  final TerminalGraphicAssetKey key;
  final int width;
  final int height;
  final List<int> digest;
  Map<String, Object?> toJson() => <String, Object?>{
    'asset_id': key.id,
    'asset_version': key.version,
    'width': width,
    'height': height,
    'digest': digest,
  };
}

final class SampledRecordingFrame {
  SampledRecordingFrame._(Map<String, Object?> value)
    : offset = Duration(microseconds: _number(value, 'offset_micros')),
      sequence = _number(value, 'sequence'),
      frame = const TerminalProtobufFrameCodec().decode(
        value['frame_bytes']! as Uint8List,
      ),
      assets = List<SampledRecordingAsset>.unmodifiable(
        (value['assets']! as List).map(
          (value) => SampledRecordingAsset._(_map(value)),
        ),
      ) {
    if (frame.frameKind != TerminalFrameKind.snapshot ||
        assets.length > 256 ||
        assets.fold<int>(
              0,
              (sum, asset) => sum + asset.width * asset.height * 4,
            ) >
            32 * 1024 * 1024 ||
        assets.map((a) => a.key).toSet().length != assets.length ||
        frame.graphics.any((g) => !assets.any((a) => a.key == g.assetKey))) {
      throw const FormatException('Incomplete sampled recording screen');
    }
  }
  final Duration offset;
  final int sequence;
  final TerminalFrameDiff frame;
  final List<SampledRecordingAsset> assets;
}

enum SampledTimelineKind {
  commandStarted,
  commandFinished,
  contextChanged,
  hookUnavailable,
  hookAvailable,
}

final class SampledTimelineEvent {
  SampledTimelineEvent._(Map<String, Object?> value)
    : offset = Duration(microseconds: _number(value, 'offset_micros')),
      kind = switch (value['kind']) {
        'command_started' => SampledTimelineKind.commandStarted,
        'command_finished' => SampledTimelineKind.commandFinished,
        'context_changed' => SampledTimelineKind.contextChanged,
        'hook_unavailable' => SampledTimelineKind.hookUnavailable,
        'hook_available' => SampledTimelineKind.hookAvailable,
        _ => throw const FormatException('Invalid recording timeline event'),
      },
      contextId = _string(value, 'context_id'),
      commandId = _optionalString(value, 'command_id'),
      command = _optionalString(value, 'command'),
      cwd = _optionalString(value, 'cwd'),
      hostname = _optionalString(value, 'hostname'),
      exitCode = value['exit_code'] as int?;

  final Duration offset;
  final SampledTimelineKind kind;
  final String contextId;
  final String? commandId;
  final String? command;
  final String? cwd;
  final String? hostname;
  final int? exitCode;
}

final class SampledTimelinePage {
  SampledTimelinePage._(Map<String, Object?> value)
    : events = List<SampledTimelineEvent>.unmodifiable(
        (value['events']! as List).map((e) => SampledTimelineEvent._(_map(e))),
      ),
      nextCursor = value['next_cursor'] == null
          ? null
          : _number(value, 'next_cursor');
  final List<SampledTimelineEvent> events;
  final int? nextCursor;
}

/// Disk-backed immutable recording. Opening returns metadata, not all frames or
/// commands. Each seek returns one complete screen; timeline pages are bounded.
final class SampledRecordingFile {
  SampledRecordingFile._(this.info, this._api);
  final SampledRecordingInfo info;
  final RecordingFileApi _api;
  final Map<RecordingFileCancellation, int> _pending = {};
  Completer<void>? _drained;
  bool _closed = false;
  bool get isClosed => _closed;

  /// Cancels reads and waits for native work to settle before file ownership can
  /// be released to deletion/retention. Cancellation alone is not settlement.
  Future<void> close() async {
    _closed = true;
    for (final cancellation in _pending.keys.toList(growable: false)) {
      cancellation.cancel();
    }
    if (_pending.isNotEmpty) {
      await (_drained ??= Completer<void>()).future;
    }
  }

  Future<Map<String, Object?>> _run(
    String operation,
    Map<String, Object?> payload, {
    RecordingFileCancellation? cancellation,
  }) async {
    if (_closed) throw StateError('Recording file is closed');
    final token = cancellation ?? RecordingFileCancellation();
    _pending.update(token, (count) => count + 1, ifAbsent: () => 1);
    try {
      final result = await _api.run(operation, payload, cancellation: token);
      if (_closed || token.isCancelled) throw const RecordingFileCancelled();
      return result;
    } finally {
      final remaining = _pending[token]! - 1;
      if (remaining == 0) {
        _pending.remove(token);
      } else {
        _pending[token] = remaining;
      }
      if (_pending.isEmpty) {
        _drained?.complete();
        _drained = null;
      }
    }
  }

  static Future<SampledRecordingFile> open(
    String bundlePath, {
    required RecordingFileApi api,
    RecordingFileCancellation? cancellation,
  }) async {
    final value = await api.run('inspect', <String, Object?>{
      'bundle_path': bundlePath,
    }, cancellation: cancellation);
    if (cancellation?.isCancelled == true) throw const RecordingFileCancelled();
    return SampledRecordingFile._(
      SampledRecordingInfo._(bundlePath, value),
      api,
    );
  }

  Map<String, Object?> get _identity => <String, Object?>{
    'bundle_path': info.path,
    'recording_id': info.id,
  };

  Future<SampledRecordingFrame?> seek(
    Duration position, {
    RecordingFileCancellation? cancellation,
  }) async {
    final value = await _run('seek', <String, Object?>{
      ..._identity,
      'offset_micros': position.inMicroseconds.clamp(
        0,
        info.duration.inMicroseconds,
      ),
    }, cancellation: cancellation);
    return value['screen'] == null
        ? null
        : SampledRecordingFrame._(_map(value['screen']));
  }

  Future<SampledTimelinePage> timeline({
    int cursor = 0,
    int limit = 64,
    RecordingFileCancellation? cancellation,
  }) async {
    if (cursor < 0 || limit < 1 || limit > 128) {
      throw ArgumentError('Invalid timeline page');
    }
    final value = await _run('timeline', <String, Object?>{
      ..._identity,
      'cursor': cursor,
      'limit': limit,
    }, cancellation: cancellation);
    final page = SampledTimelinePage._(value);
    if (page.events.length > limit ||
        (page.nextCursor != null && page.nextCursor! <= cursor)) {
      throw const FormatException('Invalid timeline continuation');
    }
    return page;
  }

  Future<TerminalGraphicAsset> loadAsset(
    SampledRecordingAsset binding, {
    RecordingFileCancellation? cancellation,
  }) async {
    final value = await _run('asset', <String, Object?>{
      ..._identity,
      'binding': binding.toJson(),
    }, cancellation: cancellation);
    if (value['asset_id'] != binding.key.id ||
        value['asset_version'] != binding.key.version ||
        value['width'] != binding.width ||
        value['height'] != binding.height ||
        value['rgba_bytes'] is! Uint8List ||
        (value['rgba_bytes']! as Uint8List).length !=
            binding.width * binding.height * 4) {
      throw const FormatException('Recording image identity mismatch');
    }
    return TerminalGraphicAsset(
      key: binding.key,
      width: binding.width,
      height: binding.height,
      rgba: value['rgba_bytes']! as Uint8List,
    );
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Invalid recording object');
  }
  return value;
}

int _number(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is! int || result < 0) {
    throw FormatException('Invalid recording $key');
  }
  return result;
}

String _string(Map<String, Object?> value, String key) {
  final result = value[key];
  if (result is! String) throw FormatException('Invalid recording $key');
  return result;
}

String? _optionalString(Map<String, Object?> value, String key) =>
    value[key] == null ? null : _string(value, key);
