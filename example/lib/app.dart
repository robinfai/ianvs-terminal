import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/configuration/data_api_configuration.dart';
import 'features/preferences/app_preferences_models.dart';
import 'features/sessions/session_controller.dart';
import 'features/shell/shell_screen.dart';
import 'ui/app_ui.dart';
import 'ui/foundation/phone_text_scale_policy.dart';

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
      highContrastTheme: buildIanvsTerminalTheme(
        Brightness.light,
        platform: defaultTargetPlatform,
        highContrast: true,
      ),
      highContrastDarkTheme: buildIanvsTerminalTheme(
        Brightness.dark,
        platform: defaultTargetPlatform,
        highContrast: true,
      ),
      builder: (context, child) => _NativePageSurface(
        child: PhoneTextScalePolicy(
          child: AppNotificationHost(
            topInset: desktopShellChromeHeight(context),
            child: child!,
          ),
        ),
      ),
      home: ShellScreen(activeDataApiDeployment: activeDataApiDeployment),
    );
  }
}

/// The native view remains visible around the system keyboard's rounded corners.
/// Keep it in the same theme as Flutter, including an explicit app appearance.
class _NativePageSurface extends StatefulWidget {
  const _NativePageSurface({required this.child});
  final Widget child;
  @override
  State<_NativePageSurface> createState() => _NativePageSurfaceState();
}

class _NativePageSurfaceState extends State<_NativePageSurface> {
  int? _color;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final color = context.appTheme.canvas.toARGB32();
    if (defaultTargetPlatform == TargetPlatform.iOS && color != _color) {
      _color = color;
      unawaited(_sync(color, Theme.of(context).brightness == Brightness.dark));
    }
  }

  Future<void> _sync(int color, bool dark) async {
    try {
      await const MethodChannel(
        'app/window_bridge',
      ).invokeMethod<void>('setPageBackground', {'argb': color, 'dark': dark});
    } on MissingPluginException {
      // Widget tests and preview hosts have no native window.
    } on PlatformException {
      // Native appearance can be applied on the next theme change.
    }
  }

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: context.appTheme.canvas, child: widget.child);
}
