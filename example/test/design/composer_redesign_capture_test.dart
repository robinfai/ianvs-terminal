import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/ui/app_ui.dart';
import 'package:app/ui/previews/composer_preview_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'configuration_capture_binding.dart';
import 'visual_capture_fonts.dart';

// Relative to example/. Omit the define to run checks without writing PNGs.
const _evidenceDirectory = String.fromEnvironment('COMPOSER_EVIDENCE_DIR');

const _referenceScenes = <ComposerRedesignScenario>[
  ComposerRedesignScenario.empty,
  ComposerRedesignScenario.completion,
  ComposerRedesignScenario.history,
  ComposerRedesignScenario.suggestion,
  ComposerRedesignScenario.multiline,
  ComposerRedesignScenario.unknown,
];
const _edgeScenes = <ComposerRedesignScenario>[
  ComposerRedesignScenario.completion,
  ComposerRedesignScenario.longAlias,
  ComposerRedesignScenario.completionDetails,
  ComposerRedesignScenario.longHistory,
  ComposerRedesignScenario.longPath,
  ComposerRedesignScenario.multiline,
  ComposerRedesignScenario.unknown,
  ComposerRedesignScenario.emptyHistory,
  ComposerRedesignScenario.moreMenu,
  ComposerRedesignScenario.shortcutHelp,
];
const _contrastScenes = <ComposerRedesignScenario>[
  ComposerRedesignScenario.empty,
  ComposerRedesignScenario.completion,
  ComposerRedesignScenario.history,
  ComposerRedesignScenario.unknown,
  ComposerRedesignScenario.loading,
  ComposerRedesignScenario.copyFeedback,
  ComposerRedesignScenario.shortcutHelp,
];

const _variants = [
  _Variant(
    'idle-light',
    Brightness.light,
    Size(856, 280),
    pixelRatio: 2,
    autofocus: false,
    scenarios: [ComposerRedesignScenario.empty],
  ),
  _Variant(
    'idle-dark',
    Brightness.dark,
    Size(856, 280),
    pixelRatio: 2,
    autofocus: false,
    scenarios: [ComposerRedesignScenario.empty],
  ),
  _Variant('light', Brightness.light, Size(920, 560)),
  _Variant('dark', Brightness.dark, Size(920, 560)),
  _Variant('narrow-2x', Brightness.dark, Size(360, 740), textScale: 2),
  _Variant(
    'reference-light',
    Brightness.light,
    Size(856, 460),
    pixelRatio: 2,
    scenarios: _referenceScenes,
  ),
  _Variant(
    'reference-dark',
    Brightness.dark,
    Size(856, 460),
    pixelRatio: 2,
    scenarios: _referenceScenes,
  ),
  _Variant(
    'compact-320',
    Brightness.light,
    Size(320, 640),
    scenarios: _edgeScenes,
  ),
  _Variant(
    'short-window',
    Brightness.dark,
    Size(640, 300),
    scenarios: _edgeScenes,
  ),
  _Variant(
    'contrast-light',
    Brightness.light,
    Size(856, 460),
    highContrast: true,
    scenarios: _contrastScenes,
  ),
  _Variant(
    'contrast-dark',
    Brightness.dark,
    Size(856, 460),
    highContrast: true,
    scenarios: _contrastScenes,
  ),
];

