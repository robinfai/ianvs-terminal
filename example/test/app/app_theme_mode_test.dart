import 'package:app/app.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';

Future<void> _pumpApp(
  WidgetTester tester, {
  LocalTerminalConfigDocument? config,
  MemoryLocalTerminalConfigRepository? configRepository,
}) async {
  final repository =
      configRepository ?? MemoryLocalTerminalConfigRepository(config);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
        profileRepositoryProvider.overrideWithValue(
          MemoryProfileRepository(
            TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
          ),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(repository),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          noIoLocalSessionRecordingRepository(),
        ),
      ],
      child: const IanvsTerminalApp(),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  for (final mode in [TerminalThemeMode.light, TerminalThemeMode.dark]) {
    testWidgets(
      'system high contrast changes $mode without replacing the session',
      (tester) async {
        addTearDown(
          tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await _pumpApp(
          tester,
          config: LocalTerminalConfigDocument(
            appearance: TerminalAppAppearance(themeMode: mode),
          ),
        );
        final context = tester.element(find.text('Trail'));
        final normal = Theme.of(context);
        final container = ProviderScope.containerOf(context);
        final session = container.read(sessionControllerProvider);
        for (final enabled in [true, false]) {
          tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
              FakeAccessibilityFeatures(highContrast: enabled);
          await tester.pumpAndSettle();
          final theme = Theme.of(tester.element(find.text('Trail')));
          final tokens = theme.extension<AppThemeTokens>()!;
          expect(theme.brightness, normal.brightness);
          expect(
            tokens.border,
            enabled
                ? isNot(normal.extension<AppThemeTokens>()!.border)
                : normal.extension<AppThemeTokens>()!.border,
          );
          expect(
            theme.textTheme.bodyMedium!.fontSize,
            normal.textTheme.bodyMedium!.fontSize,
          );
          expect(container.read(sessionControllerProvider), same(session));
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  test('system locale resolution supports regional Chinese locales', () {
    expect(
      resolveAppLocale(const <Locale>[
        Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
          countryCode: 'CN',
        ),
      ], AppLocalizations.supportedLocales),
      const Locale('zh'),
    );
    expect(
      resolveAppLocale(const <Locale>[
        Locale('fr', 'FR'),
      ], AppLocalizations.supportedLocales),
      const Locale('en'),
    );
  });

  testWidgets('ianvs terminal app follows the system Chinese locale', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = const <Locale>[
      Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hans',
        countryCode: 'CN',
      ),
    ];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

    await _pumpApp(tester);

    expect(find.text('Trail'), findsOneWidget);
    expect(
      Localizations.localeOf(tester.element(find.text('Trail'))),
      const Locale('zh'),
    );
  });

  testWidgets('persisted English overrides the system Chinese locale', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = const <Locale>[
      Locale('zh'),
    ];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

    await _pumpApp(
      tester,
      config: const LocalTerminalConfigDocument(
        appearance: TerminalAppAppearance(
          languageMode: TerminalLanguageMode.english,
        ),
      ),
    );

    expect(find.text('Trail'), findsOneWidget);
    expect(
      Localizations.localeOf(tester.element(find.text('Trail'))),
      const Locale('en'),
    );
  });

  testWidgets('language changes apply immediately and persist locally', (
    tester,
  ) async {
    final repository = MemoryLocalTerminalConfigRepository(
      const LocalTerminalConfigDocument(),
    );
    await _pumpApp(tester, configRepository: repository);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await container
        .read(sessionControllerProvider.notifier)
        .setLanguageMode(TerminalLanguageMode.simplifiedChinese);
    await tester.pumpAndSettle();

    expect(find.text('Trail'), findsOneWidget);
    expect(
      repository.savedDocuments.last.appearance.languageMode,
      TerminalLanguageMode.simplifiedChinese,
    );
  });

  testWidgets('ianvs terminal app consumes the persisted dark theme mode', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      config: const LocalTerminalConfigDocument(
        appearance: TerminalAppAppearance(themeMode: TerminalThemeMode.dark),
      ),
    );

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });

  testWidgets('ianvs terminal app defaults to system theme mode when unset', (
    tester,
  ) async {
    await _pumpApp(tester);

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
  });
}
