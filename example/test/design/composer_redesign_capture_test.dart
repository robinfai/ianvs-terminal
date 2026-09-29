import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/ui/app_ui.dart';
import 'package:app/ui/previews/composer_preview_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'configuration_capture_binding.dart';
import 'visual_capture_fonts.dart';

// Optional evidence export, relative to example/. Without this define the same
// matrix still verifies rendering and state setup without writing any files.
const _evidenceDirectory = String.fromEnvironment('COMPOSER_EVIDENCE_DIR');

enum _Scenario {
  empty,
  completion,
  history,
  suggestion,
  multiline,
  draft,
  running,
  submitting,
  suspended,
  unknown,
  rejected,
  selection,
  noCompletions,
  unavailable,
  emptyHistory,
  loading,
}

void main() {
  if (!Platform.isMacOS) {
    test('Composer captures require macOS rendering', () {}, skip: true);
    return;
  }
  ConfigurationCaptureBinding();
  setUpAll(loadVisualCaptureFonts);

  for (final variant in [
    (name: 'light', brightness: Brightness.light, size: const Size(920, 560)),
    (name: 'dark', brightness: Brightness.dark, size: const Size(920, 560)),
    (
      name: 'narrow-2x',
      brightness: Brightness.dark,
      size: const Size(360, 740),
    ),
  ]) {
    for (final scenario in _Scenario.values) {
      testWidgets('Composer redesign ${variant.name} ${scenario.name}', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = variant.size;
        addTearDown(tester.view.reset);
        final fixture = _Fixture(scenario);
        final controller = fixture.controller;
        addTearDown(controller.dispose);
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
                  textScaler: TextScaler.linear(
                    variant.name == 'narrow-2x' ? 2 : 1,
                  ),
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
                      targetLabel: 'Local Shell',
                      autofocus: true,
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
        // Fixed frames also capture animated loading/sending states without
        // pumpAndSettle waiting forever for an intentional progress indicator.
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pump(const Duration(milliseconds: 150));
        if (scenario == _Scenario.completion) {
          controller.selectNext(1);
          await tester.pump();
        }
        fixture.verify();
        expect(tester.takeException(), isNull);
        if (_evidenceDirectory.isNotEmpty) {
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final output = File(
                '$_evidenceDirectory/${variant.name}-${scenario.name}.png',
              );
              await output.parent.create(recursive: true);
              await output.writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        fixture.finish();
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

class _Fixture {
  _Fixture(this.scenario) {
    final previewScenario = switch (scenario) {
      _Scenario.completion => ComposerPreviewScenario.completion,
      _Scenario.history => ComposerPreviewScenario.history,
      _Scenario.suggestion => ComposerPreviewScenario.suggestion,
      _ => null,
    };
    if (previewScenario != null) {
      controller = createComposerPreviewController(previewScenario);
      return;
    }
    controller =
        TerminalComposerController(
          targetId: 'redesign-fixture',
          text: switch (scenario) {
            _Scenario.empty || _Scenario.emptyHistory => '',
            _Scenario.multiline =>
              'for file in ./reports/*.json; do\n  jq . "\$file"\ndone',
            _Scenario.selection => 'cd ../../../',
            _Scenario.noCompletions => 'cd ./missing-',
            _Scenario.loading || _Scenario.unavailable => 'git che',
            _ => 'npm run build',
          },
          provider: (query, _) async {
            if (scenario == _Scenario.loading) {
              await _completion.future;
            }
            if (scenario == _Scenario.unavailable) {
              throw StateError('Fixture completion provider unavailable');
            }
            return CompletionBatch(query, const []);
          },
          submit: (_) async => switch (scenario) {
            _Scenario.unknown => ComposerSubmissionOutcome.unknown,
            _Scenario.rejected => ComposerSubmissionOutcome.rejected,
            _Scenario.submitting => await _submission.future,
            _ => ComposerSubmissionOutcome.accepted,
          },
        )..updateShell(
          contextKey: 'redesign-ready',
          cwd: '~/workspace/ianvs-terminal',
          dialect: 'zsh',
          lease: 'redesign-lease',
          ownership: ComposerOwnership.ready,
        );
  }

  final _Scenario scenario;
  late final TerminalComposerController controller;
  final _submission = Completer<ComposerSubmissionOutcome>();
  final _completion = Completer<void>();

  void activate() {
    switch (scenario) {
      case _Scenario.completion:
      case _Scenario.loading:
        controller.requestCompletions();
      case _Scenario.history:
      case _Scenario.emptyHistory:
        controller.openHistory();
      case _Scenario.selection:
        controller.editor.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.editor.text.length,
        );
        controller.completeOnTab();
      case _Scenario.noCompletions:
      case _Scenario.unavailable:
        controller.completeOnTab();
      case _Scenario.unknown:
      case _Scenario.rejected:
      case _Scenario.submitting:
        unawaited(controller.run());
      case _Scenario.draft:
      case _Scenario.running:
      case _Scenario.suspended:
        controller.updateShell(
          contextKey: 'redesign-${scenario.name}',
          cwd: controller.cwd,
          dialect: 'zsh',
          lease: null,
          ownership: switch (scenario) {
            _Scenario.draft => ComposerOwnership.draft,
            _Scenario.running => ComposerOwnership.running,
            _ => ComposerOwnership.suspended,
          },
        );
      case _Scenario.empty:
      case _Scenario.suggestion:
      case _Scenario.multiline:
        break;
    }
  }

  void verify() {
    switch (scenario) {
      case _Scenario.completion:
        expect(controller.completionMenuOpen, isTrue);
        expect(controller.selectedIndex, greaterThanOrEqualTo(0));
      case _Scenario.history:
        expect(controller.historyOpen, isTrue);
        expect(controller.historyItems, isNotEmpty);
      case _Scenario.emptyHistory:
        expect(controller.historyOpen, isTrue);
        expect(controller.historyItems, isEmpty);
      case _Scenario.suggestion:
        expect(controller.inlineSuggestion, isNotEmpty);
      case _Scenario.unknown:
        expect(controller.ownership, ComposerOwnership.unknown);
        expect(controller.pendingSubmission, isNotNull);
      case _Scenario.rejected:
        expect(controller.status, 'submission_rejected');
      case _Scenario.submitting:
        expect(controller.ownership, ComposerOwnership.submitting);
      case _Scenario.loading:
        expect(controller.loading, isTrue);
      case _Scenario.selection:
        expect(controller.status, 'completion_selection');
      case _Scenario.noCompletions:
        expect(controller.status, 'no_completions');
      case _Scenario.unavailable:
        expect(controller.status, 'completion_unavailable');
      case _Scenario.empty:
      case _Scenario.multiline:
      case _Scenario.draft:
      case _Scenario.running:
      case _Scenario.suspended:
        break;
    }
  }

  void finish() {
    if (!_submission.isCompleted) {
      _submission.complete(ComposerSubmissionOutcome.accepted);
    }
    if (!_completion.isCompleted) _completion.complete();
  }
}
