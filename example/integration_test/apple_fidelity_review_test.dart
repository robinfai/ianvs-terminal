import 'package:app/data/configuration/data_api_configuration.dart';
import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/shell/defaults_appearance_dialog.dart';
import 'package:app/features/ssh/new_session_launcher.dart';
import 'package:app/features/terminal/terminal.dart' as terminal;
import 'package:app/l10n/generated/app_localizations.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:app/ui/previews/terminal_ai_workspace_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// Native simulator captures of production widgets with isolated in-memory data.

Widget _settings(TargetPlatform platform) {
  final profile = defaultTerminalProfile();
  return DefaultsAndAppearanceDialog(
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
    localDataApiAvailable: platform == TargetPlatform.macOS,
    localSessionsEnabled: platform != TargetPlatform.iOS,
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('faithful Apple controls on simulator', (tester) async {
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await binding.takeScreenshot(name);
    }

    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      await tester.pumpWidget(
        AiWorkspacePreview(
          key: UniqueKey(),
          phone: true,
          historyList: true,
          dark: dark,
        ),
      );
      await capture('history-$mode');
      await tester.enterText(find.byType(TextField).first, 'SSH');
      await tester.pumpAndSettle();
      expect(find.text('解释 SSH 连接失败'), findsOneWidget);
      await tester.pumpWidget(
        AiWorkspacePreview(key: UniqueKey(), phone: true, dark: dark),
      );
      await capture('approval-$mode');
      final review = find.byKey(const Key('ai-review-action'));
      await tester.ensureVisible(review);
      await tester.tap(review);
      await capture('approval-review-$mode');
      Widget host(Widget child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildIanvsTerminalTheme(
          dark ? Brightness.dark : Brightness.light,
          platform: TargetPlatform.iOS,
        ),
        home: Scaffold(body: child),
      );
      await tester.pumpWidget(
        host(
          SshProfileEditorDialog(
            initialValue: defaultTerminalProfile().copyWith(
              name: '生产环境',
              connection: const terminal.TerminalConnectionConfig.ssh(
                host: 'prod.example.com',
                user: 'deploy',
                port: 22,
                auth: terminal.TerminalSshAuthMethod.auto,
                privateKeys: ['~/.ssh/id_ed25519'],
              ),
            ),
            allowSaveChoice: true,
          ),
        ),
      );
      await capture('ssh-$mode');
      expect(find.byKey(const Key('ssh-port')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ssh-host')));
      await tester.pumpAndSettle();
      await capture('ssh-keyboard-$mode');
      await tester.pumpWidget(host(_settings(TargetPlatform.iOS)));
      await tester.pumpAndSettle();
      final data = find.byKey(const Key('defaults-section-data'));
      await tester.ensureVisible(data);
      await tester.tap(data);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('data-api-remote')));
      await capture('sync-$mode');
      await tester.tap(find.byKey(const Key('data-api-auth-method')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('用户名和密码').last);
      FocusManager.instance.primaryFocus?.unfocus();
      await capture('sync-password-$mode');
      final password = find.byKey(const Key('data-api-remote-password'));
      await tester.ensureVisible(password);
      await tester.tap(find.byKey(const Key('data-api-password-visibility')));
      await tester.pump();
      expect(tester.widget<TextField>(password).obscureText, isFalse);
    }
  });
}
