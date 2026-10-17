import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const uiReviewEvidenceDirectory = String.fromEnvironment(
  'FULL_UI_EVIDENCE_DIR',
);

Future<void> captureUiReview(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (uiReviewEvidenceDirectory.isEmpty) return;
  await tester.runAsync(() async {
    await Directory(uiReviewEvidenceDirectory).create(recursive: true);
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '$uiReviewEvidenceDirectory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
