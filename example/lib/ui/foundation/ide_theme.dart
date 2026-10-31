import 'package:ianvs_design/ianvs_design.dart';

import 'app_icons.dart';

/// Trail's IDE presentation layer. Shared components retain their behavior,
/// density, font fallback and accessibility contracts.
ThemeData withIdePresentation(ThemeData base) {
  final dark = base.brightness == Brightness.dark;
  final original = base.extension<IanvsTokens>()!;
  final touch = original.density == IanvsDensity.touch;
  final t = original.copyWith(
    canvas: dark ? const Color(0xFF1E1F22) : const Color(0xFFF7F8FA),
    chrome: dark ? const Color(0xFF2B2D30) : const Color(0xFFF0F1F3),
    field: dark ? const Color(0xFF1E1F22) : const Color(0xFFFFFFFF),
    raised: dark ? const Color(0xFF2B2D30) : const Color(0xFFFFFFFF),
    border: dark ? const Color(0xFF6F737A) : const Color(0xFF9DA0A8),
    separator: dark ? const Color(0xFF43454A) : const Color(0xFFD3D5DB),
    text: dark ? const Color(0xFFDFE1E5) : const Color(0xFF1E1F22),
    muted: dark ? const Color(0xFFB4B8C0) : const Color(0xFF60646B),
    subtle: dark ? const Color(0xFFADB1BA) : const Color(0xFF656972),
    accent: const Color(0xFF2457B8),
    focus: dark ? const Color(0xFF8BB4FF) : const Color(0xFF2F65CA),
    selected: dark ? const Color(0xFF25395D) : const Color(0xFFDCE8FC),
    onSelected: dark ? const Color(0xFFDFE1E5) : const Color(0xFF1E1F22),
    controlRadius: 4,
    panelRadius: 6,
    dialogRadius: 8,
  );
  final scheme = base.colorScheme.copyWith(
    primary: t.accent,
    onPrimary: Colors.white,
    primaryContainer: t.selected,
    onPrimaryContainer: t.onSelected,
    secondary: t.accent,
    onSecondary: Colors.white,
    secondaryContainer: t.selected,
    onSecondaryContainer: t.onSelected,
    tertiary: t.accent,
    onTertiary: Colors.white,
    surface: t.canvas,
    onSurface: t.text,
    onSurfaceVariant: t.muted,
    surfaceContainerLowest: t.field,
    surfaceContainerLow: t.chrome,
    surfaceContainer: t.field,
    surfaceContainerHigh: t.raised,
    surfaceContainerHighest: t.chrome,
    outline: t.border,
    outlineVariant: t.separator,
    surfaceTint: Colors.transparent,
    inverseSurface: t.text,
    onInverseSurface: t.canvas,
  );
  final text = base.textTheme.apply(bodyColor: t.text, displayColor: t.text);
  final typography = text.copyWith(
    titleMedium: text.titleMedium?.copyWith(fontSize: touch ? 16 : 14),
    titleSmall: text.titleSmall?.copyWith(fontSize: touch ? 15 : 13),
    bodySmall: text.bodySmall?.copyWith(color: t.muted),
    labelSmall: text.labelSmall?.copyWith(color: t.muted),
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(t.controlRadius),
  );
  WidgetStateProperty<Color?> foreground(Color color) =>
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? t.subtle : color,
      );
  WidgetStateProperty<Color?> fill(Color color) =>
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? t.chrome : color,
      );
  ButtonStyle button(ButtonStyle? old, {Color? background, Color? color}) =>
      (old ?? const ButtonStyle()).copyWith(
        shape: WidgetStatePropertyAll(shape),
        foregroundColor: foreground(color ?? t.text),
        backgroundColor: background == null ? null : fill(background),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return (color ?? t.text).withValues(alpha: .12);
          }
          if (states.contains(WidgetState.hovered)) {
            return (color ?? t.text).withValues(alpha: .06);
          }
          return Colors.transparent;
        }),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.focused) ? t.focus : t.border,
            width: states.contains(WidgetState.focused) ? 2 : 1,
          ),
        ),
      );
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(t.controlRadius),
    borderSide: BorderSide(color: t.border),
  );
  final input = base.inputDecorationTheme.copyWith(
    fillColor: t.field,
    border: outline,
    enabledBorder: outline,
    focusedBorder: outline.copyWith(
      borderSide: BorderSide(color: t.focus, width: 2),
    ),
    disabledBorder: outline.copyWith(
      borderSide: BorderSide(color: t.separator),
    ),
    errorBorder: outline.copyWith(borderSide: BorderSide(color: t.danger)),
    focusedErrorBorder: outline.copyWith(
      borderSide: BorderSide(color: t.danger, width: 2),
    ),
    labelStyle: typography.bodyMedium?.copyWith(color: t.muted),
    hintStyle: typography.bodyMedium?.copyWith(color: t.subtle),
    helperStyle: typography.bodySmall,
    prefixIconColor: t.muted,
    suffixIconColor: t.muted,
  );
  final menu = MenuStyle(
    backgroundColor: WidgetStatePropertyAll(t.raised),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shape: WidgetStatePropertyAll(
      shape.copyWith(side: BorderSide(color: t.border)),
    ),
    padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
    elevation: const WidgetStatePropertyAll(4),
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: t.canvas,
    canvasColor: t.canvas,
    cardColor: t.field,
    textTheme: typography,
    dividerColor: t.separator,
    dividerTheme: DividerThemeData(color: t.separator, thickness: 1, space: 1),
    hoverColor: t.text.withValues(alpha: .06),
    focusColor: t.focus.withValues(alpha: .15),
    highlightColor: t.text.withValues(alpha: .10),
    disabledColor: t.subtle,
    iconTheme: base.iconTheme.copyWith(
      color: t.muted,
      size: touch ? AppIconSize.touch : AppIconSize.toolbar,
    ),
    inputDecorationTheme: input,
    filledButtonTheme: FilledButtonThemeData(
      style: button(base.filledButtonTheme.style).copyWith(
        // Preserve distinct FilledButton and FilledButton.tonal color pairs.
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? t.subtle : null,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled) ? t.chrome : null,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button(base.outlinedButtonTheme.style, background: t.field),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: button(base.elevatedButtonTheme.style, background: t.raised),
    ),
    textButtonTheme: TextButtonThemeData(
      style: button(base.textButtonTheme.style, color: t.focus).copyWith(
        side: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? BorderSide(color: t.focus, width: 2)
              : BorderSide.none,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: button(base.iconButtonTheme.style).copyWith(
        iconSize: WidgetStatePropertyAll(
          touch ? AppIconSize.touch : AppIconSize.toolbar,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? BorderSide(color: t.focus, width: 2)
              : BorderSide.none,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: button(base.segmentedButtonTheme.style).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? t.selected : t.field,
        ),
        foregroundColor: foreground(t.text),
      ),
    ),
    switchTheme: base.switchTheme.copyWith(
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? t.chrome
            : states.contains(WidgetState.selected)
            ? t.accent
            : t.field,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? Colors.white : t.muted,
      ),
      trackOutlineColor: WidgetStatePropertyAll(t.border),
    ),
    checkboxTheme: base.checkboxTheme.copyWith(
      side: BorderSide(color: t.border),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: t.canvas,
      titleTextStyle: typography.titleMedium,
      contentTextStyle: typography.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.dialogRadius),
        side: BorderSide(color: t.border),
      ),
    ),
    menuTheme: MenuThemeData(style: menu),
    menuBarTheme: MenuBarThemeData(style: menu),
    dropdownMenuTheme: base.dropdownMenuTheme.copyWith(
      inputDecorationTheme: input,
      textStyle: typography.bodyMedium,
      menuStyle: menu,
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      color: t.raised,
      textStyle: typography.bodyMedium,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => typography.bodyMedium?.copyWith(
          color: states.contains(WidgetState.disabled) ? t.subtle : t.text,
        ),
      ),
      shape: shape.copyWith(side: BorderSide(color: t.border)),
    ),
    scrollbarTheme: base.scrollbarTheme.copyWith(
      thumbColor: WidgetStatePropertyAll(t.border),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: t.chrome,
      foregroundColor: t.text,
      titleTextStyle: typography.titleMedium,
      iconTheme: base.iconTheme.copyWith(
        color: t.muted,
        size: touch ? AppIconSize.touch : AppIconSize.toolbar,
      ),
    ),
    bottomAppBarTheme: base.bottomAppBarTheme.copyWith(color: t.chrome),
    cardTheme: base.cardTheme.copyWith(
      color: t.field,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.panelRadius),
        side: BorderSide(color: t.separator),
      ),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      textColor: t.text,
      iconColor: t.muted,
      selectedColor: t.onSelected,
      selectedTileColor: t.selected,
      shape: shape,
    ),
    expansionTileTheme: base.expansionTileTheme.copyWith(
      textColor: t.text,
      collapsedTextColor: t.text,
      iconColor: t.muted,
      collapsedIconColor: t.muted,
      shape: Border(bottom: BorderSide(color: t.separator)),
      collapsedShape: Border(bottom: BorderSide(color: t.separator)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: t.field,
      selectedColor: t.selected,
      disabledColor: t.chrome,
      labelStyle: typography.labelLarge,
      secondaryLabelStyle: typography.labelLarge?.copyWith(color: t.onSelected),
      side: BorderSide(color: t.border),
      shape: shape,
      checkmarkColor: t.onSelected,
      deleteIconColor: t.muted,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: t.accent,
      inactiveTrackColor: t.border,
      thumbColor: t.accent,
      overlayColor: t.focus.withValues(alpha: .15),
      valueIndicatorColor: t.raised,
      valueIndicatorTextStyle: typography.labelMedium,
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelColor: t.text,
      unselectedLabelColor: t.muted,
      labelStyle: typography.labelLarge,
      unselectedLabelStyle: typography.labelLarge,
      indicatorColor: t.focus,
      dividerColor: t.separator,
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: t.chrome,
      indicatorColor: t.selected,
      indicatorShape: shape,
      labelTextStyle: WidgetStatePropertyAll(typography.labelMedium),
    ),
    navigationRailTheme: base.navigationRailTheme.copyWith(
      backgroundColor: t.chrome,
      indicatorColor: t.selected,
      indicatorShape: shape,
      selectedIconTheme: IconThemeData(color: t.onSelected),
      unselectedIconTheme: IconThemeData(color: t.muted),
      selectedLabelTextStyle: typography.labelMedium,
      unselectedLabelTextStyle: typography.labelMedium,
    ),
    navigationDrawerTheme: base.navigationDrawerTheme.copyWith(
      backgroundColor: t.chrome,
      indicatorColor: t.selected,
      indicatorShape: shape,
      iconTheme: WidgetStatePropertyAll(IconThemeData(color: t.text)),
      labelTextStyle: WidgetStatePropertyAll(typography.labelLarge),
    ),
    drawerTheme: base.drawerTheme.copyWith(backgroundColor: t.chrome),
    dataTableTheme: base.dataTableTheme.copyWith(
      headingTextStyle: typography.labelLarge,
      dataTextStyle: typography.bodyMedium,
      headingRowColor: WidgetStatePropertyAll(t.chrome),
      dataRowColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? t.selected : null,
      ),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: t.raised,
      modalBackgroundColor: t.raised,
      dragHandleColor: t.muted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(t.dialogRadius),
        ),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: base.menuButtonTheme.style?.copyWith(
        foregroundColor: foreground(t.text),
        textStyle: WidgetStatePropertyAll(typography.bodyMedium),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.focused) ||
                  states.contains(WidgetState.hovered)
              ? t.selected
              : Colors.transparent,
        ),
      ),
    ),
    searchBarTheme: base.searchBarTheme.copyWith(
      backgroundColor: WidgetStatePropertyAll(t.field),
      shape: WidgetStatePropertyAll(shape),
      side: WidgetStatePropertyAll(BorderSide(color: t.border)),
      textStyle: WidgetStatePropertyAll(typography.bodyMedium),
      hintStyle: WidgetStatePropertyAll(
        typography.bodyMedium?.copyWith(color: t.subtle),
      ),
    ),
    searchViewTheme: base.searchViewTheme.copyWith(
      backgroundColor: t.field,
      shape: shape.copyWith(side: BorderSide(color: t.border)),
      headerTextStyle: typography.bodyMedium,
      headerHintStyle: typography.bodyMedium?.copyWith(color: t.subtle),
    ),
    tooltipTheme: base.tooltipTheme.copyWith(
      decoration: BoxDecoration(
        color: t.raised,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(t.controlRadius),
      ),
      textStyle: typography.bodySmall?.copyWith(color: t.text),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      backgroundColor: t.raised,
      contentTextStyle: typography.bodyMedium,
      actionTextColor: t.focus,
      closeIconColor: t.muted,
      shape: shape.copyWith(side: BorderSide(color: t.border)),
    ),
    bannerTheme: base.bannerTheme.copyWith(
      backgroundColor: t.selected,
      contentTextStyle: typography.bodyMedium,
    ),
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
      color: t.focus,
      linearTrackColor: t.border,
      circularTrackColor: t.border,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.focus,
      selectionColor: t.focus.withValues(alpha: .30),
      selectionHandleColor: t.focus,
    ),
    floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
      backgroundColor: t.accent,
      foregroundColor: scheme.onPrimary,
      shape: shape,
    ),
    datePickerTheme: base.datePickerTheme.copyWith(
      backgroundColor: t.raised,
      shape: shape.copyWith(side: BorderSide(color: t.separator)),
      headerBackgroundColor: t.chrome,
      headerForegroundColor: t.text,
      dividerColor: t.separator,
      todayBorder: BorderSide(color: t.focus),
    ),
    timePickerTheme: base.timePickerTheme.copyWith(
      backgroundColor: t.raised,
      shape: shape.copyWith(side: BorderSide(color: t.separator)),
      hourMinuteShape: shape,
      dayPeriodShape: shape,
      dayPeriodColor: WidgetStateColor.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? t.selected : t.field,
      ),
      dayPeriodTextColor: WidgetStateColor.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? t.onSelected : t.text,
      ),
      dayPeriodBorderSide: BorderSide(color: t.border),
      dialBackgroundColor: t.field,
      dialHandColor: t.accent,
      dialTextColor: t.text,
    ),
    extensions: [
      for (final extension in base.extensions.values)
        if (extension is! IanvsTokens && extension is! IanvsTypography)
          extension,
      if (base.extension<IanvsTypography>() case final code?)
        code.copyWith(code: code.code.copyWith(color: t.text)),
      t,
    ],
  );
}
