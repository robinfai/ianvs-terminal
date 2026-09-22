import 'dart:io';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';
import '../support/no_io_local_terminal_layout_repository.dart';
import 'configuration_capture_binding.dart';

Future<void> _loadFonts() async {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  for (final entry in <String, String>{
    'LayoutCaptureSans': '/System/Library/Fonts/SFNS.ttf',
    'LayoutCaptureCjk': '/System/Library/Fonts/STHeiti Medium.ttc',
    'Menlo': '/System/Library/Fonts/Menlo.ttc',
    'MaterialIcons':
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    final loader = FontLoader(entry.key)
      ..addFont(File(entry.value).readAsBytes().then(ByteData.sublistView));
    await loader.load();
  }
}

Future<void> _capture(
  WidgetTester tester, {
  required String name,
  required Brightness brightness,
  Size size = const Size(1080, 945),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final backend = FakePtyBackend();
  final baseProfile = defaultTerminalProfile();
  final profile = baseProfile.copyWith(
    appearance: baseProfile.appearance.copyWith(
      font: baseProfile.appearance.font.copyWith(family: 'Menlo'),
    ),
  );
  final theme = buildIanvsTerminalTheme(
    brightness,
    platform: TargetPlatform.macOS,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
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
        key: const Key('terminal-layout-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(
              fontFamily: 'LayoutCaptureSans',
              fontFamilyFallback: const ['LayoutCaptureCjk'],
            ),
          ),
          home: const ShellScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ShellScreen)),
  );
  final controller = container.read(sessionControllerProvider.notifier);
  controller.splitSession('1', profile, TerminalSplitAxis.horizontal);
  controller.splitSession('1', profile, TerminalSplitAxis.vertical);
  controller.splitSession('2', profile, TerminalSplitAxis.vertical);
  controller.createSession(profile);
  controller.activateSession('1');
  await tester.pumpAndSettle();
  for (var id = 1; id <= 5; id++) {
    backend.setFrame(id, {
      'rows': [
        {
          'index': 0,
          'text': id == 1
              ? 'robinfai  ~/bk-sec-portal  git: codex/portal-blueapps-mock'
              : 'robinfai  ~  >',
          'style_runs': <Object?>[],
        },
      ],
      'cursor': {'row': 1, 'col': 0, 'visible': false},
      'viewport_rows': 24,
      'viewport_cols': 80,
      'window_title': size.width < 800
          ? 'Local Shell — long-running-build-and-test-session'
          : 'Local Shell',
      'modes': {'bracketed_paste': true, 'mouse_mode': 'normal'},
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
    });
    container.read(terminalRuntimeControllerProvider).refreshSession('$id');
  }
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(find.byKey(const Key('shell-tab-pane-count-1')), findsOneWidget);
  expect(find.byKey(const Key('shell-pane-header-number-4')), findsOneWidget);
  expect(find.text('模式'), findsNothing);
  expect(find.text('粘贴'), findsNothing);
  expect(find.byKey(const Key('shell-pane-dim-1')), findsNothing);
  for (final id in ['2', '3', '4']) {
    final dim = find.byKey(Key('shell-pane-dim-$id'));
    expect(dim, findsOneWidget);
    expect(
      tester.widget<ColoredBox>(dim).color,
      theme.extension<AppThemeTokens>()!.inactiveScrim,
    );
  }
  await expectLater(
    find.byKey(const Key('terminal-layout-capture')),
    matchesGoldenFile(
      '../../../docs/design/terminal-layout-review-20260916/$name.png',
    ),
  );
  final firstPaneRect = tester.getRect(find.byKey(const Key('shell-pane-1')));
  await tester.tap(find.byKey(const Key('shell-pane-4')));
  await tester.pumpAndSettle();
  expect(container.read(sessionControllerProvider).activeSessionId, '4');
  expect(find.byKey(const Key('shell-pane-dim-4')), findsNothing);
  expect(find.byKey(const Key('shell-pane-dim-1')), findsOneWidget);
  expect(tester.getRect(find.byKey(const Key('shell-pane-1'))), firstPaneRect);
}

void main() {
  ConfigurationCaptureBinding();
  if (!Platform.isMacOS) {
    test('terminal layout captures require macOS fonts', () {}, skip: true);
    return;
  }
  setUpAll(_loadFonts);
  for (final brightness in Brightness.values) {
    testWidgets(
      'four panes in ${brightness.name}',
      (tester) async {
        await _capture(
          tester,
          name: 'implementation-${brightness.name}',
          brightness: brightness,
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
  testWidgets(
    'narrow panes with long titles and enlarged text',
    (tester) async {
      await _capture(
        tester,
        name: 'implementation-narrow',
        brightness: Brightness.dark,
        size: const Size(720, 800),
        textScale: 1.4,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
