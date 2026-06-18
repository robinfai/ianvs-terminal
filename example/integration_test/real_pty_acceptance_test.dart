import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;
import 'package:integration_test/integration_test.dart';

import 'package:app/app.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/password_manager_store.dart';
import 'package:app/features/shell/shell_screen.dart';

import '../test/support/memory_app_preferences_repository.dart';
import '../test/support/memory_local_terminal_config_repository.dart';
import '../test/support/memory_profile_repository.dart';

const _frameWait = Duration(seconds: 20);
const _pollStep = Duration(milliseconds: 100);
const _commandBlockVisibleLimit = 3;
const _acceptanceScreenshotPath = String.fromEnvironment(
  'IANVS_ACCEPTANCE_SCREENSHOT_PATH',
);
const _acceptanceScreenshotBoundaryKey = Key(
  'real-pty-acceptance-screenshot-boundary',
);
const _commandBlocksHistoryConfig = LocalTerminalConfigDocument(
  commandBlocksHistory: LocalTerminalCommandBlocksHistoryConfig(
    enabled: true,
    commandBlocks: true,
    failureSnapshots: true,
    reviewWorkspaceEntrypoints: true,
    outputDiff: true,
  ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _ignoreKnownDesktopKeyStateNoise();

  testWidgets(
    'real PTY command blocks render terminal previews for read-only commands',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final workspace = Directory.systemTemp.createTempSync(
        'ianvs terminal-command-blocks-',
      );
      final home = Directory('${workspace.path}/home')..createSync();
      File('${workspace.path}/alpha.txt').writeAsStringSync('alpha\n');
      for (var index = 1; index <= 80; index += 1) {
        File(
          '${workspace.path}/fixture_${index.toString().padLeft(3, '0')}.txt',
        ).writeAsStringSync('fixture $index\n');
      }
      Directory('${workspace.path}/nested').createSync();
      addTearDown(() {
        if (workspace.existsSync()) {
          workspace.deleteSync(recursive: true);
        }
      });

      final profile = TerminalProfile(
        id: 'command-blocks',
        name: 'Command Blocks',
        shell: '/bin/zsh',
        args: const ['-l'],
        cwd: workspace.path,
        env: {'HOME': home.path, 'LC_ALL': 'C', 'TERM': 'xterm-256color'},
      );
      final harness = await _pumpRealPtyApp(
        tester,
        profiles: [profile],
        localConfig: _commandBlocksHistoryConfig,
      );

      await _waitForCommandInput(tester);
      await _waitForPane(
        tester,
        harness.container,
        description: 'real PTY shell integration prompt metadata',
        matches: (pane) =>
            pane.shellIntegration.currentDirectory?.isNotEmpty == true,
      );

      await _submitCommandInput(tester, "alias ll='ls -la'");
      await _waitForCommandBlockCards(tester, expectedMinimum: 1);
      final commands = <({String command, bool Function(String text) output})>[
        (command: 'll', output: (text) => text.contains('fixture_080.txt')),
        (command: 'pwd', output: (text) => text.contains(workspace.path)),
        (
          command: "printf 'IANVS_DONE\\n'",
          output: (text) => text.contains('IANVS_DONE'),
        ),
      ];
      for (var index = 0; index < commands.length; index += 1) {
        final command = commands[index];
        await _submitCommandInput(tester, command.command);
        await _waitForTerminalText(
          tester,
          harness.container,
          description: 'output for ${command.command}',
          matches: command.output,
        );
        await _waitForCommandBlockCards(tester, expectedMinimum: index + 2);
      }

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'read-only command output in real PTY',
        matches: (text) =>
            text.contains('IANVS_DONE') &&
            text.contains("printf 'IANVS_DONE\\n'") &&
            !text.contains('fixture_001.txt'),
      );
      await _waitForCommandBlockCards(
        tester,
        expectedMinimum: _commandBlockVisibleLimit,
      );
      await _waitForCommandBlockPreviews(
        tester,
        expectedMinimum: _commandBlockVisibleLimit,
      );
      _expectCommandBlockPreviewText(
        tester,
        command: 'll',
        matches: ['fixture_080.txt'],
      );
      _expectCommandBlockPreviewText(
        tester,
        command: 'pwd',
        matches: [workspace.path],
        rejects: ['IANVS_DONE'],
      );
      _expectCommandBlockPreviewText(
        tester,
        command: "printf 'IANVS_DONE\\n'",
        matches: ['IANVS_DONE'],
        rejects: [workspace.path],
      );

      for (final visibleCommand
          in commands
              .skip(commands.length - _commandBlockVisibleLimit)
              .map((entry) => entry.command)) {
        expect(find.textContaining(visibleCommand), findsWidgets);
      }
      expect(
        find.text('exit 0'),
        findsAtLeastNWidgets(_commandBlockVisibleLimit),
      );
      expect(
        _verticalScrollableDescendants(
          find.byKey(const Key('shell-command-blocks-scroll-view')),
        ),
        findsWidgets,
      );
      expect(
        tester
            .widget<SingleChildScrollView>(
              find.byKey(const Key('shell-command-blocks-scroll-view')),
            )
            .reverse,
        isTrue,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
        findsAtLeastNWidgets(_commandBlockVisibleLimit),
      );
      await _writeAcceptanceScreenshotIfRequested(tester);
    },
    skip: _skipRealPtyTests,
  );

  testWidgets(
    'real PTY shell keeps line timestamp overlays hidden by default',
    (tester) async {
      final profile = _scriptProfile(
        id: 'timestamp-hidden',
        name: 'Timestamp Hidden',
        script: "printf 'timestamp smoke\\n'; sleep 2",
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'real PTY timestamp smoke output',
        matches: (text) => text.contains('timestamp smoke'),
      );

      expect(find.byKey(const Key('terminal-line-timestamp-0')), findsNothing);
    },
    skip: _skipRealPtyTests,
  );

  testWidgets(
    'real PTY shell hooks restore automatic profile switching baselines',
    (tester) async {
      final goFile = _tempSignalFile('profile-restore');
      final localProfile = _scriptProfile(
        id: 'local',
        name: 'Local',
        script: _profileSwitchScript(),
        env: {'GO_FILE': goFile.path},
      );
      final rootProfile = _scriptProfile(
        id: 'root',
        name: 'Root Session',
        script: 'sleep 2',
        switchRules: const [
          TerminalProfileSwitchRule(
            kind: TerminalProfileSwitchRuleKind.username,
            pattern: 'root',
          ),
        ],
      );
      final harness = await _pumpRealPtyApp(
        tester,
        profiles: [localProfile, rootProfile],
      );

      await _waitForPane(
        tester,
        harness.container,
        description: 'root automatic profile switch',
        matches: (pane) =>
            pane.profileId == 'root' && pane.title == 'Root Session',
      );

      _signal(goFile);

      await _waitForPane(
        tester,
        harness.container,
        description: 'automatic profile restore',
        matches: (pane) =>
            pane.profileId == 'local' &&
            pane.title == 'Local' &&
            pane.profileSnapshot?.name == 'Local' &&
            pane.shellIntegration.username == 'dev',
      );
    },
    skip: _skipRealPtyTests,
  );

  testWidgets('real PTY password manager blocks stale prompt sends', (
    tester,
  ) async {
    final goFile = _tempSignalFile('password-stale');
    final passwordStore = PasswordManagerStore()
      ..add(label: 'staging sudo', password: 's3cr3t!');
    final profile = _scriptProfile(
      id: 'password-stale',
      name: 'Password Stale',
      script: r'''
printf '[sudo] password for dev:'
while [ ! -f "$GO_FILE" ]; do sleep 0.05; done
printf '\r\033[2Kdev $ '
sleep 5
''',
      env: {'GO_FILE': goFile.path},
    );
    final harness = await _pumpRealPtyApp(
      tester,
      profiles: [profile],
      passwordStore: passwordStore,
    );

    await _waitForTerminalText(
      tester,
      harness.container,
      description: 'initial password prompt',
      matches: (text) => text.contains('[sudo] password for dev:'),
    );

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.text('Password manager'));
    await tester.tap(find.text('Password manager'));
    await tester.pump(_pollStep);
    expect(find.byKey(const Key('password-manager-sheet')), findsOneWidget);

    _signal(goFile);
    await _waitForTerminalText(
      tester,
      harness.container,
      description: 'ordinary prompt after password prompt disappeared',
      matches: (text) => !text.contains('[sudo] password for dev:'),
    );

    await tester.tap(find.byKey(const Key('password-manager-send-0')));
    await tester.pump(_pollStep);
    await tester.pump(_pollStep);

    await _waitForTerminalText(
      tester,
      harness.container,
      description: 'terminal remains free of stale password text',
      matches: (text) => !text.contains('s3cr3t!'),
    );
  }, skip: _skipRealPtyTests);

  testWidgets(
    'real PTY profile triggers respond to repeated prompts',
    (tester) async {
      final goFile = _tempSignalFile('trigger-repeat');
      final profile = _scriptProfile(
        id: 'trigger-repeat',
        name: 'Trigger Repeat',
        script: r'''
while [ ! -f "$GO_FILE" ]; do sleep 0.05; done
printf 'Password:'
IFS= read a
printf 'first:%s\n' "$a"
printf 'Password:'
IFS= read b
printf 'second:%s\n' "$b"
sleep 1
''',
        env: {'GO_FILE': goFile.path},
        triggers: const [
          TerminalProfileTrigger(
            pattern: 'Password:',
            action: TerminalProfileTriggerAction.sendText,
            value: 'secret\n',
          ),
        ],
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      _signal(goFile);

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'two trigger responses in a real PTY',
        matches: (text) =>
            text.contains('first:secret') && text.contains('second:secret'),
      );
    },
    skip: _skipRealPtyTests,
  );

  testWidgets('real PTY coprocess replies to repeated prompts', (tester) async {
    final goFile = _tempSignalFile('coprocess-repeat');
    final profile = _scriptProfile(
      id: 'coprocess-repeat',
      name: 'Coprocess Repeat',
      script: r'''
while [ ! -f "$GO_FILE" ]; do sleep 0.05; done
printf 'Are you there?'
IFS= read a
printf 'first:%s\n' "$a"
printf 'Are you there?'
IFS= read b
printf 'second:%s\n' "$b"
sleep 1
''',
      env: {'GO_FILE': goFile.path},
    );
    final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

    await _openCommandMenu(tester);
    await tester.ensureVisible(find.byKey(const Key('shell-coprocess')));
    await tester.tap(find.byKey(const Key('shell-coprocess')));
    await tester.pump(_pollStep);
    expect(find.byKey(const Key('coprocess-sheet')), findsOneWidget);
    await tester.tap(find.byKey(const Key('coprocess-start')));
    await tester.pump(_pollStep);

    _signal(goFile);

    await _waitForTerminalText(
      tester,
      harness.container,
      description: 'two coprocess responses in a real PTY',
      matches: (text) =>
          text.contains('first:Yes') && text.contains('second:Yes'),
    );
  }, skip: _skipRealPtyTests);

  testWidgets(
    'real PTY wrapped trigger output is captured as a logical row',
    (tester) async {
      final prefixLengthFile = _tempSignalFile('wrapped-trigger');
      final notifications = <Map<String, String?>>[];
      final profile = _scriptProfile(
        id: 'wrapped-trigger',
        name: 'Wrapped Trigger',
        script: r'''
while [ ! -f "$PREFIX_LENGTH_FILE" ]; do sleep 0.05; done
prefix_len=$(cat "$PREFIX_LENGTH_FILE")
i=0
while [ "$i" -lt "$prefix_len" ]; do
  printf 'x'
  i=$((i + 1))
done
printf 'ERROR 42 failed from wrapped output\n'
sleep 5
''',
        env: {'PREFIX_LENGTH_FILE': prefixLengthFile.path},
        triggers: const [
          TerminalProfileTrigger(pattern: 'ERROR [0-9]+ failed'),
        ],
      );
      final harness = await _pumpRealPtyApp(
        tester,
        profiles: [profile],
        notifications: notifications,
      );

      final cols = await _waitForViewportColumns(tester, harness.container);
      prefixLengthFile.writeAsStringSync('${(cols - 8).clamp(0, 200)}');

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'wrapped trigger output from a real PTY',
        matches: (text) => text.contains('ERROR 42') && text.contains('failed'),
      );
      expect(
        _requireActiveFrame(harness.container).rows.any((row) => row.wrapped),
        isTrue,
      );
      await _waitFor(
        tester,
        description: 'trigger notification for wrapped real PTY output',
        condition: () => notifications.any(
          (notification) =>
              notification['body']?.contains('ERROR 42 failed') ?? false,
        ),
      );

      await _openCommandMenu(tester);
      await tester.ensureVisible(
        find.byKey(const Key('shell-captured-output')),
      );
      await tester.tap(find.byKey(const Key('shell-captured-output')));
      await tester.pump(_pollStep);

      expect(find.byKey(const Key('captured-output-sheet')), findsOneWidget);
      expect(find.textContaining('ERROR 42 failed'), findsWidgets);
    },
    skip: _skipRealPtyTests,
  );

  testWidgets(
    'real PTY inactive wrapped output sends a logical activity notification',
    (tester) async {
      final prefixLengthFile = _tempSignalFile('activity-wrapped');
      final notifications = <Map<String, String?>>[];
      final profile = _scriptProfile(
        id: 'activity-source',
        name: 'Activity Source',
        script: r'''
printf 'ready\n'
while [ ! -f "$PREFIX_LENGTH_FILE" ]; do sleep 0.05; done
prefix_len=$(cat "$PREFIX_LENGTH_FILE")
i=0
while [ "$i" -lt "$prefix_len" ]; do
  printf 'x'
  i=$((i + 1))
done
printf 'ERROR 42 failed from inactive wrapped output\n'
sleep 5
''',
        env: {'PREFIX_LENGTH_FILE': prefixLengthFile.path},
      );
      final harness = await _pumpRealPtyApp(
        tester,
        profiles: [profile],
        notifications: notifications,
      );

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'first real PTY tab ready',
        matches: (text) => text.contains('ready'),
      );

      await _openCommandMenu(tester);
      await tester.tap(find.text('New tab'));
      await _waitFor(
        tester,
        description: 'second real PTY tab',
        condition: () =>
            harness.container.read(sessionControllerProvider).tabs.length == 2,
      );

      final cols = await _waitForViewportColumns(tester, harness.container);
      prefixLengthFile.writeAsStringSync('${(cols - 8).clamp(0, 200)}');

      await _waitFor(
        tester,
        description: 'inactive wrapped activity notification',
        condition: () => notifications.any(
          (notification) =>
              (notification['title']?.startsWith('Activity in ') ?? false) &&
              (notification['body']?.contains('ERROR 42 failed') ?? false) &&
              (notification['body']?.contains('inactive wrapped output') ??
                  false),
        ),
        onTimeout: () => 'Notifications: $notifications',
      );
    },
    skip: _skipRealPtyTests,
  );
}

