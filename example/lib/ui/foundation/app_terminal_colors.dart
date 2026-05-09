import 'package:flutter/material.dart';

import '../../features/profiles/profile_models.dart';
import '../../features/terminal/terminal_viewport_colors.dart';

class AppTerminalColors {
  const AppTerminalColors({required this.viewport});

  final TerminalViewportColors viewport;
}

AppTerminalColors resolveTerminalColors(
  BuildContext context, {
  TerminalProfileAppearance? profileAppearance,
}) {
  final base = TerminalViewportColors.fromBrightness(Theme.of(context).brightness);
  final overrides = profileAppearance?.colors;
  return AppTerminalColors(
    viewport: base.copyWith(
      canvasBackground: terminalViewportColorFromHex(overrides?.background),
      foreground: terminalViewportColorFromHex(overrides?.foreground),
      cursor: terminalViewportColorFromHex(overrides?.cursor),
      selection: terminalViewportColorFromHex(overrides?.selection),
    ),
  );
}
