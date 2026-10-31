import 'dart:io';

import 'package:app/ui/foundation/app_theme.dart';
import 'package:app/ui/previews/icon_design_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_review_capture.dart';
import 'visual_capture_fonts.dart';

const candidatePath = String.fromEnvironment('ICON_CANDIDATE_FONT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isMacOS) {
    test('icon captures require macOS font fixtures', () {}, skip: true);
    return;
  }
  setUpAll(() async {
    await loadVisualCaptureFonts(productionIcons: true);
    if (candidatePath.isNotEmpty) {
      await (FontLoader('IconCandidate')..addFont(
            File(candidatePath).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
  });
  for (final brightness in Brightness.values) {
    testWidgets('production icon audit ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: withVisualCaptureFonts(buildIanvsTerminalTheme(brightness)),
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Production · 16 / 20 / 24 px'),
                  ),
                  const IconDesignPreview(),
                  if (candidatePath.isNotEmpty) ...[
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Candidate · 16 / 20 / 24 px'),
                    ),
                    const IconDesignPreview(fontFamily: 'IconCandidate'),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text('Settings'),
        findsNWidgets(candidatePath.isEmpty ? 1 : 2),
      );
      await captureUiReview(tester, boundary, 'icons-${brightness.name}');
    });
  }
}