void _expectCommandBlockPreviewText(
  WidgetTester tester, {
  required String command,
  required List<String> matches,
  List<String> rejects = const <String>[],
}) {
  final overlay = tester.widget<ShellCommandBlocksOverlay>(
    find.byType(ShellCommandBlocksOverlay),
  );
  final block = overlay.viewModel.blocks.firstWhere(
    (item) => item.command == command,
    orElse: () => fail('Expected command block for "$command".'),
  );
  final text = block.terminalRows.map((row) => row.text).join('\n');
  for (final expected in matches) {
    expect(
      text,
      contains(expected),
      reason:
          'Expected "$command" block preview to contain "$expected".\n'
          'Preview text:\n$text\n'
          'All blocks:\n${_commandBlockPreviewDump(overlay)}',
    );
  }
  for (final rejected in rejects) {
    expect(
      text,
      isNot(contains(rejected)),
      reason:
          'Expected "$command" block preview not to contain "$rejected".\n'
          'Preview text:\n$text\n'
          'All blocks:\n${_commandBlockPreviewDump(overlay)}',
    );
  }
}

String _commandBlockPreviewDump(ShellCommandBlocksOverlay overlay) {
  return overlay.viewModel.blocks
      .map(
        (block) =>
            '${block.command} ${block.outputRangeLabel}\n'
            '${block.terminalRows.map((row) => row.text).join('\n')}',
      )
      .join('\n---\n');
}

