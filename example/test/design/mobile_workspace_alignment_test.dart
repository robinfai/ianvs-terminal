import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import '../ai/terminal_ai_test.dart' show FakeApi, FakeTerminal, MemoryAiStore;
import '../helpers/pump_app.dart';
import 'configuration_capture_binding.dart';
import 'ui_review_capture.dart';
import 'visual_capture_fonts.dart';

void main() {
  ConfigurationCaptureBinding();
  setUpAll(loadVisualCaptureFonts);
  for (final size in [
    const Size(320, 740),
    const Size(402, 874),
    const Size(874, 402),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'Block and AI preserve compact drafts ${size.width} ${brightness.name}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.reset);
          final boundary = GlobalKey();
          final focus = FocusNode();
          var submissions = 0;
          final composer =
              TerminalComposerController(
                targetId: 'review',
                provider: (query, _) async => CompletionBatch(query, const []),
                submit: (_) async {
                  submissions++;
                  return ComposerSubmissionOutcome.accepted;
                },
              )..updateShell(
                contextKey: 'ready',
                cwd: '/srv/review',
                dialect: 'zsh',
                lease: 'review-lease',
                ownership: ComposerOwnership.ready,
              );
          final blocks = CommandBlockController(
            request: (_) => {'blocks': <Object?>[]},
          );
          final settings = AiSettingsController(MemoryAiStore());
          await settings.loaded;
          final terminal = FakeTerminal();
          final ai = TerminalAiController(
            settings: settings,
            terminal: terminal,
            api: FakeApi(),
          );
          await ai.refreshContext();
          addTearDown(() {
            focus.dispose();
            composer.dispose();
            blocks.dispose();
            ai.dispose();
            settings.dispose();
          });
          Future<void> mount(Widget child) async {
            await tester.pumpApp(
              Builder(
                builder: (context) => Theme(
                  data: withVisualCaptureFonts(Theme.of(context)),
                  child: RepaintBoundary(
                    key: boundary,
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surface,
                      child: child,
                    ),
                  ),
                ),
              ),
              platform: TargetPlatform.iOS,
              locale: const Locale('zh'),
              brightness: brightness,
            );
            await tester.pumpAndSettle();
          }

          await mount(
            Column(
              children: [
                Expanded(
                  child: TerminalCommandBlocksView(
                    controller: blocks,
                    chinese: true,
                    onReinput: (text) {
                      composer.editor.text = text;
                      focus.requestFocus();
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: TerminalComposerView(
                    controller: composer,
                    targetLabel: 'review',
                    focusNode: focus,
                    chinese: true,
                    onAskAi: (_) => submissions++,
                  ),
                ),
              ],
            ),
          );
          final surface = find.byKey(const Key('composer-surface'));
          final editor = find.byKey(const Key('composer-editor'));
          expect(tester.getSize(surface).height, lessThanOrEqualTo(56));
          await captureUiReview(
            tester,
            boundary,
            'block-empty-${size.width.toInt()}-${brightness.name}',
          );
          await tester.enterText(editor, '中文草稿\n第二行');
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(editor).maxLines, greaterThan(1));
          composer.editor.selection = const TextSelection(
            baseOffset: 0,
            extentOffset: 4,
          );
          await tester.pump();
          final saved = composer.editor.value;
          await tester.tap(find.byKey(const Key('composer-dismiss-keyboard')));
          await tester.pumpAndSettle();
          expect(composer.editor.value, saved);
          final blockHeight = tester.getSize(surface).height;
          expect(blockHeight, lessThanOrEqualTo(56));
          expect(
            tester
                .getSize(find.byKey(const Key('composer-primary-action')))
                .height,
            greaterThanOrEqualTo(44),
          );
          await captureUiReview(
            tester,
            boundary,
            'block-draft-${size.width.toInt()}-${brightness.name}',
          );
          await tester.tap(find.byKey(const Key('composer-expand-draft')));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const Key('composer-draft-editor')),
                )
                .controller!
                .text,
            saved.text,
          );
          await tester.tap(find.byKey(const Key('composer-draft-done')));
          await tester.pumpAndSettle();
          expect(composer.editor.text, saved.text);
          expect(submissions, 0);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await mount(
            TerminalAiWorkspace(
              controller: ai,
              compactMobile: true,
              onClose: () {},
            ),
          );
          await captureUiReview(
            tester,
            boundary,
            'ai-empty-${size.width.toInt()}-${brightness.name}',
          );
          ai.setDraft(saved.text);
          await tester.pumpAndSettle();
          final aiHeight = tester
              .getSize(find.byKey(const Key('ai-mobile-composer')))
              .height;
          expect(aiHeight, lessThanOrEqualTo(56));
          expect(aiHeight, blockHeight);
          expect(ai.draft, saved.text);
          expect(terminal.writes, isEmpty);
          await captureUiReview(
            tester,
            boundary,
            'ai-draft-${size.width.toInt()}-${brightness.name}',
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      );
    }
  }
}
