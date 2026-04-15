import 'package:flutter/material.dart';

import 'features/shell/shell_screen.dart';

class FluttermApp extends StatelessWidget {
  const FluttermApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF4C956C);
    return MaterialApp(
      title: 'flutterm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F4EA),
        useMaterial3: true,
      ),
      home: const ShellScreen(),
    );
  }
}
