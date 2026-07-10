import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;
import 'package:integration_test/integration_test.dart';

import 'package:app/app.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/password_manager_store.dart';
import 'package:app/features/shell/shell_screen.dart';

import '../test/support/memory_app_preferences_repository.dart';
import '../test/support/memory_profile_repository.dart';

const _frameWait = Duration(seconds: 20);
const _pollStep = Duration(milliseconds: 100);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _ignoreKnownDesktopKeyStateNoise();

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

    await _openToolbelt(tester);
    await tester.ensureVisible(
      find.byKey(const Key('toolbelt-password-manager')),
    );
    await tester.tap(find.byKey(const Key('toolbelt-password-manager')));
    await _waitFor(
      tester,
      description: 'password manager sheet',
      condition: () =>
          find.byKey(const Key('password-manager-sheet')).evaluate().isNotEmpty,
    );

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
printf 'ready\n'
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

    await _waitForTerminalText(
      tester,
      harness.container,
      description: 'coprocess real PTY pane ready',
      matches: (text) => text.contains('ready'),
    );

    await _openToolbelt(tester);
    await tester.ensureVisible(find.byKey(const Key('toolbelt-coprocess')));
    await tester.tap(find.byKey(const Key('toolbelt-coprocess')));
    await _waitFor(
      tester,
      description: 'coprocess sheet',
      condition: () =>
          find.byKey(const Key('coprocess-sheet')).evaluate().isNotEmpty,
    );
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
      prefixLengthFile.writeAsStringSync('${cols + 400}');

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'wrapped trigger output from a real PTY',
        matches: (text) => text.contains('ERROR 42') && text.contains('failed'),
      );
      final frame = _requireActiveFrame(harness.container);
      expect(
        _frameHasWrappedOrReassembledLogicalRow(frame),
        isTrue,
        reason: _frameDebug(frame),
      );
      await _waitFor(
        tester,
        description: 'trigger notification for wrapped real PTY output',
        condition: () => notifications.any(
          (notification) =>
              notification['body']?.contains('ERROR 42 failed') ?? false,
        ),
      );

      await _openToolbelt(tester);
      await tester.tap(find.byKey(const Key('toolbelt-tab-captured-output')));
      await _waitFor(
        tester,
        description: 'captured output toolbelt panel',
        condition: () => find
            .byKey(const Key('toolbelt-panel-captured-output'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('toolbelt-captured-output')));
      await _waitFor(
        tester,
        description: 'captured output sheet',
        condition: () => find
            .byKey(const Key('captured-output-sheet'))
            .evaluate()
            .isNotEmpty,
      );

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
      prefixLengthFile.writeAsStringSync('${cols + 400}');

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

  testWidgets(
    'real PTY active wake baseline after four seconds child idle',
    (tester) => _verifyIdleWakeBaseline(tester, state: _IdleWakeState.active),
    skip: _skipRealPtyTests,
  );

  testWidgets(
    'real PTY background deadline wake baseline after four seconds child idle',
    (tester) => _verifyIdleWakeBaseline(
      tester,
      state: _IdleWakeState.backgroundDeadline,
    ),
    skip: _skipRealPtyTests,
  );

  testWidgets(
    'real PTY maximum backoff wake baseline after four seconds child idle',
    (tester) =>
        _verifyIdleWakeBaseline(tester, state: _IdleWakeState.maximumBackoff),
    skip: _skipRealPtyTests,
  );
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
  PasswordManagerStore? passwordStore,
  List<Map<String, String?>>? notifications,
  List<Map<String, Object?>>? runtimeEvents,
}) async {
  final container = ProviderContainer(
    overrides: [
      profileRepositoryProvider.overrideWithValue(
        MemoryProfileRepository(TerminalProfilesDocument(profiles: profiles)),
      ),
      appPreferencesRepositoryProvider.overrideWithValue(
        MemoryAppPreferencesRepository(null),
      ),
      shellAnimationsEnabledProvider.overrideWithValue(false),
      if (runtimeEvents != null)
        terminalGraphicsTraceSinkProvider.overrideWithValue(runtimeEvents.add),
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
      child: const IanvsTerminalApp(),
    ),
  );
  await _waitForActiveSession(tester, container);
  return _RealPtyHarness(container);
}

