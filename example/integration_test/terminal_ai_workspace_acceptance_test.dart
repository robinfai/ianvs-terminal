import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/app.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ui/previews/terminal_ai_workspace_preview.dart';
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
import '../test/support/memory_local_terminal_config_repository.dart';
import '../test/support/memory_profile_repository.dart';
import '../test/support/no_io_local_session_recording_repository.dart';
import '../test/support/no_io_local_terminal_layout_repository.dart';
import '../test/support/shell_command_actions.dart';
import 'terminal_ai_stream_acceptance.dart';

class _FixtureStore implements AiConfigurationStore {
  _FixtureStore(this.value);
  AiConfiguration? value;
  @override
  Future<AiConfiguration?> read() async => value;
  @override
  Future<void> write(AiConfiguration? configuration) async =>
      value = configuration;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const evidencePath = String.fromEnvironment('TRAIL_FUSION_EVIDENCE');
  testWidgets(
    'Main AI timeline submits once and returns unchanged TUI grid',
    (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      final fixture = await _ResponseFixture.start();
      addTearDown(fixture.close);
      final configuration = AiConfiguration(
        endpoint: 'http://127.0.0.1:${fixture.server.port}/v1',
        apiKey: 'isolated-test-fixture',
        model: 'fixture',
      );
      final settings = AiSettingsController(_FixtureStore(configuration));
      final home = await Directory.systemTemp.createTemp('trail-fusion-ui-');
      await File(
        '${home.path}/.zshrc',
      ).writeAsString("PROMPT='trail-proxy> '\nRPROMPT=''\n");
      final profile = TerminalProfile(
        id: 'proxy-ui',
        name: 'Block AI acceptance',
        shell: '/bin/zsh',
        cwd: home.path,
        env: {
          'HOME': home.path,
          'ZDOTDIR': home.path,
          'XDG_CONFIG_HOME': home.path,
          'XDG_DATA_HOME': home.path,
          'LANG': 'en_US.UTF-8',
          'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
        },
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(NativePtyBackend.load()),
          aiSettingsProvider.overrideWithValue(settings),
          profileRepositoryProvider.overrideWithValue(
            MemoryProfileRepository(
              TerminalProfilesDocument(profiles: [profile]),
            ),
          ),
          localTerminalConfigRepositoryProvider.overrideWithValue(
            MemoryLocalTerminalConfigRepository(
              const LocalTerminalConfigDocument(
                defaultProfileId: 'proxy-ui',
                appearance: TerminalAppAppearance(
                  preferredTerminalMode: TerminalViewMode.blocks,
                ),
              ),
            ),
          ),
          localTerminalLayoutRepositoryProvider.overrideWithValue(
            noIoLocalTerminalLayoutRepository(),
          ),
          localSessionRecordingRepositoryProvider.overrideWithValue(
            noIoLocalSessionRecordingRepository(),
          ),
          shellAnimationsEnabledProvider.overrideWithValue(false),
          shellNotificationSenderProvider.overrideWithValue(
            ({required title, body, identifier, expiresAfterMs}) async {},
          ),
        ],
      );
      final captureKey = GlobalKey();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        for (final tab in container.read(sessionControllerProvider).tabs) {
          for (final pane in tab.effectivePanes) {
            await container
                .read(sessionControllerProvider.notifier)
                .closeSession(pane.sessionId);
          }
        }
        container.dispose();
        settings.dispose();
        await home.delete(recursive: true);
      });
      Future<void> waitFor(bool Function() ready, String label) async {
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        while (!ready()) {
          if (DateTime.now().isAfter(deadline)) fail('Timed out: $label');
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      Future<void> click(Key key) async {
        await waitFor(
          () => find.byKey(key).evaluate().isNotEmpty,
          'UI control $key',
        );
        await tester.ensureVisible(find.byKey(key));
        await tester.tap(find.byKey(key));
        await tester.pump(const Duration(milliseconds: 150));
      }

      Future<void> capture(String name) async {
        if (evidencePath.isEmpty) return;
        if (find.byKey(const Key('block-reader')).evaluate().isNotEmpty) {
          // Capture the reader after its route transition, not a sliding frame.
          await tester.pump(const Duration(milliseconds: 350));
        }
        await tester.pump();
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(evidencePath).create(recursive: true);
        await File(
          '$evidencePath/$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: captureKey,
            child: const IanvsTerminalApp(),
          ),
        ),
      );
      await waitFor(
        () => container.read(sessionControllerProvider).activeSessionId != null,
        'local session',
      );
      final id = container.read(sessionControllerProvider).activeSessionId!;
      final runtime = container.read(terminalRuntimeControllerProvider);
      Map<String, Object?>? shell() =>
          runtime.composerRequest(id, 'composer.state', const {});
      await waitFor(() => shell()?['state'] == 'ready', 'negotiated shell');
      await tester.pump(const Duration(seconds: 1));
      final initialPane = container
          .read(sessionControllerProvider)
          .tabs
          .first
          .activePane;
      expect(
        container.read(sessionControllerProvider).preferredTerminalMode,
        TerminalViewMode.blocks,
      );
      expect(initialPane.terminalMode.mode, TerminalViewMode.blocks);
      expect(initialPane.profileId, 'proxy-ui');
      await capture('D01-initial-mode');
      await waitFor(
        () => find.byType(TerminalCommandBlocksView).evaluate().isNotEmpty,
        'visible Command Block view',
      );
      final composer = tester
          .widget<TerminalComposerView>(find.byType(TerminalComposerView))
          .controller;
      Future<void> returnToManualInput() async {
        final requestsBefore = fixture.requests;
        final blocksBefore =
            (runtime.commandBlocks(id)!['blocks']! as List).length;
        await click(const Key('ai-close'));
        final observer = find
            .byKey(const Key('ai-observer-viewport'))
            .hitTestable();
        expect(observer, findsOneWidget);
        expect(tester.widget<TerminalViewport>(observer).readOnly, isTrue);
        expect(composer.canRun, isFalse);
        expect(fixture.requests, requestsBefore);
        expect(runtime.commandBlocks(id)!['blocks'], hasLength(blocksBefore));
        await click(const Key('ai-observer-take-over'));
        expect(observer, findsNothing);
        expect(find.byType(TerminalAiWorkspace), findsNothing);
        expect(fixture.requests, requestsBefore);
        expect(runtime.commandBlocks(id)!['blocks'], hasLength(blocksBefore));
      }

      final readerRoot = find.byKey(const Key('block-reader'));
      final readerPages = find.descendant(
        of: readerRoot,
        matching: find.byType(CommandBlockTerminal),
      );
      final readerViewports = find.descendant(
        of: readerRoot,
        matching: find.byType(TerminalViewport),
      );
      await tester.enterText(
        find.byKey(const Key('composer-editor')),
        'printf preserved-draft',
      );
      const commandDraft = TextEditingValue(
        text: 'printf preserved-draft',
        selection: TextSelection(baseOffset: 7, extentOffset: 16),
      );
      tester.testTextInput.updateEditingValue(commandDraft);
      await tester.pump();
      final initialRequests = fixture.requests;
      await click(Key('terminal-ai-open-$id'));
      await tester.enterText(
        find.byKey(const Key('ai-prompt')),
        'Keep this separate AI draft',
      );
      await returnToManualInput();
      expect(composer.editor.value, commandDraft);
      expect(fixture.requests, initialRequests);
      expect(runtime.commandBlocks(id)!['blocks'], isEmpty);
      composer.clearDraft();
      await tester.pump();
      TerminalAiController ai() => tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .controller;
      Future<void> ask(String prompt) async {
        await click(const Key('ai-prompt'));
        await tester.enterText(find.byKey(const Key('ai-prompt')), prompt);
        await tester.pump();
        await click(const Key('ai-send'));
        await waitFor(() => !ai().busy, 'model proposal');
        expect(ai().error, isNull);
        if (ai().canApprove) {
          await click(const Key('ai-show-latest'));
        }
      }

      await click(Key('terminal-ai-open-$id'));
      final task = ai();
      await waitFor(() => task.context != null, 'AI context');
      expect(task.draft, 'Keep this separate AI draft');
      final proof = File('${home.path}/once.txt');
      fixture.propose('run_command', {
        'command': r"printf 'one\n'",
        'reason': 'Check the current shell',
      });
      await ask('Check the current shell without changing other files.');
      expect(await proof.exists(), false);
      expect(task.pending?.kind, AiActionKind.runCommand);
      await capture('D03-command-review');
      await click(const Key('ai-edit-action'));
      await tester.enterText(
        find.byKey(const Key('ai-edit-command')),
        "printf 'FUSION_OK\\n'; printf x >> '${proof.path}'",
      );
      await click(const Key('ai-save-edit'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(await proof.exists(), false);
      await click(const Key('ai-approve'));
      await waitFor(() => !task.busy, 'native command receipt');
      expect(task.error, isNull);
      await waitFor(() => shell()?['state'] == 'ready', 'command exit');
      await task.refreshContext();
      final native = (runtime.commandBlocks(id)!['blocks']! as List)
          .where(
            (raw) => (raw as Map)['command'].toString().contains('FUSION_OK'),
          )
          .toList();
      expect(native, hasLength(1));
      final nativeId = (native.single as Map)['id'] as String;
      final receipt = task.transcript.singleWhere(
        (entry) => entry.blockId == nativeId,
      );
      expect(receipt.state, AiEntryState.accepted);
      expect(await proof.readAsString(), 'x');
      final timeline = find.descendant(
        of: find.byType(TerminalAiWorkspace),
        matching: find.byKey(ValueKey('command-block-$nativeId')),
      );
      expect(timeline, findsOneWidget);
      expect(task.context!.lastBlock!.exitCode, 0);
      await waitFor(
        () => tester
            .widget<TextField>(find.byKey(const Key('ai-prompt')))
            .focusNode!
            .hasFocus,
        'result returns keyboard focus for the follow-up',
      );
      await capture('D05-native-block-evidence');
      tester.testTextInput.enterText('Keep this unsent follow-up');
      await tester.pump();
      expect(task.draft, 'Keep this unsent follow-up');
      await capture('D05-follow-up-without-refocusing');
      await click(ValueKey('ai-evidence-$nativeId-0'));
      await waitFor(
        () =>
            find.byKey(const Key('block-reader-scroll')).evaluate().isNotEmpty,
        'evidence opens the original output reader',
      );
      expect(
        tester
            .widget<CommandBlockTerminal>(readerPages.first)
            .block
            .visibleOutput,
        contains('FUSION_OK'),
      );
      await capture('D08-original-output-reader');
      await tester.tap(find.byKey(const Key('block-reader-close')));
      await tester.pump(const Duration(milliseconds: 350));
      expect(task.draft, 'Keep this unsent follow-up');
      await returnToManualInput();

      // A real failed command enters diagnosis through the block menu. Merely
      // attaching it must not start a model request or submit a repair.
      await waitFor(
        () => composer.canRun || shell()?['state'] == 'ready',
        'shell before failure',
      );
      final failedCommand = "ls '${home.path}/missing-source'";
      await tester.enterText(
        find.byKey(const Key('composer-editor')),
        failedCommand,
      );
      await tester.pump(const Duration(milliseconds: 200));
      Map<String, Object?>? failedBlock() =>
          (runtime.commandBlocks(id)!['blocks']! as List)
              .cast<Map<String, Object?>>()
              .where((b) => b['command'] == failedCommand)
              .firstOrNull;
      try {
        expect(composer.editor.text, failedCommand);
        await waitFor(
          () => composer.canRun,
          'composer ready to run failed command',
        );
        expect(composer.primaryAction, ComposerPrimaryAction.run);
        await click(const Key('composer-primary-action'));
        await waitFor(
          () => failedBlock()?['exitCode'] != null,
          'real nonzero command exit',
        );
      } on Object {
        await capture('D06-failure-diagnostic');
        debugPrint(
          jsonEncode({
            'composerOwnership': composer.ownership.name,
            'composerStatus': composer.status,
            'draft': composer.editor.text,
            'expectedCommand': failedCommand,
            'shell': shell(),
            'blocks': runtime.commandBlocks(id),
          }),
        );
        rethrow;
      }
      expect(failedBlock()!['exitCode'], isNot(0));
      final failedId = failedBlock()!['id']! as String;
      final failedExit = failedBlock()!['exitCode'];
      final failedRoot = find.byKey(ValueKey('command-block-$failedId'));
      await waitFor(
        () => failedRoot.evaluate().isNotEmpty,
        'failed block in terminal',
      );
      final beforeAttachRequests = fixture.requests;
      final beforeAttachCount =
          (runtime.commandBlocks(id)!['blocks']! as List).length;
      await tester.ensureVisible(failedRoot);
      await tester.tap(
        find
            .descendant(
              of: failedRoot,
              matching: find.byType(PopupMenuButton<String>),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is PopupMenuItem<String> && w.value == 'ai',
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(fixture.requests, beforeAttachRequests);
      expect(
        (runtime.commandBlocks(id)!['blocks']! as List).length,
        beforeAttachCount,
      );
      expect(task.attachments.single.id, failedId);
      expect(task.attachments.single.exitCode, failedExit);
      expect(task.draft, 'Keep this unsent follow-up');
      final failedTimeline = find.descendant(
        of: find.byType(TerminalAiWorkspace),
        matching: find.byKey(ValueKey('command-block-$failedId')),
      );
      await tester.ensureVisible(failedTimeline);
      await capture('D06-failure-attached-without-send');
      const repairCommand = r"printf 'REPAIR_EVIDENCE\n'";
      fixture.propose('run_command', {
        'command': repairCommand,
        'reason':
            'Demonstrate a separate result without altering the failed command',
      });
      await ask(
        'Explain the missing path; keep the failed evidence and propose a separate check.',
      );
      expect(
        task.transcript.any((e) => e.contexts.any((b) => b.id == failedId)),
        true,
      );
      expect(task.attachments, isEmpty);
      await click(const Key('ai-approve'));
      await waitFor(
        () => !task.busy && shell()?['state'] == 'ready',
        'separate repair receipt',
      );
      final repaired = (runtime.commandBlocks(id)!['blocks']! as List)
          .cast<Map<String, Object?>>()
          .where((b) => b['command'] == repairCommand)
          .toList();
      expect(repaired, hasLength(1));
      final repairedId = repaired.single['id']! as String;
      expect(repairedId, isNot(failedId));
      expect(repaired.single['exitCode'], 0);
      expect(failedBlock()!['exitCode'], failedExit);
      expect(failedBlock()!['command'], failedCommand);
      expect(
        task.transcript.where((e) => e.blockId == repairedId),
        hasLength(1),
      );
      await tester.ensureVisible(failedTimeline);
      expect(failedTimeline, findsOneWidget);
      await capture('D06-failure-retained-after-correction');

      // Silence is an observation state, not success or permission to resend.
      const silentCommand = r"sleep 12; printf 'SILENT_DONE\n'";
      fixture.propose('run_command', {
        'command': silentCommand,
        'reason': 'Wait for one delayed result without repeating the command',
      });
      await ask('Run one delayed check and keep observing it.');
      fixture.propose('read_screen', {
        'wait_ms': 10000,
        'reason': 'Observe the submitted command without resending it',
      });
      await click(const Key('ai-approve'));
      await waitFor(
        () => task.phase == AiPhase.observing,
        'silent command observation',
      );
      await tester.pump(const Duration(milliseconds: 1100));
      expect(task.waitStartedAt, isNotNull);
      expect(task.canInterrupt, true);
      expect(shell()?['state'], 'running');
      final silentRunning = (runtime.commandBlocks(id)!['blocks']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere((block) => block['command'] == silentCommand);
      final silentId = silentRunning['id']! as String;
      final silentStartedAt = silentRunning['startedAt']! as int;
      final elapsedLabel = find.descendant(
        of: find.byType(TerminalAiWorkspace),
        matching: find.byKey(ValueKey('block-elapsed-$silentId')),
      );
      expect(elapsedLabel, findsOneWidget);
      expect(tester.widget<Text>(elapsedLabel).data, matches(r'^\d+(s|秒)$'));
      await capture('D04-silent-command-observation');
      await click(const Key('ai-take-over'));
      expect(task.busy, false);
      expect(shell()?['state'], 'running', reason: 'AI pause sends no Ctrl+C');
      expect(elapsedLabel, findsOneWidget);
      final pausedElapsed = tester.widget<Text>(elapsedLabel).data!;
      await capture('D04-silent-command-ai-paused-elapsed');
      fixture.propose('read_screen', {
        'wait_ms': 10000,
        'reason': 'Continue observing the same running command',
      });
      await click(const Key('ai-resume'));
      await waitFor(
        () => task.phase == AiPhase.observing,
        'resume reads existing command',
      );
      await ask(
        'Keep the delayed check running; do not execute another command.',
      );
      expect(
        shell()?['state'],
        'running',
        reason: 'Supplement changes the task without interrupting its command',
      );
      await waitFor(() => shell()?['state'] == 'ready', 'delayed command exit');
      final delayed = (runtime.commandBlocks(id)!['blocks']! as List)
          .cast<Map<String, Object?>>()
          .where((b) => b['command'] == silentCommand)
          .toList();
      expect(delayed, hasLength(1));
      expect(delayed.single['exitCode'], 0);
      final delayedId = delayed.single['id']! as String;
      expect(delayedId, silentId);
      expect(delayed.single['startedAt'], silentStartedAt);
      final elapsedMs =
          (delayed.single['finishedAt']! as int) - silentStartedAt;
      expect(elapsedMs, greaterThanOrEqualTo(12000));
      final completedElapsed = '${(elapsedMs / 1000).toStringAsFixed(1)}s';
      await waitFor(
        () => tester.widget<Text>(elapsedLabel).data == completedElapsed,
        'elapsed freezes at the native command finish time',
      );
      await capture('D04-silent-command-completed-elapsed');
      final delayedOutput = runtime.commandBlocks(id, {
        'id': delayedId,
        'limit': 20,
      });
      expect(jsonEncode(delayedOutput), contains('SILENT_DONE'));
      expect(
        task.transcript.where((e) => e.blockId == delayedId),
        hasLength(1),
      );
      await returnToManualInput();
      // Select through actual header gestures, then send only the attachments
      // that remain after the user removes one. Selection itself is not input.
      final blockView = tester.widget<TerminalCommandBlocksView>(
        find.byType(TerminalCommandBlocksView),
      );
      Future<void> selectBlock(String blockId, String command) async {
        final title = find.descendant(
          of: find.byKey(ValueKey('command-block-$blockId')),
          matching: find.text(command),
        );
        await tester.ensureVisible(title);
        await tester.tap(title);
        await tester.pump();
      }

      final beforeMultiRequests = fixture.requests;
      final beforeMultiBlocks =
          (runtime.commandBlocks(id)!['blocks']! as List).length;
      final firstCommand = (native.single as Map)['command']! as String;
      await selectBlock(nativeId, firstCommand);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await selectBlock(repairedId, repairCommand);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(blockView.controller.selected, {nativeId, repairedId});
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await selectBlock(nativeId, firstCommand);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(blockView.controller.selected, {nativeId, failedId, repairedId});
      expect(fixture.requests, beforeMultiRequests);
      await capture('D07-header-multi-selection');
      await tester.tap(
        find.byTooltip(
          blockView.chinese ? '将所选命令块附给 AI' : 'Attach selected blocks to AI',
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(task.attachments.map((b) => b.id), [
        nativeId,
        failedId,
        repairedId,
      ]);
      expect(fixture.requests, beforeMultiRequests);
      final removableChip = find.byWidgetPredicate(
        (widget) =>
            widget is InputChip &&
            widget.onDeleted != null &&
            widget.tooltip?.contains(failedCommand) == true,
      );
      await tester.ensureVisible(removableChip);
      final deleteLabel = MaterialLocalizations.of(
        tester.element(removableChip),
      ).deleteButtonTooltip;
      await tester.tap(
        find.descendant(
          of: removableChip,
          matching: find.byTooltip(deleteLabel),
        ),
      );
      await tester.pump();
      expect(task.attachments.map((b) => b.id), [nativeId, repairedId]);
      expect(failedBlock()!['exitCode'], failedExit);
      final frozen = task.attachments.map((b) => b.toJson()).toList();
      await capture('D07-pending-contexts');
      const multiRequest =
          'Explain only the two attached results; execute nothing.';
      await ask(multiRequest);
      final submitted = fixture.payloads.last['messages']! as List;
      final sentUser =
          jsonDecode(
                (submitted.lastWhere((m) => (m as Map)['role'] == 'user')
                        as Map)['content']
                    as String,
              )
              as Map;
      expect(sentUser['request'], multiRequest);
      expect(sentUser['selected_blocks'], frozen);
      expect(
        task.transcript
            .lastWhere((e) => e.role == 'user')
            .contexts
            .map((b) => b.id),
        [nativeId, repairedId],
      );
      expect(task.attachments, isEmpty);
      expect(fixture.requests, beforeMultiRequests + 1);
      expect(
        (runtime.commandBlocks(id)!['blocks']! as List).length,
        beforeMultiBlocks,
      );
      expect(failedBlock()!['command'], failedCommand);
      await capture('D07-sent-contexts');
      await click(const Key('ai-prompt'));
      await tester.enterText(
        find.byKey(const Key('ai-prompt')),
        'Keep the reader return draft',
      );
      await tester.pump();
      expect(
        task.draft,
        'Keep the reader return draft',
        reason: 'Draft entered before leaving task',
      );
      await returnToManualInput();
      expect(
        task.draft,
        'Keep the reader return draft',
        reason: 'Closing task retains draft',
      );

      await tester.enterText(
        find.byKey(const Key('composer-editor')),
        'seq 1 800',
      );
      await tester.pump();
      await click(const Key('composer-primary-action'));
      Map<String, Object?>? longOutput() =>
          (runtime.commandBlocks(id)!['blocks']! as List)
              .cast<Map<String, Object?>>()
              .where((b) => b['command'] == 'seq 1 800')
              .firstOrNull;
      await waitFor(
        () => longOutput()?['exitCode'] == 0,
        'retained long output',
      );
      final longId = longOutput()!['id']! as String;
      expect(
        task.draft,
        'Keep the reader return draft',
        reason: 'Manual command retains separate AI draft',
      );
      await tester.tap(
        find.byTooltip(blockView.chinese ? '跳到最新输出' : 'Jump to latest output'),
      );
      await tester.pump(const Duration(milliseconds: 350));
      Future<void> openLongReader() async {
        final root = find.byKey(ValueKey('command-block-$longId'));
        await tester.ensureVisible(root);
        await tester.tap(
          find
              .descendant(
                of: root,
                matching: find.byType(PopupMenuButton<String>),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (w) => w is PopupMenuItem<String> && w.value == 'reader',
          ),
        );
        await tester.pumpAndSettle();
      }

      await openLongReader();
      final reader = find.byKey(const Key('block-reader-scroll'));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(reader),
          scrollDelta: const Offset(0, 680),
        ),
      );
      await tester.pumpAndSettle();
      final readerScroll = tester.widget<ListView>(reader).controller!;
      expect(readerScroll.offset, greaterThan(600));
      final readerRect = tester.getRect(reader);
      final outputLeft = tester.getRect(readerViewports.first).left;
      final pointer = await tester.startGesture(
        Offset(outputLeft + 12, readerRect.top + 55),
        kind: PointerDeviceKind.mouse,
      );
      await pointer.moveTo(Offset(outputLeft + 75, readerRect.top + 90));
      await pointer.up();
      await tester.pump();
      final selected = tester
          .widget<CommandBlockTerminal>(readerPages.first)
          .selectionController!
          .selection!;
      expect(selected.endRow, greaterThan(selected.startRow));
      final readingOffset = readerScroll.offset;
      await capture('D08-native-reader-selected');
      await tester.tap(find.byKey(const Key('block-reader-close')));
      await tester.pumpAndSettle();
      await openLongReader();
      expect(
        tester.widget<ListView>(reader).controller!.offset,
        closeTo(readingOffset, .1),
      );
      final reopened = tester
          .widget<CommandBlockTerminal>(readerPages.first)
          .selectionController!
          .selection!;
      expect(
        (
          reopened.startRow,
          reopened.startCol,
          reopened.endRow,
          reopened.endCol,
        ),
        (
          selected.startRow,
          selected.startCol,
          selected.endRow,
          selected.endCol,
        ),
      );
      await capture('D08-native-reader-reopened');
      await tester.tap(find.byKey(const Key('block-reader-find')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('block-reader-find-query')),
        '345',
      );
      await tester.pumpAndSettle();
      expect(find.text('匹配行 1/1'), findsOneWidget);
      expect(
        tester
            .widgetList<CommandBlockTerminal>(readerPages)
            .any(
              (page) =>
                  page.highlightedRow == 344 &&
                  page.block.lines.any(
                    (row) => row.index == 344 && row.text.trim() == '345',
                  ),
            ),
        true,
      );
      expect(find.byKey(const Key('block-reader-range')), findsOneWidget);
      await capture('D08-native-reader-find');
      await tester.tap(find.byKey(const Key('block-reader-find-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('block-reader-actions')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is PopupMenuItem<String> && w.value == 'filter',
        ),
      );
      await tester.pumpAndSettle();
      final filterEditor = find.descendant(
        of: readerRoot,
        matching: find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.decoration?.hintText == '过滤输出' ||
                  w.decoration?.hintText == 'Filter output'),
        ),
      );
      await tester.tap(filterEditor);
      await tester.enterText(filterEditor, r'^\s*(34|35|77)\s*$');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(
        find.descendant(
          of: readerRoot,
          matching: find.widgetWithText(FilterChip, '.*'),
        ),
      );
      await tester.pumpAndSettle();
      final nativeFiltered = runtime.commandBlocks(id, {
        'id': longId,
        'query': r'^\s*(34|35|77)\s*$',
        'regex': true,
        'limit': 10,
      });
      expect(
        (nativeFiltered?['block'] as Map?)?['matchingLines'],
        3,
        reason: jsonEncode(nativeFiltered),
      );
      await waitFor(
        () => readerPages.evaluate().isNotEmpty,
        'visible filtered native rows',
      );
      final filteredPage = tester.widget<CommandBlockTerminal>(
        readerPages.first,
      );
      expect(filteredPage.block.lines.map((r) => r.index), [33, 34, 76]);
      final filteredRect = tester.getRect(readerViewports);
      final filteredPointer = await tester.startGesture(
        filteredRect.topLeft + const Offset(2, 5),
        kind: PointerDeviceKind.mouse,
      );
      await filteredPointer.moveTo(
        Offset(filteredRect.left + 70, filteredRect.bottom - 3),
      );
      await filteredPointer.up();
      await tester.pump();
      final beforeFilteredRequests = fixture.requests;
      final beforeFilteredCommands =
          (runtime.commandBlocks(id)!['blocks']! as List).length;
      await capture('D08-filtered-native-selection');
      await tester.tap(find.byKey(const Key('block-reader-attach')));
      await tester.pumpAndSettle();
      expect(task.draft, 'Keep the reader return draft');
      expect(task.attachments, hasLength(1));
      expect(filteredPage.block.lines.map((r) => r.text.trim()), [
        '34',
        '35',
        '77',
      ]);
      final exactRanges = [
        {
          'start_line': 33,
          'end_line': 35,
          'output':
              '${filteredPage.block.lines[0].text}\n${filteredPage.block.lines[1].text}',
          'citation': '[block:$longId:34-35]',
        },
        {
          'start_line': 76,
          'end_line': 77,
          'output': filteredPage.block.lines[2].text,
          'citation': '[block:$longId:77-77]',
        },
      ];
      expect(task.attachments.single.toJson()['output_ranges'], exactRanges);
      expect(fixture.requests, beforeFilteredRequests);
      await capture('D08-disjoint-context-preview');
      await ask(
        'Explain only the three selected lines; do not execute anything.',
      );
      final filteredMessages = fixture.payloads.last['messages']! as List;
      final filteredUser =
          jsonDecode(
                (filteredMessages.lastWhere((m) => (m as Map)['role'] == 'user')
                        as Map)['content']
                    as String,
              )
              as Map;
      final sentSelection =
          (filteredUser['selected_blocks'] as List).single as Map;
      expect(sentSelection['output_ranges'], exactRanges);
      expect(sentSelection['included_line_count'], 3);
      expect(sentSelection['output_is_contiguous'], false);
      expect(sentSelection.containsKey('output'), false);
      expect(
        (runtime.commandBlocks(id)!['blocks']! as List).length,
        beforeFilteredCommands,
      );
      expect(fixture.requests, beforeFilteredRequests + 1);
      await capture('D08-disjoint-context-sent');

      final streaming = await verifyStreamingTimeline(
        tester,
        task: task,
        runtime: runtime,
        sessionId: id,
        home: home,
        propose: fixture.propose,
        ask: ask,
        click: click,
        waitFor: waitFor,
        capture: capture,
      );

      // D10/D14 use the real HTTP transport with the same native PTY. Neither
      // connection checks nor saving credentials may send the retained task.
      final commandsBeforeRecovery =
          (runtime.commandBlocks(id)!['blocks']! as List).length;
      final retainedEvidence = task.context!.lastBlock!;
      final chinese =
          Localizations.localeOf(
            tester.element(find.byType(TerminalAiWorkspace)),
          ).languageCode ==
          'zh';
      String localized(String en, String zh) => chinese ? zh : en;
      await click(const Key('ai-new-task'));
      fixture.nextStatus = HttpStatus.unauthorized;
      await click(const Key('ai-prompt'));
      await tester.enterText(
        find.byKey(const Key('ai-prompt')),
        'Inspect existing output without changing files.',
      );
      await tester.pump();
      expect(task.draft, 'Inspect existing output without changing files.');
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('ai-send'))).onPressed,
        isNotNull,
      );
      await click(const Key('ai-send'));
      try {
        await waitFor(
          () => task.error == 'authentication',
          'HTTP 401 recovery',
        );
      } on Object {
        await capture('D10-recovery-diagnostic');
        debugPrint(
          jsonEncode({
            'phase': task.phase.name,
            'error': task.error,
            'terminalError': task.terminalError,
            'takenOver': task.takenOver,
            'draft': task.draft,
            'fixtureRequests': fixture.requests,
            'pendingStatus': fixture.nextStatus,
            'task': task.taskId,
            'visibleTask': ai().taskId,
            'sameController': identical(task, ai()),
            'messages': task.transcript.map((e) => e.text).toList(),
          }),
        );
        rethrow;
      }
      final recoveryTaskId = task.taskId;
      task.attachContext(retainedEvidence);
      await click(const Key('ai-prompt'));
      await tester.enterText(
        find.byKey(const Key('ai-prompt')),
        'Preserve this follow-up during recovery',
      );
      await tester.pump();
      expect(task.draft, 'Preserve this follow-up during recovery');
      final beforeConnectionChecks = fixture.requests;
      await capture('D10-authentication-recovery');
      await click(const Key('ai-recovery-settings'));
      await tester.enterText(
        find.byKey(const Key('ai-api-key')),
        'replacement-fixture-key',
      );
      fixture.disconnectNext = true;
      await click(const Key('ai-test-connection'));
      await waitFor(
        () => find
            .textContaining(
              localized('Cannot connect to the endpoint', '无法连接 Endpoint'),
            )
            .evaluate()
            .isNotEmpty,
        'connection check failure',
      );
      expect(settings.configuration!.apiKey, 'isolated-test-fixture');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('ai-api-key')))
            .controller!
            .text,
        'replacement-fixture-key',
      );
      await capture('D14-connection-failed-edit-retained');
      await click(const Key('ai-test-connection'));
      await waitFor(
        () => find.byKey(const Key('ai-connection-ok')).evaluate().isNotEmpty,
        'connection check succeeds without saving',
      );
      expect(
        find.text(
          localized('Connection succeeded. Not saved yet.', '连接成功，尚未保存。'),
        ),
        findsOneWidget,
      );
      expect(settings.configuration!.apiKey, 'isolated-test-fixture');
      expect(fixture.requests, beforeConnectionChecks + 2);
      await capture('D14-connection-tested-not-saved');
      await click(const Key('ai-save-settings'));
      await waitFor(
        () => find.byKey(const Key('ai-settings-dialog')).evaluate().isEmpty,
        'saved connection returns to task',
      );
      expect(
        find.text(
          localized('AI connection saved. Task not sent.', 'AI 连接已保存，任务尚未发送。'),
        ),
        findsOneWidget,
      );
      expect(task.taskId, recoveryTaskId);
      expect(task.draft, 'Preserve this follow-up during recovery');
      expect(task.attachments, [retainedEvidence]);
      expect(task.error, isNull);
      expect(fixture.requests, beforeConnectionChecks + 2);
      expect(
        (runtime.commandBlocks(id)!['blocks']! as List).length,
        commandsBeforeRecovery,
      );
      expect(await proof.readAsString(), 'x');
      expect(
        task.transcript.map((e) => e.text).join('\n'),
        isNot(contains('replacement-fixture-key')),
      );
      await capture('D14-saved-task-retained');
      await click(const Key('ai-resume'));
      await waitFor(
        () => fixture.requests == beforeConnectionChecks + 3 && !task.busy,
        'explicit continuation after authentication recovery',
      );
      expect(task.draft, 'Preserve this follow-up during recovery');
      expect(
        (runtime.commandBlocks(id)!['blocks']! as List).length,
        commandsBeforeRecovery,
      );
      expect(await proof.readAsString(), 'x');
      await returnToManualInput();
      await waitFor(() => shell()?['state'] == 'ready', 'shell before vim');
      final vimFile = File('${home.path}/vim.txt');
      await vimFile.writeAsString('Original file\n');
      runtime.composerRequest(id, 'composer.submit', {
        'lease': shell()!['lease'],
        'submissionId': 'fusion-vim',
        'text': "/usr/bin/vim -u NONE -N '${vimFile.path}'",
      });
      await waitFor(
        () => runtime.liveScreen(id)?['alternateScreen'] == true,
        'vim alternate screen',
      );
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.byType(TerminalCommandBlocksView), findsNothing);
      final fullViewport = tester.widget<TerminalViewport>(
        find.byType(TerminalViewport),
      );
      final viewportSize = tester.getSize(find.byType(TerminalViewport));
      final cell = fullViewport.controller.measuredCellSize!;
      final grid = (
        ((viewportSize.height - fullViewport.contentPadding.vertical) /
                cell.height)
            .floor(),
        ((viewportSize.width - fullViewport.contentPadding.horizontal) /
                cell.width)
            .floor(),
      );
      await waitFor(
        () =>
            (
              runtime.liveScreen(id)!['rows'],
              runtime.liveScreen(id)!['columns'],
            ) ==
            grid,
        'vim resized to the full visible terminal grid',
      );
      await click(Key('terminal-ai-open-$id'));
      expect(tester.getSize(find.byType(TerminalViewport)), viewportSize);
      expect((
        runtime.liveScreen(id)!['rows'],
        runtime.liveScreen(id)!['columns'],
      ), grid);
      fixture.propose('send_keys', {
        'keys': [
          {'key': 'ESC'},
          {'text': ':q!'},
          {'key': 'ENTER'},
        ],
        'reason': 'Exit the temporary vim file without changing it',
      });
      await ask('Exit this temporary vim file without changing it.');
      expect(task.pending?.kind, AiActionKind.sendKeys);
      final tuiTaskId = task.taskId;
      await capture('D12-vim-review-overlay');
      expect((
        runtime.liveScreen(id)!['rows'],
        runtime.liveScreen(id)!['columns'],
      ), grid);
      await click(const Key('ai-approve'));
      try {
        await waitFor(
          () => find.byType(TerminalAiWorkspace).evaluate().isEmpty,
          'approved TUI action returns to read-only observation',
        );
      } on Object {
        await capture('D12-vim-approval-failure');
        if (evidencePath.isNotEmpty) {
          await File('$evidencePath/vim-approval-failure.json').writeAsString(
            jsonEncode({
              'shell': shell(),
              'screen': runtime.liveScreen(id),
              'phase': task.phase.name,
              'error': task.error,
              'terminal_error': task.terminalError,
              'pending': task.pending?.rawCall,
              'can_approve': task.canApprove,
              'revision': task.proposalRevision,
              'context': task.context?.toJson(),
              'transcript': [
                for (final entry in task.transcript)
                  {
                    'role': entry.role,
                    'action': entry.action?.kind.name,
                    'state': entry.state.name,
                    'text': entry.text,
                  },
              ],
            }),
          );
        }
        rethrow;
      }
      await waitFor(
        () => shell()?['state'] == 'ready',
        'vim returned to shell',
      );
      expect(await vimFile.readAsString(), 'Original file\n');
      expect(runtime.liveScreen(id)?['alternateScreen'], false);
      expect(
        find.byType(TerminalCommandBlocksView),
        findsNothing,
        reason: 'Recovery offers manual Blocks restoration',
      );
      final tuiObserver = find
          .byKey(const Key('ai-observer-viewport'))
          .hitTestable();
      expect(tuiObserver, findsOneWidget);
      expect(tester.widget<TerminalViewport>(tuiObserver).readOnly, isTrue);
      expect(task.takenOver, isFalse);
      await capture('D12-vim-return-normal');
      await click(const Key('ai-observer-take-over'));
      expect(tuiObserver, findsNothing);
      expect(task.taskId, tuiTaskId);
      expect(find.byType(TerminalAiWorkspace), findsNothing);
      expect(
        tester
            .widget<TerminalViewport>(
              find.byType(TerminalViewport).hitTestable(),
            )
            .readOnly,
        isFalse,
      );
      expect(await vimFile.readAsString(), 'Original file\n');
      // D14 exposes the absent override instead of baking the resolved desktop
      // default into settings. Saving it must preserve this existing session.
      final modeBeforePreference = container
          .read(sessionControllerProvider)
          .tabs
          .single
          .terminalMode
          .mode;
      final requestsBeforePreference = fixture.requests;
      final blocksBeforePreference = runtime.commandBlocks(id, {'limit': 128});
      await openShellCommand(tester, 'shell-command-defaults');
      await tester.pumpAndSettle();
      final savedAiConfiguration = settings.configuration!;
      final aiStatus = find.byKey(const Key('defaults-ai-connection-status'));
      expect(tester.widget<Text>(aiStatus).data, contains('配置已保存'));
      await capture('D14-configuration-saved-status');
      await click(const Key('defaults-ai-settings'));
      await click(const Key('ai-remove-settings'));
      await tester.pumpAndSettle();
      expect(settings.configuration, isNull);
      expect(tester.widget<Text>(aiStatus).data, contains('尚未配置'));
      await capture('D14-configuration-missing-status');
      await click(const Key('defaults-ai-settings'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('ai-endpoint')),
        savedAiConfiguration.endpoint,
      );
      await tester.enterText(
        find.byKey(const Key('ai-api-key')),
        savedAiConfiguration.apiKey,
      );
      await tester.enterText(
        find.byKey(const Key('ai-model')),
        savedAiConfiguration.model,
      );
      await click(const Key('ai-save-settings'));
      await tester.pumpAndSettle();
      // Removing configuration also removes its explicit manual policy. A new
      // connection starts with the product's current smart-review default.
      expect(settings.configuration!.toJson(), {
        ...savedAiConfiguration.toJson(),
        'approvalMode': AiApprovalMode.smart.name,
      });
      expect(tester.widget<Text>(aiStatus).data, contains('配置已保存'));
      final modeOptions = find.byKey(
        const Key('defaults-terminal-mode-options'),
      );
      await tester.ensureVisible(modeOptions);
      await tester.tap(modeOptions);
      await tester.pumpAndSettle();
      await capture('D14-platform-preference-options');
      await tester.tap(
        find.byKey(const Key('default-terminal-mode-platform')).last,
      );
      await tester.pumpAndSettle();
      await capture('D14-platform-preference-staged');
      await click(const Key('defaults-save'));
      await tester.pumpAndSettle();
      expect(
        container
            .read(sessionControllerProvider.notifier)
            .preferredTerminalModeOverride,
        isNull,
      );
      expect(
        container.read(sessionControllerProvider).tabs.single.terminalMode.mode,
        modeBeforePreference,
      );
      expect(fixture.requests, requestsBeforePreference);
      expect(runtime.commandBlocks(id, {'limit': 128}), blocksBeforePreference);
      if (evidencePath.isNotEmpty) {
        await File('$evidencePath/result.json').writeAsString(
          jsonEncode({
            'fixture': 'deterministic local HTTP, not model quality benchmark',
            'native_command_count': native.length,
            'submission_id': receipt.submissionId,
            'block_id': nativeId,
            'edited_command_executed_once': await proof.readAsString() == 'x',
            'command_draft_and_selection_restored': true,
            'result_returned_input_focus': true,
            'failure_attachment_did_not_send': true,
            'failure_block_id': failedId,
            'failure_exit_code': failedExit,
            'correction_block_id': repairedId,
            'failure_preserved_after_correction': true,
            'silent_command_block_id': delayedId,
            'silent_command_elapsed': {
              'started_at': silentStartedAt,
              'finished_at': delayed.single['finishedAt'],
              'duration_ms': elapsedMs,
              'paused_label': pausedElapsed,
              'completed_label': completedElapsed,
            },
            'streaming_timeline': streaming,
            'pause_resume_supplement_kept_command_running_once': true,
            'multi_selection_sent_block_ids': [nativeId, repairedId],
            'removed_attachment_kept_original_block': true,
            'multi_selection_and_send_did_not_execute': true,
            'reader_reopened_at_same_position_and_selection': true,
            'reader_preserved_task_draft': true,
            'filtered_selection_sent_only_original_ranges': exactRanges,
            'filtered_selection_did_not_execute': true,
            'http_401_recovery_preserved_task_draft_and_context': true,
            'failed_connection_check_preserved_edit_and_saved_configuration':
                true,
            'connection_test_and_save_have_distinct_feedback': true,
            'recovery_continued_only_after_explicit_action': true,
            'recovery_did_not_resubmit_native_command': true,
            'vim_overlay_grid': [grid.$1, grid.$2],
            'vim_returned_to_read_only_observation': true,
            'vim_input_restored_only_after_explicit_takeover': true,
            'restoration_is_manual': true,
            'platform_preference_reset_preserved_session_and_output': true,
            'ai_configuration_status_tracks_explicit_save_and_remove': true,
            'completed_at': DateTime.now().toUtc().toIso8601String(),
          }),
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  for (final scene in [
    (
      name: 'M01-fixed-text',
      size: const Size(390, 844),
      dark: false,
      completed: false,
    ),
    (
      name: 'M01-keyboard-space',
      size: const Size(390, 480),
      dark: false,
      completed: false,
    ),
    (
      name: 'M03-dark-evidence',
      size: const Size(390, 844),
      dark: true,
      completed: true,
    ),
    (
      name: 'M01-landscape',
      size: const Size(844, 300),
      dark: true,
      completed: false,
    ),
  ]) {
    testWidgets('Production component preview ${scene.name}', (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      await tester.binding.setSurfaceSize(scene.size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: AiWorkspacePreview(
            phone: true,
            dark: scene.dark,
            completed: scene.completed,
            draftOnly: !scene.completed,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-send')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      Future<void> capture(String name) async {
        if (evidencePath.isEmpty) return;
        await tester.pump();
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$evidencePath/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      await capture(scene.name);
      if (scene.name == 'M01-fixed-text' || scene.name == 'M01-landscape') {
        await tester.tap(find.byKey(const Key('ai-send')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('ai-review-action')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('ai-approve')).hitTestable(),
          findsOneWidget,
        );
        await capture(
          scene.name == 'M01-landscape'
              ? 'M02-landscape-review'
              : 'M02-full-review',
        );
        await tester.tap(find.byKey(const Key('ai-review-back')));
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}

/// Exercises the production HTTP client and native PTY with predictable replies.
/// It contains no credentials and never reaches an external model provider.
class _ResponseFixture {
  _ResponseFixture(this.server);
  final HttpServer server;
  Map<String, Object?>? next;
  int requests = 0;
  int? nextStatus;
  bool disconnectNext = false;
  final payloads = <Map<String, Object?>>[];
  static Future<_ResponseFixture> start() async {
    final fixture = _ResponseFixture(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fixture.server.listen((request) async {
      final data =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, Object?>;
      fixture.payloads.add(data);
      fixture.requests++;
      if (fixture.disconnectNext) {
        fixture.disconnectNext = false;
        (await request.response.detachSocket(writeHeaders: false)).destroy();
        return;
      }
      if (fixture.nextStatus case final int status) {
        fixture.nextStatus = null;
        request.response.statusCode = status;
        await request.response.close();
        return;
      }
      var message = fixture.next;
      fixture.next = null;
      if (message == null) {
        final messages = data['messages']! as List;
        final results = messages.where((m) => (m as Map)['role'] == 'tool');
        String? blockId;
        if (results.isNotEmpty) {
          final result =
              jsonDecode((results.last as Map)['content'] as String) as Map;
          blockId = result['block_id'] as String?;
        }
        message = {
          'role': 'assistant',
          'content': blockId == null
              ? 'The current screen has been inspected.'
              : 'The command receipt is linked to its original output. [block:$blockId:1-1]',
        };
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'id': 'fixture-${fixture.requests}',
          'model': 'fixture',
          'choices': [
            {'message': message},
          ],
        }),
      );
      await request.response.close();
    });
    return fixture;
  }

  void propose(String name, Map<String, Object?> arguments) {
    next = {
      'role': 'assistant',
      'content': 'Review this action on the current target.',
      'tool_calls': [
        {
          'id': 'fixture-action-${requests + 1}',
          'type': 'function',
          'function': {'name': name, 'arguments': jsonEncode(arguments)},
        },
      ],
    };
  }

  Future<void> close() async {
    await server.close(force: true);
  }
}