bool get _skipRealPtyTests => !Platform.isMacOS;

void _ignoreKnownDesktopKeyStateNoise() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    if (message.contains('A KeyUpEvent is dispatched') &&
        message.contains(
          'the state shows that the physical key is not pressed',
        )) {
      return;
    }
    if (previousOnError != null) {
      previousOnError(details);
    } else {
      FlutterError.presentError(details);
    }
  };
}

Future<_RealPtyHarness> _pumpRealPtyApp(
  WidgetTester tester, {
  required List<TerminalProfile> profiles,
  LocalTerminalConfigDocument? localConfig,
  PasswordManagerStore? passwordStore,
  List<Map<String, String?>>? notifications,
}) async {
  final container = ProviderContainer(
    overrides: [
      profileRepositoryProvider.overrideWithValue(
        MemoryProfileRepository(TerminalProfilesDocument(profiles: profiles)),
      ),
      appPreferencesRepositoryProvider.overrideWithValue(
        MemoryAppPreferencesRepository(null),
      ),
      localTerminalConfigRepositoryProvider.overrideWithValue(
        MemoryLocalTerminalConfigRepository(localConfig),
      ),
      shellAnimationsEnabledProvider.overrideWithValue(false),
      shellNotificationSenderProvider.overrideWithValue(({
        required title,
        body,
        identifier,
      }) async {
        notifications?.add({
          'title': title,
          'body': body,
          'identifier': identifier,
        });
      }),
      if (passwordStore != null)
        passwordManagerStoreProvider.overrideWithValue(passwordStore),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const RepaintBoundary(
        key: _acceptanceScreenshotBoundaryKey,
        child: IanvsTerminalApp(),
      ),
    ),
  );
  await _waitForActiveSession(tester, container);
  return _RealPtyHarness(container);
}

