import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/preferences/app_preferences_models.dart';
import 'features/sessions/session_controller.dart';
import 'features/shell/shell_screen.dart';

class FluttermApp extends ConsumerWidget {
  const FluttermApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const accent = Color(0xFFF6C344);
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: accent),
        scaffoldBackgroundColor: const Color(0xFFF4F4F4),
        dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF000000),
        dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF111111)),
        useMaterial3: true,
      ),
      home: const ShellScreen(),
    );
  }
}
