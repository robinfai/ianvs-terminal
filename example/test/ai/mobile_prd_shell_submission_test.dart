import 'dart:async';
import 'dart:convert';

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
    return switch (request['kind']) {
      'composer.state' => jsonEncode({
        'state': 'ready',
        'lease': 'lease-$sessionId',
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

  Future<void> mount(WidgetTester tester) async {
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
    final profile = TerminalProfile(
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
    final container = ProviderScope.containerOf(
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
    workspace.onClose();
    await _settle(tester);
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
    'closing and reopening AI does not revive an old Composer send',
    (tester) async {
      final fixture = _Fixture();
      await fixture.mount(tester);
      fixture.sendFromComposer(tester, 'Canceled request');
      await _settle(tester);
      tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .onClose();
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
