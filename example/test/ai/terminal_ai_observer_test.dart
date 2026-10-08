import 'dart:async';
import 'dart:convert';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_observer.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
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
  Future<AiConfiguration?> read() async => null;
  @override
  Future<void> write(AiConfiguration? configuration) async {}
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
    final request = jsonDecode(requestJson) as Map;
    return switch (request['kind']) {
      'composer.state' => jsonEncode({
        'state': 'ready',
        'lease': 'lease-$sessionId',
        'contextId': 'root',
        'transport': 'shell',
        'cwd': '/srv/fixture',
        'dialect': 'bash',
      }),
      'terminal.live_screen' => jsonEncode({'text': 'fixture output'}),
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

Future<({String id, TerminalInputController previousInput})> _pump(
  WidgetTester tester,
  _Backend backend, {
  Size size = const Size(390, 844),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final settings = AiSettingsController(_Store());
  final profile = TerminalProfile(
    id: 'fixture',
    name: 'dev-box',
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
                preferredTerminalMode: TerminalViewMode.normal,
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
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    settings.dispose();
  });
  await _settle(tester);
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ShellScreen)),
  );
  if (container.read(sessionControllerProvider).activeSessionId == null) {
    container.read(sessionControllerProvider.notifier).createSession(profile);
    await _settle(tester);
  }
  expect(
    container.read(sessionControllerProvider).activeSessionId,
    isNotNull,
    reason: container.read(sessionControllerProvider).lastError,
  );
  final id = container.read(sessionControllerProvider).activeSessionId!;
  final input = tester
      .widget<TerminalViewport>(find.byType(TerminalViewport).first)
      .inputController;
  return (id: id, previousInput: input);
}

Future<TerminalAiController> _open(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('terminal-ai-open-$id')));
  await _settle(tester);
  return tester
      .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
      .controller;
}

