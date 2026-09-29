import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../config/terminal_defaults.dart';

/// Semantic presentation roles for the command dock and its suggestion panels.
///
/// Defaults follow the host [ThemeData]. A host can install a [ComposerTheme]
/// extension when it needs different surfaces or typography without coupling
/// the reusable terminal package to an application-specific design system.
@immutable
final class ComposerTheme extends ThemeExtension<ComposerTheme> {
  const ComposerTheme({
    required this.surface,
    required this.border,
    required this.foreground,
    required this.muted,
    required this.accent,
    required this.chip,
    required this.selection,
    required this.onSelection,
    required this.popover,
    required this.contextSurface,
    required this.hover,
    required this.focus,
    required this.error,
    required this.errorSurface,
    required this.onError,
    required this.primaryAction,
    required this.onPrimaryAction,
    required this.disabledSurface,
    required this.disabledForeground,
    required this.divider,
    required this.shadow,
    required this.commandStyle,
    required this.resultStyle,
    required this.contextStyle,
    required this.actionStyle,
    required this.metadataStyle,
    required this.statusStyle,
    required this.controlHeight,
    required this.highContrast,
  });

  factory ComposerTheme.of(BuildContext context) {
    final theme = Theme.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final custom = theme.extension<ComposerTheme>();
    if (custom != null) return custom._withContrast(highContrast);
    return ComposerTheme.fromTheme(theme, highContrast: highContrast);
  }

  /// Resolves one theme without requiring a widget tree, also useful for
  /// contrast checks and preview fixtures.
  factory ComposerTheme.fromTheme(
    ThemeData theme, {
    bool highContrast = false,
  }) {
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    final touch = switch (theme.platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => true,
      _ => false,
    };
    // A clean editing surface stays stable across focus changes. Small
    // controls carry the accent; the dock itself never becomes a state layer.
    final surface = colors.surfaceContainerLowest;
    final foreground = Color.alphaBlend(
      colors.primary.withValues(alpha: .22),
      colors.onSurface,
    );
    final muted = highContrast
        ? colors.onSurface
        : Color.alphaBlend(
            colors.primary.withValues(alpha: .16),
            colors.onSurfaceVariant,
          );
    final border = highContrast
        ? colors.outline
        : Color.alphaBlend(
            colors.primary.withValues(alpha: .05),
            colors.outlineVariant,
          );
    final hover = Color.alphaBlend(
      colors.onSurface.withValues(alpha: highContrast ? .10 : .05),
      colors.surfaceContainer,
    );
    TextStyle uiStyle(TextStyle? base, double size, double height) =>
        (base ?? const TextStyle()).copyWith(
          fontSize: size,
          height: height,
          color: foreground,
          letterSpacing: 0,
        );
    final command = uiStyle(text.bodyMedium, 16, 1.5).copyWith(
      fontFamily: 'monospace',
      // The generic alias is not resolved by every native font manager (for
      // example Core Text). Reuse the terminal's real fixed-width families
      // before allowing the host's language and symbol fallbacks.
      fontFamilyFallback: [
        terminalPrimaryFontFamily,
        ...terminalFontFamilyFallback,
        ...?text.bodyMedium?.fontFamilyFallback,
      ],
      fontWeight: FontWeight.w400,
      textBaseline: TextBaseline.alphabetic,
    );
    final value = ComposerTheme(
      surface: surface,
      border: border,
      foreground: foreground,
      muted: muted,
      accent: colors.primary,
      chip: colors.surfaceContainerHighest,
      selection: Color.alphaBlend(
        colors.primaryContainer.withValues(alpha: .55),
        surface,
      ),
      onSelection: colors.onPrimaryContainer,
      popover: colors.surfaceContainer,
      contextSurface: colors.surfaceContainerHighest,
      hover: hover,
      focus: colors.primary,
      error: colors.error,
      errorSurface: colors.errorContainer,
      onError: colors.onErrorContainer,
      primaryAction: colors.primary,
      onPrimaryAction: colors.onPrimary,
      disabledSurface: Color.alphaBlend(
        colors.primary.withValues(alpha: .06),
        surface,
      ),
      disabledForeground: highContrast
          ? muted
          : Color.alphaBlend(muted.withValues(alpha: .60), surface),
      divider: border,
      shadow: colors.shadow.withValues(alpha: highContrast ? 0 : .12),
      commandStyle: command,
      resultStyle: command.copyWith(fontSize: 14, height: 1.4),
      contextStyle: uiStyle(text.bodySmall, 12, 1.35).copyWith(color: muted),
      actionStyle: uiStyle(
        text.labelLarge,
        12,
        1.4,
      ).copyWith(fontWeight: FontWeight.w500),
      metadataStyle: uiStyle(text.bodySmall, 11, 1.4).copyWith(color: muted),
      statusStyle: uiStyle(text.bodySmall, 12, 1.4).copyWith(color: muted),
      controlHeight: touch ? touchControlExtent : controlExtent,
      highContrast: highContrast,
    );
    return highContrast ? value._withContrast(true) : value;
  }

