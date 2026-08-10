import 'package:flutter/material.dart';

class TerminalSearchHighlightStyle {
  const TerminalSearchHighlightStyle({
    this.activeFill = const Color(0x570A84FF),
    this.inactiveFill = const Color(0x38FFB000),
    this.activeBorder = const Color(0xD10A84FF),
    this.radius = 3,
  });

  final Color activeFill;
  final Color inactiveFill;
  final Color activeBorder;
  final double radius;

  TerminalSearchHighlightStyle copyWith({
    Color? activeFill,
    Color? inactiveFill,
    Color? activeBorder,
    double? radius,
  }) {
    return TerminalSearchHighlightStyle(
      activeFill: activeFill ?? this.activeFill,
      inactiveFill: inactiveFill ?? this.inactiveFill,
      activeBorder: activeBorder ?? this.activeBorder,
      radius: radius ?? this.radius,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalSearchHighlightStyle &&
        other.activeFill == activeFill &&
        other.inactiveFill == inactiveFill &&
        other.activeBorder == activeBorder &&
        other.radius == radius;
  }

  @override
  int get hashCode =>
      Object.hash(activeFill, inactiveFill, activeBorder, radius);
}

class TerminalViewportColors {
  const TerminalViewportColors({
    required this.canvasBackground,
    required this.foreground,
    required this.cursor,
    required this.selection,
    required this.scrollbarTrack,
    required this.scrollbarThumb,
    this.minimumContrastRatio = 1,
    this.smartCursorColor = false,
  });

  static const light = TerminalViewportColors(
    canvasBackground: Color(0xFFF8F7F2),
    foreground: Color(0xFF111111),
    cursor: Color(0xFF166534),
    selection: Color(0x335B8DEF),
    scrollbarTrack: Color(0x1F111111),
    scrollbarThumb: Color(0x66111111),
  );

  static const dark = TerminalViewportColors(
    canvasBackground: Color(0xFF050608),
    foreground: Color(0xFFF8FAFC),
    cursor: Color(0xFFBBF7D0),
    selection: Color(0x663B82F6),
    scrollbarTrack: Color(0x26FFFFFF),
    scrollbarThumb: Color(0x99FFFFFF),
  );

  factory TerminalViewportColors.fromBrightness(Brightness brightness) {
    if (brightness == Brightness.light) {
      return light;
    }

    return dark;
  }

  final Color canvasBackground;
  final Color foreground;
  final Color cursor;
  final Color selection;
  final Color scrollbarTrack;
  final Color scrollbarThumb;
  final double minimumContrastRatio;
  final bool smartCursorColor;

  TerminalViewportColors copyWith({
    Color? canvasBackground,
    Color? foreground,
    Color? cursor,
    Color? selection,
    Color? scrollbarTrack,
    Color? scrollbarThumb,
    double? minimumContrastRatio,
    bool? smartCursorColor,
  }) {
    return TerminalViewportColors(
      canvasBackground: canvasBackground ?? this.canvasBackground,
      foreground: foreground ?? this.foreground,
      cursor: cursor ?? this.cursor,
      selection: selection ?? this.selection,
      scrollbarTrack: scrollbarTrack ?? this.scrollbarTrack,
      scrollbarThumb: scrollbarThumb ?? this.scrollbarThumb,
      minimumContrastRatio: minimumContrastRatio ?? this.minimumContrastRatio,
      smartCursorColor: smartCursorColor ?? this.smartCursorColor,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalViewportColors &&
        other.canvasBackground == canvasBackground &&
        other.foreground == foreground &&
        other.cursor == cursor &&
        other.selection == selection &&
        other.scrollbarTrack == scrollbarTrack &&
        other.scrollbarThumb == scrollbarThumb &&
        other.minimumContrastRatio == minimumContrastRatio &&
        other.smartCursorColor == smartCursorColor;
  }

  @override
  int get hashCode => Object.hash(
    canvasBackground,
    foreground,
    cursor,
    selection,
    scrollbarTrack,
    scrollbarThumb,
    minimumContrastRatio,
    smartCursorColor,
  );
}

Color? terminalViewportColorFromHex(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final normalized = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  final hex = switch (normalized.length) {
    6 => 'FF$normalized',
    8 => normalized,
    _ => null,
  };
  if (hex == null) {
    return null;
  }
  final colorValue = int.tryParse(hex, radix: 16);
  return colorValue == null ? null : Color(colorValue);
}

String terminalViewportHexFromColor(Color color) {
  final red = _colorChannel(color.r).toRadixString(16).padLeft(2, '0');
  final green = _colorChannel(color.g).toRadixString(16).padLeft(2, '0');
  final blue = _colorChannel(color.b).toRadixString(16).padLeft(2, '0');
  return '#${(red + green + blue).toUpperCase()}';
}

int _colorChannel(double component) {
  return (component * 255).round().clamp(0, 255);
}
