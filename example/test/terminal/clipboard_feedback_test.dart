import 'dart:async';
import 'package:app/platform/clipboard_bridge.dart';
import 'package:app/ui/components/app_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('copy confirms only after clipboard write completes', (
    tester,
  ) async {
    final completion = Completer<void>();
    final writes = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          writes.add((call.arguments as Map)['text'] as String);
          await completion.future;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        builder: (context, child) => AppNotificationHost(child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ClipboardBridge.copyWithFeedback(
                context,
                'selected terminal text',
              ),
              child: const Text('Copy'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(writes, ['selected terminal text']);
    expect(find.text('Copied'), findsNothing);
    completion.complete();
    await tester.pumpAndSettle();
    expect(find.text('Copied'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.getTopLeft(find.text('Copied')).dy, lessThan(150));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('clipboard failure shows retry feedback without false success', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          throw PlatformException(code: 'unavailable');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        builder: (context, child) => AppNotificationHost(child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  ClipboardBridge.copyWithFeedback(context, 'selected text'),
              child: const Text('Copy'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(find.text('Copied'), findsNothing);
    expect(find.text('Could not copy. Please try again.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });
}
