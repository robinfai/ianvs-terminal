const int defaultTerminalColumns = 80;
const int defaultTerminalRows = 24;
const int maxTerminalDimension = 0xffff;
const int defaultTerminalScrollbackLines = 8000;
const int maxTerminalScrollbackLines = 100000;
const int defaultTerminalGraphicMaxImageBytes = 100 * 1024 * 1024;
const int defaultTerminalGraphicMaxTotalBytes = 256 * 1024 * 1024;

int normalizeTerminalScrollbackLines(int value) {
  if (value < 1) {
    return defaultTerminalScrollbackLines;
  }
  if (value > maxTerminalScrollbackLines) {
    return maxTerminalScrollbackLines;
  }
  return value;
}

const String terminalPrimaryFontFamily = 'JetBrainsMono Nerd Font Mono';
// Flutter namespaces fonts declared by dependency packages. Keep this separate
// from the portable, user-facing family persisted in profiles and OSC settings.
const String terminalBundledFontFamily =
    'packages/ianvs_terminal_core/JetBrainsMono Nerd Font Mono';
const double terminalFontSize = 14;
const double terminalLineHeight = 1.6;
const List<String> terminalPortableMonospaceFallbacks = <String>[
  'DejaVu Sans Mono',
  'Liberation Mono',
  'Noto Sans Mono',
  'monospace',
];
const List<String> terminalFontFamilyFallback = <String>[
  'Menlo',
  'JetBrainsMono Nerd Font',
  'SF Mono',
  'Monaco',
  ...terminalPortableMonospaceFallbacks,
  'Apple Symbols',
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Noto Color Emoji',
];
