import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/app.dart';
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
import 'composer_acceptance_test.dart' show until;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'SSH negotiates Blocks, changes nodes and runs fullscreen tools',
    (tester) async {
      ensureMacosIntegrationTestFramesEnabled(tester.binding);
      const fixturePath = String.fromEnvironment('COMPOSER_SSH_FIXTURE');
      final fixture = jsonDecode(await File(fixturePath).readAsString()) as Map;
      final lsOutput = fixture['lsOutput'] as String? ?? 'block-fixture.txt';
      final profile = TerminalProfile(
        id: 'ssh-composer',
        name: 'SSH · Command Blocks',
        shell: '',
        connection: TerminalConnectionConfig.fromJson(fixture['connection']),
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
      if (fixture['smokeOnly'] == true) {
        expect(tester.takeException(), isNull);
        return;
      }
      final parent = context();
      await run('ssh composer-hop');
      await until(tester, () => context() != parent && mode().canUseBlocks);
      expect(mode().mode, TerminalViewMode.normal);
      expect(mode().notice, TerminalModeNotice.blocksRestored);
      await capture('ssh-hop-ready');
      await blocks();
      await run('exit');
      await until(tester, () => context() == parent && mode().canUseBlocks);
      expect(mode().mode, TerminalViewMode.normal);
      await blocks();
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
      expect(tester.takeException(), isNull);
    },
    skip:
        !Platform.isMacOS ||
        const String.fromEnvironment('COMPOSER_SSH_FIXTURE').isEmpty,
  );
}
