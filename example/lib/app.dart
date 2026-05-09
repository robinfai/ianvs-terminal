import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/preferences/app_preferences_models.dart';
import 'features/sessions/session_controller.dart';
import 'features/shell/shell_screen.dart';
import 'ui/app_ui.dart';

class FluttermApp extends ConsumerWidget {
  const FluttermApp({super.key});

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
      title: 'flutterm',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: buildFluttermTheme(Brightness.light),
      darkTheme: buildFluttermTheme(Brightness.dark),
      home: const ShellScreen(),
    );
  }
}
