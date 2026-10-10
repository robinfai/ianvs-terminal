import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal_composer/composer_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart'
    show TerminalConnectionConfig;

import '../helpers/pump_app.dart';
import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';
import '../support/no_io_local_terminal_layout_repository.dart';
import 'terminal_ai_test.dart' show FakeApi, FakeTerminal, MemoryAiStore;

class _DeferredStore implements AiConfigurationStore {
  final result = Completer<AiConfiguration?>();
  AiConfiguration? saved;

  @override
  Future<AiConfiguration?> read() => result.future;

  @override
  Future<void> write(AiConfiguration? configuration) async {
    saved = configuration;
  }
}

class _Backend extends FakePtyBackend {
  final submissions = <String>[];
  final contextReads = <String>[];
  final leases = <String, String>{};

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
    if (request['kind'] == 'terminal.live_screen') contextReads.add(sessionId);
    if (request['kind'] == 'composer.submit') {
      submissions.add(sessionId);
      return jsonEncode({'outcome': 'rejected'});
    }
    return switch (request['kind']) {
      'composer.state' => jsonEncode({
        'state': 'ready',
        'lease': leases[sessionId] ?? 'lease-$sessionId',
        'contextId': 'root',
        'transport': 'shell',
        'cwd': '/srv/fixture',
        'dialect': 'bash',
      }),
      'terminal.live_screen' => jsonEncode({'text': 'fixture evidence'}),
      'terminal.command_blocks' => jsonEncode({'blocks': <Object>[]}),
      _ => super.requestSessionJson(sessionId, requestJson),
    };
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var index = 0; index < 6; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Fixture {
  final store = _DeferredStore();
  final backend = _Backend();
  late final settings = AiSettingsController(store);
  late TerminalAiController ai;
  late String sessionId;
  late ProviderContainer container;
  late TerminalProfile profile;

  Future<void> mount(WidgetTester tester, {bool keepAiOpen = false}) async {
    const size = Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.binding.setSurfaceSize(size);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      settings.dispose();
      if (!store.result.isCompleted) store.result.complete(null);
      await tester.pump();
      tester.view.reset();
      await tester.binding.setSurfaceSize(null);
    });
    profile = TerminalProfile(
      id: 'fixture',
      name: 'Fixture shell',
      shell: '',
      connection: const TerminalConnectionConfig.ssh(
        host: 'fixture.test',
        user: 'lab',
      ),
    );
    await tester.pumpApp(
      const ShellScreen(),
      platform: TargetPlatform.iOS,
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
            MemoryLocalTerminalConfigRepository(
              const LocalTerminalConfigDocument(
                defaultProfileId: 'fixture',
                appearance: TerminalAppAppearance(
                  preferredTerminalMode: TerminalViewMode.blocks,
                ),
              ),
            ),
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
        child: app,
      ),
    );
    await _settle(tester);
    container = ProviderScope.containerOf(
      tester.element(find.byType(ShellScreen)),
    );
    if (container.read(sessionControllerProvider).activeSessionId == null) {
      container.read(sessionControllerProvider.notifier).createSession(profile);
      await _settle(tester);
    }
    final state = container.read(sessionControllerProvider);
    expect(state.activeSessionId, isNotNull, reason: state.lastError);
    sessionId = state.activeSessionId!;
    await tester.tap(find.byKey(Key('terminal-ai-open-$sessionId')));
    await _settle(tester);
    final workspace = tester.widget<TerminalAiWorkspace>(
      find.byType(TerminalAiWorkspace),
    );
    ai = workspace.controller;
    if (!keepAiOpen) {
      workspace.onTakeOver!();
      await _settle(tester);
    }
    backend.writes.clear();
  }

  void sendFromComposer(WidgetTester tester, String prompt) {
    // Invoke the production callback installed on the real pane. This keeps
    // edits within the exact synchronous click / settings-await boundary.
    final pane = tester.widget<ComposerPane>(
      find.byKey(ValueKey('composer-$sessionId')),
    );
    expect(pane.onAskAi, isNotNull);
    pane.onAskAi!(prompt);
  }

  AiBlockContext source(String id) => AiBlockContext(
    id: id,
    command: 'printf $id',
    output: 'Evidence from $id',
    exitCode: 0,
    cwd: '/srv/fixture',
    sourceSessionId: sessionId,
    sourceContextId: 'root',
    sourceLineBase: 100,
    outputStartLine: 0,
    outputEndLine: 1,
    totalLines: 1,
  );
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

Map<String, Object?> _approvedResponse() => {
  'content': jsonEncode({
    'action_id': 'inspect-pwd',
    'decision': 'allow',
    'risk': 'low',
    'effect': 'read_only',
    'within_scope': true,
    'needs_confirmation': false,
    'reason': 'Requested directory inspection',
  }),
};

class _PendingContextTerminal extends FakeTerminal {
  final started = Completer<void>();
  final result = Completer<AiTerminalContext>();

  @override
  Future<AiTerminalContext> readContext() {
    started.complete();
    return result.future;
  }
}

