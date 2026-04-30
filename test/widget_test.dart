import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_pty/flutterm_pty.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;

import 'package:ianvs_terminal/main.dart';
import 'package:ianvs_terminal/src/clipboard_client.dart';
import 'package:ianvs_terminal/src/fig_completion.dart';
import 'package:ianvs_terminal/src/saved_commands.dart';
import 'package:ianvs_terminal/src/session_restore.dart';
import 'package:ianvs_terminal/src/terminal_blocks.dart';
import 'package:ianvs_terminal/src/terminal_panes.dart';
import 'package:ianvs_terminal/src/terminal_settings.dart';

void main() {
  testWidgets('Ianvs Terminal boots a running flutterm-backed shell surface', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      IanvsTerminalApp(backendFactory: () => _FakePtySessionBackend()),
    );
    await tester.pump();

    expect(find.text('Ianvs Terminal'), findsOneWidget);
    expect(find.text('Local shell'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.textContaining('session-1'), findsOneWidget);
  });

  testWidgets('shell exit keeps the terminal surface and shows restart state', (
    WidgetTester tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    backend.exitOnNextPoll = 7;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text('Exited 7'), findsOneWidget);
    expect(find.byTooltip('Restart'), findsOneWidget);
    expect(find.textContaining('session-1'), findsOneWidget);
  });

  testWidgets('restart closes the old session and creates a new local shell', (
    WidgetTester tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    backend.exitOnNextPoll = 0;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.tap(find.byTooltip('Restart'));
    await tester.pump();

    expect(backend.closedSessionIds, contains('session-1'));
    expect(find.text('Running'), findsOneWidget);
    expect(find.textContaining('session-2'), findsOneWidget);
  });

  testWidgets('startup failure can retry shell creation', (tester) async {
    final backend = _FakePtySessionBackend(failuresBeforeSuccess: 1);
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    expect(find.textContaining('Unable to start local shell'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(find.text('Running'), findsOneWidget);
    expect(find.textContaining('session-1'), findsOneWidget);
  });

  testWidgets('modern paste inserts clipboard text into the active draft', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final clipboard = _FakeClipboardClient('echo pasted');

    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        clipboardClient: clipboard,
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Paste'));
    await tester.pump();

    expect(_modernInputText(tester), 'echo pasted');
    expect(backend.writes, isEmpty);
  });

  testWidgets('modern input submits draft only after enter', (tester) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    expect(
      find.byKey(const Key('terminal-modern-input-field')),
      findsOneWidget,
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'ianvs-modern-input',
    );

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'echo ianvs',
    );
    await tester.pump();
    expect(backend.writes, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(backend.writesBySession['session-1'], contains('echo ianvs\r'));
    expect(_modernInputText(tester), isEmpty);
  });

  testWidgets('shift-enter inserts newline before modern submit', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'echo one',
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      '${_modernInputText(tester)}echo two',
    );
    await tester.pump();

    expect(_modernInputText(tester), 'echo one\necho two');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      backend.writesBySession['session-1'],
      contains('echo one\necho two\r'),
    );
  });

  testWidgets('modern input completes brackets and quotes', (tester) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await _sendCharacterKey(
      tester,
      LogicalKeyboardKey.digit9,
      PhysicalKeyboardKey.digit9,
      '(',
    );
    await tester.pump();

    expect(_modernInputText(tester), '()');
    expect(_modernInputValue(tester).selection.baseOffset, 1);
    expect(_modernInputValue(tester).selection.extentOffset, 1);

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      '',
    );
    await tester.pump();

    await _sendCharacterKey(
      tester,
      LogicalKeyboardKey.quote,
      PhysicalKeyboardKey.quote,
      '"',
    );
    await tester.pump();

    expect(_modernInputText(tester), '""');
    expect(_modernInputValue(tester).selection.baseOffset, 1);
  });

  testWidgets('modern input wraps selected text with pairs', (tester) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'echo value',
    );
    _setModernInputValue(
      tester,
      const TextEditingValue(
        text: 'echo value',
        selection: TextSelection(baseOffset: 5, extentOffset: 10),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();

    expect(_modernInputText(tester), 'echo [value]');
    expect(_modernInputValue(tester).selection.baseOffset, 6);
    expect(_modernInputValue(tester).selection.extentOffset, 11);
  });

  testWidgets('modern input skips closing pairs and removes empty pairs', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'echo ()',
    );
    _setModernInputValue(
      tester,
      const TextEditingValue(
        text: 'echo ()',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();

    await _sendCharacterKey(
      tester,
      LogicalKeyboardKey.digit0,
      PhysicalKeyboardKey.digit0,
      ')',
    );
    await tester.pump();

    expect(_modernInputText(tester), 'echo ()');
    expect(_modernInputValue(tester).selection.baseOffset, 7);

    _setModernInputValue(
      tester,
      const TextEditingValue(
        text: 'echo ()',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(_modernInputText(tester), 'echo ');
    expect(_modernInputValue(tester).selection.baseOffset, 5);
  });

  testWidgets('raw mode does not use modern input pair completion', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await _metaShiftShortcut(tester, LogicalKeyboardKey.keyI);
    await _sendCharacterKey(
      tester,
      LogicalKeyboardKey.digit9,
      PhysicalKeyboardKey.digit9,
      '(',
    );
    await tester.pump();

    expect(find.textContaining('Raw input active'), findsOneWidget);
    expect(find.byKey(const Key('terminal-modern-input-field')), findsNothing);
  });

  testWidgets('tab opens completion panel and enter accepts selected item', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        completionRepository: _completionRepository(),
        completionEnvironment: const <String, String>{},
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'demo --',
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(find.byKey(const Key('terminal-completion-panel')), findsOneWidget);
    expect(find.text('--config'), findsOneWidget);
    expect(find.text('--verbose'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(_modernInputText(tester), 'demo --verbose');
    expect(backend.writesBySession['session-1'], isNull);
    expect(find.byKey(const Key('terminal-completion-panel')), findsNothing);
  });

  testWidgets('single completion candidate is accepted immediately with tab', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        completionRepository: _completionRepository(),
        completionEnvironment: const <String, String>{},
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'de',
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(_modernInputText(tester), 'demo');
    expect(find.byKey(const Key('terminal-completion-panel')), findsNothing);
  });

  testWidgets('completion state is isolated per tab and raw mode ignores tab', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        completionRepository: _completionRepository(),
        completionEnvironment: const <String, String>{},
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'demo --',
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(find.byKey(const Key('terminal-completion-panel')), findsOneWidget);

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );
    expect(find.byKey(const Key('terminal-completion-panel')), findsNothing);

    await _metaShiftShortcut(tester, LogicalKeyboardKey.keyI);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(find.textContaining('Raw input active'), findsOneWidget);
    expect(find.byKey(const Key('terminal-completion-panel')), findsNothing);

    await _previousTabShortcut(tester);
    expect(find.byKey(const Key('terminal-completion-panel')), findsOneWidget);
  });

  testWidgets('exited shell does not open completion panel', (tester) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        completionRepository: _completionRepository(),
        completionEnvironment: const <String, String>{},
      ),
    );
    await tester.pump();

    backend.exitOnNextPoll = 0;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(find.text('Exited 0'), findsOneWidget);
    expect(find.byKey(const Key('terminal-completion-panel')), findsNothing);
  });

  testWidgets('raw toggle routes paste to terminal and cmd-k returns modern', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final clipboard = _FakeClipboardClient('echo raw');
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        clipboardClient: clipboard,
      ),
    );
    await tester.pump();

    await _metaShiftShortcut(tester, LogicalKeyboardKey.keyI);
    expect(find.textContaining('Raw input active'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'ianvs-terminal');

    await tester.tap(find.byTooltip('Paste'));
    await tester.pump();
    expect(backend.writesBySession['session-1'], contains('echo raw'));

    await _metaShortcut(tester, LogicalKeyboardKey.keyK);
    expect(
      find.byKey(const Key('terminal-modern-input-field')),
      findsOneWidget,
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'ianvs-modern-input',
    );
  });

  testWidgets(
    'frame modes trigger automatic raw hint and clear back to modern',
    (tester) async {
      final backend = _FakePtySessionBackend();
      await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
      await tester.pump();

      backend.enqueueFrame(
        _frameJson(modes: const <String, Object?>{'application_cursor': true}),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(find.textContaining('Auto raw'), findsOneWidget);
      expect(
        find.byKey(const Key('terminal-modern-input-field')),
        findsNothing,
      );

      backend.enqueueFrame(_frameJson());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(
        find.byKey(const Key('terminal-modern-input-field')),
        findsOneWidget,
      );
    },
  );

  testWidgets('modern input draft and raw mode are isolated per tab', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'echo first',
    );
    await tester.pump();

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );
    expect(_modernInputText(tester), isEmpty);

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'echo second',
    );
    await tester.pump();
    await _metaShiftShortcut(tester, LogicalKeyboardKey.keyI);
    expect(find.textContaining('Raw input active'), findsOneWidget);

    await _previousTabShortcut(tester);
    expect(_modernInputText(tester), 'echo first');

    await _nextTabShortcut(tester);
    expect(find.textContaining('Raw input active'), findsOneWidget);
  });

  testWidgets('exit disables modern input and restart resets it', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'pending',
    );
    await tester.pump();
    backend.exitOnNextPoll = 0;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    final exitedField = tester.widget<TextField>(
      find.byKey(const Key('terminal-modern-input-field')),
    );
    expect(exitedField.enabled, isFalse);
    expect(_modernInputText(tester), 'pending');

    await tester.tap(find.byTooltip('Restart'));
    await tester.pump();

    expect(_modernInputText(tester), isEmpty);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'ianvs-modern-input',
    );
  });

  testWidgets('search button opens find bar and query updates result count', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    backend.searchResults['ianvs'] = <Map<String, Object?>>[
      _matchJson(row: 2, startCol: 4, endCol: 9, text: 'ianvs', offset: 3),
      _matchJson(row: 8, startCol: 0, endCol: 5, text: 'ianvs', offset: 1),
    ];

    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await tester.tap(find.byTooltip('Search'));
    await tester.pump();

    expect(find.byKey(const Key('terminal-find-field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('terminal-find-field')),
      'ianvs',
    );
    await tester.pump();

    expect(backend.searchedQueries, contains('ianvs'));
    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('cmd-f opens find bar and escape closes it', (tester) async {
    await tester.pumpWidget(
      IanvsTerminalApp(backendFactory: () => _FakePtySessionBackend()),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(find.byKey(const Key('terminal-find-field')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.byKey(const Key('terminal-find-field')), findsNothing);
  });

  testWidgets('find navigation scrolls to matches and updates active index', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    backend.searchResults['ianvs'] = <Map<String, Object?>>[
      _matchJson(row: 2, startCol: 4, endCol: 9, text: 'ianvs', offset: 3),
      _matchJson(row: 8, startCol: 0, endCol: 5, text: 'ianvs', offset: 1),
    ];

    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('terminal-find-field')),
      'ianvs',
    );
    await tester.pump();

    expect(backend.scrollToOffsets, contains(3));

    await tester.tap(find.byTooltip('Next match'));
    await tester.pump();

    expect(backend.scrollToOffsets, contains(1));
    expect(find.text('2/2'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous match'));
    await tester.pump();

    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('copy writes the active search selection to clipboard', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend(selectedText: 'ianvs');
    final clipboard = _FakeClipboardClient('');
    backend.searchResults['ianvs'] = <Map<String, Object?>>[
      _matchJson(row: 2, startCol: 4, endCol: 9, text: 'ianvs', offset: 3),
    ];

    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        clipboardClient: clipboard,
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('terminal-find-field')),
      'ianvs',
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Copy'));
    await tester.pump();

    expect(clipboard.copied, contains('ianvs'));
  });

  testWidgets('exited shell still supports find and copy but disables paste', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend(selectedText: 'ready');
    final clipboard = _FakeClipboardClient('');
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        clipboardClient: clipboard,
      ),
    );
    await tester.pump();

    backend.exitOnNextPoll = 0;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    final pasteButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.content_paste),
    );
    expect(pasteButton.onPressed, isNull);

    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('terminal-find-field')),
      'ready',
    );
    await tester.pump();

    expect(find.text('1/1'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy'));
    await tester.pump();

    expect(clipboard.copied, contains('ready'));
  });

  testWidgets('empty find result shows zero count and does not scroll', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('terminal-find-field')),
      'missing',
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Next match'));
    await tester.tap(find.byTooltip('Previous match'));
    await tester.pump();

    expect(find.text('0/0'), findsOneWidget);
    expect(backend.scrollToOffsets, isEmpty);
  });

  testWidgets('block controls are disabled when no block is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      IanvsTerminalApp(backendFactory: () => _FakePtySessionBackend()),
    );
    await tester.pump();

    expect(find.text('Block 0/0'), findsOneWidget);
    expect(find.byKey(const Key('terminal-block-panel')), findsNothing);
    expect(
      _headerIconButton(
        tester,
        const Key('terminal-block-previous-button'),
      ).onPressed,
      isNull,
    );
    expect(
      _headerIconButton(
        tester,
        const Key('terminal-block-copy-command-button'),
      ).onPressed,
      isNull,
    );
    expect(
      _headerIconButton(
        tester,
        const Key('terminal-block-reinput-button'),
      ).onPressed,
      isNull,
    );
  });

  testWidgets('injected blocks show status preview and support navigation', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        initialBlocksForSession: _blocksForSession,
      ),
    );
    await tester.pump();

    expect(find.text('Block 2/2'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.textContaining('false'), findsWidgets);

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-previous-button')),
    );
    expect(find.text('Block 1/2'), findsOneWidget);
    expect(backend.scrollToOffsets, contains(2));

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-next-button')),
    );
    expect(find.text('Block 2/2'), findsOneWidget);
    expect(backend.scrollToOffsets, contains(9));
  });

  testWidgets('block history panel shows previews and selects blocks', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        initialBlocksForSession: _blocksForSession,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('terminal-block-panel')), findsOneWidget);
    expect(
      find.byKey(const Key('terminal-block-row-session-1-block-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-block-row-session-1-block-2')),
      findsOneWidget,
    );
    expect(find.text('/tmp'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('terminal-block-row-session-1-block-1')),
    );
    await tester.pump();

    expect(find.text('Block 1/2'), findsOneWidget);
    expect(backend.scrollToOffsets, contains(2));
  });

  testWidgets('block panel actions target only the active tab', (tester) async {
    final backend = _FakePtySessionBackend();
    final clipboard = _FakeClipboardClient('');
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        clipboardClient: clipboard,
        initialBlocksForSession: _blocksForSession,
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('terminal-block-row-session-1-block-1')),
    );
    await tester.pump();
    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-panel-copy-command-button')),
    );
    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-panel-copy-output-button')),
    );
    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-panel-copy-all-button')),
    );
    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-panel-reinput-button')),
    );

    expect(clipboard.copied, containsAll(<String>['pwd', '/tmp\n']));
    expect(clipboard.copied, contains('pwd\n/tmp\n'));
    expect(_modernInputText(tester), 'pwd');
    expect(backend.writesBySession['session-1'], isNull);

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );
    expect(find.text('Block 1/1'), findsOneWidget);

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-panel-copy-command-button')),
    );
    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-panel-reinput-button')),
    );

    expect(clipboard.copied, contains('echo second'));
    expect(_modernInputText(tester), 'echo second');
    expect(backend.writesBySession['session-2'], isNull);
  });

  testWidgets('block history panel follows the active tab', (tester) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        initialBlocksForSession: _blocksForSession,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('terminal-block-row-session-1-block-2')),
      findsOneWidget,
    );

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );

    expect(
      find.byKey(const Key('terminal-block-row-session-2-block-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-block-row-session-1-block-2')),
      findsNothing,
    );

    await _previousTabShortcut(tester);

    expect(
      find.byKey(const Key('terminal-block-row-session-1-block-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-block-row-session-2-block-1')),
      findsNothing,
    );
  });

  testWidgets('exited shell block panel allows copy but disables reinput', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final clipboard = _FakeClipboardClient('');
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        clipboardClient: clipboard,
        initialBlocksForSession: _blocksForSession,
      ),
    );
    await tester.pump();

    backend.exitOnNextPoll = 0;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('terminal-block-row-session-1-block-1')),
    );
    await tester.pump();
    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-panel-copy-output-button')),
    );

    final reinputButton = _headerIconButton(
      tester,
      const Key('terminal-block-panel-reinput-button'),
    );
    expect(clipboard.copied, contains('/tmp\n'));
    expect(reinputButton.onPressed, isNull);
  });

  testWidgets('block copy and reinput target only the active tab', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final clipboard = _FakeClipboardClient('');
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        clipboardClient: clipboard,
        initialBlocksForSession: _blocksForSession,
      ),
    );
    await tester.pump();

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );
    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-copy-command-button')),
    );
    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-reinput-button')),
    );

    expect(clipboard.copied, contains('echo second'));
    expect(_modernInputText(tester), 'echo second');
    expect(backend.writesBySession['session-2'], isNull);

    await _previousTabShortcut(tester);
    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-copy-command-button')),
    );
    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-reinput-button')),
    );

    expect(clipboard.copied, contains('false'));
    expect(_modernInputText(tester), 'false');
    expect(backend.writesBySession['session-1'], isNull);
  });

  testWidgets('blocks are isolated per tab', (tester) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        initialBlocksForSession: _blocksForSession,
      ),
    );
    await tester.pump();

    expect(find.text('Block 2/2'), findsOneWidget);
    expect(find.textContaining('false'), findsWidgets);

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );

    expect(find.text('Block 1/1'), findsOneWidget);
    expect(find.textContaining('echo second'), findsWidgets);

    await _previousTabShortcut(tester);

    expect(find.text('Block 2/2'), findsOneWidget);
    expect(find.textContaining('false'), findsWidgets);
  });

  testWidgets('cmd-r opens command history search and enter fills draft', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        initialBlocksForSession: _blocksForSession,
      ),
    );
    await tester.pump();

    await _metaShortcut(tester, LogicalKeyboardKey.keyR);
    expect(
      find.byKey(const Key('terminal-command-history-panel')),
      findsOneWidget,
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'ianvs-command-history',
    );

    await tester.enterText(
      find.byKey(const Key('terminal-command-history-field')),
      'PW',
    );
    await tester.pump();

    expect(find.text('1/1'), findsOneWidget);
    expect(find.textContaining('pwd'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      find.byKey(const Key('terminal-command-history-panel')),
      findsNothing,
    );
    expect(_modernInputText(tester), 'pwd');
    expect(backend.writesBySession['session-1'], isNull);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'ianvs-modern-input',
    );
  });

  testWidgets('history button opens panel and arrow keys cycle results', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        initialBlocksForSession: _blocksForSession,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('terminal-command-history-button')));
    await tester.pump();

    expect(find.text('1/2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('2/2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('command history is isolated per tab', (tester) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        initialBlocksForSession: _blocksForSession,
      ),
    );
    await tester.pump();

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );
    await tester.tap(find.byKey(const Key('terminal-command-history-button')));
    await tester.pump();

    expect(find.textContaining('echo second'), findsWidgets);
    expect(find.textContaining('false'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_modernInputText(tester), 'echo second');

    await _previousTabShortcut(tester);
    await _metaShortcut(tester, LogicalKeyboardKey.keyR);

    expect(find.textContaining('false'), findsWidgets);
    expect(find.textContaining('echo second'), findsNothing);
  });

  testWidgets('raw mode does not open command history search', (tester) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        initialBlocksForSession: _blocksForSession,
      ),
    );
    await tester.pump();

    await _metaShiftShortcut(tester, LogicalKeyboardKey.keyI);
    await _metaShortcut(tester, LogicalKeyboardKey.keyR);

    expect(find.textContaining('Raw input active'), findsOneWidget);
    expect(
      find.byKey(const Key('terminal-command-history-panel')),
      findsNothing,
    );
  });

  testWidgets('exited shell can view history but cannot reinput it', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        initialBlocksForSession: _blocksForSession,
      ),
    );
    await tester.pump();

    backend.exitOnNextPoll = 0;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    await tester.tap(find.byKey(const Key('terminal-command-history-button')));
    await tester.pump();
    expect(
      find.byKey(const Key('terminal-command-history-panel')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(_modernInputText(tester), isEmpty);
    expect(
      find.byKey(const Key('terminal-command-history-panel')),
      findsOneWidget,
    );
  });

  testWidgets('save command button stores current draft as saved command', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final savedStore = _savedCommandsStore();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        savedCommandsStore: savedStore,
      ),
    );
    await tester.pump();

    expect(
      _headerIconButton(
        tester,
        const Key('terminal-save-command-button'),
      ).onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      '  echo saved  ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('terminal-save-command-button')));
    await tester.pump();

    expect(savedStore.load().commands, <String>['echo saved']);

    await _metaShortcut(tester, LogicalKeyboardKey.keyR);

    expect(find.text('Saved'), findsOneWidget);
    expect(find.textContaining('echo saved'), findsWidgets);
  });

  testWidgets('command search shows saved and history entries with sources', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final savedStore = _savedCommandsStore()
      ..save(const SavedCommandsState(commands: <String>['echo saved']));
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        savedCommandsStore: savedStore,
        initialBlocksForSession: _blocksForSession,
      ),
    );
    await tester.pump();

    await _metaShortcut(tester, LogicalKeyboardKey.keyR);

    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('History'), findsWidgets);
    expect(find.textContaining('echo saved'), findsWidgets);
    expect(find.textContaining('false'), findsWidgets);
  });

  testWidgets('history row can be saved and saved row can be removed', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final savedStore = _savedCommandsStore();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        savedCommandsStore: savedStore,
        initialBlocksForSession: _blocksForSession,
      ),
    );
    await tester.pump();

    await _metaShortcut(tester, LogicalKeyboardKey.keyR);
    await tester.enterText(
      find.byKey(const Key('terminal-command-history-field')),
      'pwd',
    );
    await tester.pump();

    expect(find.text('History'), findsOneWidget);

    await tester.tap(find.byTooltip('Save history command'));
    await tester.pump();

    expect(savedStore.load().commands, <String>['pwd']);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('History'), findsNothing);

    await tester.tap(find.byTooltip('Remove saved command'));
    await tester.pump();

    expect(savedStore.load().commands, isEmpty);
    expect(find.text('History'), findsOneWidget);
  });

  testWidgets('saved commands are global while history follows active tab', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final savedStore = _savedCommandsStore()
      ..save(const SavedCommandsState(commands: <String>['echo global']));
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        savedCommandsStore: savedStore,
        initialBlocksForSession: _blocksForSession,
      ),
    );
    await tester.pump();

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );
    await _metaShortcut(tester, LogicalKeyboardKey.keyR);

    expect(find.textContaining('echo global'), findsWidgets);
    expect(find.textContaining('echo second'), findsWidgets);
    expect(find.textContaining('false'), findsNothing);
  });

  testWidgets('saved commands reload after rebuilding the app', (tester) async {
    final backend = _FakePtySessionBackend();
    final savedStore = _savedCommandsStore();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        savedCommandsStore: savedStore,
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'echo persisted',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('terminal-save-command-button')));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        savedCommandsStore: savedStore,
      ),
    );
    await tester.pump();

    await _metaShortcut(tester, LogicalKeyboardKey.keyR);

    expect(find.text('Saved'), findsOneWidget);
    expect(find.textContaining('echo persisted'), findsWidgets);
  });

  testWidgets('exited shell keeps existing block copy and jump actions', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final clipboard = _FakeClipboardClient('');
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        clipboardClient: clipboard,
        initialBlocksForSession: _blocksForSession,
      ),
    );
    await tester.pump();

    backend.exitOnNextPoll = 0;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text('Exited 0'), findsOneWidget);
    expect(find.text('Block 2/2'), findsOneWidget);

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-previous-button')),
    );
    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-copy-output-button')),
    );

    expect(backend.scrollToOffsets, contains(2));
    expect(clipboard.copied, contains('/tmp\n'));
    expect(find.text('Block 3/3'), findsNothing);
  });

  testWidgets('generic shell hooks create and finish command blocks', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend(selectedText: 'ianvs-block\n');
    final clipboard = _FakeClipboardClient('');
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        clipboardClient: clipboard,
      ),
    );
    await tester.pump();

    backend.enqueueEvent(
      'session-1',
      const PtyEvent(
        kind: 'shell_hook',
        sessionId: 'session-1',
        payload: <String, Object?>{
          'hook': 'preexec',
          'command': 'echo ianvs-block',
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text('Block 1/1'), findsOneWidget);
    expect(find.text('Running'), findsNWidgets(2));
    expect(find.textContaining('echo ianvs-block'), findsWidgets);

    backend.enqueueFrame(
      _frameJson(text: 'ianvs-block', cursorRow: 2, viewportRows: 3),
    );
    backend.enqueueEvent(
      'session-1',
      const PtyEvent(
        kind: 'shell_hook',
        sessionId: 'session-1',
        payload: <String, Object?>{'hook': 'command_finished', 'exit_code': 0},
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text('Succeeded'), findsOneWidget);

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-copy-output-button')),
    );

    expect(clipboard.copied, contains('ianvs-block\n'));
  });

  testWidgets('shell hook exit codes map to failed and interrupted blocks', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    backend.enqueueEvent(
      'session-1',
      const PtyEvent(
        kind: 'shell_hook',
        sessionId: 'session-1',
        payload: <String, Object?>{'hook': 'preexec', 'command': 'false'},
      ),
    );
    backend.enqueueEvent(
      'session-1',
      const PtyEvent(
        kind: 'shell_hook',
        sessionId: 'session-1',
        payload: <String, Object?>{'hook': 'command_finished', 'exit_code': 1},
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text('Failed'), findsOneWidget);

    backend.enqueueEvent(
      'session-1',
      const PtyEvent(
        kind: 'shell_hook',
        sessionId: 'session-1',
        payload: <String, Object?>{'hook': 'preexec', 'command': 'sleep 10'},
      ),
    );
    backend.enqueueEvent(
      'session-1',
      const PtyEvent(
        kind: 'shell_hook',
        sessionId: 'session-1',
        payload: <String, Object?>{
          'hook': 'command_finished',
          'exit_code': 130,
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text('Interrupted'), findsOneWidget);
  });

  testWidgets('non zsh default shell does not inject zsh hook env', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        settingsStore: _settingsStore(defaultShell: '/bin/bash'),
      ),
    );
    await tester.pump();

    final env = _createdEnvAt(backend, 0);

    expect(env.containsKey('ZDOTDIR'), isFalse);
    expect(env.containsKey('FLUTTERM_SHELL_HOOKS'), isFalse);
  });

  testWidgets('delta rows without dirty ranges still repaint prompt text', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    backend.enqueueFrame(
      _frameJson(
        kind: 'snapshot',
        text: '',
        cursorCol: 0,
        dirtyRanges: const <Map<String, Object?>>[
          <String, Object?>{'start': 0, 'end': 1},
        ],
      ),
    );
    backend.enqueueFrame(
      _frameJson(
        kind: 'delta',
        text: '% ianvs',
        cursorCol: 7,
        dirtyRanges: const <Map<String, Object?>>[],
      ),
    );

    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    final renderObject = tester.renderObject<terminal.RenderTerminalViewport>(
      find.byElementPredicate(
        (element) => element.renderObject is terminal.RenderTerminalViewport,
      ),
    );
    final paintedText = renderObject
        .debugResolvedCellsForRow(0)
        .map((cell) => cell.text)
        .join();

    expect(paintedText, contains('ianvs'));
  });

  testWidgets('blank startup cursor row requests a full repaint for prompt', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    backend.enqueueFrame(
      _frameJson(
        kind: 'delta',
        text: '',
        cursorCol: 7,
        dirtyRanges: const <Map<String, Object?>>[],
      ),
    );
    backend.frameOnScrollTo = _frameJson(
      kind: 'snapshot',
      text: '% ianvs',
      cursorCol: 7,
    );

    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(backend.scrollToOffsets, contains(0));
    final paintedText = _renderViewport(
      tester,
    ).debugResolvedCellsForRow(0).map((cell) => cell.text).join();
    expect(paintedText, contains('ianvs'));
  });

  testWidgets('platform menu exposes desktop terminal actions', (tester) async {
    await tester.pumpWidget(
      IanvsTerminalApp(backendFactory: () => _FakePtySessionBackend()),
    );
    await tester.pump();

    final menuBar = tester.widget<PlatformMenuBar>(
      find.byType(PlatformMenuBar),
    );
    final labels = _platformMenuLabels(menuBar.menus);

    expect(
      labels,
      containsAll(<String>[
        'Terminal',
        'Settings',
        'New Tab',
        'Close Tab',
        'Restart',
        'Find',
        'Copy',
        'Paste',
        'Split Right',
        'Split Down',
        'Close Pane',
        'Next Pane',
        'Previous Pane',
      ]),
    );
  });

  testWidgets('platform menu callbacks act on the active tab', (tester) async {
    final backend = _FakePtySessionBackend();
    final clipboard = _FakeClipboardClient('echo from-menu');
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        clipboardClient: clipboard,
        settingsStore: _settingsStore(),
      ),
    );
    await tester.pump();

    _selectPlatformMenuItem(tester, 'New Tab');
    await tester.pump();
    expect(find.textContaining('session-2'), findsOneWidget);

    _selectPlatformMenuItem(tester, 'Paste');
    await tester.pump();
    expect(_modernInputText(tester), 'echo from-menu');
    expect(backend.writesBySession['session-2'], isNull);

    _selectPlatformMenuItem(tester, 'Find');
    await tester.pump();
    expect(find.byKey(const Key('terminal-find-field')), findsOneWidget);

    _selectPlatformMenuItem(tester, 'Restart');
    await tester.pump();
    expect(backend.closedSessionIds, contains('session-2'));
    expect(find.textContaining('session-3'), findsOneWidget);

    _selectPlatformMenuItem(tester, 'Settings');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('terminal-settings-panel')), findsOneWidget);
  });

  testWidgets('platform menu split pane actions follow pane state', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    expect(_platformMenuItem(tester, 'Close Pane').onSelected, isNull);
    expect(_platformMenuItem(tester, 'Split Right').onSelected, isNotNull);
    expect(_platformMenuItem(tester, 'Split Down').onSelected, isNotNull);

    _selectPlatformMenuItem(tester, 'Split Right');
    await tester.pump();

    expect(find.byKey(const Key('terminal-pane-1')), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-2')), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-active-2')), findsOneWidget);
    expect(_platformMenuItem(tester, 'Close Pane').onSelected, isNotNull);

    _selectPlatformMenuItem(tester, 'Close Pane');
    await tester.pump();

    expect(backend.closedSessionIds, contains('session-2'));
    expect(find.byKey(const Key('terminal-pane-2')), findsNothing);
    expect(_platformMenuItem(tester, 'Close Pane').onSelected, isNull);
  });

  testWidgets('platform menu enabled state follows active shell state', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    expect(_platformMenuItem(tester, 'Close Tab').onSelected, isNull);
    expect(_platformMenuItem(tester, 'Paste').onSelected, isNotNull);
    expect(_platformMenuItem(tester, 'Copy').onSelected, isNotNull);
    expect(_platformMenuItem(tester, 'Restart').onSelected, isNotNull);
    expect(_platformMenuItem(tester, 'Find').onSelected, isNotNull);

    backend.exitOnNextPoll = 0;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(_platformMenuItem(tester, 'Paste').onSelected, isNull);
    expect(_platformMenuItem(tester, 'Copy').onSelected, isNotNull);
    expect(_platformMenuItem(tester, 'Restart').onSelected, isNotNull);
    expect(_platformMenuItem(tester, 'Find').onSelected, isNotNull);

    _selectPlatformMenuItem(tester, 'New Tab');
    await tester.pump();
    expect(_platformMenuItem(tester, 'Close Tab').onSelected, isNotNull);
  });

  testWidgets('new tab creates and activates another local shell', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    expect(find.text('Local 1'), findsOneWidget);
    expect(find.textContaining('session-1'), findsOneWidget);

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );

    expect(find.text('Local 2'), findsOneWidget);
    expect(find.textContaining('session-2'), findsOneWidget);
    expect(backend.createdSessionIds, <String>['session-1', 'session-2']);
  });

  testWidgets('tab actions target only the active shell', (tester) async {
    final backend = _FakePtySessionBackend();
    final clipboard = _FakeClipboardClient('echo from-active-tab');
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        clipboardClient: clipboard,
      ),
    );
    await tester.pump();

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );
    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-paste-button')),
    );

    expect(_modernInputText(tester), 'echo from-active-tab');

    await _previousTabShortcut(tester);
    clipboard.text = 'echo from-first-tab';
    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-paste-button')),
    );

    expect(_modernInputText(tester), 'echo from-first-tab');
    expect(backend.writesBySession['session-1'], isNull);
    expect(backend.writesBySession['session-2'], isNull);
  });

  testWidgets('closing active tab disposes it and selects a neighbor', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );
    final closeSecondTab = tester.widget<IconButton>(
      find.byKey(const Key('terminal-close-tab-Local 2')),
    );
    closeSecondTab.onPressed!();
    await tester.pump();

    expect(backend.closedSessionIds, contains('session-2'));
    expect(find.text('Local 2'), findsNothing);
    expect(find.textContaining('session-1'), findsOneWidget);
  });

  testWidgets('inactive tab exit is visible after switching back', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();
    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );

    backend.exitOnNextPollBySession['session-1'] = 5;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text('Running'), findsOneWidget);
    expect(find.textContaining('session-2'), findsOneWidget);

    await _previousTabShortcut(tester);

    expect(find.text('Exited 5'), findsOneWidget);
    expect(find.textContaining('session-1'), findsOneWidget);
  });

  testWidgets('last tab cannot be closed with button or cmd-w', (tester) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    final closeOnlyTab = tester.widget<IconButton>(
      find.byKey(const Key('terminal-close-tab-Local 1')),
    );
    closeOnlyTab.onPressed!();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(backend.closedSessionIds, isEmpty);
    expect(find.text('Local 1'), findsOneWidget);
    expect(find.textContaining('session-1'), findsOneWidget);
  });

  testWidgets('tab title follows window title and falls back to local number', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    backend.enqueueFrame(_frameJson(windowTitle: 'project-alpha'));
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    expect(find.text('project-alpha'), findsOneWidget);
    expect(find.text('Local 1'), findsNothing);

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );

    expect(find.text('Local 2'), findsOneWidget);
  });

  testWidgets('tab keyboard shortcuts create close and switch tabs', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(find.text('Local 2'), findsOneWidget);
    expect(find.textContaining('session-2'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(find.textContaining('session-1'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(backend.closedSessionIds, contains('session-1'));
    expect(find.textContaining('session-2'), findsOneWidget);
  });

  testWidgets('split panes render together and actions target active pane', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final clipboard = _FakeClipboardClient('echo pane-two');
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        clipboardClient: clipboard,
      ),
    );
    await tester.pump();

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-split-right-button')),
    );

    expect(find.byKey(const Key('terminal-pane-1')), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-2')), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-active-2')), findsOneWidget);
    expect(find.textContaining('session-1'), findsOneWidget);
    expect(find.textContaining('session-2'), findsOneWidget);

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-paste-button')),
    );
    expect(_modernInputText(tester), 'echo pane-two');

    clipboard.text = 'echo pane-one';
    await tester.tap(find.byKey(const Key('terminal-pane-1')));
    await tester.pump();
    expect(find.byKey(const Key('terminal-pane-active-1')), findsOneWidget);
    expect(_modernInputText(tester), isEmpty);

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-paste-button')),
    );
    expect(_modernInputText(tester), 'echo pane-one');
    expect(backend.writesBySession['session-1'], isNull);
    expect(backend.writesBySession['session-2'], isNull);
  });

  testWidgets('pane keyboard shortcuts split switch and close panes', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await _metaShortcut(tester, LogicalKeyboardKey.keyD);
    expect(find.byKey(const Key('terminal-pane-active-2')), findsOneWidget);

    await _metaShiftShortcut(tester, LogicalKeyboardKey.keyD);
    expect(find.byKey(const Key('terminal-pane-active-3')), findsOneWidget);

    await _metaAltShortcut(tester, LogicalKeyboardKey.bracketLeft);
    expect(find.byKey(const Key('terminal-pane-active-2')), findsOneWidget);

    await _metaAltShortcut(tester, LogicalKeyboardKey.keyW);
    expect(backend.closedSessionIds, contains('session-2'));
    expect(find.byKey(const Key('terminal-pane-2')), findsNothing);
  });

  testWidgets('pane divider drag changes layout and resizes sessions', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-split-right-button')),
    );
    backend.resizeCalls.clear();

    await tester.drag(
      find.byKey(const Key('terminal-pane-divider')).first,
      const Offset(120, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      backend.resizeCalls.map((call) => call['sessionId']),
      containsAll(<String>['session-1', 'session-2']),
    );
  });

  testWidgets('session restore missing file starts with one tab and pane', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final restoreStore = _sessionRestoreStore();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        sessionRestoreStore: restoreStore,
      ),
    );
    await tester.pump();

    expect(find.text('Local 1'), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-1')), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-active-1')), findsOneWidget);
    expect(find.textContaining('session-1'), findsOneWidget);
  });

  testWidgets('session restore rebuilds tab pane layout and active focus', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final restoreStore = _sessionRestoreStore();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        sessionRestoreStore: restoreStore,
        sessionRestoreDebounceDuration: Duration.zero,
      ),
    );
    await tester.pump();

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-split-right-button')),
    );
    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );
    await _previousTabShortcut(tester);
    await tester.tap(find.byKey(const Key('terminal-pane-1')));
    await tester.pump();

    final saved = restoreStore.load();
    expect(saved.activeTabIndex, 0);
    expect(saved.tabs.length, 2);
    expect(saved.tabs.first.activePaneId, 1);
    expect(saved.tabs.first.rootPane, isA<TerminalSessionRestorePaneSplit>());

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        sessionRestoreStore: restoreStore,
        sessionRestoreDebounceDuration: Duration.zero,
      ),
    );
    await tester.pump();

    expect(find.text('Local 1'), findsOneWidget);
    expect(find.text('Local 2'), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-1')), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-2')), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-active-1')), findsOneWidget);
    expect(find.textContaining('session-4'), findsWidgets);
    expect(backend.createdSessionIds, <String>[
      'session-1',
      'session-2',
      'session-3',
      'session-4',
      'session-5',
      'session-6',
    ]);
  });

  testWidgets('bad session restore file falls back to default shell', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final restoreStore = _sessionRestoreStore(initialText: '{bad json');

    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        sessionRestoreStore: restoreStore,
      ),
    );
    await tester.pump();

    expect(find.text('Local 1'), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-1')), findsOneWidget);
    expect(find.textContaining('session-1'), findsOneWidget);
  });

  testWidgets('restored active pane receives paste after rebuild', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final clipboard = _FakeClipboardClient('echo restored-pane');
    final restoreStore = _sessionRestoreStore(
      state: TerminalSessionRestoreState(
        tabs: <TerminalSessionRestoreTab>[
          TerminalSessionRestoreTab(
            fallbackTitle: 'Local 1',
            activePaneId: 2,
            rootPane: TerminalSessionRestorePaneSplit(
              direction: TerminalPaneSplitDirection.right,
              first: TerminalSessionRestorePaneLeaf(id: 1, cwd: ''),
              second: TerminalSessionRestorePaneLeaf(id: 2, cwd: ''),
            ),
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        clipboardClient: clipboard,
        sessionRestoreStore: restoreStore,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('terminal-pane-active-2')), findsOneWidget);
    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-paste-button')),
    );

    expect(_modernInputText(tester), 'echo restored-pane');
    expect(backend.writesBySession['session-2'], isNull);
  });

  testWidgets('session restore persists split divider ratio', (tester) async {
    final backend = _FakePtySessionBackend();
    final restoreStore = _sessionRestoreStore();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        sessionRestoreStore: restoreStore,
        sessionRestoreDebounceDuration: Duration.zero,
      ),
    );
    await tester.pump();

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-split-right-button')),
    );
    await tester.drag(
      find.byKey(const Key('terminal-pane-divider')).first,
      const Offset(120, 0),
    );
    await tester.pump();

    final savedSplit =
        restoreStore.load().tabs.single.rootPane
            as TerminalSessionRestorePaneSplit;
    expect(savedSplit.ratio, greaterThan(0.5));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        sessionRestoreStore: restoreStore,
        sessionRestoreDebounceDuration: Duration.zero,
      ),
    );
    await tester.pump();

    final reloadedSplit =
        restoreStore.load().tabs.single.rootPane
            as TerminalSessionRestorePaneSplit;
    expect(reloadedSplit.ratio, closeTo(savedSplit.ratio, 0.01));
  });

  testWidgets('cmd-comma opens settings and close restores terminal focus', (
    tester,
  ) async {
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => _FakePtySessionBackend(),
        settingsStore: _settingsStore(),
      ),
    );
    await tester.pump();

    await _metaShortcut(tester, LogicalKeyboardKey.comma);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('terminal-settings-panel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-close-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('terminal-settings-panel')), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'ianvs-modern-input',
    );
  });

  testWidgets('settings update font size and theme for the active terminal', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        settingsStore: _settingsStore(),
      ),
    );
    await tester.pump();

    final beforeCellHeight = _renderViewport(tester).debugCellSize.height;
    final beforeResizeCount = backend.resizeCalls.length;

    await tester.tap(find.byKey(const Key('terminal-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-font-size-increase')));
    await tester.pumpAndSettle();

    final afterCellHeight = _renderViewport(tester).debugCellSize.height;
    expect(afterCellHeight, greaterThan(beforeCellHeight));
    expect(backend.resizeCalls.length, greaterThan(beforeResizeCount));

    await tester.tap(find.byKey(const Key('settings-theme-graphite')));
    await tester.pumpAndSettle();

    expect(
      _renderViewport(tester).debugColors.canvasBackground,
      TerminalThemePreset.graphite.viewportColors.canvasBackground,
    );
  });

  testWidgets('default shell setting applies to new tabs and restart', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        settingsStore: _settingsStore(defaultShell: '/bin/zsh'),
      ),
    );
    await tester.pump();

    expect(_createdProgramAt(backend, 0), '/bin/zsh');

    await tester.tap(find.byKey(const Key('terminal-settings-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('settings-shell-field')),
      '/bin/bash',
    );
    await tester.tap(find.byKey(const Key('settings-shell-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-close-button')));
    await tester.pumpAndSettle();

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-restart-button')),
    );
    expect(_createdProgramAt(backend, 1), '/bin/bash');

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );
    expect(_createdProgramAt(backend, 2), '/bin/bash');
  });

  testWidgets('empty default shell shows error and is not saved', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        settingsStore: _settingsStore(defaultShell: '/bin/zsh'),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('terminal-settings-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('settings-shell-field')), '');
    await tester.tap(find.byKey(const Key('settings-shell-apply')));
    await tester.pumpAndSettle();

    expect(find.text('Shell path is required'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-close-button')));
    await tester.pumpAndSettle();
    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );

    expect(_createdProgramAt(backend, 1), '/bin/zsh');
  });
}

