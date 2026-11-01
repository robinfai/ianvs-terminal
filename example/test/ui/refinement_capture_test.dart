import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/ui/previews/terminal_ai_workspace_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design/configuration_capture_binding.dart';
import '../design/visual_capture_fonts.dart';

void main() {
  ConfigurationCaptureBinding();
  setUpAll(loadVisualCaptureFonts);
  const evidence = String.fromEnvironment('AUDIT_AI_DIR');
  for (final variant in [
    (
      name: 'ios-ai-light',
      dark: false,
      size: const Size(402, 874),
      phone: true,
      history: false,
    ),
    (
      name: 'ios-ai-dark',
      dark: true,
      size: const Size(402, 874),
      phone: true,
      history: false,
    ),
    (
      name: 'macos-ai-light',
      dark: false,
      size: const Size(1280, 900),
      phone: false,
      history: false,
    ),
    (
      name: 'macos-ai-dark',
      dark: true,
      size: const Size(1280, 900),
      phone: false,
      history: false,
    ),
    (
      name: 'ios-history-light',
      dark: false,
      size: const Size(402, 874),
      phone: true,
      history: true,
    ),
    (
      name: 'ios-history-dark',
      dark: true,
      size: const Size(402, 874),
      phone: true,
      history: true,
    ),
  ]) {
    testWidgets(
      '${variant.name} history preview renders saved conversations',
      (tester) async {
        tester.view.physicalSize = variant.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final boundary = GlobalKey();
        await tester.runAsync(() async {
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: AiWorkspacePreview(
                phone: variant.phone,
                historyList: variant.history,
                dark: variant.dark,
                themeTransform: withVisualCaptureFonts,
              ),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pumpAndSettle();
        if (variant.history) expect(find.text('整理部署前的检查清单'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (evidence.isNotEmpty) {
          await tester.runAsync(() async {
            await Directory(evidence).create(recursive: true);
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '$evidence/${variant.name}.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
      },
      variant: TargetPlatformVariant.only(
        variant.phone ? TargetPlatform.iOS : TargetPlatform.macOS,
      ),
    );
  }
}
