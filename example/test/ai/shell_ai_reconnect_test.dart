import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_connections.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/recording/local_session_recording_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../helpers/pump_app.dart';
import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';
import '../support/no_io_local_terminal_layout_repository.dart';
import '../support/shell_command_actions.dart';

class _Store implements AiConfigurationStore {
  @override
  Future<AiConfiguration?> read() async => null;

  @override
  Future<void> write(AiConfiguration? value) async {}
}

class _Backend extends FakePtyBackend {
  final submissions = <({String session, String id, String command})>[];
  final inspected = <({String session, String id})>[];
  final receipts = <String, String>{};
  final closeAttempts = <String>[];
  final clearedSessions = <String>[];

  @override
  void closeSession(String sessionId) {
    closeAttempts.add(sessionId);
    super.closeSession(sessionId);
  }

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
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    switch (request['kind']) {
      case 'terminal.clear_buffer':
        clearedSessions.add(sessionId);
        return super.requestSessionJson(sessionId, requestJson);
      case 'composer.state':
        return jsonEncode({
          'state': 'ready',
          'lease': 'lease-$sessionId',
          'contextId': 'root',
          'transport': 'shell',
          'cwd': '/srv/app',
          'dialect': 'bash',
        });
      case 'composer.submit':
        submissions.add((
          session: sessionId,
          id: request['submissionId']! as String,
          command: request['text']! as String,
        ));
        return jsonEncode({'outcome': 'unknown'});
      case 'composer.receipt':
        inspected.add((
          session: sessionId,
          id: request['submissionId']! as String,
        ));
        return jsonEncode({
          'submissionId': request['submissionId'],
          'outcome': receipts[sessionId] ?? 'unknown',
          if (receipts[sessionId] == 'accepted') 'blockId': 'evidence',
        });
      case 'terminal.live_screen':
        return jsonEncode({'text': 'connected shell $sessionId'});
      case 'terminal.command_blocks':
        final block = {
          'id': 'evidence',
          'command': 'printf evidence',
          'cwd': '/srv/app',
          'exitCode': 0,
          'totalLines': 1,
          'matchingLines': 1,
          'offset': 0,
          'lines': [
            {'index': 0, 'source_row': 100, 'text': 'evidence from $sessionId'},
          ],
        };
        return jsonEncode(
          request['id'] == null
              ? {
                  'blocks': [block],
                }
              : {'block': block},
        );
    }
    return super.requestSessionJson(sessionId, requestJson);
  }
}

class _RecordingBackend extends _Backend {
  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    switch (request['kind']) {
      case 'terminal.recording_start':
        return jsonEncode({
          'ok': true,
          'max_events': 4096,
          'max_payload_bytes': 8 * 1024 * 1024,
        });
      case 'terminal.recording_stop_prepare':
        final job = request['job_id']! as String;
        final directory = request['handoff_directory']! as String;
        final path = '$directory/.ianvs-recording-handoff-$job.ndjson';
        return jsonEncode({
          'ok': true,
          'job_id': job,
          'handoff_path': path,
          'error_path': '$path.error.json',
        });
    }
    return super.requestSessionJson(sessionId, requestJson);
  }
}

