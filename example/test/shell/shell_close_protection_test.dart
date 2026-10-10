import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/recording/local_session_recording_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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

class _Store implements AiConfigurationStore {
  @override
  Future<AiConfiguration?> read() async => const AiConfiguration.mock();

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
  bool rejectSave = false;

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
    if (rejectSave) throw StateError('Recording save cancelled');
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
  TargetPlatform platform = TargetPlatform.macOS,
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
      .widgetList<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
      .singleWhere((workspace) => workspace.controller.context?.sessionId == id)
      .controller;
}

// Keep the production HTTP client and independent reviewer paths, while making
// response delivery deterministic and preventing any real network connection.
class _ModelClient implements HttpClient {
  _ModelClient(this.respond);
  final Future<Map<String, Object?>> Function(Map<String, Object?>) respond;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> postUrl(Uri url) async => _ModelRequest(respond);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ModelHeaders implements HttpHeaders {
  @override
  ContentType? contentType;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ModelRequest implements HttpClientRequest {
  _ModelRequest(this.respond);
  final Future<Map<String, Object?>> Function(Map<String, Object?>) respond;
  final bytes = <int>[];
  @override
  final headers = _ModelHeaders();
  @override
  bool followRedirects = false;
  @override
  int contentLength = -1;
  @override
  void add(List<int> data) => bytes.addAll(data);
  @override
  Future<HttpClientResponse> close() async => _ModelResponse(
    await respond(
      (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>(),
    ),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ModelResponse extends Stream<List<int>> implements HttpClientResponse {
  _ModelResponse(this.message);
  final Map<String, Object?> message;
  @override
  int get statusCode => 200;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream.value(
        utf8.encode(
          jsonEncode({
            'choices': [
              {'message': message},
            ],
          }),
        ),
      ).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _commandResponse() => {
  'content': 'Inspect the working directory',
  'tool_calls': [
    {
      'id': 'inspect-pwd',
      'function': {
        'name': 'run_command',
        'arguments': jsonEncode({
          'command': 'pwd',
          'reason': 'Inspect directory',
        }),
      },
    },
  ],
};

Future<void> _propose(WidgetTester tester, TerminalAiController ai) async {
  await HttpOverrides.runZoned(() async {
    final turn = ai.ask('Inspect the current directory');
    await _settle(tester);
    await turn;
  }, createHttpClient: (_) => _ModelClient((_) async => _commandResponse()));
  expect(ai.phase, AiPhase.awaitingApproval);
  expect(ai.pending, isNotNull);
}

Future<void> _closeTab(WidgetTester tester, String tabId) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(find.byKey(Key('shell-tab-$tabId'))));
  await _settle(tester);
  await tester.tap(find.byKey(Key('shell-tab-close-$tabId')));
  await mouse.removePointer();
  await _settle(tester);
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('shell-close-confirm')));
  await _settle(tester);
}

Future<void> _closePane(WidgetTester tester, String tabId) async {
  await tester.tap(
    find.byKey(Key('shell-tab-$tabId')),
    buttons: kSecondaryButton,
  );
  await _settle(tester);
  await tester.tap(find.text('Close active pane'));
  await _settle(tester);
}

Future<void> _cancel(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('shell-close-cancel')));
  await _settle(tester);
}

Future<void> _running(
  WidgetTester tester,
  _Backend backend,
  ProviderContainer container,
  String id,
) async {
  backend.enqueueEvent(
    id,
    PtyEvent(
      kind: 'shell_command',
      sessionId: id,
      payload: {
        'source': 'osc133',
        'eventType': 'command_executed',
        'command': 'sleep 600',
      },
    ),
  );
  container.read(terminalRuntimeControllerProvider).refreshSession(id);
  await _settle(tester);
  expect(
    container
        .read(sessionControllerProvider)
        .tabs
        .expand((tab) => tab.effectivePanes)
        .singleWhere((pane) => pane.sessionId == id)
        .shellIntegration
        .runningCommand,
    'sleep 600',
  );
}

