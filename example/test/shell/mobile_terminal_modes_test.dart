import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_history_repository.dart';
import 'package:app/features/ai/terminal_ai_retained_timeline.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/terminal_composer/terminal_mode.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../ai/terminal_ai_test.dart' show MemoryAiStore;
import '../design/configuration_capture_binding.dart';
import '../design/visual_capture_fonts.dart';
import '../helpers/ai_workspace_actions.dart';
import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';
import '../support/no_io_local_terminal_layout_repository.dart';

const _evidence = String.fromEnvironment('MOBILE_BLOCKS_EVIDENCE_DIR');

// A loopback-only responder exercises the production completion lifecycle.
// Flutter's default widget-test HTTP override would otherwise return 400.
class _LoopbackHttpOverrides extends HttpOverrides {}

Future<void> _completeAiTask(
  WidgetTester tester,
  TerminalAiController ai, {
  bool throughInput = false,
}) async {
  final server = (await tester.runAsync(
    () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
  ))!;
  server.listen((request) async {
    await request.drain<void>();
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': '已完成只读分析，未执行任何清理。'},
          },
        ],
      }),
    );
    await request.response.close();
  });
  try {
    await ai.settings.save(
      AiConfiguration(
        endpoint: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'test-only',
        model: 'fixture',
      ),
    );
    var finished = false;
    final turn = throughInput
        ? HttpOverrides.runWithHttpOverrides(() async {
            await tester.enterText(
              find.byKey(const Key('ai-prompt')),
              '分析已有输出，只给建议。',
            );
            await _settle(tester);
            expect(ai.inputIntentDecision().intent, InputIntent.ai);
            await tester.tap(find.byKey(const Key('ai-send')));
          }, _LoopbackHttpOverrides())
        : HttpOverrides.runWithHttpOverrides(
            () => ai.ask('分析已有输出，只给建议。').whenComplete(() => finished = true),
            _LoopbackHttpOverrides(),
          );
    if (throughInput) await turn;
    // Keep widget-owned microtasks in their original fake-async zone while
    // allowing the loopback socket to make progress outside it.
    for (var attempt = 0; attempt < 100 && !finished; attempt++) {
      if (throughInput &&
          ai.transcript.any((entry) => entry.role == 'assistant') &&
          !ai.busy) {
        finished = true;
      }
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(finished, isTrue, reason: 'Loopback completion did not finish');
    await turn;
  } finally {
    await tester.runAsync(() => server.close(force: true));
  }
  await _settle(tester);
  expect(ai.phase, AiPhase.idle);
  expect(ai.transcript.last.text, '已完成只读分析，未执行任何清理。');
}

