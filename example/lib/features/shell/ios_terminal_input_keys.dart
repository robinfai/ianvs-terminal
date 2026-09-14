part of 'ios_terminal_input_bar.dart';

// Direct chords avoid a sticky modifier accidentally affecting later IME text.
final _commonKeys = <_KeySpec>[
  const _KeySpec('Esc', [27], 'Escape'),
  _KeySpec('Tab', [9], 'Tab', (l10n) => l10n.terminalComplete),
  _KeySpec('⌃C', [3], 'Control C', (l10n) => l10n.terminalInterrupt),
  _KeySpec('⌃R', [18], 'Control R', (l10n) => l10n.terminalHistorySearch),
  _KeySpec('⌃L', [12], 'Control L', (l10n) => l10n.terminalClearScreen),
];

final _arrowKeys = <_KeySpec>[
  _KeySpec(
    '←',
    [27, 91, 68],
    'Move cursor left',
    (l10n) => l10n.terminalCursorLeft,
  ),
  _KeySpec(
    '↓',
    [27, 91, 66],
    'Next command',
    (l10n) => l10n.terminalCursorDown,
  ),
  _KeySpec(
    '↑',
    [27, 91, 65],
    'Previous command',
    (l10n) => l10n.terminalCursorUp,
  ),
  _KeySpec(
    '→',
    [27, 91, 67],
    'Move cursor right',
    (l10n) => l10n.terminalCursorRight,
  ),
];

final _editingKeys = <_KeySpec>[
  _KeySpec('⌃A', [1], 'Control A', (l10n) => l10n.terminalLineStart),
  _KeySpec('⌃E', [5], 'Control E', (l10n) => l10n.terminalLineEnd),
  _KeySpec('⌃U', [21], 'Control U', (l10n) => l10n.terminalDeleteToStart),
  _KeySpec('⌃K', [11], 'Control K', (l10n) => l10n.terminalDeleteToEnd),
  _KeySpec('⌃W', [23], 'Control W', (l10n) => l10n.terminalDeleteWord),
  _KeySpec('⌃Y', [25], 'Control Y', (l10n) => l10n.terminalYank),
];

final _controlKeys = <_KeySpec>[
  _KeySpec('⌃D', [4], 'Control D', (l10n) => l10n.terminalEof),
  _KeySpec('⌃Z', [26], 'Control Z', (l10n) => l10n.terminalSuspend),
  _KeySpec('⌃G', [7], 'Control G', (l10n) => l10n.terminalCancel),
  _KeySpec('⌃B', [2], 'Control B', (l10n) => l10n.terminalTmuxPrefix),
  _KeySpec('⌃O', [15], 'Control O', (l10n) => l10n.terminalNanoSave),
  _KeySpec('⌃X', [24], 'Control X', (l10n) => l10n.terminalNanoExit),
];

final _navigationKeys = <_KeySpec>[
  const _KeySpec('Home', [27, 91, 72], 'Home'),
  const _KeySpec('End', [27, 91, 70], 'End'),
  const _KeySpec('PgUp', [27, 91, 53, 126], 'Page up'),
  const _KeySpec('PgDn', [27, 91, 54, 126], 'Page down'),
  const _KeySpec('Del', [27, 91, 51, 126], 'Delete'),
  const _KeySpec('⇧Tab', [27, 91, 90], 'Shift Tab'),
  _KeySpec('⌥B', [27, 98], 'Alt B', (l10n) => l10n.terminalWordBack),
  _KeySpec('⌥F', [27, 102], 'Alt F', (l10n) => l10n.terminalWordForward),
];

const _symbolKeys = <_KeySpec>[
  _KeySpec('/', [47], '/'),
  _KeySpec('-', [45], '-'),
  _KeySpec('_', [95], '_'),
  _KeySpec('|', [124], '|'),
  _KeySpec('~', [126], '~'),
  _KeySpec(r'\', [92], r'\'),
  _KeySpec(r'$', [36], r'$'),
  _KeySpec('&', [38], '&'),
  _KeySpec(';', [59], ';'),
  _KeySpec(':', [58], ':'),
  _KeySpec('.', [46], '.'),
  _KeySpec("'", [39], "'"),
  _KeySpec('"', [34], '"'),
  _KeySpec('`', [96], '`'),
  _KeySpec('(', [40], '('),
  _KeySpec(')', [41], ')'),
  _KeySpec('[', [91], '['),
  _KeySpec(']', [93], ']'),
  _KeySpec('{', [123], '{'),
  _KeySpec('}', [125], '}'),
  _KeySpec('<', [60], '<'),
  _KeySpec('>', [62], '>'),
];

enum _KeyGroup {
  editing,
  control,
  navigation,
  symbols;

  String label(AppLocalizations l10n) => switch (this) {
    editing => l10n.terminalKeysEditing,
    control => l10n.terminalKeysControl,
    navigation => l10n.terminalKeysNavigation,
    symbols => l10n.terminalKeysSymbols,
  };

  List<_KeySpec> get keys => switch (this) {
    editing => _editingKeys,
    control => _controlKeys,
    navigation => _navigationKeys,
    symbols => _symbolKeys,
  };
}

class _KeySpec {
  const _KeySpec(
    this.label,
    this.bytes,
    this.accessibleLabel, [
    this.description,
  ]);

  final String label;
  final List<int> bytes;
  final String accessibleLabel;
  final String Function(AppLocalizations)? description;
}
