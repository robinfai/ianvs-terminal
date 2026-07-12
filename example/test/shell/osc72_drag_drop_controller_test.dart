import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;
import 'package:app/features/shell/osc72_drag_drop_controller.dart';
import 'package:app/features/shell/window_bridge.dart';

void main() {
  test('query is correlated and reports the target-only capability', () async {
    final sent = <String>[];
    final controller = _controller(sent: sent);

    await controller.handleCommand(_command('s1', action: 'q', identifier: 17));

    expect(sent, <String>['\x1b]72;t=q:i=17;drop=1:offer=0\x1b\\']);
  });

  test(
    'only the active session registers its bounded MIME allowlist',
    () async {
      final configurations = <_Configuration>[];
      final decisions = <int>[];
      final controller = _controller(
        configurations: configurations,
        decisions: decisions,
      );

      await controller.setActiveSession('s1');
      await controller.handleCommand(
        _command(
          's1',
          action: 'a',
          identifier: 4,
          payload: 'text/plain text/uri-list text/plain bad\u0001mime',
        ),
      );
      expect(
        configurations.last,
        const _Configuration(
          enabled: true,
          sessionId: 's1',
          mimeTypes: <String>['text/plain', 'text/uri-list'],
        ),
      );

      await controller.handleCommand(
        _command('s2', action: 'a', payload: 'image/png'),
      );
      expect(configurations.last.sessionId, 's1');

      await controller.setActiveSession('s2');
      expect(
        configurations.last,
        const _Configuration(
          enabled: true,
          sessionId: 's2',
          mimeTypes: <String>['image/png'],
        ),
      );
      await controller.handleCommand(_command('s2', action: 'm', operation: 2));
      expect(decisions, <int>[2]);

    await controller.handleCommand(_command('s2', action: 'A'));
    expect(configurations.last.enabled, isFalse);

    await controller.handleCommand(_command('s2', action: 'a'));
    expect(
      configurations.last.mimeTypes,
      const <String>['text/plain', 'text/uri-list'],
    );
    },
  );

  test(
    'native move and drop are routed with exact cell and pixel geometry',
    () async {
      final sent = <String>[];
      final controller = _controller(sent: sent);
      await controller.setActiveSession('s1');
      await controller.handleCommand(
        _command(
          's1',
          action: 'a',
          identifier: 5,
          payload: 'text/plain text/uri-list',
        ),
      );

      Osc72DropLocation? resolve(NativeOsc72DragEvent event) {
        return const Osc72DropLocation(
          cellX: 3,
          cellY: 2,
          pixelX: 31,
          pixelY: 42,
        );
      }

      await controller.handleNativeEvent(
        const NativeOsc72DragEvent(
          phase: 'move',
          sessionId: 's1',
          mimeTypes: <String>['image/png', 'text/plain'],
          position: Offset(100, 200),
          operations: 3,
        ),
        resolveLocation: resolve,
      );
      await controller.handleNativeEvent(
        const NativeOsc72DragEvent(
          phase: 'drop',
          sessionId: 's1',
          mimeTypes: <String>['text/uri-list'],
          position: Offset(100, 200),
          operations: 1,
          dropId: 'drop-1',
        ),
        resolveLocation: resolve,
      );

      expect(sent, <String>[
        '\x1b]72;t=m:i=5:x=3:y=2:X=31:Y=42:o=3;text/plain\x1b\\',
        '\x1b]72;t=M:i=5:x=3:y=2:X=31:Y=42:o=1;text/uri-list\x1b\\',
      ]);
    },
  );

  test('drop data is Base64 chunked, terminated, and released', () async {
    final sent = <String>[];
    final released = <String>[];
    final bytes = Uint8List.fromList(
      List<int>.generate(5000, (index) => index % 251),
    );
    final controller = _controller(
      sent: sent,
      released: released,
      readDropData:
          ({
            required dropId,
            required mimeType,
            required offset,
            required maxBytes,
          }) async {
            expect(dropId, 'drop-1');
            expect(mimeType, 'application/octet-stream');
            expect(maxBytes, 3072);
            final end = (offset + maxBytes).clamp(0, bytes.length);
            return NativeOsc72DropChunk(
              bytes: Uint8List.sublistView(bytes, offset, end),
              eof: end == bytes.length,
              size: bytes.length,
            );
          },
    );
    await controller.setActiveSession('s1');
    await controller.handleCommand(
      _command('s1', action: 'a', payload: 'application/octet-stream'),
    );
    await controller.handleNativeEvent(
      const NativeOsc72DragEvent(
        phase: 'drop',
        sessionId: 's1',
        mimeTypes: <String>['application/octet-stream'],
        position: Offset.zero,
        operations: 1,
        dropId: 'drop-1',
      ),
      resolveLocation: (_) =>
          const Osc72DropLocation(cellX: 0, cellY: 0, pixelX: 0, pixelY: 0),
    );
    sent.clear();

    await controller.handleCommand(_command('s1', action: 'r', x: 1));

    expect(sent, hasLength(3));
    expect(sent[0], startsWith('\x1b]72;t=r:x=1:m=1;'));
    expect(sent[1], startsWith('\x1b]72;t=r:x=1:m=1;'));
    expect(sent[2], '\x1b]72;t=r:x=1:m=0;\x1b\\');
    for (final sequence in sent.take(2)) {
      final payload = sequence
          .split(';')[2]
          .substring(0, sequence.split(';')[2].length - 2);
      expect(payload.length, lessThanOrEqualTo(4096));
    }

    await controller.handleCommand(_command('s1', action: 'r', operation: 1));
    expect(released, <String>['drop-1']);
  });

  test('out-of-range data request returns ENOENT without host read', () async {
    final sent = <String>[];
    final controller = _controller(sent: sent);

    await controller.handleCommand(_command('s1', action: 'r', x: 2));

    expect(sent, <String>['\x1b]72;t=R:x=2;ENOENT\x1b\\']);
  });

  test('remote URI entry requests are rejected without reading host files', () async {
    final sent = <String>[];
    final controller = _controller(sent: sent);

    await controller.handleCommand(
      terminal.TerminalSessionDragDropCommandEvent(
        's1',
        rawPayload: const <String, Object?>{
          'action': 'r',
          'x': 1,
          'y': 2,
          'payload': '',
        },
      ),
    );

    expect(sent, <String>['\x1b]72;t=R:x=1;EINVAL\x1b\\']);
  });
}

