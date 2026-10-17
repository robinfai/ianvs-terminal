import 'dart:ui' as ui;

import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import '../ai/terminal_ai_test.dart' show FakeApi, FakeTerminal, MemoryAiStore;
import '../helpers/pump_app.dart';
import 'configuration_capture_binding.dart';
import 'ui_review_capture.dart';
import 'visual_capture_fonts.dart';

void main() {
  ConfigurationCaptureBinding();
  setUpAll(() => loadVisualCaptureFonts(productionIcons: true));
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
                      child: Scaffold(body: child),
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
                  child: ListenableBuilder(
                    listenable: focus,
                    builder: (context, child) => ConstrainedBox(
                      // Match the Shell's short landscape space above an IME.
                      constraints: BoxConstraints(
                        maxHeight:
                            size.width > size.height &&
                                focus.hasFocus &&
                                tester.view.viewInsets.bottom > 0
                            ? 120
                            : double.infinity,
                      ),
                      child: child,
                    ),
                    child: TerminalComposerView(
                      controller: composer,
                      targetLabel: 'review',
                      focusNode: focus,
                      chinese: true,
                      onAskAi: (_) => submissions++,
                    ),
                  ),
                ),
              ],
            ),
          );
          void expectCentered(String key) {
            final button = find.byKey(Key(key));
            final icon = find.descendant(
              of: button,
              matching: find.byType(Icon),
            );
            expect(icon, findsOneWidget);
            expect(
              (tester.getCenter(icon) - tester.getCenter(button)).distance,
              lessThan(.01),
              reason: '$key icon must be centered in its circular action',
            );
          }

          Future<void> expectPaintedCentered(String key) async {
            final center = tester.getCenter(find.byKey(Key(key)));
            await tester.runAsync(() async {
              final render =
                  boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await render.toImage(pixelRatio: 3);
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              final cx = (center.dx * 3).round();
              final cy = (center.dy * 3).round();
              final xs = <int>[];
              final ys = <int>[];
              // Inspect white glyph ink inside the blue circle, excluding the
              // page outside its edge. Widget bounds alone miss font bearings.
              for (var y = cy - 40; y <= cy + 40; y++) {
                for (var x = cx - 40; x <= cx + 40; x++) {
                  if ((x - cx) * (x - cx) + (y - cy) * (y - cy) > 40 * 40) {
                    continue;
                  }
                  final offset = (y * image.width + x) * 4;
                  if (bytes.getUint8(offset) > 230 &&
                      bytes.getUint8(offset + 1) > 230 &&
                      bytes.getUint8(offset + 2) > 230) {
                    xs.add(x);
                    ys.add(y);
                  }
                }
              }
              image.dispose();
              expect(xs, isNotEmpty);
              xs.sort();
              ys.sort();
              expect(
                ((xs.first + xs.last) / 2 - cx).abs() / 3,
                lessThanOrEqualTo(1.5),
                reason: '$key painted horizontal center',
              );
              expect(
                ((ys.first + ys.last) / 2 - cy).abs() / 3,
                lessThanOrEqualTo(1.5),
                reason: '$key painted vertical center',
              );
            });
          }

          Future<void> exerciseIntentMenu(
            String menuKey,
            String editorKey,
          ) async {
            final editorFinder = find.byKey(Key(editorKey));
            final keyboardHeight = size.height > 500 ? 300.0 : 180.0;
            tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
            await tester.tap(editorFinder);
            await tester.pumpAndSettle();
            final field = tester.widget<TextField>(editorFinder);
            final draft = field.controller!.value;
            final focusNode = field.focusNode!;
            expect(focusNode.hasFocus, isTrue);
            await tester.tap(find.byKey(Key(menuKey)));
            await tester.pumpAndSettle();
            expect(
              focusNode.hasFocus,
              isTrue,
              reason: 'Opening the menu must not collapse the keyboard',
            );
            final items = find.byType(MenuItemButton);
            expect(items, findsNWidgets(3));
            Rect menuRect() => tester.getRect(
              find
                  .ancestor(of: items.first, matching: find.byType(Material))
                  .first,
            );
            expect(
              menuRect().bottom,
              lessThanOrEqualTo(size.height - keyboardHeight),
            );
            // The OS can dismiss the keyboard independently while the menu is
            // open. Its anchor must follow the compact editor layout.
            focusNode.unfocus();
            for (final inset in [keyboardHeight / 2, 0.0]) {
              tester.view.viewInsets = FakeViewPadding(bottom: inset);
              await tester.pumpAndSettle();
              expect(items, findsNWidgets(3));
              final anchor = tester.getRect(find.byKey(Key(menuKey)));
              expect(
                (anchor.top - menuRect().bottom).abs(),
                lessThan(14),
                reason: 'Menu must follow the button at keyboard inset $inset',
              );
              expect(menuRect().bottom, lessThanOrEqualTo(size.height - inset));
            }
            expect(field.controller!.value, draft);
            await tester.tap(items.at(1));
            await tester.pumpAndSettle();
            expect(items, findsNothing);
            expect(field.controller!.value, draft);
            await tester.tap(find.byKey(Key(menuKey)));
            await tester.pumpAndSettle();
            expect(items, findsNWidgets(3));
            await tester.tapAt(const Offset(5, 5));
            await tester.pumpAndSettle();
            expect(items, findsNothing);
            expect(field.controller!.value, draft);
            focusNode.unfocus();
            tester.view.viewInsets = FakeViewPadding.zero;
            await tester.pumpAndSettle();
          }

          expectCentered('composer-primary-action');
          for (final intent in [
            InputIntentChoice.command,
            InputIntentChoice.ai,
          ]) {
            composer.chooseInputIntent(intent);
            await tester.enterText(
              find.byKey(const Key('composer-editor')),
              'ls',
            );
            await tester.pumpAndSettle();
            expectCentered('composer-primary-action');
            await expectPaintedCentered('composer-primary-action');
            focus.unfocus();
            await tester.pumpAndSettle();
            expectCentered('composer-primary-action');
            await expectPaintedCentered('composer-primary-action');
          }
          composer.chooseInputIntent(InputIntentChoice.automatic);
          composer.clearDraft();
          await tester.pumpAndSettle();
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
          await exerciseIntentMenu('composer-input-intent', 'composer-editor');
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
          expectCentered('ai-send');
          ai.setDraft(saved.text);
          await tester.pumpAndSettle();
          final aiHeight = tester
              .getSize(find.byKey(const Key('ai-mobile-composer')))
              .height;
          expect(aiHeight, lessThanOrEqualTo(56));
          expect(aiHeight, blockHeight);
          expectCentered('ai-send');
          await expectPaintedCentered('ai-send');
          expect(ai.draft, saved.text);
          await exerciseIntentMenu('ai-input-intent', 'ai-prompt');
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
