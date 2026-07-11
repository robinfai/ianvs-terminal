import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:integration_test/integration_test.dart';

import 'package:app/app.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/password_manager_store.dart';
import 'package:app/features/shell/shell_screen.dart';

import '../test/support/memory_app_preferences_repository.dart';
import '../test/support/macos_integration_test_lifecycle.dart';
import '../test/support/memory_profile_repository.dart';
import '../test/support/memory_local_terminal_config_repository.dart';

const _frameWait = Duration(seconds: 20);
const _pollStep = Duration(milliseconds: 100);
const _refreshHintTargetMs = 100;
const _refreshHintLimitMs = int.fromEnvironment(
  'IANVS_REFRESH_HINT_LIMIT_MS',
  defaultValue: 250,
);
const _refreshFallbackLimitMs = int.fromEnvironment(
  'IANVS_REFRESH_FALLBACK_LIMIT_MS',
  defaultValue: 750,
);
const _standaloneReleaseTestGate = bool.fromEnvironment(
  'IANVS_STANDALONE_RELEASE_TEST_GATE',
);
const _refreshPolicyGateOnly = bool.fromEnvironment(
  'IANVS_REFRESH_POLICY_GATE_ONLY',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _enableStandaloneReleaseTestGate(binding);
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
    skip: _skipNonRefreshPolicyGateTests,
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
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY password manager blocks stale prompt sends',
    (tester) async {
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
        condition: () => find
            .byKey(const Key('password-manager-sheet'))
            .evaluate()
            .isNotEmpty,
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
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

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
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY coprocess replies to repeated prompts',
    (tester) async {
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
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

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
    skip: _skipNonRefreshPolicyGateTests,
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
      final firstSessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;

      await _openCommandMenu(tester);
      await tester.tap(find.text('New tab'));
      await _waitFor(
        tester,
        description: 'second real PTY tab',
        condition: () {
          final state = harness.container.read(sessionControllerProvider);
          return state.tabs.length == 2 &&
              state.activeSessionId != null &&
              state.activeSessionId != firstSessionId;
        },
      );
      await tester.pump();

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
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY OSC 99 assembles, updates, expires and closes by stable ID',
    (tester) async {
      final showFile = _tempSignalFile('osc99-show');
      final updateFile = _tempSignalFile('osc99-update');
      final closeFile = _tempSignalFile('osc99-close');
      final notifications = <Map<String, String?>>[];
      final notificationExpiries = <int?>[];
      final closedNotifications = <String>[];
      final profile = _scriptProfile(
        id: 'osc99-real-pty',
        name: 'OSC 99 Real PTY',
        script: r'''
printf 'osc99-ready\n'
while [ ! -f "$SHOW_FILE" ]; do sleep 0.05; done
printf '\033]99;i=real-build:d=0:e=1:f=YnVpbGRjdGw=:t=ZGVwbG95;UmVhbCBCdWlsZA==\033\\'
printf '\033]99;i=real-build:p=body:e=1:w=5000;U3RhcnRlZA==\033\\'
while [ ! -f "$UPDATE_FILE" ]; do sleep 0.05; done
printf '\033]99;i=real-build:w=3000;Updated\033\\'
while [ ! -f "$CLOSE_FILE" ]; do sleep 0.05; done
printf '\033]99;i=real-build:p=close;\033\\'
sleep 1
''',
        env: {
          'SHOW_FILE': showFile.path,
          'UPDATE_FILE': updateFile.path,
          'CLOSE_FILE': closeFile.path,
        },
      );
      final harness = await _pumpRealPtyApp(
        tester,
        profiles: [profile],
        notifications: notifications,
        notificationExpiries: notificationExpiries,
        closedNotifications: closedNotifications,
      );

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 99 real PTY ready marker',
        matches: (text) => text.contains('osc99-ready'),
      );
      final sourceSessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      await _openCommandMenu(tester);
      await tester.tap(find.text('New tab'));
      await _waitFor(
        tester,
        description: 'inactive OSC 99 source tab',
        condition: () {
          final state = harness.container.read(sessionControllerProvider);
          return state.tabs.length == 2 &&
              state.activeSessionId != sourceSessionId;
        },
      );

      _signal(showFile);
      await _waitFor(
        tester,
        description: 'assembled OSC 99 notification',
        condition: () {
          final pane = harness.container
              .read(sessionControllerProvider)
              .tabs
              .first
              .paneFor(sourceSessionId);
          final recent = pane?.recentNotifications;
          if (recent == null || recent.length != 1) {
            return false;
          }
          final notification = recent.single;
          return notification.identifier == 'real-build' &&
              notification.title == 'Real Build' &&
              notification.message == 'Started' &&
              notification.applicationName == 'buildctl' &&
              notification.notificationTypes.contains('deploy');
        },
      );
      await _waitFor(
        tester,
        description: 'first stable-ID OSC 99 system notification',
        condition: () => notifications.length == 1,
      );
      expect(
        notifications.single['identifier'],
        'ianvs-terminal.osc.$sourceSessionId.real-build',
      );
      expect(notificationExpiries, <int?>[5000]);

      _signal(updateFile);
      await _waitFor(
        tester,
        description: 'updated OSC 99 notification',
        condition: () => notifications.length == 2,
      );
      expect(
        notifications.map((event) => event['identifier']).toSet(),
        <String?>{'ianvs-terminal.osc.$sourceSessionId.real-build'},
      );
      expect(notificationExpiries, <int?>[5000, 3000]);

      _signal(closeFile);
      await _waitFor(
        tester,
        description: 'closed OSC 99 notification',
        condition: () => closedNotifications.contains(
          'ianvs-terminal.osc.$sourceSessionId.real-build',
        ),
      );
      expect(
        harness.container
            .read(sessionControllerProvider)
            .tabs
            .first
            .paneFor(sourceSessionId)!
            .recentNotifications,
        isEmpty,
      );
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY OSC 3008 emits bounded typed hierarchy and ignores unknown close',
    (tester) async {
      final goFile = _tempSignalFile('osc3008-context');
      final profile = _scriptProfile(
        id: 'osc3008-real-pty',
        name: 'OSC 3008 Real PTY',
        script: r'''
printf 'osc3008-ready\n'
while [ ! -f "$GO_FILE" ]; do sleep 0.05; done
printf '\033]3008;start=real-root;type=shell;user=dev\\x3bops;cwd=/work\\x5cdir\033\\'
printf '\033]3008;start=real-child;type=command;cmdline=dart test\033\\'
printf '\033]3008;end=missing;exit=failure\033\\'
printf '\033]3008;end=real-root;exit=success;status=0\033\\'
sleep 1
''',
        env: {'GO_FILE': goFile.path},
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 3008 real PTY ready marker',
        matches: (text) => text.contains('osc3008-ready'),
      );

      final contexts = <terminal.TerminalSessionContextEvent>[];
      final runtime = harness.container.read(terminalRuntimeControllerProvider);
      final subscription = runtime.events
          .where((event) => event is terminal.TerminalSessionContextEvent)
          .cast<terminal.TerminalSessionContextEvent>()
          .listen(contexts.add);
      addTearDown(subscription.cancel);

      _signal(goFile);
      await _waitFor(
        tester,
        description: 'typed OSC 3008 real PTY lifecycle',
        condition: () => contexts.length >= 3,
        onTimeout: () =>
            'Contexts: ${contexts.map((event) => event.rawPayload)}',
      );

      expect(contexts, hasLength(3), reason: 'unknown end must be ignored');
      expect(contexts[0].action, 'start');
      expect(contexts[0].identifier, 'real-root');
      expect(contexts[0].depth, 1);
      expect(contexts[0].user, 'dev;ops');
      expect(contexts[0].cwd, r'/work\dir');
      expect(contexts[1].identifier, 'real-child');
      expect(contexts[1].commandLine, 'dart test');
      expect(contexts[1].depth, 2);
      expect(contexts[2].action, 'end');
      expect(contexts[2].identifier, 'real-root');
      expect(contexts[2].implicitClosedCount, 1);
      expect(contexts[2].depth, 0);
      expect(contexts[2].exit, 'success');
      expect(contexts[2].status, 0);
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY active wake baseline after four seconds child idle',
    (tester) =>
        _verifyIdleWakeBaseline(tester, state: _BaselineIdleWakeState.active),
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY background deadline wake baseline after four seconds child idle',
    (tester) => _verifyIdleWakeBaseline(
      tester,
      state: _BaselineIdleWakeState.backgroundDeadline,
    ),
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY maximum backoff wake baseline after four seconds child idle',
    (tester) => _verifyIdleWakeBaseline(
      tester,
      state: _BaselineIdleWakeState.maximumBackoff,
    ),
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY interactive hint path after four seconds idle',
    (tester) => _verifyIdleWakePolicy(
      tester,
      state: _IdleWakeState.interactive,
      path: _IdleWakePath.nativeHint,
    ),
    skip: _skipRealPtyTests || kReleaseMode,
  );

  testWidgets(
    'real PTY background hint path after four seconds idle',
    (tester) => _verifyIdleWakePolicy(
      tester,
      state: _IdleWakeState.background,
      path: _IdleWakePath.nativeHint,
    ),
    skip: _skipRealPtyTests || kReleaseMode,
  );

  testWidgets(
    'real PTY maximum idle hint path after four seconds idle',
    (tester) => _verifyIdleWakePolicy(
      tester,
      state: _IdleWakeState.maximumIdle,
      path: _IdleWakePath.nativeHint,
    ),
    skip: _skipRealPtyTests,
  );

  testWidgets(
    'real PTY interactive masked-hint path after four seconds idle',
    (tester) => _verifyIdleWakePolicy(
      tester,
      state: _IdleWakeState.interactive,
      path: _IdleWakePath.maskedHintFallback,
    ),
    skip: _skipRealPtyTests || kReleaseMode,
  );

  testWidgets(
    'real PTY background masked-hint path after four seconds idle',
    (tester) => _verifyIdleWakePolicy(
      tester,
      state: _IdleWakeState.background,
      path: _IdleWakePath.maskedHintFallback,
    ),
    skip: _skipRealPtyTests,
  );

  testWidgets(
    'real PTY maximum idle masked-hint path after four seconds idle',
    (tester) => _verifyIdleWakePolicy(
      tester,
      state: _IdleWakeState.maximumIdle,
      path: _IdleWakePath.maskedHintFallback,
    ),
    skip: _skipRealPtyTests,
  );
}

void _enableStandaloneReleaseTestGate(
  IntegrationTestWidgetsFlutterBinding binding,
) {
  if (!kReleaseMode || !_standaloneReleaseTestGate) {
    return;
  }
  unawaited(
    binding.allTestsPassed.future.then((passed) async {
      stdout.writeln(
        'IANVS_STANDALONE_RELEASE_TEST_RESULT='
        '${passed ? 'passed' : 'failed'} '
        'tests=${binding.results.length}',
      );
      await stdout.flush();
      exit(passed ? 0 : 1);
    }),
  );
}

bool get _skipRealPtyTests => !Platform.isMacOS;

bool get _skipNonRefreshPolicyGateTests =>
    _skipRealPtyTests || _refreshPolicyGateOnly;

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
  List<int?>? notificationExpiries,
  List<String>? closedNotifications,
  List<Map<String, Object?>>? runtimeEvents,
  bool maskRefreshHints = false,
}) async {
  ensureMacosIntegrationTestFramesEnabled(tester.binding);
  final container = ProviderContainer(
    overrides: [
      if (maskRefreshHints)
        ptySessionBackendProvider.overrideWithValue(
          _MaskedRefreshHintPtyBackend(NativePtyBackend.load()),
        ),
      profileRepositoryProvider.overrideWithValue(
        MemoryProfileRepository(TerminalProfilesDocument(profiles: profiles)),
      ),
      appPreferencesRepositoryProvider.overrideWithValue(
        MemoryAppPreferencesRepository(null),
      ),
      localTerminalConfigRepositoryProvider.overrideWithValue(
        MemoryLocalTerminalConfigRepository(null),
      ),
      shellAnimationsEnabledProvider.overrideWithValue(false),
      if (runtimeEvents != null)
        terminalGraphicsTraceSinkProvider.overrideWithValue(runtimeEvents.add),
      shellNotificationSenderProvider.overrideWithValue(({
        required title,
        body,
        identifier,
        expiresAfterMs,
      }) async {
        notifications?.add({
          'title': title,
          'body': body,
          'identifier': identifier,
        });
        notificationExpiries?.add(expiresAfterMs);
      }),
      shellNotificationCloserProvider.overrideWithValue((identifier) async {
        closedNotifications?.add(identifier);
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

enum _IdleWakeState { interactive, background, maximumIdle }

enum _IdleWakePath { nativeHint, maskedHintFallback }

enum _BaselineIdleWakeState { active, backgroundDeadline, maximumBackoff }

Future<void> _verifyIdleWakeBaseline(
  WidgetTester tester, {
  required _BaselineIdleWakeState state,
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
    maskRefreshHints: true,
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
  if (state != _BaselineIdleWakeState.active) {
    runtime.setSessionFocused(sessionId, focused: false);
  }

  final (
    :delayMicros,
    :skipTicks,
    :resetBeforeSignal,
    :nominal,
    :ceiling,
  ) = switch (state) {
    _BaselineIdleWakeState.active => (
      delayMicros: 33000,
      skipTicks: 0,
      resetBeforeSignal: true,
      nominal: const Duration(milliseconds: 33),
      ceiling: const Duration(milliseconds: 250),
    ),
    _BaselineIdleWakeState.backgroundDeadline => (
      delayMicros: 264000,
      skipTicks: 7,
      resetBeforeSignal: true,
      nominal: const Duration(milliseconds: 264),
      ceiling: const Duration(milliseconds: 750),
    ),
    _BaselineIdleWakeState.maximumBackoff => (
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
  if (state == _BaselineIdleWakeState.maximumBackoff) {
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

Future<void> _verifyIdleWakePolicy(
  WidgetTester tester, {
  required _IdleWakeState state,
  required _IdleWakePath path,
}) async {
  final fixture = _createIdleWakeFixture('${state.name}-${path.name}');
  final runtimeEvents = <Map<String, Object?>>[];
  final profile = _scriptProfile(
    id: 'idle-wake-${state.name}-${path.name}',
    name: 'Idle Wake ${state.name} ${path.name}',
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
    maskRefreshHints: path == _IdleWakePath.maskedHintFallback,
  );
  final sessionId = harness.container
      .read(sessionControllerProvider)
      .activeSessionId;
  expect(sessionId, isNotNull);
  final runtime = harness.container.read(terminalRuntimeControllerProvider);

  await _waitForTerminalText(
    tester,
    harness.container,
    description: 'idle-ready before child idle marker (${state.name})',
    matches: (text) => text.contains('idle-ready'),
  );
  expect(
    fixture.idleDone.existsSync(),
    isFalse,
    reason: 'idle-ready must be observed before the child ends its 4s sleep',
  );
  await _waitFor(
    tester,
    description: 'four seconds of genuine child-process idle (${state.name})',
    condition: fixture.idleDone.existsSync,
    onTimeout: () =>
        'Last terminal frame:\n${_terminalText(harness.container)}',
  );

  final historyRefreshId = _latestRefreshId(runtimeEvents, sessionId!);
  switch (state) {
    case _IdleWakeState.interactive:
      runtime.setSessionFocused(sessionId, focused: true);
      runtime.sendInput(sessionId, Uint8List(0));
    case _IdleWakeState.background:
      runtime.setSessionActive(sessionId, active: false);
    case _IdleWakeState.maximumIdle:
      runtime.setSessionFocused(sessionId, focused: false);
  }

  final expectedClass = switch (state) {
    _IdleWakeState.interactive => terminal.TerminalRefreshClass.interactive,
    _IdleWakeState.background => terminal.TerminalRefreshClass.background,
    _IdleWakeState.maximumIdle => terminal.TerminalRefreshClass.idle,
  };
  final (:delayMicros, :skipTicks, :fallbackNominal) = switch (state) {
    _IdleWakeState.interactive => (
      delayMicros: 33000,
      skipTicks: 0,
      fallbackNominal: const Duration(milliseconds: 33),
    ),
    _IdleWakeState.background => (
      delayMicros: 264000,
      skipTicks: 7,
      fallbackNominal: const Duration(milliseconds: 264),
    ),
    _IdleWakeState.maximumIdle => (
      delayMicros: 396000,
      skipTicks: 11,
      fallbackNominal: const Duration(milliseconds: 396),
    ),
  };
  final nominal = path == _IdleWakePath.nativeHint
      ? const Duration(milliseconds: _refreshHintTargetMs)
      : fallbackNominal;
  final ceiling =
      path == _IdleWakePath.nativeHint || state == _IdleWakeState.interactive
      ? const Duration(milliseconds: _refreshHintLimitMs)
      : const Duration(milliseconds: _refreshFallbackLimitMs);

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
          latest['refresh_class'] != expectedClass.name ||
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
  expect(
    runtime.refreshPolicySnapshotFor(sessionId).refreshClass,
    expectedClass,
    reason: 'idle.done must precede the requested policy snapshot',
  );
  if (state == _IdleWakeState.maximumIdle) {
    expect(
      preparedResult!['current_delay_micros'],
      396000,
      reason: 'The deterministic fallback policy cap must remain 396ms.',
    );
  }
  expect(
    preparedResult!['hint_poll_count'],
    path == _IdleWakePath.nativeHint ? greaterThan(0) : 0,
  );
  final preparedRefreshId = preparedResult!['refresh_id'] as int;
  final preparedFullPollCount = preparedResult!['full_poll_count'] as int;

  final token =
      '${state.name}-${path.name}-${DateTime.now().microsecondsSinceEpoch}';
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

  Map<String, Object?>? wakeResult;
  await _waitFor(
    tester,
    pollStep: const Duration(milliseconds: 5),
    description: '${state.name} ${path.name} wake refresh result',
    condition: () {
      wakeResult = _firstRefreshResultAfter(
        runtimeEvents,
        sessionId,
        preparedRefreshId,
      );
      return wakeResult != null;
    },
    onTimeout: () =>
        'Recent refresh events:\n${runtimeEvents.reversed.take(12)}',
  );

  final elapsedMicros = stopwatch.elapsedMicroseconds;
  debugPrint(
    'idle_wake_policy state=${state.name} path=${path.name} '
    'raw_elapsed_micros=$elapsedMicros '
    'nominal_target_met=${elapsedMicros <= nominal.inMicroseconds} '
    'nominal_target_micros=${nominal.inMicroseconds} '
    'hard_ceiling_micros=${ceiling.inMicroseconds}',
  );
  if (path == _IdleWakePath.nativeHint) {
    expect(wakeResult!['request_reason'], 'native_hint');
    expect(wakeResult!['hint_poll_count'], greaterThan(0));
    expect(wakeResult!['full_poll_count'], preparedFullPollCount + 1);
    final lifecycle = _refreshLifecycle(
      runtimeEvents,
      sessionId,
      wakeResult!['refresh_id'] as int,
    );
    expect(
      lifecycle.map((event) => event['event']),
      containsAllInOrder(<String>[
        'full_poll_requested',
        'refresh_started',
        'frame_taken',
        'frame_applied',
        'refresh_result',
      ]),
    );
    final requested = lifecycle.firstWhere(
      (event) => event['event'] == 'full_poll_requested',
    );
    expect(requested['refresh_class'], expectedClass.name);
    final started = lifecycle.firstWhere(
      (event) => event['event'] == 'refresh_started',
    );
    final taken = lifecycle.firstWhere(
      (event) => event['event'] == 'frame_taken',
    );
    final applied = lifecycle.firstWhere(
      (event) => event['event'] == 'frame_applied',
    );
    expect(
      requested['refresh_requested_micros'] as int,
      lessThanOrEqualTo(started['refresh_started_micros'] as int),
    );
    expect(
      started['refresh_started_micros'] as int,
      lessThanOrEqualTo(taken['frame_taken_micros'] as int),
    );
    expect(
      taken['frame_taken_micros'] as int,
      lessThanOrEqualTo(applied['frame_applied_micros'] as int),
    );
  } else {
    expect(wakeResult!['hint_poll_count'], 0);
    expect(
      wakeResult!['request_reason'],
      state == _IdleWakeState.maximumIdle ? 'idle_deadline' : 'deadline',
    );
    expect(
      runtimeEvents
          .where(
            (event) =>
                event['session_id'] == sessionId &&
                (event['refresh_id'] as int? ?? 0) > preparedRefreshId,
          )
          .any((event) => event['request_reason'] == 'native_hint'),
      isFalse,
    );
  }
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

Map<String, Object?>? _firstRefreshResultAfter(
  List<Map<String, Object?>> events,
  String sessionId,
  int refreshId,
) {
  for (final event in events) {
    if (event['schema_version'] == 'ianvs-terminal-refresh-policy-v1' &&
        event['session_id'] == sessionId &&
        event['event'] == 'refresh_result' &&
        (event['refresh_id'] as int? ?? 0) > refreshId &&
        event['received_frame'] == true) {
      return event;
    }
  }
  return null;
}

List<Map<String, Object?>> _refreshLifecycle(
  List<Map<String, Object?>> events,
  String sessionId,
  int refreshId,
) {
  return events
      .where(
        (event) =>
            event['schema_version'] == 'ianvs-terminal-refresh-policy-v1' &&
            event['session_id'] == sessionId &&
            event['refresh_id'] == refreshId,
      )
      .toList(growable: false);
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

class _MaskedRefreshHintPtyBackend
    implements
        PtySessionBackend,
        PtySessionJsonRequestBackend,
        PtySessionDiagnosticsBackend,
        PtySessionGraphicAssetBackend,
        PtySessionProtobufFrameBackend {
  const _MaskedRefreshHintPtyBackend(this._delegate);

  final NativePtyBackend _delegate;

  @override
  int ping() => _delegate.ping();

  @override
  String createSession(String sessionConfigJson) {
    return _delegate.createSession(sessionConfigJson);
  }

  @override
  void closeSession(String sessionId) => _delegate.closeSession(sessionId);

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  }) {
    _delegate.resizeSession(
      sessionId,
      cols: cols,
      rows: rows,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
    );
  }

  @override
  void writeInput(String sessionId, List<int> bytes) {
    _delegate.writeInput(sessionId, bytes);
  }

  @override
  void scrollViewport(String sessionId, int deltaLines) {
    _delegate.scrollViewport(sessionId, deltaLines);
  }

  @override
  void scrollViewportTo(String sessionId, int offset) {
    _delegate.scrollViewportTo(sessionId, offset);
  }

  @override
  String? takeFrameDiffJson(String sessionId) {
    return _delegate.takeFrameDiffJson(sessionId);
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    return _delegate.pollEvents(sessionId);
  }

  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    return _delegate.requestSessionJson(sessionId, requestJson);
  }

  @override
  String? takeDiagnosticsJson(String sessionId, String kind) {
    return _delegate.takeDiagnosticsJson(sessionId, kind);
  }

  @override
  PtyGraphicAsset? loadGraphicAsset(
    String sessionId, {
    required int assetId,
    required int assetVersion,
  }) {
    return _delegate.loadGraphicAsset(
      sessionId,
      assetId: assetId,
      assetVersion: assetVersion,
    );
  }

  @override
  bool get supportsProtobufFrameDiffs => _delegate.supportsProtobufFrameDiffs;

  @override
  Uint8List? takeFrameDiffProtobuf(String sessionId) {
    return _delegate.takeFrameDiffProtobuf(sessionId);
  }
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
