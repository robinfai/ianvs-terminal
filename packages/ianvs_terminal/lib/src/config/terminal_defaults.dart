const int defaultTerminalColumns = 80;
const int defaultTerminalRows = 24;
const int maxTerminalDimension = 0xffff;
const int defaultTerminalScrollbackLines = 8000;
const int maxTerminalScrollbackLines = 100000;

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
const double terminalFontSize = 14;
const double terminalLineHeight = 1.6;
const List<String> terminalFontFamilyFallback = <String>[
  'Menlo',
  'JetBrainsMono Nerd Font',
  'SF Mono',
  'Monaco',
  'Apple Symbols',
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Noto Color Emoji',
];
