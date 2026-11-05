import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:app/features/ai/ai_model_catalog.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_history_repository.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' show InputIntentChoice;

import '../design/visual_capture_fonts.dart';
import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_terminal_layout_repository.dart';
import '../support/no_io_sampled_recording_library.dart';

class _HeaderBackend extends FakePtyBackend {
  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = jsonDecode(requestJson) as Map;
    if (request['kind'] == 'completion.query') {
      return jsonEncode({
        'schemaVersion': 1,
        'query': {...request}..remove('kind'),
        'status': 'ok',
        'items': <Object?>[],
      });
    }
    if (request['kind'] == 'terminal.live_screen') {
      return jsonEncode({'text': 'lighthouse> ', 'alternateScreen': false});
    }
    if (request['kind'] == 'composer.state') {
      return jsonEncode({
        'state': 'ready',
        'contextId': 'root',
        'lease': 'header-fixture',
        'cwd': '/home/lighthouse',
      });
    }
    return super.requestSessionJson(sessionId, requestJson);
  }
}

class _MemoryAiHistory implements TerminalAiHistoryRepository {
  @override
  Future<List<Map<String, Object?>>> load() async => [];
  @override
  Future<void> save(
    String id,
    Map<String, Object?> document, {
    Map<String, Object?>? previous,
  }) async {}
}

class _CaptureCatalog extends AiModelCatalog {
  @override
  Future<List<AiModelOption>> choices(AiConfiguration configuration) async =>
      const [
        AiModelOption('gpt-4.1'),
        AiModelOption('gpt-4.1-mini'),
        AiModelOption('gpt-4o'),
      ];
}

class _Store implements AiConfigurationStore {
  _Store([this.value]);
  AiConfiguration? value;
  @override
  Future<AiConfiguration?> read() async => value;
  @override
  Future<void> write(AiConfiguration? configuration) async {
    value = configuration;
  }
}

final _captureImages =
    Platform.environment['IANVS_CAPTURE_DESKTOP_CHROME'] == '1';

Future<void> _capture(WidgetTester tester, String name) async {
  if (!_captureImages) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('unified-chrome-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    final file = File('../build/desktop-prd-v1/iteration-1/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakePtyBackend backend, {
  Size size = const Size(1200, 700),
  double scale = 1,
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
  ValueNotifier<double>? contentWidth,
  AiConfiguration? configuration,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final settings = AiSettingsController(_Store(configuration));
  final defaultProfile = defaultTerminalProfile();
  final profile = _captureImages
      ? defaultProfile.copyWith(
          appearance: defaultProfile.appearance.copyWith(
            font: defaultProfile.appearance.font.copyWith(
              family: visualCaptureMonoFont,
              fallback: visualCaptureFontFallback,
            ),
          ),
        )
      : defaultProfile;
  final theme = buildIanvsTerminalTheme(
    brightness,
    platform: TargetPlatform.macOS,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aiSettingsProvider.overrideWithValue(settings),
        terminalAiHistoryRepositoryProvider.overrideWithValue(
          _MemoryAiHistory(),
        ),
        aiModelCatalogProvider.overrideWithValue(_CaptureCatalog()),
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
        sampledRecordingLibraryProvider.overrideWithValue(
          noIoSampledRecordingLibrary(),
        ),
      ],
      child: RepaintBoundary(
        key: const Key('unified-chrome-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: withVisualCaptureFonts(theme),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: contentWidth == null
              ? const Scaffold(body: ShellScreen())
              : ValueListenableBuilder<double>(
                  valueListenable: contentWidth,
                  child: const Scaffold(body: ShellScreen()),
                  builder: (context, width, child) => Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(width: width, child: child),
                  ),
                ),
        ),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    settings.dispose();
  });
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(ShellScreen)));
}

class _CaptureBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => false;
}

