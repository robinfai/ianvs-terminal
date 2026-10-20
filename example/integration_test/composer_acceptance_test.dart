import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/app.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal_composer/terminal_mode.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/macos_integration_test_lifecycle.dart';
import '../test/support/memory_app_preferences_repository.dart';
import '../test/support/memory_local_terminal_config_repository.dart';
import '../test/support/memory_profile_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Composer edits locally, accepts candidates, submits and recovers focus',
    (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      final home = await Directory.systemTemp.createTemp('composer-ui-');
      await File('${home.path}/.zshrc').writeAsString(
        "PROMPT='composer> '\nRPROMPT=''\nHISTSIZE=100\nalias gc='git checkout'\n"
        'for i in {1..60}; do print -s -- "echo scroll-fixture-\$i"; done\n'
        "print -s -- 'printf history-example'\n",
      );
      await File('${home.path}/hello world.txt').writeAsString('fixture');
      await Directory(
        '${home.path}/documents/nested folder',
      ).create(recursive: true);
      await Directory(
        '${home.path}/pkg/application/handlers',
      ).create(recursive: true);
      await Directory('${home.path}/My files/中文目录').create(recursive: true);
      final profile = TerminalProfile(
        id: 'composer-test',
        name: 'Composer Test',
        shell: '/bin/zsh',
        cwd: home.path,
        env: {'HOME': home.path, 'ZDOTDIR': home.path, 'LANG': 'en_US.UTF-8'},
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(NativePtyBackend.load()),
          profileRepositoryProvider.overrideWithValue(
            MemoryProfileRepository(
              TerminalProfilesDocument(profiles: [profile]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            MemoryAppPreferencesRepository(null),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            MemoryLocalTerminalConfigRepository(null),
          ),
          shellAnimationsEnabledProvider.overrideWithValue(false),
          shellNotificationSenderProvider.overrideWithValue(
            ({required title, body, identifier, expiresAfterMs}) async {},
          ),
        ],
      );
      final captureKey = GlobalKey();
      Future<void> capture(String name) async {
        const directory = String.fromEnvironment('BLOCKS_NATIVE_EVIDENCE_DIR');
        if (directory.isEmpty) return;
        await tester.pump();
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File(
          '$directory/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        final sessionId = container
            .read(sessionControllerProvider)
            .activeSessionId;
        if (sessionId != null) {
          await container
              .read(sessionControllerProvider.notifier)
              .closeSession(sessionId);
        }
        container.dispose();
        await home.delete(recursive: true);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: captureKey,
            child: const IanvsTerminalApp(),
          ),
        ),
      );
      await until(
        tester,
        () => container.read(sessionControllerProvider).activeSessionId != null,
      );
      final id = container.read(sessionControllerProvider).activeSessionId!;
      await until(
        tester,
        () => container
            .read(sessionControllerProvider)
            .tabs
            .first
            .activePane
            .terminalMode
            .canUseBlocks,
      );
      expect(find.byKey(Key('composer-toggle-$id')), findsNothing);
      expect(find.byType(TerminalAiWorkspace), findsNothing);
      final normalTerminalSize = tester.getSize(find.byType(TerminalViewport));
      Future<void> chooseMode(String mode, {String? sessionId}) async {
        final targetId = sessionId ?? id;
        await tester.tap(
          find.byKey(Key('shell-tab-$targetId')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await capture('terminal-mode-menu');
        await tester.tap(find.byKey(Key('terminal-mode-$mode-$targetId')));
        await tester.pumpAndSettle();
      }

      await chooseMode('blocks');
      final editor = find.byKey(const Key('ai-prompt'));
      await until(
        tester,
        () => find.byType(TerminalAiWorkspace).evaluate().isNotEmpty,
      );
      final model = tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .commandSession!
          .draftEditor!;
      final ai = tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .controller;
      await until(
        tester,
        () =>
            model.ownership == ComposerOwnership.ready &&
            !ai.busy &&
            !ai.checkingTerminal,
      );
      await until(
        tester,
        () => find.byType(TerminalCommandBlocksView).evaluate().isNotEmpty,
      );
      // Golden fixtures register a font named "monospace"; a native macOS
      // host need not provide that alias. Verify the actual fallback remains
      // fixed-width, rather than silently rendering shell text as UI prose.
      final commandStyle = tester.widget<TextField>(editor).style!;
      double commandWidth(String text) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: commandStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }

      expect(
        commandWidth('iiiiiiii'),
        closeTo(commandWidth('WWWWWWWW'), .01),
        reason: 'Native Composer command text must resolve to a monospace font',
      );
      final surface = find.byKey(const Key('ai-command-surface'));
      final emptyHeight = tester.getSize(surface).height;
      for (final text in ['pwd', '中文', 'echo 中文 😀', '']) {
        await tester.enterText(editor, text);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.getSize(surface).height, closeTo(emptyHeight, .01));
      }

      // History comes from this shell, before Composer has submitted anything.
      final initialLease = model.readyLease;
      await tester.enterText(editor, 'printf');
      await until(tester, () => model.inlineSuggestion == ' history-example');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(model.editor.text, 'printf history-example');
      expect(model.readyLease, initialLease);
      await tester.enterText(editor, 'history-example');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(model.historyItems, ['printf history-example']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(model.editor.text, 'history-example');
      await tester.enterText(editor, 'printf');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(model.editor.text, 'printf history-example');
      expect(model.readyLease, initialLease);
      await tester.enterText(editor, 'g');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await until(
        tester,
        () => model.items.any(
          (item) => item.kind == 'alias' && item.label == 'gc',
        ),
      );
      final alias = model.items.firstWhere((item) => item.label == 'gc');
      expect(alias.detail, 'git checkout');
      model.highlightCompletion(alias);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(model.editor.text, 'gc');
      expect(model.readyLease, initialLease);
      await tester.enterText(editor, 'git che --help');
      model.editor.selection = const TextSelection.collapsed(offset: 7);
      await until(tester, () => model.items.any((e) => e.label == 'checkout'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(model.editor.text, 'git checkout --help');
      expect(model.ownership, ComposerOwnership.ready);

      // Explicit Tab works with automatic local suggestions still disabled.
      final lease = model.readyLease;
      expect(model.localSuggestions, isFalse);
      await tester.enterText(editor, 'ls ./');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await until(tester, () => !model.loading && model.selectedIndex >= 0);
      expect(model.editor.text, 'ls ./');
      expect(model.items.any((e) => e.label == './documents/'), isTrue);
      expect(model.items.any((e) => e.label == './hello world.txt'), isTrue);
      while (model.items[model.selectedIndex].label != './documents/') {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(model.editor.text, 'ls ./documents/');
      // A unique nested directory inserts immediately, including safe quoting.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await until(tester, () => model.editor.text.contains('nested'));
      expect(model.editor.text, "ls './documents/nested folder/'");
      expect(model.localSuggestions, isFalse);
      expect(model.ownership, ComposerOwnership.ready);
      expect(model.readyLease, lease);

      model.toggleLocalSuggestions();
      await tester.enterText(editor, 'cat he');
      await until(
        tester,
        () => model.items.any((e) => e.label == 'hello world.txt'),
      );
      expect(model.items.first.source, 'local:files');
      model.toggleLocalSuggestions();
      await tester.enterText(editor, 'cd pkg/application/handlers');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await until(
        tester,
        () =>
            model.ownership == ComposerOwnership.ready &&
            !ai.busy &&
            !ai.checkingTerminal &&
            model.editor.text.isEmpty &&
            model.cwd.endsWith('/pkg/application/handlers'),
      );
      final pathLease = model.readyLease;
      await tester.enterText(editor, 'cd ../../../');
      model.editor.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 12,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(model.status, 'completion_selection');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      // Integration-test key events do not pass through NSTextInputContext.
      // Deliver the native macOS selector as the platform would for this key.
      tester
          .state<EditableTextState>(
            find.descendant(of: editor, matching: find.byType(EditableText)),
          )
          .performSelector('moveRight:');
      expect(model.editor.selection, const TextSelection.collapsed(offset: 12));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await until(
        tester,
        () =>
            !model.loading &&
            model.items.any((item) => item.label == '../../../documents/'),
        diagnostics: () =>
            'text=${model.editor.text}; selection=${model.editor.selection}; status=${model.status}; owner=${model.ownership}; candidates=${model.items.map((i) => i.label).join(', ')}',
      );
      expect(model.items.every((item) => item.kind == 'directory'), isTrue);
      await tester.enterText(editor, 'cd ../../../docu');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await until(
        tester,
        () => model.editor.text == 'cd ../../../documents/',
        diagnostics: () =>
            'text=${model.editor.text}; status=${model.status}; owner=${model.ownership}; '
            'loading=${model.loading}; focus=${tester.widget<TextField>(editor).focusNode!.hasFocus}; '
            'candidates=${model.items.map((item) => item.label).join(', ')}',
      );
      expect(model.readyLease, pathLease);
      await tester.enterText(editor, 'cd ${home.path}/docu');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await until(
        tester,
        () => model.editor.text == 'cd ${home.path}/documents/',
      );
      expect(model.readyLease, pathLease);
      await tester.enterText(editor, 'cd ~/My');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await until(tester, () => model.editor.text == "cd ~/'My files/'");
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await until(tester, () => model.editor.text == "cd ~/'My files/中文目录/'");
      expect(model.localSuggestions, isFalse);
      expect(model.readyLease, pathLease);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await until(
        tester,
        () =>
            model.ownership == ComposerOwnership.ready &&
            !ai.busy &&
            !ai.checkingTerminal &&
            model.cwd.endsWith('/My files/中文目录'),
      );
      await tester.enterText(
        editor,
        "export COMPOSER_TEST=retained; print 'Composer 中文 😀'",
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await until(
        tester,
        () =>
            model.ownership == ComposerOwnership.ready &&
            !ai.busy &&
            !ai.checkingTerminal &&
            model.editor.text.isEmpty,
      );
      String terminalText() => container
          .read(sessionControllerProvider.notifier)
          .viewportFor(id)
          .frame
          .rows
          .map((r) => r.text)
          .join('\n');
      await until(tester, () => terminalText().contains('Composer 中文 😀'));
      final blocks = tester
          .widget<TerminalCommandBlocksView>(
            find.byType(TerminalCommandBlocksView),
          )
          .controller;
      await until(
        tester,
        () =>
            blocks.blocks.any((block) => block.command.contains('Composer 中文')),
      );
      final unicodeBlock = blocks.blocks.lastWhere(
        (block) => block.command.contains('Composer 中文'),
      );
      expect(
        await blocks.outputText(unicodeBlock.id),
        contains('Composer 中文 😀'),
      );
      expect(
        await blocks.outputText(unicodeBlock.id),
        isNot(contains('composer>')),
      );
      expect(tester.widget<TextField>(editor).focusNode!.hasFocus, isTrue);
      // Scroll over real PTY output, including multiple updates in a single
      // trackpad gesture. The content-sized terminal must leave the gesture
      // and its momentum with the enclosing transcript scroll position.
      await tester.enterText(
        editor,
        r'for i in {1..120}; do print "BLOCK_SCROLL:$i"; done',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await until(
        tester,
        () =>
            model.ownership == ComposerOwnership.ready &&
            !ai.busy &&
            !ai.checkingTerminal &&
            blocks.blocks.any(
              (block) =>
                  block.lines.any((line) => line.text == 'BLOCK_SCROLL:120'),
            ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final tallBlockId = blocks.blocks.last.id;
      expect(
        tester
            .getSize(find.byKey(ValueKey('command-block-$tallBlockId')))
            .height,
        lessThanOrEqualTo(normalTerminalSize.height / 3),
      );
      await capture('block-default-height');
      await tester.tap(find.byKey(ValueKey('block-expand-$tallBlockId')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .getSize(find.byKey(ValueKey('command-block-$tallBlockId')))
            .height,
        greaterThan(normalTerminalSize.height / 3),
      );
      await capture('block-expanded-height');
      // The expanded block initially contains only the native preview page.
      // Load its real output so the same output spans all six drag updates,
      // independently of the host window's height.
      blocks.page(tallBlockId, 0);
      await tester.pumpAndSettle();
      expect(
        blocks
            .displayBlock(blocks.blocks.singleWhere((b) => b.id == tallBlockId))
            .lines
            .length,
        greaterThanOrEqualTo(120),
      );
      final blockList = find.descendant(
        of: find.byType(TerminalCommandBlocksView),
        matching: find.byType(CommandTimelineView),
      );
      expect(blockList, findsOneWidget);
      final blockScroll = tester
          .widget<CommandTimelineView>(blockList)
          .controller;
      expect(blockScroll.positions, hasLength(1));
      // Expansion restores a reading anchor asynchronously. Wait for layout,
      // then place this gesture away from either edge: bouncing scroll physics
      // deliberately applies friction to deltas beyond minScrollExtent.
      await tester.pumpAndSettle();
      final position = blockScroll.position;
      expect(
        position.maxScrollExtent - position.minScrollExtent,
        greaterThan(680),
      );
      final expandedOutput = find.descendant(
        of: find.byKey(ValueKey('command-block-$tallBlockId')),
        matching: find.byType(TerminalViewport),
      );
      expect(expandedOutput, findsOneWidget);
      final listTop = tester.getTopLeft(blockList).dy;
      final outputStart =
          blockScroll.offset + tester.getTopLeft(expandedOutput).dy - listTop;
      final gestureStart = (outputStart + 600).clamp(
        position.minScrollExtent + 600,
        position.maxScrollExtent - 80,
      );
      // Keep every update inside this expanded output. A tall viewport's own
      // center can be offscreen even while its contents fill the whole window,
      // so a center-based hitTestable() finder is not a visibility test here.
      blockScroll.jumpTo(gestureStart);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(expandedOutput).dy,
        closeTo(listTop + outputStart - gestureStart, .5),
      );
      final outputPoint = tester.getCenter(blockList);
      expect(tester.getRect(expandedOutput).contains(outputPoint), isTrue);
      final outputTrackpad = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await outputTrackpad.panZoomStart(outputPoint);
      await outputTrackpad.panZoomUpdate(
        outputPoint,
        pan: const Offset(0, 40),
        timeStamp: const Duration(milliseconds: 16),
      );
      await tester.pump(const Duration(milliseconds: 16));
      var outputOffset = blockScroll.offset;
      for (var step = 1; step <= 6; step++) {
        // Layout may correct scrollOffset while preserving the reading anchor.
        // Measure the same visible output, not that internal correction.
        final beforeY = tester.getTopLeft(expandedOutput).dy;
        await outputTrackpad.panZoomUpdate(
          outputPoint,
          pan: Offset(0, 40 + 64.0 * step),
          timeStamp: Duration(milliseconds: 16 + 16 * step),
        );
        await tester.pump(const Duration(milliseconds: 16));
        expect(blockScroll.position.outOfRange, isFalse);
        expect(tester.getRect(expandedOutput).contains(outputPoint), isTrue);
        debugPrint(
          'trackpad-measurement step=$step '
          'visible_delta=${tester.getTopLeft(expandedOutput).dy - beforeY} '
          'scroll_delta=${blockScroll.offset - outputOffset}',
        );
        expect(
          tester.getTopLeft(expandedOutput).dy,
          closeTo(beforeY + 64, .5),
          reason:
              'step $step; scrollOffset $outputOffset -> ${blockScroll.offset}',
        );
        expect(blockScroll.offset, lessThan(outputOffset));
        expect(blockScroll.position.isScrollingNotifier.value, isTrue);
        outputOffset = blockScroll.offset;
      }
      // Flutter expires velocity after 40 ms of wall-clock inactivity. A
      // native frame/assertion can exceed that on CI. Exercise such a pause,
      // then send a fresh final movement and release without a frame between.
      await tester.pump(const Duration(milliseconds: 60));
      final finalMovementStart = blockScroll.offset;
      await outputTrackpad.panZoomUpdate(
        outputPoint,
        pan: const Offset(0, 40 + 64.0 * 7),
        timeStamp: const Duration(milliseconds: 128),
      );
      final releaseOffset = blockScroll.offset;
      await outputTrackpad.panZoomEnd(
        timeStamp: const Duration(milliseconds: 144),
      );
      expect(releaseOffset, closeTo(finalMovementStart - 64, .5));
      expect(blockScroll.position.isScrollingNotifier.value, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      debugPrint(
        'trackpad-inertia-measurement: '
        '${releaseOffset - blockScroll.offset} logical pixels after release',
      );
      expect(blockScroll.offset, lessThan(releaseOffset - 10));
      // End inertia before the next independent keyboard interaction.
      blockScroll.jumpTo(blockScroll.offset);
      await tester.tap(editor);
      await tester.enterText(editor, r'print COMPOSER_VALUE:$COMPOSER_TEST');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await until(
        tester,
        () => terminalText().contains('COMPOSER_VALUE:retained'),
      );
      await until(
        tester,
        () =>
            model.ownership == ComposerOwnership.ready &&
            !ai.busy &&
            !ai.checkingTerminal,
        diagnostics: () =>
            'after expanded block: owner=${model.ownership}; draft=${model.editor.text}; status=${model.status}; mode=${container.read(sessionControllerProvider).tabs.first.activePane.terminalMode.unavailableReason}; output=${terminalText()}',
      );
      await tester.enterText(editor, '');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(model.historyItems.length, greaterThan(50));
      final historyList = find.byKey(const Key('composer-history-list'));
      final historyScroll = tester.widget<ListView>(historyList).controller!;
      final historyPoint = tester.getCenter(historyList);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: historyPoint);
      await mouse.moveTo(historyPoint + const Offset(1, 0));
      await tester.pumpAndSettle();
      final historySelection = model.historySelectedIndex;
      final trackpad = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await trackpad.panZoomStart(historyPoint);
      await trackpad.panZoomUpdate(
        historyPoint,
        pan: const Offset(0, 40),
        timeStamp: const Duration(milliseconds: 16),
      );
      await tester.pump(const Duration(milliseconds: 16));
      var previousOffset = historyScroll.offset;
      for (var step = 1; step <= 3; step++) {
        await trackpad.panZoomUpdate(
          historyPoint,
          pan: Offset(0, 40.0 + 60 * step),
          timeStamp: Duration(milliseconds: 16 + 16 * step),
        );
        await tester.pump(const Duration(milliseconds: 16));
        expect(historyScroll.offset, lessThan(previousOffset - 40));
        previousOffset = historyScroll.offset;
      }
      expect(model.historySelectedIndex, historySelection);
      expect(model.editor.text, isEmpty);
      await trackpad.panZoomEnd(timeStamp: const Duration(milliseconds: 80));
      await mouse.removePointer();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        find
            .descendant(
              of: historyList,
              matching: find.text(
                model.historyItems[model.historySelectedIndex],
                findRichText: true,
              ),
            )
            .hitTestable(),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      // Keep the real dock mounted at its submitted multiline height while
      // the PTY owns input. Ctrl+C must reach the running shell, then return
      // focus to the same editor once a new ready lease arrives.
      await tester.enterText(
        editor,
        'sleep 30;\nprint composer-layout-complete',
      );
      await tester.pump(const Duration(milliseconds: 300));
      final submittedHeight = tester.getSize(surface).height;
      expect(submittedHeight, greaterThan(emptyHeight));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await until(
        tester,
        () => model.ownership == ComposerOwnership.running && !ai.busy,
      );
      await until(tester, () => !ai.busy);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byKey(Key('composer-toggle-$id')), findsNothing);
      expect(tester.getSize(surface).height, closeTo(submittedHeight, .01));
      expect(tester.widget<TextField>(editor).readOnly, isTrue);
      expect(tester.widget<TextField>(editor).focusNode!.hasFocus, isFalse);
      await until(
        tester,
        () => find
            .byType(CommandBlockTerminal)
            .evaluate()
            .any(
              (element) =>
                  (element.widget as CommandBlockTerminal).block.running,
            ),
        diagnostics: () =>
            'owner=${model.ownership}; focus=${FocusManager.instance.primaryFocus}; '
            'scroll=${blockScroll.offset}/${blockScroll.position.maxScrollExtent}; '
            'blocks=${blocks.blocks.map((block) => '${block.id}:${block.command}:${block.running}').join(' | ')}; '
            'mounted=${find.byType(CommandBlockTerminal).evaluate().map((element) => (element.widget as CommandBlockTerminal).block.id).join(',')}',
      );
      final runningTerminal = tester.widget<CommandBlockTerminal>(
        find.byWidgetPredicate(
          (widget) => widget is CommandBlockTerminal && widget.block.running,
        ),
      );
      expect(runningTerminal.liveFocus!.hasFocus, isTrue);
      await capture('native-running');
      // Local editing remains inactive while the running block owns input.
      expect(model.localSuggestions, isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await until(
        tester,
        () =>
            model.ownership == ComposerOwnership.ready &&
            !ai.busy &&
            !ai.checkingTerminal,
      );
      await tester.pump();
      expect(tester.widget<TextField>(editor).readOnly, isFalse);
      expect(tester.widget<TextField>(editor).focusNode!.hasFocus, isTrue);
      expect(tester.getSize(surface).height, closeTo(emptyHeight, .01));

      await tester.enterText(
        editor,
        r'read "reply?Answer: "; print -r -- "BLOCK_REPLY:$reply"',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await until(
        tester,
        () =>
            model.ownership == ComposerOwnership.running &&
            !ai.busy &&
            blocks.blocks.any(
              (block) => block.running && block.command.startsWith('read '),
            ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final reading = tester.widget<TerminalViewport>(
        find.descendant(
          of: find.byWidgetPredicate(
            (widget) => widget is CommandBlockTerminal && widget.block.running,
          ),
          matching: find.byType(TerminalViewport),
        ),
      );
      expect(reading.focusNode!.hasFocus, isTrue);
      reading.inputController.sendText('hello\n');
      await until(
        tester,
        () =>
            model.ownership == ComposerOwnership.ready &&
            !ai.busy &&
            !ai.checkingTerminal &&
            blocks.blocks.every((block) => !block.running),
      );
      expect(
        await blocks.outputText(blocks.blocks.last.id),
        contains('BLOCK_REPLY:hello'),
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.widget<TextField>(editor).focusNode!.hasFocus, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump(const Duration(milliseconds: 100));
      expect(blocks.activeId, blocks.blocks.last.id);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(tester.widget<TextField>(editor).focusNode!.hasFocus, isTrue);
      await capture('native-completed');

      await tester.enterText(editor, 'saved draft');
      await chooseMode('normal');
      expect(editor, findsNothing);
      await chooseMode('blocks');
      expect(model.editor.text, 'saved draft');
      // Apple's Bash 3.2 has shell hooks but no Composer adapter. Its child
      // context must never borrow the parent Zsh editor's ready lease.
      // Keep the injected bash() wrapper while selecting /bin/bash for this
      // call only; the other completion/execution fixtures retain their PATH.
      await tester.enterText(editor, 'PATH=/usr/bin:/bin:/usr/sbin:/sbin bash');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await until(
        tester,
        () =>
            container
                .read(sessionControllerProvider)
                .tabs
                .first
                .activePane
                .shellIntegration
                .contextKind ==
            'shell',
      );
      await until(
        tester,
        () => find.byType(TerminalAiWorkspace).evaluate().isEmpty,
      );
      final childShell = tester.widget<TerminalViewport>(
        find.byType(TerminalViewport),
      );
      expect(childShell.focusNode!.hasFocus, isTrue);
      await until(
        tester,
        () =>
            container
                .read(sessionControllerProvider)
                .tabs
                .first
                .activePane
                .terminalMode
                .unavailableReason ==
            BlockUnavailableReason.unsupportedShell,
        diagnostics: () =>
            'child mode=${container.read(sessionControllerProvider).tabs.first.activePane.terminalMode.unavailableReason}; '
            'context=${container.read(sessionControllerProvider).tabs.first.activePane.shellIntegration.contextId}; '
            'state=${container.read(terminalRuntimeControllerProvider).composerRequest(id, 'composer.state', const {})}; '
            'owner=${model.ownership}; output=${terminalText()}',
      );
      final childPane = container
          .read(sessionControllerProvider)
          .tabs
          .first
          .activePane;
      final childState = container
          .read(terminalRuntimeControllerProvider)
          .composerRequest(id, 'composer.state', const {});
      expect(childPane.shellIntegration.contextId, isNot('root'));
      expect(childState?['contextId'], childPane.shellIntegration.contextId);
      expect(childState?['transport'], 'shell');
      expect(childState?['state'], 'draft');
      expect(childState?['lease'], isNull);
      expect(childPane.terminalMode.canUseBlocks, isFalse);
      expect(childPane.terminalMode.mode, TerminalViewMode.normal);
      expect(find.byType(TerminalAiWorkspace), findsNothing);
      expect(childShell.focusNode!.hasFocus, isTrue);
      await capture('terminal-mode-nested-shell');
      childShell.inputController.sendText('exit\n');
      await until(
        tester,
        () =>
            model.ownership == ComposerOwnership.ready &&
            !ai.busy &&
            !ai.checkingTerminal &&
            container
                .read(sessionControllerProvider)
                .tabs
                .first
                .activePane
                .terminalMode
                .canUseBlocks,
      );
      expect(
        container
            .read(sessionControllerProvider)
            .tabs
            .first
            .activePane
            .terminalMode
            .mode,
        TerminalViewMode.normal,
      );
      expect(
        container
            .read(sessionControllerProvider)
            .tabs
            .first
            .activePane
            .terminalMode
            .notice,
        TerminalModeNotice.blocksRestored,
      );
      await chooseMode('blocks');
      await tester.enterText(
        editor,
        r"printf '\033[?1049hALT_SCREEN'; read -k 1 answer; printf '\033[?1049l'",
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await until(
        tester,
        () => container
            .read(sessionControllerProvider.notifier)
            .viewportFor(id)
            .frame
            .modes
            .alternateScreen,
      );
      await until(
        tester,
        () => find.byType(TerminalAiWorkspace).evaluate().isEmpty,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(TerminalCommandBlocksView), findsNothing);
      final fullScreen = tester.widget<TerminalViewport>(
        find.byType(TerminalViewport),
      );
      expect(fullScreen.focusNode!.hasFocus, isTrue);
      fullScreen.inputController.sendText('x');
      await until(
        tester,
        () =>
            model.ownership == ComposerOwnership.ready &&
            !ai.busy &&
            !ai.checkingTerminal &&
            !container
                .read(sessionControllerProvider.notifier)
                .viewportFor(id)
                .frame
                .modes
                .alternateScreen,
      );
      await until(
        tester,
        () => container
            .read(sessionControllerProvider)
            .tabs
            .first
            .activePane
            .terminalMode
            .canUseBlocks,
      );
      expect(find.byType(TerminalCommandBlocksView), findsNothing);
      expect(
        container
            .read(sessionControllerProvider)
            .tabs
            .first
            .activePane
            .terminalMode
            .mode,
        TerminalViewMode.normal,
      );
      await chooseMode('blocks');
      // Exercise actual fullscreen programs, including their PTY input and
      // resize after the Composer dock is removed. Quitting never restores
      // Blocks automatically.
      for (final program in [
        (
          name: 'top',
          command: '/usr/bin/top -s 1',
          ready: 'Processes:',
          quit: 'q',
        ),
        (
          name: 'vim',
          command: '/usr/bin/vim -Nu NONE -i NONE -n',
          ready: 'VIM',
          quit: ':q!\r',
        ),
      ]) {
        await until(
          tester,
          () =>
              model.ownership == ComposerOwnership.ready &&
              !ai.busy &&
              !ai.checkingTerminal,
        );
        await tester.tap(editor);
        await tester.enterText(editor, program.command);
        await tester.pump(const Duration(milliseconds: 100));
        expect(model.editor.text, program.command);
        expect(tester.widget<TextField>(editor).focusNode!.hasFocus, isTrue);
        // Esc with no candidate intentionally hands control to the terminal.
        // Close only an actual suggestion before deliberate execution.
        if (model.completionMenuOpen ||
            model.inlineSuggestion.isNotEmpty ||
            model.loading ||
            model.completionStatus.isNotEmpty) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }
        expect(tester.widget<TextField>(editor).focusNode!.hasFocus, isTrue);
        expect(ai.canRunUserCommand, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await until(
          tester,
          () =>
              find.byType(TerminalAiWorkspace).evaluate().isEmpty &&
              terminalText().contains(program.ready),
          diagnostics: () =>
              '${program.name}: ${container.read(sessionControllerProvider).tabs.first.activePane.terminalMode.unavailableReason}; '
              'owner=${model.ownership}; draft=${model.editor.text}; status=${model.status}; '
              'alternate=${container.read(sessionControllerProvider.notifier).viewportFor(id).frame.modes.alternateScreen}; '
              'output=${terminalText()}',
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(TerminalCommandBlocksView), findsNothing);
        final terminalFinder = find.byType(TerminalViewport);
        final terminal = tester.widget<TerminalViewport>(terminalFinder);
        expect(terminal.focusNode!.hasFocus, isTrue);
        expect(tester.getSize(terminalFinder), normalTerminalSize);
        expect(terminal.controller.frame.viewportRows, greaterThan(15));
        if (program.name == 'vim') {
          terminal.inputController.sendText('iVIM_BLOCK_INPUT');
          await until(tester, () => terminalText().contains('VIM_BLOCK_INPUT'));
          terminal.inputController.sendText('\u001b');
          await tester.pump(const Duration(milliseconds: 100));
        }
        await capture('fullscreen-${program.name}');
        terminal.inputController.sendText(program.quit);
        await until(
          tester,
          () =>
              model.ownership == ComposerOwnership.ready &&
              !ai.busy &&
              !ai.checkingTerminal &&
              container
                  .read(sessionControllerProvider)
                  .tabs
                  .first
                  .activePane
                  .terminalMode
                  .canUseBlocks,
        );
        expect(find.byType(TerminalAiWorkspace), findsNothing);
        expect(
          container
              .read(sessionControllerProvider)
              .tabs
              .first
              .activePane
              .terminalMode
              .notice,
          TerminalModeNotice.blocksRestored,
        );
        await chooseMode('blocks');
      }
      final releaseOutput = File('${home.path}/.release-background-output');
      final finishOutput = File('${home.path}/.finish-background-output');
      addTearDown(() => finishOutput.writeAsString('finish'));
      final backgroundCommand =
          '(while [[ ! -e "${releaseOutput.path}" ]]; do sleep 0.05; done; '
          'print BLOCK_UNASSIGNED_OUTPUT; '
          'while [[ ! -e "${finishOutput.path}" ]]; do sleep 0.05; done) &';
      final beforeBackgroundLease = model.readyLease;
      await tester.enterText(editor, backgroundCommand);
      // This compound expression has no resolved first command token. Use
      // the visible override instead of expecting Auto to execute it.
      expect(ai.inputIntentDecision().intent, InputIntent.ai);
      await tester.tap(find.byKey(const Key('ai-input-intent')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is CheckedPopupMenuItem<InputIntentChoice> &&
              widget.value == InputIntentChoice.command,
        ),
      );
      await tester.pumpAndSettle();
      expect(ai.inputIntentDecision().intent, InputIntent.command);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await until(
        tester,
        () =>
            model.ownership == ComposerOwnership.ready &&
            !ai.busy &&
            !ai.checkingTerminal &&
            model.readyLease != beforeBackgroundLease &&
            blocks.blocks.last.command == backgroundCommand &&
            !blocks.blocks.last.running,
        diagnostics: () =>
            'owner=${model.ownership}; intent=${ai.inputIntentDecision().intent}; '
            'draft=${model.editor.text}; status=${model.status}; output=${terminalText()}',
      );
      // Returning from a multiline command resizes the PTY after the Shell's
      // debounce. Match the native grid to the measured layout, then observe a
      // stable idle screen across the output-attribution refresh before release.
      final backgroundViewport = container
          .read(sessionControllerProvider.notifier)
          .viewportFor(id);
      (Object?, Object?, Object?, String?)? idleScreen;
      DateTime? idleSince;
      await until(tester, () {
        final size = tester.getSize(find.byKey(ValueKey('blocks-pane-$id')));
        final padding = container
            .read(sessionControllerProvider)
            .terminalViewportPadding;
        final cell = backgroundViewport.measuredCellSize!;
        final expectedColumns = ((size.width - padding * 2) / cell.width)
            .floor();
        final expectedRows = ((size.height - padding * 2) / cell.height)
            .floor();
        final live = container
            .read(terminalRuntimeControllerProvider)
            .liveScreen(id)!;
        final sample = (
          live['columns'],
          live['rows'],
          live['text'],
          model.readyLease,
        );
        final frame = backgroundViewport.frame;
        final matchesLayout =
            live['columns'] == expectedColumns &&
            live['rows'] == expectedRows &&
            frame.viewportCols == expectedColumns &&
            frame.viewportRows == expectedRows;
        if (!matchesLayout || sample != idleScreen) {
          idleScreen = sample;
          idleSince = DateTime.now();
          return false;
        }
        return DateTime.now().difference(idleSince!) >=
            const Duration(milliseconds: 200);
      }, diagnostics: () => 'idle screen did not settle: $idleScreen');
      expect(find.byType(TerminalCommandBlocksView), findsOneWidget);
      final backgroundOutputLease = model.readyLease;
      // Keep idle output separate from the job-completion notification and
      // prompt repaint. Let the child finish only after fallback is observed.
      await releaseOutput.writeAsString('release');
      bool hasBackgroundOutput() => terminalText()
          .split('\n')
          .any(
            (line) =>
                line.trim().replaceFirst(RegExp('^composer> '), '') ==
                'BLOCK_UNASSIGNED_OUTPUT',
          );
      await until(tester, hasBackgroundOutput, diagnostics: terminalText);
      await until(
        tester,
        () => find.byType(TerminalCommandBlocksView).evaluate().isEmpty,
        diagnostics: () =>
            'unattributed mode=${container.read(sessionControllerProvider).tabs.first.activePane.terminalMode.unavailableReason}; '
            'owner=${model.ownership}; output=${terminalText()}',
      );
      expect(hasBackgroundOutput(), isTrue);
      expect(model.readyLease, backgroundOutputLease);
      final fallback = container
          .read(sessionControllerProvider)
          .tabs
          .first
          .activePane
          .terminalMode;
      expect(fallback.mode, TerminalViewMode.normal);
      expect(
        fallback.unavailableReason,
        BlockUnavailableReason.unattributedOutput,
      );
      debugPrint(
        'background-output-measurement: stable grid '
        '${backgroundViewport.frame.viewportCols}x${backgroundViewport.frame.viewportRows}; '
        'same ready lease; unattributed output fallback confirmed',
      );
      await finishOutput.writeAsString('finish');
      // Submit normal exit through the production human Composer. Its native
      // final output, close event, resize and ShellScreen listeners must settle
      // together rather than leaving a running pane without a viewport.
      final exitingId = container
          .read(sessionControllerProvider.notifier)
          .createSession(profile)!;
      await until(
        tester,
        () => container
            .read(sessionControllerProvider)
            .tabs
            .last
            .activePane
            .terminalMode
            .canUseBlocks,
      );
      await chooseMode('blocks', sessionId: exitingId);
      await until(tester, () => editor.evaluate().isNotEmpty);
      await tester.enterText(editor, 'exit');
      final exitModel = tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .commandSession!
          .draftEditor!;
      if (exitModel.completionMenuOpen ||
          exitModel.inlineSuggestion.isNotEmpty ||
          exitModel.loading ||
          exitModel.completionStatus.isNotEmpty) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await until(
        tester,
        () => !container
            .read(sessionControllerProvider)
            .tabs
            .any((tab) => tab.containsSession(exitingId)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        container.read(sessionControllerProvider).activeSessionId,
        isNot(exitingId),
      );
      expect(
        container
            .read(terminalRuntimeControllerProvider)
            .existingViewportFor(exitingId),
        isNull,
      );
      expect(find.byKey(Key('terminal-unavailable-$exitingId')), findsNothing);
      await capture('normal-exit-no-stale-pane');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !Platform.isMacOS,
  );
}

Future<void> until(
  WidgetTester tester,
  bool Function() ready, {
  String Function()? diagnostics,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Composer state did not settle: ${diagnostics?.call() ?? ''}');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}