// Exercise the production recording close gate without filesystem timing.
class _BlockingRecordingRepository extends LocalSessionRecordingRepository
    with NoIoLocalSessionRecordingRecovery {
  _BlockingRecordingRepository()
    : super(directoryResolver: () async => throw StateError('Unexpected I/O'));

  final saveStarted = Completer<void>();
  final allowSave = Completer<void>();

  @override
  Future<LocalSessionRecordingDestination> reserve({
    required String runtimeSessionId,
    required DateTime createdAtUtc,
  }) async => LocalSessionRecordingDestination(
    File('/unused-recording-fixture/$runtimeSessionId.ndjson'),
    reservationNonce: '0123456789abcdef0123456789abcdef',
  );

  @override
  Future<Directory> ensureNativeHandoffDirectory() async =>
      Directory('/unused-recording-fixture/handoff');

  @override
  Future<TerminalRecordingFinalizeJob> reserveNativeRecordingJob({
    required String sessionId,
    required Directory handoffDirectory,
    required LocalSessionRecordingDestination destination,
    required List<TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
  }) async {
    const id = 'abcdef0123456789abcdef0123456789';
    final path = '${handoffDirectory.path}/.ianvs-recording-handoff-$id.ndjson';
    return TerminalRecordingFinalizeJob(
      sessionId: sessionId,
      jobId: id,
      handoffPath: path,
      errorPath: '$path.error.json',
    );
  }

  @override
  void markNativeRecordingCaptureStartedSynchronously({
    required TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
  }) {}

  @override
  void prepareNativeRecordingJobMetadataSynchronously({
    required TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required List<TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
  }) {}

  @override
  Future<void> registerNativeRecordingJob({
    required TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required LocalSessionRecordingDestination destination,
    required List<TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
  }) async {}

  @override
  Future<String> finalizeNativeRecording({
    required TerminalRecordingFinalizeJob job,
    required Directory handoffDirectory,
    required LocalSessionRecordingDestination destination,
    required List<TerminalRecordingSemanticEvent> semanticEvents,
    String? displayName,
    LocalSessionRecordingFinalizeCancellation? cancellation,
    LocalSessionRecordingNativeJobStatusProbe? nativeJobStatusProbe,
  }) async {
    if (!saveStarted.isCompleted) saveStarted.complete();
    await allowSave.future;
    return destination.file.path;
  }

  @override
  bool release(LocalSessionRecordingDestination destination) => true;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<({ProviderContainer container, String id, TerminalProfile profile})>
_pump(
  WidgetTester tester,
  _Backend backend, {
  TargetPlatform platform = TargetPlatform.iOS,
  LocalSessionRecordingRepository? recordingRepository,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  final size = platform == TargetPlatform.macOS
      ? const Size(1200, 900)
      : const Size(390, 844);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final settings = AiSettingsController(_Store());
  addTearDown(settings.dispose);
  final profile = TerminalProfile(
    id: 'cloud',
    name: 'Cloud',
    shell: '',
    connection: const TerminalConnectionConfig.ssh(
      host: 'cloud.test',
      user: 'fixture',
    ),
  );
  await tester.pumpApp(
    const ShellScreen(),
    platform: platform,
    wrapper: (app) => ProviderScope(
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
          recordingRepository ?? noIoLocalSessionRecordingRepository(),
        ),
      ],
      child: app,
    ),
  );
  await _settle(tester);
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ShellScreen)),
  );
  expect(MediaQuery.sizeOf(tester.element(find.byType(ShellScreen))), size);
  if (platform == TargetPlatform.iOS) {
    expect(
      Theme.of(tester.element(find.byType(ShellScreen))).materialTapTargetSize,
      MaterialTapTargetSize.padded,
    );
  }
  if (container.read(sessionControllerProvider).activeSessionId == null) {
    container.read(sessionControllerProvider.notifier).createSession(profile);
    await _settle(tester);
  }
  return (
    container: container,
    id: container.read(sessionControllerProvider).activeSessionId!,
    profile: profile,
  );
}

Future<TerminalAiController> _openAi(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('terminal-ai-open-$id')));
  await _settle(tester);
  return tester
      .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
      .controller;
}

Future<void> _disconnect(
  WidgetTester tester,
  _Backend backend,
  ProviderContainer container,
  String id,
) async {
  backend.enqueueEvent(
    id,
    PtyEvent(kind: 'exit', sessionId: id, payload: {'code': 255}),
  );
  container.read(terminalRuntimeControllerProvider).refreshSession(id);
  await _settle(tester);
  expect(
    container
        .read(sessionControllerProvider)
        .tabs
        .expand((tab) => tab.effectivePanes)
        .singleWhere((pane) => pane.sessionId == id)
        .isExited,
    isTrue,
  );
}

Future<void> _showDisconnected(WidgetTester tester) async {
  final back = find.byKey(const Key('mobile-connections-back'));
  if (back.evaluate().isNotEmpty) {
    await tester.tap(back);
    await _settle(tester);
  }
  if (find
      .byKey(const Key('mobile-sessions-disconnected-toggle'))
      .evaluate()
      .isNotEmpty) {
    await tester.ensureVisible(
      find.byKey(const Key('mobile-sessions-disconnected-toggle')),
    );
    await tester.tap(
      find.byKey(const Key('mobile-sessions-disconnected-toggle')),
    );
    await _settle(tester);
  }
}