void main() {
  if (_captureImages) {
    _CaptureBinding();
  }
  setUpAll(loadVisualCaptureFonts);

  testWidgets(
    'macOS settings opens over the shell as a modal',
    (tester) async {
      await _pump(tester, _HeaderBackend());
      await tester.tap(find.byKey(const Key('shell-chrome-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shell-command-defaults')));
      await tester.pumpAndSettle();
      final dialog = find.byKey(const Key('defaults-dialog'));
      expect(
        ModalRoute.of(tester.element(dialog)),
        isA<DialogRoute<Object?>>(),
      );
      expect(
        tester
            .getSize(
              find
                  .descendant(of: dialog, matching: find.byType(AppPanel))
                  .first,
            )
            .width,
        lessThan(1200),
      );
      expect(find.byKey(const Key('shell-chrome-bar')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'AI and editable terminal share a persistent mode switch ${brightness.name}',
      (tester) async {
        final layouts = <Map<Object?, Object?>>[];
        const bridge = MethodChannel('app/window_bridge');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (
          call,
        ) async {
          if (call.method == 'setTitleBarLayout') {
            layouts.add((call.arguments as Map).cast<Object?, Object?>());
          }
          return null;
        });
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            bridge,
            null,
          ),
        );
        final backend = _HeaderBackend();
        final container = await _pump(
          tester,
          backend,
          size: const Size(866, 468),
          configuration: const AiConfiguration(
            endpoint: 'https://fixture.test/v1',
            apiKey: 'fixture',
            model: 'gpt-4.1',
          ),
          brightness: brightness,
          locale: const Locale('zh'),
        );
        final sessions = container.read(sessionControllerProvider.notifier);
        if (container.read(sessionControllerProvider).activeSessionId == null) {
          sessions.createSession(defaultTerminalProfile());
        }
        await tester.pumpAndSettle();
        if (find
            .byKey(const Key('session-sidebar'))
            .hitTestable()
            .evaluate()
            .isNotEmpty) {
          await tester.tap(find.byKey(const Key('shell-toggle-sidebar')));
          await tester.pumpAndSettle();
        }
        final id = container.read(sessionControllerProvider).activeSessionId!;
        await tester.tap(find.byKey(Key('terminal-ai-open-$id')));
        await tester.pumpAndSettle();
        final modeRect = tester.getRect(
          find.byKey(const Key('ai-workspace-mode')),
        );
        final task = tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .controller;
        task.setDraft('帮我看看哪个目录占用最多');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        final banner = find.byKey(const Key('shell-runtime-error-dismiss'));
        if (banner.evaluate().isNotEmpty) {
          await tester.tap(banner);
          await tester.pumpAndSettle();
        }
        final header = tester.getRect(
          find.byKey(const Key('ai-journal-header')),
        );
        final chrome = tester.getRect(
          find.byKey(const Key('shell-chrome-bar')),
        );
        expect(header.top, closeTo(chrome.bottom, .1));
        expect(header.left, closeTo(chrome.left, .1));
        final regions = (layouts.last['draggableRegions']! as List)
            .cast<Map<Object?, Object?>>()
            .map(
              (r) => Rect.fromLTWH(
                (r['x']! as num).toDouble(),
                (r['y']! as num).toDouble(),
                (r['width']! as num).toDouble(),
                (r['height']! as num).toDouble(),
              ),
            );
        for (final key in [
          'ai-workspace-mode',
          'ai-header-more',
          'ai-new-task',
        ]) {
          final center = tester.getCenter(find.byKey(Key(key)));
          expect(
            regions.any((r) => r.contains(center)),
            isFalse,
            reason: '$key must not drag the native window',
          );
        }
        await _capture(tester, 'ai-header-${brightness.name}');
        final composerRect = tester.getRect(
          find.byKey(const Key('ai-command-surface')),
        );
        await tester.tap(
          find
              .descendant(
                of: find.byType(TerminalAiWorkspace),
                matching: find.byType(EditableText),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(const Key('ai-command-surface'))),
          composerRect,
        );
        await _capture(tester, 'ai-composer-focus-${brightness.name}');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        task.setDraft('');
        task.chooseInputIntent(InputIntentChoice.ai);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('ai-composer-model')));
        await tester.pumpAndSettle();
        await _capture(tester, 'ai-models-${brightness.name}');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        task.setDraft('帮我看看哪个目录占用最多');
        await tester.pumpAndSettle();
        final writes = backend.writes.length;
        await tester.tap(
          find.descendant(
            of: find.byKey(const Key('ai-workspace-mode')),
            matching: find.text('终端'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('ai-observer-viewport')), findsNothing);
        expect(find.byType(TerminalAiWorkspace), findsNothing);
        expect(
          tester.getRect(find.byKey(const Key('ai-workspace-mode'))),
          modeRect,
        );
        await _capture(tester, 'ordinary-terminal-${brightness.name}');
        expect(backend.writes.length, writes);
        await tester.sendKeyEvent(
          LogicalKeyboardKey.arrowRight,
          platform: 'macos',
        );
        await tester.pump();
        expect(backend.writes.last, '\x1b[C'.codeUnits);
        expect(backend.writes.length, writes + 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyX, platform: 'macos');
        tester.testTextInput.enterText('x');
        await tester.pump();
        expect(backend.writes.last, 'x'.codeUnits);
        expect(backend.writes.length, writes + 2);
        await tester.tap(
          find.descendant(
            of: find.byKey(const Key('ai-workspace-mode')),
            matching: find.text('AI'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
              .controller,
          same(task),
        );
        expect(task.draft, '帮我看看哪个目录占用最多');
        expect(backend.writes.length, writes + 2);
        await tester.tap(find.byKey(const Key('ai-header-more')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('ai-open-settings')), findsOneWidget);
        expect(find.byKey(const Key('ai-close')), findsOneWidget);
        expect(find.byKey(const Key('ai-observe-terminal')), findsNothing);
        await _capture(tester, 'ai-header-menu-${brightness.name}');
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  for (final (width, scale, locale) in [
    (1200.0, 1.0, const Locale('en')),
    (640.0, 2.0, const Locale('en')),
    (640.0, 2.0, const Locale('zh')),
  ]) {
    testWidgets(
      'one chrome row at $width / $scale / $locale',
      (tester) async {
        final layouts = <Map<Object?, Object?>>[];
        const bridge = MethodChannel('app/window_bridge');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (
          call,
        ) async {
          if (call.method == 'setTitleBarLayout') {
            layouts.add((call.arguments as Map).cast<Object?, Object?>());
          }
          return null;
        });
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            bridge,
            null,
          ),
        );
        final container = await _pump(
          tester,
          FakePtyBackend(),
          size: Size(width, 400),
          scale: scale,
          locale: locale,
        );
        final chrome = tester.getRect(
          find.byKey(const Key('shell-chrome-bar')),
        );
        final tabs = tester.getRect(find.byKey(const Key('shell-tab-strip')));
        final menu = tester.getRect(find.byKey(const Key('shell-chrome-menu')));
        expect(chrome.height, inInclusiveRange(44, 64));
        expect(tabs.center.dy, closeTo(menu.center.dy, 1));
        expect(tabs.left, greaterThanOrEqualTo(118));
        expect(tabs.right, lessThanOrEqualTo(menu.left));
        expect(
          find.byKey(const Key('shell-chrome-window-title')),
          findsNothing,
        );
        expect(layouts.last['height'], chrome.height);
        final regions = (layouts.last['draggableRegions']! as List)
            .cast<Map<Object?, Object?>>()
            .map(
              (r) => Rect.fromLTWH(
                (r['x']! as num).toDouble(),
                (r['y']! as num).toDouble(),
                (r['width']! as num).toDouble(),
                (r['height']! as num).toDouble(),
              ),
            );
        expect(regions.any((r) => r.contains(menu.center)), isFalse);
        expect(
          regions.any(
            (r) => r.contains(
              tester.getCenter(find.byKey(const Key('shell-tab-1'))),
            ),
          ),
          isFalse,
        );
        final sessions = container.read(sessionControllerProvider.notifier);
        final profile = container
            .read(sessionControllerProvider)
            .tabs
            .single
            .activePane
            .profileSnapshot!;
        for (var index = 1; index < 12; index++) {
          sessions.createSession(profile);
        }
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('shell-tab-overflow-button')),
          findsOneWidget,
        );
        await _capture(tester, 'chrome-$width-$scale-$locale-tabs');
        await tester.tap(find.byKey(const Key('shell-tab-overflow-button')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('shell-tab-overflow-item-12')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _capture(tester, 'chrome-$width-$scale-$locale-overflow');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'native drag gaps follow restored tabs and layout-only width changes',
    (tester) async {
      final layouts = <Map<Object?, Object?>>[];
      const bridge = MethodChannel('app/window_bridge');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (
        call,
      ) async {
        if (call.method == 'setTitleBarLayout') {
          layouts.add((call.arguments as Map).cast<Object?, Object?>());
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          bridge,
          null,
        ),
      );
      final width = ValueNotifier<double>(1728);
      addTearDown(width.dispose);
      final container = await _pump(
        tester,
        FakePtyBackend(),
        size: const Size(866, 468),
        configuration: const AiConfiguration(
          endpoint: 'https://fixture.test/v1',
          apiKey: 'fixture',
          model: 'gpt-4.1',
        ),
        contentWidth: width,
      );
      final sessions = container.read(sessionControllerProvider.notifier);
      final beforeRestore = layouts.length;
      for (var i = 0; i < 3; i++) {
        sessions.createSession(defaultTerminalProfile());
      }
      await tester.pumpAndSettle();
      expect(
        layouts[beforeRestore]['draggableRegions'],
        isEmpty,
        reason:
            'Revoke empty-session gaps before restored controls become clickable',
      );
      void expectCurrentGaps() {
        final regions = (layouts.last['draggableRegions']! as List)
            .cast<Map<Object?, Object?>>()
            .map(
              (r) => Rect.fromLTWH(
                (r['x']! as num).toDouble(),
                (r['y']! as num).toDouble(),
                (r['width']! as num).toDouble(),
                (r['height']! as num).toDouble(),
              ),
            )
            .toList();
        final active = container
            .read(sessionControllerProvider)
            .activeSessionId!;
        for (final key in [
          'shell-tab-$active',
          'terminal-ai-open-$active',
          'shell-chrome-new-tab',
          'shell-chrome-menu',
        ]) {
          final center = tester.getCenter(find.byKey(Key(key)));
          expect(regions.any((r) => r.contains(center)), isFalse, reason: key);
        }
        final blank = Offset(
          tester.getRect(find.byKey(const Key('shell-chrome-new-tab'))).right +
              10,
          22,
        );
        expect(
          regions.any((r) => r.contains(blank)),
          isTrue,
          reason: 'The actual rail gap must remain draggable',
        );
      }

      expectCurrentGaps();
      for (final nextWidth in [1450.0, 1728.0]) {
        width.value = nextWidth;
        await tester.pumpAndSettle();
        expectCurrentGaps();
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  for (final collapsed in [false, true]) {
    testWidgets(
      'sidebar pending approval ${collapsed ? 'in collapsed group ' : ''}reveals the original hidden split pane without writes',
      (tester) async {
        final backend = FakePtyBackend();
        final container = await _pump(tester, backend);
        final sessions = container.read(sessionControllerProvider.notifier);
        sessions.splitActiveSession(
          defaultTerminalProfile(),
          TerminalSplitAxis.horizontal,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('terminal-ai-open-2')));
        await tester.pumpAndSettle();
        final ai = tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .controller;
        sessions.activateSession('1');
        sessions.createSession(defaultTerminalProfile());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('shell-toggle-sidebar')));
        await tester.pumpAndSettle();
        if (collapsed) {
          await tester.tap(find.byKey(const Key('session-group-directory')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('sidebar-session-1')), findsNothing);
        }
        final writesBefore = backend.writes.length;
        ai.pending = const AiAction(
          id: 'sidebar-proposal',
          kind: AiActionKind.runCommand,
          command: 'printf pending',
          reason: 'Fixture proposal',
          rawCall: {},
        );
        ai.phase = AiPhase.awaitingApproval;
        ai.setDraft('Retained split pane draft');
        await tester.pumpAndSettle();
        final badge = collapsed
            ? find.byKey(const Key('shell-sidebar-approval'))
            : find.descendant(
                of: find.byKey(const Key('sidebar-session-1')),
                matching: find.byKey(const Key('shell-tab-approval-1')),
              );
        expect(badge, findsOneWidget);
        expect(container.read(sessionControllerProvider).activeSessionId, '3');
        expect(backend.writes.length, writesBefore);
        await tester.tap(badge);
        await tester.pumpAndSettle();
        expect(container.read(sessionControllerProvider).activeSessionId, '2');
        expect(
          tester
              .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
              .controller,
          same(ai),
        );
        expect(ai.phase, isNot(AiPhase.executing));
        expect(ai.draft, 'Retained split pane draft');
        expect(backend.writes.length, writesBefore);
        expect(
          backend.jsonRequests.where((r) => r['kind'] == 'composer.submit'),
          isEmpty,
        );
        ai.takeOver();
        await tester.pumpAndSettle();
        expect(badge, findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'hidden pending approvals update and only reveal their source',
    (tester) async {
      final backend = FakePtyBackend();
      final container = await _pump(tester, backend);
      final sessions = container.read(sessionControllerProvider.notifier);
      for (var index = 1; index < 12; index++) {
        sessions.createSession(defaultTerminalProfile());
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('terminal-ai-open-12')));
      await tester.pumpAndSettle();
      final ai = tester
          .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
          .controller;
      await tester.tap(find.byKey(const Key('shell-tab-1')));
      await tester.pumpAndSettle();
      final writesBefore = backend.writes.length;
      ai.pending = const AiAction(
        id: 'hidden-proposal',
        kind: AiActionKind.runCommand,
        command: 'printf pending',
        reason: 'Fixture proposal',
        rawCall: {},
      );
      ai.phase = AiPhase.awaitingApproval;
      ai.setDraft('Retained hidden draft');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('shell-tab-overflow-approval')),
        findsOneWidget,
      );
      expect(container.read(sessionControllerProvider).activeSessionId, '1');
      await tester.tap(find.byKey(const Key('shell-tab-overflow-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shell-tab-approval-12')));
      await tester.pumpAndSettle();
      expect(container.read(sessionControllerProvider).activeSessionId, '12');
      expect(
        tester
            .widget<TerminalAiWorkspace>(find.byType(TerminalAiWorkspace))
            .controller,
        same(ai),
      );
      expect(ai.phase, isNot(AiPhase.executing));
      expect(ai.draft, 'Retained hidden draft');
      expect(backend.writes.length, writesBefore);
      expect(
        backend.jsonRequests.where((r) => r['kind'] == 'composer.submit'),
        isEmpty,
      );
      ai.takeOver();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('shell-tab-overflow-approval')),
        findsNothing,
      );
      expect(find.byKey(const Key('shell-tab-approval-12')), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
