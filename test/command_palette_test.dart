import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_pty/flutterm_pty.dart';

import 'package:ianvs_terminal/src/clipboard_client.dart';
import 'package:ianvs_terminal/src/command_palette.dart';
import 'package:ianvs_terminal/src/launch_config.dart';
import 'package:ianvs_terminal/src/saved_commands.dart';
import 'package:ianvs_terminal/src/terminal_blocks.dart';
import 'package:ianvs_terminal/src/terminal_settings.dart';
import 'package:ianvs_terminal/src/terminal_windows.dart';

void main() {
  test('builds saved history and session entries across app windows', () {
    final backend = _FakePtySessionBackend();
    final saved = SavedCommandsController.memory()..addCommand('echo saved');
    final windows = _windows(backend, savedCommandsController: saved);
    final alpha = Directory.systemTemp.createTempSync('ianvs_palette_alpha_');
    final prod = Directory.systemTemp.createTempSync('ianvs_palette_prod_');
    addTearDown(() {
      windows.dispose();
      saved.dispose();
      alpha.deleteSync(recursive: true);
      prod.deleteSync(recursive: true);
    });

    windows.createInitialWindow();
    windows.activeShell.completionController.updateCwd(alpha.path);
    windows.activeShell.blocksController.addBlock(
      const TerminalBlock(
        id: 'session-1-block-1',
        sessionId: 'session-1',
        commandText: 'pwd',
        outputText: '/tmp/alpha\n',
        status: TerminalBlockStatus.succeeded,
        scrollbackOffset: 2,
        recordedAt: '2026-05-04T09:15:00Z',
      ),
    );
    windows.newWindow();
    windows.newSshTab(
      host: 'prod.example.internal',
      account: 'ops-user',
      environment: 'prod',
      project: 'payments-api',
    );
    windows.activeShell.completionController.updateCwd(prod.path);

    final entries = buildCommandPaletteEntries(
      windowsController: windows,
      savedCommandsController: saved,
    );

    expect(
      entries.where(
        (entry) => entry.source == CommandPaletteEntrySource.workflow,
      ),
      hasLength(1),
    );
    expect(
      entries.where(
        (entry) => entry.source == CommandPaletteEntrySource.history,
      ),
      hasLength(1),
    );
    expect(
      entries.where(
        (entry) => entry.source == CommandPaletteEntrySource.session,
      ),
      hasLength(3),
    );
    expect(
      entries.any(
        (entry) =>
            entry.source == CommandPaletteEntrySource.session &&
            entry.metadata.host == 'prod.example.internal' &&
            entry.lastCommand == '',
      ),
      isTrue,
    );
    final history = entries.singleWhere(
      (entry) => entry.source == CommandPaletteEntrySource.history,
    );
    expect(history.commandDetailLabel, contains('Succeeded'));
    expect(history.commandDetailLabel, contains(alpha.path));
    expect(history.commandDetailLabel, contains('2026-05-04'));
    expect(history.commandDetailLabel, contains('Output /tmp/alpha'));

    final prodSession = entries.singleWhere(
      (entry) =>
          entry.source == CommandPaletteEntrySource.session &&
          entry.metadata.host == 'prod.example.internal',
    );
    expect(prodSession.sessionDetailLabel, contains('Prompt'));
    expect(
      prodSession.sessionDetailLabel,
      contains('Target Host prod.example.internal'),
    );
    expect(prodSession.sessionDetailLabel, contains('Running'));
  });

  test(
    'controller filters unified palette by prefix and supports save/remove',
    () {
      final backend = _FakePtySessionBackend();
      final saved = SavedCommandsController.memory();
      final windows = _windows(backend, savedCommandsController: saved);
      final launchConfigDir = Directory.systemTemp.createTempSync(
        'ianvs_palette_launch_configs_',
      );
      final launchConfigStore = TerminalLaunchConfigurationStore(
        directory: launchConfigDir,
      );
      launchConfigStore.save(
        File('${launchConfigDir.path}/daily-stack.json'),
        const TerminalLaunchConfiguration(
          windows: <TerminalLaunchConfigurationWindow>[
            TerminalLaunchConfigurationWindow(
              fallbackTitle: 'Ops Window',
              tabs: <TerminalLaunchConfigurationTab>[
                TerminalLaunchConfigurationTab(
                  fallbackTitle: 'Deploy',
                  activePaneId: 1,
                  rootPane: TerminalLaunchConfigurationPaneLeaf(
                    id: 1,
                    cwd: '/tmp/payments',
                    startupCommand: 'kubectl get pods',
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      addTearDown(() {
        windows.dispose();
        saved.dispose();
        launchConfigDir.deleteSync(recursive: true);
      });

      windows.createInitialWindow();
      windows.activeShell.blocksController.addBlock(
        const TerminalBlock(
          id: 'session-1-block-1',
          sessionId: 'session-1',
          commandText: 'echo history',
          outputText: 'history\n',
          status: TerminalBlockStatus.succeeded,
          scrollbackOffset: 3,
          recordedAt: '2026-05-04T10:30:00Z',
        ),
      );
      windows.newWindow();
      windows.newSshTab(
        host: 'prod.example.internal',
        account: 'ops-user',
        environment: 'prod',
        project: 'payments-api',
      );

      final controller = CommandPaletteController(
        windowsController: windows,
        savedCommandsController: saved,
        launchConfigStore: launchConfigStore,
      );
      addTearDown(controller.dispose);

      controller.open(filter: CommandPaletteFilter.commands);
      expect(controller.countForFilter(CommandPaletteFilter.workflow), 0);
      expect(controller.countForFilter(CommandPaletteFilter.history), 1);
      expect(controller.countForFilter(CommandPaletteFilter.session), 3);
      expect(controller.countForFilter(CommandPaletteFilter.ssh), 1);
      expect(controller.countForFilter(CommandPaletteFilter.launchConfig), 1);
      controller.updateQuery('history');
      expect(
        controller.matches.single.source,
        CommandPaletteEntrySource.history,
      );
      expect(controller.saveActiveEntry(), isTrue);
      expect(saved.commands, <String>['echo history']);

      controller.updateQuery('saved:echo');
      expect(
        controller.matches.single.source,
        CommandPaletteEntrySource.workflow,
      );
      expect(controller.removeActiveEntry(), isTrue);
      expect(saved.commands, isEmpty);

      controller.updateQuery('workflow:echo');
      expect(controller.matches, isEmpty);

      controller.open(filter: CommandPaletteFilter.all);
      controller.updateQuery('launch:daily');
      expect(
        controller.matches.single.source,
        CommandPaletteEntrySource.launchConfig,
      );
      expect(
        controller.matches.single.launchConfigDetailLabel,
        contains('App config'),
      );
      expect(
        controller.matches.single.launchConfigDetailLabel,
        contains('1 panes'),
      );

      controller.updateFilter(CommandPaletteFilter.session);
      expect(controller.query, isEmpty);
      expect(controller.effectiveFilter, CommandPaletteFilter.session);
      expect(controller.matches.every((entry) => entry.isSessionEntry), isTrue);

      controller.updateQuery('session:prod');
      expect(
        controller.matches.single.source,
        CommandPaletteEntrySource.session,
      );
      expect(controller.matches.single.metadata.host, 'prod.example.internal');

      controller.updateQuery('ssh:payments');
      expect(controller.matches.single.isSshSession, isTrue);
    },
  );
}

TerminalWindowsController _windows(
  _FakePtySessionBackend backend, {
  SavedCommandsController? savedCommandsController,
}) {
  final settingsDir = Directory.systemTemp.createTempSync(
    'ianvs_command_palette_settings_',
  );
  addTearDown(() {
    if (settingsDir.existsSync()) {
      settingsDir.deleteSync(recursive: true);
    }
  });
  final settingsController = TerminalSettingsController(
    store: TerminalSettingsStore(
      file: File('${settingsDir.path}/settings.json'),
      defaultShell: '/bin/zsh',
    ),
  );
  return TerminalWindowsController(
    backendFactory: () => backend,
    clipboardClient: _FakeClipboardClient(),
    settingsController: settingsController,
    savedCommandsController:
        savedCommandsController ?? SavedCommandsController.memory(),
  );
}

class _FakeClipboardClient implements ClipboardClient {
  @override
  Future<String> readText() async => '';

  @override
  Future<void> writeText(String text) async {}
}

class _FakePtySessionBackend implements PtySessionBackend {
  int _createCount = 0;
  final Map<String, Queue<PtyEvent>> _queuedEvents =
      <String, Queue<PtyEvent>>{};

  @override
  int ping() => 42;

  @override
  String createSession(String sessionConfigJson) {
    _createCount += 1;
    return 'session-$_createCount';
  }

  @override
  void closeSession(String sessionId) {}

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    final queued = _queuedEvents[sessionId];
    if (queued == null || queued.isEmpty) {
      return const <PtyEvent>[];
    }
    final events = queued.toList(growable: false);
    queued.clear();
    return events;
  }

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
  }) {}

  @override
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {}

  @override
  String? searchTextJson(String sessionId, String query) => '[]';

  @override
  String? selectionText(String sessionId, String requestJson) => '';

  @override
  String? takeFrameDiffJson(String sessionId) {
    return jsonEncode(<String, Object?>{
      'kind': 'snapshot',
      'rows': <Object?>[],
      'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'viewport_start_row': 0,
      'viewport_row_shift': 0,
      'modes': <String, Object?>{},
      'window_title': '',
      'window_icon_name': '',
      'hyperlinks': <Object?>[],
    });
  }

  @override
  void writeInput(String sessionId, List<int> bytes) {}
}
