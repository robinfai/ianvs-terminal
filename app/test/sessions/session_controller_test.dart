import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/profiles/profile_repository.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/preferences/app_preferences_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/ffi/flutterm_core.dart';

import '../support/fake_core_bindings.dart';

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

class _EventfulCoreBindings implements CoreBindings {
  _EventfulCoreBindings(this._delegate);

  final FakeCoreBindings _delegate;
  final Map<int, List<Map<String, Object?>>> _queuedEvents = {};

  void enqueueEvent(String sessionId, Map<String, Object?> event) {
    _queuedEvents.putIfAbsent(int.parse(sessionId), () => []).add(event);
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
  int sessionCreate(ffi.Pointer<Utf8> profileJson) =>
      _delegate.sessionCreate(profileJson);

  @override
  int sessionClose(int sessionId) => _delegate.sessionClose(sessionId);

  @override
  ffi.Pointer<Utf8> sessionPollEventsJson(int sessionId) {
    final delegatePointer = _delegate.sessionPollEventsJson(sessionId);
    if (delegatePointer == ffi.nullptr) {
      final queued = _queuedEvents.remove(sessionId);
      if (queued == null) {
        return ffi.nullptr;
      }
      return jsonEncode(queued).toNativeUtf8();
    }

    try {
      final events =
          (jsonDecode(delegatePointer.toDartString()) as List<dynamic>)
              .cast<Map<String, Object?>>();
      final queued = _queuedEvents.remove(sessionId);
      if (queued != null) {
        events.addAll(queued);
      }
      return jsonEncode(events).toNativeUtf8();
    } finally {
      _delegate.stringFree(delegatePointer);
    }
  }

  @override
  int sessionResize(
    int sessionId,
    int cols,
    int rows,
    int pixelWidth,
    int pixelHeight,
  ) => _delegate.sessionResize(sessionId, cols, rows, pixelWidth, pixelHeight);

  @override
  int sessionScroll(int sessionId, int deltaLines) =>
      _delegate.sessionScroll(sessionId, deltaLines);

  @override
  int sessionScrollTo(int sessionId, int offset) =>
      _delegate.sessionScrollTo(sessionId, offset);

  @override
  ffi.Pointer<Utf8> sessionTakeFrameDiffJson(int sessionId) =>
      _delegate.sessionTakeFrameDiffJson(sessionId);

  @override
  int sessionWrite(int sessionId, ffi.Pointer<ffi.Uint8> bytes, int length) =>
      _delegate.sessionWrite(sessionId, bytes, length);

  @override
  void stringFree(ffi.Pointer<Utf8> value) => malloc.free(value);
}

class _CountingCoreBindings extends FakeCoreBindings {
  int takeFrameDiffCalls = 0;
  int pollEventsCalls = 0;

  @override
  ffi.Pointer<Utf8> sessionTakeFrameDiffJson(int sessionId) {
    takeFrameDiffCalls += 1;
    return super.sessionTakeFrameDiffJson(sessionId);
  }

  @override
  ffi.Pointer<Utf8> sessionPollEventsJson(int sessionId) {
    pollEventsCalls += 1;
    return super.sessionPollEventsJson(sessionId);
  }
}

class _DelayedFrameCoreBindings extends _CountingCoreBindings {
  _DelayedFrameCoreBindings({this.revealOnRead = 3});

  final int revealOnRead;

