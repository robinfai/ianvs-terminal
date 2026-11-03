import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/recording/sampled_replay_surface.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design/visual_capture_fonts.dart';

void main() {
  final capture = Platform.environment['IANVS_RECORDING_VISUAL_CAPTURE'] == '1';
  if (capture) setUpAll(loadVisualCaptureFonts);
  ThemeData theme(Brightness brightness) {
    final value = buildIanvsTerminalTheme(
      brightness,
      platform: TargetPlatform.macOS,
    );
    return capture ? withVisualCaptureFonts(value) : value;
  }

  for (final size in <Size>[const Size(1100, 740), const Size(390, 700)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'replay layout, commands and controls at $size $brightness with large text',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          Duration? sought;
          var closed = false;
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme(brightness),
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(size.width < 500 ? 2 : 1),
                ),
                child: RepaintBoundary(
                  key: const Key('capture-replay'),
                  child: child,
                ),
              ),
              home: Scaffold(
                body: SampledReplaySurface(
                  title: 'A recorded session',
                  viewport: const Center(child: Text('stored screen')),
                  position: const Duration(seconds: 1),
                  duration: const Duration(hours: 27),
                  playing: false,
                  loading: false,
                  speed: 1,
                  interrupted: true,
                  timelineLoading: false,
                  commands: const [
                    SampledReplayCommand(
                      label: 'printf ready',
                      detail: 'Exit 0 · host',
                      offset: Duration(seconds: 5),
                    ),
                  ],
                  onToggle: () {},
                  onSeek: (value) => sought = value,
                  onSpeed: (_) {},
                  onCopy: () {},
                  onClose: () => closed = true,
                  onFirstPage: () {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('stored screen'), findsOneWidget);
          await tester.tap(find.byTooltip('Commands'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (Platform.environment['IANVS_RECORDING_VISUAL_CAPTURE'] == '1') {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('capture-replay')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              try {
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File(
                  'build/recording_bench/adaptive/replay-${size.width.toInt()}-${brightness.name}.png',
                );
                await file.parent.create(recursive: true);
                await file.writeAsBytes(bytes!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }
          await tester.tap(find.text('printf ready'));
          await tester.pumpAndSettle();
          expect(sought, const Duration(seconds: 5));
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Close'));
          expect(closed, isTrue);
        },
      );
    }
  }
}