TerminalProfile _scriptProfile({
  required String id,
  required String name,
  required String script,
  Map<String, String> env = const {},
  List<TerminalProfileTrigger> triggers = const [],
  List<TerminalProfileSwitchRule> switchRules = const [],
}) {
  return TerminalProfile(
    id: id,
    name: name,
    shell: '/bin/sh',
    args: ['-lc', script],
    env: {'LC_ALL': 'C', ...env},
    triggers: triggers,
    switchRules: switchRules,
  );
}

String _profileSwitchScript() {
  return [
    _printfShellHook({
      'hook': 'command_finished',
      'command': 'sudo -s',
      'user': 'root',
      'pwd': '/root',
      'shell': 'sh',
    }),
    'while [ ! -f "\$GO_FILE" ]; do sleep 0.05; done',
    _printfShellHook({
      'hook': 'command_finished',
      'command': 'exit',
      'user': 'dev',
      'pwd': '/Users/dev',
      'shell': 'sh',
    }),
    'sleep 1',
  ].join('\n');
}

String _printfShellHook(Map<String, Object?> payload) {
  final encoded = utf8.encode(jsonEncode(payload));
  final hex = encoded
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return "printf '\\033Phook;$hex\\033\\\\'";
}

File _tempSignalFile(String name) {
  final directory = Directory.systemTemp.createTempSync(
    'ianvs terminal-$name-',
  );
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return File('${directory.path}/signal');
}

