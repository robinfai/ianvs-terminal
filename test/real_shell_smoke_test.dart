import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_pty/flutterm_pty.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart';
import 'package:ianvs_terminal/src/clipboard_client.dart';
import 'package:ianvs_terminal/src/fig_completion.dart';
import 'package:ianvs_terminal/src/local_shell_session_controller.dart';
import 'package:ianvs_terminal/src/saved_commands.dart';
import 'package:ianvs_terminal/src/session_restore.dart';
import 'package:ianvs_terminal/src/shell_integration.dart';
import 'package:ianvs_terminal/src/terminal_blocks.dart';
import 'package:ianvs_terminal/src/terminal_settings.dart';
import 'package:ianvs_terminal/src/terminal_tabs_controller.dart';

void main() {
  final coreLibraryPath = Platform.environment['FLUTTERM_CORE_LIB'];
  final skipReason = _skipReason(coreLibraryPath);
  final zshSkipReason = skipReason ?? _zshSkipReason();

  test(
    'real local shell echoes through flutterm runtime',
    () async {
      final backend = NativePtyBackend.load();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        TerminalSessionConfig(
          launch: TerminalLaunchConfig(
            program: '/bin/sh',
            cwd: Platform.environment['HOME'],
            env: const <String, String>{'TERM': 'xterm-256color'},
          ),
        ),
      );

      runtime.resizeSession(sessionId, const Size(960, 540), 1);
      runtime.sendInput(
        sessionId,
        Uint8List.fromList(utf8.encode('echo ianvs\n')),
      );

      final visibleText = await _waitForVisibleText(
        runtime: runtime,
        sessionId: sessionId,
        needle: 'ianvs',
      );

      expect(visibleText, contains('ianvs'));
    },
    skip: skipReason,
    timeout: const Timeout(Duration(seconds: 12)),
  );

  test(
    'real local shell preserves output before reporting exit code',
    () async {
      final backend = NativePtyBackend.load();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
      );
      addTearDown(runtime.dispose);

      final visibleFrames = <String>[];
      final exitCodeCompleter = Completer<int?>();
      final events = runtime.events.listen((event) {
        switch (event) {
          case TerminalSessionFrameEvent(:final frame):
            visibleFrames.add(_visibleText(frame));
          case TerminalSessionExitEvent(:final exitCode):
            if (!exitCodeCompleter.isCompleted) {
              exitCodeCompleter.complete(exitCode);
            }
          case TerminalSessionShellHookEvent():
            break;
        }
      });
      addTearDown(events.cancel);

      final sessionId = runtime.createSession(
        TerminalSessionConfig(
          launch: TerminalLaunchConfig(
            program: '/bin/sh',
            cwd: Platform.environment['HOME'],
            env: const <String, String>{'TERM': 'xterm-256color'},
          ),
        ),
      );

      runtime.resizeSession(sessionId, const Size(960, 540), 1);
      runtime.sendInput(
        sessionId,
        Uint8List.fromList(utf8.encode('echo ianvs && exit 7\n')),
      );

      final visibleText = await _waitForCapturedText(
        visibleFrames: visibleFrames,
        needle: 'ianvs',
      );
      final code = await exitCodeCompleter.future.timeout(
        const Duration(seconds: 8),
      );

      expect(visibleText, contains('ianvs'));
      expect(code, 7);
    },
    skip: skipReason,
    timeout: const Timeout(Duration(seconds: 12)),
  );

  test(
    'product shell controller can find and copy real terminal output',
    () async {
      final clipboard = _SmokeClipboardClient(
        "printf 'alpha\\nianvs\\nomega\\n'\n",
      );
      final controller = LocalShellSessionController(
        backendFactory: NativePtyBackend.load,
        clipboardClient: clipboard,
        sessionConfigFactory: _smokeSessionConfig,
      );
      addTearDown(controller.dispose);

      controller.start();
      controller.resizeSession(const Size(960, 540), 1);
      await controller.pasteClipboard();
      await controller.modernInputController.submit();

      await _waitForControllerText(controller: controller, needle: 'ianvs');

      controller.openFind();
      controller.updateFindQuery('ianvs');

      expect(controller.findState.matches, isNotEmpty);
      expect(controller.findState.displayIndex, 1);

      await controller.copySelection();

      expect(clipboard.copied, contains('ianvs'));
    },
    skip: skipReason,
    timeout: const Timeout(Duration(seconds: 12)),
  );

  test(
    'product tabs controller keeps two real local shells isolated',
    () async {
      final clipboard = _SmokeClipboardClient('echo tab-one\n');
      final savedCommands = SavedCommandsController.memory();
      final tabs = TerminalTabsController(
        backendFactory: NativePtyBackend.load,
        clipboardClient: clipboard,
        savedCommandsController: savedCommands,
        settingsController: _smokeSettingsController(),
      );
      addTearDown(() {
        tabs.dispose();
        savedCommands.dispose();
      });

      tabs.createInitialTab();
      tabs.activeShell.resizeSession(const Size(960, 540), 1);
      await tabs.activeShell.pasteClipboard();
      await tabs.activeShell.modernInputController.submit();

      await _waitForControllerText(
        controller: tabs.activeShell,
        needle: 'tab-one',
      );

      clipboard.text = 'echo tab-two\n';
      tabs.newTab();
      tabs.activeShell.resizeSession(const Size(960, 540), 1);
      await tabs.activeShell.pasteClipboard();
      await tabs.activeShell.modernInputController.submit();

      await _waitForControllerText(
        controller: tabs.activeShell,
        needle: 'tab-two',
      );

      tabs.previousTab();
      await _waitForControllerText(
        controller: tabs.activeShell,
        needle: 'tab-one',
      );

      tabs.closeActiveTab();

      expect(tabs.tabs.length, 1);
      await _waitForControllerText(
        controller: tabs.activeShell,
        needle: 'tab-two',
      );
    },
    skip: skipReason,
    timeout: const Timeout(Duration(seconds: 16)),
  );

  test(
    'product tabs controller keeps two split panes isolated',
    () async {
      final clipboard = _SmokeClipboardClient('echo pane-one\n');
      final savedCommands = SavedCommandsController.memory();
      final tabs = TerminalTabsController(
        backendFactory: NativePtyBackend.load,
        clipboardClient: clipboard,
        savedCommandsController: savedCommands,
        settingsController: _smokeSettingsController(),
      );
      addTearDown(() {
        tabs.dispose();
        savedCommands.dispose();
      });

      tabs.createInitialTab();
      tabs.activeShell.resizeSession(const Size(720, 420), 1);
      await tabs.activeShell.pasteClipboard();
      await tabs.activeShell.modernInputController.submit();

      await _waitForControllerText(
        controller: tabs.activeShell,
        needle: 'pane-one',
      );

      clipboard.text = 'echo pane-two\n';
      tabs.splitActivePaneRight();
      tabs.activeShell.resizeSession(const Size(720, 420), 1);
      await tabs.activeShell.pasteClipboard();
      await tabs.activeShell.modernInputController.submit();

      await _waitForControllerText(
        controller: tabs.activeShell,
        needle: 'pane-two',
      );

      tabs.previousPane();
      await _waitForControllerText(
        controller: tabs.activeShell,
        needle: 'pane-one',
      );

      tabs.closeActivePane();

      expect(tabs.activeTab.paneCount, 1);
      await _waitForControllerText(
        controller: tabs.activeShell,
        needle: 'pane-two',
      );
    },
    skip: skipReason,
    timeout: const Timeout(Duration(seconds: 18)),
  );

  test(
    'product split pane inherits zsh cwd for path completions',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'ianvs_terminal_pane_cwd_',
      );
      final savedCommands = SavedCommandsController.memory();
      addTearDown(() {
        savedCommands.dispose();
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final nested = Directory('${dir.path}/nested')..createSync();
      File('${nested.path}/ianvs-pane-file.txt').writeAsStringSync('ok');
      final tabs = TerminalTabsController(
        backendFactory: NativePtyBackend.load,
        clipboardClient: _SmokeClipboardClient(''),
        savedCommandsController: savedCommands,
        settingsController: _smokeSettingsController(defaultShell: '/bin/zsh'),
        completionRepository: _smokeCompletionRepository(),
      );
      addTearDown(tabs.dispose);

      tabs.createInitialTab();
      tabs.activeShell.resizeSession(const Size(720, 420), 1);
      tabs.activeShell.modernInputController.updateDraft('cd ${nested.path}');
      await tabs.activeShell.modernInputController.submit();
      await _waitForCompletionCwd(
        controller: tabs.activeShell,
        needle: nested.path,
      );

      tabs.splitActivePaneRight();
      tabs.activeShell.resizeSession(const Size(720, 420), 1);
      await _waitForCompletionCwd(
        controller: tabs.activeShell,
        needle: nested.path,
      );
      final accepted = await tabs.activeShell.completionController
          .completeOrAccept(
            const TextEditingValue(
              text: 'demo --config ianvs-pane',
              selection: TextSelection.collapsed(offset: 24),
            ),
          );

      expect(accepted, isNotNull);
      expect(accepted!.text, 'demo --config ianvs-pane-file.txt');
    },
    skip: zshSkipReason,
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'product session restore recreates tabs panes and cwd',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'ianvs_terminal_restore_',
      );
      final savedCommands = SavedCommandsController.memory();
      final store = TerminalSessionRestoreStore(
        file: File('${dir.path}/session_restore.json'),
      );
      TerminalTabsController? tabs;
      TerminalTabsController? restoredTabs;
      TerminalSessionRestoreController? restoreController;
      TerminalSessionRestoreController? restoredRestoreController;

      addTearDown(() {
        restoredTabs?.dispose();
        tabs?.dispose();
        restoredRestoreController?.dispose();
        restoreController?.dispose();
        savedCommands.dispose();
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });

      final nested = Directory('${dir.path}/nested')..createSync();
      File('${nested.path}/restore-marker').writeAsStringSync('ok');
      restoreController = TerminalSessionRestoreController(
        store: store,
        debounceDuration: Duration.zero,
      );
      tabs = TerminalTabsController(
        backendFactory: NativePtyBackend.load,
        clipboardClient: _SmokeClipboardClient(''),
        savedCommandsController: savedCommands,
        settingsController: _smokeSettingsController(defaultShell: '/bin/zsh'),
        sessionRestoreController: restoreController,
      );

      tabs.createInitialTab();
      tabs.activeShell.resizeSession(const Size(720, 420), 1);
      tabs.activeShell.modernInputController.updateDraft('cd ${nested.path}');
      await tabs.activeShell.modernInputController.submit();
      await _waitForCompletionCwd(
        controller: tabs.activeShell,
        needle: nested.path,
      );

      tabs.splitActivePaneRight();
      tabs.activeShell.resizeSession(const Size(720, 420), 1);
      await _waitForCompletionCwd(
        controller: tabs.activeShell,
        needle: nested.path,
      );
      final activePaneId = tabs.activePane.id;
      tabs.newTab();
      tabs.selectTab(0);

      expect(tabs.tabs.length, 2);
      expect(tabs.activeIndex, 0);
      expect(tabs.activeTab.paneCount, 2);

      tabs.dispose();
      tabs = null;
      restoreController.dispose();
      restoreController = null;

      restoredRestoreController = TerminalSessionRestoreController(
        store: store,
        debounceDuration: Duration.zero,
      );
      restoredTabs = TerminalTabsController(
        backendFactory: NativePtyBackend.load,
        clipboardClient: _SmokeClipboardClient(''),
        savedCommandsController: savedCommands,
        settingsController: _smokeSettingsController(defaultShell: '/bin/zsh'),
        sessionRestoreController: restoredRestoreController,
      );

      restoredTabs.createInitialTab();

      expect(restoredTabs.tabs.length, 2);
      expect(restoredTabs.activeIndex, 0);
      expect(restoredTabs.activeTab.paneCount, 2);
      expect(restoredTabs.activePane.id, activePaneId);

      restoredTabs.activeShell.resizeSession(const Size(720, 420), 1);
      restoredTabs.activeShell.modernInputController.updateDraft(
        'test -f restore-marker && echo ianvs-restore-cwd',
      );
      await restoredTabs.activeShell.modernInputController.submit();

      final visibleText = await _waitForControllerText(
        controller: restoredTabs.activeShell,
        needle: 'ianvs-restore-cwd',
      );

      expect(visibleText, contains('ianvs-restore-cwd'));
    },
    skip: zshSkipReason,
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'product tabs controller uses default shell setting for new local shells',
    () async {
      final clipboard = _SmokeClipboardClient('echo settings-shell\n');
      final savedCommands = SavedCommandsController.memory();
      final tabs = TerminalTabsController(
        backendFactory: NativePtyBackend.load,
        clipboardClient: clipboard,
        savedCommandsController: savedCommands,
        settingsController: _smokeSettingsController(),
      );
      addTearDown(() {
        tabs.dispose();
        savedCommands.dispose();
      });

      tabs.createInitialTab();
      tabs.activeShell.resizeSession(const Size(960, 540), 1);
      await tabs.activeShell.pasteClipboard();
      await tabs.activeShell.modernInputController.submit();

      await _waitForControllerText(
        controller: tabs.activeShell,
        needle: 'settings-shell',
      );
    },
    skip: skipReason,
    timeout: const Timeout(Duration(seconds: 12)),
  );

  test(
    'product local shell shows startup prompt across repeated starts',
    () async {
      for (var attempt = 0; attempt < 5; attempt += 1) {
        final prompt = 'ianvs-prompt-$attempt> ';
        final controller = LocalShellSessionController(
          backendFactory: NativePtyBackend.load,
          clipboardClient: _SmokeClipboardClient(''),
          sessionConfigFactory: () => _promptSessionConfig(prompt),
        );

        try {
          controller.start();
          controller.resizeSession(const Size(960, 540), 1);

          final visibleText = await _waitForControllerText(
            controller: controller,
            needle: prompt.trim(),
          );

          expect(visibleText, contains(prompt.trim()));
        } finally {
          controller.dispose();
        }
      }
    },
    skip: skipReason,
    timeout: const Timeout(Duration(seconds: 24)),
  );

  test(
    'product modern input submits real shell command',
    () async {
      final controller = LocalShellSessionController(
        backendFactory: NativePtyBackend.load,
        clipboardClient: _SmokeClipboardClient(''),
        sessionConfigFactory: _smokeSessionConfig,
      );
      addTearDown(controller.dispose);

      controller.start();
      controller.resizeSession(const Size(960, 540), 1);
      controller.modernInputController.updateDraft('echo ianvs-modern');
      await controller.modernInputController.submit();

      final visibleText = await _waitForControllerText(
        controller: controller,
        needle: 'ianvs-modern',
      );

      expect(visibleText, contains('ianvs-modern'));
    },
    skip: skipReason,
    timeout: const Timeout(Duration(seconds: 12)),
  );

  test(
    'product zsh shell integration creates real command blocks',
    () async {
      final dir = Directory.systemTemp.createTempSync('ianvs_terminal_zsh_');
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final clipboard = _SmokeClipboardClient(
        'echo ianvs-modern-block\nfalse\n',
      );
      final controller = LocalShellSessionController(
        backendFactory: NativePtyBackend.load,
        clipboardClient: clipboard,
        sessionConfigFactory: () => _zshIntegratedSessionConfig(dir),
      );
      addTearDown(controller.dispose);

      controller.start();
      controller.resizeSession(const Size(960, 540), 1);
      await controller.pasteClipboard();
      await controller.modernInputController.submit();

      final blocks = await _waitForBlocks(controller: controller, count: 2);
      final echoBlock = blocks.firstWhere(
        (block) => block.commandText == 'echo ianvs-modern-block',
      );
      final falseBlock = blocks.firstWhere(
        (block) => block.commandText == 'false',
      );

      expect(echoBlock.status, TerminalBlockStatus.succeeded);
      expect(echoBlock.outputText, contains('ianvs-modern-block'));
      expect(falseBlock.status, TerminalBlockStatus.failed);
    },
    skip: zshSkipReason,
    timeout: const Timeout(Duration(seconds: 16)),
  );

  test(
    'product command history search reinputs a real zsh block',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'ianvs_terminal_history_',
      );
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final controller = LocalShellSessionController(
        backendFactory: NativePtyBackend.load,
        clipboardClient: _SmokeClipboardClient(''),
        sessionConfigFactory: () => _zshIntegratedSessionConfig(dir),
      );
      addTearDown(controller.dispose);

      controller.start();
      controller.resizeSession(const Size(960, 540), 1);
      controller.modernInputController.updateDraft('echo ianvs-history');
      await controller.modernInputController.submit();

      await _waitForBlocks(controller: controller, count: 1);
      controller.commandHistoryController.open();
      controller.commandHistoryController.updateQuery('history');

      expect(
        controller.commandHistoryController.matches.single.commandText,
        'echo ianvs-history',
      );

      await controller.commandHistoryController.chooseActiveEntry();

      expect(
        controller.modernInputController.state.draft,
        'echo ianvs-history',
      );
    },
    skip: zshSkipReason,
    timeout: const Timeout(Duration(seconds: 16)),
  );

  test(
    'product saved command library reloads a real zsh block command',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'ianvs_terminal_saved_command_',
      );
      final controllers = <LocalShellSessionController>[];
      final savedControllers = <SavedCommandsController>[];
      addTearDown(() {
        for (final controller in controllers) {
          controller.dispose();
        }
        for (final controller in savedControllers) {
          controller.dispose();
        }
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final store = SavedCommandsStore(
        file: File('${dir.path}/saved_commands.json'),
      );
      final saved = SavedCommandsController(store: store);
      savedControllers.add(saved);
      final controller = LocalShellSessionController(
        backendFactory: NativePtyBackend.load,
        clipboardClient: _SmokeClipboardClient(''),
        savedCommandsController: saved,
        sessionConfigFactory: () => _zshIntegratedSessionConfig(dir),
      );
      controllers.add(controller);

      controller.start();
      controller.resizeSession(const Size(960, 540), 1);
      controller.modernInputController.updateDraft('echo ianvs-saved-command');
      await controller.modernInputController.submit();

      await _waitForBlocks(controller: controller, count: 1);
      controller.commandHistoryController.updateQuery('saved-command');
      expect(controller.commandHistoryController.saveActiveEntry(), isTrue);
      expect(saved.commands, <String>['echo ianvs-saved-command']);

      final reloadedSaved = SavedCommandsController(store: store);
      savedControllers.add(reloadedSaved);
      final reloadedController = LocalShellSessionController(
        backendFactory: NativePtyBackend.load,
        clipboardClient: _SmokeClipboardClient(''),
        savedCommandsController: reloadedSaved,
        sessionConfigFactory: () => _zshIntegratedSessionConfig(dir),
      );
      controllers.add(reloadedController);
      reloadedController.start();
      reloadedController.resizeSession(const Size(960, 540), 1);
      reloadedController.commandHistoryController.updateQuery('saved-command');

      expect(
        reloadedController.commandHistoryController.matches.single.commandText,
        'echo ianvs-saved-command',
      );

      await reloadedController.commandHistoryController.chooseActiveEntry();

      expect(
        reloadedController.modernInputController.state.draft,
        'echo ianvs-saved-command',
      );
    },
    skip: zshSkipReason,
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'product completion uses zsh cwd for file path templates',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'ianvs_terminal_completion_cwd_',
      );
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final home = Directory('${dir.path}/home')..createSync(recursive: true);
      final nested = Directory('${home.path}/nested')..createSync();
      File('${nested.path}/ianvs-file.txt').writeAsStringSync('ok');
      final controller = LocalShellSessionController(
        backendFactory: NativePtyBackend.load,
        clipboardClient: _SmokeClipboardClient(''),
        completionRepository: _smokeCompletionRepository(),
        sessionConfigFactory: () =>
            _zshIntegratedSessionConfigForHome(supportDir: dir, home: home),
      );
      addTearDown(controller.dispose);

      controller.start();
      controller.resizeSession(const Size(960, 540), 1);
      controller.modernInputController.updateDraft('cd nested');
      await controller.modernInputController.submit();
      await _waitForCompletionCwd(controller: controller, needle: '/nested');

      final accepted = await controller.completionController.completeOrAccept(
        const TextEditingValue(
          text: 'demo --config ian',
          selection: TextSelection.collapsed(offset: 17),
        ),
      );

      expect(accepted, isNotNull);
      expect(accepted!.text, 'demo --config ianvs-file.txt');
    },
    skip: zshSkipReason,
    timeout: const Timeout(Duration(seconds: 18)),
  );

  test(
    'product completion suggests executable root commands from PATH',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'ianvs_terminal_completion_path_',
      );
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      final bin = Directory('${dir.path}/bin')..createSync();
      final tool = File('${bin.path}/ianvs-root-tool')
        ..writeAsStringSync('#!/bin/sh\n');
      Process.runSync('chmod', <String>['755', tool.path]);
      final controller = LocalShellSessionController(
        backendFactory: NativePtyBackend.load,
        clipboardClient: _SmokeClipboardClient(''),
        completionEnvironment: <String, String>{'PATH': bin.path},
        completionRepository: FigCompletionRepository.empty(),
        sessionConfigFactory: _smokeSessionConfig,
      );
      addTearDown(controller.dispose);

      controller.start();
      controller.resizeSession(const Size(960, 540), 1);
      final accepted = await controller.completionController.completeOrAccept(
        const TextEditingValue(
          text: 'ianvs-root',
          selection: TextSelection.collapsed(offset: 10),
        ),
      );

      expect(accepted, isNotNull);
      expect(accepted!.text, 'ianvs-root-tool');
    },
    skip: skipReason,
    timeout: const Timeout(Duration(seconds: 12)),
  );
}

