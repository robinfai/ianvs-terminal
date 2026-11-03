import 'dart:io';
import 'dart:ui' as ui;
import 'package:app/features/ai/ai_connection_test.dart';
import 'package:app/ui/previews/ai_connection_test_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Opt-in local visual review; no platform font dependency in normal CI.
void main() {
  const output = String.fromEnvironment('AI_TEST_CAPTURE_DIR');
  const font = String.fromEnvironment('AI_TEST_CAPTURE_FONT');
  for (final status in [
    AiConnectionTestStatus.running,
    AiConnectionTestStatus.success,
    AiConnectionTestStatus.timedOut,
    AiConnectionTestStatus.failed,
  ]) {
    testWidgets(
      'capture connection test ${status.name}',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(680, 540));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.runAsync(() async {
          final loader = FontLoader('VisualTest')
            ..addFont(File(font).readAsBytes().then(ByteData.sublistView));
          await loader.load();
          const icons = String.fromEnvironment('AI_TEST_CAPTURE_ICONS');
          if (icons.isNotEmpty) {
            await (FontLoader('MaterialIcons')..addFont(
                  File(icons).readAsBytes().then(ByteData.sublistView),
                ))
                .load();
          }
        });
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: AiConnectionTestPreview(
              status: status,
              fontFamily: 'VisualTest',
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File(
            '$output/${status.name}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      skip: output.isEmpty || font.isEmpty,
    );
  }
}
