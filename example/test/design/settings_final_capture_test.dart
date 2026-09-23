import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/shell/defaults_appearance_dialog.dart';
import 'package:app/l10n/generated/app_localizations.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'configuration_capture_binding.dart';
import 'visual_capture_fonts.dart';

const _surfaceSize = Size(1440, 1024);

Future<void> _pumpSettings(
  WidgetTester tester, {
  Size surfaceSize = _surfaceSize,
  Brightness brightness = Brightness.light,
  TextScaler textScaler = TextScaler.noScaling,
  DataApiConfiguration dataApiConfiguration =
      const DataApiConfiguration.disabled(),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = surfaceSize;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final profile = defaultTerminalProfile();
  final baseTheme = buildIanvsTerminalTheme(
    brightness,
    platform: TargetPlatform.macOS,
  );

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: withVisualCaptureFonts(baseTheme),
      home: Scaffold(
        body: DefaultsAndAppearanceDialog(
          profiles: [profile],
          configuredDefaultProfileId: profile.id,
          effectiveDefaultProfileId: profile.id,
          themeMode: TerminalThemeMode.system,
          languageMode: TerminalLanguageMode.system,
          terminalViewportPadding:
              TerminalAppAppearance.defaultTerminalViewportPadding,
          restoreLayout: true,
          osc52Policy: LocalTerminalOsc52Policy.profile,
          openUrlPolicy: LocalTerminalOpenUrlPolicy.ask,
          requestAttentionPolicy: LocalTerminalRequestAttentionPolicy.disabled,
          reportVariableDecisions: const {},
          dataApiConfiguration: dataApiConfiguration,
          localDataApiAvailable: true,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _captureTab(
  WidgetTester tester, {
  required String tabKey,
  required String goldenName,
  Size surfaceSize = _surfaceSize,
  Brightness brightness = Brightness.light,
  TextScaler textScaler = TextScaler.noScaling,
  String? goldenPath,
}) async {
  await _pumpSettings(
    tester,
    surfaceSize: surfaceSize,
    brightness: brightness,
    textScaler: textScaler,
  );
  if (tabKey != 'general') {
    await tester.tap(find.byKey(Key('defaults-section-$tabKey')));
    await tester.pumpAndSettle();
  }
  await expectLater(
    find.byKey(const Key('defaults-dialog')),
    matchesGoldenFile(
      goldenPath ?? 'goldens/settings-tabs/current/$goldenName.png',
    ),
  );
}

void main() {
  ConfigurationCaptureBinding();
  setUpAll(loadVisualCaptureFonts);
  for (final brightness in Brightness.values) {
    for (final section in [
      'general',
      'appearance',
      'shortcuts',
      'security',
      'data',
    ]) {
      testWidgets('settings final ${brightness.name} $section', (tester) async {
        await _captureTab(
          tester,
          tabKey: section,
          goldenName: section,
          brightness: brightness,
          goldenPath:
              'goldens/settings-general-20260912/renders/${brightness.name}-$section.png',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('settings final narrow scaled', (tester) async {
    await _captureTab(
      tester,
      tabKey: 'general',
      goldenName: 'narrow-scaled',
      surfaceSize: const Size(680, 620),
      textScaler: const TextScaler.linear(2),
      goldenPath: 'goldens/settings-general-20260912/renders/narrow-scaled.png',
    );
    expect(tester.takeException(), isNull);
  });
}