TerminalSessionConfig _smokeSessionConfig() {
  return TerminalSessionConfig(
    launch: TerminalLaunchConfig(
      program: '/bin/sh',
      cwd: Platform.environment['HOME'],
      env: const <String, String>{'TERM': 'xterm-256color'},
    ),
  );
}

TerminalSessionConfig _promptSessionConfig(String prompt) {
  return TerminalSessionConfig(
    launch: TerminalLaunchConfig(
      program: '/bin/sh',
      args: const <String>['-i'],
      cwd: Platform.environment['HOME'],
      env: <String, String>{
        'TERM': 'xterm-256color',
        'PS1': prompt,
        'ENV': '/dev/null',
      },
    ),
  );
}

TerminalSessionConfig _zshIntegratedSessionConfig(Directory dir) {
  final home = Directory('${dir.path}/home')..createSync(recursive: true);
  return _zshIntegratedSessionConfigForHome(supportDir: dir, home: home);
}

TerminalSessionConfig _zshIntegratedSessionConfigForHome({
  required Directory supportDir,
  required Directory home,
}) {
  return applyShellIntegration(
    TerminalSessionConfig(
      launch: TerminalLaunchConfig(
        program: '/bin/zsh',
        args: const <String>['-i'],
        cwd: home.path,
        env: <String, String>{'HOME': home.path, 'TERM': 'xterm-256color'},
      ),
    ),
    applicationSupportDirectory: supportDir,
    environment: <String, String>{'HOME': home.path},
  );
}

