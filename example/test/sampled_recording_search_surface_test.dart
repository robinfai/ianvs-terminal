import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/recording/sampled_recording_search_models.dart';
import 'package:app/features/recording/sampled_recording_search_surface.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'design/visual_capture_fonts.dart';

void main() {
  final capture = Platform.environment['IANVS_RECORDING_VISUAL_CAPTURE'] == '1';
  if (capture) setUpAll(loadVisualCaptureFonts);
  final hit = RecordingSearchResult(
    path: '/recordings/fixture.trailrec',
    title: 'Deployment review',
    createdAtUtc: DateTime.utc(2026, 9, 27),
    offset: const Duration(hours: 26, minutes: 15),
    scope: RecordingSearchScope.command,
    preview: 'git status --short',
    hostname: 'nested.example',
  );

  for (final size in <Size>[const Size(1100, 740), const Size(390, 700)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'search filters, navigation and keyboard at $size $brightness',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          try {
            RecordingSearchQuery? query;
            RecordingSearchResult? selected;
            var closed = false;
            var next = false;
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
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(size.width < 500 ? 2 : 1),
                  ),
                  child: RepaintBoundary(
                    key: const Key('capture-search'),
                    child: child,
                  ),
                ),
                home: Scaffold(
                  body: RecordingSearchSurface(
                    results: [hit],
                    loading: false,
                    hasCriteria: true,
                    pageNumber: 2,
                    scannedFiles: 2,
                    totalFiles: 3,
                    skippedFiles: 0,
                    onQuery: (value) => query = value,
                    onSelect: (value) => selected = value,
                    onClose: () => closed = true,
                    onRetry: () {},
                    onFirst: () {},
                    onPrevious: () {},
                    onNext: () => next = true,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.enterText(find.byType(TextField).first, 'git status');
            expect(query!.text, 'git status');
            await tester.ensureVisible(find.byType(TextField).last);
            await tester.enterText(find.byType(TextField).last, 'nested');
            await tester.pumpAndSettle();
            expect(query!.hostname, 'nested');
            final scope = find.byType(DropdownButton<RecordingSearchScope>);
            await tester.ensureVisible(scope);
            await tester.tap(scope);
            await tester.pumpAndSettle();
            await tester.tap(find.text('Commands only').last);
            await tester.pumpAndSettle();
            expect(query!.scope, RecordingSearchScope.command);
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(find.text('Clear filters'));
            await tester.tap(find.text('Clear filters'));
            await tester.pumpAndSettle();
            expect(query!.hostname, isEmpty);
            expect(query!.scope, RecordingSearchScope.all);
            expect(query!.text, 'git status');

            await tester.ensureVisible(find.text(hit.preview));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (capture) {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const Key('capture-search')),
              );
              await tester.runAsync(() async {
                final image = await boundary.toImage();
                try {
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  final file = File(
                    'build/recording_bench/adaptive/search-${size.width.toInt()}-${brightness.name}.png',
                  );
                  await file.parent.create(recursive: true);
                  await file.writeAsBytes(bytes!.buffer.asUint8List());
                } finally {
                  image.dispose();
                }
              });
            }
            await tester.tap(find.text(hit.preview));
            expect(selected, same(hit));
            final forward = find.byTooltip('Next search page');
            expect(
              tester
                  .getSemantics(forward)
                  .getSemanticsData()
                  .hasAction(ui.SemanticsAction.tap),
              isTrue,
            );
            await tester.tap(forward);
            expect(next, isTrue);
            await tester.ensureVisible(find.byType(TextField).first);
            await tester.tap(find.byType(TextField).first);
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

  testWidgets('loading disables results and paging; errors offer retry', (
    tester,
  ) async {
    var loading = true;
    var retried = false;
    var next = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildIanvsTerminalTheme(
          Brightness.light,
          platform: TargetPlatform.macOS,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return RecordingSearchSurface(
                results: [hit],
                loading: loading,
                hasCriteria: true,
                pageNumber: 1,
                scannedFiles: 1,
                totalFiles: 2,
                skippedFiles: 0,
                error: loading ? null : 'Fixture unavailable',
                onQuery: (_) {},
                onSelect: (_) => fail('Loading result was selectable'),
                onClose: () {},
                onRetry: () => retried = true,
                onNext: () => next = true,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.widget<ListTile>(find.byType(ListTile)).enabled, isFalse);
    await tester.tap(find.byTooltip('Next search page'));
    expect(next, isFalse);
    rebuild(() => loading = false);
    await tester.pumpAndSettle();
    expect(find.text('Fixture unavailable'), findsOneWidget);
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}
