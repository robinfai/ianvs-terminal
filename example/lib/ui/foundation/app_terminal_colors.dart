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
  return resolveTerminalColorsForScheme(
    Theme.of(context).colorScheme,
    highContrast: MediaQuery.highContrastOf(context),
    profileAppearance: profileAppearance,
  );
}

AppTerminalColors resolveTerminalColorsForScheme(
  ColorScheme colorScheme, {
  bool highContrast = false,
  TerminalProfileAppearance? profileAppearance,
}) {
  final base = TerminalViewportColors(
    canvasBackground: colorScheme.surfaceContainerLowest,
    foreground: colorScheme.onSurface,
    cursor: colorScheme.primary,
    selection: colorScheme.primary.withValues(alpha: 0.28),
    scrollbarTrack: colorScheme.outlineVariant.withValues(alpha: 0.32),
    // The thumb is composited over the translucent track, not just the canvas.
    scrollbarThumb: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
    // Preserve explicit program colors for fades while keeping theme-derived
    // text readable on backgrounds selected by terminal applications.
    minimumContrastRatio: 4.5,
    preserveExplicitForegroundColors: !highContrast,
    smartCursorColor: true,
  );
  final overrides = profileAppearance?.colors;
  final background = terminalViewportColorFromHex(
    overrides?.special.background,
  );
  // A terminal preset can have the opposite brightness to the application.
  // Derive scrollbar tokens from its canvas instead of the surrounding chrome.
  final terminalScheme = background == null
      ? colorScheme
      : ColorScheme.fromSeed(
          seedColor: colorScheme.primary,
          brightness: ThemeData.estimateBrightnessForColor(background),
        );
  return AppTerminalColors(
    viewport: base.copyWith(
      canvasBackground: background,
      foreground: terminalViewportColorFromHex(overrides?.special.foreground),
      cursor: terminalViewportColorFromHex(overrides?.special.cursor),
      selection: terminalViewportColorFromHex(overrides?.special.selection),
      scrollbarTrack: background == null
          ? null
          : terminalScheme.onSurface.withValues(alpha: 0.16),
      scrollbarThumb: background == null
          ? null
          : terminalScheme.onSurface.withValues(alpha: 0.75),
    ),
  );
}