void _signal(File file) {
  file.createSync(recursive: true);
}

Future<void> _openCommandMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('shell-chrome-menu')));
  await tester.pump(_pollStep);
}

Future<void> _waitForCommandInput(WidgetTester tester) async {
  await _waitFor(
    tester,
    description: 'command block input field',
    condition: () => find
        .byKey(const Key('shell-command-input-field'))
        .evaluate()
        .isNotEmpty,
  );
}

Future<void> _submitCommandInput(WidgetTester tester, String command) async {
  final input = find.byKey(const Key('shell-command-input-field'));
  await _waitForCommandInput(tester);
  await tester.tap(input);
  await tester.enterText(input, command);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump(_pollStep);
}

Future<void> _waitForCommandBlockCards(
  WidgetTester tester, {
  required int expectedMinimum,
}) async {
  var latest = 0;
  await _waitFor(
    tester,
    description: '$expectedMinimum command block cards',
    condition: () {
      latest = _stringKeyPrefixFinder(
        'shell-command-block-card-',
      ).evaluate().length;
      return latest >= expectedMinimum;
    },
    onTimeout: () =>
        'Found $latest command block cards.\n${_commandBlockCardTextDump(tester)}',
  );
}

Future<void> _waitForCommandBlockPreviews(
  WidgetTester tester, {
  required int expectedMinimum,
}) async {
  var latest = 0;
  await _waitFor(
    tester,
    description: '$expectedMinimum command block terminal previews',
    condition: () {
      latest = find.byType(terminal.TerminalFramePreview).evaluate().length;
      return latest >= expectedMinimum;
    },
    onTimeout: () =>
        'Found $latest command block terminal previews.\n'
        '${_commandBlockCardTextDump(tester)}',
  );
}

