import 'dart:convert';
import 'dart:typed_data';

import '../terminal/terminal.dart' as terminal;
import 'window_bridge.dart';

typedef Osc72SendInput = void Function(String sessionId, Uint8List bytes);
typedef Osc72ConfigureTarget =
    Future<void> Function({
      required bool enabled,
      String? sessionId,
      required List<String> mimeTypes,
    });
typedef Osc72SetDecision = Future<void> Function(int operation);
typedef Osc72ReadDropData =
    Future<NativeOsc72DropChunk> Function({
      required String dropId,
      required String mimeType,
      required int offset,
      required int maxBytes,
    });
typedef Osc72ReleaseDrop = Future<void> Function(String dropId);

class Osc72DropLocation {
  const Osc72DropLocation({
    required this.cellX,
    required this.cellY,
    required this.pixelX,
    required this.pixelY,
  });

  final int cellX;
  final int cellY;
  final int pixelX;
  final int pixelY;
}

class _Osc72Target {
  const _Osc72Target({required this.mimeTypes, this.identifier});

  final List<String> mimeTypes;
  final int? identifier;
}

class _Osc72Drop {
  const _Osc72Drop({
    required this.sessionId,
    required this.dropId,
    required this.mimeTypes,
  });

  final String sessionId;
  final String dropId;
  final List<String> mimeTypes;
}

/// Product-side target-only implementation of Kitty OSC 72.
///
/// Child commands remain untrusted. The controller enables the native target
/// only for the active session, serves only data captured from a user-driven
/// system drop, chunks Base64 to the normative 4 KiB packet bound, and releases
/// native data after completion/error.
class Osc72DragDropController {
  Osc72DragDropController({
    required Osc72SendInput sendInput,
    Osc72ConfigureTarget configureTarget =
        WindowBridge.configureOsc72DropTarget,
    Osc72SetDecision setDecision = WindowBridge.setOsc72DropDecision,
    Osc72ReadDropData readDropData = WindowBridge.readOsc72DropData,
    Osc72ReleaseDrop releaseDrop = WindowBridge.releaseOsc72Drop,
  }) : _sendInput = sendInput,
       _configureTarget = configureTarget,
       _setDecision = setDecision,
       _readDropData = readDropData,
       _releaseDrop = releaseDrop;

  static const int _maxMimeTypes = 64;
  static const int _maxMimeBytes = 256;
  static const int _rawChunkBytes = 3072;
  static const List<String> _defaultMimeTypes = <String>[
    'text/plain',
    'text/uri-list',
  ];

  final Osc72SendInput _sendInput;
  final Osc72ConfigureTarget _configureTarget;
  final Osc72SetDecision _setDecision;
  final Osc72ReadDropData _readDropData;
  final Osc72ReleaseDrop _releaseDrop;
  final Map<String, _Osc72Target> _targets = <String, _Osc72Target>{};
  String? _activeSessionId;
  _Osc72Drop? _activeDrop;

  Future<void> setActiveSession(String? sessionId) async {
    _activeSessionId = sessionId;
    await _syncNativeTarget();
  }

  Future<void> handleCommand(
    terminal.TerminalSessionDragDropCommandEvent event,
  ) async {
    switch (event.action) {
      case 'q':
        _sendSequence(
          event.sessionId,
          metadata: _metadata('q', identifier: event.identifier),
          payload: 'drop=1:offer=0',
        );
      case 'a':
        // t=a:x=1 carries the hashed machine id, not a MIME allowlist.
        if (event.x == 1) {
          return;
        }
        final parsedMimeTypes = _parseMimeTypes(event.payload);
        final mimeTypes = parsedMimeTypes.isEmpty
            ? _defaultMimeTypes
            : parsedMimeTypes;
        _targets[event.sessionId] = _Osc72Target(
          mimeTypes: mimeTypes,
          identifier: event.identifier,
        );
        await _syncNativeTarget();
      case 'A':
        _targets.remove(event.sessionId);
        await _releaseActiveDropFor(event.sessionId);
        await _syncNativeTarget();
      case 'm':
        if (event.sessionId != _activeSessionId) {
          return;
        }
        final operation = event.operation;
        await _setDecision(operation == 1 || operation == 2 ? operation! : 0);
      case 'r':
        if (event.x != null) {
          await _serveDropData(event);
        } else {
          await _releaseActiveDropFor(event.sessionId);
        }
      case 'R' || 'E':
        await _releaseActiveDropFor(event.sessionId);
      // Outgoing drag source support is deliberately not advertised. These
      // commands cannot start an OS drag or read a host file.
      case 'o' || 'p' || 'P' || 'e' || 'k' || 'M':
        return;
      default:
        return;
    }
  }

