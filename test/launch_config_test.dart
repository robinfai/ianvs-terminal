import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ianvs_terminal/src/launch_config.dart';
import 'package:ianvs_terminal/src/session_launch.dart';
import 'package:ianvs_terminal/src/session_metadata.dart';
import 'package:ianvs_terminal/src/terminal_panes.dart';

void main() {
  test('store returns empty config when file is missing', () {
    final dir = Directory.systemTemp.createTempSync('ianvs_launch_missing_');
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    const store = TerminalLaunchConfigurationStore();

    expect(
      store.load(File('${dir.path}/ianvs-terminal.launch.json')).tabs,
      isEmpty,
    );
  });

  test(
    'store saves and reloads tabs panes active state and startup commands',
    () {
      final dir = Directory.systemTemp.createTempSync('ianvs_launch_save_');
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      const store = TerminalLaunchConfigurationStore();
      final file = File('${dir.path}/ianvs-terminal.launch.json');
      final configuration = TerminalLaunchConfiguration(
        activeWindowIndex: 0,
        windows: <TerminalLaunchConfigurationWindow>[
          TerminalLaunchConfigurationWindow(
            fallbackTitle: 'Window 1',
            activeTabIndex: 1,
            tabs: <TerminalLaunchConfigurationTab>[
              TerminalLaunchConfigurationTab(
                fallbackTitle: 'Local 1',
                activePaneId: 2,
                rootPane: TerminalLaunchConfigurationPaneSplit(
                  direction: TerminalPaneSplitDirection.right,
                  ratio: 0.65,
                  first: const TerminalLaunchConfigurationPaneLeaf(
                    id: 1,
                    cwd: '/tmp/one',
                    startupCommand: 'pnpm dev',
                    sessionMetadata: TerminalSessionMetadata(
                      kind: TerminalSessionKind.ssh,
                      host: 'prod.example.internal',
                      project: 'payments-api',
                      safetyContext: TerminalSafetyContext(
                        identity: 'robin.oncall',
                      ),
                    ),
                    launchProfile: TerminalSessionLaunchProfile.sshCommand(
                      host: 'prod.example.internal',
                      account: 'ops-user',
                    ),
                  ),
                  second: const TerminalLaunchConfigurationPaneLeaf(
                    id: 2,
                    cwd: '/tmp/two',
                    startupCommand: 'flutter test',
                  ),
                ),
              ),
              const TerminalLaunchConfigurationTab(
                fallbackTitle: 'Local 2',
                activePaneId: 3,
                rootPane: TerminalLaunchConfigurationPaneLeaf(
                  id: 3,
                  cwd: '/tmp/three',
                  startupCommand: '',
                ),
              ),
            ],
          ),
        ],
      );

      store.save(file, configuration);
      final reloaded = store.load(file);

      expect(reloaded.activeTabIndex, 1);
      expect(reloaded.tabs.length, 2);
      expect(reloaded.tabs.first.fallbackTitle, 'Local 1');
      expect(reloaded.tabs.first.activePaneId, 2);
      final split =
          reloaded.tabs.first.rootPane as TerminalLaunchConfigurationPaneSplit;
      expect(split.direction, TerminalPaneSplitDirection.right);
      expect(split.ratio, 0.65);
      expect(
        (split.first as TerminalLaunchConfigurationPaneLeaf).startupCommand,
        'pnpm dev',
      );
      expect(
        (split.first as TerminalLaunchConfigurationPaneLeaf)
            .sessionMetadata
            .host,
        'prod.example.internal',
      );
      expect(
        (split.first as TerminalLaunchConfigurationPaneLeaf)
            .launchProfile
            .isSshCommand,
        isTrue,
      );
      expect(
        (split.first as TerminalLaunchConfigurationPaneLeaf)
            .sessionMetadata
            .safetyContext
            .identity,
        'robin.oncall',
      );
      expect(
        (split.second as TerminalLaunchConfigurationPaneLeaf).startupCommand,
        'flutter test',
      );
    },
  );

  test('store saves and reloads app windows with active window index', () {
    final dir = Directory.systemTemp.createTempSync('ianvs_launch_windows_');
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
    const store = TerminalLaunchConfigurationStore();
    final file = File('${dir.path}/ianvs-terminal.launch.json');
    final configuration = TerminalLaunchConfiguration(
      activeWindowIndex: 1,
      windows: <TerminalLaunchConfigurationWindow>[
        const TerminalLaunchConfigurationWindow(
          fallbackTitle: 'Window 1',
          activeTabIndex: 0,
          tabs: <TerminalLaunchConfigurationTab>[
            TerminalLaunchConfigurationTab(
              fallbackTitle: 'Local 1',
              activePaneId: 1,
              rootPane: TerminalLaunchConfigurationPaneLeaf(
                id: 1,
                cwd: '/tmp/one',
              ),
            ),
          ],
        ),
        const TerminalLaunchConfigurationWindow(
          fallbackTitle: 'Window 2',
          activeTabIndex: 0,
          tabs: <TerminalLaunchConfigurationTab>[
            TerminalLaunchConfigurationTab(
              fallbackTitle: 'SSH Prod',
              activePaneId: 2,
              rootPane: TerminalLaunchConfigurationPaneLeaf(
                id: 2,
                cwd: '/tmp/two',
                startupCommand: 'ssh prod.example.internal',
              ),
            ),
          ],
        ),
      ],
    );

    store.save(file, configuration);
    final savedJson =
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final savedWindows = savedJson['windows'] as List<Object?>;
    final reloaded = store.load(file);

    expect(savedJson['activeWindowIndex'], 1);
    expect(savedWindows, hasLength(2));
    expect(reloaded.activeWindowIndex, 1);
    expect(reloaded.windows, hasLength(2));
    expect(reloaded.windows.last.fallbackTitle, 'Window 2');
    expect(reloaded.windows.last.tabs.single.fallbackTitle, 'SSH Prod');
  });

  test('bad json empty tabs and invalid fields fall back safely', () {
    final dir = Directory.systemTemp.createTempSync('ianvs_launch_bad_');
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
    const store = TerminalLaunchConfigurationStore();
    final file = File('${dir.path}/ianvs-terminal.launch.json');

    file
      ..createSync(recursive: true)
      ..writeAsStringSync('{not json');
    expect(store.load(file).tabs, isEmpty);

    final parsedInvalid = TerminalLaunchConfiguration.fromJson(
      <String, Object?>{
        'activeTabIndex': 0,
        'tabs': <Object?>[
          <String, Object?>{
            'fallbackTitle': '',
            'activePaneId': 42,
            'rootPane': <String, Object?>{
              'type': 'split',
              'direction': 'down',
              'ratio': 9,
              'first': <String, Object?>{
                'type': 'leaf',
                'id': 7,
                'startupCommand': 'echo one',
              },
              'second': <String, Object?>{
                'type': 'leaf',
                'id': 8,
                'cwd': '/tmp/eight',
              },
            },
          },
        ],
      },
    );

    expect(parsedInvalid.tabs.single.fallbackTitle, 'Local 1');
    expect(parsedInvalid.tabs.single.activePaneId, 7);
    final split =
        parsedInvalid.tabs.single.rootPane
            as TerminalLaunchConfigurationPaneSplit;
    expect(split.direction, TerminalPaneSplitDirection.down);
    expect(split.ratio, 0.5);
    expect(
      (split.first as TerminalLaunchConfigurationPaneLeaf).startupCommand,
      'echo one',
    );
    expect(
      (split.second as TerminalLaunchConfigurationPaneLeaf).cwd,
      '/tmp/eight',
    );
  });

  test('launch config reassigns duplicate pane ids globally', () {
    final parsed = TerminalLaunchConfiguration.fromJson(<String, Object?>{
      'activeTabIndex': 1,
      'tabs': <Object?>[
        <String, Object?>{
          'fallbackTitle': 'Local 1',
          'activePaneId': 1,
          'rootPane': <String, Object?>{
            'type': 'split',
            'first': <String, Object?>{'type': 'leaf', 'id': 1},
            'second': <String, Object?>{'type': 'leaf', 'id': 1},
          },
        },
        <String, Object?>{
          'fallbackTitle': 'Local 2',
          'activePaneId': 1,
          'rootPane': <String, Object?>{'type': 'leaf', 'id': 1},
        },
      ],
    });

    final paneIds = parsed.tabs
        .expand((tab) => tab.rootPane.leaves)
        .map((leaf) => leaf.id)
        .toList(growable: false);

    expect(paneIds, <int>[1, 2, 3]);
    expect(parsed.tabs.last.activePaneId, 3);
  });

  test('suggested path stays inside the target workspace', () {
    expect(
      suggestedLaunchConfigPath(
        cwd: '/Users/robin/workspace/demo',
        currentPath: '/workspace',
        operatingSystem: 'macos',
      ),
      '/Users/robin/workspace/demo/ianvs-terminal.launch.json',
    );
    expect(
      suggestedLaunchConfigPath(
        cwd: r'C:\Users\Robin\workspace',
        currentPath: r'C:\workspace',
        operatingSystem: 'windows',
      ),
      r'C:\Users\Robin\workspace\ianvs-terminal.launch.json',
    );
  });

  test('named launch config path defaults into app state directory', () {
    expect(
      suggestedNamedLaunchConfigPath(
        name: 'Payments API Prod',
        currentPath: '/workspace/demo',
        operatingSystem: 'macos',
        environment: const <String, String>{'HOME': '/Users/robin'},
      ),
      '/Users/robin/Library/Application Support/Ianvs/ianvs-terminal/launch_configs/payments-api-prod.json',
    );
  });

  test('launch config file stem sanitizes invalid characters and fallback', () {
    expect(
      sanitizeLaunchConfigFileStem('Payments API / Prod'),
      'payments-api-prod',
    );
    expect(sanitizeLaunchConfigFileStem('  '), 'ianvs-terminal-app');
  });

  test('display name is derived from json path basename', () {
    expect(
      launchConfigDisplayNameFromPath(
        '/Users/robin/Library/Application Support/Ianvs/ianvs-terminal/launch_configs/payments-api-prod.json',
      ),
      'payments-api-prod',
    );
    expect(
      launchConfigDisplayNameFromPath(
        r'C:\Users\Robin\ianvs-terminal\launch_configs\prod.json',
      ),
      'prod',
    );
  });
}
