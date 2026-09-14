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
  final colorScheme = Theme.of(context).colorScheme;
  final base = TerminalViewportColors(
    canvasBackground: colorScheme.surfaceContainerLowest,
    foreground: colorScheme.onSurface,
    cursor: colorScheme.primary,
    selection: colorScheme.primary.withValues(alpha: 0.28),
    scrollbarTrack: colorScheme.outlineVariant.withValues(alpha: 0.32),
    scrollbarThumb: colorScheme.onSurfaceVariant.withValues(alpha: 0.62),
    // Preserve explicit program colors for fades while keeping theme-derived
    // text readable on backgrounds selected by terminal applications.
    minimumContrastRatio: 4.5,
    preserveExplicitForegroundColors: !MediaQuery.highContrastOf(context),
    smartCursorColor: true,
  );
  final overrides = profileAppearance?.colors;
  return AppTerminalColors(
    viewport: base.copyWith(
      cursor: terminalViewportColorFromHex(overrides?.special.cursor),
      selection: terminalViewportColorFromHex(overrides?.special.selection),
    ),
  );
}
