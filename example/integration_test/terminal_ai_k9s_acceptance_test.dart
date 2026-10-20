import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/app.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
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
import 'k9s_acceptance_fixture.dart';

class _MemoryStore implements AiConfigurationStore {
  _MemoryStore(this.value);
  AiConfiguration? value;
  @override
  Future<AiConfiguration?> read() async => value;
  @override
  Future<void> write(AiConfiguration? configuration) async =>
      value = configuration;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const evidencePath = String.fromEnvironment('TRAIL_K9S_EVIDENCE');
  const executable = String.fromEnvironment(
    'TRAIL_K9S_BINARY',
    defaultValue: '/opt/homebrew/bin/k9s',
  );
  testWidgets(
    'k9s uses the full grid and hands AI input back to the same PTY',
    (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      expect(
        await File(executable).exists(),
        true,
        reason: 'Provide TRAIL_K9S_BINARY',
      );
      final fixture = await K9sAcceptanceFixture.start();
      final home = await Directory('/private/tmp').createTemp('trail-k9s-ui-');
      await fixture.writeConfig(home);
      await File(
        '${home.path}/.zshrc',
      ).writeAsString("PROMPT='trail-k9s> '\nRPROMPT=''\n");
      final settings = AiSettingsController(
        _MemoryStore(
          AiConfiguration(
            endpoint: 'http://127.0.0.1:${fixture.server.port}/v1',
            apiKey: 'synthetic-k9s-fixture',
            model: 'fixture',
          ),
        ),
      );
      final profile = TerminalProfile(
        id: 'k9s-ui',
        name: 'K9s isolated acceptance',
        shell: '/bin/zsh',
        cwd: home.path,
        env: {
          'HOME': home.path,
          'ZDOTDIR': home.path,
          'XDG_CONFIG_HOME': home.path,
          'XDG_DATA_HOME': home.path,
          'K9S_CONFIG_DIR': '${home.path}/k9s',
          'KUBECONFIG': '${home.path}/kubeconfig.json',
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
                defaultProfileId: 'k9s-ui',
                appearance: TerminalAppAppearance(
                  themeMode: TerminalThemeMode.dark,
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
      final result = <String, Object?>{
        'passed': false,
        'fixture':
            'actual k9s and native PTY; synthetic Kubernetes API and AI responses',
      };
      final runtime = container.read(terminalRuntimeControllerProvider);
      final writes = <List<int>>[];
      final subscription = runtime.inputEvents.listen(
        (event) => writes.add(event.bytes.toList()),
      );
      Future<void> capture(String name) async {
        if (evidencePath.isEmpty || captureKey.currentContext == null) return;
        await tester.pump();
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(evidencePath).create(recursive: true);
        await File(
          '$evidencePath/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

      addTearDown(() async {
        final id = container.read(sessionControllerProvider).activeSessionId;
        if (id != null) result['final_screen'] = runtime.liveScreen(id);
        if (result['passed'] != true) await capture('failure');
        await tester.pumpWidget(const SizedBox.shrink());
        for (final tab in container.read(sessionControllerProvider).tabs) {
          for (final pane in tab.effectivePanes) {
            await container
                .read(sessionControllerProvider.notifier)
                .closeSession(pane.sessionId);
          }
        }
        await subscription.cancel();
        container.dispose();
        settings.dispose();
        await fixture.close();
        if (evidencePath.isNotEmpty) {
          await Directory(evidencePath).create(recursive: true);
          await File(
            '$evidencePath/result.json',
          ).writeAsString(jsonEncode(result));
          await File(
            '$evidencePath/requests.json',
          ).writeAsString(jsonEncode(fixture.requests));
          await File(
            '$evidencePath/ai-payloads.json',
          ).writeAsString(jsonEncode(fixture.aiPayloads));
          await File(
            '$evidencePath/input-bytes.json',
          ).writeAsString(jsonEncode(writes));
          final log = File('${home.path}/k9s.log');
          if (await log.exists()) await log.copy('$evidencePath/k9s.log');
        }
        await home.delete(recursive: true);
      });
      Future<void> waitFor(bool Function() ready, String label) async {
        result['stage'] = label;
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!ready()) {
          if (DateTime.now().isAfter(deadline)) fail('Timed out: $label');
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      Future<void> click(Key key) async {
        await waitFor(
          () => find.byKey(key).evaluate().isNotEmpty,
          'control $key',
        );
        await tester.ensureVisible(find.byKey(key));
        await tester.tap(find.byKey(key));
        await tester.pump(const Duration(milliseconds: 200));
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
      Map<String, Object?>? shell() =>
          runtime.composerRequest(id, 'composer.state', const {});
      String screen() => runtime.liveScreen(id)?['text'] as String? ?? '';
      List<Map<String, Object?>> blocks() =>
          (runtime.commandBlocks(id)!['blocks']! as List)
              .cast<Map<String, Object?>>();
      TerminalViewport viewport() =>
          tester.widget<TerminalViewport>(find.byType(TerminalViewport));
      (Object?, Object?) grid() =>
          (runtime.liveScreen(id)?['rows'], runtime.liveScreen(id)?['columns']);
      await waitFor(
        () =>
            shell()?['state'] == 'ready' &&
            find.byType(TerminalCommandBlocksView).evaluate().isNotEmpty,
        'initial Blocks ready',
      );
      final command =
          "'$executable' --kubeconfig '${home.path}/kubeconfig.json' "
          "--readonly --splashless -c pods --logFile '${home.path}/k9s.log' --request-timeout 3s";
      Future<void> launch(int pass) async {
        runtime.composerRequest(id, 'composer.submit', {
          'lease': shell()!['lease'],
          'submissionId': 'k9s-native-$pass',
          'text': command,
        });
        await waitFor(
          () =>
              runtime.liveScreen(id)?['alternateScreen'] == true &&
              screen().contains('trail-fixture-pod'),
          'k9s Pod list $pass',
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(TerminalCommandBlocksView), findsNothing);
        expect(find.byType(TerminalComposerView), findsNothing);
        expect(viewport().controller.frame.modes.mouseMode, isNot('off'));
      }

      await launch(1);
      final size = tester.getSize(find.byType(TerminalViewport));
      final cell = viewport().controller.measuredCellSize!;
      final expectedGrid = (
        ((size.height - viewport().contentPadding.vertical) / cell.height)
            .floor(),
        ((size.width - viewport().contentPadding.horizontal) / cell.width)
            .floor(),
      );
      await waitFor(() => grid() == expectedGrid, 'full terminal grid');
      result['grid'] = [expectedGrid.$1, expectedGrid.$2];
      result['viewport'] = [size.width, size.height];
      result['mouse_mode'] = viewport().controller.frame.modes.mouseMode;
      await capture('D12-k9s-full-terminal');

      // Actual terminal input opens k9s Help; the AI overlay must not send Esc
      // through to this view when the user merely closes that overlay.
      await tester.tap(find.byType(TerminalViewport));
      viewport().inputController.sendText('?');
      await waitFor(
        () =>
            screen().contains('Help') &&
            !screen().contains('trail-fixture-pod'),
        'k9s help from terminal input',
      );
      final helpScreen = screen();
      await click(Key('terminal-ai-open-$id'));
      final task = tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .controller;
      expect(tester.getSize(find.byType(TerminalViewport)), size);
      expect(grid(), expectedGrid);
      await click(const Key('ai-prompt'));
      await tester.enterText(
        find.byKey(const Key('ai-prompt')),
        'Keep this unsent k9s question',
      );
      final beforeCopy = writes.length;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 150));
      expect(writes, hasLength(beforeCopy));
      expect(runtime.liveScreen(id)?['alternateScreen'], true);
      await capture('D12-k9s-ai-draft-overlay');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await waitFor(
        () => find.byType(TerminalAiWorkspace).evaluate().isEmpty,
        'Escape closes AI first',
      );
      expect(writes, hasLength(beforeCopy));
      expect(screen(), helpScreen);
      expect(task.draft, 'Keep this unsent k9s question');
      expect(grid(), expectedGrid);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await waitFor(
        () => find.byType(TerminalAiWorkspace).evaluate().isNotEmpty,
        'Escape in the read-only observer returns to the retained task',
      );
      expect(writes, hasLength(beforeCopy));
      expect(screen(), helpScreen);
      expect(task.draft, 'Keep this unsent k9s question');
      await click(const Key('ai-close'));
      final observer = find
          .byKey(const Key('ai-observer-viewport'))
          .hitTestable();
      expect(tester.widget<TerminalViewport>(observer).readOnly, isTrue);
      await click(const Key('ai-observer-take-over'));
      expect(observer, findsNothing);
      expect(writes, hasLength(beforeCopy));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await waitFor(
        () => screen().contains('trail-fixture-pod'),
        'Escape reaches k9s after explicit input takeover',
      );
      expect(writes.skip(beforeCopy).expand((v) => v), contains(27));
      result['ai_ctrl_c_did_not_write'] = true;
      result['first_escape_only_closed_ai'] = true;
      result['observer_escape_returned_task_without_write'] = true;
      result['explicit_takeover_then_escape_reached_k9s'] = true;

      await click(Key('terminal-ai-open-$id'));
      fixture.proposeExit();
      await click(const Key('ai-prompt'));
      await tester.enterText(
        find.byKey(const Key('ai-prompt')),
        'Propose keys to exit this isolated k9s view.',
      );
      await click(const Key('ai-send'));
      await waitFor(() => task.canApprove && !task.busy, 'k9s key proposal');
      expect(task.pending?.kind, AiActionKind.sendKeys);
      final approvedTaskId = task.taskId;
      expect(grid(), expectedGrid);
      expect(tester.getSize(find.byType(TerminalViewport)), size);
      expect(runtime.liveScreen(id)?['alternateScreen'], true);
      final beforeApproval = writes.length;
      await capture('D12-k9s-key-review');
      await click(const Key('ai-approve'));
      await waitFor(
        () =>
            find.byType(TerminalAiWorkspace).evaluate().isEmpty &&
            shell()?['state'] == 'ready',
        'approval returns to read-only observation and exits k9s',
      );
      expect(writes.skip(beforeApproval).expand((v) => v).toList(), [
        27,
        58,
        113,
        13,
      ]);
      expect(runtime.liveScreen(id)?['alternateScreen'], false);
      expect(find.byType(TerminalCommandBlocksView), findsNothing);
      expect(
        blocks().where((b) => b['command'] == command).single['exitCode'],
        0,
      );
      result['approved_keys_once'] = true;
      expect(observer, findsOneWidget);
      expect(tester.widget<TerminalViewport>(observer).readOnly, isTrue);
      expect(task.takenOver, isFalse);
      final afterApproval = writes.length;
      tester
          .widget<TerminalViewport>(observer)
          .inputController
          .sendText('observer must not write');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(writes, hasLength(afterApproval));
      await capture('D12-k9s-exit-normal');
      await click(const Key('ai-observer-take-over'));
      expect(observer, findsNothing);
      expect(task.taskId, approvedTaskId);
      expect(find.byType(TerminalAiWorkspace), findsNothing);
      expect(
        tester
            .widget<TerminalViewport>(
              find.byType(TerminalViewport).hitTestable(),
            )
            .readOnly,
        isFalse,
      );
      expect(writes, hasLength(afterApproval));
      result['approved_tui_return_remains_read_only'] = true;

      Future<void> restoreBlocks() async {
        final before = writes.length;
        await tester.tap(
          find.byKey(Key('shell-tab-$id')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await waitFor(
          () => tester
              .widget<CheckedPopupMenuItem<Object>>(
                find.byKey(Key('terminal-mode-blocks-$id')),
              )
              .enabled,
          'open menu reflects recovered Blocks capability',
        );
        await capture('D12-k9s-manual-mode-menu');
        await click(Key('terminal-mode-blocks-$id'));
        await waitFor(
          () => find.byType(TerminalCommandBlocksView).evaluate().isNotEmpty,
          'manual Blocks restore',
        );
        await tester.pumpAndSettle();
        expect(find.byKey(Key('terminal-mode-blocks-$id')), findsNothing);
        expect(writes, hasLength(before));
      }

      await restoreBlocks();
      await launch(2);
      await waitFor(() => grid() == expectedGrid, 'second full grid');
      await tester.tap(find.byType(TerminalViewport));
      final beforeInterrupt = writes.length;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await waitFor(
        () => shell()?['state'] == 'ready',
        'terminal-owned Ctrl+C exits k9s',
      );
      expect(writes.skip(beforeInterrupt).expand((v) => v), contains(3));
      expect(runtime.liveScreen(id)?['alternateScreen'], false);
      expect(find.byType(TerminalCommandBlocksView), findsNothing);
      await restoreBlocks();
      await capture('D12-k9s-restored-blocks');
      result.addAll({
        'passed': true,
        'terminal_ctrl_c_reached_k9s': true,
        'manual_blocks_restore': true,
        'same_session_id': id,
        'k9s_runs': blocks().where((b) => b['command'] == command).toList(),
        'ai_requests': fixture.aiPayloads.length,
      });
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