  Future<void> handleNativeEvent(
    NativeOsc72DragEvent event, {
    required Osc72DropLocation? Function(NativeOsc72DragEvent event)
    resolveLocation,
  }) async {
    final target = _targets[event.sessionId];
    if (target == null || event.sessionId != _activeSessionId) {
      return;
    }
    if (event.phase == 'leave') {
      _sendSequence(
        event.sessionId,
        metadata: _metadata(
          'm',
          identifier: target.identifier,
          values: const <String, int>{'x': -1, 'y': -1, 'o': 0},
        ),
      );
      return;
    }
    final location = resolveLocation(event);
    if (location == null) {
      await _setDecision(0);
      return;
    }
    final offered = event.mimeTypes
        .where(target.mimeTypes.contains)
        .take(_maxMimeTypes)
        .toList(growable: false);
    final isDrop = event.phase == 'drop';
    if (isDrop) {
      final dropId = event.dropId;
      if (dropId == null || offered.isEmpty) {
        await _setDecision(0);
        return;
      }
      await _releaseActiveDrop();
      _activeDrop = _Osc72Drop(
        sessionId: event.sessionId,
        dropId: dropId,
        mimeTypes: offered,
      );
    }
    _sendSequence(
      event.sessionId,
      metadata: _metadata(
        isDrop ? 'M' : 'm',
        identifier: target.identifier,
        values: <String, int>{
          'x': location.cellX,
          'y': location.cellY,
          'X': location.pixelX,
          'Y': location.pixelY,
          'o': event.operations.clamp(0, 3),
        },
      ),
      payload: offered.join(' '),
    );
  }

  Future<void> resetSession(String sessionId) async {
    _targets.remove(sessionId);
    await _releaseActiveDropFor(sessionId);
    await _syncNativeTarget();
  }

  Future<void> dispose() async {
    _targets.clear();
    _activeSessionId = null;
    await _releaseActiveDrop();
    await _configureTarget(enabled: false, mimeTypes: const <String>[]);
  }

  Future<void> _syncNativeTarget() async {
    final sessionId = _activeSessionId;
    final target = sessionId == null ? null : _targets[sessionId];
    if (sessionId == null || target == null || target.mimeTypes.isEmpty) {
      await _configureTarget(enabled: false, mimeTypes: const <String>[]);
      return;
    }
    await _configureTarget(
      enabled: true,
      sessionId: sessionId,
      mimeTypes: target.mimeTypes,
    );
  }

  Future<void> _serveDropData(
    terminal.TerminalSessionDragDropCommandEvent event,
  ) async {
    final drop = _activeDrop;
    final index = event.x;
    if (event.y != null || event.pixelY != null) {
      // Remote URI entry and directory-handle reads are outside the local
      // target subset. Never reinterpret them as a request for the URI list.
      _sendError(event.sessionId, event.identifier, index, 'EINVAL');
      return;
    }
    if (drop == null ||
        drop.sessionId != event.sessionId ||
        index == null ||
        index < 1 ||
        index > drop.mimeTypes.length) {
      _sendError(event.sessionId, event.identifier, index, 'ENOENT');
      return;
    }
    final mimeType = drop.mimeTypes[index - 1];
    var offset = 0;
    try {
      while (true) {
        final chunk = await _readDropData(
          dropId: drop.dropId,
          mimeType: mimeType,
          offset: offset,
          maxBytes: _rawChunkBytes,
        );
        if (chunk.bytes.isNotEmpty) {
          _sendSequence(
            event.sessionId,
            metadata: _metadata(
              'r',
              identifier: event.identifier,
              values: <String, int>{'x': index, 'm': 1},
            ),
            payload: base64.encode(chunk.bytes),
          );
          offset += chunk.bytes.length;
        }
        if (chunk.eof) {
          _sendSequence(
            event.sessionId,
            metadata: _metadata(
              'r',
              identifier: event.identifier,
              values: <String, int>{'x': index, 'm': 0},
            ),
          );
          return;
        }
        if (chunk.bytes.isEmpty) {
          throw const FormatException('OSC 72 drop reader made no progress');
        }
      }
    } on Object {
      _sendError(event.sessionId, event.identifier, index, 'EIO');
      await _releaseActiveDropFor(event.sessionId);
    }
  }

  void _sendError(String sessionId, int? identifier, int? index, String error) {
    _sendSequence(
      sessionId,
      metadata: _metadata(
        'R',
        identifier: identifier,
        values: <String, int>{'x': ?index},
      ),
      payload: error,
    );
  }

  Future<void> _releaseActiveDropFor(String sessionId) async {
    if (_activeDrop?.sessionId == sessionId) {
      await _releaseActiveDrop();
    }
  }

  Future<void> _releaseActiveDrop() async {
    final drop = _activeDrop;
    _activeDrop = null;
    if (drop != null) {
      await _releaseDrop(drop.dropId);
    }
  }

  List<String> _parseMimeTypes(String payload) {
    final values = <String>[];
    final seen = <String>{};
    for (final value in payload.split(RegExp(r'\s+'))) {
      if (value.isEmpty ||
          utf8.encode(value).length > _maxMimeBytes ||
          value.runes.any((rune) => rune < 0x21 || rune == 0x7f) ||
          !seen.add(value)) {
        continue;
      }
      values.add(value);
      if (values.length == _maxMimeTypes) {
        break;
      }
    }
    return List<String>.unmodifiable(values);
  }

  String _metadata(
    String action, {
    int? identifier,
    Map<String, int> values = const <String, int>{},
  }) {
    final parts = <String>['t=$action'];
    if (identifier != null && identifier > 0) {
      parts.add('i=$identifier');
    }
    for (final entry in values.entries) {
      parts.add('${entry.key}=${entry.value}');
    }
    return parts.join(':');
  }

  void _sendSequence(
    String sessionId, {
    required String metadata,
    String payload = '',
  }) {
    final sequence = '\x1b]72;$metadata;$payload\x1b\\';
    _sendInput(sessionId, Uint8List.fromList(utf8.encode(sequence)));
  }
}
