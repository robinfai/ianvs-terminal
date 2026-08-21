import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';
import 'generated/app_localizations_en.dart';

export 'generated/app_localizations.dart';

extension AppLocalizationsX on BuildContext {
  /// Returns the active localization, with English as a safe fallback for
  /// isolated component tests that do not build the application root.
  AppLocalizations get l10n =>
      AppLocalizations.of(this) ?? AppLocalizationsEn();
}

/// Resolves the application locale from the operating system preferences.
///
/// Language matching intentionally delegates to Flutter so regional Chinese
/// locales such as zh-Hans-CN resolve to the supported `zh` translation.
Locale resolveAppLocale(
  List<Locale>? systemLocales,
  Iterable<Locale> supportedLocales,
) => basicLocaleListResolution(systemLocales, supportedLocales);