void main() {
  group('Shell close protection', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'pending proposal cancellation preserves state and permits copying draft',
      (tester) async {
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
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
        final backend = _Backend();
        final (:container, :id, profile: _) = await _pump(tester, backend);
        final ai = await _openAi(tester, id);
        await _propose(tester, ai);
        ai.setDraft('Keep this follow-up exactly');
        ai.attachContext(ai.context!.lastBlock!);
        final proposal = ai.pending;
        final revision = ai.proposalRevision;
        final source = ai.attachments.single;
        await _closeTab(tester, id);
        expect(find.byKey(const Key('shell-close-protection')), findsOneWidget);
        expect(backend.closedSessionIds, isEmpty);
        expect(find.textContaining('pwd'), findsWidgets);
        await tester.tap(find.byKey(const Key('shell-close-copy-drafts')));
        await _settle(tester);
        expect(copied, contains('Keep this follow-up exactly'));
        await _cancel(tester);
        expect(container.read(sessionControllerProvider).activeSessionId, id);
        expect(ai.pending, same(proposal));
        expect(ai.proposalRevision, revision);
        expect(ai.phase, AiPhase.awaitingApproval);
        expect(ai.draft, 'Keep this follow-up exactly');
        expect(ai.attachments.single, same(source));
        expect(backend.submissions, isEmpty);
        expect(backend.closedSessionIds, isEmpty);
        await _closeTab(tester, id);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _settle(tester);
        expect(find.byKey(const Key('shell-close-protection')), findsNothing);
        expect(ai.pending, same(proposal));
        expect(backend.writes, isEmpty);
        await _closeTab(tester, id);
        await _confirm(tester);
        expect(backend.closedSessionIds, [id]);
        expect(container.read(sessionControllerProvider).tabs, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets('ordinary idle AI draft does not add a close confirmation', (
      tester,
    ) async {
      final backend = _Backend();
      final (:container, :id, profile: _) = await _pump(tester, backend);
      final ai = await _openAi(tester, id);
      ai.setDraft('Unsent idle draft');
      await _closeTab(tester, id);
      expect(find.byKey(const Key('shell-close-protection')), findsNothing);
      expect(backend.closedSessionIds, [id]);
      expect(container.read(sessionControllerProvider).tabs, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('tab warning aggregates actual running and unreviewed panes', (
      tester,
    ) async {
      final backend = _Backend();
      final (:container, :id, :profile) = await _pump(tester, backend);
      final ai = await _openAi(tester, id);
      await _propose(tester, ai);
      final controller = container.read(sessionControllerProvider.notifier);
      controller.splitSession(id, profile, TerminalSplitAxis.horizontal);
      await _settle(tester);
      final second = container.read(sessionControllerProvider).activeSessionId!;
      expect(second, isNot(id));
      await _running(tester, backend, container, second);
      await _closeTab(tester, id);
      final dialog = find.byKey(const Key('shell-close-protection'));
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.textContaining(id)),
        findsWidgets,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining(second)),
        findsWidgets,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining('sleep 600')),
        findsOneWidget,
      );
      await _cancel(tester);
      expect(
        container.read(sessionControllerProvider).tabs.single.effectivePanes,
        hasLength(2),
      );
      expect(ai.phase, AiPhase.awaitingApproval);
      expect(backend.closedSessionIds, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'a pane added while confirmation is open is never closed by it',
      (tester) async {
        final backend = _Backend();
        final (:container, :id, :profile) = await _pump(tester, backend);
        final ai = await _openAi(tester, id);
        await _propose(tester, ai);
        await _closeTab(tester, id);
        expect(find.byKey(const Key('shell-close-protection')), findsOneWidget);
        container
            .read(sessionControllerProvider.notifier)
            .splitSession(id, profile, TerminalSplitAxis.horizontal);
        await _settle(tester);
        await _confirm(tester);
        expect(backend.closedSessionIds, isEmpty);
        expect(
          container.read(sessionControllerProvider).tabs.single.effectivePanes,
          hasLength(2),
        );
        expect(ai.phase, AiPhase.awaitingApproval);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'unknown receipt in an older task is protected while current task is idle',
      (tester) async {
        final backend = _Backend();
        final (:container, :id, profile: _) = await _pump(tester, backend);
        final ai = await _openAi(tester, id);
        await ai.runUserCommand('printf once');
        expect(ai.hasUnresolvedSubmission, isTrue);
        ai.setDraft('Older task follow-up');
        final oldTask = ai.taskId;
        ai.newTask();
        expect(ai.hasUnresolvedSubmission, isFalse);
        await _closeTab(tester, id);
        expect(find.byKey(const Key('shell-close-protection')), findsOneWidget);
        await _cancel(tester);
        ai.selectTask(oldTask);
        expect(ai.hasUnresolvedSubmission, isTrue);
        expect(ai.draft, 'Older task follow-up');
        expect(backend.submissions, hasLength(1));
        expect(backend.closedSessionIds, isEmpty);
        expect(container.read(sessionControllerProvider).activeSessionId, id);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    for (final change in ['proposal', 'topology', 'attachment']) {
      testWidgets(
        '$change changes during recording finalization reject stale close and resume recording',
        (tester) async {
          final backend = _RecordingBackend();
          final recordings = _BlockingRecordingRepository();
          addTearDown(() {
            if (!recordings.allowSave.isCompleted) {
              recordings.allowSave.complete();
            }
          });
          final (:container, :id, :profile) = await _pump(
            tester,
            backend,
            recordingRepository: recordings,
          );
          final ai = await _openAi(tester, id);
          await _propose(tester, ai);
          ai.setDraft('Preserve after recording gate');
          final sessions = container.read(sessionControllerProvider.notifier);
          expect(await sessions.startSessionRecording(id), isTrue);
          await _closeTab(tester, id);
          await _confirm(tester);
          expect(recordings.saveStarted.isCompleted, isTrue);
          expect(backend.closedSessionIds, isEmpty);
          if (change == 'proposal') {
            ai.editPendingCommand(
              'printf updated',
              revision: ai.proposalRevision,
            );
            expect(ai.pending!.command, 'printf updated');
          } else if (change == 'topology') {
            sessions.splitSession(id, profile, TerminalSplitAxis.horizontal);
          } else {
            ai.attachContext(ai.context!.lastBlock!);
            expect(ai.attachments, hasLength(1));
          }
          final preserved = ai.pending;
          recordings.allowSave.complete();
          await _settle(tester);
          expect(backend.closedSessionIds, isEmpty);
          expect(ai.pending, same(preserved));
          expect(ai.phase, AiPhase.awaitingApproval);
          expect(ai.draft, 'Preserve after recording gate');
          final panes = container
              .read(sessionControllerProvider)
              .tabs
              .single
              .effectivePanes;
          expect(
            container.read(sessionControllerProvider).recordingSessionIds,
            contains(id),
          );
          expect(panes, hasLength(change == 'topology' ? 2 : 1));
          await tester.pumpWidget(const SizedBox.shrink());
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }

    testWidgets(
      'recording save rejection preserves the approved close target AI state',
      (tester) async {
        final backend = _RecordingBackend();
        final recordings = _BlockingRecordingRepository()..rejectSave = true;
        addTearDown(() {
          if (!recordings.allowSave.isCompleted) {
            recordings.allowSave.complete();
          }
        });
        final (:container, :id, profile: _) = await _pump(
          tester,
          backend,
          recordingRepository: recordings,
        );
        final ai = await _openAi(tester, id);
        await _propose(tester, ai);
        ai.setDraft('Unsaved follow-up');
        final pending = ai.pending;
        final revision = ai.proposalRevision;
        expect(
          await container
              .read(sessionControllerProvider.notifier)
              .startSessionRecording(id),
          isTrue,
        );
        await _closeTab(tester, id);
        await _confirm(tester);
        expect(recordings.saveStarted.isCompleted, isTrue);
        recordings.allowSave.complete();
        await _settle(tester);
        expect(backend.closedSessionIds, isEmpty);
        expect(ai.pending, same(pending));
        expect(ai.phase, AiPhase.awaitingApproval);
        expect(ai.proposalRevision, revision);
        expect(ai.draft, 'Unsaved follow-up');
        expect(container.read(sessionControllerProvider).activeSessionId, id);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'native partial tab close removes only successful panes and preserves failed pane AI',
      (tester) async {
        final backend = _Backend();
        final (:container, :id, :profile) = await _pump(tester, backend);
        final sessions = container.read(sessionControllerProvider.notifier);
        sessions.splitSession(id, profile, TerminalSplitAxis.horizontal);
        await _settle(tester);
        final second = container
            .read(sessionControllerProvider)
            .activeSessionId!;
        final ai = await _openAi(tester, second);
        await _propose(tester, ai);
        ai.setDraft('Keep failed pane');
        final proposal = ai.pending;
        backend.failingCloseSessionIds.add(second);
        await _closeTab(tester, id);
        await _confirm(tester);
        expect(backend.closedSessionIds, [id]);
        expect(
          container
              .read(sessionControllerProvider)
              .tabs
              .single
              .effectivePanes
              .map((pane) => pane.sessionId),
          [second],
        );
        expect(ai.pending, same(proposal));
        expect(ai.phase, AiPhase.awaitingApproval);
        expect(ai.draft, 'Keep failed pane');
        expect(container.read(sessionControllerProvider).lastError, isNotNull);
        backend.failingCloseSessionIds.clear();
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets('pane close protection targets only that pane', (tester) async {
      final backend = _Backend();
      final (:container, :id, :profile) = await _pump(tester, backend);
      final sessions = container.read(sessionControllerProvider.notifier);
      sessions.splitSession(id, profile, TerminalSplitAxis.horizontal);
      await _settle(tester);
      final second = container.read(sessionControllerProvider).activeSessionId!;
      final ai = await _openAi(tester, second);
      await _propose(tester, ai);
      await _closePane(tester, id);
      final dialog = find.byKey(const Key('shell-close-protection'));
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('Session $second'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('Session $id'),
        ),
        findsNothing,
      );
      await _confirm(tester);
      expect(backend.closedSessionIds, [second]);
      expect(
        container
            .read(sessionControllerProvider)
            .tabs
            .single
            .effectivePanes
            .single
            .sessionId,
        id,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
      'pane close repeats proposal check after recording finalization',
      (tester) async {
        final backend = _RecordingBackend();
        final recordings = _BlockingRecordingRepository();
        addTearDown(() {
          if (!recordings.allowSave.isCompleted) {
            recordings.allowSave.complete();
          }
        });
        final (:container, :id, profile: _) = await _pump(
          tester,
          backend,
          recordingRepository: recordings,
        );
        final ai = await _openAi(tester, id);
        await _propose(tester, ai);
        ai.setDraft('Keep pane draft');
        expect(
          await container
              .read(sessionControllerProvider.notifier)
              .startSessionRecording(id),
          isTrue,
        );
        await _closePane(tester, id);
        await _confirm(tester);
        expect(recordings.saveStarted.isCompleted, isTrue);
        ai.editPendingCommand(
          'printf changed-pane',
          revision: ai.proposalRevision,
        );
        final revised = ai.pending;
        recordings.allowSave.complete();
        await _settle(tester);
        expect(backend.closedSessionIds, isEmpty);
        expect(ai.pending, same(revised));
        expect(ai.draft, 'Keep pane draft');
        expect(
          container.read(sessionControllerProvider).recordingSessionIds,
          contains(id),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'disconnected mobile owner with unknown result can cancel removal',
      (tester) async {
        final backend = _Backend();
        final (:container, :id, profile: _) = await _pump(
          tester,
          backend,
          platform: TargetPlatform.iOS,
        );
        final ai = await _openAi(tester, id);
        await ai.runUserCommand('printf once');
        ai.setDraft('Unresolved mobile follow-up');
        backend.enqueueEvent(
          id,
          PtyEvent(kind: 'exit', sessionId: id, payload: {'code': 255}),
        );
        container.read(terminalRuntimeControllerProvider).refreshSession(id);
        await _settle(tester);
        await tester.tap(find.byKey(const Key('mobile-connections-back')));
        await _settle(tester);
        await tester.tap(
          find.byKey(const Key('mobile-sessions-disconnected-toggle')),
        );
        await _settle(tester);
        await tester.tap(find.byKey(Key('mobile-session-remove-$id')));
        await _settle(tester);
        expect(find.byKey(const Key('shell-close-protection')), findsOneWidget);
        await _cancel(tester);
        expect(ai.hasUnresolvedSubmission, isTrue);
        expect(ai.draft, 'Unresolved mobile follow-up');
        expect(
          container.read(sessionControllerProvider).tabs.single.isExited,
          isTrue,
        );
        expect(backend.closedSessionIds, isEmpty);
        expect(backend.submissions, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'late API reply after confirmed close cannot propose or write again',
      (tester) async {
        final backend = _Backend();
        final (:container, :id, profile: _) = await _pump(tester, backend);
        final ai = await _openAi(tester, id);
        final reply = Completer<Map<String, Object?>>();
        await HttpOverrides.runZoned(() async {
          final turn = ai.ask('Inspect the current directory');
          await _settle(tester);
          expect(ai.phase, AiPhase.thinking);
          await _closeTab(tester, id);
          await _confirm(tester);
          expect(backend.closedSessionIds, [id]);
          reply.complete(_commandResponse());
          await _settle(tester);
          await turn;
          expect(ai.pending, isNull);
          expect(backend.submissions, isEmpty);
          expect(backend.writes, isEmpty);
          expect(container.read(sessionControllerProvider).tabs, isEmpty);
        }, createHttpClient: (_) => _ModelClient((_) => reply.future));
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    for (final partial in [false, true]) {
      testWidgets(
        'asynchronous ${partial ? 'partial' : 'complete'} close preserves a newly opened modal focus',
        (tester) async {
          final backend = _RecordingBackend();
          final recordings = _BlockingRecordingRepository();
          addTearDown(() {
            if (!recordings.allowSave.isCompleted) {
              recordings.allowSave.complete();
            }
          });
          final (:container, :id, :profile) = await _pump(
            tester,
            backend,
            recordingRepository: recordings,
          );
          final sessions = container.read(sessionControllerProvider.notifier);
          final ai = await _openAi(tester, id);
          await _propose(tester, ai);
          if (partial) {
            sessions.splitSession(id, profile, TerminalSplitAxis.horizontal);
            await _settle(tester);
            backend.failingCloseSessionIds.add(
              container.read(sessionControllerProvider).activeSessionId!,
            );
          }
          expect(await sessions.startSessionRecording(id), isTrue);
          await _closeTab(tester, id);
          await _confirm(tester);
          expect(recordings.saveStarted.isCompleted, isTrue);
          final next = sessions.createSession(profile)!;
          await _settle(tester);
          final focus = FocusNode(debugLabel: 'New modal editor');
          addTearDown(focus.dispose);
          unawaited(
            showDialog<void>(
              context: tester.element(find.byType(ShellScreen)),
              builder: (context) => AlertDialog(
                title: const Text('Continue this edit'),
                content: TextField(
                  key: const Key('close-await-modal-editor'),
                  focusNode: focus,
                  autofocus: true,
                ),
              ),
            ),
          );
          await _settle(tester);
          expect(focus.hasFocus, isTrue);
          recordings.allowSave.complete();
          await _settle(tester);
          expect(backend.closedSessionIds, [id]);
          expect(
            container.read(sessionControllerProvider).activeSessionId,
            next,
          );
          expect(focus.hasFocus, isTrue);
          expect(FocusManager.instance.primaryFocus, same(focus));
          backend.failingCloseSessionIds.clear();
          Navigator.of(
            tester.element(find.byKey(const Key('close-await-modal-editor'))),
          ).pop();
          await _settle(tester);
          await tester.pumpWidget(const SizedBox.shrink());
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  });
}
