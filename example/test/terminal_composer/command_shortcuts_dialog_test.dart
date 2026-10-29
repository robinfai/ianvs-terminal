import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/terminal_composer/command_shortcuts_dialog.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design/configuration_capture_binding.dart';
import '../design/visual_capture_fonts.dart';

const _evidence = String.fromEnvironment('SHORTCUT_EVIDENCE_DIR');

void main() {
  ConfigurationCaptureBinding();
  setUpAll(loadVisualCaptureFonts);
  for (final scene in [
    (
      name: 'desktop',
      size: const Size(1008, 994),
      brightness: Brightness.light,
      scale: 1.0,
      platform: TargetPlatform.macOS,
    ),
    (
      name: 'dark',
      size: const Size(1008, 994),
      brightness: Brightness.dark,
      scale: 1.0,
      platform: TargetPlatform.macOS,
    ),
    (
      name: 'phone',
      size: const Size(320, 568),
      brightness: Brightness.light,
      scale: 1.0,
      platform: TargetPlatform.iOS,
    ),
    (
      name: 'short',
      size: const Size(640, 400),
      brightness: Brightness.light,
      scale: 1.0,
      platform: TargetPlatform.linux,
    ),
    (
      name: 'scaled',
      size: const Size(960, 850),
      brightness: Brightness.dark,
      scale: 2.0,
      platform: TargetPlatform.macOS,
    ),
  ]) {
    testWidgets('shortcut reference stays usable in ${scene.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scene.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: withVisualCaptureFonts(
              buildIanvsTerminalTheme(
                scene.brightness,
                platform: scene.platform,
              ),
            ),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scene.scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const CommandShortcutsDialog(),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text(scene.platform == TargetPlatform.macOS ? 'Option' : 'Alt'),
        findsOneWidget,
      );
      final done = find.byKey(const Key('command-shortcuts-done'));
      expect(done.hitTestable(), findsOneWidget);
      if (_evidence.isNotEmpty) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('capture')),
          );
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(_evidence).create(recursive: true);
          await File(
            '$_evidence/${scene.name}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.ensureVisible(find.text('上一个控件'));
      await tester.pumpAndSettle();
      expect(find.text('上一个控件').hitTestable(), findsOneWidget);
      expect(done.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(done);
      await tester.pumpAndSettle();
      expect(find.byType(CommandShortcutsDialog), findsNothing);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(CommandShortcutsDialog), findsNothing);
    });
  }
}
