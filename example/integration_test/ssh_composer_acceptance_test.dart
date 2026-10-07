import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/app.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
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
import '../test/support/no_io_local_session_recording_repository.dart';
import '../test/support/no_io_local_terminal_layout_repository.dart';
import 'composer_acceptance_test.dart' show until;
import 'ssh_disconnect_acceptance.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'SSH negotiates Blocks, changes nodes and runs fullscreen tools',
    (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      const fixturePath = String.fromEnvironment('COMPOSER_SSH_FIXTURE');
      final fixture = jsonDecode(await File(fixturePath).readAsString()) as Map;
      final cloudReadOnly = fixture['cloudReadOnly'] == true;
      final aiFixture = await SshDisconnectFixture.start();
      addTearDown(aiFixture.close);
      final lsOutput = fixture['lsOutput'] as String? ?? 'block-fixture.txt';
      final profile = TerminalProfile(
        id: 'ssh-composer',
        name: 'SSH · Command Blocks',
        shell: '',
        connection: TerminalConnectionConfig.fromJson(fixture['connection']),
      );
      final container = ProviderContainer(
        overrides: [
          aiSettingsProvider.overrideWithValue(aiFixture.settings),
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
            MemoryLocalTerminalConfigRepository(
              const LocalTerminalConfigDocument(
                defaultProfileId: 'ssh-composer',
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
      Future<void> capture(String name) async {
        const path = String.fromEnvironment('BLOCKS_NATIVE_EVIDENCE_DIR');
        if (path.isEmpty) return;
        await tester.pump();
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(path).create(recursive: true);
        await File('$path/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }

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
      final sessions = container.read(sessionControllerProvider.notifier);
      TerminalModeState mode() => container
          .read(sessionControllerProvider)
          .tabs
          .first
          .activePane
          .terminalMode;
      String context() =>
          container
              .read(sessionControllerProvider)
              .tabs
              .first
              .activePane
              .shellIntegration
              .contextId ??
          'root';
      String text() => sessions
          .viewportFor(id)
          .frame
          .rows
          .map((line) => line.text)
          .join('\n');
      await until(
        tester,
        () => mode().canUseBlocks,
        diagnostics: () => '${mode().unavailableReason}: ${text()}',
      );
      final fullSize = tester.getSize(find.byType(TerminalViewport));
      await until(
        tester,
        () => sessions.viewportFor(id).measuredCellSize != null,
      );
      final fullViewport = tester.widget<TerminalViewport>(
        find.byType(TerminalViewport),
      );
      final cell = sessions.viewportFor(id).measuredCellSize!;
      final fullRows =
          ((fullSize.height - fullViewport.contentPadding.vertical) /
                  cell.height)
              .floor();
      final fullColumns =
          ((fullSize.width - fullViewport.contentPadding.horizontal) /
                  cell.width)
              .floor();
      await until(
        tester,
        () =>
            sessions.viewportFor(id).frame.viewportRows == fullRows &&
            sessions.viewportFor(id).frame.viewportCols == fullColumns,
      );
      Future<void> blocks() async {
        await tester.tap(
          find.byKey(Key('shell-tab-$id')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CheckedPopupMenuItem<Object>>(
                find.byKey(Key('terminal-mode-blocks-$id')),
              )
              .enabled,
          isTrue,
        );
        await capture('ssh-mode-menu');
        await tester.tap(find.byKey(Key('terminal-mode-blocks-$id')));
        await tester.pumpAndSettle();
      }

      await blocks();
      final editor = find.byKey(const Key('composer-editor'));
      final model = tester
          .widget<TerminalComposerView>(find.byType(TerminalComposerView))
          .controller;
      Future<void> run(String command) async {
        await until(tester, () => model.ownership == ComposerOwnership.ready);
        await tester.tap(editor);
        await tester.enterText(editor, command);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      }

      if (cloudReadOnly) {
        // Keep this session's inspection out of personal directories/history.
        // No startup file, remote fixture, or other session is changed.
        await run('unset HISTFILE; cd /');
        await until(tester, () => model.ownership == ComposerOwnership.ready);
      }
      await run(r"printf 'Remote command blocks ready\n中文输出正常\n'");
      await until(
        tester,
        () =>
            model.ownership == ComposerOwnership.ready &&
            text().contains('Remote command blocks ready'),
      );
      expect(find.byType(TerminalCommandBlocksView), findsOneWidget);
      final commandBlocks = tester
          .widget<TerminalCommandBlocksView>(
            find.byType(TerminalCommandBlocksView),
          )
          .controller;
      await until(
        tester,
        () => commandBlocks.blocks.any(
          (block) =>
              !block.running &&
              block.exitCode == 0 &&
              block.visibleOutput.contains('中文输出正常'),
        ),
        diagnostics: () => 'No completed output block: ${text()}',
      );
      for (var index = 0; index < 2; index++) {
        await run('ls');
        await until(
          tester,
          () =>
              model.ownership == ComposerOwnership.ready &&
              commandBlocks.blocks
                      .where(
                        (block) =>
                            block.command == 'ls' &&
                            !block.running &&
                            block.exitCode == 0 &&
                            block.visibleOutput.contains(lsOutput),
                      )
                      .length ==
                  index + 1,
          diagnostics: () => 'Repeated ls lost its output block: ${text()}',
        );
      }
      await capture('ssh-block-completed');
      List<Map<String, Object?>> completedLs() => [
        for (final block in commandBlocks.blocks)
          if (block.command == 'ls')
            {
              'id': block.id,
              'command': block.command,
              'exitCode': block.exitCode,
              'output': block.visibleOutput,
              'sourceLineBase': block.sourceLineBase,
              'totalLines': block.totalLines,
            },
      ];
      final originalLs = completedLs();
      if (fixture['smokeOnly'] == true) {
        expect(tester.takeException(), isNull);
        return;
      }
      final parent = context();
      if (!cloudReadOnly) {
        await run('ssh composer-hop');
        await until(tester, () => context() != parent && mode().canUseBlocks);
        expect(mode().mode, TerminalViewMode.normal);
        expect(mode().notice, TerminalModeNotice.blocksRestored);
        await capture('ssh-hop-ready');
        await blocks();
        await run('exit');
        await until(tester, () => context() == parent && mode().canUseBlocks);
        expect(mode().mode, TerminalViewMode.normal);
      } else {
        final completedIds = commandBlocks.blocks.map((b) => b.id).toList();
        await tester.tap(
          find.byKey(Key('shell-tab-$id')),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('terminal-mode-normal-$id')));
        await tester.pumpAndSettle();
        expect(mode().mode, TerminalViewMode.normal);
        expect(find.byType(TerminalComposerView), findsNothing);
        expect(text(), contains('中文输出正常'));
        expect(commandBlocks.blocks.map((b) => b.id).toList(), completedIds);
        expect(container.read(sessionControllerProvider).activeSessionId, id);
        await capture('ssh-cloud-manual-normal');
      }
      await blocks();
      for (final program in [
        (
          name: 'top',
          command: cloudReadOnly ? '/usr/bin/top -d 1' : '/usr/bin/top -s 1',
          ready: cloudReadOnly ? 'Tasks:' : 'Processes:',
          quit: 'q',
        ),
        (
          name: 'vim',
          command: '/usr/bin/vim -Nu NONE -i NONE -n',
          ready: 'VIM',
          quit: ':q!\r',
        ),
      ]) {
        await run(program.command);
        await until(
          tester,
          () =>
              find.byType(TerminalComposerView).evaluate().isEmpty &&
              text().contains(program.ready),
          diagnostics: () => '${mode().unavailableReason}: ${text()}',
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(TerminalCommandBlocksView), findsNothing);
        final terminal = tester.widget<TerminalViewport>(
          find.byType(TerminalViewport),
        );
        expect(tester.getSize(find.byType(TerminalViewport)), fullSize);
        await until(
          tester,
          () =>
              sessions.viewportFor(id).frame.viewportRows == fullRows &&
              sessions.viewportFor(id).frame.viewportCols == fullColumns,
          diagnostics: () =>
              '${program.name}: expected $fullRows x $fullColumns; '
              'actual ${sessions.viewportFor(id).frame.viewportRows} x '
              '${sessions.viewportFor(id).frame.viewportCols}',
        );
        expect(sessions.viewportFor(id).frame.viewportRows, fullRows);
        expect(sessions.viewportFor(id).frame.viewportCols, fullColumns);
        expect(terminal.focusNode!.hasFocus, isTrue);
        await capture('ssh-fullscreen-${program.name}');
        terminal.inputController.sendText(program.quit);
        await until(
          tester,
          () =>
              model.ownership == ComposerOwnership.ready && mode().canUseBlocks,
        );
        expect(mode().mode, TerminalViewMode.normal);
        await blocks();
      }
      if (cloudReadOnly) {
        expect(context(), parent);
        expect(container.read(sessionControllerProvider).activeSessionId, id);
        expect(mode().mode, TerminalViewMode.blocks);
        await until(
          tester,
          () =>
              commandBlocks.available &&
              commandBlocks.blocks.where((b) => b.command == 'ls').length == 2,
          diagnostics: () {
            final snapshot = commandBlocks.request(const {});
            return jsonEncode({
              'available': commandBlocks.available,
              'alternateScreen': snapshot?['alternateScreen'],
              'nativeBlocks': [
                for (final block in snapshot?['blocks'] as List? ?? const [])
                  if (block is Map<String, Object?>)
                    {
                      'id': block['id'],
                      'command': block['command'],
                      'exitCode': block['exitCode'],
                      'totalLines': block['totalLines'],
                    },
              ],
            });
          },
        );
        expect(completedLs(), originalLs);
        await capture('ssh-cloud-restored-blocks');
        const evidence = String.fromEnvironment('BLOCKS_NATIVE_EVIDENCE_DIR');
        if (evidence.isNotEmpty) {
          await File('$evidence/cloud-result.json').writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'target': 'user-configured ssh cloud',
              'transport': 'production native SSH',
              'negotiated_blocks': mode().canUseBlocks,
              'completed_ls_commands': 2,
              'manual_normal_preserved_blocks_and_session': true,
              'tui_preserved_ls_identity_output_exit_and_source_rows': true,
              'fullscreen_programs': ['Linux top', 'vim'],
              'full_terminal_size': {
                'width': fullSize.width,
                'height': fullSize.height,
                'rows': fullRows,
                'columns': fullColumns,
              },
              'manual_blocks_restored_same_context': true,
              'remote_configuration_written': false,
              'scope': 'Direct SSH; nested hops use the separate loopback lab.',
            }),
          );
        }
      }
      if (fixture['disconnectPath'] case final String disconnectPath) {
        await aiFixture.verify(
          tester,
          container: container,
          sessionId: id,
          home: fixture['home'] as String,
          disconnectPath: disconnectPath,
          capture: capture,
        );
      }
      expect(tester.takeException(), isNull);
    },
    skip:
        !Platform.isMacOS ||
        const String.fromEnvironment('COMPOSER_SSH_FIXTURE').isEmpty,
  );
}
