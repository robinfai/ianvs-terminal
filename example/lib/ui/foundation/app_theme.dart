import 'package:ianvs_design/ianvs_design.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' show ComposerTheme;

import 'app_high_contrast.dart';
import 'app_motion.dart';
import 'app_theme_tokens.dart';

/// Matches MainFlutterWindow.chromeBarHeight, including its native drag region.
const appWindowTitleBarHeight = 44.0;

/// Shared Ianvs components and typography, plus Trail's terminal surfaces.
ThemeData buildIanvsTerminalTheme(
  Brightness brightness, {
  TargetPlatform? platform,
  bool highContrast = false,
}) {
  final resolvedPlatform = platform ?? TargetPlatform.macOS;
  final touch = switch (resolvedPlatform) {
    TargetPlatform.android ||
    TargetPlatform.fuchsia ||
    TargetPlatform.iOS => true,
    _ => false,
  };
  final base = IanvsTheme.build(
    brightness: brightness,
    platform: resolvedPlatform,
    density: touch ? IanvsDensity.touch : IanvsDensity.compact,
    touchVisualDensity: resolvedPlatform == TargetPlatform.iOS
        ? IanvsTouchVisualDensity.compact
        : IanvsTouchVisualDensity.standard,
  );
  // Focused Reading keeps mobile page headings and secondary labels quiet.
  // Body/input metrics and desktop typography retain the shared defaults.
  final reading = touch
      ? base.copyWith(
          textTheme: base.textTheme.copyWith(
            titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 16),
            labelSmall: base.textTheme.labelSmall?.copyWith(fontSize: 12),
          ),
        )
      : base;
  final shared = highContrast ? withAppHighContrast(reading) : reading;
  final design = shared.extension<IanvsTokens>()!;
  // The legacy names are an adapter for terminal/business surfaces. General
  // colors, spacing and control metrics all come from the shared design system.
  final terminal = AppThemeTokens.fallbackFor(brightness).copyWith(
    canvas: design.canvas,
    chrome: design.chrome,
    chromeElevated: design.raised,
    panel: design.field,
    panelElevated: design.raised,
    overlay: design.raised,
    border: design.separator,
    borderStrong: design.border,
    textPrimary: design.text,
    textMuted: design.muted,
    textSubtle: design.subtle,
    accent: design.accent,
    focus: design.focus,
    focusRing: design.focus,
    selected: design.selected,
    danger: design.danger,
    warning: design.warning,
    success: design.success,
    dangerContainer: shared.colorScheme.errorContainer,
    warningContainer: Color.alphaBlend(
      design.warning.withValues(alpha: .12),
      design.field,
    ),
    successContainer: Color.alphaBlend(
      design.success.withValues(alpha: .12),
      design.field,
    ),
    spacing: const AppThemeSpacing(
      xs: IanvsSpacing.xs,
      sm: IanvsSpacing.sm,
      md: IanvsSpacing.md,
      lg: IanvsSpacing.lg,
      xl: IanvsSpacing.xl,
      xxl: IanvsSpacing.xxl,
    ),
    radius: AppThemeRadius(
      sm: design.controlRadius,
      md: design.controlRadius,
      lg: design.panelRadius,
      xl: design.panelRadius,
    ),
    // Desktop chrome follows the same semantic surfaces as mobile pages.
    shellChrome: AppShellChromeColors(
      base: design.canvas,
      surface: design.raised,
      rail: design.chrome,
      tabActiveBackground: design.field,
      tabTrackBackground: design.chrome,
      tabHoverBackground: design.raised,
      tabBorder: design.separator,
      tabTextPrimary: design.text,
      tabTextMuted: design.muted,
      tabTextSubtle: design.subtle,
    ),
    controls: AppThemeControls(
      dense: design.controlHeight,
      compact: design.controlHeight,
      regular: design.controlHeight,
    ),
  );
  final input = shared.inputDecorationTheme;
  final outline = input.enabledBorder!;
  final desktopInput = input.copyWith(
    // Keep the editing surface clean while the pointer rests on a focused
    // field; the accent outline communicates focus without a gray fill.
    hoverColor: Colors.transparent,
    focusedBorder: outline.copyWith(
      borderSide: BorderSide(
        color: Color.alphaBlend(
          design.focus.withValues(alpha: .85),
          design.field,
        ),
        width: highContrast ? 2 : 1.5,
      ),
    ),
  );
  final mobileOutline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(
      color: highContrast ? design.border : design.separator,
      width: highContrast ? 1.5 : 1,
    ),
  );
  final mobileInput = input.copyWith(
    border: mobileOutline,
    enabledBorder: mobileOutline,
    focusedBorder: mobileOutline.copyWith(
      borderSide: BorderSide(
        color: design.focus,
        width: highContrast ? 2 : 1.5,
      ),
    ),
    errorBorder: mobileOutline.copyWith(
      borderSide: BorderSide(color: design.danger),
    ),
    focusedErrorBorder: mobileOutline.copyWith(
      borderSide: BorderSide(color: design.danger, width: 2),
    ),
    disabledBorder: mobileOutline,
  );
  final baseComposer = ComposerTheme.fromTheme(
    shared,
    highContrast: highContrast,
  );
  // Resolve Chinese through the iOS system CJK face before symbol fonts.
  // Keep fixed-width families first so Latin commands retain their metrics.
  final commandFallback = [
    for (final family
        in baseComposer.commandStyle.fontFamilyFallback ?? <String>[]) ...[
      if (resolvedPlatform == TargetPlatform.iOS && family == 'Apple Symbols')
        'PingFang SC',
      family,
    ],
  ];
  final composer = baseComposer.copyWith(
    // Blue belongs to actions and focus, not to all command text/borders.
    foreground: design.text,
    muted: highContrast ? design.text : design.muted,
    border: highContrast ? design.border : design.separator,
    divider: highContrast ? design.border : design.separator,
    commandStyle: baseComposer.commandStyle.copyWith(
      color: design.text,
      fontFamilyFallback: commandFallback,
    ),
    resultStyle: baseComposer.resultStyle.copyWith(
      color: design.text,
      fontFamilyFallback: commandFallback,
    ),
    contextStyle: baseComposer.contextStyle.copyWith(color: design.muted),
    metadataStyle: baseComposer.metadataStyle.copyWith(
      color: design.muted,
      fontSize: touch ? 12 : null,
    ),
    actionStyle: baseComposer.actionStyle.copyWith(
      color: design.text,
      fontSize: touch ? 13 : null,
    ),
    statusStyle: baseComposer.statusStyle.copyWith(color: design.muted),
    // Unfilled marks and cursors need a foreground accent, including on
    // selected blocks. Keep the filled primary action's paired colors.
    accent: design.focus,
    readerTopInset: resolvedPlatform == TargetPlatform.macOS
        ? appWindowTitleBarHeight
        : 0,
  );
  return shared.copyWith(
    pageTransitionsTheme: const AppPageTransitionsTheme(),
    inputDecorationTheme: touch ? mobileInput : desktopInput,
    filledButtonTheme: FilledButtonThemeData(
      style: shared.filledButtonTheme.style?.copyWith(
        overlayColor: FilledButton.styleFrom(
          overlayColor: composer.primaryActionOverlay,
        ).overlayColor,
      ),
    ),
    dropdownMenuTheme: shared.dropdownMenuTheme.copyWith(
      inputDecorationTheme: (touch ? mobileInput : desktopInput).copyWith(
        suffixIconConstraints: shared
            .dropdownMenuTheme
            .inputDecorationTheme
            ?.suffixIconConstraints,
      ),
    ),
    extensions: [...shared.extensions.values, terminal, composer],
  );
}