  @override
  int sessionCreate(ffi.Pointer<Utf8> profileJson) {
    final sessionId = super.sessionCreate(profileJson);
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
  ffi.Pointer<Utf8> sessionTakeFrameDiffJson(int sessionId) {
    final pointer = super.sessionTakeFrameDiffJson(sessionId);
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
    return pointer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const defaultProfile = TerminalProfile(
    id: 'default',
    name: 'Local Shell',
    shell: '/bin/zsh',
  );
  const sshProfile = TerminalProfile(
    id: 'ssh',
    name: 'SSH',
    shell: '/usr/bin/ssh',
  );

  test('session lifecycle updates tabs and active session', () {
    final coreClient = TerminalCoreClient(FakeCoreBindings());
    final container = ProviderContainer(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            const TerminalProfilesDocument(defaultProfileId: '', profiles: []),
          ),
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

  test('closing inactive session keeps current active session', () {
    final coreClient = TerminalCoreClient(FakeCoreBindings());
    final container = ProviderContainer(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            const TerminalProfilesDocument(defaultProfileId: '', profiles: []),
          ),
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

  test('resizeActiveSession dedupes identical size requests', () {
    final coreBindings = FakeCoreBindings();
    final coreClient = TerminalCoreClient(coreBindings);
    final container = ProviderContainer(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            const TerminalProfilesDocument(defaultProfileId: '', profiles: []),
          ),
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
    expect(coreBindings.resizeCalls, hasLength(2));

    final last = coreBindings.resizeCalls.last;
    expect(last[0], equals(int.parse(sessionId)));
    expect(last[1], greaterThan(0));
    expect(last[2], greaterThan(0));
    expect(last[3], greaterThan(0));
    expect(last[4], greaterThan(0));
  });

  test(
    'resizeActiveSession prefers measured viewport cell size when available',
    () {
      final coreBindings = FakeCoreBindings();
      final coreClient = TerminalCoreClient(coreBindings);
      final container = ProviderContainer(
        overrides: [
          terminalCoreClientProvider.overrideWithValue(coreClient),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(
                defaultProfileId: '',
                profiles: [],
              ),
            ),
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
    final coreBindings = FakeCoreBindings();
    final coreClient = TerminalCoreClient(coreBindings);
    final container = ProviderContainer(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            const TerminalProfilesDocument(defaultProfileId: '', profiles: []),
          ),
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
    final coreBindings = FakeCoreBindings();
    final coreClient = TerminalCoreClient(coreBindings);
    final container = ProviderContainer(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            const TerminalProfilesDocument(defaultProfileId: '', profiles: []),
          ),
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

  test(
    'resize events update the terminal session before resizing the macOS window',
    () async {
      final bindings = _EventfulCoreBindings(FakeCoreBindings());
      final coreClient = TerminalCoreClient(bindings);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('app/window_bridge');
      MethodCall? resizeCall;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'resizeBy') {
          resizeCall = call;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final container = ProviderContainer(
        overrides: [
          terminalCoreClientProvider.overrideWithValue(coreClient),
          sessionControllerProvider.overrideWith(_TestSessionController.new),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(
                defaultProfileId: '',
                profiles: [],
              ),
            ),
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
      expect(resizeCall, isNotNull);
      expect((resizeCall!.arguments as Map)['widthDelta'], 260.0);
      expect((resizeCall!.arguments as Map)['heightDelta'], 60.0);
    },
  );

  test('OSC 52 copy events decode UTF-8 clipboard text', () async {
    final bindings = _EventfulCoreBindings(FakeCoreBindings());
    final coreClient = TerminalCoreClient(bindings);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String copied = '';
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': ''};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final container = ProviderContainer(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            const TerminalProfilesDocument(defaultProfileId: '', profiles: []),
          ),
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
    final fakeBindings = FakeCoreBindings();
    final bindings = _EventfulCoreBindings(fakeBindings);
    final coreClient = TerminalCoreClient(bindings);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': '你好, 世界🌟'};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final container = ProviderContainer(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(coreClient),
        sessionControllerProvider.overrideWith(_TestSessionController.new),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            const TerminalProfilesDocument(defaultProfileId: '', profiles: []),
          ),
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
      final coreClient = TerminalCoreClient(FakeCoreBindings());
      final profileRepository = _TestProfileRepository(
        const TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [defaultProfile, sshProfile],
        ),
      );
      final preferencesRepository = _TestAppPreferencesRepository(
        const TerminalAppPreferencesDocument(
          defaults: TerminalAppDefaults(defaultProfileId: 'default'),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          terminalCoreClientProvider.overrideWithValue(coreClient),
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

  test('driver-friendly mode avoids the periodic session polling loop', () async {
    final coreBindings = _CountingCoreBindings();
    final coreClient = TerminalCoreClient(coreBindings);
    final container = ProviderContainer(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(coreClient),
        profileRepositoryProvider.overrideWithValue(
          _TestProfileRepository(
            const TerminalProfilesDocument(
              defaultProfileId: 'default',
              profiles: [defaultProfile],
            ),
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
      final coreBindings = _DelayedFrameCoreBindings(revealOnRead: 3);
      final coreClient = TerminalCoreClient(coreBindings);
      final container = ProviderContainer(
        overrides: [
          terminalCoreClientProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(
                defaultProfileId: 'default',
                profiles: [defaultProfile],
              ),
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
      final coreBindings = _CountingCoreBindings();
      final coreClient = TerminalCoreClient(coreBindings);
      final container = ProviderContainer(
        overrides: [
          terminalCoreClientProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(
                defaultProfileId: 'default',
                profiles: [defaultProfile],
              ),
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
      final coreBindings = FakeCoreBindings();
      final coreClient = TerminalCoreClient(coreBindings);
      final container = ProviderContainer(
        overrides: [
          terminalCoreClientProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(
                defaultProfileId: 'default',
                profiles: [defaultProfile],
              ),
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

      expect(coreBindings.lastCreatedProfileJson, isNotNull);
      expect(coreBindings.lastCreatedProfileJson!['env'], {
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
      });
    },
  );

  test('bootstrap prefers app defaults over legacy profile defaults', () async {
    final coreClient = TerminalCoreClient(FakeCoreBindings());
    final profileRepository = _TestProfileRepository(
      const TerminalProfilesDocument(
        defaultProfileId: 'default',
        profiles: [defaultProfile, sshProfile],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        terminalCoreClientProvider.overrideWithValue(coreClient),
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
    'bootstrap falls back to legacy default when preferences are absent',
    () async {
      final coreClient = TerminalCoreClient(FakeCoreBindings());
      final profileRepository = _TestProfileRepository(
        const TerminalProfilesDocument(
          defaultProfileId: 'ssh',
          profiles: [defaultProfile, sshProfile],
        ),
      );
      final preferencesRepository = _TestAppPreferencesRepository(null);
      final container = ProviderContainer(
        overrides: [
          terminalCoreClientProvider.overrideWithValue(coreClient),
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
      expect(state.defaultProfileId, 'ssh');
      expect(state.tabs.single.profileId, 'ssh');
      expect(preferencesRepository.savedDocuments, isEmpty);
    },
  );

  test(
    'bootstrap clears invalid persisted defaults and falls back to first profile',
    () async {
      final coreClient = TerminalCoreClient(FakeCoreBindings());
      final preferencesRepository = _TestAppPreferencesRepository(
        const TerminalAppPreferencesDocument(
          defaults: TerminalAppDefaults(defaultProfileId: 'missing'),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          terminalCoreClientProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(
                defaultProfileId: 'ssh',
                profiles: [defaultProfile, sshProfile],
              ),
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
      final coreClient = TerminalCoreClient(FakeCoreBindings());
      final profileRepository = _TestProfileRepository(
        const TerminalProfilesDocument(
          defaultProfileId: 'default',
          profiles: [defaultProfile, sshProfile],
        ),
      );
      final preferencesRepository = _TestAppPreferencesRepository(null);
      final container = ProviderContainer(
        overrides: [
          terminalCoreClientProvider.overrideWithValue(coreClient),
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
    'deleteProfile clears a legacy-seeded default through preferences repair-write',
    () async {
      final coreClient = TerminalCoreClient(FakeCoreBindings());
      final profileRepository = _TestProfileRepository(
        const TerminalProfilesDocument(
          defaultProfileId: 'ssh',
          profiles: [defaultProfile, sshProfile],
        ),
      );
      final preferencesRepository = _TestAppPreferencesRepository(null);
      final container = ProviderContainer(
        overrides: [
          terminalCoreClientProvider.overrideWithValue(coreClient),
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
      expect(
        preferencesRepository.savedDocuments.last.defaults.defaultProfileId,
        isNull,
      );
      expect(
        profileRepository.savedDocuments.single.profiles.map(
          (profile) => profile.id,
        ),
        ['default'],
      );
      expect(profileRepository.savedDocuments.single.defaultProfileId, 'ssh');
    },
  );

  test(
    'shell exit closes an inactive tab without changing the active tab',
    () async {
      final bindings = _EventfulCoreBindings(FakeCoreBindings());
      final coreClient = TerminalCoreClient(bindings);
      final container = ProviderContainer(
        overrides: [
          terminalCoreClientProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(
                defaultProfileId: '',
                profiles: [],
              ),
            ),
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
      final bindings = _EventfulCoreBindings(FakeCoreBindings());
      final coreClient = TerminalCoreClient(bindings);
      final container = ProviderContainer(
        overrides: [
          terminalCoreClientProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(
                defaultProfileId: '',
                profiles: [],
              ),
            ),
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
      final bindings = _EventfulCoreBindings(FakeCoreBindings());
      final coreClient = TerminalCoreClient(bindings);
      final container = ProviderContainer(
        overrides: [
          terminalCoreClientProvider.overrideWithValue(coreClient),
          profileRepositoryProvider.overrideWithValue(
            _TestProfileRepository(
              const TerminalProfilesDocument(
                defaultProfileId: '',
                profiles: [],
              ),
            ),
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
