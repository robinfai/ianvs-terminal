import 'package:flutter/foundation.dart';

import '../config/terminal_config.dart';
import '../config/terminal_defaults.dart';

/// Uses the bundled default face without changing the user's saved family.
///
/// Package fonts are registered by Flutter under a package-qualified name.
/// Resolve that name explicitly because dart:ui's paragraph styles do not have
/// Flutter TextStyle's package argument. Other configured families stay intact.
TerminalFontConfig terminalFontForRendering(
  TerminalFontConfig font, {
  TargetPlatform? platform,
}) {
  final family = font.family == terminalPrimaryFontFamily
      ? terminalBundledFontFamily
      : font.family;
  var fallback = font.fallback;
  if ((platform ?? defaultTargetPlatform) == TargetPlatform.linux) {
    final missing = terminalPortableMonospaceFallbacks
        .where((family) => !fallback.contains(family))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      fallback = List<String>.unmodifiable(<String>[...fallback, ...missing]);
    }
  }
  if (family == font.family && identical(fallback, font.fallback)) {
    return font;
  }
  return font.copyWith(family: family, fallback: fallback);
}
