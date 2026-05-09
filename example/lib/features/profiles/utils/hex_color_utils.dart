import 'package:flutter/material.dart';

import '../../terminal/terminal_viewport_colors.dart';

String normalizeHexColor(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return '';
  }

  final withoutHash = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  final isValid = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(withoutHash);
  if (!isValid) {
    throw const FormatException('Invalid hex color');
  }

  return '#${withoutHash.toUpperCase()}';
}

bool isValidOptionalHexColor(String input) {
  try {
    normalizeHexColor(input);
    return true;
  } on FormatException {
    return false;
  }
}

Color? parseOptionalHexColor(String input) {
  final normalized = normalizeHexColor(input);
  if (normalized.isEmpty) {
    return null;
  }

  return terminalViewportColorFromHex(normalized);
}

HSVColor hexToHsvColor(String input) {
  return HSVColor.fromColor(parseOptionalHexColor(input)!);
}

String hsvColorToHex(HSVColor color) {
  return terminalViewportHexFromColor(color.toColor());
}
