import 'package:app/features/shell/window_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('window metrics accepts finite platform sizes', () {
    final metrics = WindowMetrics.fromMap(const <String, Object?>{
      'contentWidth': 900.0,
      'contentHeight': 600.0,
      'frameWidth': 940.0,
      'frameHeight': 660.0,
      'devicePixelRatio': 2.0,
    });

    expect(metrics.contentSize, const Size(900, 600));
    expect(metrics.frameSize, const Size(940, 660));
    expect(metrics.devicePixelRatio, 2);
  });

  test('window metrics ignores invalid platform sizes', () {
    final metrics = WindowMetrics.fromMap(const <String, Object?>{
      'contentWidth': -1.0,
      'contentHeight': 600.0,
      'frameWidth': 940.0,
      'frameHeight': double.infinity,
      'devicePixelRatio': 0.0,
    });

    expect(metrics.contentSize, isNull);
    expect(metrics.frameSize, isNull);
    expect(metrics.devicePixelRatio, isNull);
  });

  test('hotkey window status tolerates malformed platform fields', () {
    final status = HotkeyWindowStatus.fromMap(const <String, Object?>{
      'registered': 'yes',
      'shortcut': 42,
      'errorCode': 'bad',
    });

    expect(status.registered, isFalse);
    expect(status.shortcut, '⌥⌘Space');
    expect(status.errorCode, isNull);
  });

  test('hotkey window status accepts numeric error codes', () {
    final status = HotkeyWindowStatus.fromMap(const <String, Object?>{
      'registered': true,
      'shortcut': ' ⌃Space ',
      'errorCode': 12.0,
    });

    expect(status.registered, isTrue);
    expect(status.shortcut, '⌃Space');
    expect(status.errorCode, 12);
  });

  test('hotkey window status rejects fractional error codes', () {
    final status = HotkeyWindowStatus.fromMap(const <String, Object?>{
      'registered': true,
      'errorCode': 12.5,
    });

    expect(status.errorCode, isNull);
  });

  test('hotkey window status falls back for blank shortcuts', () {
    final status = HotkeyWindowStatus.fromMap(const <String, Object?>{
      'registered': true,
      'shortcut': '   ',
    });

    expect(status.shortcut, '⌥⌘Space');
  });

  test('OSC 72 native drag events validate and bound platform data', () {
    final event = NativeOsc72DragEvent.fromPlatform(<String, Object?>{
      'phase': 'drop',
      'sessionId': 'session-1',
      'mimeTypes': <String>[
        for (var index = 0; index < 80; index += 1) 'type/$index',
      ],
      'x': 12.5,
      'y': 23,
      'operations': 3,
      'dropId': 'drop-1',
    });

    expect(event.phase, 'drop');
    expect(event.sessionId, 'session-1');
    expect(event.mimeTypes, hasLength(64));
    expect(event.position, const Offset(12.5, 23));
    expect(event.operations, 3);
    expect(event.dropId, 'drop-1');
    expect(
      () => NativeOsc72DragEvent.fromPlatform(const <String, Object?>{}),
      throwsFormatException,
    );
  });

  testWidgets('openExternalUrl only forwards supported URL schemes', (
    tester,
  ) async {
    const channel = MethodChannel('app/window_bridge');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    await WindowBridge.openExternalUrl('x-apple.systempreferences:Security');
    await WindowBridge.openExternalUrl('javascript:alert(1)');
    await WindowBridge.openExternalUrl('http:');
    await WindowBridge.openExternalUrl('  https://example.com/path  ');
    await WindowBridge.openExternalUrl('file:///tmp/ianvs.txt');

    expect(calls, hasLength(2));
    expect(calls.first.method, 'openExternalUrl');
    expect(calls.first.arguments, <String, Object?>{
      'url': 'https://example.com/path',
    });
    expect(calls.last.arguments, <String, Object?>{
      'url': 'file:///tmp/ianvs.txt',
    });
  });

  testWidgets('download save panel receives only a bounded basename', (
    tester,
  ) async {
    const channel = MethodChannel('app/window_bridge');
    MethodCall? seen;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      seen = call;
      return '/tmp/report.txt';
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final selected = await WindowBridge.chooseFileDownloadLocation(
      suggestedName: '../unsafe\\report\u0000.txt',
    );

    expect(selected, '/tmp/report.txt');
    expect(seen?.method, 'chooseFileDownloadLocation');
    expect(seen?.arguments, <String, Object?>{'suggestedName': 'report.txt'});
  });

  testWidgets('recording file management forwards normalized paths', (
    tester,
  ) async {
    const channel = MethodChannel('app/window_bridge');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return switch (call.method) {
        'chooseRecordingFile' => ' /tmp/session.ndjson ',
        'movePathToTrash' => true,
        _ => null,
      };
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final selected = await WindowBridge.chooseRecordingFile(
      initialDirectory: ' /tmp/ianvs-recordings ',
    );
    await WindowBridge.revealInFinder(' /tmp/session.ndjson ');
    final moved = await WindowBridge.movePathToTrash(' /tmp/session.ndjson ');

    expect(selected, '/tmp/session.ndjson');
    expect(moved, isTrue);
    expect(calls.map((call) => call.method), <String>[
      'chooseRecordingFile',
      'revealInFinder',
      'movePathToTrash',
    ]);
    expect(calls[0].arguments, <String, Object?>{
      'initialDirectory': '/tmp/ianvs-recordings',
    });
    expect(calls[1].arguments, <String, Object?>{
      'path': '/tmp/session.ndjson',
    });
    expect(calls[2].arguments, <String, Object?>{
      'path': '/tmp/session.ndjson',
    });
  });

  testWidgets(
    'OSC 72 bridge sends bounded target, decision, read and release calls',
    (tester) async {
      const channel = MethodChannel('app/window_bridge');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'readOsc72DropData') {
          return <String, Object?>{
            'bytes': Uint8List.fromList(<int>[1, 2, 3]),
            'eof': true,
            'size': 3,
          };
        }
        if (call.method == 'osc72DropTargetStatus') {
          return <String, Object?>{
            'enabled': true,
            'sessionId': 'session-1',
            'mimeTypes': <String>['text/plain'],
            'decision': 1,
            'cachedDrops': 0,
          };
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await WindowBridge.configureOsc72DropTarget(
        enabled: true,
        sessionId: 'session-1',
        mimeTypes: const <String>['text/plain'],
      );
      await WindowBridge.setOsc72DropDecision(1);
      final chunk = await WindowBridge.readOsc72DropData(
        dropId: 'drop-1',
        mimeType: 'text/plain',
        offset: 0,
      );
      await WindowBridge.releaseOsc72Drop('drop-1');
      final status = await WindowBridge.osc72DropTargetStatus();

      expect(chunk.bytes, <int>[1, 2, 3]);
      expect(chunk.eof, isTrue);
      expect(chunk.size, 3);
      expect(status?.enabled, isTrue);
      expect(status?.sessionId, 'session-1');
      expect(status?.mimeTypes, <String>['text/plain']);
      expect(calls.map((call) => call.method), <String>[
        'configureOsc72DropTarget',
        'setOsc72DropDecision',
        'readOsc72DropData',
        'releaseOsc72Drop',
        'osc72DropTargetStatus',
      ]);
      expect(calls[2].arguments, <String, Object?>{
        'dropId': 'drop-1',
        'mimeType': 'text/plain',
        'offset': 0,
        'maxBytes': 3072,
      });
    },
  );
}
