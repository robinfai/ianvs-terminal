import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ianvs_design/ianvs_design.dart' show IanvsTypography;

const _captureFont = 'VisualCaptureSans';
const _captureCjkFont = 'VisualCaptureCjk';
const visualCaptureMonoFont = 'VisualCaptureMono';
const visualCaptureFontFallback = <String>[_captureCjkFont];
const _captureTextFallback = <String>[
  _captureCjkFont,
  // Roboto and Noto Sans SC do not cover every macOS shortcut symbol.
  visualCaptureMonoFont,
];

/// Load only repository assets and fonts from the pinned Flutter SDK.
Future<void> loadVisualCaptureFonts() async {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final sdkFonts = '$flutterRoot/bin/cache/artifacts/material_fonts';
  final fromWorkspace = Directory('example/test/design');
  final fixtures = fromWorkspace.existsSync()
      ? fromWorkspace
      : Directory('test/design');
  final repository = fixtures.absolute.parent.parent.parent;
  final mono =
      '${repository.path}/native/vendor/par-term-emu-core-rust/'
      'src/screenshot/JetBrainsMono-Regular.ttf';
  for (final entry in <String, List<String>>{
    _captureFont: [
      '$sdkFonts/Roboto-Regular.ttf',
      '$sdkFonts/Roboto-Medium.ttf',
      '$sdkFonts/Roboto-Bold.ttf',
      '$sdkFonts/Roboto-Italic.ttf',
      '$sdkFonts/Roboto-BoldItalic.ttf',
    ],
    _captureCjkFont: ['${fixtures.path}/fonts/NotoSansSC-Regular.otf'],
    visualCaptureMonoFont: [mono],
    // Code/path widgets explicitly request this generic family.
    'monospace': [mono],
    'MaterialIcons': ['$sdkFonts/MaterialIcons-Regular.otf'],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}

TextStyle? _text(TextStyle? style) => style?.copyWith(
  fontFamily: _captureFont,
  fontFamilyFallback: _captureTextFallback,
);

WidgetStateProperty<TextStyle?>? _states(
  WidgetStateProperty<TextStyle?>? style,
) => style == null
    ? null
    : WidgetStateProperty.resolveWith((states) => _text(style.resolve(states)));

ButtonStyle? _button(ButtonStyle? style) =>
    style?.copyWith(textStyle: _states(style.textStyle));

InputDecorationThemeData _input(InputDecorationThemeData theme) =>
    theme.copyWith(
      labelStyle: _text(theme.labelStyle),
      floatingLabelStyle: _text(theme.floatingLabelStyle),
      helperStyle: _text(theme.helperStyle),
      hintStyle: _text(theme.hintStyle),
      errorStyle: _text(theme.errorStyle),
      prefixStyle: _text(theme.prefixStyle),
      suffixStyle: _text(theme.suffixStyle),
      counterStyle: _text(theme.counterStyle),
    );

/// Preserve production colors, sizes and states, including component styles
/// and code typography that do not inherit from textTheme.
ThemeData withVisualCaptureFonts(ThemeData theme) {
  return theme.copyWith(
    textTheme: theme.textTheme.apply(
      fontFamily: _captureFont,
      fontFamilyFallback: _captureTextFallback,
    ),
    primaryTextTheme: theme.primaryTextTheme.apply(
      fontFamily: _captureFont,
      fontFamilyFallback: _captureTextFallback,
    ),
    extensions: [
      for (final extension in theme.extensions.values)
        if (extension is IanvsTypography)
          extension.copyWith(
            code: extension.code.copyWith(
              fontFamily: visualCaptureMonoFont,
              fontFamilyFallback: visualCaptureFontFallback,
            ),
          )
        else
          extension,
    ],
    filledButtonTheme: FilledButtonThemeData(
      style: _button(theme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _button(theme.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: _button(theme.textButtonTheme.style),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: _button(theme.elevatedButtonTheme.style),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: _button(theme.iconButtonTheme.style),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: _button(theme.segmentedButtonTheme.style),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: _button(theme.menuButtonTheme.style),
    ),
    inputDecorationTheme: _input(theme.inputDecorationTheme),
    dropdownMenuTheme: theme.dropdownMenuTheme.copyWith(
      textStyle: _text(theme.dropdownMenuTheme.textStyle),
      inputDecorationTheme: theme.dropdownMenuTheme.inputDecorationTheme == null
          ? null
          : _input(theme.dropdownMenuTheme.inputDecorationTheme!),
    ),
    popupMenuTheme: theme.popupMenuTheme.copyWith(
      textStyle: _text(theme.popupMenuTheme.textStyle),
      labelTextStyle: _states(theme.popupMenuTheme.labelTextStyle),
    ),
    chipTheme: theme.chipTheme.copyWith(
      labelStyle: _text(theme.chipTheme.labelStyle),
      secondaryLabelStyle: _text(theme.chipTheme.secondaryLabelStyle),
    ),
    sliderTheme: theme.sliderTheme.copyWith(
      valueIndicatorTextStyle: _text(theme.sliderTheme.valueIndicatorTextStyle),
    ),
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: _text(theme.appBarTheme.titleTextStyle),
      toolbarTextStyle: _text(theme.appBarTheme.toolbarTextStyle),
    ),
    navigationBarTheme: theme.navigationBarTheme.copyWith(
      labelTextStyle: _states(theme.navigationBarTheme.labelTextStyle),
    ),
    navigationRailTheme: theme.navigationRailTheme.copyWith(
      selectedLabelTextStyle: _text(
        theme.navigationRailTheme.selectedLabelTextStyle,
      ),
      unselectedLabelTextStyle: _text(
        theme.navigationRailTheme.unselectedLabelTextStyle,
      ),
    ),
    navigationDrawerTheme: theme.navigationDrawerTheme.copyWith(
      labelTextStyle: _states(theme.navigationDrawerTheme.labelTextStyle),
    ),
    tabBarTheme: theme.tabBarTheme.copyWith(
      labelStyle: _text(theme.tabBarTheme.labelStyle),
      unselectedLabelStyle: _text(theme.tabBarTheme.unselectedLabelStyle),
    ),
    dataTableTheme: theme.dataTableTheme.copyWith(
      headingTextStyle: _text(theme.dataTableTheme.headingTextStyle),
      dataTextStyle: _text(theme.dataTableTheme.dataTextStyle),
    ),
    dialogTheme: theme.dialogTheme.copyWith(
      titleTextStyle: _text(theme.dialogTheme.titleTextStyle),
      contentTextStyle: _text(theme.dialogTheme.contentTextStyle),
    ),
    searchBarTheme: theme.searchBarTheme.copyWith(
      textStyle: _states(theme.searchBarTheme.textStyle),
      hintStyle: _states(theme.searchBarTheme.hintStyle),
    ),
    searchViewTheme: theme.searchViewTheme.copyWith(
      headerTextStyle: _text(theme.searchViewTheme.headerTextStyle),
      headerHintStyle: _text(theme.searchViewTheme.headerHintStyle),
    ),
    tooltipTheme: theme.tooltipTheme.copyWith(
      textStyle: _text(theme.tooltipTheme.textStyle),
    ),
    snackBarTheme: theme.snackBarTheme.copyWith(
      contentTextStyle: _text(theme.snackBarTheme.contentTextStyle),
    ),
  );
}
