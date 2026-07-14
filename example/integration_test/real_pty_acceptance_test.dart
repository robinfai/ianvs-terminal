import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:integration_test/integration_test.dart';

import 'package:app/app.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_ports.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/password_manager_store.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/shell/window_bridge.dart';
import 'package:app/features/terminal/render_terminal_viewport.dart';

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
    'real PTY OSC 1337 ClearCapturedOutput updates the open session sheet',
    (tester) async {
      final goFile = _tempSignalFile('osc1337-clear-captured-output');
      final profile = _scriptProfile(
        id: 'osc1337-clear-captured-output',
        name: 'OSC 1337 Clear Captured Output',
        script: r'''
printf 'CAPTURE-ME-PHASE35\n'
while [ ! -f "$GO_FILE" ]; do sleep 0.05; done
printf '\033]1337;ClearCapturedOutput=1\a'
printf '\033]1337;ClearCapturedOutput\033\\'
printf 'OSC1337-CAPTURE-CLEAR-DONE\n'
IFS= read -r token
printf 'OSC1337-CAPTURE-CLEAR-AFTER:%s\n' "$token"
sleep 1
''',
        env: {'GO_FILE': goFile.path},
        triggers: const [TerminalProfileTrigger(pattern: 'CAPTURE-ME-PHASE35')],
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 1337 captured-output source row',
        matches: (text) => text.contains('CAPTURE-ME-PHASE35'),
      );
      await _openToolbelt(tester);
      await tester.tap(find.byKey(const Key('toolbelt-tab-captured-output')));
      await _waitFor(
        tester,
        description: 'OSC 1337 captured-output panel',
        condition: () => find
            .byKey(const Key('toolbelt-panel-captured-output'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('toolbelt-captured-output')));
      await _waitFor(
        tester,
        description: 'OSC 1337 captured-output source entry',
        condition: () => find.text('CAPTURE-ME-PHASE35').evaluate().isNotEmpty,
      );

      _signal(goFile);
      await _waitFor(
        tester,
        description: 'OSC 1337 cleared open captured-output sheet',
        condition: () =>
            find
                .byKey(const Key('captured-output-sheet'))
                .evaluate()
                .isNotEmpty &&
            find.text('CAPTURE-ME-PHASE35').evaluate().isEmpty &&
            find
                .byKey(const Key('captured-output-empty-state'))
                .evaluate()
                .isNotEmpty,
      );
      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 1337 clear leaves terminal output intact',
        matches: (text) =>
            text.contains('CAPTURE-ME-PHASE35') &&
            text.contains('OSC1337-CAPTURE-CLEAR-DONE'),
      );

      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      harness.container
          .read(terminalRuntimeControllerProvider)
          .sendInput(sessionId, Uint8List.fromList(utf8.encode('continued\n')));
      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 1337 clear keeps the real PTY interactive',
        matches: (text) =>
            text.contains('OSC1337-CAPTURE-CLEAR-AFTER:continued'),
      );
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
    'real PTY OSC 99 reports explicit menu interactions to its source child',
    (tester) async {
      final profile = _scriptProfile(
        id: 'osc99-interactive-real-pty',
        name: 'OSC 99 Interactive Real PTY',
        script: r'''
python3 - <<'PY'
import os, termios, tty
tty_fd = os.open("/dev/tty", os.O_RDWR)
old = termios.tcgetattr(tty_fd)
tty.setraw(tty_fd)
os.write(tty_fd, b"osc99-interactive-ready\r\n")
os.write(tty_fd, b"\x1b]99;i=integration:d=0:a=report:c=1;Deploy ready\x1b\\")
os.write(tty_fd, b"\x1b]99;i=integration:p=buttons;Approve\xe2\x80\xa8Retry\x1b\\")
for index in range(1, 4):
    data = b""
    while not data.endswith(b"\x1b\\"):
        data += os.read(tty_fd, 1)
    os.write(tty_fd, ("\r\nosc99-report-%d:%s\r\n" % (index, data.hex())).encode())
os.write(tty_fd, b"\x1b]99;i=after-dismiss:p=alive;\x1b\\")
alive = b""
while not alive.endswith(b"\x1b\\"):
    alive += os.read(tty_fd, 1)
os.write(tty_fd, ("osc99-alive-after-dismiss:%s\r\n" % alive.hex()).encode())
termios.tcsetattr(tty_fd, termios.TCSANOW, old)
os.close(tty_fd)
PY
sleep 1
''',
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitForPane(
        tester,
        harness.container,
        description: 'interactive OSC 99 notification state',
        matches: (pane) {
          final recent = pane.recentNotifications;
          return recent.length == 1 &&
              recent.single.identifier == 'integration' &&
              recent.single.reportActivation &&
              recent.single.reportClose &&
              listEquals(recent.single.buttons, const ['Approve', 'Retry']);
        },
      );
      ScaffoldMessenger.of(
        tester.element(find.byType(ShellScreen)),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();

      Future<void> openNotificationMenu() async {
        await tester.tap(find.byKey(const Key('shell-status-notification')));
        await tester.pumpAndSettle();
      }

      await openNotificationMenu();
      await tester.tap(
        find.byKey(const Key('shell-status-notification-0-button-2')),
      );
      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'exact OSC 99 button report',
        matches: (text) => text.contains(
          'osc99-report-1:1b5d39393b693d696e746567726174696f6e3b321b5c',
        ),
      );

      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      final controller = harness.container.read(
        sessionControllerProvider.notifier,
      );
      var currentNotification = harness.container
          .read(sessionControllerProvider)
          .tabs
          .single
          .activePane
          .recentNotifications
          .single;
      expect(
        controller.reportSessionNotificationAction(
          sessionId,
          currentNotification,
        ),
        isTrue,
      );
      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'exact OSC 99 activation report',
        matches: (text) => text.contains(
          'osc99-report-2:1b5d39393b693d696e746567726174696f6e3b1b5c',
        ),
      );

      currentNotification = harness.container
          .read(sessionControllerProvider)
          .tabs
          .single
          .activePane
          .recentNotifications
          .single;
      expect(
        controller.dismissSessionNotification(sessionId, currentNotification),
        isTrue,
      );
      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'exact OSC 99 close report',
        matches: (text) => text.contains(
          'osc99-report-3:1b5d39393b693d696e746567726174696f6e3a703d636c6f73653b1b5c',
        ),
      );
      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'dismissed OSC 99 identifier absent from alive query',
        matches: (text) => text.contains(
          'osc99-alive-after-dismiss:1b5d39393b693d61667465722d6469736d6973733a703d616c6976653b1b5c',
        ),
      );
      expect(
        harness.container
            .read(sessionControllerProvider)
            .tabs
            .single
            .activePane
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
    'real PTY OSC 21 updates frame colors while OSC 23 preserves title',
    (tester) async {
      final goFile = _tempSignalFile('osc21-color-control');
      final profile = _scriptProfile(
        id: 'osc21-real-pty',
        name: 'OSC 21 Real PTY',
        script: r'''
printf 'osc21-ready\n'
while [ ! -f "$GO_FILE" ]; do sleep 0.05; done
printf '\033]0;stable-osc21-title\033\\'
printf '\033]21;foreground=#123456;background=#234567;cursor=#345678;196=#456789\033\\'
printf '\033]23;legacy-payload\033\\'
printf '\033[38;5;196mP\033[0m OSC21-SET\n'
sleep 1
''',
        env: {'GO_FILE': goFile.path},
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 21 real PTY ready marker',
        matches: (text) => text.contains('osc21-ready'),
      );
      _signal(goFile);

      await _waitFor(
        tester,
        description: 'OSC 21 frame colors and OSC 23 stable title',
        condition: () {
          final frame = _activeFrame(harness.container);
          final pane = _activePane(harness.container);
          if (frame == null || pane?.title != 'stable-osc21-title') {
            return false;
          }
          final matchingRows = frame.rows
              .where((row) => row.text.contains('P OSC21-SET'))
              .toList(growable: false);
          if (matchingRows.isEmpty) {
            return false;
          }
          final row = matchingRows.first;
          final column = row.text.indexOf('P OSC21-SET');
          final paletteRuns = row.styleRuns
              .where(
                (run) =>
                    run.start <= column &&
                    run.end > column &&
                    run.foreground?.toARGB32() == 0xff456789,
              )
              .toList(growable: false);
          return frame.defaultForeground?.toARGB32() == 0xff123456 &&
              frame.defaultBackground?.toARGB32() == 0xff234567 &&
              frame.cursorColor?.toARGB32() == 0xff345678 &&
              paletteRuns.isNotEmpty;
        },
        onTimeout: () {
          final frame = _activeFrame(harness.container);
          return 'Pane: ${_activePane(harness.container)}\nFrame: $frame';
        },
      );
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY xterm special and selection colors reach the product frame',
    (tester) async {
      final goFile = _tempSignalFile('xterm-special-colors');
      final profile = _scriptProfile(
        id: 'xterm-special-colors-real-pty',
        name: 'XTerm Special Colors Real PTY',
        script: r'''
printf 'xterm-special-colors-ready\n'
while [ ! -f "$GO_FILE" ]; do sleep 0.05; done
printf '\033]5;0;#c000ff\033\\'
printf '\033]6;0;1\033\\'
printf '\033]17;#112233;#445566;#778899\033\\'
printf '\033[1mB\033[0m XTERM-SPECIAL-COLORS\n'
sleep 1
''',
        env: {'GO_FILE': goFile.path},
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'xterm special colors real PTY ready marker',
        matches: (text) => text.contains('xterm-special-colors-ready'),
      );
      _signal(goFile);

      await _waitFor(
        tester,
        description: 'xterm special and selection colors in the product frame',
        condition: () {
          final frame = _activeFrame(harness.container);
          if (frame == null) {
            return false;
          }
          final matchingRows = frame.rows
              .where((row) => row.text.contains('B XTERM-SPECIAL-COLORS'))
              .toList(growable: false);
          if (matchingRows.isEmpty) {
            return false;
          }
          final row = matchingRows.first;
          final column = row.text.indexOf('B XTERM-SPECIAL-COLORS');
          final specialColorRuns = row.styleRuns
              .where(
                (run) =>
                    run.start <= column &&
                    run.end > column &&
                    run.foreground?.toARGB32() == 0xffc000ff &&
                    !run.bold,
              )
              .toList(growable: false);
          return frame.selectionBackground?.toARGB32() == 0xff112233 &&
              frame.selectionForeground?.toARGB32() == 0xff778899 &&
              specialColorRuns.isNotEmpty;
        },
        onTimeout: () => 'Frame: ${_activeFrame(harness.container)}',
      );
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY iTerm color extensions reach styles and product frame colors',
    (tester) async {
      final goFile = _tempSignalFile('iterm-color-extensions');
      final profile = _scriptProfile(
        id: 'iterm-color-extensions-real-pty',
        name: 'iTerm Color Extensions Real PTY',
        script: r'''
printf 'iterm-color-extensions-ready\n'
while [ ! -f "$GO_FILE" ]; do sleep 0.05; done
printf '\033]1337;SetColors=fg=112233,bg=000000,bold=ff00ff,underline=00ff00,link=00ffff,selbg=ff0000,selfg=000000,curbg=ffff00,curfg=0000ff,tab=123456,red=aabbcc\033\\'
printf '\033[1mB\033[0;4mU\033[0;38;5;1mR\033[0m ITERM-COLORS\n'
sleep 1
''',
        env: {'GO_FILE': goFile.path},
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'iTerm color extensions real PTY ready marker',
        matches: (text) => text.contains('iterm-color-extensions-ready'),
      );
      _signal(goFile);

      await _waitFor(
        tester,
        description: 'iTerm colors in styles and product frame metadata',
        condition: () {
          final frame = _activeFrame(harness.container);
          if (frame == null) {
            return false;
          }
          final rows = frame.rows
              .where((row) => row.text.contains('BUR ITERM-COLORS'))
              .toList(growable: false);
          if (rows.isEmpty) {
            return false;
          }
          final row = rows.first;
          final bold = row.styleRuns.where(
            (run) =>
                run.start == 0 &&
                run.foreground?.toARGB32() == 0xffff00ff &&
                run.bold,
          );
          final underline = row.styleRuns.where(
            (run) =>
                run.start == 1 &&
                run.underlineColor?.toARGB32() == 0xff00ff00 &&
                run.underline,
          );
          final palette = row.styleRuns.where(
            (run) => run.start == 2 && run.foreground?.toARGB32() == 0xffaabbcc,
          );
          return frame.defaultForeground?.toARGB32() == 0xff112233 &&
              frame.defaultBackground?.toARGB32() == 0xff000000 &&
              frame.cursorColor?.toARGB32() == 0xffffff00 &&
              frame.selectionBackground?.toARGB32() == 0xffff0000 &&
              frame.selectionForeground?.toARGB32() == 0xff000000 &&
              frame.linkColor?.toARGB32() == 0xff00ffff &&
              frame.cursorTextColor?.toARGB32() == 0xff0000ff &&
              frame.tabColor?.toARGB32() == 0xff123456 &&
              bold.isNotEmpty &&
              underline.isNotEmpty &&
              palette.isNotEmpty;
        },
        onTimeout: () => 'Frame: ${_activeFrame(harness.container)}',
      );
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY iTerm OSC 6 updates tab color incrementally and restores profile',
    (tester) async {
      final goFile = _tempSignalFile('iterm-osc6-tab-color');
      final baseProfile = _scriptProfile(
        id: 'iterm-osc6-tab-color-real-pty',
        name: 'iTerm OSC 6 Tab Color Real PTY',
        script: r'''
printf 'iterm-osc6-tab-color-ready\n'
while [ ! -f "$GO_FILE" ]; do sleep 0.05; done
printf '\033]6;1;bg;red;brightness;255\a'
printf '\033]6;1;bg;green;brightness;128\033\\'
printf '\033]6;1;bg;blue;brightness;64\a'
printf '\033]6;1;bg;red;brightness;999\a'
printf 'OSC6-TAB-SET\n'
IFS= read -r token
printf '\033]6;1;bg;*;default\033\\'
printf 'OSC6-TAB-RESET:%s\n' "$token"
sleep 1
''',
        env: {'GO_FILE': goFile.path},
      );
      final profile = baseProfile.copyWith(
        appearance: baseProfile.appearance.copyWith(
          colors: baseProfile.appearance.colors.copyWith(
            special: baseProfile.appearance.colors.special.copyWith(
              tab: '#102030',
            ),
          ),
        ),
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'iTerm OSC 6 real PTY ready marker',
        matches: (text) => text.contains('iterm-osc6-tab-color-ready'),
      );
      _signal(goFile);

      await _waitFor(
        tester,
        description: 'iTerm OSC 6 composed tab color in the product frame',
        condition: () {
          final frame = _activeFrame(harness.container);
          return frame?.tabColor?.toARGB32() == 0xffff8040 &&
              frame?.rows.any((row) => row.text.contains('OSC6-TAB-SET')) ==
                  true;
        },
        onTimeout: () => _activeFrame(harness.container).toString(),
      );

      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      harness.container
          .read(terminalRuntimeControllerProvider)
          .sendInput(sessionId, Uint8List.fromList(utf8.encode('continued\n')));
      await _waitFor(
        tester,
        description: 'iTerm OSC 6 profile reset and continued real PTY input',
        condition: () {
          final frame = _activeFrame(harness.container);
          return frame?.tabColor?.toARGB32() == 0xff102030 &&
              frame?.rows.any(
                    (row) => row.text.contains('OSC6-TAB-RESET:continued'),
                  ) ==
                  true;
        },
        onTimeout: () => _activeFrame(harness.container).toString(),
      );
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY OSC 22 updates pointer shape independently of mouse reporting',
    (tester) async {
      final goFile = _tempSignalFile('osc22-pointer-shape');
      final profile = _scriptProfile(
        id: 'osc22-real-pty',
        name: 'OSC 22 Real PTY',
        script: r'''
printf 'osc22-ready\n'
while [ ! -f "$GO_FILE" ]; do sleep 0.05; done
printf '\033[?1003h'
printf '\033]22;zoom-in\033\\'
printf 'OSC22-SET\n'
sleep 1
''',
        env: {'GO_FILE': goFile.path},
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 22 real PTY ready marker',
        matches: (text) => text.contains('osc22-ready'),
      );
      _signal(goFile);

      await _waitFor(
        tester,
        description: 'OSC 22 pointer frame and mouse-reporting independence',
        condition: () {
          final frame = _activeFrame(harness.container);
          return frame?.pointerShape == terminal.TerminalPointerShape.zoomIn &&
              frame?.modes.mouseMode == 'any_event' &&
              frame?.rows.any((row) => row.text.contains('OSC22-SET')) == true;
        },
        onTimeout: () => 'Frame: ${_activeFrame(harness.container)}',
      );
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY OSC 66 crosses frame transport and sized-text rendering',
    (tester) async {
      final goFile = _tempSignalFile('osc66-sized-text');
      final profile = _scriptProfile(
        id: 'osc66-real-pty',
        name: 'OSC 66 Real PTY',
        script: r'''
printf 'osc66-ready\n'
while [ ! -f "$GO_FILE" ]; do sleep 0.05; done
printf '\033[31;44;1m'
printf '\033]66;s=2:w=2:n=1:d=2:v=2:h=1;AB\033\\'
printf '\033[0m OSC66-DONE\n'
sleep 1
''',
        env: {'GO_FILE': goFile.path},
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 66 real PTY ready marker',
        matches: (text) => text.contains('osc66-ready'),
      );
      _signal(goFile);

      await _waitFor(
        tester,
        description: 'OSC 66 typed frame placement',
        condition: () {
          final frame = _activeFrame(harness.container);
          if (frame == null ||
              !frame.rows.any((row) => row.text.contains('OSC66-DONE'))) {
            return false;
          }
          return frame.sizedText.any(
            (placement) =>
                placement.text == 'AB' &&
                placement.widthCells == 4 &&
                placement.heightCells == 2 &&
                placement.scale == 2 &&
                placement.subscaleN == 1 &&
                placement.subscaleD == 2 &&
                placement.verticalAlign == 2 &&
                placement.horizontalAlign == 1 &&
                !placement.naturalWidth,
          );
        },
        onTimeout: () => 'Frame: ${_activeFrame(harness.container)}',
      );

      if (kDebugMode) {
        await _waitFor(
          tester,
          description: 'OSC 66 render-object sized-text paint',
          condition: () =>
              tester.allRenderObjects.whereType<RenderTerminalViewport>().any(
                (renderObject) => renderObject.debugSizedText.any(
                  (resolved) =>
                      resolved.text == 'AB' &&
                      resolved.blockRect.width > 0 &&
                      resolved.blockRect.height > 0 &&
                      resolved.visibleRect.width > 0 &&
                      resolved.visibleRect.height > 0 &&
                      resolved.scale > 0,
                ),
              ),
          onTimeout: () => 'Frame: ${_activeFrame(harness.container)}',
        );
      }
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY OSC 72 query and target lifecycle reach the macOS bridge',
    (tester) async {
      final goFile = _tempSignalFile('osc72-drop-target');
      final profile = _scriptProfile(
        id: 'osc72-real-pty',
        name: 'OSC 72 Real PTY',
        script: r'''
python3 - <<'PY'
import os, select, termios, time, tty
tty_fd = os.open("/dev/tty", os.O_RDWR)
old = termios.tcgetattr(tty_fd)
tty.setraw(tty_fd)
os.write(tty_fd, b"\x1b]72;t=q:i=72;\x1b\\")
ready, _, _ = select.select([tty_fd], [], [], 3.0)
data = os.read(tty_fd, 512) if ready else b"TIMEOUT"
termios.tcsetattr(tty_fd, termios.TCSANOW, old)
os.close(tty_fd)
os.write(1, b"OSC72-RESPONSE:" + repr(data).encode() + b"\n")
PY
printf '\033]72;t=a:i=72;text/plain text/uri-list\033\\OSC72-READY\n'
while [ ! -f "$GO_FILE" ]; do sleep 0.05; done
printf '\033]72;t=A:i=72;\033\\OSC72-STOPPED\n'
sleep 1
''',
        env: {'GO_FILE': goFile.path},
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 72 correlated query response and target marker',
        matches: (text) =>
            text.contains('t=q:i=72;drop=1:offer=0') &&
            text.contains('OSC72-READY'),
      );
      final enabled = await _waitForOsc72Status(
        tester,
        matches: (status) =>
            status.enabled &&
            status.mimeTypes.join(' ') == 'text/plain text/uri-list',
      );
      expect(enabled.sessionId, isNotEmpty);
      expect(enabled.cachedDrops, 0);

      _signal(goFile);
      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 72 target stop marker',
        matches: (text) => text.contains('OSC72-STOPPED'),
      );
      await _waitForOsc72Status(tester, matches: (status) => !status.enabled);
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY OSC 1337 mark version and cell-size reply cross the product',
    (tester) async {
      final profile = _scriptProfile(
        id: 'osc1337-shell-metadata',
        name: 'OSC 1337 Shell Metadata',
        script: r'''
python3 - <<'PY'
import os, select, termios, tty
tty_fd = os.open("/dev/tty", os.O_RDWR)
old = termios.tcgetattr(tty_fd)
tty.setraw(tty_fd)
os.write(tty_fd, b"\x1b]1337;ShellIntegrationVersion=17;zsh\x1b\\")
os.write(tty_fd, b"OSC1337-MARK-LINE\r\n\x1b]1337;SetMark\x07")
os.write(tty_fd, b"\x1b]1337;ReportCellSize\x1b\\")
ready, _, _ = select.select([tty_fd], [], [], 3.0)
data = os.read(tty_fd, 512) if ready else b"TIMEOUT"
termios.tcsetattr(tty_fd, termios.TCSANOW, old)
os.close(tty_fd)
os.write(1, b"OSC1337-CELL:" + repr(data).encode() + b"\n")
PY
sleep 1
''',
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 1337 cell-size response marker',
        matches: (text) =>
            text.contains('OSC1337-MARK-LINE') &&
            text.contains('OSC1337-CELL:') &&
            text.contains('ReportCellSize='),
      );
      final pane = harness.container
          .read(sessionControllerProvider)
          .tabs
          .single
          .activePane;
      expect(pane.shellIntegration.shell, 'zsh');
      expect(pane.shellIntegration.integrationVersion, '17');
      expect(pane.shellIntegration.promptMarks, isNotEmpty);
      expect(pane.shellIntegration.promptMarks.last.globalLine, isNotNull);
      final text = _activeFrame(
        harness.container,
      )!.rows.map((row) => row.text).join('\n');
      final response = RegExp(
        r'ReportCellSize=(\d+\.\d{2});(\d+\.\d{2});(\d+\.\d{2})',
      ).firstMatch(text);
      expect(response, isNotNull);
      expect(double.parse(response!.group(1)!), greaterThan(0));
      expect(double.parse(response.group(2)!), greaterThan(0));
      expect(double.parse(response.group(3)!), greaterThanOrEqualTo(1));
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY OSC 1337 and DECSCUSR cursor shapes reach the renderer',
    (tester) async {
      final oscFile = _tempSignalFile('osc1337-cursor-shape');
      final csiFile = _tempSignalFile('decscusr-cursor-shape');
      final profile = _scriptProfile(
        id: 'osc1337-cursor-shape',
        name: 'OSC 1337 Cursor Shape',
        script: r'''
printf 'osc1337-cursor-ready\n'
while [ ! -f "$OSC_FILE" ]; do sleep 0.05; done
printf '\033]1337;CursorShape=1\033\\OSC1337-CURSOR-BEAM\n'
while [ ! -f "$CSI_FILE" ]; do sleep 0.05; done
printf '\033[4 qDECSCUSR-CURSOR-UNDERLINE\n'
sleep 1
''',
        env: {'OSC_FILE': oscFile.path, 'CSI_FILE': csiFile.path},
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 1337 cursor ready marker',
        matches: (text) => text.contains('osc1337-cursor-ready'),
      );
      _signal(oscFile);
      await _waitFor(
        tester,
        description: 'OSC 1337 beam cursor frame',
        condition: () {
          final frame = _activeFrame(harness.container);
          return frame?.cursor.shape == terminal.TerminalCursorShape.beam &&
              frame!.cursor.blink == null &&
              frame.rows.any((row) => row.text.contains('OSC1337-CURSOR-BEAM'));
        },
      );

      _signal(csiFile);
      await _waitFor(
        tester,
        description: 'DECSCUSR steady underline cursor frame',
        condition: () {
          final frame = _activeFrame(harness.container);
          return frame?.cursor.shape ==
                  terminal.TerminalCursorShape.underline &&
              frame!.cursor.blink == false &&
              frame.rows.any(
                (row) => row.text.contains('DECSCUSR-CURSOR-UNDERLINE'),
              );
        },
      );
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY OSC 1337 ReportVariable denies first and reports future allowed value',
    (tester) async {
      final goFile = _tempSignalFile('osc1337-report-variable');
      final profile = _scriptProfile(
        id: 'osc1337-report-variable',
        name: 'OSC 1337 Report Variable',
        script: r'''
python3 - <<'PY'
import os, select, termios, time, tty

tty_fd = os.open('/dev/tty', os.O_RDWR)
old = termios.tcgetattr(tty_fd)
tty.setraw(tty_fd)

def read_report():
    data = b''
    deadline = time.time() + 5.0
    while time.time() < deadline and b'\x07' not in data:
        ready, _, _ = select.select([tty_fd], [], [], 0.1)
        if ready:
            data += os.read(tty_fd, 4096)
    return data if data else b'TIMEOUT'

try:
    os.write(tty_fd, b'\x1b]1337;SetUserVar=REPORT_KEY=cmVwb3J0LXZhbHVl\x07')
    os.write(tty_fd, b'\x1b]1337;ReportVariable=dXNlci5SRVBPUlRfS0VZ\x07')
    first = read_report()
    os.write(1, b'OSC1337-REPORT-FIRST:' + first.hex().encode() + b'\r\n')
    while not os.path.exists(os.environ['GO_FILE']):
        time.sleep(0.05)
    os.write(tty_fd, b'\x1b]1337;ReportVariable=dXNlci5SRVBPUlRfS0VZ\x1b\\')
    allowed = read_report()
    os.write(1, b'OSC1337-REPORT-ALLOWED:' + allowed.hex().encode() + b'\r\n')
    os.write(tty_fd, b'\x1b]1337;ReportVariable=c2Vzc2lvbi5lbnZpcm9ubWVudA==\x07')
    unknown = read_report()
    os.write(1, b'OSC1337-REPORT-UNKNOWN:' + unknown.hex().encode() + b'\r\n')
finally:
    termios.tcsetattr(tty_fd, termios.TCSANOW, old)
    os.close(tty_fd)
PY
sleep 1
''',
        env: {'GO_FILE': goFile.path},
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitFor(
        tester,
        description: 'OSC 1337 first denied report and future policy prompt',
        condition: () =>
            find
                .byKey(const Key('osc1337-report-variable-dialog'))
                .evaluate()
                .isNotEmpty &&
            _terminalText(harness.container).contains(
              'OSC1337-REPORT-FIRST:'
              '1b5d313333373b5265706f72745661726961626c653d07',
            ),
        onTimeout: () => 'Terminal text: ${_terminalText(harness.container)}',
      );
      expect(find.text('user.REPORT_KEY'), findsOneWidget);
      await tester.tap(find.byKey(const Key('osc1337-report-variable-allow')));
      await tester.pumpAndSettle();
      _signal(goFile);

      await _waitFor(
        tester,
        description: 'OSC 1337 allowed and unknown exact report replies',
        condition: () {
          final text = _terminalText(harness.container);
          return text.contains('OSC1337-REPORT-ALLOWED:') &&
              text.contains('OSC1337-REPORT-UNKNOWN:');
        },
        onTimeout: () => 'Terminal text: ${_terminalText(harness.container)}',
      );
      final terminalText = _terminalText(harness.container);
      final compactTerminalText = terminalText.replaceAll('\n', '');
      expect(
        compactTerminalText,
        contains(
          'OSC1337-REPORT-ALLOWED:'
          '1b5d313333373b5265706f72745661726961626c653d636d567762334a304c585a686248566c07',
        ),
      );
      expect(
        compactTerminalText,
        contains(
          'OSC1337-REPORT-UNKNOWN:'
          '1b5d313333373b5265706f72745661726961626c653d07',
        ),
      );
      expect(
        find.byKey(const Key('osc1337-report-variable-dialog')),
        findsNothing,
      );
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY OSC 1337 UnicodeVersion changes visible columns and survives resize input',
    (tester) async {
      final profile = _scriptProfile(
        id: 'osc1337-unicode-version',
        name: 'OSC 1337 Unicode Version',
        script: r'''
printf '\033]1337;UnicodeVersion=8\aU8:☕\033[38;2;255;0;0mX\033[0m\r\n'
printf '\033]1337;UnicodeVersion=push app-test\033\\'
printf '\033]1337;UnicodeVersion=9\033\\U9:☕\033[38;2;255;0;0mX\033[0m\r\n'
printf '\033]1337;UnicodeVersion=pop app-test\aU8R:☕\033[38;2;255;0;0mX\033[0m\r\n'
printf 'U8-FINAL:☕X'
IFS= read -r token
printf '\r\nAFTER:%s:☕X' "$token"
sleep 1
''',
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitFor(
        tester,
        description: 'Unicode 8/9 visible terminal-column contract',
        condition: () {
          final frame = _activeFrame(harness.container);
          if (frame == null ||
              !frame.rows.any((row) => row.text.contains('U8-FINAL:☕X'))) {
            return false;
          }

          terminal.TerminalRow? rowFor(String marker) {
            for (final row in frame.rows) {
              if (row.text.contains(marker)) {
                return row;
              }
            }
            return null;
          }

          bool hasRedSpan(String marker, int start, int end) {
            final row = rowFor(marker);
            return row != null &&
                row.styleRuns.any(
                  (run) =>
                      run.start == start &&
                      run.end == end &&
                      run.foreground?.toARGB32() == 0xffff0000,
                );
          }

          return hasRedSpan('U8:', 4, 5) &&
              hasRedSpan('U9:', 5, 6) &&
              hasRedSpan('U8R:', 5, 6) &&
              frame.cursor.col == 11;
        },
        onTimeout: () {
          final frame = _activeFrame(harness.container);
          return frame == null ? 'No frame' : _frameDebug(frame);
        },
      );

      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      harness.container
          .read(sessionControllerProvider.notifier)
          .resizeSession(sessionId, const Size(900, 600), 1);
      harness.container
          .read(terminalRuntimeControllerProvider)
          .sendInput(sessionId, Uint8List.fromList(utf8.encode('continued\n')));

      await _waitFor(
        tester,
        description: 'Unicode 8 width after resize replay and continued input',
        condition: () {
          final frame = _activeFrame(harness.container);
          return frame != null &&
              frame.rows.any(
                (row) => row.text.contains('AFTER:continued:☕X'),
              ) &&
              frame.cursor.col == 18;
        },
        onTimeout: () {
          final frame = _activeFrame(harness.container);
          return frame == null ? 'No frame' : _frameDebug(frame);
        },
      );
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY OSC 1337 cursor guide enables, paints, and disables',
    (tester) async {
      final enableFile = _tempSignalFile('osc1337-cursor-guide-enable');
      final disableFile = _tempSignalFile('osc1337-cursor-guide-disable');
      final profile = _scriptProfile(
        id: 'osc1337-cursor-guide',
        name: 'OSC 1337 Cursor Guide',
        script: r'''
printf 'osc1337-cursor-guide-ready\n'
while [ ! -f "$ENABLE_FILE" ]; do sleep 0.05; done
printf '\033]1337;HighlightCursorLine=yes\033\\OSC1337-GUIDE-ENABLED\n'
while [ ! -f "$DISABLE_FILE" ]; do sleep 0.05; done
printf '\033]1337;HighlightCursorLine=no\033\\OSC1337-GUIDE-DISABLED\n'
sleep 1
''',
        env: {'ENABLE_FILE': enableFile.path, 'DISABLE_FILE': disableFile.path},
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 1337 cursor guide ready marker',
        matches: (text) => text.contains('osc1337-cursor-guide-ready'),
      );
      _signal(enableFile);
      await _waitFor(
        tester,
        description: 'OSC 1337 cursor guide enabled frame',
        condition: () {
          final frame = _activeFrame(harness.container);
          return frame?.cursor.highlightLine == true &&
              frame!.cursorGuideColor != null &&
              frame.rows.any(
                (row) => row.text.contains('OSC1337-GUIDE-ENABLED'),
              );
        },
        onTimeout: () => 'Frame: ${_activeFrame(harness.container)}',
      );

      if (kDebugMode) {
        await _waitFor(
          tester,
          description: 'OSC 1337 cursor guide render-object paint',
          condition: () =>
              tester.allRenderObjects.whereType<RenderTerminalViewport>().any(
                (renderObject) =>
                    renderObject.debugCursorGuideRect?.height.isFinite ==
                        true &&
                    renderObject.debugCursorGuideColor != null,
              ),
        );
      }

      _signal(disableFile);
      await _waitFor(
        tester,
        description: 'OSC 1337 cursor guide disabled frame',
        condition: () {
          final frame = _activeFrame(harness.container);
          return frame?.cursor.highlightLine == false &&
              frame!.rows.any(
                (row) => row.text.contains('OSC1337-GUIDE-DISABLED'),
              );
        },
        onTimeout: () => 'Frame: ${_activeFrame(harness.container)}',
      );
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY iTerm2 OSC 1337 streaming and base64 copy use clipboard policy',
    (tester) async {
      final goFile = _tempSignalFile('osc1337-clipboard');
      final writes = <(String, String)>[];
      final profile = _scriptProfile(
        id: 'osc1337-clipboard',
        name: 'OSC 1337 Clipboard',
        script: r'''
printf 'osc1337-clipboard-ready\n'
while [ ! -f "$GO_FILE" ]; do sleep 0.05; done
printf '\033]1337;CopyToClipboard=find\a'
printf 'streamed clipboard text'
printf '\033]1337;EndCopy\033\\'
printf '\033]1337;Copy=:ZGlyZWN0IPCfmIA=\a'
printf '\nOSC1337-CLIPBOARD-DONE\n'
sleep 1
''',
        env: {'GO_FILE': goFile.path},
      );
      final harness = await _pumpRealPtyApp(
        tester,
        profiles: [profile],
        clipboardTextWrite: (text, selection) async {
          writes.add((text, selection));
        },
      );

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 1337 clipboard ready marker',
        matches: (text) => text.contains('osc1337-clipboard-ready'),
      );
      _signal(goFile);

      await _waitFor(
        tester,
        description: 'OSC 1337 clipboard writes and visible stream output',
        condition: () =>
            writes.length == 2 &&
            _terminalText(
              harness.container,
            ).contains('streamed clipboard text') &&
            _terminalText(harness.container).contains('OSC1337-CLIPBOARD-DONE'),
        onTimeout: () =>
            'Writes: $writes; text: ${_terminalText(harness.container)}',
      );
      expect(writes, <(String, String)>[
        ('streamed clipboard text', 'find'),
        ('direct 😀', 'c'),
      ]);
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY iTerm2 OSC 1337 download requires Save and blocks upload',
    (tester) async {
      final downloadFile = _tempSignalFile('osc1337-file-download');
      final uploadFile = _tempSignalFile('osc1337-file-upload');
      String? savedPath;
      List<int>? savedBytes;
      final profile = _scriptProfile(
        id: 'osc1337-file-transfer',
        name: 'OSC 1337 File Transfer',
        script: r'''
trap '' INT
printf 'osc1337-file-transfer-ready\n'
while [ ! -f "$DOWNLOAD_FILE" ]; do sleep 0.05; done
printf '\033]1337;File=name=b3NjLXBoYXNlMjgudHh0;size=14;inline=0:aGVsbG8gcGhhc2UgMjg=\a'
while [ ! -f "$UPLOAD_FILE" ]; do sleep 0.05; done
stty -isig
printf '\033]1337;RequestUpload=format=tgz\a'
printf '\nOSC1337-FILE-TRANSFER-DONE\n'
sleep 5
''',
        env: <String, String>{
          'DOWNLOAD_FILE': downloadFile.path,
          'UPLOAD_FILE': uploadFile.path,
        },
      );
      final harness = await _pumpRealPtyApp(
        tester,
        profiles: [profile],
        fileDownloadWriter: (path, bytes) async {
          savedPath = path;
          savedBytes = List<int>.from(bytes);
        },
      );
      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 1337 file transfer ready marker',
        matches: (text) => text.contains('osc1337-file-transfer-ready'),
      );

      const channel = MethodChannel('app/window_bridge');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        return call.method == 'chooseFileDownloadLocation'
            ? '/virtual/osc-phase28.txt'
            : null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      _signal(downloadFile);

      await _waitFor(
        tester,
        description: 'OSC 1337 real PTY download Save prompt',
        condition: () =>
            find.text('Received osc-phase28.txt (14 B)').evaluate().isNotEmpty,
        onTimeout: () => 'Terminal text: ${_terminalText(harness.container)}',
      );
      expect(savedBytes, isNull);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byKey(const Key('osc1337-file-download-save-1')));
      await _waitFor(
        tester,
        description: 'OSC 1337 real PTY exact saved bytes',
        condition: () => savedBytes != null,
      );
      expect(savedPath, '/virtual/osc-phase28.txt');
      expect(savedBytes, utf8.encode('hello phase 28'));
      await _waitFor(
        tester,
        description: 'OSC 1337 real PTY saved feedback',
        condition: () =>
            find.text('Saved osc-phase28.txt').evaluate().isNotEmpty,
      );

      _signal(uploadFile);
      await _waitFor(
        tester,
        description: 'OSC 1337 real PTY upload denial',
        condition: () =>
            find.text('File upload request blocked').evaluate().isNotEmpty &&
            _terminalText(
              harness.container,
            ).contains('OSC1337-FILE-TRANSFER-DONE'),
        onTimeout: () => 'Terminal text: ${_terminalText(harness.container)}',
      );
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY iTerm2 OSC 1337 OpenURL waits for explicit approval',
    (tester) async {
      final goFile = _tempSignalFile('osc1337-open-url');
      final opened = <String>[];
      final profile = _scriptProfile(
        id: 'osc1337-open-url',
        name: 'OSC 1337 Open URL',
        script: r'''
printf 'osc1337-open-url-ready\n'
while [ ! -f "$GO_FILE" ]; do sleep 0.05; done
printf '\033]1337;OpenURL=:aHR0cHM6Ly9leGFtcGxlLnRlc3QvcGhhc2UyOQ==\033\\'
printf 'OSC1337-OPEN-URL-DONE\n'
sleep 5
''',
        env: {'GO_FILE': goFile.path},
      );
      final harness = await _pumpRealPtyApp(
        tester,
        profiles: [profile],
        externalUrlOpener: (url) async => opened.add(url),
      );
      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 1337 OpenURL ready marker',
        matches: (text) => text.contains('osc1337-open-url-ready'),
      );

      _signal(goFile);
      await _waitFor(
        tester,
        description: 'OSC 1337 OpenURL confirmation dialog',
        condition: () =>
            find
                .byKey(const Key('osc1337-open-url-dialog'))
                .evaluate()
                .isNotEmpty &&
            _terminalText(harness.container).contains('OSC1337-OPEN-URL-DONE'),
        onTimeout: () => 'Terminal text: ${_terminalText(harness.container)}',
      );
      expect(
        opened,
        isEmpty,
        reason: 'PTY output must not open a URL by itself',
      );
      expect(find.text('Open terminal-requested URL?'), findsOneWidget);
      expect(
        find.textContaining('https://example.test/phase29'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('osc1337-open-url-approve')));
      await _waitFor(
        tester,
        description: 'approved OSC 1337 URL opener call',
        condition: () => opened.length == 1,
      );
      expect(opened, <String>['https://example.test/phase29']);
      expect(
        _terminalText(harness.container),
        contains('OSC1337-OPEN-URL-DONE'),
      );
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY iTerm2 OSC 1337 attention reaches bounded product effects',
    (tester) async {
      final goFile = _tempSignalFile('osc1337-attention');
      final attention = _RecordingAttentionBridge();
      final profile = _scriptProfile(
        id: 'osc1337-attention',
        name: 'OSC 1337 Attention',
        script: r'''
printf 'osc1337-attention-ready\n'
while [ ! -f "$GO_FILE" ]; do sleep 0.05; done
printf '\033]1337;RequestAttention=fireworks\033\\'
printf 'OSC1337-FIREWORKS-SHOWN\n'
sleep 1
printf '\033]1337;RequestAttention=once\007'
printf 'OSC1337-ONCE-REQUESTED\n'
sleep 0.2
printf '\033]1337;RequestAttention=no\033\\'
printf 'OSC1337-ATTENTION-DONE\n'
sleep 5
''',
        env: {'GO_FILE': goFile.path},
      );
      final harness = await _pumpRealPtyApp(
        tester,
        profiles: [profile],
        localConfig: const LocalTerminalConfigDocument(
          hostActions: LocalTerminalHostActionsConfig(
            osc1337RequestAttention: LocalTerminalRequestAttentionPolicy.allow,
          ),
        ),
        userAttentionBridge: attention,
      );
      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 1337 attention ready marker',
        matches: (text) => text.contains('osc1337-attention-ready'),
      );
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      final fireworks = find.byKey(Key('osc1337-fireworks-$sessionId'));

      _signal(goFile);
      await _waitFor(
        tester,
        description: 'cursor-local OSC 1337 fireworks overlay',
        condition: () =>
            fireworks.evaluate().isNotEmpty &&
            _terminalText(
              harness.container,
            ).contains('OSC1337-FIREWORKS-SHOWN'),
        onTimeout: () => 'Terminal text: ${_terminalText(harness.container)}',
      );
      expect(attention.requests, isEmpty);

      await _waitFor(
        tester,
        description: 'informational attention request and cancellation',
        condition: () =>
            attention.requests.length == 1 &&
            attention.cancellations.length == 1 &&
            _terminalText(harness.container).contains('OSC1337-ATTENTION-DONE'),
        onTimeout: () =>
            'requests=${attention.requests} '
            'cancellations=${attention.cancellations}\n'
            'Terminal text: ${_terminalText(harness.container)}',
      );
      expect(attention.requests, <NativeUserAttentionType>[
        NativeUserAttentionType.informational,
      ]);
      expect(attention.cancellations, <int>[700]);
      expect(fireworks, findsNothing);
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY iTerm2 OSC 1337 annotations reach the product sheet and badge',
    (tester) async {
      final goFile = _tempSignalFile('osc1337-annotations');
      final profile = _scriptProfile(
        id: 'osc1337-annotations',
        name: 'OSC 1337 Annotations',
        script: r'''
printf 'osc1337-annotations-ready\n'
while [ ! -f "$GO_FILE" ]; do sleep 0.05; done
printf 'prefix \033]1337;AddHiddenAnnotation=4|Hidden protocol note\aaway\n'
printf 'second \033]1337;AddAnnotation=7|Visible protocol note\033\\visible\n'
printf 'OSC1337-ANNOTATIONS-DONE\n'
sleep 1
''',
        env: {'GO_FILE': goFile.path},
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 1337 annotations ready marker',
        matches: (text) => text.contains('osc1337-annotations-ready'),
      );
      _signal(goFile);

      await _waitFor(
        tester,
        description: 'visible OSC 1337 annotation product sheet',
        condition: () =>
            find.byKey(const Key('annotations-sheet')).evaluate().isNotEmpty &&
            find.text('Visible protocol note').evaluate().isNotEmpty &&
            find.text('Hidden protocol note').evaluate().isNotEmpty &&
            find.text('visible').evaluate().isNotEmpty &&
            find.text('away').evaluate().isNotEmpty,
        onTimeout: () => 'Terminal text: ${_terminalText(harness.container)}',
      );

      await tester.tap(find.byKey(const Key('annotations-close')));
      await tester.pumpAndSettle();
      final sessionId = harness.container
          .read(sessionControllerProvider)
          .activeSessionId!;
      expect(
        find.byKey(Key('terminal-annotation-badge-$sessionId')),
        findsOneWidget,
      );
      expect(find.text('2 annotations'), findsOneWidget);
      expect(
        _terminalText(harness.container),
        contains('OSC1337-ANNOTATIONS-DONE'),
      );
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY iTerm2 OSC 1337 blocks fold and unfold through product controls',
    (tester) async {
      final goFile = _tempSignalFile('osc1337-blocks');
      final profile = _scriptProfile(
        id: 'osc1337-blocks',
        name: 'OSC 1337 Blocks',
        script: r'''
printf 'osc1337-blocks-ready\n'
while [ ! -f "$GO_FILE" ]; do sleep 0.05; done
printf '\033]1337;Block=id=build-acceptance;attr=start;type=build\033\\'
printf 'BLOCK-FIRST\nBLOCK-SECRET\nBLOCK-LAST'
printf '\033]1337;Block=id=build-acceptance;attr=end\033\\'
printf '\033]1337;UpdateBlock=id=build-acceptance;action=fold\033\\'
printf '\nOSC1337-BLOCKS-DONE\n'
sleep 5
''',
        env: {'GO_FILE': goFile.path},
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitForTerminalText(
        tester,
        harness.container,
        description: 'OSC 1337 blocks ready marker',
        matches: (text) => text.contains('osc1337-blocks-ready'),
      );
      _signal(goFile);

      await _waitFor(
        tester,
        description: 'folded OSC 1337 block product frame',
        condition: () {
          final frame = _activeFrame(harness.container);
          return frame != null &&
              frame.blocks.any(
                (block) =>
                    block.id == 'build-acceptance' &&
                    block.folded &&
                    block.hiddenRows == 2,
              ) &&
              frame.rows.any(
                (row) =>
                    row.text.contains('BLOCK-FIRST') &&
                    row.text.contains('BLOCK-LAST') &&
                    row.sourceEndRow != null,
              ) &&
              !frame.rows.any((row) => row.text.contains('BLOCK-SECRET'));
        },
        onTimeout: () => 'Frame: ${_activeFrame(harness.container)}',
      );

      final toggle = find.byKey(
        terminal.terminalBlockToggleKey('build-acceptance'),
      );
      expect(toggle, findsOneWidget);
      expect(find.byTooltip('Unfold block'), findsOneWidget);
      await tester.tap(toggle);
      await tester.pump();

      await _waitFor(
        tester,
        description: 'unfolded OSC 1337 block product frame',
        condition: () {
          final frame = _activeFrame(harness.container);
          return frame != null &&
              frame.blocks.any(
                (block) => block.id == 'build-acceptance' && !block.folded,
              ) &&
              frame.rows.any((row) => row.text.contains('BLOCK-SECRET'));
        },
        onTimeout: () => 'Frame: ${_activeFrame(harness.container)}',
      );
      expect(find.byTooltip('Fold block'), findsOneWidget);

      await tester.tap(toggle);
      await tester.pump();
      await _waitFor(
        tester,
        description: 're-folded OSC 1337 block product frame',
        condition: () {
          final frame = _activeFrame(harness.container);
          return frame != null &&
              frame.blocks.any(
                (block) => block.id == 'build-acceptance' && block.folded,
              ) &&
              !frame.rows.any((row) => row.text.contains('BLOCK-SECRET'));
        },
        onTimeout: () => 'Frame: ${_activeFrame(harness.container)}',
      );
      expect(_terminalText(harness.container), contains('OSC1337-BLOCKS-DONE'));
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY iTerm2 OSC 1337 buttons copy and return the exact custom reply',
    (tester) async {
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String?;
          }
          if (call.method == 'Clipboard.getData') {
            return <String, Object?>{'text': copiedText};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final profile = _scriptProfile(
        id: 'osc1337-buttons',
        name: 'OSC 1337 Buttons',
        script: r'''
printf '\033]1337;Block=id=copy-acceptance;attr=start\033\\'
printf 'BUTTON-COPY-EXACT'
printf '\033]1337;Block=id=copy-acceptance;attr=end\033\\\r\n'
printf '\033]1337;Button=type=copy;block=copy-acceptance\a'
printf '\033]1337;Button=type=custom;code=42;icon=star.fill\033\\'
printf 'OSC1337-BUTTONS-READY\r\n'
saved_stty=$(stty -g)
stty raw -echo
reply=$(dd bs=1 count=11 2>/dev/null | od -An -tx1 | tr -d ' \n')
stty "$saved_stty"
printf 'OSC1337-BUTTON-REPLY:%s\r\n' "$reply"
printf '\033]1337;Button=type=custom\033\\OSC1337-BUTTON-INVALID\r\n'
sleep 5
''',
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitFor(
        tester,
        description: 'OSC 1337 real PTY inline buttons',
        condition: () {
          final frame = _activeFrame(harness.container);
          return frame != null &&
              frame.inlineButtons.length == 2 &&
              frame.inlineButtons.every((button) => button.valid) &&
              _terminalText(
                harness.container,
              ).contains('OSC1337-BUTTONS-READY');
        },
        onTimeout: () => 'Frame: ${_activeFrame(harness.container)}',
      );
      final initial = _activeFrame(harness.container)!;
      final copy = initial.inlineButtons.firstWhere(
        (button) => button.kind == terminal.TerminalInlineButtonKind.copy,
      );
      final custom = initial.inlineButtons.firstWhere(
        (button) => button.kind == terminal.TerminalInlineButtonKind.custom,
      );
      await tester.tap(find.byKey(terminal.terminalInlineButtonKey(copy.id)));
      await tester.pump();
      expect(copiedText, 'BUTTON-COPY-EXACT');

      await tester.tap(find.byKey(terminal.terminalInlineButtonKey(custom.id)));
      await _waitFor(
        tester,
        description: 'OSC 1337 exact custom response and invalidation',
        condition: () {
          final frame = _activeFrame(harness.container);
          return _terminalText(
                harness.container,
              ).contains('OSC1337-BUTTON-REPLY:1b5b3f313333373b34327e') &&
              frame != null &&
              frame.inlineButtons.any(
                (button) =>
                    button.id == custom.id &&
                    button.kind == terminal.TerminalInlineButtonKind.custom &&
                    !button.valid,
              );
        },
        onTimeout: () =>
            'Text: ${_terminalText(harness.container)}; frame: ${_activeFrame(harness.container)}',
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(terminal.terminalInlineButtonKey(custom.id)),
            )
            .onPressed,
        isNull,
      );
    },
    skip: _skipNonRefreshPolicyGateTests,
  );

  testWidgets(
    'real PTY OSC 1337 ClearScrollback clears product rows and history',
    (tester) async {
      final goFile = _tempSignalFile('osc1337-clear-buffer');
      final profile = _scriptProfile(
        id: 'osc1337-clear-buffer',
        name: 'OSC 1337 Clear Buffer',
        script: r'''
index=0
while [ "$index" -lt 48 ]; do
  printf 'OSC1337-OLD-%02d\n' "$index"
  index=$((index + 1))
done
printf 'OSC1337-CLEAR-READY\n'
while [ ! -f "$GO_FILE" ]; do sleep 0.05; done
printf '\033]1337;ClearScrollback\033\\OSC1337-AFTER-CLEAR\n'
sleep 1
''',
        env: {'GO_FILE': goFile.path},
      );
      final harness = await _pumpRealPtyApp(tester, profiles: [profile]);

      await _waitFor(
        tester,
        description: 'OSC 1337 pre-clear scrollback',
        condition: () {
          final frame = _activeFrame(harness.container);
          return frame != null &&
              frame.scrollbackMaxOffset > 0 &&
              frame.rows.any((row) => row.text.contains('OSC1337-CLEAR-READY'));
        },
      );

      _signal(goFile);
      await _waitFor(
        tester,
        description: 'OSC 1337 cleared product frame',
        condition: () {
          final frame = _activeFrame(harness.container);
          if (frame == null ||
              frame.scrollbackOffset != 0 ||
              frame.scrollbackMaxOffset != 0 ||
              !frame.rows.any(
                (row) => row.text.contains('OSC1337-AFTER-CLEAR'),
              )) {
            return false;
          }
          return frame.rows.every((row) => !row.text.contains('OSC1337-OLD-'));
        },
        onTimeout: () => 'Frame: ${_activeFrame(harness.container)}',
      );
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
  SessionClipboardTextWrite? clipboardTextWrite,
  ShellFileDownloadWriter? fileDownloadWriter,
  ShellExternalUrlOpener? externalUrlOpener,
  LocalTerminalConfigDocument? localConfig,
  ShellUserAttentionBridge? userAttentionBridge,
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
        MemoryLocalTerminalConfigRepository(localConfig),
      ),
      shellAnimationsEnabledProvider.overrideWithValue(false),
      if (clipboardTextWrite != null)
        sessionClipboardTextWriteProvider.overrideWithValue(clipboardTextWrite),
      if (fileDownloadWriter != null)
        shellFileDownloadWriterProvider.overrideWithValue(fileDownloadWriter),
      if (externalUrlOpener != null)
        shellExternalUrlOpenerProvider.overrideWithValue(externalUrlOpener),
      if (userAttentionBridge != null)
        shellUserAttentionBridgeProvider.overrideWithValue(userAttentionBridge),
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

final class _RecordingAttentionBridge implements ShellUserAttentionBridge {
  final List<NativeUserAttentionType> requests = <NativeUserAttentionType>[];
  final List<int> cancellations = <int>[];

  @override
  Future<int?> request(NativeUserAttentionType type) async {
    requests.add(type);
    return 700;
  }

  @override
  Future<void> cancel(int requestId) async {
    cancellations.add(requestId);
  }
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

Future<NativeOsc72DropTargetStatus> _waitForOsc72Status(
  WidgetTester tester, {
  required bool Function(NativeOsc72DropTargetStatus status) matches,
}) async {
  final deadline = DateTime.now().add(_frameWait);
  NativeOsc72DropTargetStatus? latest;
  while (DateTime.now().isBefore(deadline)) {
    latest = await WindowBridge.osc72DropTargetStatus();
    if (latest != null && matches(latest)) {
      return latest;
    }
    await tester.pump(_pollStep);
  }
  fail('Timed out waiting for OSC 72 native target status. Latest: $latest');
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