Future<void> _closeAi(WidgetTester tester) async {
  tester
      .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
      .onTakeOver!();
  await _settle(tester);
}

Future<void> _closeDesktopTab(WidgetTester tester, String tabId) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(find.byKey(Key('shell-tab-$tabId'))));
  await _settle(tester);
  await tester.tap(find.byKey(Key('shell-tab-close-$tabId')));
  await mouse.removePointer();
  await _settle(tester);
  final confirm = find.byKey(const Key('shell-close-confirm'));
  if (confirm.evaluate().isNotEmpty) {
    await tester.tap(confirm);
    await _settle(tester);
  }
}

Future<void> _clearBufferShortcut(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('shell-terminal-surface')));
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK, platform: 'macos');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
  await _settle(tester);
}

void main() {
  group('Shell AI reconnect', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'ordinary reconnect preserves a closed AI and its old receipt',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final backend = _Backend();
        final (:container, :id, profile: _) = await _pump(tester, backend);
        final ai = await _openAi(tester, id);
        await ai.runUserCommand('printf once');
        expect(ai.hasUnresolvedSubmission, isTrue);
        final task = ai.taskId;
        ai.setDraft('keep my task draft');
        ai.attachContext(ai.context!.lastBlock!);
        tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .onTakeOver!();
        await _settle(tester);
        await _disconnect(tester, backend, container, id);
        await tester.tap(find.byKey(Key('mobile-disconnected-reconnect-$id')));
        await _settle(tester);
        final next = container.read(sessionControllerProvider).activeSessionId!;
        expect(next, isNot(id));
        expect(find.byType(TerminalAiWorkspace), findsNothing);
        expect(await _openAi(tester, next), same(ai));
        expect(ai.taskId, task);
        expect(ai.draft, 'keep my task draft');
        expect(ai.attachments.single.sourceSessionId, id);
        expect(ai.retainsSource(id), isTrue);
        expect(ai.hasUnresolvedSubmission, isTrue);
        expect(ai.canResume, isFalse);
        expect(backend.submissions, hasLength(1));
        expect(backend.inspected.every((entry) => entry.session == id), isTrue);
        expect(backend.closedSessionIds, isEmpty);
        backend.receipts[id] = 'accepted';
        await ai.refreshContext();
        expect(ai.hasUnresolvedSubmission, isFalse);
        expect(ai.transcript.single.blockId, 'evidence');
        expect(ai.transcript.single.target!.sessionId, id);
        expect(backend.submissions, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'concurrent and repeated reconnect preserve the replacement draft',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final backend = _Backend();
        final (:container, :id, profile: _) = await _pump(tester, backend);
        final ai = await _openAi(tester, id);
        ai.setDraft('original AI draft');
        await _disconnect(tester, backend, container, id);
        final reconnect = tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .onReconnect!;
        final first = reconnect();
        final second = reconnect();
        await _settle(tester);
        await Future.wait([first, second]);
        final next = container.read(sessionControllerProvider).activeSessionId!;
        expect(container.read(sessionControllerProvider).tabs, hasLength(2));
        expect(
          tester
              .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
              .controller,
          same(ai),
        );
        expect((ai.terminal as TerminalAiConnections).sourceSessionIds, {
          id,
          next,
        });
        ai.setDraft('new AI draft');
        tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .onTakeOver!();
        await _settle(tester);
        await tester.enterText(
          find.byKey(const Key('composer-editor')),
          'new terminal draft',
        );
        await reconnect();
        await _settle(tester);
        expect(container.read(sessionControllerProvider).activeSessionId, next);
        expect(container.read(sessionControllerProvider).tabs, hasLength(2));
        expect(find.byType(TerminalAiWorkspace), findsNothing);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('composer-editor')))
              .controller!
              .text,
          'new terminal draft',
        );
        expect(ai.draft, 'new AI draft');
        expect(backend.submissions, isEmpty);
        expect(backend.writes, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'an earlier history row reconnects the latest failed AI and terminal draft',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final backend = _Backend();
        final (:container, :id, profile: _) = await _pump(tester, backend);
        final ai = await _openAi(tester, id);
        final task = ai.taskId;
        ai.attachContext(ai.context!.lastBlock!);
        await _disconnect(tester, backend, container, id);
        await tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .onReconnect!();
        await _settle(tester);
        final second = container
            .read(sessionControllerProvider)
            .activeSessionId!;
        ai.setDraft('latest AI draft');
        tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .onTakeOver!();
        await _settle(tester);
        await tester.enterText(
          find.byKey(const Key('composer-editor')),
          'latest terminal draft',
        );
        await _disconnect(tester, backend, container, second);
        await _showDisconnected(tester);
        final reconnect = find.byKey(Key('mobile-session-reconnect-$id'));
        await tester.ensureVisible(reconnect);
        await tester.tap(reconnect);
        await _settle(tester);
        final state = container.read(sessionControllerProvider);
        final third = state.activeSessionId!;
        expect(third, isNot(isIn([id, second])));
        expect(state.tabs, hasLength(3));
        expect(state.liveReconnectionFor(id), third);
        expect(state.liveReconnectionFor(second), third);
        expect(find.byType(TerminalAiWorkspace), findsNothing);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('composer-editor')))
              .controller!
              .text,
          'latest terminal draft',
        );
        expect(await _openAi(tester, third), same(ai));
        expect(ai.taskId, task);
        expect(ai.draft, 'latest AI draft');
        expect(ai.attachments.single.sourceSessionId, id);
        expect((ai.terminal as TerminalAiConnections).sourceSessionIds, {
          id,
          second,
          third,
        });
        expect(backend.submissions, isEmpty);
        expect(backend.writes, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'ordinary detail reconnect leaves AI unbound to the old session',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final backend = _Backend();
        final (:container, :id, profile: _) = await _pump(tester, backend);
        expect(find.byKey(Key('terminal-ai-open-$id')), findsOneWidget);
        await _disconnect(tester, backend, container, id);
        await tester.tap(find.byKey(Key('mobile-disconnected-reconnect-$id')));
        await _settle(tester);
        final next = container.read(sessionControllerProvider).activeSessionId!;
        final ai = await _openAi(tester, next);
        expect(ai.transcript, isEmpty);
        expect(ai.retainsSource(id), isFalse);
        expect((ai.terminal as TerminalAiConnections).sourceSessionIds, {next});
        expect(backend.submissions, isEmpty);
        expect(backend.inspected, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'reconnecting an unopened history row does not create an AI history',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final backend = _Backend();
        final (:container, id: _, :profile) = await _pump(tester, backend);
        await tester.tap(find.byKey(const Key('mobile-connections-back')));
        await _settle(tester);
        final original = container
            .read(sessionControllerProvider.notifier)
            .createSession(profile)!;
        await _settle(tester);
        expect(find.byKey(Key('terminal-ai-open-$original')), findsNothing);
        await _disconnect(tester, backend, container, original);
        await _showDisconnected(tester);
        await tester.ensureVisible(
          find.byKey(Key('mobile-session-reconnect-$original')),
        );
        await tester.tap(find.byKey(Key('mobile-session-reconnect-$original')));
        await _settle(tester);
        final next = container.read(sessionControllerProvider).activeSessionId!;
        expect(next, isNot(original));
        expect(find.byType(TerminalAiWorkspace), findsNothing);
        final ai = await _openAi(tester, next);
        expect(ai.transcript, isEmpty);
        expect(ai.retainsSource(original), isFalse);
        expect((ai.terminal as TerminalAiConnections).sourceSessionIds, {next});
        expect(backend.submissions, isEmpty);
        expect(backend.writes, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'history cleanup protects an AI source with an unknown receipt',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final backend = _Backend();
        final (:container, :id, profile: _) = await _pump(tester, backend);
        final ai = await _openAi(tester, id);
        await ai.runUserCommand('printf once');
        await _disconnect(tester, backend, container, id);
        await tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .onReconnect!();
        await _settle(tester);
        final next = container.read(sessionControllerProvider).activeSessionId!;
        await _showDisconnected(tester);
        final remove = find.byKey(Key('mobile-session-remove-$id'));
        expect(tester.widget<TextButton>(remove).onPressed, isNull);
        expect(
          container.read(terminalRuntimeControllerProvider).hasSession(id),
          isTrue,
        );
        expect(backend.closedSessionIds, isEmpty);
        backend.receipts[id] = 'accepted';
        await ai.refreshContext();
        expect(ai.hasUnresolvedSubmission, isFalse);
        expect(ai.context!.sessionId, next);
        expect(ai.transcript.single.target!.sessionId, id);
        expect(backend.inspected.every((entry) => entry.session == id), isTrue);
        expect(backend.submissions, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'batch cleanup closes a disconnected AI owner before its reordered source',
      (tester) async {
        final backend = _Backend();
        final (:container, :id, profile: _) = await _pump(tester, backend);
        final ai = await _openAi(tester, id);
        await ai.runUserCommand('printf once');
        await _disconnect(tester, backend, container, id);
        await tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .onReconnect!();
        await _settle(tester);
        final controller = container.read(sessionControllerProvider.notifier);
        final next = container.read(sessionControllerProvider).activeSessionId!;
        await _closeAi(tester);
        await _disconnect(tester, backend, container, next);
        controller.reorderTab(oldIndex: 1, newIndex: 0);
        await _settle(tester);
        expect(
          container
              .read(sessionControllerProvider)
              .tabs
              .map((tab) => tab.sessionId),
          [next, id],
        );
        expect(ai.retainsSource(id), isTrue);
        await _showDisconnected(tester);
        final clear = find.byKey(
          const Key('mobile-sessions-clear-disconnected'),
        );
        await tester.ensureVisible(clear);
        await tester.tap(clear);
        await _settle(tester);
        await tester.tap(find.byKey(const Key('shell-close-confirm')));
        await _settle(tester);
        expect(backend.closedSessionIds, [next, id]);
        expect(container.read(sessionControllerProvider).tabs, isEmpty);
        final runtime = container.read(terminalRuntimeControllerProvider);
        expect(runtime.hasSession(id), isFalse);
        expect(runtime.hasSession(next), isFalse);
        expect(backend.submissions, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    for (final rejectOwnerClose in [false, true]) {
      testWidgets(
        rejectOwnerClose
            ? 'split tab close retains the old source when its AI owner rejects close'
            : 'split tab close removes its AI owner before the old source',
        (tester) async {
          final backend = _Backend();
          final (:container, :id, profile: _) = await _pump(
            tester,
            backend,
            platform: TargetPlatform.macOS,
          );
          final ai = await _openAi(tester, id);
          await ai.runUserCommand('printf once');
          await _disconnect(tester, backend, container, id);
          await tester
              .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
              .onReconnect!();
          await _settle(tester);
          final controller = container.read(sessionControllerProvider.notifier);
          final next = container
              .read(sessionControllerProvider)
              .activeSessionId!;
          await _closeAi(tester);
          expect(
            controller.moveSessionToPane(
              sourceSessionId: next,
              targetSessionId: id,
              axis: TerminalSplitAxis.horizontal,
              before: false,
            ),
            isTrue,
          );
          await _settle(tester);
          final tab = container.read(sessionControllerProvider).tabs.single;
          expect(tab.effectivePanes.map((pane) => pane.sessionId), [id, next]);
          if (rejectOwnerClose) backend.failingCloseSessionIds.add(next);
          await _closeDesktopTab(tester, tab.sessionId);
          final runtime = container.read(terminalRuntimeControllerProvider);
          if (rejectOwnerClose) {
            expect(backend.closeAttempts, [next]);
            expect(backend.closedSessionIds, isEmpty);
            expect(runtime.hasSession(id), isTrue);
            expect(runtime.hasSession(next), isTrue);
            expect(
              container
                  .read(sessionControllerProvider)
                  .tabs
                  .single
                  .effectivePanes
                  .map((pane) => pane.sessionId),
              [id, next],
            );
            expect(await _openAi(tester, next), same(ai));
            expect(ai.hasUnresolvedSubmission, isTrue);
            backend.receipts[id] = 'accepted';
            await ai.refreshContext();
            expect(ai.hasUnresolvedSubmission, isFalse);
            expect(ai.transcript.single.target!.sessionId, id);
            backend.failingCloseSessionIds.remove(next);
          } else {
            expect(backend.closedSessionIds, [next, id]);
            expect(container.read(sessionControllerProvider).tabs, isEmpty);
            expect(runtime.hasSession(id), isFalse);
            expect(runtime.hasSession(next), isFalse);
          }
          expect(backend.submissions, hasLength(1));
          await tester.pumpWidget(const SizedBox.shrink());
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }

    testWidgets(
      'recording finalization during tab close prevents AI reconnecting the source',
      (tester) async {
        final backend = _RecordingBackend();
        final repository = _BlockingRecordingRepository();
        addTearDown(() {
          if (!repository.allowSave.isCompleted) {
            repository.allowSave.complete();
          }
        });
        final (:container, :id, profile: _) = await _pump(
          tester,
          backend,
          platform: TargetPlatform.macOS,
          recordingRepository: repository,
        );
        final ai = await _openAi(tester, id);
        await ai.runUserCommand('printf once');
        final controller = container.read(sessionControllerProvider.notifier);
        expect(await controller.startSessionRecording(id), isTrue);
        await _closeDesktopTab(tester, id);
        expect(repository.saveStarted.isCompleted, isTrue);
        expect(backend.closedSessionIds, isEmpty);
        await _disconnect(tester, backend, container, id);
        final reconnect = tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .onReconnect;
        expect(reconnect, isNotNull);
        await reconnect!();
        await _settle(tester);
        expect(container.read(sessionControllerProvider).tabs, hasLength(1));
        expect(container.read(sessionControllerProvider).activeSessionId, id);
        expect((ai.terminal as TerminalAiConnections).sourceSessionIds, {id});
        expect(backend.submissions, hasLength(1));
        repository.allowSave.complete();
        await _settle(tester);
        // The source disconnected during recording finalization. Its earlier
        // close confirmation cannot cover this changed connection state.
        expect(backend.closedSessionIds, isEmpty);
        expect(ai.hasUnresolvedSubmission, isTrue);
        await _closeDesktopTab(tester, id);
        expect(backend.closedSessionIds, [id]);
        expect(container.read(sessionControllerProvider).tabs, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    for (final retainedByAi in [false, true]) {
      testWidgets(
        retainedByAi
            ? 'mobile menu hides clear buffer for a retained AI evidence source'
            : 'mobile menu hides clear buffer for a disconnected output record',
        (tester) async {
          final backend = _Backend();
          final (:container, :id, profile: _) = await _pump(tester, backend);
          if (retainedByAi) {
            final ai = await _openAi(tester, id);
            await ai.runUserCommand('printf once');
          }
          await _disconnect(tester, backend, container, id);
          if (retainedByAi) {
            await tester
                .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
                .onReconnect!();
            await _settle(tester);
            await _closeAi(tester);
            await _showDisconnected(tester);
            final record = find.byKey(Key('mobile-session-$id'));
            await tester.ensureVisible(record);
            await tester.tap(record);
            await _settle(tester);
          }
          expect(container.read(sessionControllerProvider).activeSessionId, id);
          await tester.tap(find.byKey(const Key('shell-chrome-menu')));
          await _settle(tester);
          expect(find.byKey(const Key('shell-clear-buffer')), findsNothing);
          expect(backend.clearedSessions, isEmpty);
          await tester.pumpWidget(const SizedBox.shrink());
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }

    testWidgets(
      'desktop menu and shortcut preserve retained evidence while live clear still works',
      (tester) async {
        final backend = _Backend();
        final (:container, :id, profile: _) = await _pump(
          tester,
          backend,
          platform: TargetPlatform.macOS,
        );
        final ai = await _openAi(tester, id);
        await ai.runUserCommand('printf once');
        await _disconnect(tester, backend, container, id);
        await tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .onReconnect!();
        await _settle(tester);
        final next = container.read(sessionControllerProvider).activeSessionId!;
        await _closeAi(tester);
        final controller = container.read(sessionControllerProvider.notifier);
        controller.activateSession(id);
        await _settle(tester);
        await openShellCommand(tester, 'shell-clear-buffer');
        await _settle(tester);
        expect(backend.clearedSessions, isEmpty);
        await _clearBufferShortcut(tester);
        expect(backend.clearedSessions, isEmpty);
        backend.receipts[id] = 'accepted';
        await ai.refreshContext();
        expect(ai.hasUnresolvedSubmission, isFalse);
        expect(ai.transcript.single.target!.sessionId, id);
        expect(ai.transcript.single.blockId, 'evidence');
        controller.activateSession(next);
        await _settle(tester);
        await _clearBufferShortcut(tester);
        expect(backend.clearedSessions, [next]);
        expect(backend.submissions, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  });
}
