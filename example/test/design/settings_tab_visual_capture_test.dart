import 'dart:io';

import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/shell/defaults_appearance_dialog.dart';
import 'package:app/l10n/generated/app_localizations.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _surfaceSize = Size(1440, 1024);

Future<ByteData> _readFont(String path) async {
  final bytes = await File(path).readAsBytes();
  return ByteData.sublistView(Uint8List.fromList(bytes));
}

Future<void> _loadVisualFonts() async {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final text = FontLoader('SettingsCaptureSans')
    ..addFont(_readFont('/System/Library/Fonts/STHeiti Medium.ttc'));
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(
      _readFont(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    );
  await Future.wait([text.load(), materialIcons.load()]);
}

Future<void> _pumpSettings(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _surfaceSize;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final profile = defaultTerminalProfile();
  final baseTheme = buildIanvsTerminalTheme(
    Brightness.light,
    platform: TargetPlatform.macOS,
  );
  const captureFont = 'SettingsCaptureSans';
  final inputDecorationTheme = baseTheme.inputDecorationTheme;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: baseTheme.copyWith(
        textTheme: baseTheme.textTheme.apply(fontFamily: captureFont),
        primaryTextTheme: baseTheme.primaryTextTheme.apply(
          fontFamily: captureFont,
        ),
        inputDecorationTheme: inputDecorationTheme.copyWith(
          labelStyle: inputDecorationTheme.labelStyle?.copyWith(
            fontFamily: captureFont,
          ),
          floatingLabelStyle: inputDecorationTheme.floatingLabelStyle?.copyWith(
            fontFamily: captureFont,
          ),
          helperStyle: inputDecorationTheme.helperStyle?.copyWith(
            fontFamily: captureFont,
          ),
          hintStyle: inputDecorationTheme.hintStyle?.copyWith(
            fontFamily: captureFont,
          ),
          errorStyle: inputDecorationTheme.errorStyle?.copyWith(
            fontFamily: captureFont,
          ),
        ),
      ),
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
          dataApiConfiguration: const DataApiConfiguration.disabled(),
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
}) async {
  await _pumpSettings(tester);
  if (tabKey != 'general') {
    await tester.tap(find.byKey(Key('defaults-section-$tabKey')));
    await tester.pumpAndSettle();
  }
  await expectLater(
    find.byKey(const Key('defaults-dialog')),
    matchesGoldenFile(
      '../../../docs/design/settings-tabs/current/$goldenName.png',
    ),
  );
}

void main() {
  if (!Platform.isMacOS) {
    test('settings tab visual captures require macOS fonts', () {}, skip: true);
    return;
  }

  setUpAll(_loadVisualFonts);

  testWidgets('captures General settings tab', (tester) async {
    await _captureTab(tester, tabKey: 'general', goldenName: '01-general');
  });

  testWidgets('captures Appearance settings tab', (tester) async {
    await _captureTab(
      tester,
      tabKey: 'appearance',
      goldenName: '02-appearance',
    );
  });

  testWidgets('captures Keyboard shortcuts settings tab', (tester) async {
    await _captureTab(tester, tabKey: 'shortcuts', goldenName: '03-shortcuts');
  });

  testWidgets('captures Security and permissions settings tab', (tester) async {
    await _captureTab(tester, tabKey: 'security', goldenName: '04-security');
  });

  testWidgets('captures Data service settings tab', (tester) async {
    await _captureTab(tester, tabKey: 'data', goldenName: '05-data');
  });
}
