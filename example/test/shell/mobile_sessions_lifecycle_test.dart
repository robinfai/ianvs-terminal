import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../design/configuration_capture_binding.dart';
import '../design/visual_capture_fonts.dart';
import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';
import '../support/no_io_local_terminal_layout_repository.dart';

const _evidence = String.fromEnvironment('MOBILE_LIFECYCLE_EVIDENCE_DIR');

class _AiStore implements AiConfigurationStore {
  @override
  Future<AiConfiguration?> read() async => null;

  @override
  Future<void> write(AiConfiguration? value) async {}
}

class _SshBackend extends FakePtyBackend {
  final createdSessionIds = <String>[];

  @override
  PtyRuntimeCapabilities get runtimeCapabilities =>
      PtyRuntimeCapabilities.fromJson({
        'schema_version': 1,
        'runtime_contract': 'ianvs-runtime-contract-v1',
        'frame_schema_versions': <String>[],
        'recording_schema_versions': <int>[],
        'features': ['session-config.json.v1', 'ssh-session.v1'],
      });

  @override
  String createSession(String sessionConfigJson) {
    final id = super.createSession(sessionConfigJson);
    createdSessionIds.add(id);
    return id;
  }

  void exitSession(String id, int code) => enqueueEvent(
    id,
    PtyEvent(kind: 'exit', sessionId: id, payload: {'code': code}),
  );
}

class _Fixture {
  const _Fixture(this.container, this.backend, this.profile, this.first);

  final ProviderContainer container;
  final _SshBackend backend;
  final TerminalProfile profile;
  final String first;

  SessionController get controller =>
      container.read(sessionControllerProvider.notifier);
  SessionState get state => container.read(sessionControllerProvider);
  List<TerminalPane> get panes =>
      state.tabs.expand((tab) => tab.effectivePanes).toList();

  Future<String> open(WidgetTester tester) async {
    final id = controller.createSession(profile)!;
    await _settle(tester);
    return id;
  }

  Future<void> exit(WidgetTester tester, String id, {int code = 255}) async {
    backend.exitSession(id, code);
    container.read(terminalRuntimeControllerProvider).refreshSession(id);
    await _settle(tester);
  }
}

Future<void> _settle(WidgetTester tester) async {
  // The production runtime polls continuously, so pump a bounded duration.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<_Fixture> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final backend = _SshBackend();
  final settings = AiSettingsController(_AiStore());
  addTearDown(settings.dispose);
  final profile = TerminalProfile(
    id: 'cloud',
    name: 'Cloud server',
    shell: '',
    appearance: const TerminalDisplayConfig(
      font: TerminalFontConfig(family: 'monospace'),
    ),
    connection: const TerminalConnectionConfig.ssh(
      host: 'cloud.test',
      user: 'fixture',
    ),
  );
  var theme = buildIanvsTerminalTheme(brightness, platform: TargetPlatform.iOS);
  if (_evidence.isNotEmpty) theme = withVisualCaptureFonts(theme);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aiSettingsProvider.overrideWithValue(settings),
        ptySessionBackendProvider.overrideWithValue(backend),
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
        pasteHistoryRepositoryProvider.overrideWithValue(
          MemoryPasteHistoryRepository(),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          noIoLocalTerminalLayoutRepository(),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          noIoLocalSessionRecordingRepository(),
        ),
      ],
      child: RepaintBoundary(
        key: const Key('mobile-lifecycle-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ShellScreen(),
        ),
      ),
    ),
  );
  await _settle(tester);
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ShellScreen)),
  );
  expect(container.read(sessionControllerProvider).isReady, isTrue);
  expect(container.read(sessionControllerProvider).tabs, isEmpty);
  final first = container
      .read(sessionControllerProvider.notifier)
      .createSession(profile)!;
  await _settle(tester);
  expect(find.byKey(const Key('mobile-session-picker')), findsOneWidget);
  return _Fixture(container, backend, profile, first);
}

