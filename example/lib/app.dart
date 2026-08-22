import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/configuration/data_api_configuration.dart';
import 'features/preferences/app_preferences_models.dart';
import 'features/sessions/session_controller.dart';
import 'features/shell/shell_screen.dart';
import 'ui/app_ui.dart';

class IanvsTerminalApp extends ConsumerWidget {
  const IanvsTerminalApp({this.activeDataApiDeployment, super.key});

  final DataApiDeployment? activeDataApiDeployment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = switch (ref.watch(
      sessionControllerProvider.select((state) => state.themeMode),
    )) {
      TerminalThemeMode.system => ThemeMode.system,
      TerminalThemeMode.light => ThemeMode.light,
      TerminalThemeMode.dark => ThemeMode.dark,
    };
    final locale = switch (ref.watch(
      sessionControllerProvider.select((state) => state.languageMode),
    )) {
      TerminalLanguageMode.system => null,
      TerminalLanguageMode.english => const Locale('en'),
      TerminalLanguageMode.simplifiedChinese => const Locale('zh'),
    };

    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      localeListResolutionCallback: resolveAppLocale,
      themeMode: themeMode,
      theme: buildIanvsTerminalTheme(
        Brightness.light,
        platform: defaultTargetPlatform,
      ),
      darkTheme: buildIanvsTerminalTheme(
        Brightness.dark,
        platform: defaultTargetPlatform,
      ),
      home: ShellScreen(activeDataApiDeployment: activeDataApiDeployment),
    );
  }
}