enum _IdleWakeState { active, backgroundDeadline, maximumBackoff }

Future<void> _verifyIdleWakeBaseline(
  WidgetTester tester, {
  required _IdleWakeState state,
}) async {
  final fixture = _createIdleWakeFixture(state.name);
  final runtimeEvents = <Map<String, Object?>>[];
  final profile = _scriptProfile(
    id: 'idle-wake-${state.name}',
    name: 'Idle Wake ${state.name}',
    script: r'''
printf 'idle-ready\n'
sleep 4
: > "$IDLE_DONE_FILE"
IFS= read -r token < "$WAKE_FIFO"
printf 'idle-wake:%s\n' "$token"
sleep 1
''',
    env: <String, String>{
      'IDLE_DONE_FILE': fixture.idleDone.path,
      'WAKE_FIFO': fixture.wakeFifo.path,
    },
  );
  final harness = await _pumpRealPtyApp(
    tester,
    profiles: <TerminalProfile>[profile],
    runtimeEvents: runtimeEvents,
  );

  await _waitFor(
    tester,
    description: 'four seconds of genuine child-process idle (${state.name})',
    condition: fixture.idleDone.existsSync,
    onTimeout: () =>
        'Last terminal frame:\n${_terminalText(harness.container)}',
  );

  final sessionId = harness.container
      .read(sessionControllerProvider)
      .activeSessionId;
  expect(sessionId, isNotNull);
  final historyRefreshId = _latestRefreshId(runtimeEvents, sessionId!);
  final runtime = harness.container.read(terminalRuntimeControllerProvider);

  final (
    :delayMicros,
    :skipTicks,
    :resetBeforeSignal,
    :nominal,
    :ceiling,
  ) = switch (state) {
    _IdleWakeState.active => (
      delayMicros: 33000,
      skipTicks: 0,
      resetBeforeSignal: true,
      nominal: const Duration(milliseconds: 33),
      ceiling: const Duration(milliseconds: 250),
    ),
    _IdleWakeState.backgroundDeadline => (
      delayMicros: 264000,
      skipTicks: 7,
      resetBeforeSignal: true,
      nominal: const Duration(milliseconds: 264),
      ceiling: const Duration(milliseconds: 750),
    ),
    _IdleWakeState.maximumBackoff => (
      delayMicros: 396000,
      skipTicks: 11,
      resetBeforeSignal: false,
      nominal: const Duration(milliseconds: 396),
      ceiling: const Duration(milliseconds: 750),
    ),
  };

  if (resetBeforeSignal) {
    runtime.sendInput(sessionId, Uint8List(0));
  }

  Map<String, Object?>? preparedResult;
  await _waitFor(
    tester,
    pollStep: const Duration(milliseconds: 5),
    description: 'a current ${state.name} refresh result newer than history',
    condition: () {
      final latest = _latestRefreshEvent(runtimeEvents, sessionId);
      if (latest == null ||
          latest['event'] != 'refresh_result' ||
          latest['refresh_id'] is! int ||
          (latest['refresh_id'] as int) <= historyRefreshId ||
          latest['current_delay_micros'] != delayMicros ||
          latest['backoff_skip_ticks'] != skipTicks) {
        return false;
      }
      preparedResult = latest;
      return true;
    },
    onTimeout: () {
      final latest = _latestRefreshEvent(runtimeEvents, sessionId);
      return 'History refresh_id: $historyRefreshId\nLatest event: $latest';
    },
  );

  expect(preparedResult, isNotNull);
  if (state == _IdleWakeState.maximumBackoff) {
    expect(
      preparedResult!['current_delay_micros'],
      396000,
      reason: 'The deterministic fallback policy cap must remain 396ms.',
    );
  }

  final token = '${state.name}-${DateTime.now().microsecondsSinceEpoch}';
  final stopwatch = Stopwatch()..start();
  await fixture.wakeFifo.writeAsString('$token\n', flush: true);
  await _waitFor(
    tester,
    pollStep: const Duration(milliseconds: 5),
    description: '${state.name} FIFO wake token',
    condition: () =>
        _terminalText(harness.container).contains('idle-wake:$token'),
    onTimeout: () =>
        'Last terminal frame:\n${_terminalText(harness.container)}',
  );
  stopwatch.stop();

  final elapsedMicros = stopwatch.elapsedMicroseconds;
  debugPrint(
    'idle_wake_baseline state=${state.name} '
    'elapsed_micros=$elapsedMicros '
    'nominal_target_micros=${nominal.inMicroseconds} '
    'hard_ceiling_micros=${ceiling.inMicroseconds}',
  );
  expect(
    elapsedMicros,
    lessThanOrEqualTo(ceiling.inMicroseconds),
    reason:
        '${state.name} idle wake elapsed_micros=$elapsedMicros exceeded '
        'hard_ceiling_micros=${ceiling.inMicroseconds}; '
        'nominal_target_micros=${nominal.inMicroseconds}',
  );
}

