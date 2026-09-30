import 'dart:convert';
import 'dart:io';

import 'package:app/features/shell/window_bridge.dart';
import 'package:app/features/terminal/terminal.dart';
import 'package:app/platform/clipboard_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/macos_integration_test_lifecycle.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Linux clipboard MIME wildcard returns concrete image type and exact bytes',
    (tester) async {
      await tester.pumpWidget(const SizedBox.expand());
      ensureDesktopIntegrationTestFramesEnabled(tester.binding);
      final bytes = Uint8List.fromList([
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
        0,
        255,
      ]);
      await ClipboardBridge.writeMimeItems([
        TerminalClipboardMimeItem(mimeType: 'image/png', bytes: bytes),
      ]);
      expect(await ClipboardBridge.listMimeTypes(), contains('image/png'));
      final items = await ClipboardBridge.readMimeItems(['image/*']);
      expect(items, hasLength(1));
      expect(items.single.mimeType, 'image/png');
      expect(items.single.bytes, orderedEquals(bytes));
    },
    skip: !Platform.isLinux,
  );

  testWidgets('Linux text clipboard MIME round trips UTF-8 bytes', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.expand());
    ensureDesktopIntegrationTestFramesEnabled(tester.binding);
    const text = 'Linux clipboard fixture: 中文 café\nsecond line';
    final bytes = Uint8List.fromList(utf8.encode(text));
    await ClipboardBridge.writeMimeItems([
      TerminalClipboardMimeItem(mimeType: 'text/plain', bytes: bytes),
    ]);
    final items = await ClipboardBridge.readMimeItems(['text/plain']);
    expect(items, hasLength(1));
    expect(items.single.mimeType, 'text/plain');
    expect(items.single.bytes, orderedEquals(bytes));
    expect(utf8.decode(items.single.bytes), text);
    expect(await ClipboardBridge.paste(), text);
    for (final selection in ['find', 'font', 'unknown']) {
      await expectLater(
        ClipboardBridge.writeText('must not replace normal text', selection),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'unsupported_clipboard_selection',
          ),
        ),
      );
      expect(await ClipboardBridge.paste(), text);
    }
  }, skip: !Platform.isLinux);

  testWidgets(
    'Linux native window bridge reports real metrics and validates external URLs',
    (tester) async {
      await tester.pumpWidget(const SizedBox.expand());
      ensureDesktopIntegrationTestFramesEnabled(tester.binding);
      final metrics = await WindowBridge.metrics();
      expect(metrics, isNotNull);
      expect(metrics!.contentSize!.width, greaterThan(0));
      expect(metrics.contentSize!.height, greaterThan(0));
      expect(metrics.devicePixelRatio, greaterThan(0));

      // Exercise native validation directly: the Dart facade intentionally
      // ignores invalid schemes before invoking the platform channel.
      const channel = MethodChannel('app/window_bridge');
      await expectLater(
        channel.invokeMethod<void>('openExternalUrl', {'url': 'javascript:1'}),
        throwsA(isA<PlatformException>()),
      );
    },
    skip: !Platform.isLinux,
  );

  testWidgets('Linux OSC 72 target has a bounded native lifecycle', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.expand());
    ensureDesktopIntegrationTestFramesEnabled(tester.binding);
    addTearDown(() => WindowBridge.configureOsc72DropTarget(enabled: false));
    await WindowBridge.configureOsc72DropTarget(
      enabled: true,
      sessionId: 'linux-bridge-fixture',
      mimeTypes: const ['text/plain', 'text/uri-list'],
    );
    final enabled = await WindowBridge.osc72DropTargetStatus();
    expect(enabled, isNotNull);
    expect(enabled!.enabled, isTrue);
    expect(enabled.sessionId, 'linux-bridge-fixture');
    expect(enabled.mimeTypes, ['text/plain', 'text/uri-list']);
    expect(enabled.cachedDrops, 0);
    await WindowBridge.setOsc72DropDecision(1);
    expect((await WindowBridge.osc72DropTargetStatus())?.decision, 1);
    await WindowBridge.configureOsc72DropTarget(enabled: false);
    expect((await WindowBridge.osc72DropTargetStatus())?.enabled, isFalse);
  }, skip: !Platform.isLinux);
}