Finder _key(String value) => find.byKey(Key(value));
Finder get _home => _key('ios-ssh-profile-empty-state');
Finder get _sheet => _key('mobile-sessions-sheet');
Finder _row(String id) => _key('mobile-session-$id');

Future<void> _tap(WidgetTester tester, String key) async {
  final target = _key(key);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await _settle(tester);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // The binding checks foundation globals before package:test tearDown runs.
  debugDefaultTargetPlatformOverride = null;
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (_evidence.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      _key('mobile-lifecycle-capture'),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_evidence).create(recursive: true);
    await File(
      '$_evidence/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  ConfigurationCaptureBinding();
  if (_evidence.isNotEmpty) setUpAll(loadVisualCaptureFonts);
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'returning home preserves live sessions until explicit disconnect',
    (tester) async {
      final fixture = await _pump(tester);
      final id = fixture.first;
      final viewport = fixture.controller.viewportFor(id);
      await _tap(tester, 'mobile-connections-back');

      expect(_home, findsOneWidget);
      expect(_row(id), findsOneWidget);
      expect(fixture.state.activeSessionId, id);
      expect(fixture.backend.closedSessionIds, isEmpty);
      expect(fixture.controller.viewportFor(id), same(viewport));
      await _capture(tester, 'connections-with-live-session');

      await _tap(tester, 'mobile-session-$id');
      expect(_home, findsNothing);
      expect(fixture.state.activeSessionId, id);
      expect(fixture.backend.createdSessionIds, [id]);
      await _tap(tester, 'mobile-connections-back');
      await _tap(tester, 'mobile-session-disconnect-$id');

      expect(fixture.state.tabs, isEmpty);
      expect(fixture.backend.closedSessionIds, [id]);
      expect(_home, findsOneWidget);
      expect(_row(id), findsNothing);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    },
  );

  testWidgets(
    'an open picker regroups a disconnected session and opens read-only output',
    (tester) async {
      final fixture = await _pump(tester);
      final id = fixture.first;
      final live = await fixture.open(tester);
      final viewport = fixture.controller.viewportFor(id);
      await _tap(tester, 'mobile-session-picker');
      expect(_row(id), findsOneWidget);
      expect(_row(live), findsOneWidget);

      await fixture.exit(tester, id);
      expect(_sheet, findsOneWidget);
      expect(_row(id), findsNothing);
      expect(_row(live), findsOneWidget);
      expect(
        tester.widget<Text>(_key('mobile-sessions-active-heading')).data,
        endsWith('(1)'),
      );
      await _tap(tester, 'mobile-sessions-disconnected-toggle');
      expect(_row(id), findsOneWidget);
      expect(_key('mobile-session-disconnect-$id'), findsNothing);
      expect(_key('mobile-session-reconnect-$id'), findsOneWidget);
      await _capture(tester, 'picker-after-live-disconnect');
      await _tap(tester, 'mobile-session-$id');

      expect(_sheet, findsNothing);
      expect(fixture.state.activeSessionId, id);
      expect(_key('mobile-disconnected-notice-$id'), findsOneWidget);
      expect(find.text('Connection ended'), findsOneWidget);
      final terminal = tester.widget<TerminalViewport>(
        find.byType(TerminalViewport),
      );
      expect(terminal.readOnly, isTrue);
      expect(terminal.controller, same(viewport));
      final keyboard = tester.widget<TextButton>(_key('mobile-show-keyboard'));
      expect(keyboard.onPressed, isNull);
      final writes = fixture.backend.writes.length;
      terminal.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await _settle(tester);
      expect(fixture.backend.writes, hasLength(writes));
      expect(fixture.backend.closedSessionIds, isEmpty);
      await _capture(tester, 'disconnected-read-only-output');
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    },
  );

  testWidgets('ordinary exit zero removes the session and returns home', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    await fixture.exit(tester, fixture.first, code: 0);

    expect(fixture.state.tabs, isEmpty);
    expect(fixture.state.activeSessionId, isNull);
    expect(fixture.backend.closedSessionIds, contains(fixture.first));
    expect(_home, findsOneWidget);
    expect(_key('mobile-sessions-disconnected-toggle'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  for (final scene in [
    (
      name: 'landscape with closing keyboard',
      capture: 'landscape-keyboard',
      size: const Size(844, 390),
      keyboard: 180.0,
      brightness: Brightness.light,
    ),
    (
      name: 'narrow dark portrait',
      capture: 'narrow-dark',
      size: const Size(320, 693),
      keyboard: 0.0,
      brightness: Brightness.dark,
    ),
  ]) {
    testWidgets('disconnected output remains usable in ${scene.name}', (
      tester,
    ) async {
      final fixture = await _pump(
        tester,
        size: scene.size,
        brightness: scene.brightness,
      );
      tester.view.viewInsets = FakeViewPadding(bottom: scene.keyboard);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await fixture.exit(tester, fixture.first);
      await _capture(tester, '${scene.capture}-disconnected');

      expect(tester.takeException(), isNull);
      expect(
        _key('mobile-disconnected-notice-${fixture.first}'),
        findsOneWidget,
      );
      expect(
        tester.widget<TerminalViewport>(find.byType(TerminalViewport)).readOnly,
        isTrue,
      );
      if (scene.keyboard > 0) {
        expect(_key('mobile-show-keyboard'), findsNothing);
        tester.view.viewInsets = FakeViewPadding.zero;
        await _settle(tester);
        expect(tester.takeException(), isNull);
        expect(_key('mobile-show-keyboard'), findsNothing);
        tester.view.physicalSize = const Size(390, 844);
        await _settle(tester);
        expect(tester.takeException(), isNull);
        expect(
          tester
              .widget<TerminalViewport>(find.byType(TerminalViewport))
              .readOnly,
          isTrue,
        );
        expect(
          tester.widget<TextButton>(_key('mobile-show-keyboard')).onPressed,
          isNull,
        );
        expect(
          find.text(
            'Output is read-only and stays available until you remove this record or quit the app.',
          ),
          findsOneWidget,
        );
        await _capture(tester, '${scene.capture}-rotated-portrait');
        tester.view.physicalSize = scene.size;
        tester.view.viewInsets = FakeViewPadding(bottom: scene.keyboard);
        await _settle(tester);
        expect(tester.takeException(), isNull);
        expect(_key('mobile-show-keyboard'), findsNothing);
      } else {
        expect(
          tester.widget<TextButton>(_key('mobile-show-keyboard')).onPressed,
          isNull,
        );
      }
      final reconnect = _key('mobile-disconnected-reconnect-${fixture.first}');
      await tester.ensureVisible(reconnect);
      await _settle(tester);
      expect(reconnect.hitTestable(), findsOneWidget);
      await tester.tap(reconnect);
      await _settle(tester);
      expect(fixture.backend.createdSessionIds, hasLength(2));
      expect(fixture.state.activeSessionId, isNot(fixture.first));

      tester.view.viewInsets = FakeViewPadding.zero;
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<TerminalViewport>(find.byType(TerminalViewport)).readOnly,
        isFalse,
      );
      expect(
        tester.widget<TextButton>(_key('mobile-show-keyboard')).onPressed,
        isNotNull,
      );
      await _capture(tester, '${scene.capture}-reconnected');
      await _unmount(tester);
    });
  }

  testWidgets('removing two disconnected records keeps the picker open', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    await fixture.exit(tester, fixture.first);
    final second = await fixture.open(tester);
    await fixture.exit(tester, second);
    final live = await fixture.open(tester);
    await _tap(tester, 'mobile-session-picker');
    await _tap(tester, 'mobile-sessions-disconnected-toggle');

    for (final id in [fixture.first, second]) {
      await _tap(tester, 'mobile-session-remove-$id');
      expect(_sheet, findsOneWidget);
      expect(_row(id), findsNothing);
      expect(_row(live), findsOneWidget);
    }
    expect(fixture.panes.map((pane) => pane.sessionId), [live]);
    expect(fixture.backend.closedSessionIds, [fixture.first, second]);
    expect(_key('mobile-sessions-disconnected-toggle'), findsNothing);
    await _capture(tester, 'picker-after-record-removal');
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets(
    'bulk cleanup removes only exited records and preserves a live session',
    (tester) async {
      final fixture = await _pump(tester);
      await fixture.exit(tester, fixture.first);
      final second = await fixture.open(tester);
      await fixture.exit(tester, second);
      final live = await fixture.open(tester);
      final viewport = fixture.controller.viewportFor(live);
      await _tap(tester, 'mobile-connections-back');
      await _tap(tester, 'mobile-sessions-clear-disconnected');

      expect(fixture.panes.map((pane) => pane.sessionId), [live]);
      expect(
        fixture.backend.closedSessionIds,
        unorderedEquals([fixture.first, second]),
      );
      expect(fixture.controller.viewportFor(live), same(viewport));
      expect(fixture.backend.createdSessionIds, [fixture.first, second, live]);
      expect(_home, findsOneWidget);
      expect(_row(live), findsOneWidget);
      expect(_key('mobile-sessions-disconnected-toggle'), findsNothing);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    },
  );

  testWidgets('removing the last diagnostic from the more menu returns home', (
    tester,
  ) async {
    final fixture = await _pump(tester);
    await fixture.exit(tester, fixture.first);
    expect(_key('shell-runtime-error'), findsOneWidget);
    await _tap(tester, 'shell-chrome-menu');
    expect(_key('mobile-session-menu-reconnect'), findsOneWidget);
    await _tap(tester, 'mobile-session-menu-close');

    expect(fixture.state.tabs, isEmpty);
    expect(fixture.state.activeSessionId, isNull);
    expect(fixture.state.lastError, isNull);
    expect(_key('shell-runtime-error'), findsNothing);
    expect(_home, findsOneWidget);
    expect(_key('mobile-disconnected-notice-${fixture.first}'), findsNothing);
    expect(fixture.backend.closedSessionIds, [fixture.first]);
    await _capture(tester, 'connections-after-last-record-removal');
    await _unmount(tester);
  });

  testWidgets(
    'home and more menu reconnect and disconnect the selected session',
    (tester) async {
      final fixture = await _pump(tester);
      final first = fixture.first;
      await fixture.exit(tester, first);
      await _tap(tester, 'mobile-connections-back');
      await _tap(tester, 'mobile-sessions-disconnected-toggle');
      await _tap(tester, 'mobile-session-reconnect-$first');
      final second = fixture.state.activeSessionId!;

      expect(second, isNot(first));
      expect(_home, findsNothing);
      expect(_key('mobile-disconnected-notice-$second'), findsNothing);
      expect(fixture.backend.createdSessionIds, [first, second]);
      await _tap(tester, 'shell-chrome-menu');
      expect(_key('mobile-session-menu-reconnect'), findsNothing);
      expect(_key('mobile-session-menu-close'), findsOneWidget);
      await _capture(tester, 'live-session-more-menu');
      await _tap(tester, 'mobile-session-menu-close');

      expect(fixture.backend.closedSessionIds, [second]);
      expect(fixture.state.activeSessionId, first);
      expect(_key('mobile-disconnected-notice-$first'), findsOneWidget);
      await _tap(tester, 'shell-chrome-menu');
      await _tap(tester, 'mobile-session-menu-reconnect');
      final third = fixture.state.activeSessionId!;
      expect(third, isNot(isIn([first, second])));
      expect(fixture.backend.createdSessionIds, [first, second, third]);
      expect(fixture.state.reconnectionTargets, {first: third});
      expect(
        fixture.panes.where((pane) => !pane.isExited).single.sessionId,
        third,
      );
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    },
  );
}