String _commandBlockCardTextDump(WidgetTester tester) {
  final cards = _stringKeyPrefixFinder('shell-command-block-card-');
  final textWidgets = tester.widgetList<Text>(
    find.descendant(of: cards, matching: find.byType(Text)),
  );
  final texts = textWidgets
      .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
      .where((text) => text.trim().isNotEmpty)
      .toList(growable: false);
  return texts.isEmpty ? 'Command block card texts: <none>' : texts.join('\n');
}

Future<void> _writeAcceptanceScreenshotIfRequested(WidgetTester tester) async {
  if (_acceptanceScreenshotPath.trim().isEmpty) {
    return;
  }
  await tester.pump(const Duration(milliseconds: 250));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_acceptanceScreenshotBoundaryKey),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (byteData == null) {
    throw StateError('Failed to encode command block acceptance screenshot');
  }
  final file = File(_acceptanceScreenshotPath);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(byteData.buffer.asUint8List());
}

Future<void> _waitForActiveSession(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await _waitFor(
    tester,
    description: 'active real PTY session',
    condition: () {
      final state = container.read(sessionControllerProvider);
      return state.isReady && state.activeSessionId != null;
    },
  );
}

Future<void> _waitForPane(
  WidgetTester tester,
  ProviderContainer container, {
  required String description,
  required bool Function(TerminalPane pane) matches,
}) async {
  await _waitFor(
    tester,
    description: description,
    condition: () {
      final state = container.read(sessionControllerProvider);
      final sessionId = state.activeSessionId;
      if (sessionId == null) {
        return false;
      }
      final pane = _activePane(container);
      return pane != null && matches(pane);
    },
    onTimeout: () {
      final pane = _activePane(container);
      return 'Active pane: $pane';
    },
  );
}

Future<void> _waitForTerminalText(
  WidgetTester tester,
  ProviderContainer container, {
  required String description,
  required bool Function(String text) matches,
}) async {
  var latest = _terminalText(container);
  await _waitFor(
    tester,
    description: description,
    condition: () {
      latest = _terminalText(container);
      return matches(latest);
    },
    onTimeout: () => 'Last terminal frame:\n$latest',
  );
}

Future<int> _waitForViewportColumns(
  WidgetTester tester,
  ProviderContainer container,
) async {
  var cols = 0;
  await _waitFor(
    tester,
    description: 'measured real PTY viewport columns',
    condition: () {
      final frame = _activeFrame(container);
      if (frame == null) {
        return false;
      }
      cols = frame.viewportCols;
      return cols > 10;
    },
  );
  return cols;
}

Future<void> _waitFor(
  WidgetTester tester, {
  required String description,
  required bool Function() condition,
  String Function()? onTimeout,
}) async {
  final deadline = DateTime.now().add(_frameWait);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(_pollStep);
    if (condition()) {
      return;
    }
  }
  fail(
    'Timed out waiting for $description.${onTimeout == null ? '' : '\n${onTimeout()}'}',
  );
}

TerminalPane? _activePane(ProviderContainer container) {
  final state = container.read(sessionControllerProvider);
  final sessionId = state.activeSessionId;
  if (sessionId == null) {
    return null;
  }
  for (final tab in state.tabs) {
    final pane = tab.paneFor(sessionId);
    if (pane != null) {
      return pane;
    }
  }
  return null;
}

terminal.TerminalFrameDiff? _activeFrame(ProviderContainer container) {
  final state = container.read(sessionControllerProvider);
  final sessionId = state.activeSessionId;
  if (sessionId == null) {
    return null;
  }
  return container
      .read(sessionControllerProvider.notifier)
      .viewportFor(sessionId)
      .frame;
}

terminal.TerminalFrameDiff _requireActiveFrame(ProviderContainer container) {
  final frame = _activeFrame(container);
  if (frame == null) {
    throw StateError('No active terminal frame');
  }
  return frame;
}

String _terminalText(ProviderContainer container) {
  final frame = _activeFrame(container);
  if (frame == null) {
    return '';
  }
  return frame.rows.map((row) => row.text.trimRight()).join('\n');
}

Finder _stringKeyPrefixFinder(String prefix) {
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith(prefix);
  });
}

Finder _verticalScrollableDescendants(Finder parent) {
  return find.descendant(
    of: parent,
    matching: find.byWidgetPredicate((widget) {
      return widget is Scrollable &&
          (widget.axisDirection == AxisDirection.down ||
              widget.axisDirection == AxisDirection.up);
    }),
  );
}

class _RealPtyHarness {
  const _RealPtyHarness(this.container);

  final ProviderContainer container;
}
