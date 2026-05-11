import 'package:flutter/foundation.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart';

enum TerminalThemePresetTone {
  dark,
  light;

  String get label => switch (this) {
    TerminalThemePresetTone.dark => 'Dark',
    TerminalThemePresetTone.light => 'Light',
  };
}

@immutable
class TerminalThemePreset {
  const TerminalThemePreset({
    required this.id,
    required this.name,
    required this.tone,
    required this.palette,
  });

  final String id;
  final String name;
  final TerminalThemePresetTone tone;
  final TerminalColorPalette palette;

  List<String> get previewColors => <String>[
    palette.special.foreground!,
    palette.special.background!,
    palette.normal.red!,
    palette.normal.green!,
    palette.normal.blue!,
    palette.bright.yellow!,
    palette.special.cursor!,
    palette.special.selection!,
  ];

  bool matchesColors(TerminalColorPalette other) {
    return mapEquals(_flattenColors(palette), _flattenColors(other));
  }
}

Map<String, String?> _flattenColors(TerminalColorPalette palette) {
  return <String, String?>{
    'special.foreground': palette.special.foreground,
    'special.background': palette.special.background,
    'special.cursor': palette.special.cursor,
    'special.selection': palette.special.selection,
    'normal.black': palette.normal.black,
    'normal.red': palette.normal.red,
    'normal.green': palette.normal.green,
    'normal.yellow': palette.normal.yellow,
    'normal.blue': palette.normal.blue,
    'normal.magenta': palette.normal.magenta,
    'normal.cyan': palette.normal.cyan,
    'normal.white': palette.normal.white,
    'bright.black': palette.bright.black,
    'bright.red': palette.bright.red,
    'bright.green': palette.bright.green,
    'bright.yellow': palette.bright.yellow,
    'bright.blue': palette.bright.blue,
    'bright.magenta': palette.bright.magenta,
    'bright.cyan': palette.bright.cyan,
    'bright.white': palette.bright.white,
  };
}

const List<TerminalThemePreset> terminalThemePresets = <TerminalThemePreset>[
  TerminalThemePreset(
    id: 'graphite-night',
    name: 'Graphite Night',
    tone: TerminalThemePresetTone.dark,
    palette: TerminalColorPalette(
      special: TerminalSpecialColors(
        foreground: '#E6EAF2',
        background: '#11141A',
        cursor: '#7DD3FC',
        selection: '#2A3C56',
      ),
      normal: TerminalAnsiColors(
        black: '#1B2028',
        red: '#D96C75',
        green: '#8FB573',
        yellow: '#D8B46B',
        blue: '#6EA9E6',
        magenta: '#BA83D3',
        cyan: '#5FAFB8',
        white: '#CBD3DE',
      ),
      bright: TerminalAnsiColors(
        black: '#5D6875',
        red: '#F48B96',
        green: '#A8D48B',
        yellow: '#E9C989',
        blue: '#8DC6FF',
        magenta: '#D6A2EF',
        cyan: '#79CBD5',
        white: '#F8FBFF',
      ),
    ),
  ),
  TerminalThemePreset(
    id: 'moss-night',
    name: 'Moss Night',
    tone: TerminalThemePresetTone.dark,
    palette: TerminalColorPalette(
      special: TerminalSpecialColors(
        foreground: '#E7F1E8',
        background: '#0F1411',
        cursor: '#9FE870',
        selection: '#294034',
      ),
      normal: TerminalAnsiColors(
        black: '#162019',
        red: '#C66A5C',
        green: '#7FB36A',
        yellow: '#C9B36C',
        blue: '#6D96C9',
        magenta: '#9E82BC',
        cyan: '#5F9C91',
        white: '#D6E0D2',
      ),
      bright: TerminalAnsiColors(
        black: '#5A6A5D',
        red: '#E58A79',
        green: '#9BD285',
        yellow: '#DECD88',
        blue: '#8AB4E2',
        magenta: '#BAA0DA',
        cyan: '#7ABCB0',
        white: '#F5FBF4',
      ),
    ),
  ),
  TerminalThemePreset(
    id: 'ember-dusk',
    name: 'Ember Dusk',
    tone: TerminalThemePresetTone.dark,
    palette: TerminalColorPalette(
      special: TerminalSpecialColors(
        foreground: '#F3E9DD',
        background: '#1A1412',
        cursor: '#F59E0B',
        selection: '#4A3322',
      ),
      normal: TerminalAnsiColors(
        black: '#231A18',
        red: '#D97863',
        green: '#A9B665',
        yellow: '#D7AE5F',
        blue: '#7AA2D6',
        magenta: '#C58ACD',
        cyan: '#5AA6A6',
        white: '#DDD1C5',
      ),
      bright: TerminalAnsiColors(
        black: '#6B5A56',
        red: '#F4977E',
        green: '#C1D47D',
        yellow: '#F0C877',
        blue: '#98BDEA',
        magenta: '#E0A8E4',
        cyan: '#7AC4C3',
        white: '#FFF8F0',
      ),
    ),
  ),
  TerminalThemePreset(
    id: 'paper-slate',
    name: 'Paper Slate',
    tone: TerminalThemePresetTone.light,
    palette: TerminalColorPalette(
      special: TerminalSpecialColors(
        foreground: '#1F2937',
        background: '#F6F3EC',
        cursor: '#2563EB',
        selection: '#C7D7F5',
      ),
      normal: TerminalAnsiColors(
        black: '#2C323D',
        red: '#BE4B49',
        green: '#2E7D5B',
        yellow: '#AD7A20',
        blue: '#2E63B8',
        magenta: '#8657C9',
        cyan: '#0F766E',
        white: '#D7D2C8',
      ),
      bright: TerminalAnsiColors(
        black: '#6B7280',
        red: '#DB6B68',
        green: '#4E9D7A',
        yellow: '#C99636',
        blue: '#4D84DE',
        magenta: '#A078E5',
        cyan: '#2D9E95',
        white: '#FFFDFC',
      ),
    ),
  ),
  TerminalThemePreset(
    id: 'sage-mist',
    name: 'Sage Mist',
    tone: TerminalThemePresetTone.light,
    palette: TerminalColorPalette(
      special: TerminalSpecialColors(
        foreground: '#24312B',
        background: '#F1F5EF',
        cursor: '#2F855A',
        selection: '#CFE3D4',
      ),
      normal: TerminalAnsiColors(
        black: '#2A332E',
        red: '#B95C59',
        green: '#3F7A57',
        yellow: '#A07A32',
        blue: '#446EAC',
        magenta: '#8661B0',
        cyan: '#2B7F7B',
        white: '#D6DDD6',
      ),
      bright: TerminalAnsiColors(
        black: '#6F7873',
        red: '#D97C78',
        green: '#5D9B75',
        yellow: '#BD9650',
        blue: '#648CC6',
        magenta: '#A27DCC',
        cyan: '#4E9F9A',
        white: '#FFFFFF',
      ),
    ),
  ),
];