  static const radius = 12.0;
  static const popoverRadius = 10.0;
  static const controlRadius = 6.0;
  static const rowRadius = 6.0;
  static const gap = 8.0;
  static const smallGap = 4.0;
  static const inset = 12.0;
  static const sectionGap = 12.0;
  static const controlExtent = 32.0;
  static const touchControlExtent = 44.0;
  static const iconSize = 18.0;
  static const rowIconSize = 16.0;
  static const maxMenuWidth = 760.0;
  static const stateDuration = Duration(milliseconds: 120);

  final Color surface;
  final Color border;
  final Color foreground;
  final Color muted;
  final Color accent;
  final Color chip;
  final Color selection;
  final Color onSelection;
  final Color popover;
  final Color contextSurface;
  final Color hover;
  final Color focus;
  final Color error;
  final Color errorSurface;
  final Color onError;
  final Color primaryAction;
  final Color onPrimaryAction;
  final Color disabledSurface;
  final Color disabledForeground;
  final Color divider;
  final Color shadow;
  final TextStyle commandStyle;
  final TextStyle resultStyle;
  final TextStyle contextStyle;
  final TextStyle actionStyle;
  final TextStyle metadataStyle;
  final TextStyle statusStyle;
  final double controlHeight;
  final bool highContrast;

  Color get onSurface => foreground;
  Color get selected => selection;
  Color get onSelected => onSelection;
  double get borderWidth => highContrast ? 1.5 : 1;
  double get focusWidth => highContrast ? 2 : 1;

  /// Strengthens custom chrome when Increase Contrast is active. The host's
  /// semantic foreground is the fallback, so no fixed light/dark palette is
  /// introduced. Surface text still uses its paired foreground roles.
  ComposerTheme _withContrast(bool enabled) {
    if (!enabled) return this;
    Color boundary(Color color) =>
        _contrast(color, surface) >= 3 && _contrast(color, popover) >= 3
        ? color
        : foreground;
    return copyWith(
      highContrast: true,
      border: boundary(border),
      divider: boundary(divider),
      focus: boundary(focus),
      muted: foreground,
      disabledForeground: foreground,
      contextStyle: contextStyle.copyWith(color: foreground),
      metadataStyle: metadataStyle.copyWith(color: foreground),
      statusStyle: statusStyle.copyWith(color: foreground),
      shadow: shadow.withValues(alpha: 0),
    );
  }

  static double _contrast(Color a, Color b) {
    final first = a.computeLuminance();
    final second = b.computeLuminance();
    return first > second
        ? (first + .05) / (second + .05)
        : (second + .05) / (first + .05);
  }

