import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/preferences/app_preferences_models.dart';
import 'features/sessions/session_controller.dart';
import 'features/shell/shell_screen.dart';
import 'ui/app_ui.dart';

class IanvsTerminalApp extends ConsumerWidget {
  const IanvsTerminalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = switch (ref.watch(
      sessionControllerProvider.select((state) => state.themeMode),
    )) {
      TerminalThemeMode.system => ThemeMode.system,
      TerminalThemeMode.light => ThemeMode.light,
      TerminalThemeMode.dark => ThemeMode.dark,
    };

    return MaterialApp(
      title: 'Ianvs Terminal',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: buildIanvsTerminalTheme(Brightness.light),
      darkTheme: buildIanvsTerminalTheme(Brightness.dark),
      home: const ShellScreen(),
    );
  }
}
