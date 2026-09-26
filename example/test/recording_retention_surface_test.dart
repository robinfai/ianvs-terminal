import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/recording/recording_retention_policy.dart';
import 'package:app/features/recording/recording_retention_surface.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design/visual_capture_fonts.dart';

const int _gib = 1024 * 1024 * 1024;
final Finder _days = find.byKey(const Key('recording-retention-days'));
final Finder _capacity = find.byKey(const Key('recording-retention-capacity'));
final Finder _save = find.byKey(const Key('recording-retention-save'));

Future<void> _pumpSurface(
  WidgetTester tester, {
  required ValueChanged<RecordingRetentionPolicy> onSave,
  VoidCallback? onClose,
  VoidCallback? onRetry,
  bool loading = false,
  bool saving = false,
  String? error,
  Size size = const Size(1100, 740),
  Brightness brightness = Brightness.light,
  bool capture = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final theme = buildIanvsTerminalTheme(
    brightness,
    platform: TargetPlatform.macOS,
  );
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: capture ? withVisualCaptureFonts(theme) : theme,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(size.width < 500 ? 2 : 1)),
        child: RepaintBoundary(
          key: const Key('capture-retention'),
          child: child,
        ),
      ),
      home: Scaffold(
        body: RecordingRetentionSurface(
          policy: RecordingRetentionPolicy(
            maximumAgeDays: 30,
            maximumBytes: 20 * _gib,
          ),
          usedBytes: 3 * _gib,
          loading: loading,
          saving: saving,
          error: error,
          onSave: onSave,
          onClose: onClose ?? () {},
          onRetry: onRetry ?? () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group(RecordingRetentionSurface, () {
    final capture =
        Platform.environment['IANVS_RECORDING_VISUAL_CAPTURE'] == '1';
    if (capture) setUpAll(loadVisualCaptureFonts);
    for (final size in [const Size(1100, 740), const Size(390, 700)]) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'edits and saves limits with keyboard access at $size $brightness',
          (tester) async {
            final semantics = tester.ensureSemantics();
            try {
              RecordingRetentionPolicy? saved;
              var closed = false;
              await _pumpSurface(
                tester,
                size: size,
                brightness: brightness,
                capture: capture,
                onSave: (value) => saved = value,
                onClose: () => closed = true,
              );
              await tester.ensureVisible(_days);
              await tester.enterText(_days, '14');
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              await tester.pumpAndSettle();
              expect(
                tester
                    .widget<EditableText>(
                      find.descendant(
                        of: _capacity,
                        matching: find.byType(EditableText),
                      ),
                    )
                    .focusNode
                    .hasFocus,
                isTrue,
              );
              await tester.ensureVisible(_capacity);
              await tester.enterText(_capacity, '1.5');
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expect(
                tester
                    .getSemantics(_save)
                    .getSemanticsData()
                    .hasAction(ui.SemanticsAction.tap),
                isTrue,
              );
              if (capture) {
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(const Key('capture-retention')),
                );
                await tester.runAsync(() async {
                  final image = await boundary.toImage();
                  try {
                    final bytes = await image.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                    final file = File(
                      'build/recording_bench/adaptive/retention-${size.width.toInt()}-${brightness.name}.png',
                    );
                    await file.parent.create(recursive: true);
                    await file.writeAsBytes(bytes!.buffer.asUint8List());
                  } finally {
                    image.dispose();
                  }
                });
              }
              await tester.tap(_save);
              expect(saved!.maximumAgeDays, 14);
              expect(saved!.maximumBytes, 3 * _gib ~/ 2);
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              expect(closed, isTrue);
              expect(tester.takeException(), isNull);
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }

    testWidgets('invalid limits do not apply and can be corrected', (
      tester,
    ) async {
      RecordingRetentionPolicy? saved;
      await _pumpSurface(tester, onSave: (value) => saved = value);
      await tester.enterText(_days, '0');
      await tester.enterText(_capacity, 'NaN');
      await tester.tap(_save);
      await tester.pump();
      expect(saved, isNull);
      expect(
        find.text('Enter a whole number from 1 to 36500.'),
        findsOneWidget,
      );
      await tester.enterText(_days, '36500');
      await tester.enterText(_capacity, '0.25');
      await tester.tap(_save);
      await tester.pump();
      expect(saved!.maximumAgeDays, 36500);
      expect(saved!.maximumBytes, _gib ~/ 4);
    });

    testWidgets(
      'saving prevents repeated apply and dismissal; errors offer retry',
      (tester) async {
        var saved = false;
        var closed = false;
        var retried = false;
        await _pumpSurface(
          tester,
          saving: true,
          onSave: (_) => saved = true,
          onClose: () => closed = true,
        );
        await tester.tap(_save);
        await tester.tap(find.text('Cancel'));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(saved, isFalse);
        expect(closed, isFalse);
        await _pumpSurface(
          tester,
          error: 'Fixture disk unavailable',
          onSave: (_) => saved = true,
          onRetry: () => retried = true,
        );
        await tester.pumpAndSettle();
        expect(find.text('Fixture disk unavailable'), findsOneWidget);
        await tester.tap(find.text('Retry'));
        expect(retried, isTrue);
      },
    );
  });
}
