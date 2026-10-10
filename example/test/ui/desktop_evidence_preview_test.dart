import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/ui/app_ui.dart';
import 'package:app/ui/previews/desktop_evidence_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../design/configuration_capture_binding.dart';
import '../design/visual_capture_fonts.dart';

void main() {
  ConfigurationCaptureBinding();
  setUpAll(loadVisualCaptureFonts);
  const evidence = String.fromEnvironment('DESKTOP_PREVIEW_EVIDENCE_DIR');
  for (final variant in [
    (size: const Size(1200, 760), dark: false, contrast: false, scale: 1.0),
    (size: const Size(1200, 760), dark: true, contrast: true, scale: 1.0),
    (size: const Size(360, 640), dark: true, contrast: false, scale: 2.0),
  ]) {
    testWidgets('desktop reader preview $variant preserves its source', (
      tester,
    ) async {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: DesktopEvidencePreview(
            theme: withVisualCaptureFonts(
              buildIanvsTerminalTheme(
                variant.dark ? Brightness.dark : Brightness.light,
                platform: TargetPlatform.macOS,
                highContrast: variant.contrast,
              ),
            ),
            highContrast: variant.contrast,
            textScale: variant.scale,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Build log · preview'), findsOneWidget);
      expect(find.byKey(const Key('block-reader')), findsOneWidget);
      expect(find.text('Disconnected · exit 0'), findsOneWidget);
      final semantics = tester.widget<Semantics>(
        find.byKey(const Key('desktop-session-status')),
      );
      expect(semantics.properties.label, contains('Evidence reader'));
      expect(semantics.properties.label, contains('Read-only'));
      final numbers = find.byKey(const ValueKey('reader-line-numbers-0'));
      final numberContext = tester.element(numbers);
      final label = TextPainter(
        text: TextSpan(
          text: '240',
          style: ComposerTheme.of(
            numberContext,
          ).metadataStyle.copyWith(fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(numberContext),
      )..layout();
      expect(
        tester.getSize(numbers).width,
        greaterThanOrEqualTo(label.width + 16),
      );
      label.dispose();
      expect(
        tester.getTopLeft(find.byKey(const Key('block-reader-close'))).dy -
            tester.getTopLeft(find.byKey(const Key('block-reader'))).dy,
        lessThan(20),
        reason: 'The hosted reader already sits below the native title bar.',
      );
      Future<void> capturePreview(String mode) async {
        if (evidence.isEmpty) return;
        await tester.runAsync(() async {
          await Directory(evidence).create(recursive: true);
          final render =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final name =
              '${variant.dark ? 'dark' : 'light'}-'
              '${variant.contrast ? 'contrast' : 'normal'}-'
              '${variant.size.width.toInt()}-${variant.scale}-$mode';
          await File(
            '$evidence/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capturePreview('full');
      if (variant.size.width >= 960) {
        await tester.tap(find.byKey(const Key('pane-evidence-beside')));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const Key('pane-evidence-reader'))).width,
          360,
        );
        await capturePreview('beside');
      }
      await tester.tap(find.byKey(const Key('block-reader-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('block-reader')), findsNothing);
      await tester.tap(find.byKey(const Key('desktop-preview-open-reader')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('block-reader')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
