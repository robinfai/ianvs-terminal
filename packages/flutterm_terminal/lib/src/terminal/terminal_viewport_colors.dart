import 'package:flutter/material.dart';

class TerminalViewportColors {
  const TerminalViewportColors({
    required this.canvasBackground,
    required this.foreground,
    required this.cursor,
    required this.selection,
    required this.scrollbarTrack,
    required this.scrollbarThumb,
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

  TerminalViewportColors copyWith({
    Color? canvasBackground,
    Color? foreground,
    Color? cursor,
    Color? selection,
    Color? scrollbarTrack,
    Color? scrollbarThumb,
  }) {
    return TerminalViewportColors(
      canvasBackground: canvasBackground ?? this.canvasBackground,
      foreground: foreground ?? this.foreground,
      cursor: cursor ?? this.cursor,
      selection: selection ?? this.selection,
      scrollbarTrack: scrollbarTrack ?? this.scrollbarTrack,
      scrollbarThumb: scrollbarThumb ?? this.scrollbarThumb,
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
        other.scrollbarThumb == scrollbarThumb;
  }

  @override
  int get hashCode => Object.hash(
    canvasBackground,
    foreground,
    cursor,
    selection,
    scrollbarTrack,
    scrollbarThumb,
  );
}

Color? terminalViewportColorFromHex(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final normalized = value.replaceFirst('#', '');
  return Color(int.parse('FF$normalized', radix: 16));
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