TerminalSettingsController _smokeSettingsController({
  String defaultShell = '/bin/sh',
}) {
  final dir = Directory.systemTemp.createTempSync('ianvs_terminal_smoke_');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  final controller = TerminalSettingsController(
    store: TerminalSettingsStore(
      file: File('${dir.path}/settings.json'),
      defaultShell: defaultShell,
    ),
  );
  addTearDown(controller.dispose);
  return controller;
}

String? _skipReason(String? coreLibraryPath) {
  if (!Platform.isMacOS) {
    return 'Real shell smoke is macOS-only for M0.';
  }
  if (coreLibraryPath == null || coreLibraryPath.isEmpty) {
    return 'Set FLUTTERM_CORE_LIB to run the real flutterm shell smoke.';
  }
  if (!File(coreLibraryPath).existsSync()) {
    return 'FLUTTERM_CORE_LIB does not point to an existing dylib.';
  }
  return null;
}

String? _zshSkipReason() {
  if (!File('/bin/zsh').existsSync()) {
    return '/bin/zsh is required for zsh shell integration smoke.';
  }
  return null;
}

Future<String> _waitForVisibleText({
  required TerminalRuntimeController runtime,
  required String sessionId,
  required String needle,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  var visibleText = '';

  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    visibleText = _visibleText(runtime.viewportFor(sessionId).frame);
    if (visibleText.contains(needle)) {
      return visibleText;
    }
  }

  fail('Timed out waiting for "$needle" in terminal frame:\n$visibleText');
}

