import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/widgets/mobile_session_list.dart';
import 'package:app/features/terminal/terminal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  group(MobileSessionList, () {
    testWidgets(
      'groups split panes by current status and routes each explicit action',
      (tester) async {
        final actions = _SessionActions();
        final running = _pane('running');
        final history = _pane('history', exited: true, exitCode: 255);
        await _pumpList(
          tester,
          actions.list([
            _tab([running, history]),
          ]),
        );

        expect(find.text('Active sessions (1)'), findsOneWidget);
        expect(find.text('Disconnected (1)'), findsOneWidget);
        expect(find.text('Running'), findsOneWidget);
        expect(find.text('user@running.example:2222'), findsOneWidget);
        expect(_row('history'), findsNothing);
        await tester.tap(_row('running'));
        await tester.tap(_action('disconnect', 'running'));
        expect(actions.selected, [same(running)]);
        expect(actions.disconnected, [same(running)]);
        expect(actions.removed, isEmpty);

        // Clearing remains available without opening every retained record.
        await tester.tap(_clear);
        expect(actions.clears, 1);
        await tester.tap(_toggle);
        await tester.pump();
        expect(find.text('user@history.example:2222'), findsOneWidget);
        expect(find.text('Exit code 255'), findsOneWidget);
        expect(find.text('View output'), findsOneWidget);
        await tester.ensureVisible(_row('history'));
        await tester.tap(_row('history'));
        await tester.ensureVisible(_action('reconnect', 'history'));
        await tester.tap(_action('reconnect', 'history'));
        await tester.tap(_action('remove', 'history'));
        expect(actions.selected, [same(running), same(history)]);
        expect(actions.reconnected, [same(history)]);
        expect(actions.removed, [same(history)]);
        expect(actions.disconnected, [same(running)]);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'updates visible groups and callbacks from replacement session state',
      (tester) async {
        final actions = _SessionActions();
        final running = _pane('running');
        final history = _pane('history', exited: true);
        final tabs = ValueNotifier([
          _tab([running, history]),
        ]);
        addTearDown(tabs.dispose);
        await _pumpList(
          tester,
          ValueListenableBuilder<List<TerminalTab>>(
            valueListenable: tabs,
            builder: (_, value, _) => actions.list(value),
          ),
        );
        await tester.tap(_toggle);
        await tester.pump();

        final exited = running.copyWith(
          title: 'Latest retained output',
          isExited: true,
          exitCode: 17,
        );
        tabs.value = [
          _tab([exited, history]),
        ];
        await tester.pump();
        expect(find.text('Active sessions (0)'), findsOneWidget);
        expect(find.text('Disconnected (2)'), findsOneWidget);
        expect(find.text('No active connections'), findsOneWidget);
        expect(find.text('Latest retained output'), findsOneWidget);
        expect(find.text('Exit code 17'), findsOneWidget);
        expect(_action('disconnect', 'running'), findsNothing);
        await tester.tap(_action('reconnect', 'running'));
        expect(actions.reconnected, [same(exited)]);

        tabs.value = [];
        await tester.pump();
        expect(_toggle, findsNothing);
        expect(_clear, findsNothing);
        expect(find.byType(TextButton), findsNothing);

        tabs.value = [
          _tab([history]),
        ];
        await tester.pump();
        expect(find.text('Disconnected (1)'), findsOneWidget);
        expect(_row('history'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'opens the current replacement without changing the retained row target',
      (tester) async {
        final actions = _SessionActions();
        final history = _pane('history', exited: true);
        final live = ValueNotifier(<String, String>{});
        addTearDown(live.dispose);
        await _pumpList(
          tester,
          ValueListenableBuilder<Map<String, String>>(
            valueListenable: live,
            builder: (_, value, _) => actions.list([
              _tab([history]),
            ], liveReconnections: value),
          ),
        );
        await tester.tap(_toggle);
        await tester.pump();
        expect(find.text('Reconnect'), findsOneWidget);

        live.value = {'history': 'replacement'};
        await tester.pump();
        expect(find.text('Reconnect'), findsNothing);
        expect(find.text('Reconnected · Previous output'), findsOneWidget);
        expect(find.text('Open current connection'), findsOneWidget);
        await tester.tap(_action('reconnect', 'history'));
        await tester.tap(_row('history'));
        expect(actions.reconnected, [same(history)]);
        expect(actions.selected, [same(history)]);

        live.value = {};
        await tester.pump();
        expect(find.text('Open current connection'), findsNothing);
        expect(find.text('Reconnect'), findsOneWidget);
      },
    );

    testWidgets(
      'protects referenced output while keeping viewing and reconnect available',
      (tester) async {
        final actions = _SessionActions();
        final running = _pane('running');
        final history = _pane('history', exited: true);
        final protected = ValueNotifier({'running', 'history'});
        addTearDown(protected.dispose);
        await _pumpList(
          tester,
          ValueListenableBuilder<Set<String>>(
            valueListenable: protected,
            builder: (_, value, _) => actions.list([
              _tab([running, history]),
            ], protectedSessionIds: value),
          ),
        );

        await tester.tap(_clear);
        await tester.tap(_action('disconnect', 'running'));
        await tester.tap(_toggle);
        await tester.pump();
        await tester.ensureVisible(_action('remove', 'history'));
        await tester.tap(_action('remove', 'history'));
        expect(actions.clears, 0);
        expect(actions.disconnected, isEmpty);
        expect(actions.removed, isEmpty);
        expect(
          find.text(
            'This record is in use by an AI conversation. '
            'End its current session before removing it.',
          ),
          findsNWidgets(2),
        );
        await tester.tap(_action('reconnect', 'history'));
        await tester.ensureVisible(_row('history'));
        await tester.tap(_row('history'));
        expect(actions.reconnected, [same(history)]);
        expect(actions.selected, [same(history)]);

        protected.value = {};
        await tester.pump();
        await tester.ensureVisible(_action('remove', 'history'));
        await tester.tap(_action('remove', 'history'));
        await tester.ensureVisible(_clear);
        await tester.tap(_clear);
        await tester.ensureVisible(_action('disconnect', 'running'));
        await tester.tap(_action('disconnect', 'running'));
        expect(actions.removed, [same(history)]);
        expect(actions.disconnected, [same(running)]);
        expect(actions.clears, 1);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('uses each tab root pane when no split layout exists', (
      tester,
    ) async {
      final actions = _SessionActions();
      final profile = defaultTerminalProfile();
      await _pumpList(
        tester,
        actions.list([
          TerminalTab(
            sessionId: 'local',
            title: 'Local terminal',
            profileId: profile.id,
            profileSnapshot: profile,
          ),
          const TerminalTab(
            sessionId: 'unknown',
            title: 'Output without its saved profile',
            profileId: 'removed-profile',
            isExited: true,
          ),
        ]),
      );
      expect(find.text('This device'), findsOneWidget);
      await tester.tap(_row('local'));
      expect(actions.selected.single.sessionId, 'local');
      await tester.tap(_toggle);
      await tester.pump();
      expect(find.text('Unknown profile'), findsOneWidget);
      await tester.tap(_row('unknown'));
      expect(actions.selected.last.sessionId, 'unknown');
    });

    for (final brightness in Brightness.values) {
      for (final locale in [const Locale('en'), const Locale('zh')]) {
        testWidgets('keeps actions reachable at 320px in ${brightness.name} '
            'and ${locale.languageCode}', (tester) async {
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final actions = _SessionActions();
          final running = _pane(
            'running-with-an-extremely-long-hostname',
          ).copyWith(title: '一个很长的连接标题 · production / application / region');
          final history = _pane('history', exited: true, exitCode: 255);
          await _pumpList(
            tester,
            actions.list(
              [
                _tab([running, history]),
              ],
              liveReconnections: {'history': 'replacement'},
            ),
            brightness: brightness,
            locale: locale,
          );
          await tester.tap(_action('disconnect', running.sessionId));
          await tester.tap(_toggle);
          await tester.pump();
          await tester.ensureVisible(_action('reconnect', 'history'));
          await tester.tap(_action('reconnect', 'history'));
          await tester.ensureVisible(_action('remove', 'history'));
          await tester.tap(_action('remove', 'history'));
          expect(actions.disconnected, [same(running)]);
          expect(actions.reconnected, [same(history)]);
          expect(actions.removed, [same(history)]);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}

Finder get _toggle =>
    find.byKey(const Key('mobile-sessions-disconnected-toggle'));
Finder get _clear =>
    find.byKey(const Key('mobile-sessions-clear-disconnected'));
Finder _row(String id) => find.byKey(Key('mobile-session-$id'));
Finder _action(String action, String id) =>
    find.byKey(Key('mobile-session-$action-$id'));

Future<void> _pumpList(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('en'),
}) => tester.pumpApp(
  SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
  brightness: brightness,
  locale: locale,
  platform: TargetPlatform.iOS,
);

TerminalPane _pane(String id, {bool exited = false, int? exitCode}) {
  final profile = TerminalProfile(
    id: 'profile-$id',
    name: 'Profile $id',
    shell: '/bin/sh',
    connection: TerminalConnectionConfig.ssh(
      host: '$id.example',
      user: 'user',
      port: 2222,
    ),
  );
  return TerminalPane(
    sessionId: id,
    title: 'Session $id',
    profileId: profile.id,
    profileSnapshot: profile,
    isExited: exited,
    exitCode: exitCode,
  );
}

TerminalTab _tab(List<TerminalPane> panes) => TerminalTab(
  sessionId: panes.first.sessionId,
  title: 'Workspace',
  profileId: panes.first.profileId,
  panes: panes,
);

class _SessionActions {
  final selected = <TerminalPane>[];
  final reconnected = <TerminalPane>[];
  final disconnected = <TerminalPane>[];
  final removed = <TerminalPane>[];
  int clears = 0;

  Widget list(
    List<TerminalTab> tabs, {
    Map<String, String> liveReconnections = const {},
    Set<String> protectedSessionIds = const {},
  }) => MobileSessionList(
    tabs: tabs,
    activeSessionId: tabs.firstOrNull?.activeSessionId,
    liveReconnections: liveReconnections,
    protectedSessionIds: protectedSessionIds,
    onSelect: selected.add,
    onReconnect: reconnected.add,
    onDisconnect: disconnected.add,
    onRemove: removed.add,
    onClearDisconnected: () => clears++,
  );
}
