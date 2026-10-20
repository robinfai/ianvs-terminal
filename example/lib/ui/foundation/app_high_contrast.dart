import 'package:ianvs_design/ianvs_design.dart';

/// Keeps the existing palette and typography while strengthening boundaries
/// and secondary text for the system's Increase Contrast preference.
ThemeData withAppHighContrast(ThemeData theme) {
  final design = theme.extension<IanvsTokens>()!;
  final boundary = design.muted;
  final tokens = design.copyWith(
    border: boundary,
    separator: boundary,
    muted: design.text,
    subtle: design.text,
  );
  final scheme = theme.colorScheme.copyWith(
    outline: boundary,
    outlineVariant: boundary,
    onSurfaceVariant: design.text,
  );
  final side = BorderSide(color: boundary, width: 1.5);
  ShapeBorder? outlinedShape(ShapeBorder? shape) =>
      shape is OutlinedBorder ? shape.copyWith(side: side) : shape;
  MenuStyle? outlinedMenu(MenuStyle? style) => style?.copyWith(
    shape: WidgetStateProperty.resolveWith((states) {
      final shape = style.shape?.resolve(states);
      return shape?.copyWith(side: side);
    }),
  );
  InputBorder? outline(InputBorder? border) =>
      border?.copyWith(borderSide: side);
  final input = theme.inputDecorationTheme;
  final text = theme.textTheme;
  final highContrastInput = input.copyWith(
    border: outline(input.border),
    enabledBorder: outline(input.enabledBorder),
    disabledBorder: outline(input.disabledBorder),
    focusedBorder: input.focusedBorder?.copyWith(
      borderSide: BorderSide(color: design.focus, width: 2),
    ),
    labelStyle: input.labelStyle?.copyWith(color: design.text),
    hintStyle: input.hintStyle?.copyWith(color: design.text),
    helperStyle: input.helperStyle?.copyWith(color: design.text),
  );
  return theme.copyWith(
    colorScheme: scheme,
    textTheme: text.copyWith(
      bodySmall: text.bodySmall?.copyWith(color: design.text),
      labelSmall: text.labelSmall?.copyWith(color: design.text),
    ),
    dividerColor: boundary,
    dividerTheme: theme.dividerTheme.copyWith(color: boundary, thickness: 1.5),
    inputDecorationTheme: highContrastInput,
    dropdownMenuTheme: theme.dropdownMenuTheme.copyWith(
      inputDecorationTheme: highContrastInput.copyWith(
        suffixIconConstraints:
            theme.dropdownMenuTheme.inputDecorationTheme?.suffixIconConstraints,
      ),
      menuStyle: outlinedMenu(theme.dropdownMenuTheme.menuStyle),
    ),
    dialogTheme: theme.dialogTheme.copyWith(
      shape: outlinedShape(theme.dialogTheme.shape),
    ),
    popupMenuTheme: theme.popupMenuTheme.copyWith(
      shape: outlinedShape(theme.popupMenuTheme.shape),
    ),
    menuTheme: MenuThemeData(style: outlinedMenu(theme.menuTheme.style)),
    menuBarTheme: MenuBarThemeData(
      style: outlinedMenu(theme.menuBarTheme.style),
    ),
    searchBarTheme: theme.searchBarTheme.copyWith(
      side: WidgetStatePropertyAll(side),
    ),
    chipTheme: theme.chipTheme.copyWith(side: side),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: theme.outlinedButtonTheme.style?.copyWith(
        side: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? BorderSide(color: design.focus, width: 2)
              : side,
        ),
      ),
    ),
    scrollbarTheme: theme.scrollbarTheme.copyWith(
      thumbColor: WidgetStatePropertyAll(boundary),
    ),
    extensions: [
      for (final extension in theme.extensions.values)
        if (extension is! IanvsTokens) extension,
      tokens,
    ],
  );
}