class _MobileBackend extends FakePtyBackend {
  String owner = 'draft';
  String contextId = 'root';
  int lineCount = 12;
  bool alternateScreen = false;
  final submissions = <String>[];
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
    if (request['kind'] == 'completion.query') {
      final query = Map<String, Object?>.of(request)..remove('kind');
      return jsonEncode({
        'schemaVersion': 1,
        'query': query,
        'status': 'ok',
        'items': <Object?>[],
      });
    }
    if (request['kind'] == 'completion.local_start') {
      return jsonEncode({'status': 'unsupported_context'});
    }
    if (request['kind'] == 'composer.state') {
      return jsonEncode({
        'state': owner,
        'lease': owner == 'ready'
            ? 'lease-$contextId-${submissions.length}'
            : null,
        'contextId': contextId,
        'transport': 'shell',
        'cwd': '/srv/app',
        'dialect': 'bash',
        'commandNames': ['echo', 'uname', 'vim'],
      });
    }
    if (request['kind'] == 'composer.submit') {
      submissions.add(request['text']! as String);
      return jsonEncode({'outcome': 'accepted'});
    }
    if (request['kind'] == 'composer.receipt') {
      return jsonEncode({
        'submissionId': request['submissionId'],
        'outcome': 'accepted',
        'blockId': '1',
      });
    }
    if (request['kind'] == 'terminal.live_screen') {
      return jsonEncode({
        'text': alternateScreen ? 'vim editor' : 'cloud shell',
        'alternateScreen': alternateScreen,
      });
    }
    if (request['kind'] == 'terminal.command_blocks') {
      final limit = request['limit'] as int? ?? 160;
      final offset =
          request['offset'] as int? ?? (lineCount - limit).clamp(0, lineCount);
      final block = {
        'id': '1',
        'command': alternateScreen ? 'vim notes.txt' : 'uname -a',
        'cwd': '/srv/app',
        'exitCode': owner == 'running' ? null : 0,
        'running': owner == 'running',
        'columns': 80,
        'totalLines': lineCount,
        'matchingLines': lineCount,
        'offset': offset,
        'lines': [
          for (var i = offset; i < (offset + limit).clamp(0, lineCount); i++)
            {
              'index': i,
              'source_row': 1000 + i,
              'text': 'cloud · output line ${i + 1}',
              'wrapped': false,
            },
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

class _InteractiveBackend extends _MobileBackend {
  bool receiptRunning = true;
  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    if (request['kind'] == 'composer.submit') owner = 'running';
    final result = super.requestSessionJson(sessionId, requestJson);
    if (request['kind'] == 'composer.receipt') {
      return jsonEncode({
        ...jsonDecode(result!) as Map,
        'running': receiptRunning,
      });
    }
    return result;
  }
}

class _CompletionBackend extends _MobileBackend {
  final completionRequests = <Map<String, Object?>>[];
  Map<String, Object?>? localQuery;
  bool delayLocal = false;
  int cancelled = 0;
  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = jsonDecode(requestJson) as Map<String, Object?>;
    switch (request['kind']) {
      case 'composer.state':
        final state =
            jsonDecode(super.requestSessionJson(sessionId, requestJson)!)
                as Map<String, Object?>;
        return jsonEncode({
          ...state,
          'commandNames': ['ls', 'echo', 'uname', 'vim'],
          'historyRevision': 1,
          'history': ['ls ./archive/', 'echo older command'],
        });
      case 'completion.query':
        completionRequests.add(request);
      case 'completion.local_start':
        localQuery = (request['query']! as Map).cast<String, Object?>();
        return jsonEncode({'status': 'pending', 'jobId': 'files'});
      case 'completion.local_cancel':
        cancelled++;
        return jsonEncode({'status': 'cancelled'});
      case 'completion.local_poll':
        if (delayLocal) return jsonEncode({'status': 'pending'});
        final query = localQuery!;
        return jsonEncode({
          'status': 'complete',
          'batch': {
            'schemaVersion': 1,
            'query': query,
            'status': 'ok',
            'items': query['text'] == 'ls ./'
                ? [
                    for (final name in ['alpha/', 'beta/'])
                      {
                        'itemId': name,
                        'label': name,
                        'detail': 'Directory',
                        'kind': 'directory',
                        'source': 'files',
                        'replaceStartUtf16': 3,
                        'replaceEndUtf16': 5,
                        'newText': './$name',
                        'finalCursorUtf16': 5 + name.length,
                        'riskHint': false,
                      },
                  ]
                : <Object?>[],
          },
        });
    }
    return super.requestSessionJson(sessionId, requestJson);
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _expectReadOnlyObservation(
  WidgetTester tester,
  _MobileBackend backend,
) async {
  final observer = find.byKey(const Key('ai-observer-viewport')).hitTestable();
  expect(observer, findsOneWidget);
  final viewport = tester.widget<TerminalViewport>(observer);
  expect(viewport.readOnly, isTrue);
  viewport.inputController.sendText('observation must not write');
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  expect(backend.writes, isEmpty);
  expect(backend.submissions, isEmpty);
}

Future<({ProviderContainer container, String id})> _pump(
  WidgetTester tester,
  _MobileBackend backend, {
  TargetPlatform platform = TargetPlatform.iOS,
  Brightness brightness = Brightness.light,
  Size size = const Size(390, 844),
  double scale = 1,
  TerminalViewMode? preference,
  AiConfiguration? configuration = const AiConfiguration.mock(),
  TerminalAiHistoryRepository? historyRepository,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    debugDefaultTargetPlatformOverride = null;
    tester.view.reset();
  });
  final profile = TerminalProfile(
    id: 'cloud',
    name: 'Cloud',
    shell: '',
    appearance: const TerminalDisplayConfig(
      font: TerminalFontConfig(family: 'monospace'),
    ),
    connection: const TerminalConnectionConfig.ssh(
      host: 'cloud.test',
      user: 'user',
    ),
  );
  var theme = buildIanvsTerminalTheme(brightness, platform: platform);
  if (_evidence.isNotEmpty) theme = withVisualCaptureFonts(theme);
  final aiSettings = AiSettingsController(MemoryAiStore(configuration));
  addTearDown(aiSettings.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aiSettingsProvider.overrideWithValue(aiSettings),
        if (historyRepository != null)
          terminalAiHistoryRepositoryProvider.overrideWithValue(
            historyRepository,
          ),
        ptySessionBackendProvider.overrideWithValue(backend),
        profileRepositoryProvider.overrideWithValue(
          MemoryProfileRepository(
            TerminalProfilesDocument(profiles: [profile]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(
            TerminalAppPreferencesDocument(
              appearance: TerminalAppAppearance(
                preferredTerminalMode: preference,
              ),
            ),
          ),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          MemoryLocalTerminalConfigRepository(
            LocalTerminalConfigDocument(
              appearance: TerminalAppAppearance(
                preferredTerminalMode: preference,
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
      child: RepaintBoundary(
        key: const Key('mobile-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const ShellScreen(),
        ),
      ),
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
  expect(
    container.read(sessionControllerProvider).activeSessionId,
    isNotNull,
    reason: container.read(sessionControllerProvider).lastError,
  );
  return (
    container: container,
    id: container.read(sessionControllerProvider).activeSessionId!,
  );
}

TerminalModeState _mode(ProviderContainer container) => container
    .read(sessionControllerProvider)
    .tabs
    .first
    .activePane
    .terminalMode;

Future<void> _choose(
  WidgetTester tester,
  String id,
  TerminalViewMode mode,
) async {
  if (_isPhone) {
    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
  } else {
    await tester.tap(
      find.byKey(Key('shell-tab-$id')),
      buttons: kSecondaryMouseButton,
    );
  }
  await _settle(tester);
  final item = find.byKey(Key('terminal-mode-${mode.name}-$id'));
  await tester.ensureVisible(item);
  await tester.tap(item);
  await _settle(tester);
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (_evidence.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('mobile-capture')),
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

bool get _isPhone =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

Finder _commandEditor(WidgetTester tester) =>
    find.byKey(const Key('ai-prompt'));

Future<void> _showWorkspace(WidgetTester tester, String id) async {
  if (find.byType(TerminalAiWorkspace).evaluate().isEmpty) {
    await tester.tap(find.byKey(Key('terminal-ai-open-$id')));
    await _settle(tester);
  }
}

void main() {
  ConfigurationCaptureBinding();
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('mobile search reserves terminal space at $size', (
      tester,
    ) async {
      final backend = _MobileBackend()..owner = 'ready';
      final (:container, :id) = await _pump(
        tester,
        backend,
        size: size,
        brightness: Brightness.dark,
        preference: TerminalViewMode.normal,
      );
      backend.setFrame(id, {
        'rows': [
          {'index': 0, 'text': 'MANUALQA'},
          {'index': 1, 'text': 'cloud shell prompt'},
        ],
        'viewport_rows': 24,
        'viewport_cols': 80,
      });
      backend.setSearchMatches(id, 'MANUALQA', [
        {'row': 0, 'start_col': 0, 'end_col': 8, 'text': 'MANUALQA'},
      ]);
      await _settle(tester);
      final viewportFinder = find.byType(TerminalViewport).hitTestable();
      final controller = tester
          .widget<TerminalViewport>(viewportFinder)
          .controller;
      final originalTop = tester.getRect(viewportFinder).top;
      await tester.tap(find.byKey(const Key('shell-search-scrollback-top')));
      await _settle(tester);
      await tester.enterText(
        find.byKey(const Key('terminal-search-field')),
        'MANUALQA',
      );
      await _settle(tester);
      for (final keyboard in [
        0.0,
        if (size.width > size.height) 120.0 else 300.0,
      ]) {
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        await _settle(tester);
        final search = tester.getRect(
          find.byKey(const Key('terminal-search-bar')),
        );
        final viewport = tester.getRect(viewportFinder);
        expect(viewport.top, greaterThanOrEqualTo(search.bottom));
        expect(viewport.height, greaterThan(20));
        expect(viewport.bottom, lessThanOrEqualTo(size.height - keyboard));
        expect(find.text('1/1'), findsOneWidget);
        expect(
          tester.widget<TerminalViewport>(viewportFinder).searchMatches,
          hasLength(1),
        );
        await tester.tap(find.byKey(const Key('terminal-search-next')));
        await _settle(tester);
        expect(
          tester.getRect(viewportFinder).top,
          greaterThanOrEqualTo(search.bottom),
        );
        expect(tester.takeException(), isNull);
      }
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.tap(find.byKey(const Key('terminal-search-close')));
      await _settle(tester);
      expect(find.byKey(const Key('terminal-search-bar')), findsNothing);
      expect(tester.getRect(viewportFinder).top, originalTop);
      expect(
        tester.widget<TerminalViewport>(viewportFinder).controller,
        same(controller),
      );
      expect(controller.frame.rows.first.text, 'MANUALQA');
      expect(backend.writes, isEmpty);
      expect(container.read(sessionControllerProvider).activeSessionId, id);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
  testWidgets(
    'late restart history switches Shell to archived native timeline',
    (tester) async {
      final history = _DelayedHistoryRepository();
      final backend = _MobileBackend()..owner = 'ready';
      final mounted = await _pump(tester, backend, historyRepository: history);
      final id = mounted.id;
      await _showWorkspace(tester, id);
      history.documents.complete([
        {
          'schema': 1,
          'id': 'saved-previous-task',
          'title': 'Previous task',
          'transcript': [
            {
              'id': 'old-message',
              'role': 'assistant',
              'text': 'Saved reply',
              'state': 'message',
            },
          ],
          'sources': {
            'saved-previous-source': [
              {
                'id': 'old-block',
                'command': 'pwd',
                'exitCode': 0,
                'running': false,
                'totalLines': 1,
                'lines': [
                  {'index': 0, 'text': 'saved output'},
                ],
              },
            ],
          },
        },
      ]);
      await _settle(tester);
      final workspace = tester.widget<TerminalAiWorkspace>(
        find.byType(TerminalAiWorkspace),
      );
      expect(workspace.controller.restoredHistory, isTrue);
      expect(find.byType(TerminalAiRetainedTimeline), findsOneWidget);
      expect(find.text('Saved reply'), findsOneWidget);
      expect(backend.submissions, isEmpty);
      expect(backend.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final preference in [null, TerminalViewMode.blocks]) {
      testWidgets(
        'mobile without LLM only offers Normal: $platform $preference',
        (tester) async {
          final backend = _MobileBackend()..owner = 'ready';
          final (:id, :container) = await _pump(
            tester,
            backend,
            platform: platform,
            configuration: null,
            preference: preference,
          );
          expect(_mode(container).mode, TerminalViewMode.normal);
          expect(
            _mode(container).unavailableReason,
            BlockUnavailableReason.llmRequired,
          );
          await tester.tap(find.byKey(const Key('shell-chrome-menu')));
          await _settle(tester);
          expect(
            tester
                .widget<ListTile>(find.byKey(Key('terminal-mode-blocks-$id')))
                .enabled,
            isFalse,
          );
          await tester.tap(find.byKey(Key('terminal-mode-recheck-$id')));
          await _settle(tester);
          expect(_mode(container).canUseBlocks, isFalse);
          await _showWorkspace(tester, id);
          await _settle(tester);
          expect(find.byKey(const Key('ai-settings-dialog')), findsOneWidget);
          expect(find.byType(TerminalAiWorkspace), findsNothing);
          expect(backend.submissions, isEmpty);
          await tester.pumpWidget(const SizedBox.shrink());
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
    testWidgets(
      'removing LLM revokes Blocks and retains command draft on $platform',
      (tester) async {
        final backend = _MobileBackend()..owner = 'ready';
        final (:id, :container) = await _pump(
          tester,
          backend,
          platform: platform,
        );
        expect(_mode(container).mode, TerminalViewMode.blocks);
        await tester.enterText(_commandEditor(tester), 'echo keep draft');
        final settings = container.read(aiSettingsProvider);
        await settings.save(null);
        await _settle(tester);
        expect(_mode(container).mode, TerminalViewMode.normal);
        expect(_mode(container).canUseBlocks, isFalse);
        await settings.save(const AiConfiguration.mock());
        await _settle(tester);
        // Capability restoration never silently changes the current input owner.
        expect(_mode(container).mode, TerminalViewMode.normal);
        await _choose(tester, id, TerminalViewMode.blocks);
        expect(
          tester.widget<TextField>(_commandEditor(tester)).controller!.text,
          'echo keep draft',
        );
        await _showWorkspace(tester, id);
        await _settle(tester);
        expect(find.byType(TerminalAiWorkspace), findsOneWidget);
        await settings.save(null);
        await _settle(tester);
        expect(find.byType(TerminalAiWorkspace), findsNothing);
        expect(_mode(container).mode, TerminalViewMode.normal);
        expect(backend.submissions, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      'unified command then AI uses one owner and draft on $platform',
      (tester) async {
        final backend = _MobileBackend()..owner = 'ready';
        final (:id, :container) = await _pump(
          tester,
          backend,
          platform: platform,
          preference: TerminalViewMode.blocks,
          size:
              platform == TargetPlatform.iOS ||
                  platform == TargetPlatform.android
              ? const Size(390, 844)
              : const Size(1200, 800),
        );
        final workspace = tester.widget<TerminalAiWorkspace>(
          find.byType(TerminalAiWorkspace),
        );
        final ai = workspace.controller;
        expect(workspace.unifiedWorkspace, isTrue);
        expect(
          find.byKey(const Key('ai-prompt')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('composer-editor')).hitTestable(),
          findsNothing,
        );
        expect(ai.transcript, isEmpty);
        expect(backend.submissions, isEmpty);
        await tester.enterText(
          find.byKey(const Key('ai-prompt')),
          'echo unified',
        );
        await _settle(tester);
        expect(ai.inputIntentDecision().intent, InputIntent.command);
        await tester.tap(find.byKey(const Key('ai-send')));
        await _settle(tester);
        expect(backend.submissions, ['echo unified']);
        expect(ai.transcript.single.state, AiEntryState.accepted);
        expect(ai.draft, isEmpty);
        expect(
          tester
              .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
              .controller,
          same(ai),
        );
        final task = ai.taskId;
        await _completeAiTask(tester, ai, throughInput: true);
        expect(ai.taskId, task);
        expect(backend.submissions, [
          'echo unified',
        ], reason: 'AI text must not execute as a command.');
        await tester.enterText(find.byKey(const Key('ai-prompt')), '中文草稿\n第二行');
        await _choose(tester, id, TerminalViewMode.normal);
        expect(find.byType(TerminalAiWorkspace), findsNothing);
        await _choose(tester, id, TerminalViewMode.blocks);
        expect(
          tester
              .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
              .controller,
          same(ai),
        );
        expect(ai.taskId, task);
        expect(ai.draft, '中文草稿\n第二行');
        expect(_mode(container).mode, TerminalViewMode.blocks);
        expect(backend.submissions, ['echo unified']);
        expect(backend.writes, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('desktop Blocks has no LLM prerequisite', (tester) async {
    final backend = _MobileBackend()..owner = 'ready';
    final (:container, :id) = await _pump(
      tester,
      backend,
      platform: TargetPlatform.macOS,
      configuration: null,
      preference: TerminalViewMode.blocks,
      size: const Size(1200, 800),
    );
    expect(_mode(container).mode, TerminalViewMode.blocks);
    await _showWorkspace(tester, id);
    await _settle(tester);
    expect(find.byType(TerminalAiWorkspace), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets('unified Composer Tab history undo and IME on $platform', (
      tester,
    ) async {
      final backend = _CompletionBackend()..owner = 'ready';
      await _pump(
        tester,
        backend,
        platform: platform,
        size: const Size(1200, 800),
        preference: TerminalViewMode.blocks,
      );
      final ai = tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .controller;
      final prompt = find.byKey(const Key('ai-prompt'));
      await tester.enterText(prompt, 'ls ./');
      await _settle(tester);
      expect(ai.inputIntentDecision().intent, InputIntent.command);
      expect(
        tester.widget<TextField>(prompt).focusNode!.hasFocus,
        isTrue,
        reason: 'focus before Tab',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);
      expect(
        find.byKey(const Key('composer-completion-list')).hitTestable(),
        findsOneWidget,
        reason:
            'query=${backend.localQuery} requests=${backend.completionRequests} focus=${tester.widget<TextField>(prompt).focusNode?.hasFocus} feedback=${tester.widgetList<Text>(find.byKey(const Key('ai-completion-feedback'))).map((e) => e.data)}',
      );
      expect(find.text('alpha/'), findsWidgets);
      expect(ai.draft, 'ls ./');
      expect(backend.submissions, isEmpty);
      await _capture(tester, 'unified-composer-completions-${platform.name}');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);
      expect(ai.draft, 'ls ./beta/');
      expect(
        backend.submissions,
        isEmpty,
        reason: 'Accepting a candidate never executes',
      );
      final modifier = platform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(modifier);
      await _settle(tester);
      expect(ai.draft, 'ls ./');
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(modifier);
      await _settle(tester);
      expect(ai.draft, 'ls ./beta/');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);
      expect(backend.submissions, ['ls ./beta/']);
      await tester.enterText(prompt, 'ls ./');
      await _settle(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _settle(tester);
      expect(
        find.byKey(const Key('composer-history-list')).hitTestable(),
        findsOneWidget,
      );
      await tester.enterText(prompt, 'archive');
      await _settle(tester);
      expect(tester.widget<TextField>(prompt).controller!.text, 'archive');
      expect(find.byKey(const Key('composer-history-list')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(ai.draft, 'ls ./');
      await tester.enterText(prompt, 'ls .');
      await tester.enterText(prompt, 'ls ./');
      await _settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _settle(tester);
      expect(
        ai.draft,
        'ls ./archive/',
        reason: 'Original history inline suggestion remains available',
      );
      expect(backend.submissions, hasLength(1));
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(modifier);
      await _settle(tester);
      expect(
        tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .commandSession!
            .blocks
            .activeId,
        '1',
      );
      expect(ai.draft, 'ls ./archive/');
      // Block navigation intentionally focuses the selected command block.
      await tester.tap(prompt);
      await _settle(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _settle(tester);
      expect(ai.draft, 'ls ./archive/\n');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _settle(tester);
      expect(ai.draft, isEmpty);
      expect(backend.writes, isEmpty);
      // Composing belongs to the IME, not completion or command submission.
      final editor = tester.widget<TextField>(prompt).controller!;
      editor.value = const TextEditingValue(
        text: 'ls ./zhong',
        selection: TextSelection.collapsed(offset: 10),
        composing: TextRange(start: 5, end: 10),
      );
      await _settle(tester);
      final count = backend.completionRequests.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);
      expect(backend.completionRequests, hasLength(count));
      expect(backend.submissions, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('AI workspace replay shelf remains interactive and semantic', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final backend = _CompletionBackend()..owner = 'ready';
    await _pump(
      tester,
      backend,
      platform: TargetPlatform.macOS,
      size: const Size(1400, 900),
      preference: TerminalViewMode.blocks,
    );
    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await _settle(tester);
    await tester.ensureVisible(find.byKey(const Key('shell-open-recording')));
    await tester.tap(find.byKey(const Key('shell-open-recording')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    final close = find.byKey(const Key('recording-library-close'));
    expect(close, findsOneWidget);
    expect(close.hitTestable(), findsOneWidget);
    expect(tester.getSemantics(close).label, isNotEmpty);
    await tester.tap(close);
    await _settle(tester);
    expect(close, findsNothing);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets('unified Composer action menu and empty history on $platform', (
      tester,
    ) async {
      final backend = _CompletionBackend()..owner = 'ready';
      await _pump(
        tester,
        backend,
        platform: platform,
        size: platform == TargetPlatform.iOS
            ? const Size(402, 874)
            : const Size(640, 400),
        preference: TerminalViewMode.blocks,
      );
      final workspace = tester.widget<TerminalAiWorkspace>(
        find.byType(TerminalAiWorkspace),
      );
      final ai = workspace.controller;
      final prompt = find.byKey(const Key('ai-prompt'));
      await tester.enterText(prompt, '');
      await _settle(tester);
      Future<void> action(String value) async {
        await tester.ensureVisible(find.byKey(const Key('ai-command-actions')));
        await tester.tap(find.byKey(const Key('ai-command-actions')));
        await _settle(tester);
        final item = find.byWidgetPredicate(
          (w) => w is PopupMenuItem<String> && w.value == value,
        );
        await tester.ensureVisible(item);
        await tester.tap(item);
        await _settle(tester);
      }

      if (platform == TargetPlatform.macOS) {
        await tester.ensureVisible(find.byKey(const Key('ai-command-actions')));
        await tester.tap(find.byKey(const Key('ai-command-actions')));
        await _settle(tester);
        expect(find.byType(PopupMenuItem<String>), findsWidgets);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _settle(tester);
        expect(find.byType(PopupMenuItem<String>), findsNothing);
        expect(tester.widget<TextField>(prompt).focusNode!.hasFocus, isTrue);
        expect(ai.draft, isEmpty);
        expect(backend.submissions, isEmpty);
      }
      await action('history');
      await _capture(tester, 'composer-history-${platform.name}');
      expect(
        find.byKey(const Key('composer-history-list')).hitTestable(),
        findsOneWidget,
        reason:
            'count=${find.byKey(const Key('composer-history-list')).evaluate().length} focus=${tester.widget<TextField>(prompt).focusNode!.hasFocus} intent=${ai.inputIntentDecision().intent} draft=${ai.draft}',
      );
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('ai-send'))).onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('ai-send')));
      await _settle(tester);
      expect(ai.draft, 'ls ./archive/');
      expect(backend.submissions, isEmpty);
      await action('clear');
      expect(ai.draft, isEmpty);
      await action('undo');
      expect(ai.draft, 'ls ./archive/');
      await action('redo');
      expect(ai.draft, isEmpty);
      await tester.enterText(prompt, 'ls ./');
      await _settle(tester);
      await action('suggest');
      expect(backend.localQuery?['text'], 'ls ./');
      expect(
        find.byKey(const Key('composer-completion-list')).hitTestable(),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      await action('help');
      expect(find.byKey(const Key('command-shortcuts-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('command-shortcuts-done')));
      await _settle(tester);
      expect(ai.draft, 'ls ./');
      expect(backend.submissions, isEmpty);
      expect(tester.widget<TextField>(prompt).focusNode!.hasFocus, isTrue);
      if (platform == TargetPlatform.macOS) {
        tester.view.physicalSize = const Size(1440, 1024);
        await _settle(tester);
        await _capture(tester, 'composer-refined-desktop');
        expect(ai.draft, 'ls ./');
        expect(tester.widget<TextField>(prompt).focusNode!.hasFocus, isTrue);
      }
      expect(backend.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('unified Composer running input is scoped and revoked', (
    tester,
  ) async {
    final backend = _InteractiveBackend()..owner = 'ready';
    await _pump(
      tester,
      backend,
      platform: TargetPlatform.macOS,
      size: const Size(1200, 800),
      preference: TerminalViewMode.blocks,
    );
    final workspace = tester.widget<TerminalAiWorkspace>(
      find.byType(TerminalAiWorkspace),
    );
    final ai = workspace.controller;
    TerminalCommandBlocksView timeline() =>
        tester.widget<TerminalCommandBlocksView>(
          find.byType(TerminalCommandBlocksView),
        );
    // An externally/AI-started command does not grant raw input to this UI.
    backend.owner = 'running';
    await ai.refreshContext();
    await _settle(tester);
    expect(timeline().liveInput, isNull);
    backend.owner = 'ready';
    await ai.refreshContext();
    await _settle(tester);
    final prompt = find.byKey(const Key('ai-prompt'));
    await tester.enterText(prompt, 'uname -a');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(backend.submissions, ['uname -a']);
    for (var attempt = 0; attempt < 200 && ai.busy; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await _settle(tester);
    expect(ai.busy, isFalse);
    expect(
      timeline().liveInput,
      isNotNull,
      reason:
          'phase=${ai.phase} changed=${ai.targetChanged} pending=${ai.pending} target=${ai.context?.contextId} entries=${ai.transcript.map((e) => '${e.state}:${e.submissionId}:${e.blockId}')}',
    );
    final input = timeline().liveInput!;
    input.sendText('hello');
    expect(utf8.decode(backend.writes.last), 'hello');
    final count = backend.writes.length;
    backend.receiptRunning = false;
    input.sendText('completed receipt');
    expect(backend.writes, hasLength(count));
    backend.receiptRunning = true;
    backend.contextId = 'another-shell';
    input.sendText('changed context');
    expect(backend.writes, hasLength(count));
    backend.contextId = 'root';
    workspace.onObserveTerminal!();
    input.sendText('stale before rebuild');
    expect(backend.writes, hasLength(count));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('ai-observer-back')));
    await _settle(tester);
    input.sendText('stale after return');
    expect(backend.writes, hasLength(count));
    final current = timeline().liveInput!;
    current.sendText('current');
    expect(utf8.decode(backend.writes.last), 'current');
    final nextCount = backend.writes.length;
    ai.chooseInputIntent(InputIntentChoice.ai);
    current.sendText('old input after AI selection');
    expect(backend.writes, hasLength(nextCount));
    await _settle(tester);
    await tester.enterText(prompt, 'Explain this running command');
    expect(ai.draft, 'Explain this running command');
    expect(timeline().liveInput, isNull);
    ai.chooseInputIntent(InputIntentChoice.command);
    await _settle(tester);
    current.sendText('old input after selecting command again');
    expect(backend.writes, hasLength(nextCount));
    final foreground = timeline().liveInput!;
    ai.suspendForBackground();
    foreground.sendText('background');
    expect(backend.writes, hasLength(nextCount));
    await ai.resumeFromBackground();
    foreground.sendText('stale after resume');
    expect(backend.writes, hasLength(nextCount));
    await _settle(tester);
    final resumed = timeline().liveInput!;
    ai.newTask();
    resumed.sendText('old task');
    expect(backend.writes, hasLength(nextCount));
    await _settle(tester);
    expect(timeline().liveInput, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'unified Composer rejects late results and isolates new-task undo',
    (tester) async {
      final backend = _CompletionBackend()
        ..owner = 'ready'
        ..delayLocal = true;
      final (:id, :container) = await _pump(
        tester,
        backend,
        platform: TargetPlatform.macOS,
        size: const Size(1200, 800),
        preference: TerminalViewMode.blocks,
      );
      final workspace = tester.widget<TerminalAiWorkspace>(
        find.byType(TerminalAiWorkspace),
      );
      final ai = workspace.controller;
      final prompt = find.byKey(const Key('ai-prompt'));
      await tester.enterText(prompt, 'ls ./');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 30));
      await tester.enterText(prompt, 'echo replacement');
      backend.delayLocal = false;
      await _settle(tester);
      expect(ai.draft, 'echo replacement');
      expect(
        find.byKey(const Key('composer-completion-list')).hitTestable(),
        findsNothing,
      );
      await tester.enterText(prompt, 'ls ./');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);
      final staleAccept = tester
          .widget<InkWell>(
            find
                .ancestor(
                  of: find.text('alpha/').first,
                  matching: find.byType(InkWell),
                )
                .first,
          )
          .onTap!;
      workspace.onObserveTerminal!();
      staleAccept();
      expect(ai.draft, 'ls ./');
      expect(backend.submissions, isEmpty);
      await _settle(tester);
      await tester.tap(find.byKey(const Key('ai-observer-back')));
      await _settle(tester);
      ai.chooseInputIntent(InputIntentChoice.ai);
      await _settle(tester);
      final count = backend.completionRequests.length;
      await tester.enterText(prompt, 'Explain this output');
      await _settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);
      expect(backend.completionRequests, hasLength(count));
      ai.newTask();
      await _settle(tester);
      await tester.tap(prompt);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await _settle(tester);
      expect(ai.draft, isEmpty);
      expect(backend.submissions, isEmpty);
      expect(backend.writes, isEmpty);
      expect(container.read(sessionControllerProvider).activeSessionId, id);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  for (final brightness in Brightness.values) {
    for (final (size, scale) in [
      (const Size(1200, 800), 1.0),
      (const Size(640, 400), 2.0),
    ]) {
      testWidgets(
        'desktop unified keyboard and layout $brightness $size scale $scale',
        (tester) async {
          final backend = _MobileBackend()..owner = 'ready';
          final (:id, :container) = await _pump(
            tester,
            backend,
            platform: TargetPlatform.macOS,
            brightness: brightness,
            size: size,
            scale: scale,
            preference: TerminalViewMode.blocks,
          );
          final workspace = tester.widget<TerminalAiWorkspace>(
            find.byType(TerminalAiWorkspace),
          );
          final ai = workspace.controller;
          expect(
            tester
                .widget<TextField>(_commandEditor(tester))
                .focusNode!
                .hasFocus,
            isTrue,
          );
          expect(
            find.byKey(const Key('composer-editor')).hitTestable(),
            findsNothing,
          );
          await tester.enterText(_commandEditor(tester), 'echo keyboard');
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await _settle(tester);
          expect(backend.submissions, ['echo keyboard']);
          await _completeAiTask(tester, ai, throughInput: true);
          await tester.enterText(_commandEditor(tester), 'echo draft');
          await _settle(tester);
          expect(ai.inputIntentDecision().intent, InputIntent.command);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await _settle(tester);
          expect(ai.inputIntentDecision().intent, InputIntent.ai);
          expect(backend.submissions, ['echo keyboard']);
          await tester.enterText(_commandEditor(tester), '中文草稿\n第二行');
          await _settle(tester);
          await _capture(
            tester,
            'desktop-unified-${brightness.name}-${size.width.toInt()}-scale-$scale',
          );
          await tester.tap(find.byKey(Key('terminal-ai-open-$id')));
          await _settle(tester);
          expect(
            find.byKey(const Key('ai-observer-viewport')).hitTestable(),
            findsOneWidget,
          );
          expect(ai.draft, '中文草稿\n第二行');
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await _settle(tester);
          expect(
            find.byKey(const Key('ai-prompt')).hitTestable(),
            findsOneWidget,
          );
          expect(
            tester
                .widget<TextField>(_commandEditor(tester))
                .focusNode!
                .hasFocus,
            isTrue,
          );
          expect(ai.draft, '中文草稿\n第二行');
          expect(container.read(sessionControllerProvider).activeSessionId, id);
          expect(backend.submissions, ['echo keyboard']);
          expect(backend.writes, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }

  testWidgets(
    'desktop unconfigured model still runs commands and configuration never sends a draft',
    (tester) async {
      final backend = _MobileBackend()..owner = 'ready';
      await _pump(
        tester,
        backend,
        platform: TargetPlatform.macOS,
        size: const Size(1200, 800),
        configuration: null,
        preference: TerminalViewMode.blocks,
      );
      final ai = tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .controller;
      await tester.enterText(_commandEditor(tester), 'echo no-model');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);
      expect(backend.submissions, ['echo no-model']);
      for (var i = 0; i < 5; i++) {
        await _settle(tester);
      }
      expect(ai.busy, isFalse);
      ai.chooseInputIntent(InputIntentChoice.ai);
      await tester.enterText(_commandEditor(tester), 'Explain the output');
      await _settle(tester);
      await tester.tap(find.byKey(const Key('ai-send')));
      await _settle(tester);
      expect(find.byKey(const Key('ai-settings-dialog')), findsOneWidget);
      expect(ai.draft, 'Explain the output');
      expect(backend.submissions, ['echo no-model']);
      expect(backend.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  group('AI evidence reinput', () {
    Future<void> insertEvidence(WidgetTester tester, String sourceId) async {
      tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .onShowEvidence!((
        id: '1',
        startLine: 0,
        endLine: 1,
        origins: [
          (
            id: '1',
            sessionId: sourceId,
            first: 0,
            last: 1,
            sourceLineBase: 1000,
          ),
        ],
      ));
      await _settle(tester);
      expect(find.byKey(const Key('block-reader')), findsOneWidget);
      await tester.tap(find.byKey(const Key('block-reader-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('放入 Composer 编辑'));
      await _settle(tester);
    }

    for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
      for (final reconnect in [false, true]) {
        testWidgets(
          'reveals and focuses the draft from Normal on ${platform.name} '
          '(reconnected: $reconnect)',
          (tester) async {
            final backend = _MobileBackend()..owner = 'ready';
            final (:id, :container) = await _pump(
              tester,
              backend,
              platform: platform,
              size: platform == TargetPlatform.macOS
                  ? const Size(1200, 800)
                  : const Size(390, 844),
              preference: TerminalViewMode.normal,
            );
            await _showWorkspace(tester, id);
            await _settle(tester);
            final ai = tester
                .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
                .controller;
            ai.setDraft('keep task draft');
            ai.attachContext(ai.context!.lastBlock!);
            final taskId = ai.taskId;
            var targetId = id;
            if (reconnect) {
              backend.enqueueEvent(
                id,
                PtyEvent(kind: 'exit', sessionId: id, payload: {'code': 255}),
              );
              container
                  .read(terminalRuntimeControllerProvider)
                  .refreshSession(id);
              await _settle(tester);
              final reconnectButton = find.byKey(
                Key(
                  platform == TargetPlatform.iOS
                      ? 'ai-mobile-primary-reconnect'
                      : 'ai-reconnect-terminal',
                ),
              );
              await tester.ensureVisible(reconnectButton);
              await tester.tap(reconnectButton);
              await _settle(tester);
              targetId = container
                  .read(sessionControllerProvider)
                  .activeSessionId!;
              expect(targetId, isNot(id));
            }
            final writes = backend.writes.length;
            await insertEvidence(tester, id);

            final state = container.read(sessionControllerProvider);
            final pane = state.tabs
                .expand((tab) => tab.effectivePanes)
                .singleWhere((pane) => pane.sessionId == targetId);
            expect(pane.terminalMode.mode, TerminalViewMode.blocks);
            expect(state.preferredTerminalMode, TerminalViewMode.normal);
            expect(state.activeSessionId, targetId);
            expect(find.byType(TerminalAiWorkspace), findsOneWidget);
            final editor = tester.widget<TextField>(_commandEditor(tester));
            expect(editor.controller!.text, 'uname -a');
            if (!_isPhone) {
              expect(
                editor.controller!.selection,
                const TextSelection.collapsed(offset: 8),
              );
              expect(editor.focusNode!.hasFocus, true);
            }
            expect(ai.taskId, taskId);
            expect(ai.draft, 'uname -a');
            expect(backend.writes, hasLength(writes));
            expect(backend.submissions, isEmpty);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            debugDefaultTargetPlatformOverride = null;
          },
        );
      }
    }

    testWidgets('keeps the shared draft when the editor is unavailable', (
      tester,
    ) async {
      final backend = _MobileBackend()..owner = 'ready';
      final (:id, :container) = await _pump(
        tester,
        backend,
        platform: TargetPlatform.macOS,
        size: const Size(1200, 800),
        preference: TerminalViewMode.blocks,
      );
      await tester.enterText(_commandEditor(tester), 'original command draft');
      await _showWorkspace(tester, id);
      await _settle(tester);
      final ai = tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .controller;
      ai.setDraft('keep task draft');
      backend.owner = 'draft';
      await _settle(tester);
      await insertEvidence(tester, id);

      expect(_mode(container).mode, TerminalViewMode.normal);
      expect(find.byType(TerminalAiWorkspace), findsOneWidget);
      expect(ai.draft, 'keep task draft');
      expect(find.text('正在检测 Shell 支持…'), findsWidgets);
      backend.owner = 'ready';
      await _settle(tester);
      await tester.tap(
        find.byKey(Key('shell-tab-$id')),
        buttons: kSecondaryMouseButton,
      );
      await _settle(tester);
      await tester.tap(find.byKey(Key('terminal-mode-blocks-$id')));
      await _settle(tester);
      expect(
        tester.widget<TextField>(_commandEditor(tester)).controller!.text,
        'keep task draft',
      );
      expect(backend.writes, isEmpty);
      expect(backend.submissions, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    for (final targetMode in TerminalViewMode.values) {
      testWidgets(
        'completed AI task returns to visible $targetMode on $platform',
        (tester) async {
          final backend = _MobileBackend()..owner = 'ready';
          final (:id, :container) = await _pump(
            tester,
            backend,
            platform: platform,
            size: platform == TargetPlatform.macOS
                ? const Size(1200, 800)
                : const Size(390, 844),
            preference: TerminalViewMode.blocks,
          );
          await tester.enterText(
            _commandEditor(tester),
            'retained command draft',
          );
          await _showWorkspace(tester, id);
          await _settle(tester);
          final ai = tester
              .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
              .controller;
          await _completeAiTask(tester, ai);
          await tester.enterText(
            find.byKey(const Key('ai-prompt')),
            'retained follow-up draft',
          );
          final task = ai.taskId;
          final transcript = ai.transcript;
          final sessionPayload = backend.lastCreatedSessionPayload;
          final writes = backend.writes.length;

          Future<void> choose(TerminalViewMode mode) async {
            if (platform == TargetPlatform.macOS) {
              await tester.tap(
                find.byKey(Key('shell-tab-$id')),
                buttons: kSecondaryMouseButton,
              );
              await _settle(tester);
              await tester.tap(
                find.byKey(Key('terminal-mode-${mode.name}-$id')),
              );
              await _settle(tester);
            } else {
              await _choose(tester, id, mode);
            }
          }

          await choose(targetMode);
          expect(_mode(container).mode, targetMode);
          expect(
            find.byType(TerminalAiWorkspace),
            targetMode == TerminalViewMode.blocks
                ? findsOneWidget
                : findsNothing,
          );
          if (targetMode == TerminalViewMode.normal) {
            final terminal = find.byType(TerminalViewport).hitTestable();
            expect(terminal, findsOneWidget);
            expect(
              tester.widget<TerminalViewport>(terminal).focusNode!.hasFocus,
              isTrue,
            );
            expect(_commandEditor(tester), findsNothing);
          } else {
            final editor = tester.widget<TextField>(
              _commandEditor(tester).hitTestable(),
            );
            expect(editor.controller!.text, 'retained follow-up draft');
            if (!_isPhone) expect(editor.focusNode!.hasFocus, isTrue);
          }
          await _showWorkspace(tester, id);
          await _settle(tester);
          final reopened = tester
              .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
              .controller;
          expect(reopened, same(ai));
          expect(reopened.taskId, task);
          expect(reopened.transcript, orderedEquals(transcript));
          expect(reopened.draft, 'retained follow-up draft');
          expect(reopened.phase, AiPhase.idle);

          // Selecting Normal again must work even when it is already checked.
          await choose(TerminalViewMode.normal);
          expect(find.byType(TerminalAiWorkspace), findsNothing);
          expect(find.byType(TerminalViewport).hitTestable(), findsOneWidget);
          expect(container.read(sessionControllerProvider).activeSessionId, id);
          expect(backend.lastCreatedSessionPayload, same(sessionPayload));
          expect(backend.closedSessionIds, isEmpty);
          expect(backend.writes, hasLength(writes));
          expect(backend.submissions, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }

  if (_evidence.isNotEmpty) setUpAll(loadVisualCaptureFonts);
  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets(
      'reduced motion session menus preserve input and grid on $platform',
      (tester) async {
        tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final backend = _MobileBackend()..owner = 'ready';
        final (:container, :id) = await _pump(
          tester,
          backend,
          platform: platform,
          size: platform == TargetPlatform.iOS
              ? const Size(390, 844)
              : const Size(1200, 850),
        );
        final writes = backend.writes.length;
        final resizes = backend.resizeCalls.length;
        final state = container.read(sessionControllerProvider);
        if (platform == TargetPlatform.macOS) {
          await tester.tap(
            find.byKey(Key('shell-tab-$id')),
            buttons: kSecondaryMouseButton,
          );
          await tester.pump();
          final item = find.byKey(Key('terminal-mode-normal-$id'));
          expect(
            ModalRoute.of(tester.element(item))!.animation!.isCompleted,
            true,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _settle(tester);
          expect(item, findsNothing);
        }
        await tester.tap(find.byKey(const Key('shell-chrome-menu')));
        await tester.pump();
        await tester.pump();
        final settings = find.byKey(const Key('shell-command-defaults'));
        expect(
          ModalRoute.of(tester.element(settings))!.animation!.isCompleted,
          true,
        );
        expect(backend.writes.length, writes);
        expect(backend.resizeCalls.length, resizes);
        await tester.ensureVisible(settings);
        await tester.tap(settings);
        for (var i = 0; i < 8; i++) {
          await tester.pump();
        }
        final save = find.byKey(const Key('defaults-save'));
        expect(save, findsOneWidget);
        if (platform == TargetPlatform.macOS) {
          expect(
            ModalRoute.of(tester.element(save))!.animation!.isCompleted,
            true,
          );
        }
        await _settle(tester);
        final defaultsContext = tester.element(save);
        Navigator.of(defaultsContext).pop();
        await _settle(tester);
        expect(
          container.read(sessionControllerProvider).activeSessionId,
          state.activeSessionId,
        );
        expect(backend.writes.length, writes);
        expect(backend.resizeCalls.length, resizes);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    testWidgets('SSH failure keeps AI draft and output on ${platform.name}', (
      tester,
    ) async {
      final backend = _MobileBackend()..owner = 'ready';
      final mounted = await _pump(
        tester,
        backend,
        platform: platform,
        size: platform == TargetPlatform.macOS
            ? const Size(1280, 800)
            : const Size(390, 844),
      );
      final id = mounted.id;
      final container = mounted.container;
      await _showWorkspace(tester, id);
      await _settle(tester);
      final ai = tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .controller;
      await tester.enterText(
        find.byKey(const Key('ai-prompt')),
        'Keep this SSH follow-up',
      );
      final evidence = ai.context!.lastBlock!;
      ai.attachContext(evidence);
      final taskId = ai.taskId;
      backend.enqueueEvent(
        id,
        PtyEvent(kind: 'exit', sessionId: id, payload: {'code': 255}),
      );
      final runtime = container.read(terminalRuntimeControllerProvider);
      runtime.refreshSession(id);
      await _settle(tester);
      expect(
        container
            .read(sessionControllerProvider)
            .tabs
            .single
            .activePane
            .isExited,
        true,
      );
      expect(find.byType(TerminalAiWorkspace), findsOneWidget);
      expect(
        tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .controller,
        same(ai),
      );
      expect(ai.taskId, taskId);
      expect(ai.draft, 'Keep this SSH follow-up');
      expect(ai.attachments, [evidence]);
      expect(ai.terminalError, 'session_unavailable');
      expect(ai.canApprove, false);
      expect(ai.canResume, false);
      expect(runtime.commandBlocks(id), isNotNull);
      expect(backend.submissions, isEmpty);
      expect(
        find.descendant(
          of: find.byType(TerminalAiWorkspace),
          matching: find.byKey(ValueKey('command-block-${evidence.id}')),
        ),
        findsOneWidget,
      );
      await _capture(tester, 'D10-ssh-disconnected-${platform.name}');
      await observeAiTerminal(
        tester,
        compactMobile: platform == TargetPlatform.iOS,
      );
      await _settle(tester);
      await _expectReadOnlyObservation(tester, backend);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('ai-observer-take-over')))
            .onPressed,
        isNull,
      );
      expect(ai.taskId, taskId);
      expect(ai.draft, 'Keep this SSH follow-up');
      expect(ai.attachments, [evidence]);
      await _showWorkspace(tester, id);
      await _settle(tester);
      expect(ai.draft, 'Keep this SSH follow-up');
      expect(ai.attachments, [evidence]);
      expect(tester.takeException(), isNull);
      final phone = platform == TargetPlatform.iOS;
      if (phone) {
        final details = find.byKey(const Key('ai-mobile-recovery-details'));
        final staleDetails = tester.widget<IconButton>(details).onPressed!;
        await tester.tap(details);
        staleDetails();
        await _settle(tester);
        expect(find.byKey(const Key('ai-mobile-details')), findsOneWidget);
      }
      final configure = find.byKey(
        Key(phone ? 'ai-mobile-detail-ssh-settings' : 'ai-terminal-settings'),
      );
      await tester.ensureVisible(configure);
      final staleConfigure = phone
          ? null
          : tester.widget<TextButton>(configure).onPressed;
      await tester.tap(configure);
      staleConfigure?.call();
      await _settle(tester);
      expect(find.byKey(const Key('ssh-host')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('ssh-host')),
        'cancelled-change.example.test',
      );
      await _capture(tester, 'D10-ssh-settings-${platform.name}');
      await tester.tap(
        platform == TargetPlatform.iOS
            ? find.byKey(const Key('ssh-mobile-back'))
            : find.byTooltip('取消'),
      );
      await _settle(tester);
      expect(container.read(sessionControllerProvider).activeSessionId, id);
      expect(container.read(sessionControllerProvider).tabs, hasLength(1));
      expect(ai.draft, 'Keep this SSH follow-up');
      expect(ai.attachments, [evidence]);
      expect(backend.submissions, isEmpty);
      final reconnect = find.byKey(
        Key(phone ? 'ai-mobile-primary-reconnect' : 'ai-reconnect-terminal'),
      );
      await tester.ensureVisible(reconnect);
      final staleReconnect = tester
          .widget<ButtonStyleButton>(reconnect)
          .onPressed;
      expect(staleReconnect, isNotNull);
      if (platform == TargetPlatform.iOS) {
        expect(tester.getSize(reconnect).height, greaterThanOrEqualTo(44));
      }
      await tester.tap(reconnect);
      // Exercise a late callback after transfer without targeting a stale
      // render tree before the next frame installs the successor pane.
      staleReconnect!();
      await _settle(tester);
      final reconnectedState = container.read(sessionControllerProvider);
      final next = reconnectedState.activeSessionId!;
      expect(next, isNot(id));
      expect(
        reconnectedState.tabs,
        hasLength(2),
        reason: 'Repeated reconnect does not create duplicate connections',
      );
      expect(
        tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .controller,
        same(ai),
      );
      expect(ai.context!.sessionId, next);
      expect(ai.draft, 'Keep this SSH follow-up');
      expect(ai.attachments, [evidence]);
      expect(backend.submissions, isEmpty);
      expect(runtime.isSessionRetainedAfterExit(id), true);
      expect(
        find.byKey(ValueKey('command-block-$id/${evidence.id}')),
        findsOneWidget,
      );
      await _capture(tester, 'D10-ssh-reconnected-${platform.name}');
      await container.read(sessionControllerProvider.notifier).closeSession(id);
      await _settle(tester);
      expect(find.byType(TerminalAiWorkspace), findsOneWidget);
      await container
          .read(sessionControllerProvider.notifier)
          .closeSession(next);
      await _settle(tester);
      expect(find.byType(TerminalAiWorkspace), findsNothing);
      expect(runtime.hasSession(id), false);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
  testWidgets(
    'phone can recheck current support without changing mode or task',
    (tester) async {
      final backend = _MobileBackend()..owner = 'ready';
      final (:id, :container) = await _pump(tester, backend);
      await tester.enterText(_commandEditor(tester), 'command draft');
      await _showWorkspace(tester, id);
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('ai-prompt')), 'task draft');
      backend.owner = 'draft';
      await _settle(tester);
      expect(_mode(container).mode, TerminalViewMode.normal);
      final grid = List<int>.of(backend.resizeCalls.last);
      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await _settle(tester);
      final recheck = find.byKey(Key('terminal-mode-recheck-$id'));
      expect(recheck, findsOneWidget);
      await tester.ensureVisible(recheck);
      await _capture(tester, 'M05-recheck-entry');
      await tester.tap(recheck);
      await _settle(tester);
      expect(_mode(container).canUseBlocks, false);
      expect(_mode(container).mode, TerminalViewMode.normal);
      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await _settle(tester);
      await _capture(tester, 'M05-recheck-unavailable');
      backend.owner = 'ready';
      await tester.tap(recheck);
      await _settle(tester);
      expect(_mode(container).canUseBlocks, true);
      expect(_mode(container).mode, TerminalViewMode.normal);
      expect(backend.resizeCalls.last, grid);
      expect(find.byType(TerminalAiWorkspace), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('ai-prompt')))
            .controller!
            .text,
        'task draft',
      );
      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await _settle(tester);
      expect(find.text('当前节点支持命令块。'), findsOneWidget);
      await _capture(tester, 'M05-recheck-supported');
      await tester.tap(find.byKey(Key('terminal-mode-blocks-$id')));
      await _settle(tester);
      expect(_mode(container).mode, TerminalViewMode.blocks);
      expect(find.byType(TerminalAiWorkspace), findsOneWidget);
      expect(
        tester.widget<TextField>(_commandEditor(tester)).controller!.text,
        'task draft',
      );
      expect(backend.writes, isEmpty);
      expect(backend.submissions, isEmpty);
      expect(container.read(sessionControllerProvider).activeSessionId, id);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets('phone reader touch selection returns to the retained AI task', (
    tester,
  ) async {
    final backend = _MobileBackend()
      ..owner = 'ready'
      ..lineCount = 800;
    final (:id, :container) = await _pump(tester, backend);
    expect(_mode(container).mode, TerminalViewMode.blocks);
    await tester.enterText(_commandEditor(tester), 'keep command draft');
    await _showWorkspace(tester, id);
    await _settle(tester);
    await tester.enterText(find.byKey(const Key('ai-prompt')), 'keep AI draft');
    final ai = tester
        .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
        .controller;
    expect(ai.context?.sessionId, id);
    final taskId = ai.taskId;
    await observeAiTerminal(tester);
    await _settle(tester);
    await _expectReadOnlyObservation(tester, backend);
    expect(ai.taskId, taskId);
    expect(ai.takenOver, isFalse);
    expect(ai.draft, 'keep AI draft');
    await tester.tap(
      find.byKey(const Key('ai-observer-take-over')).hitTestable(),
    );
    await _settle(tester);
    expect(find.byKey(const Key('ai-observer-viewport')), findsNothing);
    expect(ai.taskId, taskId);
    expect(ai.draft, 'keep AI draft');
    await _choose(tester, id, TerminalViewMode.blocks);
    await tester.tap(
      find
          .byKey(const ValueKey('block-expand-1'))
          .hitTestable()
          .last
          .hitTestable()
          .last,
    );
    await _settle(tester);
    expect(tester.testTextInput.isVisible, false);
    expect(_commandEditor(tester), findsNothing);
    expect(find.byKey(const Key('ai-prompt')), findsNothing);
    final reader = find.byKey(const Key('block-reader-scroll'));
    await tester.dragFrom(
      Offset(195, tester.getRect(reader).center.dy),
      const Offset(0, -360),
    );
    await tester.pumpAndSettle();
    final scroll = tester.widget<ListView>(reader).controller!;
    final savedOffset = scroll.offset;
    expect(savedOffset, greaterThan(200));
    final output = find.byType(CommandBlockTerminal).first;
    final viewportFinder = find.descendant(
      of: output,
      matching: find.byType(TerminalViewport),
    );
    final viewport = tester.widget<TerminalViewport>(viewportFinder);
    final cell = viewport.controller.measuredCellSize!;
    final top = tester.getTopLeft(viewportFinder);
    final visible = tester.getRect(reader);
    final row = ((visible.top - top.dy) / cell.height).ceil() + 3;
    final start = top + Offset(10 * cell.width, (row + .5) * cell.height);
    final gesture = await tester.startGesture(start);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveBy(Offset(4 * cell.width, 2 * cell.height));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await _settle(tester);
    final selection = tester
        .widget<CommandBlockTerminal>(output)
        .selectionController!
        .selection!;
    expect(selection.endRow - selection.startRow, 2);
    if (find.byKey(terminalTouchCopyMenuItemKey).evaluate().isNotEmpty) {
      await tester.tapAt(const Offset(10, 10));
      await _settle(tester);
    }
    await _capture(tester, 'M04-touch-selected');
    await tester.tap(find.byKey(const Key('block-reader-actions')));
    await _settle(tester);
    expect(find.text('复制全部保留输出'), findsOneWidget);
    expect(find.text('复制所选文本'), findsOneWidget);
    await _capture(tester, 'D08-reader-copy-actions');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.byKey(const Key('block-reader-scroll')), findsOneWidget);
    await tester.tap(find.byKey(const Key('block-reader-attach')));
    await _settle(tester);
    expect(find.byType(TerminalAiWorkspace), findsOneWidget);
    expect(ai.draft, 'keep AI draft');
    expect(
      ai.transcript,
      isEmpty,
      reason: 'Attaching must not send a question',
    );
    final attached = ai.attachments.single;
    expect(attached.outputStartLine, selection.startRow);
    expect(attached.outputEndLine, selection.endRow + 1);
    expect(attached.sourceLineBase, 1000);
    expect(
      attached.output,
      [
        for (var row = selection.startRow; row <= selection.endRow; row++)
          'cloud · output line ${row + 1}',
      ].join('\n'),
    );
    expect(backend.submissions, isEmpty);
    expect(backend.writes, isEmpty);
    await _capture(tester, 'M04-return-to-task');
    await tester.tap(
      find
          .byKey(const ValueKey('block-expand-1'))
          .hitTestable()
          .last
          .hitTestable(),
    );
    await _settle(tester);
    expect(
      tester.widget<ListView>(reader).controller!.offset,
      closeTo(savedOffset, .1),
    );
    final restored = tester
        .widget<CommandBlockTerminal>(find.byType(CommandBlockTerminal).first)
        .selectionController!
        .selection!;
    expect(restored.startRow, selection.startRow);
    expect(restored.endRow, selection.endRow);
    expect(restored.startCol, selection.startCol);
    expect(restored.endCol, selection.endCol);
    await tester.tap(find.byKey(const Key('block-reader-close')));
    await _settle(tester);
    expect(ai.draft, 'keep AI draft');
    expect(ai.attachments, [attached]);
    backend.enqueueEvent(
      id,
      PtyEvent(kind: 'exit', sessionId: id, payload: {'code': 255}),
    );
    container.read(terminalRuntimeControllerProvider).refreshSession(id);
    await _settle(tester);
    final reconnect = find.byKey(const Key('ai-mobile-primary-reconnect'));
    await tester.ensureVisible(reconnect);
    await tester.tap(reconnect);
    await _settle(tester);
    final nextId = container.read(sessionControllerProvider).activeSessionId!;
    expect(nextId, isNot(id));
    expect(ai.attachments.single.sourceSessionId, id);
    await tester.tap(find.byKey(ValueKey('block-expand-$id/1')).hitTestable());
    await _settle(tester);
    expect(
      tester.widget<ListView>(reader).controller!.offset,
      closeTo(savedOffset, .1),
    );
    final afterReconnect = tester
        .widget<CommandBlockTerminal>(find.byType(CommandBlockTerminal).first)
        .selectionController!
        .selection!;
    expect(afterReconnect.startRow, selection.startRow);
    expect(afterReconnect.endRow, selection.endRow);
    expect(afterReconnect.startCol, selection.startCol);
    expect(afterReconnect.endCol, selection.endCol);
    await _capture(tester, 'D10-reconnected-reader-selection');
    await tester.tap(find.byKey(const Key('block-reader-attach')));
    await _settle(tester);
    expect(ai.draft, 'keep AI draft');
    expect(ai.attachments.single.sourceSessionId, id);
    expect(ai.attachments.single.output, attached.output);
    expect(backend.submissions, isEmpty);
    await observeAiTerminal(tester);
    await _settle(tester);
    await _expectReadOnlyObservation(tester, backend);
    expect(ai.taskId, taskId);
    expect(ai.draft, 'keep AI draft');
    await tester.tap(
      find.byKey(const Key('ai-observer-take-over')).hitTestable(),
    );
    await _settle(tester);
    await _showWorkspace(
      tester,
      container.read(sessionControllerProvider).activeSessionId!,
    );
    expect(
      tester
          .widget<TextField>(_commandEditor(tester).hitTestable())
          .controller!
          .text,
      'keep AI draft',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
  for (final scene in [
    (
      name: 'portrait',
      size: const Size(390, 844),
      keyboard: 300.0,
      brightness: Brightness.light,
    ),
    (
      name: 'landscape',
      size: const Size(844, 390),
      keyboard: 180.0,
      brightness: Brightness.light,
    ),
    (
      name: 'short-dark',
      size: const Size(568, 320),
      keyboard: 160.0,
      brightness: Brightness.dark,
    ),
  ]) {
    testWidgets('phone TUI grid and input ownership ${scene.name}', (
      tester,
    ) async {
      final backend = _MobileBackend()..owner = 'ready';
      final (:id, :container) = await _pump(
        tester,
        backend,
        size: scene.size,
        brightness: scene.brightness,
      );
      await tester.enterText(_commandEditor(tester), 'retained before TUI');
      backend.owner = 'running';
      backend.alternateScreen = true;
      backend.setFrame(id, {
        'rows': [
          {'index': 0, 'text': 'vim editor'},
        ],
        'viewport_rows': 24,
        'viewport_cols': 80,
        'modes': {'alternate_screen': true},
      });
      await _settle(tester);
      expect(_mode(container).mode, TerminalViewMode.normal);
      // The read-only observer is a second projection of this same runtime.
      // Keep checking the original PTY viewport's geometry throughout.
      final viewport = find.byWidgetPredicate(
        (widget) =>
            widget is TerminalViewport &&
            widget.key != const Key('ai-observer-viewport'),
        description: 'original PTY viewport',
      );
      final fullSize = tester.getSize(viewport);
      final fullGrid = List<int>.of(backend.resizeCalls.last);
      await _showWorkspace(tester, id);
      await _settle(tester);
      expect(tester.getSize(viewport), fullSize);
      expect(backend.resizeCalls.last, fullGrid);
      expect(
        find.byKey(const Key('mobile-show-keyboard')).hitTestable(),
        findsNothing,
      );
      await observeAiTerminal(tester);
      await _settle(tester);
      await _expectReadOnlyObservation(tester, backend);
      expect(tester.getSize(viewport), fullSize);
      expect(backend.resizeCalls.last, fullGrid);
      await tester.tap(
        find.byKey(const Key('ai-observer-take-over')).hitTestable(),
      );
      await _settle(tester);
      tester.view.viewInsets = FakeViewPadding(bottom: scene.keyboard);
      await _settle(tester);
      final keyboardSize = tester.getSize(viewport);
      final keyboardGrid = List<int>.of(backend.resizeCalls.last);
      expect(keyboardSize.height, lessThan(fullSize.height));
      expect(find.byKey(const Key('ios-terminal-input-bar')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ios-terminal-key-Control C')));
      expect(backend.writes, [
        orderedEquals([3]),
      ]);
      backend.writes.clear();
      await _showWorkspace(tester, id);
      await _settle(tester);
      expect(tester.getSize(viewport), keyboardSize);
      expect(backend.resizeCalls.last, keyboardGrid);
      expect(
        find.byKey(const Key('ios-terminal-input-bar')).hitTestable(),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const Key('ai-prompt')),
        'explain this TUI',
      );
      await _settle(tester);
      expect(
        tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .controller
            .draft,
        'explain this TUI',
      );
      expect(
        tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .controller
            .context!
            .runningCommand,
        'vim notes.txt',
      );
      expect(find.byKey(const Key('ai-task-status')), findsOneWidget);
      expect(backend.writes, isEmpty);
      final prompt = find.byKey(const Key('ai-prompt'));
      final promptFocus = tester.widget<TextField>(prompt).focusNode!;
      final promptSelection = tester
          .widget<TextField>(prompt)
          .controller!
          .selection;
      expect(promptFocus.hasFocus, isTrue);
      tester.view.viewInsets = FakeViewPadding.zero;
      await _settle(tester);
      expect(tester.getSize(viewport), fullSize);
      expect(promptFocus.hasFocus, isFalse);
      expect(
        tester.getSize(find.byKey(const Key('ai-mobile-composer'))).height,
        lessThanOrEqualTo(56),
      );
      expect(
        tester.widget<TextField>(prompt).controller!.selection,
        promptSelection,
      );
      await tester.showKeyboard(prompt);
      tester.view.viewInsets = FakeViewPadding(bottom: scene.keyboard);
      await _settle(tester);
      expect(tester.getSize(viewport), keyboardSize);
      expect(promptFocus.hasFocus, isTrue);
      expect(
        tester.widget<TextField>(prompt).controller!.selection,
        promptSelection,
      );
      expect(
        tester.widget<TextField>(prompt).controller!.text,
        'explain this TUI',
      );
      for (final key in ['ai-mobile-task-menu', 'ai-send']) {
        final button = find.byKey(Key(key));
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      }
      await openAiMobileTaskMenu(tester);
      final newTask = find.byKey(const Key('ai-new-task'));
      expect(newTask.hitTestable(), findsOneWidget);
      expect(tester.getSize(newTask).height, greaterThanOrEqualTo(44));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'M06-${scene.name}-ai-keyboard');
      await tester.tap(find.byKey(const Key('ai-dismiss-keyboard')));
      await _settle(tester);
      expect(promptFocus.hasFocus, isFalse);
      expect(find.byType(TerminalAiWorkspace), findsOneWidget);
      expect(backend.writes, isEmpty);
      tester.view.viewInsets = FakeViewPadding.zero;
      await _settle(tester);
      expect(tester.getSize(viewport), fullSize);
      expect(
        tester.widget<TextField>(prompt).controller!.text,
        'explain this TUI',
      );
      await _capture(tester, 'M06-${scene.name}-keyboard-dismissed');
      final ai = tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .controller;
      final taskId = ai.taskId;
      final phase = ai.phase;
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(tester.getSize(viewport), fullSize);
      expect(backend.resizeCalls.last, fullGrid);
      expect(backend.writes, isEmpty);
      expect(find.byType(TerminalAiWorkspace), findsNothing);
      final observer = find.byKey(const Key('ai-observer-viewport'));
      expect(observer.hitTestable(), findsOneWidget);
      final observed = tester.widget<TerminalViewport>(observer);
      expect(observed.readOnly, isTrue);
      expect(observed.focusNode!.hasFocus, isTrue);
      expect(ai.phase, phase);
      expect(ai.taskId, taskId);
      expect(ai.draft, 'explain this TUI');
      expect(
        tester
            .widget<TerminalAiWorkspace>(
              find.byType(TerminalAiWorkspace, skipOffstage: false),
            )
            .controller,
        same(ai),
      );
      observed.selectionController.setSelection(
        const TerminalSelection(startRow: 0, startCol: 0, endRow: 0, endCol: 3),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(observed.selectionController.selection, isNull);
      expect(observer.hitTestable(), findsOneWidget);
      expect(ai.phase, phase);
      expect(backend.writes, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(observer.hitTestable(), findsNothing);
      expect(find.byType(TerminalAiWorkspace), findsOneWidget);
      expect(ai.phase, phase);
      expect(ai.taskId, taskId);
      expect(ai.draft, 'explain this TUI');
      expect(backend.writes, isEmpty);
      // Only the explicit takeover control returns raw keyboard ownership.
      await observeAiTerminal(tester);
      await _settle(tester);
      await _expectReadOnlyObservation(tester, backend);
      expect(ai.phase, phase);
      expect(ai.taskId, taskId);
      await tester.tap(
        find.byKey(const Key('ai-observer-take-over')).hitTestable(),
      );
      await _settle(tester);
      expect(observer.hitTestable(), findsNothing);
      expect(find.byType(TerminalAiWorkspace), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(backend.writes, [
        orderedEquals([27]),
      ]);
      backend.writes.clear();
      backend.owner = 'ready';
      backend.alternateScreen = false;
      backend.setFrame(id, {
        'rows': [
          {'index': 0, 'text': 'shell> '},
        ],
        'viewport_rows': fullGrid[2],
        'viewport_cols': fullGrid[1],
      });
      await _settle(tester);
      expect(_mode(container).mode, TerminalViewMode.normal);
      expect(_mode(container).notice, TerminalModeNotice.blocksRestored);
      await _capture(tester, 'M06-${scene.name}-manual-restoration');
      await _choose(tester, id, TerminalViewMode.blocks);
      expect(
        tester.widget<TextField>(_commandEditor(tester)).controller!.text,
        'explain this TUI',
      );
      expect(backend.writes, isEmpty);
      expect(backend.submissions, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }
  testWidgets(
    'phone session menu preserves the AI task through capability changes',
    (tester) async {
      final backend = _MobileBackend()..owner = 'ready';
      final (:id, :container) = await _pump(tester, backend);
      await tester.enterText(_commandEditor(tester), 'command draft');
      await _showWorkspace(tester, id);
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('ai-prompt')), 'task draft');
      final ai = tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .controller;
      final grid = List<int>.of(backend.resizeCalls.last);
      final resizeCount = backend.resizeCalls.length;
      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await _settle(tester);
      expect(backend.resizeCalls, hasLength(resizeCount));
      expect(backend.resizeCalls.last, grid);
      await _capture(tester, 'M05-task-session-menu');
      await tester.tap(find.byKey(Key('terminal-mode-normal-$id')));
      await _settle(tester);
      expect(_mode(container).mode, TerminalViewMode.normal);
      expect(ai.draft, 'task draft');
      expect(find.byType(TerminalAiWorkspace), findsNothing);
      await _showWorkspace(tester, id);
      await _settle(tester);
      await _choose(tester, id, TerminalViewMode.blocks);
      expect(_mode(container).mode, TerminalViewMode.blocks);
      expect(find.byType(TerminalAiWorkspace), findsOneWidget);
      await _showWorkspace(tester, id);
      await _settle(tester);
      backend.owner = 'draft';
      backend.enqueueEvent(
        id,
        PtyEvent(
          kind: 'shell_hook',
          sessionId: id,
          payload: {
            'hook': 'bootstrap.checking',
            'context_id': 'hop',
            'parent_context_id': 'root',
            'context_kind': 'ssh',
            'host_context_id': 'hop',
          },
        ),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await _settle(tester);
      final blocks = find.byKey(Key('terminal-mode-blocks-$id'));
      final disabled = tester.widget<ListTile>(blocks);
      expect(disabled.enabled, false);
      expect(disabled.subtitle, isNotNull);
      await _capture(tester, 'M05-task-capability-reason');
      backend.contextId = 'hop';
      backend.owner = 'ready';
      await _settle(tester);
      expect(_mode(container).mode, TerminalViewMode.blocks);
      expect(_mode(container).notice, isNull);
      expect(tester.widget<ListTile>(blocks).enabled, true);
      expect(ai.draft, 'task draft');
      await tester.tap(blocks);
      await _settle(tester);
      expect(_mode(container).mode, TerminalViewMode.blocks);
      expect(ai.draft, 'task draft');
      expect(ai.transcript, isEmpty);
      expect(find.byType(TerminalAiWorkspace), findsOneWidget);
      await _showWorkspace(tester, id);
      await _settle(tester);
      expect(
        tester.widget<TextField>(_commandEditor(tester)).controller!.text,
        'task draft',
      );
      expect(backend.writes, isEmpty);
      expect(backend.submissions, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      '${platform.name} negotiates Blocks and preserves manual Normal',
      (tester) async {
        final backend = _MobileBackend();
        final (:container, :id) = await _pump(
          tester,
          backend,
          platform: platform,
        );
        expect(
          container.read(sessionControllerProvider).preferredTerminalMode,
          TerminalViewMode.blocks,
        );
        expect(_mode(container).mode, TerminalViewMode.normal);
        expect(find.byType(TerminalComposerView), findsNothing);
        await tester.tap(find.byKey(const Key('shell-chrome-menu')));
        await _settle(tester);
        final blocksItem = find.byKey(Key('terminal-mode-blocks-$id'));
        expect(tester.widget<ListTile>(blocksItem).enabled, isFalse);
        // The open sheet must reflect the negotiation result without reopening.
        backend.owner = 'ready';
        await _settle(tester);
        expect(_mode(container).mode, TerminalViewMode.blocks);
        expect(tester.widget<ListTile>(blocksItem).enabled, isTrue);
        final normalItem = find.byKey(Key('terminal-mode-normal-$id'));
        expect(tester.getSize(normalItem).height, greaterThanOrEqualTo(48));
        await _capture(tester, '${platform.name}-menu');
        await tester.tap(normalItem);
        await _settle(tester);
        backend.owner = 'draft';
        await _settle(tester);
        backend.owner = 'ready';
        await _settle(tester);
        expect(_mode(container).mode, TerminalViewMode.normal);
        await _choose(tester, id, TerminalViewMode.blocks);
        await tester.enterText(_commandEditor(tester), 'echo 移动端');
        expect(backend.writes, isEmpty);
        await _choose(tester, id, TerminalViewMode.normal);
        await _choose(tester, id, TerminalViewMode.blocks);
        final editor = tester.widget<TextField>(_commandEditor(tester));
        expect(editor.controller!.text, 'echo 移动端');
        await tester.tap(_commandEditor(tester));
        expect(editor.focusNode!.hasFocus, isTrue);
        await tester.tap(
          find.byKey(Key(_isPhone ? 'ai-send' : 'composer-primary-action')),
        );
        await _settle(tester);
        expect(backend.submissions, ['echo 移动端']);
        expect(backend.writes, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('SSH restores Blocks; fullscreen restoration stays manual', (
    tester,
  ) async {
    final backend = _MobileBackend()..owner = 'ready';
    final (:container, :id) = await _pump(tester, backend);
    expect(_mode(container).mode, TerminalViewMode.blocks);
    await tester.enterText(_commandEditor(tester), 'saved draft');
    backend.owner = 'draft';
    backend.enqueueEvent(
      id,
      PtyEvent(
        kind: 'shell_hook',
        sessionId: id,
        payload: {
          'hook': 'bootstrap.checking',
          'context_id': 'hop',
          'parent_context_id': 'root',
          'context_kind': 'ssh',
          'host_context_id': 'hop',
        },
      ),
    );
    await _settle(tester);
    expect(_mode(container).mode, TerminalViewMode.normal);
    expect(_mode(container).canUseBlocks, isFalse);
    expect(
      tester
          .widget<Badge>(find.byKey(const Key('mobile-terminal-mode-notice')))
          .isLabelVisible,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await _settle(tester);
    expect(
      tester
          .widget<ListTile>(find.byKey(Key('terminal-mode-blocks-$id')))
          .enabled,
      isFalse,
    );
    await _capture(tester, 'ios-fallback');
    backend.contextId = 'hop';
    backend.owner = 'ready';
    await _settle(tester);
    expect(_mode(container).mode, TerminalViewMode.blocks);
    expect(_mode(container).notice, isNull);
    await tester.tap(find.byKey(Key('terminal-mode-blocks-$id')));
    await _settle(tester);
    await _showWorkspace(tester, id);
    backend.owner = 'running';
    backend.alternateScreen = true;
    backend.setFrame(id, {
      'rows': [
        {'index': 0, 'text': 'top — process list'},
      ],
      'viewport_rows': 24,
      'viewport_cols': 80,
      'modes': {'alternate_screen': true},
    });
    await _settle(tester);
    expect(_mode(container).mode, TerminalViewMode.normal);
    expect(
      _mode(container).unavailableReason,
      BlockUnavailableReason.fullScreen,
    );
    expect(find.byType(TerminalComposerView), findsNothing);
    expect(find.byType(TerminalCommandBlocksView), findsNothing);
    if (find
        .byKey(const Key('ai-observer-viewport'))
        .hitTestable()
        .evaluate()
        .isEmpty) {
      await observeAiTerminal(tester);
      await _settle(tester);
    }
    await _expectReadOnlyObservation(tester, backend);
    await tester.tap(find.byKey(const Key('ai-observer-take-over')));
    await _settle(tester);
    expect(
      tester
          .widget<TerminalViewport>(find.byType(TerminalViewport))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    backend.setFrame(id, {
      'rows': <Object?>[],
      'viewport_rows': 24,
      'viewport_cols': 80,
    });
    backend.owner = 'ready';
    backend.alternateScreen = false;
    await _settle(tester);
    expect(_mode(container).mode, TerminalViewMode.normal);
    expect(_mode(container).canUseBlocks, isTrue);
    await _choose(tester, id, TerminalViewMode.blocks);
    expect(
      tester.widget<TextField>(_commandEditor(tester)).controller!.text,
      'saved draft',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'main-screen application modes fall back without an alternate buffer',
    (tester) async {
      final backend = _MobileBackend()..owner = 'ready';
      final (:container, :id) = await _pump(tester, backend);
      // Prompt editors may use application keys; a prompt alone is not a TUI.
      backend.setFrame(id, {
        'rows': <Object?>[],
        'viewport_rows': 24,
        'viewport_cols': 80,
        'modes': {
          'application_cursor': true,
          'application_keypad': true,
          'hide_cursor': true,
        },
      });
      await _settle(tester);
      expect(_mode(container).mode, TerminalViewMode.blocks);
      backend.owner = 'running';
      // Progress output hiding only its cursor remains a normal command block.
      backend.setFrame(id, {
        'rows': <Object?>[],
        'viewport_rows': 24,
        'viewport_cols': 80,
        'modes': {'hide_cursor': true},
      });
      await _settle(tester);
      expect(_mode(container).mode, TerminalViewMode.blocks);
      // Linux procps top uses DECCKM, DECKPAM and DECTCEM on the main buffer.
      backend.setFrame(id, {
        'rows': [
          {'index': 0, 'text': 'top — load average'},
        ],
        'viewport_rows': 24,
        'viewport_cols': 80,
        'modes': {
          'application_cursor': true,
          'application_keypad': true,
          'hide_cursor': true,
        },
      });
      await _settle(tester);
      expect(_mode(container).mode, TerminalViewMode.normal);
      expect(
        _mode(container).unavailableReason,
        BlockUnavailableReason.fullScreen,
      );
      expect(find.byType(TerminalCommandBlocksView), findsNothing);
      expect(find.byType(TerminalComposerView), findsNothing);
      // An application's input prompt can show its cursor again before exiting.
      backend.setFrame(id, {
        'rows': <Object?>[],
        'viewport_rows': 24,
        'viewport_cols': 80,
      });
      await _settle(tester);
      expect(_mode(container).canUseBlocks, isFalse);
      backend.owner = 'ready';
      await _settle(tester);
      expect(_mode(container).mode, TerminalViewMode.normal);
      expect(_mode(container).notice, TerminalModeNotice.blocksRestored);
      await _choose(tester, id, TerminalViewMode.blocks);
      expect(_mode(container).mode, TerminalViewMode.blocks);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  for (final scene in [
    (
      name: 'phone',
      size: const Size(390, 844),
      keyboard: 300.0,
      scale: 1.0,
      brightness: Brightness.light,
    ),
    (
      name: 'landscape',
      size: const Size(844, 390),
      keyboard: 180.0,
      scale: 1.0,
      brightness: Brightness.light,
    ),
    (
      name: 'fixed-text-dark',
      size: const Size(360, 800),
      keyboard: 300.0,
      scale: 1.0,
      brightness: Brightness.dark,
    ),
    (
      name: 'landscape-dark',
      size: const Size(844, 390),
      keyboard: 180.0,
      scale: 1.0,
      brightness: Brightness.dark,
    ),
    (
      name: 'ipad',
      size: const Size(1024, 768),
      keyboard: 280.0,
      scale: 1.0,
      brightness: Brightness.dark,
    ),
  ]) {
    testWidgets('mobile Block input fits ${scene.name} with the keyboard', (
      tester,
    ) async {
      final backend = _MobileBackend()..owner = 'ready';
      final (:container, :id) = await _pump(
        tester,
        backend,
        size: scene.size,
        brightness: scene.brightness,
        scale: scene.scale,
      );
      expect(_mode(container).mode, TerminalViewMode.blocks);
      if (scene.name == 'phone') {
        expect(find.text('末尾 6 / 12 行 · 查看全部').hitTestable(), findsOneWidget);
        await _capture(tester, 'ios-block');
        expect(
          find.byKey(const ValueKey('block-output-scroll-1')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const ValueKey('block-expand-1')).hitTestable().last,
        );
        await _settle(tester);
        expect(find.byKey(const Key('block-reader-scroll')), findsOneWidget);
        final readerBack = find.byKey(const Key('block-reader-close'));
        expect(tester.getSize(readerBack).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(readerBack).width, greaterThanOrEqualTo(44));
        final readerActions = find.byKey(const Key('block-reader-actions'));
        expect(tester.getSize(readerActions).height, greaterThanOrEqualTo(44));
        expect(readerActions.hitTestable(), findsOneWidget);
        await _capture(tester, 'ios-reader');
        await tester.tap(find.byKey(const Key('block-reader-close')));
        await _settle(tester);
      }
      await tester.enterText(_commandEditor(tester), 'echo 移动端');
      tester.view.viewInsets = FakeViewPadding(bottom: scene.keyboard);
      await _settle(tester);
      expect(find.byKey(const Key('ios-terminal-input-bar')), findsNothing);
      expect(tester.takeException(), isNull);
      final run = find.byKey(const Key('ai-send'));
      await tester.ensureVisible(run);
      await _settle(tester);
      expect(run.hitTestable(), findsOneWidget);
      expect(tester.getSize(run).height, greaterThanOrEqualTo(44));
      expect(
        tester.getBottomRight(run).dy,
        lessThanOrEqualTo(scene.size.height - scene.keyboard),
      );
      final surface = tester.getRect(
        scene.name == 'ipad'
            ? _commandEditor(tester)
            : find.byKey(const Key('ai-mobile-composer')),
      );
      expect(surface.top, greaterThanOrEqualTo(0));
      expect(
        surface.bottom,
        lessThanOrEqualTo(scene.size.height - scene.keyboard),
        reason: 'The complete input surface must remain above the keyboard.',
      );
      if (scene.name.startsWith('landscape')) {
        final editable = find.descendant(
          of: _commandEditor(tester),
          matching: find.byType(EditableText),
        );
        await _capture(tester, 'unified-${scene.name}');
        expect(
          tester.getRect(editable).center.dy,
          closeTo(tester.getRect(run).center.dy, 2),
          reason: 'Inline command text should align with the action row.',
        );
      }
      if (scene.name.startsWith('landscape') || scene.name == 'ipad') {
        expect(
          find
              .byKey(const ValueKey('block-expand-1'))
              .hitTestable()
              .last
              .hitTestable(),
          findsOneWidget,
          reason: 'Full output remains reachable with the keyboard open.',
        );
        expect(find.text('末尾 6 / 12 行 · 查看全部').hitTestable(), findsOneWidget);
      }
      await _capture(tester, 'ios-${scene.name}-keyboard');
      if (scene.name == 'ipad') {
        tester.view.viewInsets = FakeViewPadding.zero;
        await _settle(tester);
        await _choose(tester, id, TerminalViewMode.normal);
        expect(_mode(container).mode, TerminalViewMode.normal);
        expect(find.byType(TerminalComposerView), findsNothing);
      }
      if (scene.name == 'phone') {
        backend.owner = 'running';
        await _settle(tester);
        expect(
          find.byKey(const Key('ios-terminal-input-bar')).hitTestable(),
          findsNothing,
        );
        backend.owner = 'ready';
        await _settle(tester);
      }
      tester.testTextInput.hide();
      FocusManager.instance.primaryFocus?.unfocus();
      tester.view.viewInsets = FakeViewPadding.zero;
      await _settle(tester);
      if (scene.name != 'ipad') {
        expect(
          tester.getSize(find.byKey(const Key('ai-mobile-composer'))).height,
          lessThanOrEqualTo(56),
        );
        expect(
          tester.widget<TextField>(_commandEditor(tester)).controller!.text,
          'echo 移动端',
        );
      }
      expect(backend.writes, isEmpty);
      expect(id, isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('mobile settings save Normal for new sessions only', (
    tester,
  ) async {
    final backend = _MobileBackend()..owner = 'ready';
    final (:container, :id) = await _pump(tester, backend);
    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await _settle(tester);
    final settings = find.byKey(const Key('shell-command-defaults'));
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await _settle(tester);
    await tester.tap(find.byKey(const Key('defaults-section-general')));
    await _settle(tester);
    final choices = find.byKey(const Key('defaults-terminal-mode-options'));
    await tester.ensureVisible(choices);
    await tester.tap(choices);
    await _settle(tester);
    await tester.tap(
      find.byKey(const Key('default-terminal-mode-normal')).last,
    );
    await _settle(tester);
    await tester.tap(find.byKey(const Key('defaults-save')));
    await _settle(tester);
    expect(
      container.read(sessionControllerProvider).preferredTerminalMode,
      TerminalViewMode.normal,
    );
    expect(_mode(container).mode, TerminalViewMode.blocks);
    container
        .read(sessionControllerProvider.notifier)
        .createSession(
          container.read(sessionControllerProvider).profiles.first,
        );
    await _settle(tester);
    final state = container.read(sessionControllerProvider);
    expect(state.activeSessionId, isNot(id));
    expect(
      state.tabs.last.activePane.terminalMode.mode,
      TerminalViewMode.normal,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('explicit Normal preference overrides the mobile default', (
    tester,
  ) async {
    final backend = _MobileBackend()..owner = 'ready';
    final (:container, :id) = await _pump(
      tester,
      backend,
      preference: TerminalViewMode.normal,
    );
    expect(_mode(container).mode, TerminalViewMode.normal);
    expect(_mode(container).canUseBlocks, isTrue);
    await _choose(tester, id, TerminalViewMode.blocks);
    expect(_mode(container).mode, TerminalViewMode.blocks);
    expect(
      container.read(sessionControllerProvider).preferredTerminalMode,
      TerminalViewMode.normal,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}

class _DelayedHistoryRepository implements TerminalAiHistoryRepository {
  final documents = Completer<List<Map<String, Object?>>>();
  @override
  Future<List<Map<String, Object?>>> load() => documents.future;
  @override
  Future<void> save(
    String id,
    Map<String, Object?> document, {
    Map<String, Object?>? previous,
  }) async {}
}
