import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _captureFont = 'VisualCaptureSans';
const _captureFallback = <String>['VisualCaptureCjk'];

/// Use the same explicit fonts for every macOS visual fixture.
Future<void> loadVisualCaptureFonts() async {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  for (final entry in <String, String>{
    _captureFont: '/System/Library/Fonts/SFNS.ttf',
    _captureFallback.single: '/System/Library/Fonts/STHeiti Medium.ttc',
    'Menlo': '/System/Library/Fonts/Menlo.ttc',
    'MaterialIcons':
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    final loader = FontLoader(entry.key)
      ..addFont(File(entry.value).readAsBytes().then(ByteData.sublistView));
    await loader.load();
  }
}

/// Component themes carry explicit fonts, so textTheme alone is insufficient.
/// Keep production colors, sizes and states while applying loaded capture fonts.
ThemeData withVisualCaptureFonts(ThemeData baseTheme) {
  final inputDecorationTheme = baseTheme.inputDecorationTheme;
  return baseTheme.copyWith(
    filledButtonTheme: FilledButtonThemeData(
      style: baseTheme.filledButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll(
          baseTheme.textTheme.labelLarge!.copyWith(
            fontFamily: _captureFont,
            fontFamilyFallback: _captureFallback,
          ),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: baseTheme.outlinedButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll(
          baseTheme.textTheme.labelLarge!.copyWith(
            fontFamily: _captureFont,
            fontFamilyFallback: _captureFallback,
          ),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: baseTheme.textButtonTheme.style?.copyWith(
        textStyle: WidgetStatePropertyAll(
          baseTheme.textTheme.labelLarge!.copyWith(
            fontFamily: _captureFont,
            fontFamilyFallback: _captureFallback,
          ),
        ),
      ),
    ),
    textTheme: baseTheme.textTheme.apply(
      fontFamily: _captureFont,
      fontFamilyFallback: _captureFallback,
    ),
    primaryTextTheme: baseTheme.primaryTextTheme.apply(
      fontFamily: _captureFont,
      fontFamilyFallback: _captureFallback,
    ),
    inputDecorationTheme: inputDecorationTheme.copyWith(
      labelStyle: inputDecorationTheme.labelStyle?.copyWith(
        fontFamily: _captureFont,
        fontFamilyFallback: _captureFallback,
      ),
      floatingLabelStyle: inputDecorationTheme.floatingLabelStyle?.copyWith(
        fontFamily: _captureFont,
        fontFamilyFallback: _captureFallback,
      ),
      helperStyle: inputDecorationTheme.helperStyle?.copyWith(
        fontFamily: _captureFont,
        fontFamilyFallback: _captureFallback,
      ),
      hintStyle: inputDecorationTheme.hintStyle?.copyWith(
        fontFamily: _captureFont,
        fontFamilyFallback: _captureFallback,
      ),
      errorStyle: inputDecorationTheme.errorStyle?.copyWith(
        fontFamily: _captureFont,
        fontFamilyFallback: _captureFallback,
      ),
    ),
  );
}
