import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

extension PumpApp on WidgetTester {
  Future<void> pumpApp(
    Widget child, {
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('en'),
    double textScale = 1,
    TargetPlatform platform = TargetPlatform.macOS,
    String? fontFamily,
    List<String>? fontFamilyFallback,
  }) => pumpWidget(
    MaterialApp(
      theme: buildIanvsTerminalTheme(brightness, platform: platform).copyWith(
        textTheme: buildIanvsTerminalTheme(brightness, platform: platform)
            .textTheme
            .apply(
              fontFamily: fontFamily,
              fontFamilyFallback: fontFamilyFallback,
            ),
      ),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: child),
    ),
  );
}
