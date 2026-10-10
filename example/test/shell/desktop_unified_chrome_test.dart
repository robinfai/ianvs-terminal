import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
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

import '../design/visual_capture_fonts.dart';
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

final _captureImages =
    Platform.environment['IANVS_CAPTURE_DESKTOP_CHROME'] == '1';

Future<void> _capture(WidgetTester tester, String name) async {
  if (!_captureImages) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('unified-chrome-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
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
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  addTearDown(tester.view.reset);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final settings = AiSettingsController(_Store());
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
    Brightness.light,
    platform: TargetPlatform.macOS,
  );
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
        key: const Key('unified-chrome-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _captureImages ? withVisualCaptureFonts(theme) : theme,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(body: ShellScreen()),
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

void main() {
  if (_captureImages) setUpAll(loadVisualCaptureFonts);
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
