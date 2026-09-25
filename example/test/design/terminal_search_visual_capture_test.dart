import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'visual_capture_fonts.dart';

const _captureKey = Key('search-review-capture');
const _fieldKey = Key('terminal-search-field');
const _modeKey = Key('terminal-search-mode');

// Optional local HIG review uses installed Apple fonts without copying or
// redistributing them. Normal test runs retain the pinned portable fixtures.
final String? _systemFontPath = Platform.environment['SEARCH_REVIEW_SYSTEM_FONT'];

Future<void> _loadReviewFonts() async {
  if (_systemFontPath == null) {
    await loadVisualCaptureFonts();
    return;
  }
  for (final entry in {
    '.AppleSystemUIFont': _systemFontPath!,
    'PingFang SC': Platform.environment['SEARCH_REVIEW_CJK_FONT']!,
    'MaterialIcons': 'assets/fonts/TrailLightIcons.ttf',
  }.entries) {
    final loader = FontLoader(entry.key)
      ..addFont(File(entry.value).readAsBytes().then(ByteData.sublistView));
    await loader.load();
  }
}

ThemeData _reviewTheme(Brightness brightness) {
  final theme = buildIanvsTerminalTheme(
    brightness,
    platform: TargetPlatform.macOS,
  );
  return _systemFontPath == null ? withVisualCaptureFonts(theme) : theme;
}

Future<FakePtyBackend> _pumpSearch(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  String language = 'zh',
  Size size = const Size(600, 420),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final backend = FakePtyBackend();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(backend),
        profileRepositoryProvider.overrideWithValue(
          MemoryProfileRepository(
            TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
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
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: _reviewTheme(brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const ShellScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  backend.setFrame(1, {
    'rows': <Object?>[],
    'cursor': {'row': 0, 'col': 0, 'visible': false},
    'viewport_rows': 24,
    'viewport_cols': 80,
  });
  ProviderScope.containerOf(
    tester.element(find.byType(ShellScreen)),
  ).read(terminalRuntimeControllerProvider).refreshSession('1');
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('shell-toolbar-search')));
  await tester.pumpAndSettle();
  return backend;
}

// Captures the real ShellScreen, including its overlay menus. Set this env var
// to save review artifacts; ordinary test runs only validate behavior/layout.
Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['SEARCH_REVIEW_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  ConfigurationCaptureBinding();
  if (!Platform.isMacOS) {
    test('search visual review requires macOS rendering', () {}, skip: true);
    return;
  }
  setUpAll(_loadReviewFonts);

  for (final scenario in [
    (
      name: 'light-zh',
      brightness: Brightness.light,
      language: 'zh',
      size: const Size(600, 420),
      scale: 1.0,
    ),
    (
      name: 'dark-zh',
      brightness: Brightness.dark,
      language: 'zh',
      size: const Size(600, 420),
      scale: 1.0,
    ),
    (
      name: 'light-en',
      brightness: Brightness.light,
      language: 'en',
      size: const Size(600, 420),
      scale: 1.0,
    ),
    (
      name: 'narrow-scaled',
      brightness: Brightness.light,
      language: 'zh',
      size: const Size(360, 520),
      scale: 2.0,
    ),
  ]) {
    testWidgets(
      'search menu review ${scenario.name}',
      (tester) async {
        await _pumpSearch(
          tester,
          brightness: scenario.brightness,
          language: scenario.language,
          size: scenario.size,
          textScale: scenario.scale,
        );
        final editable = find.descendant(
          of: find.byKey(_fieldKey),
          matching: find.byType(EditableText),
        );
        final fieldRect = tester.getRect(editable);
        final preferredLineHeight = tester
            .state<EditableTextState>(editable)
            .renderEditable
            .preferredLineHeight;
        await _capture(tester, '${scenario.name}-input');
        await tester.tap(find.byKey(_modeKey));
        await tester.pumpAndSettle();
        final bar = tester.getRect(
          find.byKey(const Key('terminal-search-bar')),
        );
        for (final key in [
          'smart_case_substring',
          'case_sensitive_substring',
          'case_insensitive_substring',
          'case_sensitive_regex',
          'case_insensitive_regex',
        ]) {
          final rect = tester.getRect(
            find.byKey(Key('terminal-search-mode-$key')),
          );
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(scenario.size.width));
          expect(rect.top, greaterThan(bar.bottom));
          expect(rect.bottom, lessThanOrEqualTo(scenario.size.height));
        }
        expect(tester.takeException(), isNull);
        await _capture(tester, '${scenario.name}-filter');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(_fieldKey), findsOneWidget);
        expect(
          find.byKey(const Key('terminal-search-mode-smart_case_substring')),
          findsNothing,
        );
        await tester.tap(find.byKey(const Key('terminal-search-scope')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _capture(tester, '${scenario.name}-scope');
        expect(
          fieldRect.height,
          greaterThanOrEqualTo(preferredLineHeight),
          reason: 'Enlarged search text must fit its editing viewport.',
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }

  testWidgets(
    'large search status leaves room for query editing',
    (tester) async {
      final backend = await _pumpSearch(
        tester,
        size: const Size(360, 520),
        textScale: 2,
      );
      await tester.enterText(find.byKey(_fieldKey), 'missing');
      await tester.pumpAndSettle();
      final status = find.byKey(const Key('terminal-search-status'));
      expect(find.text('无匹配项'), findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: status, matching: find.byType(RichText)),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(tester.getSize(find.byKey(_fieldKey)).width, greaterThan(100));
      await _capture(tester, 'narrow-scaled-no-matches');
      backend.setSearchMatches(1, 'needle', [
        {'row': 3, 'start_col': 0, 'end_col': 6, 'text': 'needle'},
      ]);
      await tester.enterText(find.byKey(_fieldKey), 'needle');
      await tester.pumpAndSettle();
      expect(find.text('1/1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'search menus preserve selection and keyboard behavior',
    (tester) async {
      final backend = await _pumpSearch(tester);
      final semantics = tester.ensureSemantics();

      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('terminal-search-next')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(_modeKey));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('terminal-search-mode-smart_case_substring')),
        findsNothing,
      );
      expect(find.byKey(_fieldKey), findsOneWidget);
      expect(backend.writes, isEmpty);
      await tester.tap(find.byKey(_modeKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('terminal-search-mode-case_sensitive_regex')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_fieldKey), '[');
      await tester.pumpAndSettle();
      expect(find.text('无效的正则表达式'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('terminal-search-next')))
            .onPressed,
        isNull,
      );
      await _capture(tester, 'regex-error');
      await tester.tap(find.byKey(const Key('terminal-search-clear')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_modeKey));
      await tester.pumpAndSettle();
      final selected = tester.getSemantics(
        find.byKey(const Key('terminal-search-mode-case_sensitive_regex')),
      );
      expect(
        selected.getSemanticsData().flagsCollection.isSelected,
        ui.Tristate.isTrue,
      );
      await _capture(tester, 'regex-selected');
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