Osc72DragDropController _controller({
  List<String>? sent,
  List<_Configuration>? configurations,
  List<int>? decisions,
  List<String>? released,
  Osc72ReadDropData? readDropData,
}) {
  return Osc72DragDropController(
    sendInput: (sessionId, bytes) {
      sent?.add(utf8.decode(bytes));
    },
    configureTarget: ({required enabled, sessionId, required mimeTypes}) async {
      configurations?.add(
        _Configuration(
          enabled: enabled,
          sessionId: sessionId,
          mimeTypes: mimeTypes,
        ),
      );
    },
    setDecision: (operation) async {
      decisions?.add(operation);
    },
    readDropData:
        readDropData ??
        ({
          required dropId,
          required mimeType,
          required offset,
          required maxBytes,
        }) async => throw StateError('unexpected read'),
    releaseDrop: (dropId) async {
      released?.add(dropId);
    },
  );
}

terminal.TerminalSessionDragDropCommandEvent _command(
  String sessionId, {
  required String action,
  int? identifier,
  int? operation,
  int? x,
  String payload = '',
}) {
  return terminal.TerminalSessionDragDropCommandEvent(
    sessionId,
    rawPayload: <String, Object?>{
      'action': action,
      'identifier': identifier,
      'operation': operation,
      'x': x,
      'payload': payload,
    },
  );
}

class _Configuration {
  const _Configuration({
    required this.enabled,
    required this.sessionId,
    required this.mimeTypes,
  });

  final bool enabled;
  final String? sessionId;
  final List<String> mimeTypes;

  @override
  bool operator ==(Object other) {
    return other is _Configuration &&
        other.enabled == enabled &&
        other.sessionId == sessionId &&
        _listEquals(other.mimeTypes, mimeTypes);
  }

  @override
  int get hashCode =>
      Object.hash(enabled, sessionId, Object.hashAll(mimeTypes));
}

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
