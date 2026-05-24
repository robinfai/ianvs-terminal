import 'dart:convert';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_pty/flutterm_pty.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/preferences/app_preferences_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_ports.dart';
import 'package:app/features/sessions/session_state.dart';

import '../support/fake_pty_backend.dart';

class _TestProfileRepository extends ProfileRepository {
  _TestProfileRepository(this._document);

  TerminalProfilesDocument _document;
  final List<TerminalProfilesDocument> savedDocuments = [];

  @override
  Future<TerminalProfilesDocument> load() async => _document;

  @override
  Future<void> save(TerminalProfilesDocument document) async {
    savedDocuments.add(document);
    _document = document;
  }
}

class _TestSessionController extends SessionController {
  @override
  SessionState build() {
    return SessionState.initial();
  }
}

class _BootstrapOverrideSessionController extends SessionController {
  _BootstrapOverrideSessionController(this.profileId);

  final String profileId;

  @override
  String? get bootstrapDefaultProfileIdOverride => profileId;
}

class _TestAppPreferencesRepository extends AppPreferencesRepository {
  _TestAppPreferencesRepository(this._document);

  TerminalAppPreferencesDocument? _document;
  final List<TerminalAppPreferencesDocument> savedDocuments = [];

  @override
  Future<TerminalAppPreferencesDocument?> load() async => _document;

  @override
  Future<void> save(TerminalAppPreferencesDocument document) async {
    savedDocuments.add(document);
    _document = document;
  }
}

class _EventfulPtyBackend
    implements PtySessionBackend, PtySessionJsonRequestBackend {
  _EventfulPtyBackend(this._delegate);

  final FakePtyBackend _delegate;

  void enqueueEvent(String sessionId, Map<String, Object?> event) {
    _delegate.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: event['kind']! as String,
        sessionId: sessionId,
        payload: (event['payload'] as Map?)?.cast<String, Object?>(),
      ),
    );
  }

  void enqueueExit(String sessionId, {int? code}) {
    enqueueEvent(sessionId, {
      'kind': 'exit',
      'session_id': int.parse(sessionId),
      'payload': code == null ? null : {'code': code},
    });
  }

  @override
  int ping() => _delegate.ping();

  @override
  String createSession(String sessionConfigJson) =>
      _delegate.createSession(sessionConfigJson);

  @override
  void closeSession(String sessionId) => _delegate.closeSession(sessionId);

  @override
  List<PtyEvent> pollEvents(String sessionId) =>
      _delegate.pollEvents(sessionId);

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
  }) => _delegate.resizeSession(
    sessionId,
    cols: cols,
    rows: rows,
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight,
  );

  @override
  void scrollViewport(String sessionId, int deltaLines) =>
      _delegate.scrollViewport(sessionId, deltaLines);

  @override
  void scrollViewportTo(String sessionId, int offset) =>
      _delegate.scrollViewportTo(sessionId, offset);

  @override
  void writeInput(String sessionId, List<int> bytes) =>
      _delegate.writeInput(sessionId, bytes);

  @override
  String? requestSessionJson(String sessionId, String requestJson) =>
      _delegate.requestSessionJson(sessionId, requestJson);

  @override
  String? takeFrameDiffJson(String sessionId) =>
      _delegate.takeFrameDiffJson(sessionId);
}

class _CountingPtyBackend extends FakePtyBackend {
  int takeFrameDiffCalls = 0;
  int pollEventsCalls = 0;

  @override
  String? takeFrameDiffJson(String sessionId) {
    takeFrameDiffCalls += 1;
    return super.takeFrameDiffJson(sessionId);
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    pollEventsCalls += 1;
    return super.pollEvents(sessionId);
  }
}

class _DelayedFramePtyBackend extends _CountingPtyBackend {
  _DelayedFramePtyBackend({this.revealOnRead = 3});

  final int revealOnRead;