_IdleWakeFixture _createIdleWakeFixture(String name) {
  final directory = Directory.systemTemp.createTempSync(
    'ianvs-terminal-idle-wake-$name-',
  );
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  final wakeFifo = File('${directory.path}/wake.fifo');
  final result = Process.runSync('/usr/bin/mkfifo', <String>[wakeFifo.path]);
  expect(
    result.exitCode,
    0,
    reason: 'mkfifo failed: stdout=${result.stdout} stderr=${result.stderr}',
  );
  return _IdleWakeFixture(
    idleDone: File('${directory.path}/idle.done'),
    wakeFifo: wakeFifo,
  );
}

int _latestRefreshId(List<Map<String, Object?>> events, String sessionId) {
  var latest = 0;
  for (final event in events) {
    if (event['schema_version'] != 'ianvs-terminal-refresh-policy-v1' ||
        event['session_id'] != sessionId ||
        event['refresh_id'] is! int) {
      continue;
    }
    final refreshId = event['refresh_id'] as int;
    if (refreshId > latest) {
      latest = refreshId;
    }
  }
  return latest;
}

Map<String, Object?>? _latestRefreshEvent(
  List<Map<String, Object?>> events,
  String sessionId,
) {
  for (final event in events.reversed) {
    if (event['schema_version'] == 'ianvs-terminal-refresh-policy-v1' &&
        event['session_id'] == sessionId) {
      return event;
    }
  }
  return null;
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
  await _waitFor(
    tester,
    description: 'command menu overlay',
    condition: () => find
        .byKey(const Key('shell-command-menu-overlay'))
        .evaluate()
        .isNotEmpty,
  );
}

Future<void> _openToolbelt(WidgetTester tester) async {
  await _openCommandMenu(tester);
  await tester.ensureVisible(find.byKey(const Key('shell-top-toolbelt')));
  await tester.tap(find.byKey(const Key('shell-top-toolbelt')));
  await _waitFor(
    tester,
    description: 'toolbelt panel',
    condition: () =>
        find.byKey(const Key('shell-toolbelt-panel')).evaluate().isNotEmpty,
  );
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
  Duration pollStep = _pollStep,
}) async {
  final deadline = DateTime.now().add(_frameWait);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      return;
    }
    await tester.pump(pollStep);
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

String _frameDebug(terminal.TerminalFrameDiff frame) {
  final rows = frame.rows
      .map(
        (row) =>
            '${row.index}: wrapped=${row.wrapped} len=${row.text.trimRight().length} text=${row.text}',
      )
      .join('\n');
  return 'viewportCols=${frame.viewportCols}\n$rows';
}

bool _frameHasWrappedOrReassembledLogicalRow(terminal.TerminalFrameDiff frame) {
  return frame.rows.any(
    (row) =>
        row.wrapped ||
        (frame.viewportCols > 0 &&
            row.text.trimRight().length > frame.viewportCols),
  );
}

class _RealPtyHarness {
  const _RealPtyHarness(this.container);

  final ProviderContainer container;
}

class _IdleWakeFixture {
  const _IdleWakeFixture({required this.idleDone, required this.wakeFifo});

  final File idleDone;
  final File wakeFifo;
}
