import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/ui/app_ui.dart';
import 'package:app/ui/previews/command_blocks_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'configuration_capture_binding.dart';
import 'visual_capture_fonts.dart';

const evidence = String.fromEnvironment('BLOCKS_EVIDENCE_DIR');

void main() {
  ConfigurationCaptureBinding();
  setUpAll(loadVisualCaptureFonts);
  for (final scene in [
    (
      name: 'light',
      brightness: Brightness.light,
      size: const Size(900, 850),
      scale: 1.0,
      contrast: false,
      running: false,
    ),
    (
      name: 'dark',
      brightness: Brightness.dark,
      size: const Size(900, 850),
      scale: 1.0,
      contrast: false,
      running: false,
    ),
    (
      name: 'running',
      brightness: Brightness.light,
      size: const Size(900, 850),
      scale: 1.0,
      contrast: false,
      running: true,
    ),
    (
      name: 'narrow-2x',
      brightness: Brightness.dark,
      size: const Size(360, 800),
      scale: 2.0,
      contrast: false,
      running: false,
    ),
    (
      name: 'contrast',
      brightness: Brightness.light,
      size: const Size(900, 850),
      scale: 1.0,
      contrast: true,
      running: false,
    ),
    (
      name: 'short',
      brightness: Brightness.dark,
      size: const Size(640, 330),
      scale: 1.0,
      contrast: false,
      running: false,
    ),
  ]) {
    testWidgets('command blocks ${scene.name}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scene.size;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: CommandBlocksPreview(
            brightness: scene.brightness,
            theme: withVisualCaptureFonts(
              buildIanvsTerminalTheme(
                scene.brightness,
                platform: TargetPlatform.macOS,
              ),
            ),
            textScale: scene.scale,
            highContrast: scene.contrast,
            running: scene.running,
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(TerminalViewport), findsWidgets);
      expect(find.byType(TerminalComposerView), findsOneWidget);
      if (evidence.isNotEmpty) {
        await tester.runAsync(() async {
          await Directory(evidence).create(recursive: true);
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '$evidence/${scene.name}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