  @override
  String createSession(String sessionConfigJson) {
    final sessionId = super.createSession(sessionConfigJson);
    setFrame(sessionId, {
      'rows': [
        {'index': 0, 'text': '', 'style_runs': const []},
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });
    return sessionId;
  }

  @override
  String? takeFrameDiffJson(String sessionId) {
    final frameJson = super.takeFrameDiffJson(sessionId);
    final reads = takeFrameDiffCalls;
    if (reads < revealOnRead) {
      setFrame(sessionId, {
        'rows': [
          {'index': 0, 'text': '', 'style_runs': const []},
        ],
        'cursor': {'row': 0, 'col': 0, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 0, 'end': 1},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });
    } else {
      setFrame(sessionId, {
        'rows': [
          {'index': 0, 'text': 'driver ready', 'style_runs': const []},
        ],
        'cursor': {'row': 0, 'col': 0, 'visible': true},
        'selection': null,
        'viewport_rows': 24,
        'viewport_cols': 80,
        'dirty_ranges': [
          {'start': 0, 'end': 1},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });
    }
    return frameJson;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final defaultProfile = TerminalProfile(
    id: 'default',
    name: 'Local Shell',
    shell: '/bin/zsh',
  );
  final sshProfile = TerminalProfile(
    id: 'ssh',
    name: 'SSH',
    shell: '/usr/bin/ssh',
  );

  test('session lifecycle updates tabs and active session', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);

    expect(container.read(sessionControllerProvider).tabs, isEmpty);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    expect(container.read(sessionControllerProvider).tabs, hasLength(1));
    final first = container.read(sessionControllerProvider).activeSessionId;
    expect(first, isNotNull);

    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-2'));
    expect(container.read(sessionControllerProvider).tabs, hasLength(2));
    final second = container.read(sessionControllerProvider).activeSessionId;
    expect(second, isNotNull);
    expect(second, isNot(equals(first)));

    controller.activateSession(first!);
    expect(container.read(sessionControllerProvider).activeSessionId, first);

    controller.closeSession(first);
    final afterCloseFirst = container.read(sessionControllerProvider);
    expect(afterCloseFirst.tabs, hasLength(1));
    expect(afterCloseFirst.activeSessionId, second);

    controller.closeSession(second!);
    final afterCloseSecond = container.read(sessionControllerProvider);
    expect(afterCloseSecond.tabs, isEmpty);
    expect(afterCloseSecond.activeSessionId, isNull);
  });

  test('reorderTab moves tabs without changing the active session', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-2'));
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-3'));

    final initialTabs = container.read(sessionControllerProvider).tabs;
    final first = initialTabs[0].sessionId;
    final second = initialTabs[1].sessionId;
    final third = initialTabs[2].sessionId;

    controller.activateSession(second);
    controller.reorderTab(oldIndex: 0, newIndex: 2);

    var state = container.read(sessionControllerProvider);
    expect(state.tabs.map((tab) => tab.sessionId), [second, third, first]);
    expect(state.activeSessionId, second);

    controller.reorderTab(oldIndex: 2, newIndex: 0);
    state = container.read(sessionControllerProvider);
    expect(state.tabs.map((tab) => tab.sessionId), [first, second, third]);
    expect(state.activeSessionId, second);

    controller.reorderTab(oldIndex: -1, newIndex: 2);
    expect(
      container
          .read(sessionControllerProvider)
          .tabs
          .map((tab) => tab.sessionId),
      [first, second, third],
    );
  });

  test('xterm sessions advertise 24-bit color support', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);

    controller.createSession(defaultTerminalProfile().copyWith(id: 'xterm'));

