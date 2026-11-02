import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/data/configuration/data_api_configuration_repository.dart';
import 'package:app/data/services/portable_master_key.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/shell/defaults_appearance_dialog.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/ai/terminal_ai_test.dart' show MemoryAiStore;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('settings navigation and sync hierarchy', (tester) async {
    final settings = AiSettingsController(MemoryAiStore(null));
    await settings.loaded;
    addTearDown(settings.dispose);
    final platform = defaultTargetPlatform;
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpDefaultsDialog(
        tester,
        surfaceSize: const Size(402, 874),
        platform: platform,
        brightness: brightness,
        aiSettings: settings,
      );
      if (platform == TargetPlatform.iOS) {
        await binding.takeScreenshot('settings-${brightness.name}');
      }
      await tester.tap(find.byKey(const Key('defaults-ai-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-settings-dialog')), findsOneWidget);
      Navigator.of(
        tester.element(find.byKey(const Key('ai-settings-dialog'))),
      ).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('defaults-section-data')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('data-api-remote')));
      await tester.tap(find.byKey(const Key('data-api-remote')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('data-api-auth-method')));
      if (platform == TargetPlatform.iOS) {
        await binding.takeScreenshot('sync-${brightness.name}');
      }
      expect(tester.takeException(), isNull);
    }
  });
}

Future<void> _pumpDefaultsDialog(
  WidgetTester tester, {
  required Size surfaceSize,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  TargetPlatform platform = TargetPlatform.macOS,
  List<TerminalProfile> profiles = const [],
  String? configuredDefaultProfileId,
  String? effectiveDefaultProfileId,
  PortableMasterKeyRepository? masterKeyRepository,
  bool openDataServiceInitially = false,
  DataApiConfiguration dataApiConfiguration =
      const DataApiConfiguration.disabled(),
  DataApiAccountManager? accountManager,
  AiSettingsController? aiSettings,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildIanvsTerminalTheme(brightness, platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: DefaultsAndAppearanceDialog(
          accountManager: accountManager,
          aiSettings: aiSettings,
          masterKeyRepository: masterKeyRepository,
          openDataServiceInitially: openDataServiceInitially,
          dataApiConfiguration: dataApiConfiguration,
          profiles: profiles,
          configuredDefaultProfileId: configuredDefaultProfileId,
          effectiveDefaultProfileId: effectiveDefaultProfileId,
          themeMode: TerminalThemeMode.system,
          terminalViewportPadding:
              TerminalAppAppearance.defaultTerminalViewportPadding,
          restoreLayout: false,
          osc52Policy: LocalTerminalOsc52Policy.profile,
          openUrlPolicy: LocalTerminalOpenUrlPolicy.ask,
          requestAttentionPolicy: LocalTerminalRequestAttentionPolicy.disabled,
          reportVariableDecisions: const {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