  @override
  ComposerTheme copyWith({
    Color? surface,
    Color? border,
    Color? foreground,
    Color? muted,
    Color? accent,
    Color? chip,
    Color? selection,
    Color? onSelection,
    Color? popover,
    Color? contextSurface,
    Color? hover,
    Color? focus,
    Color? error,
    Color? errorSurface,
    Color? onError,
    Color? primaryAction,
    Color? onPrimaryAction,
    Color? disabledSurface,
    Color? disabledForeground,
    Color? divider,
    Color? shadow,
    TextStyle? commandStyle,
    TextStyle? resultStyle,
    TextStyle? contextStyle,
    TextStyle? actionStyle,
    TextStyle? metadataStyle,
    TextStyle? statusStyle,
    double? controlHeight,
    bool? highContrast,
  }) => ComposerTheme(
    surface: surface ?? this.surface,
    border: border ?? this.border,
    foreground: foreground ?? this.foreground,
    muted: muted ?? this.muted,
    accent: accent ?? this.accent,
    chip: chip ?? this.chip,
    selection: selection ?? this.selection,
    onSelection: onSelection ?? this.onSelection,
    popover: popover ?? this.popover,
    contextSurface: contextSurface ?? this.contextSurface,
    hover: hover ?? this.hover,
    focus: focus ?? this.focus,
    error: error ?? this.error,
    errorSurface: errorSurface ?? this.errorSurface,
    onError: onError ?? this.onError,
    primaryAction: primaryAction ?? this.primaryAction,
    onPrimaryAction: onPrimaryAction ?? this.onPrimaryAction,
    disabledSurface: disabledSurface ?? this.disabledSurface,
    disabledForeground: disabledForeground ?? this.disabledForeground,
    divider: divider ?? this.divider,
    shadow: shadow ?? this.shadow,
    commandStyle: commandStyle ?? this.commandStyle,
    resultStyle: resultStyle ?? this.resultStyle,
    contextStyle: contextStyle ?? this.contextStyle,
    actionStyle: actionStyle ?? this.actionStyle,
    metadataStyle: metadataStyle ?? this.metadataStyle,
    statusStyle: statusStyle ?? this.statusStyle,
    controlHeight: controlHeight ?? this.controlHeight,
    highContrast: highContrast ?? this.highContrast,
  );

  @override
  ComposerTheme lerp(covariant ComposerTheme? other, double t) {
    if (other == null) return this;
    return ComposerTheme(
      surface: Color.lerp(surface, other.surface, t)!,
      border: Color.lerp(border, other.border, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      chip: Color.lerp(chip, other.chip, t)!,
      selection: Color.lerp(selection, other.selection, t)!,
      onSelection: Color.lerp(onSelection, other.onSelection, t)!,
      popover: Color.lerp(popover, other.popover, t)!,
      contextSurface: Color.lerp(contextSurface, other.contextSurface, t)!,
      hover: Color.lerp(hover, other.hover, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorSurface: Color.lerp(errorSurface, other.errorSurface, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      primaryAction: Color.lerp(primaryAction, other.primaryAction, t)!,
      onPrimaryAction: Color.lerp(onPrimaryAction, other.onPrimaryAction, t)!,
      disabledSurface: Color.lerp(disabledSurface, other.disabledSurface, t)!,
      disabledForeground: Color.lerp(
        disabledForeground,
        other.disabledForeground,
        t,
      )!,
      divider: Color.lerp(divider, other.divider, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      commandStyle: TextStyle.lerp(commandStyle, other.commandStyle, t)!,
      resultStyle: TextStyle.lerp(resultStyle, other.resultStyle, t)!,
      contextStyle: TextStyle.lerp(contextStyle, other.contextStyle, t)!,
      actionStyle: TextStyle.lerp(actionStyle, other.actionStyle, t)!,
      metadataStyle: TextStyle.lerp(metadataStyle, other.metadataStyle, t)!,
      statusStyle: TextStyle.lerp(statusStyle, other.statusStyle, t)!,
      controlHeight: lerpDouble(controlHeight, other.controlHeight, t)!,
      highContrast: t < .5 ? highContrast : other.highContrast,
    );
  }
}