    expect(coreClient.lastCreatedSessionPayload!['launch'], {
      'program': defaultTerminalProfile().shell,
      'args': defaultTerminalProfile().args,
      'env': {'TERM': 'xterm-256color', 'COLORTERM': 'truecolor'},
      'cwd': defaultTerminalProfile().cwd,
    });
    expect(
      container
          .read(sessionControllerProvider)
          .tabs
          .single
          .profileSnapshot!
          .env,
      {'TERM': 'xterm-256color', 'COLORTERM': 'truecolor'},
    );
  });

  test('vt220 sessions keep a conservative terminal environment', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);

    controller.createSession(vt220TerminalProfile().copyWith(id: 'vt220'));

    expect(coreClient.lastCreatedSessionPayload!['launch'], {
      'program': vt220TerminalProfile().shell,
      'args': vt220TerminalProfile().args,
      'env': {'TERM': 'vt220'},
      'cwd': vt220TerminalProfile().cwd,
    });
  });

  test('closing inactive session keeps current active session', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);

    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final first = container.read(sessionControllerProvider).activeSessionId!;
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-2'));
    final second = container
        .read(sessionControllerProvider)
        .tabs
        .last
        .sessionId;
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-3'));
    final third = container.read(sessionControllerProvider).activeSessionId!;

    expect(third, isNotNull);
    expect(third, isNot(equals(first)));
    expect(third, isNot(equals(second)));

    controller.activateSession(first);
    expect(container.read(sessionControllerProvider).activeSessionId, first);

    controller.closeSession(second);
    final afterCloseInactive = container.read(sessionControllerProvider);
    expect(afterCloseInactive.tabs, hasLength(2));
    expect(
      afterCloseInactive.tabs.any((tab) => tab.sessionId == second),
      isFalse,
    );
    expect(afterCloseInactive.activeSessionId, first);
  });

  test('splitActiveSession adds panes inside the active tab', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile().copyWith(id: 'shell-1');

    controller.createSession(profile);
    final firstSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);

    final splitState = container.read(sessionControllerProvider);
    expect(splitState.tabs, hasLength(1));
    expect(splitState.tabs.single.effectivePanes, hasLength(2));
    expect(splitState.tabs.single.splitAxis, TerminalSplitAxis.horizontal);
    expect(splitState.activeSessionId, isNot(firstSessionId));
    expect(splitState.tabs.single.containsSession(firstSessionId), isTrue);
    expect(
      splitState.tabs.single.containsSession(splitState.activeSessionId!),
      isTrue,
    );
    expect(coreClient.lastCreatedSessionPayload!['launch'], {
      'program': profile.shell,
      'args': profile.args,
      'env': {'TERM': 'xterm-256color', 'COLORTERM': 'truecolor'},
      'cwd': profile.cwd,
    });

    final secondSessionId = splitState.activeSessionId!;
    controller.activateSession(firstSessionId);
    expect(
      container.read(sessionControllerProvider).activeSessionId,
      firstSessionId,
    );

    controller.closeSession(firstSessionId);
    final afterCloseFirst = container.read(sessionControllerProvider);
    expect(afterCloseFirst.tabs, hasLength(1));
    expect(afterCloseFirst.tabs.single.effectivePanes, hasLength(1));
    expect(afterCloseFirst.activeSessionId, secondSessionId);

    controller.closeSession(secondSessionId);
    final afterCloseSecond = container.read(sessionControllerProvider);
    expect(afterCloseSecond.tabs, isEmpty);
    expect(afterCloseSecond.activeSessionId, isNull);
  });

  test('splitActiveSession supports nested mixed directions', () {
    final coreClient = FakePtyBackend();
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    final profile = defaultTerminalProfile().copyWith(id: 'shell-1');

    controller.createSession(profile);
    final firstSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    controller.splitActiveSession(profile, TerminalSplitAxis.horizontal);
    final secondSessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    controller.splitActiveSession(profile, TerminalSplitAxis.vertical);

    final splitState = container.read(sessionControllerProvider);
    final tab = splitState.tabs.single;
    expect(tab.effectivePanes, hasLength(3));
    expect(tab.effectivePaneLayout.splitAxis, TerminalSplitAxis.horizontal);
    expect(
      tab.effectivePaneLayout.second!.splitAxis,
      TerminalSplitAxis.vertical,
    );
    expect(tab.containsSession(firstSessionId), isTrue);
    expect(tab.containsSession(secondSessionId), isTrue);
    expect(splitState.activeSessionId, isNot(firstSessionId));
    expect(splitState.activeSessionId, isNot(secondSessionId));

    controller.closeSession(secondSessionId);
    final afterCloseNestedPane = container.read(sessionControllerProvider);
    expect(afterCloseNestedPane.tabs.single.effectivePanes, hasLength(2));
    expect(
      afterCloseNestedPane.tabs.single.effectivePaneLayout.splitAxis,
      TerminalSplitAxis.horizontal,
    );
  });

  test('resizeActiveSession dedupes identical size requests', () {
    final coreBindings = FakePtyBackend();
    final coreClient = coreBindings;
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    controller.resizeActiveSession(const Size(640, 480), 2.0);
    expect(coreBindings.resizeCalls, hasLength(1));
    expect(
      coreBindings.resizeCalls.single,
      [int.parse(sessionId), 71, 26, 1280, 960],
      reason:
          'falls back to the default cell size before viewport metrics exist',
    );

    controller.resizeActiveSession(const Size(640, 480), 2.0);
    expect(
      coreBindings.resizeCalls,
      hasLength(1),
      reason: 'duplicate call skipped',
    );

    controller.resizeActiveSession(const Size(644, 480), 2.0);
    expect(
      coreBindings.resizeCalls,
      hasLength(2),
      reason: 'pixel-only viewport changes still update native pixel size',
    );
    expect(coreBindings.resizeCalls.last, [
      int.parse(sessionId),
      71,
      26,
      1288,
      960,
    ]);

    controller.resizeActiveSession(const Size(644, 480), 2.0);
    expect(
      coreBindings.resizeCalls,
      hasLength(2),
      reason: 'full metric duplicate skipped',
    );

    controller.resizeActiveSession(const Size(650, 480), 2.0);
    expect(coreBindings.resizeCalls, hasLength(3));

    final last = coreBindings.resizeCalls.last;
    expect(last[0], equals(int.parse(sessionId)));
    expect(last[1], greaterThan(0));
    expect(last[2], greaterThan(0));
    expect(last[3], greaterThan(0));
    expect(last[4], greaterThan(0));
  });

  test('resizeActiveSession uses the provided inner viewport size as-is', () {
    final coreBindings = FakePtyBackend();
    final coreClient = coreBindings;
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    controller.resizeActiveSession(const Size(1540, 1106), 2.0);

    expect(coreBindings.resizeCalls.single, [
      int.parse(sessionId),
      171,
      61,
      3080,
      2212,
    ]);
  });

  test(
    'resizeActiveSession prefers measured viewport cell size when available',
    () {
      final coreBindings = FakePtyBackend();
      final coreClient = coreBindings;
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-1'),
      );
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      controller
          .viewportFor(sessionId)
          .updateMeasuredCellSize(const Size(10, 20));

      controller.resizeActiveSession(const Size(640, 480), 2.0);

      expect(coreBindings.resizeCalls, hasLength(1));
      expect(coreBindings.resizeCalls.single, [
        int.parse(sessionId),
        64,
        24,
        1280,
        960,
      ]);
    },
  );

  test('refreshing a session applies OSC window titles to the tab title', () {
    final coreBindings = FakePtyBackend();
    final coreClient = coreBindings;
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    coreBindings.setFrame(int.parse(sessionId), {
      'rows': [
        {'index': 0, 'text': 'flutterm ready', 'style_runs': const []},
      ],
      'cursor': {'row': 0, 'col': 4, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'window_title': 'Build Target',
    });

    controller.resizeActiveSession(const Size(640, 480), 1.0);

    expect(
      container.read(sessionControllerProvider).tabs.single.title,
      'Build Target',
    );
  });

  test('refreshing a session falls back to OSC icon names with UTF-8 text', () {
    final coreBindings = FakePtyBackend();
    final coreClient = coreBindings;
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    coreBindings.setFrame(int.parse(sessionId), {
      'rows': [
        {'index': 0, 'text': 'flutterm ready', 'style_runs': const []},
      ],
      'cursor': {'row': 0, 'col': 4, 'visible': true},
      'selection': null,
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'window_title': null,
      'window_icon_name': '构建目标',
    });

    controller.resizeActiveSession(const Size(640, 480), 1.0);

    expect(container.read(sessionControllerProvider).tabs.single.title, '构建目标');
  });

  testWidgets(
    'shell hook metadata updates per-session shell integration state',
    (tester) async {
      final bindings = _EventfulPtyBackend(FakePtyBackend());
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(bindings),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-1'),
      );
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      await tester.pump();

      bindings.enqueueEvent(sessionId, {
        'kind': 'shell_hook',
        'payload': const <String, Object?>{
          'hook': 'command_finished',
          'command': 'git status',
          'pwd': '/tmp/project',
          'shell': 'zsh',
          'host': 'workstation.local',
          'user': 'dev',
          'exit_code': 0,
          'prompt_scrollback_offset': 12,
        },
      });
      bindings.enqueueEvent(sessionId, {
        'kind': 'shell_hook',
        'payload': const <String, Object?>{
          'hook': 'command_finished',
          'command': 'dart test',
          'cwd': '/tmp/project',
          'prompt_scrollback_offset': 36,
        },
      });

      container
          .read(terminalRuntimeControllerProvider)
          .refreshSession(sessionId);
      await tester.pump();

      final shellIntegration = container
          .read(sessionControllerProvider)
          .tabs
          .single
          .activePane
          .shellIntegration;
      expect(shellIntegration.currentDirectory, '/tmp/project');
      expect(shellIntegration.shell, 'zsh');
      expect(shellIntegration.hostname, 'workstation.local');
      expect(shellIntegration.username, 'dev');
      expect(shellIntegration.lastCommand, 'dart test');
      expect(shellIntegration.lastExitCode, 0);
      expect(shellIntegration.recentCommands, <String>[
        'dart test',
        'git status',
      ]);
      expect(shellIntegration.recentDirectories, <String>['/tmp/project']);
      expect(
        shellIntegration.promptMarks
            .map((mark) => mark.scrollbackOffset)
            .toList(),
        <int>[12, 36],
      );
    },
  );

  testWidgets('shell hook metadata switches to a matching profile', (
    tester,
  ) async {
    final defaultProfile = defaultTerminalProfile().copyWith(
      id: 'local',
      name: 'Local',
    );
    final rootProfile = defaultTerminalProfile().copyWith(
      id: 'root',
      name: 'Root Session',
      switchRules: const [
        TerminalProfileSwitchRule(
          kind: TerminalProfileSwitchRuleKind.username,
          pattern: 'root',
        ),
      ],
    );
    final bindings = _EventfulPtyBackend(FakePtyBackend());
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(bindings),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [defaultProfile, rootProfile]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider);
    await tester.pump();
    await tester.pump();
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    bindings.enqueueEvent(sessionId, {
      'kind': 'shell_hook',
      'payload': const <String, Object?>{
        'hook': 'command_finished',
        'command': 'sudo -s',
        'user': 'root',
        'pwd': '/root',
      },
    });
    container.read(terminalRuntimeControllerProvider).refreshSession(sessionId);
    await tester.pump();

    final pane = container
        .read(sessionControllerProvider)
        .tabs
        .single
        .activePane;
    expect(pane.profileId, 'root');
    expect(pane.title, 'Root Session');
    expect(pane.profileSnapshot?.name, 'Root Session');
    expect(pane.shellIntegration.username, 'root');
  });

  testWidgets('automatic profile switching restores the baseline profile', (
    tester,
  ) async {
    final defaultProfile = defaultTerminalProfile().copyWith(
      id: 'local',
      name: 'Local',
    );
    final rootProfile = defaultTerminalProfile().copyWith(
      id: 'root',
      name: 'Root Session',
      switchRules: const [
        TerminalProfileSwitchRule(
          kind: TerminalProfileSwitchRuleKind.username,
          pattern: 'root',
        ),
      ],
    );
    final bindings = _EventfulPtyBackend(FakePtyBackend());
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(bindings),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [defaultProfile, rootProfile]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider);
    await tester.pump();
    await tester.pump();
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;

    bindings.enqueueEvent(sessionId, {
      'kind': 'shell_hook',
      'payload': const <String, Object?>{
        'hook': 'command_finished',
        'command': 'sudo -s',
        'user': 'root',
        'pwd': '/root',
      },
    });
    container.read(terminalRuntimeControllerProvider).refreshSession(sessionId);
    await tester.pump();

    expect(
      container
          .read(sessionControllerProvider)
          .tabs
          .single
          .activePane
          .profileId,
      'root',
    );

    bindings.enqueueEvent(sessionId, {
      'kind': 'shell_hook',
      'payload': const <String, Object?>{
        'hook': 'command_finished',
        'command': 'exit',
        'user': 'dev',
        'pwd': '/Users/dev',
      },
    });
    container.read(terminalRuntimeControllerProvider).refreshSession(sessionId);
    await tester.pump();

    final pane = container
        .read(sessionControllerProvider)
        .tabs
        .single
        .activePane;
    expect(pane.profileId, 'local');
    expect(pane.title, 'Local');
    expect(pane.profileSnapshot?.name, 'Local');
    expect(pane.shellIntegration.username, 'dev');
  });

  test(
    'resize events update the terminal session before resizing the macOS window',
    () async {
      final bindings = _EventfulPtyBackend(FakePtyBackend());
      final coreClient = bindings;
      double? windowWidthDelta;
      double? windowHeightDelta;

      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          sessionWindowResizeProvider.overrideWithValue(({
            required heightDelta,
            required widthDelta,
          }) async {
            windowWidthDelta = widthDelta;
            windowHeightDelta = heightDelta;
          }),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-1'),
      );
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      bindings.enqueueEvent(sessionId, {
        'kind': 'resize',
        'session_id': int.parse(sessionId),
        'payload': {'rows': 30, 'cols': 100},
      });

      controller.resizeActiveSession(const Size(640, 480), 1.0);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bindings._delegate.resizeCalls, hasLength(2));
      expect(bindings._delegate.resizeCalls.last, [
        int.parse(sessionId),
        100,
        30,
        900,
        540,
      ]);
      expect(windowWidthDelta, 260.0);
      expect(windowHeightDelta, 60.0);
    },
  );

  test(
    'resize events honor measured cell size before resizing the macOS window',
    () async {
      final bindings = _EventfulPtyBackend(FakePtyBackend());
      final coreClient = bindings;
      double? windowWidthDelta;
      double? windowHeightDelta;

      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          sessionWindowResizeProvider.overrideWithValue(({
            required heightDelta,
            required widthDelta,
          }) async {
            windowWidthDelta = widthDelta;
            windowHeightDelta = heightDelta;
          }),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-1'),
      );
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;
      controller
          .viewportFor(sessionId)
          .updateMeasuredCellSize(const Size(10, 20));
      bindings.enqueueEvent(sessionId, {
        'kind': 'resize',
        'session_id': int.parse(sessionId),
        'payload': {'rows': 30, 'cols': 100},
      });

      controller.resizeActiveSession(const Size(640, 480), 1.0);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bindings._delegate.resizeCalls, hasLength(2));
      expect(bindings._delegate.resizeCalls.last, [
        int.parse(sessionId),
        100,
        30,
        1000,
        600,
      ]);
      expect(windowWidthDelta, 360.0);
      expect(windowHeightDelta, 120.0);
    },
  );

  test('OSC 52 copy events decode UTF-8 clipboard text', () async {
    final bindings = _EventfulPtyBackend(FakePtyBackend());
    final coreClient = bindings;
    String copied = '';

    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionClipboardCopyProvider.overrideWithValue((text) async {
          copied = text;
        }),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    bindings.enqueueEvent(sessionId, {
      'kind': 'clipboard_copy',
      'session_id': int.parse(sessionId),
      'payload': {
        'selection': 'c',
        'data': base64.encode(utf8.encode('复制内容🌟')),
      },
    });

    controller.resizeActiveSession(const Size(640, 480), 1.0);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(copied, '复制内容🌟');
  });

  test('OSC 52 paste requests reply with UTF-8 clipboard content', () async {
    final fakeBindings = FakePtyBackend();
    final bindings = _EventfulPtyBackend(fakeBindings);
    final coreClient = bindings;

    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        sessionClipboardPasteProvider.overrideWithValue(() async => '你好, 世界🌟'),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(sessionControllerProvider.notifier);
    controller.createSession(defaultTerminalProfile().copyWith(id: 'shell-1'));
    final sessionId = container
        .read(sessionControllerProvider)
        .activeSessionId!;
    bindings.enqueueEvent(sessionId, {
      'kind': 'clipboard_paste_request',
      'session_id': int.parse(sessionId),
      'payload': {'selection': 'c'},
    });

    controller.resizeActiveSession(const Size(640, 480), 1.0);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final expectedPayload = base64.encode(utf8.encode('你好, 世界🌟'));
    expect(
      fakeBindings.writes.last,
      utf8.encode('\x1B]52;c;$expectedPayload\x07'),
    );
  });

  test(
    'bootstrap prefers explicit override over persisted and legacy defaults',
    () async {
      final coreClient = FakePtyBackend();
      final profileRepository = _TestProfileRepository(
        TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
      );
      final preferencesRepository = _TestAppPreferencesRepository(
        const TerminalAppPreferencesDocument(
          defaults: TerminalAppDefaults(defaultProfileId: 'default'),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(profileRepository),
          appPreferencesRepositoryProvider.overrideWithValue(
            preferencesRepository,
          ),
          sessionControllerProvider.overrideWith(
            () => _BootstrapOverrideSessionController('ssh'),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(sessionControllerProvider);
      expect(state.defaultProfileId, 'ssh');
      expect(state.tabs.single.profileId, 'ssh');
      expect(preferencesRepository.savedDocuments, isEmpty);
    },
  );

  test('bootstrap publishes ready state with the initial session', () async {
    final coreClient = FakePtyBackend();
    final profileRepository = _TestProfileRepository(
      TerminalProfilesDocument(profiles: [defaultProfile]),
    );
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        profileRepositoryProvider.overrideWithValue(profileRepository),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    final states = <SessionState>[];
    container.listen<SessionState>(
      sessionControllerProvider,
      (_, next) => states.add(next),
    );
    container.read(sessionControllerProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(states.any((state) => state.isReady), isTrue);
    expect(
      states.where((state) => state.isReady),
      everyElement(
        isA<SessionState>()
            .having((state) => state.tabs, 'tabs', isNotEmpty)
            .having(
              (state) => state.activeSessionId,
              'activeSessionId',
              isNotNull,
            ),
      ),
    );
  });

  test(
    'bootstrap surfaces configuration warnings and starts sessions from recovered values',
    () async {
      final coreBindings = FakePtyBackend();
      final coreClient = coreBindings;
      final invalidDocument = TerminalProfilesDocument.fromJson({
        'schemaVersion': 2,
        'profiles': [
          {
            'id': 'default',
            'name': 'Local Shell',
            'launch': {
              'program': '',
              'args': const ['-l', 2],
              'env': const {'TERM_PROGRAM': 'flutterm', 'BAD': false},
              'cwd': null,
            },
            'terminal': {'emulation': 'ansi', 'scrollbackLines': -1},
            'appearance': {
              'font': {
                'family': 'Menlo',
                'fallback': const ['Monaco'],
              },
            },
          },
        ],
      });
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(invalidDocument),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final state = container.read(sessionControllerProvider);
      expect(state.configurationWarnings, isNotEmpty);
      expect(
        state.configurationWarnings.map((warning) => warning.path),
        containsAll(<String>[
          'launch.program',
          'launch.args[1]',
          'launch.env.BAD',
          'terminal.emulation',
          'terminal.scrollbackLines',
        ]),
      );
      expect(coreBindings.lastCreatedSessionPayload, isNotNull);
      expect(coreBindings.lastCreatedSessionPayload!['launch'], {
        'program': defaultTerminalProfile().shell,
        'args': const ['-l'],
        'env': const {
          'TERM': 'xterm-256color',
          'COLORTERM': 'truecolor',
          'TERM_PROGRAM': 'flutterm',
        },
        'cwd': null,
      });
      expect(coreBindings.lastCreatedSessionPayload!['terminal'], {
        'emulation': 'xterm256',
        'scrollbackLines': 8000,
      });
    },
  );

  test('driver-friendly mode avoids the periodic session polling loop', () async {
    final coreBindings = _CountingPtyBackend();
    final coreClient = coreBindings;
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            TerminalProfilesDocument(profiles: [defaultProfile]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(null),
        ),
        sessionPollingEnabledProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(container.read(sessionControllerProvider).tabs, hasLength(1));
    expect(
      coreBindings.takeFrameDiffCalls,
      lessThanOrEqualTo(1),
      reason:
          'driver mode should not keep scheduling frame-sync-hostile polling',
    );
    expect(
      coreBindings.pollEventsCalls,
      lessThanOrEqualTo(1),
      reason:
          'driver mode should not keep polling terminal events in the background',
    );
  });

  test(
    'driver-friendly mode performs a limited warm-up refresh until content appears',
    () async {
      final coreBindings = _DelayedFramePtyBackend(revealOnRead: 3);
      final coreClient = coreBindings;
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultProfile]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
          driverWarmUpRefreshEnabledProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 450));

      final state = container.read(sessionControllerProvider);
      expect(state.tabs, hasLength(1));
      expect(coreBindings.takeFrameDiffCalls, greaterThan(1));
      expect(coreBindings.takeFrameDiffCalls, lessThanOrEqualTo(4));
      expect(coreBindings.pollEventsCalls, lessThanOrEqualTo(4));
      expect(
        container
            .read(sessionControllerProvider.notifier)
            .viewportFor(state.activeSessionId!)
            .frame
            .rows
            .first
            .text,
        isNotEmpty,
      );
    },
  );

  test(
    'driver-friendly mode still avoids background polling when content is already ready',
    () async {
      final coreBindings = _CountingPtyBackend();
      final coreClient = coreBindings;
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultProfile]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          sessionPollingEnabledProvider.overrideWithValue(false),
          driverWarmUpRefreshEnabledProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 450));

      expect(coreBindings.takeFrameDiffCalls, lessThanOrEqualTo(2));
      expect(coreBindings.pollEventsCalls, lessThanOrEqualTo(2));
    },
  );

  test(
    'driver-friendly mode applies terminal environment overrides to new sessions',
    () async {
      final coreBindings = FakePtyBackend();
      final coreClient = coreBindings;
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultProfile]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
          sessionEnvironmentOverridesProvider.overrideWithValue(
            const <String, String>{
              'TERM': 'xterm-256color',
              'COLORTERM': 'truecolor',
            },
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final state = container.read(sessionControllerProvider);
      expect(coreBindings.lastCreatedSessionPayload, isNotNull);
      expect(coreBindings.lastCreatedSessionPayload!['launch'], {
        'program': defaultProfile.shell,
        'args': defaultProfile.args,
        'env': {'TERM': 'xterm-256color', 'COLORTERM': 'truecolor'},
        'cwd': defaultProfile.cwd,
      });
      expect(state.tabs.single.profileSnapshot, isNotNull);
      expect(state.tabs.single.profileSnapshot!.env, {
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
      });
    },
  );

  test('bootstrap prefers app defaults over legacy profile defaults', () async {
    final coreClient = FakePtyBackend();
    final profileRepository = _TestProfileRepository(
      TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
    );
    final container = ProviderContainer(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(coreClient),
        profileRepositoryProvider.overrideWithValue(profileRepository),
        appPreferencesRepositoryProvider.overrideWithValue(
          _TestAppPreferencesRepository(
            const TerminalAppPreferencesDocument(
              defaults: TerminalAppDefaults(defaultProfileId: 'ssh'),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(sessionControllerProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(sessionControllerProvider);
    expect(state.defaultProfileId, 'ssh');
    expect(state.tabs.single.profileId, 'ssh');
  });

  test(
    'saveProfile clears configuration warnings for the saved profile',
    () async {
      final coreClient = FakePtyBackend();
      final profileRepository = _TestProfileRepository(
        TerminalProfilesDocument(
          profiles: [defaultProfile, sshProfile],
          loadWarnings: const [
            TerminalProfileLoadWarning(
              profileId: 'ssh',
              profileName: 'SSH',
              path: 'terminal.scrollbackLines',
              rawValueSummary: '-1',
              fallbackSummary: 'used default value 8000',
            ),
          ],
        ),
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(profileRepository),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      final controller = container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        container.read(sessionControllerProvider).configurationWarnings,
        hasLength(1),
      );

      await controller.saveProfile(
        sshProfile.copyWith(
          scrollbackLines: 4096,
          appearance: sshProfile.appearance.copyWith(
            colors: const terminal.TerminalColorPalette(
              special: terminal.TerminalSpecialColors(foreground: '#112233'),
            ),
          ),
        ),
      );

      final state = container.read(sessionControllerProvider);
      expect(state.configurationWarnings, isEmpty);
      expect(profileRepository.savedDocuments.last.loadWarnings, isEmpty);
    },
  );

  test(
    'bootstrap ignores legacy profile defaults when preferences are absent',
    () async {
      final coreClient = FakePtyBackend();
      final profileRepository = _TestProfileRepository(
        TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
      );
      final preferencesRepository = _TestAppPreferencesRepository(null);
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(profileRepository),
          appPreferencesRepositoryProvider.overrideWithValue(
            preferencesRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(sessionControllerProvider);
      expect(state.defaultProfileId, 'default');
      expect(state.tabs.single.profileId, 'default');
      expect(preferencesRepository.savedDocuments, isEmpty);
    },
  );

  test(
    'bootstrap clears invalid persisted defaults and falls back to first profile',
    () async {
      final coreClient = FakePtyBackend();
      final preferencesRepository = _TestAppPreferencesRepository(
        const TerminalAppPreferencesDocument(
          defaults: TerminalAppDefaults(defaultProfileId: 'missing'),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
            ),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            preferencesRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(sessionControllerProvider);
      expect(state.defaultProfileId, 'default');
      expect(state.tabs.single.profileId, 'default');
      expect(preferencesRepository.savedDocuments, hasLength(1));
      expect(
        preferencesRepository.savedDocuments.single.defaults.defaultProfileId,
        isNull,
      );
    },
  );

  test(
    'setDefaultProfile writes only app preferences during the compatibility window',
    () async {
      final coreClient = FakePtyBackend();
      final profileRepository = _TestProfileRepository(
        TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
      );
      final preferencesRepository = _TestAppPreferencesRepository(null);
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(profileRepository),
          appPreferencesRepositoryProvider.overrideWithValue(
            preferencesRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await container
          .read(sessionControllerProvider.notifier)
          .setDefaultProfile('ssh');

      expect(preferencesRepository.savedDocuments, hasLength(1));
      expect(
        preferencesRepository.savedDocuments.single.defaults.defaultProfileId,
        'ssh',
      );
      expect(profileRepository.savedDocuments, isEmpty);
    },
  );

  test(
    'deleteProfile only clears configured defaults tracked in preferences',
    () async {
      final coreClient = FakePtyBackend();
      final profileRepository = _TestProfileRepository(
        TerminalProfilesDocument(profiles: [defaultProfile, sshProfile]),
      );
      final preferencesRepository = _TestAppPreferencesRepository(null);
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(profileRepository),
          appPreferencesRepositoryProvider.overrideWithValue(
            preferencesRepository,
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await container
          .read(sessionControllerProvider.notifier)
          .deleteProfile('ssh');

      final state = container.read(sessionControllerProvider);
      expect(state.defaultProfileId, 'default');
      expect(preferencesRepository.savedDocuments, isEmpty);
      expect(
        profileRepository.savedDocuments.single.profiles.map(
          (profile) => profile.id,
        ),
        ['default'],
      );
      expect(
        profileRepository.savedDocuments.single.toJson().containsKey(
          'defaultProfileId',
        ),
        isFalse,
      );
    },
  );

  test(
    'shell exit closes an inactive tab without changing the active tab',
    () async {
      final bindings = _EventfulPtyBackend(FakePtyBackend());
      final coreClient = bindings;
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      for (var attempt = 0; attempt < 5; attempt += 1) {
        final bootSessionId = container
            .read(sessionControllerProvider)
            .activeSessionId;
        if (bootSessionId == null) {
          break;
        }
        controller.closeSession(bootSessionId);
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-1'),
      );
      final first = container.read(sessionControllerProvider).activeSessionId!;
      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-2'),
      );
      final second = container.read(sessionControllerProvider).activeSessionId!;
      expect(second, isNot(first));

      bindings.enqueueExit(first, code: 0);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(sessionControllerProvider);
      expect(state.tabs.map((tab) => tab.sessionId), isNot(contains(first)));
      expect(state.activeSessionId, second);
    },
  );

  test(
    'shell exit closes the active tab and focuses the remaining tab',
    () async {
      final bindings = _EventfulPtyBackend(FakePtyBackend());
      final coreClient = bindings;
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final bootSessionId = container
          .read(sessionControllerProvider)
          .activeSessionId;
      if (bootSessionId != null) {
        controller.closeSession(bootSessionId);
      }

      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-1'),
      );
      final first = container.read(sessionControllerProvider).activeSessionId!;
      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-2'),
      );
      final second = container.read(sessionControllerProvider).activeSessionId!;

      bindings.enqueueExit(second, code: 0);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(sessionControllerProvider);
      expect(state.tabs.map((tab) => tab.sessionId), equals([first]));
      expect(state.activeSessionId, first);
    },
  );

  test(
    'shell exit closes the last tab and returns to the empty state',
    () async {
      final bindings = _EventfulPtyBackend(FakePtyBackend());
      final coreClient = bindings;
      final container = ProviderContainer(
        overrides: [
          ptySessionBackendProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(TerminalProfilesDocument(profiles: [])),
          ),
          appPreferencesRepositoryProvider.overrideWithValue(
            _TestAppPreferencesRepository(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(sessionControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      for (var attempt = 0; attempt < 5; attempt += 1) {
        final bootSessionId = container
            .read(sessionControllerProvider)
            .activeSessionId;
        if (bootSessionId == null) {
          break;
        }
        controller.closeSession(bootSessionId);
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      controller.createSession(
        defaultTerminalProfile().copyWith(id: 'shell-1'),
      );
      final sessionId = container
          .read(sessionControllerProvider)
          .activeSessionId!;

      bindings.enqueueExit(sessionId, code: 0);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(sessionControllerProvider);
      expect(state.tabs, isEmpty);
      expect(state.activeSessionId, isNull);
    },
  );
}