void main() {
  testWidgets(
    'observer copies retained selection and Escape clears selection before returning',
    (tester) async {
      final viewport = TerminalViewportController()
        ..updateFrame(
          const TerminalFrameDiff(
            rows: [TerminalRow(index: 0, text: 'visible fragment')],
            viewportRows: 1,
            viewportCols: 24,
            cursor: TerminalCursor(row: 0, col: 0, visible: false),
            dirtyRanges: [],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
          ),
        );
      var backs = 0;
      String? retained;
      await tester.pumpApp(
        TerminalAiObserver(
          sessionId: 'fixture',
          targetLabel: 'fixture',
          viewport: viewport,
          onScrollLines: (_) {},
          onScrollToOffset: (_) {},
          onTakeOver: () => fail('Escape is never takeover'),
          onBack: () => backs++,
          readSelectionText: (selection, {required block}) => retained,
        ),
      );
      final view = tester.widget<TerminalViewport>(
        find.byKey(const Key('ai-observer-viewport')),
      );
      view.selectionController.setSelection(
        const TerminalSelection(
          startRow: 0,
          startCol: 0,
          endRow: 100,
          endCol: 4,
        ),
      );
      expect(
        view.inputController.readSelection(),
        '',
        reason: 'No partial visible-only copy',
      );
      retained = 'retained first page\nretained last page';
      expect(view.inputController.readSelection(), retained);
      const escape = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.escape,
        logicalKey: LogicalKeyboardKey.escape,
        timeStamp: Duration.zero,
      );
      expect(view.onHostKeyEvent!(escape), KeyEventResult.handled);
      expect(view.selectionController.selection, isNull);
      expect(backs, 0);
      view.onHostKeyEvent!(escape);
      expect(backs, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      viewport.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clipboard started before observation stays revoked after takeover',
    (tester) async {
      final backend = _Backend();
      final fixture = await _pump(tester, backend);
      final clipboard = Completer<Object?>();
      var reads = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            reads++;
            return clipboard.future;
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
      final pending = fixture.previousInput.pasteClipboard();
      await tester.pump();
      expect(reads, 1);
      await _open(tester, fixture.id);
      await tester.tap(find.byKey(const Key('ai-observe-terminal')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('ai-observer-take-over')));
      await _settle(tester);
      backend.writes.clear();
      clipboard.complete({'text': 'stale clipboard after takeover'});
      await pending;
      fixture.previousInput.sendText('stale callback after takeover');
      expect(backend.writes, isEmpty);
      final fresh = tester
          .widget<TerminalViewport>(find.byType(TerminalViewport).first)
          .inputController;
      fresh.sendText('new manual edit');
      expect(backend.writes.map(utf8.decode), ['new manual edit']);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'observing preserves task, selection and native geometry without writable callbacks',
    (tester) async {
      final backend = _Backend();
      final fixture = await _pump(tester, backend);
      final ai = await _open(tester, fixture.id);
      final workspaceState = tester.state(find.byType(TerminalAiWorkspace));
      await tester.enterText(find.byKey(const Key('ai-prompt')), '保留这个草稿 🧭');
      final editor = tester
          .widget<TextField>(find.byKey(const Key('ai-prompt')))
          .controller!;
      editor.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
      final saved = editor.value;
      final phase = ai.phase;
      await tester.tap(find.byKey(const Key('ai-observe-terminal')));
      await _settle(tester);
      expect(find.byType(TerminalAiObserver).hitTestable(), findsOneWidget);
      expect(find.byKey(const Key('ai-prompt')), findsNothing);
      expect(ai.takenOver, isFalse);
      expect(ai.phase, phase);
      final observer = tester.widget<TerminalViewport>(
        find.byKey(const Key('ai-observer-viewport')),
      );
      expect(observer.readOnly, isTrue);
      expect(observer.onMeasuredCellSizeChanged, isNull);
      expect(observer.onPasteClipboard, isNull);
      expect(observer.onActivateInlineButton, isNull);
      expect(
        observer.inputController.runtime,
        isNot(isA<TerminalRuntimeController>()),
      );
      final resizeCount = backend.resizeCalls.length;
      backend.writes.clear();
      const modes = TerminalFrameModes(
        focusTracking: true,
        mouseMode: 'any_event',
        mouseEncoding: 'sgr',
      );
      for (final input in [fixture.previousInput, observer.inputController]) {
        input.sendText('must not reach PTY');
        input.sendFocusReport(focused: true, modes: modes);
        input.sendMouseReport(
          modes: modes,
          row: 0,
          col: 0,
          button: 0,
          pressed: true,
        );
        await input.pasteClipboard();
      }
      await tester.tap(find.byKey(const Key('ai-observer-viewport')));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await _settle(tester);
      expect(backend.writes, isEmpty);
      expect(backend.resizeCalls, hasLength(resizeCount));
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.tap(find.byKey(const Key('ai-observer-back')));
      await _settle(tester);
      expect(
        tester.state(find.byType(TerminalAiWorkspace)),
        same(workspaceState),
      );
      expect(editor.value, saved);
      expect(ai.takenOver, isFalse);
      expect(backend.resizeCalls, hasLength(resizeCount));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'explicit take over revokes AI before restoring manual input and never interrupts',
    (tester) async {
      final backend = _Backend();
      final fixture = await _pump(tester, backend);
      final ai = await _open(tester, fixture.id);
      // Represent an in-flight model turn; terminal execution stays in the
      // fake backend, and takeover must revoke this owner without Ctrl+C.
      ai.phase = AiPhase.thinking;
      await tester.tap(find.byKey(const Key('ai-observe-terminal')));
      await _settle(tester);
      backend.writes.clear();
      await tester.tap(find.byKey(const Key('ai-observer-take-over')));
      await _settle(tester);
      expect(ai.takenOver, isTrue);
      expect(find.byType(TerminalAiWorkspace), findsNothing);
      expect(backend.writes, isEmpty, reason: 'Taking over is not Ctrl+C');
      final input = tester
          .widget<TerminalViewport>(find.byType(TerminalViewport).first)
          .inputController;
      input.sendText('manual input');
      expect(backend.writes.map(utf8.decode), ['manual input']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'iPad task and observer share one session and preserve draft across width threshold',
    (tester) async {
      final backend = _Backend();
      final fixture = await _pump(tester, backend, size: const Size(1024, 900));
      final ai = await _open(tester, fixture.id);
      final workspace = tester.state(find.byType(TerminalAiWorkspace));
      await tester.enterText(find.byKey(const Key('ai-prompt')), '保留选区与任务');
      final editor = tester
          .widget<TextField>(find.byKey(const Key('ai-prompt')))
          .controller!;
      editor.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
      final saved = editor.value;
      final observer = tester.widget<TerminalAiObserver>(
        find.byType(TerminalAiObserver),
      );
      expect(observer.sessionId, fixture.id);
      expect(find.byType(TerminalAiObserver).hitTestable(), findsOneWidget);
      expect(
        tester.getSize(find.byType(TerminalAiObserver)).width,
        greaterThanOrEqualTo(360),
      );
      expect(
        tester.getSize(find.byType(TerminalAiWorkspace)).width,
        greaterThanOrEqualTo(360),
      );
      tester.view.physicalSize = const Size(390, 844);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await _settle(tester);
      expect(find.byType(TerminalAiObserver), findsNothing);
      expect(tester.state(find.byType(TerminalAiWorkspace)), same(workspace));
      expect(editor.value, saved);
      expect(ai.takenOver, isFalse);
      tester.view.physicalSize = const Size(1024, 900);
      await tester.binding.setSurfaceSize(const Size(1024, 900));
      await _settle(tester);
      expect(find.byType(TerminalAiObserver).hitTestable(), findsOneWidget);
      expect(tester.state(find.byType(TerminalAiWorkspace)), same(workspace));
      expect(editor.value, saved);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