Future<void> _tapHeaderControl(WidgetTester tester, Finder finder) async {
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _previousTabShortcut(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

Future<void> _nextTabShortcut(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

Future<void> _metaShortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

Future<void> _sendCharacterKey(
  WidgetTester tester,
  LogicalKeyboardKey logicalKey,
  PhysicalKeyboardKey physicalKey,
  String character,
) async {
  await tester.sendKeyEvent(
    logicalKey,
    physicalKey: physicalKey,
    character: character,
  );
}

Future<void> _metaShiftShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

Future<void> _metaAltShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
}

String _modernInputText(WidgetTester tester) {
  return tester
      .widget<TextField>(find.byKey(const Key('terminal-modern-input-field')))
      .controller!
      .text;
}

TextEditingValue _modernInputValue(WidgetTester tester) {
  return tester
      .widget<TextField>(find.byKey(const Key('terminal-modern-input-field')))
      .controller!
      .value;
}

void _setModernInputValue(WidgetTester tester, TextEditingValue value) {
  final field = tester.widget<TextField>(
    find.byKey(const Key('terminal-modern-input-field')),
  );
  field.controller!.value = value;
}

terminal.RenderTerminalViewport _renderViewport(WidgetTester tester) {
  return tester.renderObject<terminal.RenderTerminalViewport>(
    find.byElementPredicate(
      (element) => element.renderObject is terminal.RenderTerminalViewport,
    ),
  );
}

IconButton _headerIconButton(WidgetTester tester, Key key) {
  return tester.widget<IconButton>(
    find.descendant(of: find.byKey(key), matching: find.byType(IconButton)),
  );
}

TerminalSettingsStore _settingsStore({String defaultShell = '/bin/zsh'}) {
  final dir = Directory.systemTemp.createTempSync('ianvs_terminal_widget_');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return TerminalSettingsStore(
    file: File('${dir.path}/settings.json'),
    defaultShell: defaultShell,
  );
}

SavedCommandsStore _savedCommandsStore() {
  final dir = Directory.systemTemp.createTempSync(
    'ianvs_terminal_saved_widget_',
  );
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return SavedCommandsStore(file: File('${dir.path}/saved_commands.json'));
}

TerminalSessionRestoreStore _sessionRestoreStore({
  TerminalSessionRestoreState? state,
  String? initialText,
}) {
  final dir = Directory.systemTemp.createTempSync(
    'ianvs_terminal_restore_widget_',
  );
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  final file = File('${dir.path}/session_restore.json');
  if (initialText != null) {
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(initialText);
  }
  final store = TerminalSessionRestoreStore(file: file);
  if (state != null) {
    store.save(state);
  }
  return store;
}

FigCompletionRepository _completionRepository() {
  return FigCompletionRepository.memory(
    index: const FigCompletionIndex(
      commands: <FigCompletionCommandRef>[
        FigCompletionCommandRef(name: 'demo', specPath: 'specs/demo.json'),
      ],
    ),
    specs: const <String, FigCompletionSpec>{
      'specs/demo.json': FigCompletionSpec(
        names: <String>['demo'],
        description: 'Demo command',
        options: <FigCompletionOption>[
          FigCompletionOption(names: <String>['--config']),
          FigCompletionOption(names: <String>['--verbose']),
        ],
      ),
    },
  );
}

String _createdProgramAt(_FakePtySessionBackend backend, int index) {
  final launch = backend.createdSessionConfigs[index]['launch'];
  return (launch as Map<String, Object?>)['program']! as String;
}

Map<String, Object?> _createdEnvAt(_FakePtySessionBackend backend, int index) {
  final launch = backend.createdSessionConfigs[index]['launch'];
  return ((launch as Map<String, Object?>)['env']! as Map)
      .cast<String, Object?>();
}

List<TerminalBlock> _blocksForSession(String sessionId) {
  return switch (sessionId) {
    'session-1' => const <TerminalBlock>[
      TerminalBlock(
        id: 'session-1-block-1',
        sessionId: 'session-1',
        commandText: 'pwd',
        outputText: '/tmp\n',
        status: TerminalBlockStatus.succeeded,
        scrollbackOffset: 2,
      ),
      TerminalBlock(
        id: 'session-1-block-2',
        sessionId: 'session-1',
        commandText: 'false',
        outputText: '',
        status: TerminalBlockStatus.failed,
        scrollbackOffset: 9,
      ),
    ],
    'session-2' => const <TerminalBlock>[
      TerminalBlock(
        id: 'session-2-block-1',
        sessionId: 'session-2',
        commandText: 'echo second',
        outputText: 'second\n',
        status: TerminalBlockStatus.succeeded,
        scrollbackOffset: 4,
      ),
    ],
    _ => const <TerminalBlock>[],
  };
}

List<String> _platformMenuLabels(List<PlatformMenuItem> items) {
  final labels = <String>[];
  void collect(PlatformMenuItem item) {
    if (item.label.isNotEmpty) {
      labels.add(item.label);
    }
    for (final member in item.members) {
      collect(member);
    }
    for (final child in item.descendants) {
      collect(child);
    }
  }

  for (final item in items) {
    collect(item);
  }
  return labels;
}

PlatformMenuItem _platformMenuItem(WidgetTester tester, String label) {
  final menuBar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
  PlatformMenuItem? match(PlatformMenuItem item) {
    if (item.label == label) {
      return item;
    }
    for (final member in item.members) {
      final found = match(member);
      if (found != null) {
        return found;
      }
    }
    for (final child in item.descendants) {
      final found = match(child);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  for (final item in menuBar.menus) {
    final found = match(item);
    if (found != null) {
      return found;
    }
  }
  throw StateError('Missing platform menu item: $label');
}

void _selectPlatformMenuItem(WidgetTester tester, String label) {
  final item = _platformMenuItem(tester, label);
  expect(item.onSelected, isNotNull, reason: '$label should be enabled');
  item.onSelected!();
}

class _FakeClipboardClient implements ClipboardClient {
  _FakeClipboardClient(this.text);

  String text;
  final List<String> copied = <String>[];

  @override
  Future<String> readText() async => text;

  @override
  Future<void> writeText(String text) async {
    copied.add(text);
    this.text = text;
  }
}

class _FakePtySessionBackend implements PtySessionBackend {
  _FakePtySessionBackend({
    this.failuresBeforeSuccess = 0,
    this.selectedText = '',
  });

  int failuresBeforeSuccess;
  final String selectedText;
  int _createCount = 0;
  int? exitOnNextPoll;
  final Map<String, int> exitOnNextPollBySession = <String, int>{};
  final List<String> writes = <String>[];
  final List<String> createdSessionIds = <String>[];
  final List<Map<String, Object?>> createdSessionConfigs =
      <Map<String, Object?>>[];
  final List<String> closedSessionIds = <String>[];
  final List<Map<String, Object?>> resizeCalls = <Map<String, Object?>>[];
  final List<String> searchedQueries = <String>[];
  final List<int> scrollToOffsets = <int>[];
  final Map<String, List<String>> writesBySession = <String, List<String>>{};
  final Queue<Map<String, Object?>> _queuedFrames =
      Queue<Map<String, Object?>>();
  final Map<String, Queue<PtyEvent>> _queuedEvents =
      <String, Queue<PtyEvent>>{};
  final Map<String, List<Map<String, Object?>>> searchResults =
      <String, List<Map<String, Object?>>>{};
  Map<String, Object?>? frameOnScrollTo;

  void enqueueFrame(Map<String, Object?> frame) {
    _queuedFrames.add(frame);
  }

  void enqueueEvent(String sessionId, PtyEvent event) {
    _queuedEvents.putIfAbsent(sessionId, Queue<PtyEvent>.new).add(event);
  }

  @override
  int ping() => 42;

  @override
  String createSession(String sessionConfigJson) {
    if (failuresBeforeSuccess > 0) {
      failuresBeforeSuccess -= 1;
      throw StateError('Failed to create test session');
    }
    _createCount += 1;
    final sessionId = 'session-$_createCount';
    createdSessionIds.add(sessionId);
    createdSessionConfigs.add(
      jsonDecode(sessionConfigJson) as Map<String, Object?>,
    );
    return sessionId;
  }

  @override
  void closeSession(String sessionId) {
    closedSessionIds.add(sessionId);
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    final queued = _queuedEvents[sessionId];
    if (queued != null && queued.isNotEmpty) {
      final events = queued.toList(growable: false);
      queued.clear();
      return events;
    }
    final exitCode =
        exitOnNextPollBySession.remove(sessionId) ?? exitOnNextPoll;
    if (exitCode == null) {
      return const <PtyEvent>[];
    }
    if (exitOnNextPoll == exitCode) {
      exitOnNextPoll = null;
    }
    return <PtyEvent>[
      PtyEvent(
        kind: 'exit',
        sessionId: sessionId,
        payload: <String, Object?>{'code': exitCode},
      ),
    ];
  }

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
  }) {
    resizeCalls.add(<String, Object?>{
      'sessionId': sessionId,
      'cols': cols,
      'rows': rows,
      'pixelWidth': pixelWidth,
      'pixelHeight': pixelHeight,
    });
  }

  @override
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {
    scrollToOffsets.add(offset);
    final frame = frameOnScrollTo;
    if (frame != null) {
      _queuedFrames.addFirst(frame);
      frameOnScrollTo = null;
    }
  }

  @override
  String? searchTextJson(String sessionId, String query) {
    searchedQueries.add(query);
    return jsonEncode(searchResults[query] ?? const <Map<String, Object?>>[]);
  }

  @override
  String? selectionText(String sessionId, String requestJson) => selectedText;

  @override
  String? takeFrameDiffJson(String sessionId) {
    if (_queuedFrames.isNotEmpty) {
      return jsonEncode(_queuedFrames.removeFirst());
    }
    return jsonEncode(_frameJson());
  }

  @override
  void writeInput(String sessionId, List<int> bytes) {
    final text = String.fromCharCodes(bytes);
    writes.add(text);
    writesBySession.putIfAbsent(sessionId, () => <String>[]).add(text);
  }
}

Map<String, Object?> _frameJson({
  String kind = 'snapshot',
  String text = 'ready',
  int cursorCol = 0,
  int cursorRow = 0,
  int viewportRows = 1,
  String? windowTitle,
  Map<String, Object?> modes = const <String, Object?>{},
  List<Map<String, Object?>> dirtyRanges = const <Map<String, Object?>>[
    <String, Object?>{'start': 0, 'end': 1},
  ],
}) {
  final frame = <String, Object?>{
    'frame_kind': kind,
    'rows': <Object?>[
      <String, Object?>{
        'index': 0,
        'text': text,
        'style_runs': const <Object?>[],
      },
    ],
    'cursor': <String, Object?>{
      'row': cursorRow,
      'col': cursorCol,
      'visible': true,
    },
    'viewport_rows': viewportRows,
    'viewport_cols': 80,
    'dirty_ranges': dirtyRanges,
    'scrollback_offset': 0,
    'scrollback_max_offset': 0,
    'modes': modes,
  };
  if (windowTitle != null) {
    frame['window_title'] = windowTitle;
  }
  return frame;
}

Map<String, Object?> _matchJson({
  required int row,
  required int startCol,
  required int endCol,
  required String text,
  required int offset,
}) {
  return <String, Object?>{
    'row': row,
    'start_col': startCol,
    'end_col': endCol,
    'text': text,
    'scrollback_offset': offset,
  };
}