String _visibleText(TerminalFrameDiff frame) {
  return frame.rows.map((row) => row.text).join('\n');
}

Future<String> _waitForCapturedText({
  required List<String> visibleFrames,
  required String needle,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (DateTime.now().isBefore(deadline)) {
    for (final visibleText in visibleFrames.reversed) {
      if (visibleText.contains(needle)) {
        return visibleText;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  fail('Timed out waiting for "$needle" in terminal frames:\n$visibleFrames');
}

Future<String> _waitForControllerText({
  required LocalShellSessionController controller,
  required String needle,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  var visibleText = '';

  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    visibleText = _visibleText(controller.viewportController.frame);
    if (visibleText.contains(needle)) {
      return visibleText;
    }
  }

  fail('Timed out waiting for "$needle" in terminal frame:\n$visibleText');
}

Future<List<TerminalBlock>> _waitForBlocks({
  required LocalShellSessionController controller,
  required int count,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final blocks = controller.blocksController.blocks;
    if (blocks.length >= count &&
        blocks
            .take(count)
            .every((block) => block.status != TerminalBlockStatus.running)) {
      return blocks;
    }
  }

  fail(
    'Timed out waiting for $count blocks: '
    '${controller.blocksController.blocks.map((block) => '${block.commandText}:${block.status.label}').toList()}',
  );
}

Future<void> _waitForCompletionCwd({
  required LocalShellSessionController controller,
  required String needle,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (controller.completionController.cwd.endsWith(needle)) {
      return;
    }
  }

  fail('Timed out waiting for completion cwd ending with $needle');
}

FigCompletionRepository _smokeCompletionRepository() {
  return FigCompletionRepository.memory(
    index: const FigCompletionIndex(
      commands: <FigCompletionCommandRef>[
        FigCompletionCommandRef(name: 'demo', specPath: 'specs/demo.json'),
      ],
    ),
    specs: const <String, FigCompletionSpec>{
      'specs/demo.json': FigCompletionSpec(
        names: <String>['demo'],
        options: <FigCompletionOption>[
          FigCompletionOption(
            names: <String>['--config'],
            args: <FigCompletionArg>[
              FigCompletionArg(name: 'file', templates: <String>['filepaths']),
            ],
          ),
        ],
      ),
    },
  );
}

class _SmokeClipboardClient implements ClipboardClient {
  _SmokeClipboardClient(this.text);

  String text;
  final List<String> copied = <String>[];

  @override
  Future<String> readText() async => text;

  @override
  Future<void> writeText(String text) async {
    copied.add(text);
    this.text = text;
  }
}