void main() {
  if (!Platform.isMacOS) {
    test('Composer captures require macOS rendering', () {}, skip: true);
    return;
  }
  ConfigurationCaptureBinding();
  setUpAll(() async {
    await loadVisualCaptureFonts();
    if (_evidenceDirectory.isEmpty) return;
    if (_evidenceDirectory.split('/').contains('before')) {
      throw StateError(
        'The redesign before evidence is immutable. Use after/.',
      );
    }
    final directory = Directory(_evidenceDirectory);
    await directory.create(recursive: true);
    await File('${directory.path}/capture-manifest.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'renderer': 'Flutter widget production components with fixture state',
        'hostOS': Platform.operatingSystemVersion,
        'variants': [
          for (final variant in _variants)
            {
              'name': variant.name,
              'logicalWidth': variant.size.width,
              'logicalHeight': variant.size.height,
              'pixelRatio': variant.pixelRatio,
              'textScale': variant.textScale,
              'brightness': variant.brightness.name,
              'highContrast': variant.highContrast,
              'autofocus': variant.autofocus,
              'scenarios': variant.scenarios.map((s) => s.name).toList(),
            },
        ],
      }),
    );
  });

  for (final variant in _variants) {
    for (final scenario in variant.scenarios) {
      testWidgets(
        'Composer redesign ${variant.name} ${scenario.name}',
        (tester) async {
          tester.view.devicePixelRatio = variant.pixelRatio;
          tester.view.physicalSize = variant.size * variant.pixelRatio;
          addTearDown(tester.view.reset);
          String? clipboard;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                clipboard = (call.arguments as Map)['text'] as String;
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          final fixture = ComposerRedesignFixture(scenario);
          final controller = fixture.controller;
          addTearDown(fixture.dispose);
          final boundaryKey = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundaryKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: withVisualCaptureFonts(
                  buildIanvsTerminalTheme(
                    variant.brightness,
                    platform: TargetPlatform.macOS,
                  ),
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(variant.textScale),
                    highContrast: variant.highContrast,
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: TerminalComposerView(
                        controller: controller,
                        targetLabel: fixture.targetLabel,
                        autofocus: variant.autofocus,
                        chinese: true,
                        onUseTerminal: () {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          fixture.activate();
          // Fixed frames also capture pending loading/sending states without
          // pumpAndSettle waiting forever for an intentional progress indicator.
          await tester.pump(const Duration(milliseconds: 150));
          fixture.revealSelection();
          await tester.pump(const Duration(milliseconds: 150));
          await tester.pump();
          if (scenario == ComposerRedesignScenario.moreMenu ||
              scenario == ComposerRedesignScenario.copyFeedback ||
              scenario == ComposerRedesignScenario.shortcutHelp) {
            await tester.tap(find.byKey(const Key('composer-more-actions')));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            if (scenario == ComposerRedesignScenario.copyFeedback) {
              await tester.tap(find.byKey(const Key('composer-copy-draft')));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 300));
              expect(clipboard, 'git');
              expect(controller.editor.text, 'git');
              expect(
                find.byKey(const Key('composer-feedback')),
                findsOneWidget,
              );
            }
            if (scenario == ComposerRedesignScenario.shortcutHelp) {
              final help = find.byKey(const Key('composer-shortcut-help'));
              await tester.ensureVisible(help);
              await tester.pump();
              await tester.tap(help);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 300));
              expect(find.byType(AlertDialog), findsOneWidget);
            }
          }
          if (scenario == ComposerRedesignScenario.completionDetails &&
              find
                  .byKey(const Key('composer-completion-detail-action'))
                  .evaluate()
                  .isNotEmpty) {
            await tester.tap(
              find.byKey(const Key('composer-completion-detail-action')),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(find.byType(AlertDialog), findsOneWidget);
          }
          if (_evidenceDirectory.isNotEmpty) {
            await tester.runAsync(() async {
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(
                pixelRatio: variant.pixelRatio,
              );
              try {
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '$_evidenceDirectory/${variant.name}-${scenario.name}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }
          _verifyFixture(fixture);
          expect(tester.takeException(), isNull);
          _expectWithinViewport(tester, 'composer-editor', variant.size);
          _expectWithinViewport(
            tester,
            'composer-primary-action',
            variant.size,
          );
          _expectWithinViewport(tester, 'composer-more-actions', variant.size);
          for (final key in [
            'composer-history-list',
            'composer-completion-list',
            'composer-completion-detail',
            'composer-copy-draft',
          ]) {
            if (find.byKey(Key(key)).evaluate().isNotEmpty) {
              _expectWithinViewport(tester, key, variant.size);
            }
          }
          fixture.finish();
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
        },
        variant: const TargetPlatformVariant({TargetPlatform.macOS}),
      );
    }
  }
}

void _expectWithinViewport(WidgetTester tester, String key, Size size) {
  final finder = find.byKey(Key(key));
  expect(finder, findsOneWidget);
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(-.5), reason: '$key clips left');
  expect(rect.top, greaterThanOrEqualTo(-.5), reason: '$key clips above');
  expect(
    rect.right,
    lessThanOrEqualTo(size.width + .5),
    reason: '$key clips right',
  );
  expect(
    rect.bottom,
    lessThanOrEqualTo(size.height + .5),
    reason: '$key clips below',
  );
  expect(rect.width, greaterThan(0));
  expect(rect.height, greaterThan(0));
}

void _verifyFixture(ComposerRedesignFixture fixture) {
  final controller = fixture.controller;
  if (fixture.hasCompletionMenu) {
    expect(controller.completionMenuOpen, isTrue);
    expect(controller.selectedIndex, greaterThanOrEqualTo(0));
  }
  if (fixture.hasHistoryMenu) expect(controller.historyOpen, isTrue);
  switch (fixture.scenario) {
    case ComposerRedesignScenario.history:
    case ComposerRedesignScenario.longHistory:
      expect(controller.historyItems, isNotEmpty);
    case ComposerRedesignScenario.emptyHistory:
    case ComposerRedesignScenario.historyNoMatch:
      expect(controller.historyItems, isEmpty);
    case ComposerRedesignScenario.suggestion:
      expect(controller.inlineSuggestion, isNotEmpty);
    case ComposerRedesignScenario.unknown:
    case ComposerRedesignScenario.unknownLoading:
      expect(controller.ownership, ComposerOwnership.unknown);
      expect(controller.pendingSubmission, isNotNull);
      expect(controller.status, 'unknown_outcome');
      if (fixture.scenario == ComposerRedesignScenario.unknownLoading) {
        expect(controller.loading, isTrue);
      }
    case ComposerRedesignScenario.rejected:
      expect(controller.status, 'submission_rejected');
    case ComposerRedesignScenario.submitting:
      expect(controller.ownership, ComposerOwnership.submitting);
    case ComposerRedesignScenario.loading:
      expect(controller.loading, isTrue);
    case ComposerRedesignScenario.selection:
      expect(controller.status, 'completion_selection');
    case ComposerRedesignScenario.noCompletions:
      expect(controller.status, 'no_completions');
    case ComposerRedesignScenario.unavailable:
      expect(controller.status, 'completion_unavailable');
    case ComposerRedesignScenario.unsupportedContext:
      expect(controller.status, 'unsupported_context');
    case ComposerRedesignScenario.automaticSuggestions:
      expect(controller.localSuggestions, isTrue);
    case ComposerRedesignScenario.empty:
    case ComposerRedesignScenario.multiline:
    case ComposerRedesignScenario.draft:
    case ComposerRedesignScenario.running:
    case ComposerRedesignScenario.suspended:
    case ComposerRedesignScenario.longPath:
    case ComposerRedesignScenario.longAlias:
    case ComposerRedesignScenario.completionDetails:
    case ComposerRedesignScenario.completion:
    case ComposerRedesignScenario.moreMenu:
    case ComposerRedesignScenario.copyFeedback:
    case ComposerRedesignScenario.shortcutHelp:
      break;
  }
}

class _Variant {
  const _Variant(
    this.name,
    this.brightness,
    this.size, {
    this.pixelRatio = 1,
    this.textScale = 1,
    this.highContrast = false,
    this.autofocus = true,
    this.scenarios = ComposerRedesignScenario.values,
  });

  final String name;
  final Brightness brightness;
  final Size size;
  final double pixelRatio;
  final double textScale;
  final bool highContrast;
  final bool autofocus;
  final List<ComposerRedesignScenario> scenarios;
}
