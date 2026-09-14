import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../features/shell/ios_terminal_input_bar.dart';
import '../app_ui.dart';

@Preview(name: 'Keyboard · Light', group: 'Terminal', size: Size(390, 280))
Widget iosTerminalKeyboardLightPreview() => _preview(Brightness.light);

@Preview(name: 'Keyboard · Dark', group: 'Terminal', size: Size(390, 280))
Widget iosTerminalKeyboardDarkPreview() => _preview(Brightness.dark);

@Preview(name: 'Keyboard · Landscape', group: 'Terminal', size: Size(844, 180))
Widget iosTerminalKeyboardWidePreview() => _preview(Brightness.dark);

@Preview(
  name: 'Keyboard · 320 px · 2× text',
  group: 'Terminal',
  size: Size(320, 340),
)
Widget iosTerminalKeyboardLargeTextPreview() =>
    _preview(Brightness.light, scale: 2);

Widget _preview(Brightness brightness, {double scale = 1}) => MaterialApp(
  theme: buildIanvsTerminalTheme(brightness, platform: TargetPlatform.iOS),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: Builder(
      builder: (context) => Align(
        alignment: Alignment.bottomCenter,
        child: IosTerminalInputBar(
          palette: AppThemeTokens.of(context),
          keyboardVisible: true,
          onSendBytes: (_) {},
          onDismissKeyboard: () {},
        ),
      ),
    ),
  ),
);