void main() {
  for (final destination in ['connections home', 'another tab']) {
    for (final waitingFor in ['model', 'review']) {
      testWidgets(
        'background revokes $waitingFor after leaving AI for $destination',
        (tester) async {
          final deferred = Completer<Map<String, Object?>>();
          var requests = 0;
          await HttpOverrides.runZoned(
            () async {
              final fixture = _Fixture();
              await fixture.mount(tester, keepAiOpen: true);
              fixture.store.result.complete(
                const AiConfiguration.mock(approvalMode: AiApprovalMode.smart),
              );
              await _settle(tester);
              final turn = fixture.ai.ask('Inspect the current directory');
              await _settle(tester);
              expect(
                fixture.ai.phase,
                waitingFor == 'model' ? AiPhase.thinking : AiPhase.reviewing,
              );

              if (destination == 'connections home') {
                await tester.tap(
                  find.byKey(const Key('mobile-connections-back')),
                );
              } else {
                fixture.container
                    .read(sessionControllerProvider.notifier)
                    .createSession(fixture.profile);
              }
              await _settle(tester);
              expect(find.byType(TerminalAiWorkspace), findsNothing);
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.inactive,
              );
              await tester.pump();
              deferred.complete(
                waitingFor == 'model'
                    ? _commandResponse()
                    : _approvedResponse(),
              );
              await _settle(tester);
              await turn;
              expect(fixture.backend.submissions, isEmpty);
              expect(fixture.ai.busy, false);
              expect(fixture.ai.takenOver, true);
              expect(fixture.ai.pending, isNull);
              expect(fixture.backend.writes, isEmpty);
              final completedRequests = requests;
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.resumed,
              );
              await _settle(tester);
              expect(requests, completedRequests);
              expect(fixture.backend.submissions, isEmpty);
            },
            createHttpClient: (_) => _ModelClient((_) async {
              requests++;
              if (requests == (waitingFor == 'model' ? 1 : 2)) {
                return deferred.future;
              }
              return requests == 1 ? _commandResponse() : _approvedResponse();
            }),
          );
        },
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      );
    }
  }

  for (final changedTarget in [false, true]) {
    testWidgets(
      'all hidden proposals are revalidated once on resume (changed: $changedTarget)',
      (tester) async {
        await HttpOverrides.runZoned(
          () async {
            final fixture = _Fixture();
            await fixture.mount(tester, keepAiOpen: true);
            fixture.store.result.complete(const AiConfiguration.mock());
            await _settle(tester);
            final firstTurn = fixture.ai.ask('Inspect the first directory');
            await _settle(tester);
            await firstTurn;
            final firstProposal = fixture.ai.pending;
            expect(firstProposal, isNotNull);
            final secondId = fixture.container
                .read(sessionControllerProvider.notifier)
                .createSession(fixture.profile)!;
            await _settle(tester);
            await tester.tap(find.byKey(Key('terminal-ai-open-$secondId')));
            await _settle(tester);
            final second = tester
                .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
                .controller;
            final secondTurn = second.ask('Inspect the second directory');
            await _settle(tester);
            await secondTurn;
            final secondProposal = second.pending;
            expect(secondProposal, isNotNull);
            await tester.tap(find.byKey(const Key('mobile-connections-back')));
            await _settle(tester);
            expect(find.byType(TerminalAiWorkspace), findsNothing);

            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.hidden,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
            await tester.pump(const Duration(minutes: 30));
            expect(fixture.ai.pending, same(firstProposal));
            expect(second.pending, same(secondProposal));
            expect(fixture.ai.canApprove, false);
            expect(second.canApprove, false);
            await fixture.ai.approve();
            await second.approve();
            expect(fixture.backend.submissions, isEmpty);
            if (changedTarget) {
              fixture.backend.leases[fixture.sessionId] =
                  'new-foreground-lease';
            }
            fixture.backend.contextReads.clear();
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.hidden,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await _settle(tester);
            expect(
              fixture.backend.contextReads,
              unorderedEquals([fixture.sessionId, secondId]),
            );
            expect(
              fixture.ai.pending,
              changedTarget ? isNull : same(firstProposal),
            );
            expect(fixture.ai.canApprove, !changedTarget);
            expect(second.pending, same(secondProposal));
            expect(second.canApprove, true);
            expect(fixture.backend.submissions, isEmpty);
            expect(fixture.backend.writes, isEmpty);
          },
          createHttpClient: (_) =>
              _ModelClient((_) async => _commandResponse()),
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  testWidgets(
    'new hidden controller inherits inactive lifecycle',
    (tester) async {
      var requests = 0;
      await HttpOverrides.runZoned(
        () async {
          final fixture = _Fixture();
          await fixture.mount(tester);
          fixture.store.result.complete(const AiConfiguration.mock());
          await _settle(tester);
          final secondId = fixture.container
              .read(sessionControllerProvider.notifier)
              .createSession(fixture.profile)!;
          await _settle(tester);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          // A late UI callback can still create the workspace during a transition.
          tester
              .widget<ButtonStyleButton>(
                find.byKey(Key('terminal-ai-open-$secondId')),
              )
              .onPressed!();
          await _settle(tester);
          final second = tester
              .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
              .controller;
          await second.ask('Do not send this while inactive');
          expect(requests, 0);
          expect(second.transcript, isEmpty);
          expect(fixture.backend.submissions, isEmpty);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await _settle(tester);
          expect(requests, 0);
        },
        createHttpClient: (_) => _ModelClient((_) async {
          requests++;
          return _commandResponse();
        }),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Composer send freezes draft and sources before settings load',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      final original = fixture.source('original');
      final later = fixture.source('later');
      fixture.ai.attachContext(original);

      fixture.sendFromComposer(tester, 'Explain the original output');
      fixture.ai.setDraft('Keep my next question');
      fixture.ai.removeAttachment(0);
      fixture.ai.attachContext(later);
      fixture.store.result.complete(const AiConfiguration.mock());
      await _settle(tester);

      final user = fixture.ai.transcript.where((entry) => entry.role == 'user');
      expect(user, hasLength(1));
      expect(user.single.text, 'Explain the original output');
      expect(user.single.contexts, [original]);
      expect(fixture.ai.draft, 'Keep my next question');
      expect(fixture.ai.attachments, [later]);
      expect(fixture.backend.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Composer send cannot cross a task switch while loading settings',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      final originalTask = fixture.ai.taskId;
      fixture.sendFromComposer(tester, 'Original task request');
      fixture.ai.newTask();
      fixture.ai.setDraft('New task draft');
      fixture.store.result.complete(const AiConfiguration.mock());
      await _settle(tester);

      expect(fixture.ai.transcript, isEmpty);
      expect(fixture.ai.draft, 'New task draft');
      fixture.ai.selectTask(originalTask);
      await _settle(tester);
      expect(fixture.ai.transcript, isEmpty);
      expect(fixture.ai.draft, 'Original task request');
      expect(fixture.backend.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'taking over and reopening AI does not revive an old Composer send',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      fixture.sendFromComposer(tester, 'Canceled request');
      await _settle(tester);
      tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .onTakeOver!();
      await _settle(tester);
      await tester.tap(
        find.byKey(Key('terminal-ai-open-${fixture.sessionId}')),
      );
      await _settle(tester);
      fixture.store.result.complete(const AiConfiguration.mock());
      await _settle(tester);

      expect(fixture.ai.transcript, isEmpty);
      expect(fixture.ai.draft, 'Canceled request');
      expect(fixture.backend.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'missing configuration opens settings and saving does not send',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      final original = fixture.source('original');
      fixture.ai.attachContext(original);
      fixture.sendFromComposer(tester, 'Retain this unsent request');
      fixture.store.result.complete(null);
      await _settle(tester);
      expect(find.byKey(const Key('ai-settings-dialog')), findsOneWidget);
      expect(fixture.ai.transcript, isEmpty);

      for (final field in {
        'ai-endpoint': 'http://127.0.0.1:8787/v1',
        'ai-api-key': 'public-fixture-key',
        'ai-model': 'fixture',
      }.entries) {
        final input = find.byKey(Key(field.key));
        await tester.ensureVisible(input);
        await tester.enterText(input, field.value);
      }
      final save = find.byKey(const Key('ai-save-settings'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await _settle(tester);

      expect(find.byKey(const Key('ai-settings-dialog')), findsNothing);
      expect(fixture.store.saved, isNotNull);
      expect(fixture.ai.transcript, isEmpty);
      expect(fixture.ai.draft, 'Retain this unsent request');
      expect(fixture.ai.attachments, [original]);
      expect(fixture.backend.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'late missing settings do not open over a different task',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      fixture.sendFromComposer(tester, 'Old task request');
      fixture.ai.newTask();
      fixture.ai.setDraft('Current task draft');
      fixture.store.result.complete(null);
      await _settle(tester);

      expect(find.byKey(const Key('ai-settings-dialog')), findsNothing);
      expect(fixture.ai.transcript, isEmpty);
      expect(fixture.ai.draft, 'Current task draft');
      expect(fixture.backend.writes, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  test(
    'entry-point revocation after context await preserves the unsent draft',
    () async {
      final settings = AiSettingsController(MemoryAiStore());
      await settings.loaded;
      final terminal = _PendingContextTerminal();
      final api = FakeApi();
      final ai = TerminalAiController(
        settings: settings,
        terminal: terminal,
        api: api,
      );
      addTearDown(ai.dispose);
      addTearDown(settings.dispose);
      var valid = true;

      final submission = ai.ask('Original request', canStart: () => valid);
      await terminal.started.future;
      valid = false;
      terminal.result.complete(terminal.context);
      await submission;

      expect(api.requests, isEmpty);
      expect(terminal.writes, isEmpty);
      expect(ai.transcript, isEmpty);
      expect(ai.draft, 'Original request');
      expect(ai.busy, isFalse);
      expect(ai.takenOver, isTrue);
    },
  );
}
