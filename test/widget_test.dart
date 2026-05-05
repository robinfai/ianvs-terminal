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
import 'package:ianvs_terminal/src/launch_config.dart';
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
    expect(find.text('Local shell'), findsWidgets);
    expect(find.text('Running'), findsOneWidget);
    expect(find.textContaining('session-1'), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('terminal-header'))).height, 76);
    expect(find.byKey(const Key('terminal-add-menu-button')), findsOneWidget);
    expect(
      find.byKey(const Key('terminal-header-overflow-menu-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('terminal-new-tab-button')), findsNothing);
    expect(
      find.byKey(const Key('terminal-launch-config-button')),
      findsNothing,
    );
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
    expect(
      find.byKey(const Key('terminal-header-overflow-menu-button')),
      findsOneWidget,
    );
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
    await _selectHeaderOverflowAction(tester, 'restart');

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

    await _selectHeaderOverflowAction(tester, 'paste');

    expect(_modernInputText(tester), 'echo pasted');
    expect(backend.writes, isEmpty);
  });

  testWidgets('modern paste replaces the active draft selection', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final clipboard = _FakeClipboardClient('Ianvs');

    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        clipboardClient: clipboard,
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'echo world',
    );
    _setModernInputValue(
      tester,
      const TextEditingValue(
        text: 'echo world',
        selection: TextSelection(baseOffset: 5, extentOffset: 10),
      ),
    );
    await tester.pump();

    await _selectHeaderOverflowAction(tester, 'paste');

    expect(_modernInputText(tester), 'echo Ianvs');
    expect(_modernInputValue(tester).selection.baseOffset, 10);
    expect(backend.writes, isEmpty);
  });

  testWidgets('modern input submits draft only after enter', (tester) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    expect(
      find.byKey(const Key('terminal-modern-input-editor')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-modern-input-toolbar')),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byKey(const Key('terminal-modern-input-toolbar')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Opacity && widget.opacity == 0,
        ),
      ),
      findsNothing,
    );
    expect(
      _headerIconButton(
        tester,
        const Key('terminal-save-command-button'),
      ).onPressed,
      isNull,
    );
    expect(
      find.byKey(const Key('terminal-modern-input-field')),
      findsOneWidget,
    );
    final inputField = tester.widget<TextField>(
      find.byKey(const Key('terminal-modern-input-field')),
    );
    expect(inputField.decoration?.border, InputBorder.none);
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

  testWidgets('modern input editor shortcuts update draft and search', (
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

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'kubectl get pods',
    );
    await tester.pump();
    await _altShortcut(tester, LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(_modernInputText(tester), 'kubectl get ');

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'echo clear',
    );
    await tester.pump();
    await _controlShortcut(tester, LogicalKeyboardKey.keyU);
    await tester.pump();
    expect(_modernInputText(tester), isEmpty);

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'select buffer',
    );
    await tester.pump();
    await _metaShortcut(tester, LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(_modernInputValue(tester).selection.baseOffset, 0);
    expect(_modernInputValue(tester).selection.extentOffset, 13);

    await _controlShortcut(tester, LogicalKeyboardKey.keyR);
    await tester.pump();

    expect(
      find.byKey(const Key('terminal-inline-menu-shell-command-palette')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-command-history-panel')),
      findsOneWidget,
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'ianvs-command-history',
    );
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

  testWidgets('modern input keeps focus while auto-expanding for multiline', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await tester.tap(find.byKey(const Key('terminal-modern-input-field')));
    await tester.pump();
    var field = tester.widget<TextField>(
      find.byKey(const Key('terminal-modern-input-field')),
    );
    expect(field.focusNode?.hasFocus, isTrue);
    expect(field.maxLines, 1);

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'echo one',
    );
    await tester.pump();
    field = tester.widget<TextField>(
      find.byKey(const Key('terminal-modern-input-field')),
    );
    expect(field.maxLines, 1);
    expect(field.focusNode?.hasFocus, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(_modernInputText(tester), 'echo one\n');
    field = tester.widget<TextField>(
      find.byKey(const Key('terminal-modern-input-field')),
    );
    expect(field.maxLines, 2);
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('shift-enter inserts newline at the active selection', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'echo one',
    );
    _setModernInputValue(
      tester,
      const TextEditingValue(
        text: 'echo one',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(_modernInputText(tester), 'echo \none');
    expect(_modernInputValue(tester).selection.baseOffset, 6);
    expect(backend.writes, isEmpty);
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

  testWidgets('modern input inserts shifted symbol keys consistently', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await _sendShiftCharacterKey(
      tester,
      LogicalKeyboardKey.minus,
      PhysicalKeyboardKey.minus,
      '_',
    );
    await tester.pump();
    expect(_modernInputText(tester), '_');

    await _sendShiftCharacterKey(
      tester,
      LogicalKeyboardKey.equal,
      PhysicalKeyboardKey.equal,
      '+',
    );
    await tester.pump();
    expect(_modernInputText(tester), '_+');

    await _sendShiftCharacterKey(
      tester,
      LogicalKeyboardKey.backslash,
      PhysicalKeyboardKey.backslash,
      '|',
    );
    await tester.pump();
    expect(_modernInputText(tester), '_+|');

    await _sendShiftCharacterKey(
      tester,
      LogicalKeyboardKey.slash,
      PhysicalKeyboardKey.slash,
      '?',
    );
    await tester.pump();
    expect(_modernInputText(tester), '_+|?');
  });

  testWidgets('modern input keeps shifted pair symbols auto-completed', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await _sendShiftCharacterKey(
      tester,
      LogicalKeyboardKey.bracketLeft,
      PhysicalKeyboardKey.bracketLeft,
      '{',
    );
    await tester.pump();
    expect(_modernInputText(tester), '{}');
    expect(_modernInputValue(tester).selection.baseOffset, 1);

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      '',
    );
    await tester.pump();

    await _sendShiftCharacterKey(
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
    expect(
      find.byKey(const Key('terminal-inline-menu-shell-completion')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-completion-source-badge-Spec')),
      findsWidgets,
    );
    expect(
      find.byKey(const Key('terminal-completion-active-badge---config')),
      findsOneWidget,
    );
    expect(find.text('--config'), findsOneWidget);
    expect(find.text('--verbose'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      find.byKey(const Key('terminal-completion-active-badge---verbose')),
      findsOneWidget,
    );
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

    await _selectHeaderOverflowAction(tester, 'paste');
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

  testWidgets('running block writes raw key input to terminal stdin', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        initialBlocksForSession: (String sessionId) {
          if (sessionId != 'session-1') {
            return const <TerminalBlock>[];
          }
          return const <TerminalBlock>[
            TerminalBlock(
              id: 'session-1-block-1',
              sessionId: 'session-1',
              commandText: 'sleep 1',
              outputText: '',
              status: TerminalBlockStatus.running,
              scrollbackOffset: 0,
              recordedAt: '2026-05-04T09:00:00Z',
            ),
          ];
        },
      ),
    );
    await tester.pump();

    await _metaShiftShortcut(tester, LogicalKeyboardKey.keyI);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'ianvs-terminal',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    final terminalWrites = backend.writesBySession['session-1'];
    expect(terminalWrites, isNotNull);
    expect(terminalWrites, isNotEmpty);
  });

  testWidgets(
    'completed block submit switches to running block before PTY write',
    (tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        initialBlocksForSession: (String sessionId) {
          if (sessionId != 'session-1') {
            return const <TerminalBlock>[];
          }
          return const <TerminalBlock>[
            TerminalBlock(
              id: 'session-1-block-1',
              sessionId: 'session-1',
              commandText: 'pwd',
              outputText: '/tmp\n',
              status: TerminalBlockStatus.succeeded,
              scrollbackOffset: 2,
              recordedAt: '2026-05-04T09:00:00Z',
            ),
            TerminalBlock(
              id: 'session-1-block-2',
              sessionId: 'session-1',
              commandText: 'sleep 1',
              outputText: '',
              status: TerminalBlockStatus.running,
              scrollbackOffset: 9,
              recordedAt: '2026-05-04T09:01:00Z',
            ),
          ];
        },
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('terminal-inline-block-chip-session-1-block-1')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'echo rerouted',
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(backend.writesBySession['session-1'], contains('echo rerouted\r'));
    expect(
      find.descendant(
        of: find.byKey(const Key('terminal-inline-active-block-card')),
        matching: find.textContaining('sleep 1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'completed block with no running block submits without changing selection',
    (tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        initialBlocksForSession: (String sessionId) {
          if (sessionId != 'session-1') {
            return const <TerminalBlock>[];
          }
          return const <TerminalBlock>[
            TerminalBlock(
              id: 'session-1-block-1',
              sessionId: 'session-1',
              commandText: 'pwd',
              outputText: '/tmp\n',
              status: TerminalBlockStatus.succeeded,
              scrollbackOffset: 2,
              recordedAt: '2026-05-04T09:00:00Z',
            ),
          ];
        },
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'echo local-completed',
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      backend.writesBySession['session-1'],
      contains('echo local-completed\r'),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('terminal-inline-active-block-card')),
        matching: find.textContaining('pwd'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'completed block raw entry switches to running block and routes paste to PTY',
    (tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final clipboard = _FakeClipboardClient('echo complete');
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        clipboardClient: clipboard,
        initialBlocksForSession: (String sessionId) {
          if (sessionId != 'session-1') {
            return const <TerminalBlock>[];
          }
          return const <TerminalBlock>[
            TerminalBlock(
              id: 'session-1-block-1',
              sessionId: 'session-1',
              commandText: 'pwd',
              outputText: '/tmp\n',
              status: TerminalBlockStatus.succeeded,
              scrollbackOffset: 2,
              recordedAt: '2026-05-04T09:00:00Z',
            ),
            TerminalBlock(
              id: 'session-1-block-2',
              sessionId: 'session-1',
              commandText: 'sleep 1',
              outputText: '',
              status: TerminalBlockStatus.running,
              scrollbackOffset: 9,
              recordedAt: '2026-05-04T09:01:00Z',
            ),
          ];
        },
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('terminal-inline-block-chip-session-1-block-1')),
    );
    await tester.pump();
    await _metaShiftShortcut(tester, LogicalKeyboardKey.keyI);

    expect(find.textContaining('Raw input active'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'ianvs-terminal');
    expect(
      find.descendant(
        of: find.byKey(const Key('terminal-inline-active-block-card')),
        matching: find.textContaining('sleep 1'),
      ),
      findsOneWidget,
    );

    await _selectHeaderOverflowAction(tester, 'paste');
    expect(backend.writesBySession['session-1'], contains('echo complete'));
  });

  testWidgets(
    'completed block with no running block keeps raw entry in modern input',
    (tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final clipboard = _FakeClipboardClient('echo complete');
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        clipboardClient: clipboard,
        initialBlocksForSession: (String sessionId) {
          if (sessionId != 'session-1') {
            return const <TerminalBlock>[];
          }
          return const <TerminalBlock>[
            TerminalBlock(
              id: 'session-1-block-1',
              sessionId: 'session-1',
              commandText: 'pwd',
              outputText: '/tmp\n',
              status: TerminalBlockStatus.succeeded,
              scrollbackOffset: 2,
              recordedAt: '2026-05-04T09:00:00Z',
            ),
          ];
        },
      ),
    );
    await tester.pump();

    await _metaShiftShortcut(tester, LogicalKeyboardKey.keyI);
    expect(find.textContaining('Raw input active'), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'ianvs-modern-input',
    );

    await _selectHeaderOverflowAction(tester, 'paste');
    expect(_modernInputText(tester), contains('echo complete'));
    expect(backend.writesBySession['session-1'], isNull);
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

  testWidgets('completed block keeps modern focus during auto-raw mode changes', (
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

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'pwd',
    );
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'ianvs-modern-input',
    );

    backend.enqueueFrame(
      _frameJson(modes: const <String, Object?>{'application_cursor': true}),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(
      find.byKey(const Key('terminal-modern-input-field')),
      findsOneWidget,
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'ianvs-modern-input',
    );
    expect(find.textContaining('Auto raw'), findsNothing);
  });

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

    await _selectHeaderOverflowAction(tester, 'restart');

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

    await _selectHeaderOverflowAction(tester, 'search');

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

  testWidgets('opening find closes command history and moves focus', (
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
      find.byKey(const Key('terminal-inline-menu-shell-command-palette')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-command-history-panel')),
      findsOneWidget,
    );

    await _metaShortcut(tester, LogicalKeyboardKey.keyF);
    await tester.pump();

    expect(
      find.byKey(const Key('terminal-command-history-panel')),
      findsNothing,
    );
    expect(find.byKey(const Key('terminal-find-field')), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'ianvs-find');
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
    await _selectHeaderOverflowAction(tester, 'search');
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
    await _selectHeaderOverflowAction(tester, 'search');
    await tester.enterText(
      find.byKey(const Key('terminal-find-field')),
      'ianvs',
    );
    await tester.pump();

    await _selectHeaderOverflowAction(tester, 'copy');

    expect(clipboard.copied, contains('ianvs'));
  });

  testWidgets('exited shell still supports find and copy but disables paste', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend(selectedText: 'ianvs');
    final clipboard = _FakeClipboardClient('');
    backend.searchResults['ianvs'] = <Map<String, Object?>>[
      _matchJson(row: 12, startCol: 0, endCol: 5, text: 'ianvs', offset: 4),
    ];
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

    expect(_headerOverflowMenuItem(tester, 'paste').enabled, isFalse);

    await _selectHeaderOverflowAction(tester, 'search');
    await tester.enterText(
      find.byKey(const Key('terminal-find-field')),
      'ianvs',
    );
    await tester.pump();

    expect(find.text('1/1'), findsOneWidget);
    expect(backend.searchedQueries, contains('ianvs'));

    await _selectHeaderOverflowAction(tester, 'copy');

    expect(clipboard.copied, contains('ianvs'));
  });

  testWidgets('empty find result shows zero count and does not scroll', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();
    await _selectHeaderOverflowAction(tester, 'search');
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
      tester
          .widget<terminal.TerminalViewport>(
            find.byType(terminal.TerminalViewport),
          )
          .contentPadding
          .top,
      14,
    );
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

  testWidgets('inline block rail shows the active block and dividers', (
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

    expect(find.byKey(const Key('terminal-inline-block-rail')), findsOneWidget);
    expect(
      find.byKey(const Key('terminal-input-context-strip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-input-context-chip-target')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-input-context-chip-cwd')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-input-context-chip-status')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-input-context-chip-last-command')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-input-command-detection-strip')),
      findsNothing,
    );
    expect(find.textContaining('/agent'), findsNothing);
    expect(
      tester
          .widget<terminal.TerminalViewport>(
            find.byType(terminal.TerminalViewport),
          )
          .contentPadding
          .top,
      greaterThan(144),
    );
    expect(
      tester
          .widget<terminal.TerminalViewport>(
            find.byType(terminal.TerminalViewport),
          )
          .contentPadding
          .left,
      132,
    );
    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      'git status --short',
    );
    await tester.pump();

    expect(
      find.byKey(const Key('terminal-input-command-detection-strip')),
      findsNothing,
    );
    expect(find.text('Terminal command'), findsNothing);
    expect(find.textContaining('Autodetected'), findsNothing);
    expect(
      find.byKey(const Key('terminal-input-context-strip')),
      findsOneWidget,
    );
    final inlineActions = tester
        .widget<PopupMenuButton<String>>(
          find.byKey(const Key('terminal-inline-block-actions-button')),
        )
        .itemBuilder(
          tester.element(
            find.byKey(const Key('terminal-inline-block-actions-button')),
          ),
        )
        .whereType<PopupMenuItem<String>>()
        .toList(growable: false);
    expect(
      inlineActions.map((item) => item.value),
      containsAll(<String>[
        'copy-command',
        'copy-output',
        'copy-all',
        'reinput',
        'bookmark',
      ]),
    );
    expect(
      inlineActions.singleWhere((item) => item.value == 'bookmark').enabled,
      isFalse,
    );
    expect(
      find.byKey(const Key('terminal-inline-active-block-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-sticky-block-command-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-inline-block-context-strip')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('terminal-inline-block-chip-session-1-block-1')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('terminal-inline-block-chip-session-1-block-2')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('terminal-inline-active-block-card')),
        matching: find.textContaining('false'),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('terminal-modern-input-field')),
      '',
    );
    await tester.pump();

    expect(
      find.byKey(const Key('terminal-inline-block-context-strip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-inline-block-chip-session-1-block-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-inline-block-chip-session-1-block-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-inline-block-divider-1')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('terminal-inline-active-block-card')),
        matching: find.textContaining('false'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('terminal-sticky-block-command-header')),
    );
    await tester.pump();
    expect(backend.scrollToOffsets, contains(9));

    await tester.tap(
      find.byKey(const Key('terminal-inline-block-chip-session-1-block-1')),
    );
    await tester.pump();

    expect(backend.scrollToOffsets, contains(2));
    expect(
      find.descendant(
        of: find.byKey(const Key('terminal-inline-active-block-card')),
        matching: find.textContaining('pwd'),
      ),
      findsOneWidget,
    );
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

    expect(find.byKey(const Key('terminal-block-panel')), findsNothing);
    await _openBlockHistoryPanel(tester);
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

    await _openBlockHistoryPanel(tester);
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
    await _openBlockHistoryPanel(tester);

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

    await _openBlockHistoryPanel(tester);
    expect(
      find.byKey(const Key('terminal-block-row-session-1-block-2')),
      findsOneWidget,
    );

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );

    expect(find.byKey(const Key('terminal-block-panel')), findsNothing);
    await _openBlockHistoryPanel(tester);
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

  testWidgets('inline block rail follows the active tab', (tester) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        initialBlocksForSession: _blocksForSession,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('terminal-inline-block-chip-session-1-block-2')),
      findsOneWidget,
    );

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );

    expect(
      find.byKey(const Key('terminal-inline-block-chip-session-2-block-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-inline-block-chip-session-1-block-2')),
      findsNothing,
    );

    await _previousTabShortcut(tester);

    expect(
      find.byKey(const Key('terminal-inline-block-chip-session-1-block-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-inline-block-chip-session-2-block-1')),
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

    await _openBlockHistoryPanel(tester);
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
    await _selectInlineBlockAction(tester, 'copy-command');
    await _selectInlineBlockAction(tester, 'reinput');

    expect(clipboard.copied, contains('echo second'));
    expect(_modernInputText(tester), 'echo second');
    expect(backend.writesBySession['session-2'], isNull);

    await _previousTabShortcut(tester);
    await _selectInlineBlockAction(tester, 'copy-command');
    await _selectInlineBlockAction(tester, 'reinput');

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

  testWidgets(
    'command search prioritizes active-tab history and keeps cross-tab results',
    (tester) async {
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
      await tester.tap(
        find.byKey(const Key('terminal-command-history-button')),
      );
      await tester.pump();

      expect(find.textContaining('echo second'), findsWidgets);
      expect(find.textContaining('false'), findsWidgets);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(_modernInputText(tester), 'echo second');

      await _previousTabShortcut(tester);
      await _metaShortcut(tester, LogicalKeyboardKey.keyR);

      expect(find.textContaining('false'), findsWidgets);
      expect(find.textContaining('echo second'), findsWidgets);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(_modernInputText(tester), 'false');
    },
  );

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
    await _controlShortcut(tester, LogicalKeyboardKey.keyR);

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

    expect(find.text('Workflow'), findsOneWidget);
    expect(find.textContaining('echo saved'), findsWidgets);
  });

  testWidgets('command search shows saved and history entries with sources', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final savedStore = _savedCommandsStore()
      ..save(
        const SavedCommandsState(
          entries: <SavedCommandEntry>[
            SavedCommandEntry(command: 'echo saved'),
          ],
        ),
      );
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        savedCommandsStore: savedStore,
        initialBlocksForSession: _blocksForSession,
      ),
    );
    await tester.pump();

    await _metaShortcut(tester, LogicalKeyboardKey.keyR);

    expect(find.text('Workflow'), findsOneWidget);
    expect(find.text('History'), findsWidgets);
    expect(find.textContaining('echo saved'), findsWidgets);
    expect(find.textContaining('false'), findsWidgets);
    expect(find.textContaining('Output /tmp'), findsWidgets);
    expect(find.textContaining('Completed 2026-05-04'), findsWidgets);
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
    expect(find.text('Workflow'), findsOneWidget);
    expect(find.text('History'), findsNothing);

    await tester.tap(find.byTooltip('Remove saved command'));
    await tester.pump();

    expect(savedStore.load().commands, isEmpty);
    expect(find.text('History'), findsOneWidget);
  });

  testWidgets('saved commands and history are global in command search', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final savedStore = _savedCommandsStore()
      ..save(
        const SavedCommandsState(
          entries: <SavedCommandEntry>[
            SavedCommandEntry(command: 'echo global'),
          ],
        ),
      );
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
    expect(find.textContaining('false'), findsWidgets);
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

    expect(find.text('Workflow'), findsOneWidget);
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

  testWidgets('shell hooks from another session do not create blocks', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    backend.enqueueEvent(
      'session-1',
      const PtyEvent(
        kind: 'shell_hook',
        sessionId: 'session-2',
        payload: <String, Object?>{'hook': 'preexec', 'command': 'echo wrong'},
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text('Block 1/1'), findsNothing);
    expect(find.textContaining('echo wrong'), findsNothing);
  });

  testWidgets('duplicate command blocks keep distinct output ranges', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend(
      selectionTextResolver: (_, request) {
        return switch (request['start_row']) {
          1 => 'first-output\n',
          3 => 'second-output\n',
          _ => '',
        };
      },
    );
    final clipboard = _FakeClipboardClient('');
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        clipboardClient: clipboard,
      ),
    );
    await tester.pump();

    backend.enqueueFrame(_frameJson(text: 'echo same', cursorRow: 0));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    backend.enqueueEvent(
      'session-1',
      const PtyEvent(
        kind: 'shell_hook',
        sessionId: 'session-1',
        payload: <String, Object?>{'hook': 'preexec', 'command': 'echo same'},
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

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

    backend.enqueueFrame(_frameJson(text: 'echo same', cursorRow: 2));
    await tester.pump(const Duration(milliseconds: 34));
    final viewport = tester.widget<terminal.TerminalViewport>(
      find.byType(terminal.TerminalViewport).first,
    );
    expect(viewport.controller.frame.cursor.row, 2);

    backend.enqueueEvent(
      'session-1',
      const PtyEvent(
        kind: 'shell_hook',
        sessionId: 'session-1',
        payload: <String, Object?>{'hook': 'preexec', 'command': 'echo same'},
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

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

    expect(find.text('Block 2/2'), findsOneWidget);

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-copy-output-button')),
    );
    expect(clipboard.copied.last, 'second-output\n');

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-previous-button')),
    );
    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-block-copy-output-button')),
    );
    expect(clipboard.copied.last, 'first-output\n');
    expect(
      backend.selectionRequests.map((request) => request['start_row']),
      containsAll(<Object?>[1, 3]),
    );
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

  testWidgets('shell exit maps a running block status from exit code', (
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
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    backend.exitOnNextPollBySession['session-1'] = 1;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Unknown'), findsNothing);
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
        'Workspace Search',
        'Launch Config',
        'Saved Launch Configs',
        'New SSH Session',
        'Session Context',
        'New Window',
        'Close Window',
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

  testWidgets('launch config panel saves and reapplies workspace files', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final dir = Directory.systemTemp.createTempSync('ianvs_launch_widget_');
    final file = File('${dir.path}/ianvs-terminal.launch.json');
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await _selectHeaderOverflowAction(tester, 'split-right');

    await _selectAddMenuAction(tester, 'launch-config');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('terminal-launch-config-scope-explainer')),
      findsOneWidget,
    );
    expect(find.text('App config'), findsOneWidget);
    expect(find.text('Tab config'), findsOneWidget);
    expect(
      find.byKey(const Key('terminal-launch-config-name-field')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('terminal-launch-config-name-field')),
      '',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('terminal-launch-config-save-button')),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('terminal-launch-config-name-field')),
      'workspace-layout',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('terminal-launch-config-save-button')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.ensureVisible(
      find.byKey(const Key('terminal-launch-config-advanced-toggle')),
    );
    await tester.tap(
      find.byKey(const Key('terminal-launch-config-advanced-toggle')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('terminal-launch-config-path-field')),
      file.path,
    );
    await tester.enterText(
      find.byKey(const Key('terminal-launch-config-startup-field-pane-1')),
      'pnpm dev',
    );
    await tester.enterText(
      find.byKey(const Key('terminal-launch-config-startup-field-pane-2')),
      'flutter test',
    );
    await tester.ensureVisible(
      find.byKey(const Key('terminal-launch-config-save-button')),
    );
    await tester.tap(
      find.byKey(const Key('terminal-launch-config-save-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('terminal-launch-config-success-state')),
      findsOneWidget,
    );
    expect(find.textContaining(file.path), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('terminal-launch-config-done-button')),
    );
    await tester.tap(
      find.byKey(const Key('terminal-launch-config-done-button')),
    );
    await tester.pumpAndSettle();

    final savedJson =
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final savedTabs = savedJson['tabs'] as List<Object?>;
    final rootPane =
        (savedTabs.single as Map<String, Object?>)['rootPane']
            as Map<String, Object?>;
    expect(rootPane['type'], 'split');
    final savedFirst = rootPane['first'] as Map<String, Object?>;
    final savedSecond = rootPane['second'] as Map<String, Object?>;
    expect(savedFirst['startupCommand'], 'pnpm dev');
    expect(savedSecond['startupCommand'], 'flutter test');

    await _selectHeaderOverflowAction(tester, 'close-pane');
    expect(find.byKey(const Key('terminal-pane-2')), findsNothing);

    await _selectAddMenuAction(tester, 'launch-config');
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('terminal-launch-config-apply-button')),
    );
    await tester.tap(
      find.byKey(const Key('terminal-launch-config-apply-button')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('terminal-pane-1')), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-2')), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-active-2')), findsOneWidget);
    expect(backend.writesBySession['session-3'], contains('pnpm dev\r'));
    expect(backend.writesBySession['session-4'], contains('flutter test\r'));
  });

  testWidgets(
    'launch config export captures app windows and restores the active window',
    (tester) async {
      final backend = _FakePtySessionBackend();
      final dir = Directory.systemTemp.createTempSync(
        'ianvs_launch_windows_widget_',
      );
      final file = File('${dir.path}/ianvs-terminal.launch.json');
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });
      await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
      await tester.pump();

      await _selectAddMenuAction(tester, 'new-window');
      expect(find.text('Window 2'), findsOneWidget);

      await _selectAddMenuAction(tester, 'new-ssh');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('terminal-new-ssh-host-field')),
        'prod.example.internal',
      );
      await tester.enterText(
        find.byKey(const Key('terminal-new-ssh-project-field')),
        'window-two-ssh',
      );
      await tester.tap(find.byKey(const Key('terminal-new-ssh-open-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('terminal-tab-window-two-ssh')),
        findsOneWidget,
      );

      await _selectAddMenuAction(tester, 'launch-config');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('terminal-launch-config-name-field')),
        'window-export',
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('terminal-launch-config-advanced-toggle')),
      );
      await tester.tap(
        find.byKey(const Key('terminal-launch-config-advanced-toggle')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('terminal-launch-config-path-field')),
        file.path,
      );
      await tester.ensureVisible(
        find.byKey(const Key('terminal-launch-config-save-button')),
      );
      await tester.tap(
        find.byKey(const Key('terminal-launch-config-save-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('terminal-launch-config-success-state')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('terminal-launch-config-done-button')),
      );
      await tester.tap(
        find.byKey(const Key('terminal-launch-config-done-button')),
      );
      await tester.pumpAndSettle();

      final savedJson =
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final savedWindows = savedJson['windows'] as List<Object?>;
      expect(savedJson['activeWindowIndex'], 1);
      expect(savedWindows, hasLength(2));

      await _selectHeaderOverflowAction(tester, 'close-window');
      expect(find.text('Window 2'), findsNothing);
      expect(
        find.byKey(const Key('terminal-tab-window-two-ssh')),
        findsNothing,
      );

      await _selectAddMenuAction(tester, 'launch-config');
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('terminal-launch-config-apply-button')),
      );
      await tester.tap(
        find.byKey(const Key('terminal-launch-config-apply-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Window 1'), findsOneWidget);
      expect(find.text('Window 2'), findsOneWidget);
      expect(
        find.byKey(const Key('terminal-tab-window-two-ssh')),
        findsOneWidget,
      );
    },
  );

  testWidgets('saved launch config panel applies and removes saved configs', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final dir = Directory.systemTemp.createTempSync(
      'ianvs_saved_launch_widget_',
    );
    final store = TerminalLaunchConfigurationStore(directory: dir);
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
    await tester.pumpWidget(
      IanvsTerminalApp(backendFactory: () => backend, launchConfigStore: store),
    );
    await tester.pump();

    await _selectHeaderOverflowAction(tester, 'split-right');
    await _selectAddMenuAction(tester, 'launch-config');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('terminal-launch-config-name-field')),
      'saved-layout',
    );
    await tester.ensureVisible(
      find.byKey(const Key('terminal-launch-config-save-button')),
    );
    await tester.tap(
      find.byKey(const Key('terminal-launch-config-save-button')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('terminal-launch-config-done-button')),
    );
    await tester.tap(
      find.byKey(const Key('terminal-launch-config-done-button')),
    );
    await tester.pumpAndSettle();

    expect(store.listSaved(), hasLength(1));
    await _selectHeaderOverflowAction(tester, 'close-pane');
    expect(find.byKey(const Key('terminal-pane-2')), findsNothing);

    await _selectAddMenuAction(tester, 'saved-configs');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('terminal-saved-launch-configs-panel')),
      findsOneWidget,
    );
    expect(find.text('saved-layout'), findsWidgets);
    expect(
      find.byKey(const Key('terminal-saved-launch-config-sidecar')),
      findsOneWidget,
    );
    expect(find.text('App config'), findsWidgets);
    expect(
      find.byKey(const Key('terminal-saved-launch-config-scope-copy')),
      findsOneWidget,
    );

    final makeDefaultButton = find.byKey(
      const Key('terminal-saved-launch-config-default-button'),
    );
    await tester.ensureVisible(makeDefaultButton);
    await tester.tap(makeDefaultButton);
    await tester.pump();
    expect(find.text('Default'), findsWidgets);

    final applyButton = find.byKey(
      const Key('terminal-saved-launch-config-apply-button'),
    );
    await tester.ensureVisible(applyButton);
    await tester.tap(applyButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('terminal-pane-1')), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-2')), findsOneWidget);

    await _selectAddMenuAction(tester, 'saved-configs');
    await tester.pumpAndSettle();
    final removeButton = find.byKey(
      const Key('terminal-saved-launch-config-remove-button'),
    );
    await tester.ensureVisible(removeButton);
    await tester.tap(removeButton);
    await tester.pumpAndSettle();
    expect(find.text('No saved configs'), findsOneWidget);
    expect(store.listSaved(), isEmpty);
  });

  testWidgets('command palette applies saved launch config source', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final dir = Directory.systemTemp.createTempSync(
      'ianvs_palette_launch_widget_',
    );
    final store = TerminalLaunchConfigurationStore(directory: dir);
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
    store.save(
      File('${dir.path}/palette-layout.json'),
      TerminalLaunchConfiguration(
        windows: <TerminalLaunchConfigurationWindow>[
          TerminalLaunchConfigurationWindow(
            fallbackTitle: 'Palette Window',
            tabs: <TerminalLaunchConfigurationTab>[
              TerminalLaunchConfigurationTab(
                fallbackTitle: 'Palette Tab',
                activePaneId: 2,
                rootPane: TerminalLaunchConfigurationPaneSplit(
                  direction: TerminalPaneSplitDirection.right,
                  first: const TerminalLaunchConfigurationPaneLeaf(
                    id: 1,
                    cwd: '/tmp/left',
                  ),
                  second: const TerminalLaunchConfigurationPaneLeaf(
                    id: 2,
                    cwd: '/tmp/right',
                    startupCommand: 'echo restored',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      IanvsTerminalApp(backendFactory: () => backend, launchConfigStore: store),
    );
    await tester.pump();

    expect(find.byKey(const Key('terminal-pane-2')), findsNothing);

    await tester.tap(find.byKey(const Key('terminal-command-history-button')));
    await tester.pump();
    expect(
      find.byKey(const Key('terminal-command-palette-source-rail')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('terminal-command-palette-source-filter-Launch')),
    );
    await tester.pump();

    expect(find.text('palette-layout'), findsOneWidget);
    expect(
      find.byKey(const Key('terminal-command-palette-filter-Launch')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('terminal-command-history-field')),
      'launch:palette',
    );
    await tester.pump();

    expect(find.text('palette-layout'), findsOneWidget);
    expect(
      find.byKey(const Key('terminal-command-palette-filter-Launch')),
      findsOneWidget,
    );
    expect(find.textContaining('App config'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('terminal-pane-1')), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-2')), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-active-2')), findsOneWidget);
  });

  testWidgets('tab and window context actions save scoped launch configs', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final dir = Directory.systemTemp.createTempSync(
      'ianvs_context_launch_widget_',
    );
    final store = TerminalLaunchConfigurationStore(directory: dir);
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
    await tester.pumpWidget(
      IanvsTerminalApp(backendFactory: () => backend, launchConfigStore: store),
    );
    await tester.pump();

    await _selectHeaderOverflowAction(tester, 'split-right');
    await _selectAddMenuAction(tester, 'save-tab-config');
    await tester.pumpAndSettle();

    var saved = store.listSaved();
    expect(saved, hasLength(1));
    expect(
      saved.single.configuration.scope,
      TerminalLaunchConfigurationScope.tab,
    );
    expect(saved.single.windowCount, 1);
    expect(saved.single.tabCount, 1);
    expect(saved.single.paneCount, 2);

    await _selectAddMenuAction(tester, 'new-window');
    await _selectAddMenuAction(tester, 'save-app-config');
    await tester.pumpAndSettle();

    saved = store.listSaved();
    expect(saved, hasLength(2));
    final appConfig = saved
        .map((entry) => entry.configuration)
        .singleWhere(
          (configuration) =>
              configuration.scope == TerminalLaunchConfigurationScope.app,
        );
    expect(appConfig.windows, hasLength(2));
    expect(appConfig.activeWindowIndex, 1);
  });

  testWidgets('add menu exposes creation and launch config actions', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final dir = Directory.systemTemp.createTempSync('ianvs_add_menu_widget_');
    final store = TerminalLaunchConfigurationStore(directory: dir);
    addTearDown(() {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });
    await tester.pumpWidget(
      IanvsTerminalApp(backendFactory: () => backend, launchConfigStore: store),
    );
    await tester.pump();

    final addMenu = find.byKey(const Key('terminal-add-menu-button'));
    final popup = tester.widget<PopupMenuButton<String>>(addMenu);
    final values = popup
        .itemBuilder(tester.element(addMenu))
        .whereType<PopupMenuItem<String>>()
        .map((item) => item.value)
        .toList(growable: false);
    expect(
      values,
      containsAll(<String>[
        'new-tab',
        'new-window',
        'new-ssh',
        'saved-configs',
        'save-tab-config',
        'save-app-config',
        'launch-config',
      ]),
    );
    final overflowMenu = find.byKey(
      const Key('terminal-header-overflow-menu-button'),
    );
    final overflowValues = tester
        .widget<PopupMenuButton<String>>(overflowMenu)
        .itemBuilder(tester.element(overflowMenu))
        .whereType<PopupMenuItem<String>>()
        .map((item) => item.value)
        .toList(growable: false);
    expect(
      overflowValues,
      containsAll(<String>[
        'search',
        'workspace-search',
        'settings',
        'close-window',
        'split-right',
        'split-down',
        'close-pane',
        'session-context',
        'copy',
        'paste',
        'restart',
      ]),
    );

    popup.onSelected!('new-tab');
    await tester.pump();
    expect(find.byKey(const Key('terminal-tab-Local 2')), findsOneWidget);

    popup.onSelected!('save-tab-config');
    await tester.pumpAndSettle();
    var saved = store.listSaved();
    expect(
      saved.single.configuration.scope,
      TerminalLaunchConfigurationScope.tab,
    );

    popup.onSelected!('save-app-config');
    await tester.pumpAndSettle();
    saved = store.listSaved();
    expect(
      saved.map((entry) => entry.configuration.scope),
      contains(TerminalLaunchConfigurationScope.app),
    );

    popup.onSelected!('saved-configs');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('terminal-saved-launch-configs-panel')),
      findsOneWidget,
    );
    expect(find.textContaining('Tab config'), findsWidgets);
    expect(find.textContaining('App config'), findsWidgets);
  });

  testWidgets(
    'new ssh session launches a local ssh command and restart keeps target',
    (tester) async {
      final backend = _FakePtySessionBackend();
      await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
      await tester.pump();

      await _selectAddMenuAction(tester, 'new-ssh');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('terminal-new-ssh-session-panel')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('terminal-new-ssh-host-field')),
        'prod.example.internal',
      );
      await tester.enterText(
        find.byKey(const Key('terminal-new-ssh-account-field')),
        'ops-user',
      );
      await tester.enterText(
        find.byKey(const Key('terminal-new-ssh-environment-field')),
        'prod-use1',
      );
      await tester.enterText(
        find.byKey(const Key('terminal-new-ssh-project-field')),
        'payments-api',
      );
      await tester.tap(find.byKey(const Key('terminal-new-ssh-open-button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('terminal-tab-payments-api')),
        findsOneWidget,
      );
      expect(find.text('SSH command'), findsOneWidget);
      final launch =
          backend.createdSessionConfigs.last['launch'] as Map<String, Object?>;
      expect(launch['program'] as String, endsWith('ssh'));
      expect((launch['args'] as List<Object?>).cast<String>(), <String>[
        'ops-user@prod.example.internal',
      ]);

      await _selectHeaderOverflowAction(tester, 'session-context');
      await tester.pumpAndSettle();
      expect(
        find.text('Current transport: SSH command via local PTY.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('terminal-session-host-field')),
        'staging.example.internal',
      );
      await tester.tap(
        find.byKey(const Key('terminal-session-context-apply-button')),
      );
      await tester.pumpAndSettle();

      await _selectHeaderOverflowAction(tester, 'restart');
      final restartedLaunch =
          backend.createdSessionConfigs.last['launch'] as Map<String, Object?>;
      expect(restartedLaunch['program'] as String, endsWith('ssh'));
      expect(
        (restartedLaunch['args'] as List<Object?>).cast<String>(),
        <String>['ops-user@staging.example.internal'],
      );
    },
  );

  testWidgets('new ssh session rejects option-like host input', (tester) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await _selectAddMenuAction(tester, 'new-ssh');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('terminal-new-ssh-host-field')),
      '-oProxyCommand=bad',
    );
    await tester.tap(find.byKey(const Key('terminal-new-ssh-open-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Host must be a hostname or address, not ssh options.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-new-ssh-session-panel')),
      findsOneWidget,
    );
    expect(backend.createdSessionConfigs.length, 1);
  });

  testWidgets(
    'session context panel updates active pane labels and safety context',
    (tester) async {
      await tester.pumpWidget(
        IanvsTerminalApp(backendFactory: () => _FakePtySessionBackend()),
      );
      await tester.pump();

      await _selectHeaderOverflowAction(tester, 'session-context');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('terminal-session-context-panel')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('terminal-session-kind-ssh')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('terminal-session-host-field')),
        'prod.example.internal',
      );
      await tester.enterText(
        find.byKey(const Key('terminal-session-account-field')),
        'ops-user',
      );
      await tester.enterText(
        find.byKey(const Key('terminal-session-environment-field')),
        'prod-use1',
      );
      await tester.enterText(
        find.byKey(const Key('terminal-session-project-field')),
        'payments-api',
      );
      await tester.ensureVisible(
        find.byKey(const Key('terminal-session-identity-field')),
      );
      await tester.enterText(
        find.byKey(const Key('terminal-session-identity-field')),
        'robin.oncall',
      );
      await tester.enterText(
        find.byKey(const Key('terminal-session-auth-source-field')),
        'Ianvs Access',
      );
      await tester.enterText(
        find.byKey(const Key('terminal-session-valid-until-field')),
        '2026-05-03T18:00:00Z',
      );
      await tester.ensureVisible(
        find.byKey(const Key('terminal-session-context-apply-button')),
      );
      await tester.tap(
        find.byKey(const Key('terminal-session-context-apply-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('SSH session'), findsWidgets);
      expect(find.text('Metadata only'), findsOneWidget);
      expect(find.text('Host prod.example.internal'), findsOneWidget);
      expect(find.text('Account ops-user'), findsOneWidget);
      expect(find.text('Env prod-use1'), findsOneWidget);
      expect(find.text('Project payments-api'), findsOneWidget);
      expect(find.text('Identity robin.oncall'), findsOneWidget);
      expect(find.text('Source Ianvs Access'), findsOneWidget);
      expect(find.text('Valid until 2026-05-03T18:00:00Z'), findsOneWidget);
      expect(
        find.byKey(const Key('terminal-tab-payments-api')),
        findsOneWidget,
      );

      _selectPlatformMenuItem(tester, 'Session Context');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('terminal-session-context-panel')),
        findsOneWidget,
      );
      final hostField = tester.widget<TextField>(
        find.byKey(const Key('terminal-session-host-field')),
      );
      expect(hostField.controller?.text, 'prod.example.internal');
      await tester.tap(
        find.byKey(const Key('terminal-session-context-close-button')),
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets('session context rejects option-like ssh metadata host', (
    tester,
  ) async {
    await tester.pumpWidget(
      IanvsTerminalApp(backendFactory: () => _FakePtySessionBackend()),
    );
    await tester.pump();

    await _selectHeaderOverflowAction(tester, 'session-context');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('terminal-session-kind-ssh')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('terminal-session-host-field')),
      '-V',
    );
    await tester.tap(
      find.byKey(const Key('terminal-session-context-apply-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Host must be a hostname or address, not ssh options.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-session-context-panel')),
      findsOneWidget,
    );
  });

  testWidgets('workspace search opens from header menu and shortcut', (
    tester,
  ) async {
    await tester.pumpWidget(
      IanvsTerminalApp(backendFactory: () => _FakePtySessionBackend()),
    );
    await tester.pump();

    await _selectHeaderOverflowAction(tester, 'workspace-search');
    await tester.pump();
    expect(
      find.byKey(const Key('terminal-workspace-search-panel')),
      findsOneWidget,
    );
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'ianvs-workspace-search',
    );

    await tester.tap(find.byTooltip('Close workspace search'));
    await tester.pump();
    expect(
      find.byKey(const Key('terminal-workspace-search-panel')),
      findsNothing,
    );

    _selectPlatformMenuItem(tester, 'Workspace Search');
    await tester.pump();
    expect(
      find.byKey(const Key('terminal-workspace-search-panel')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Close workspace search'));
    await tester.pump();
    await _metaShiftShortcut(tester, LogicalKeyboardKey.keyO);
    expect(
      find.byKey(const Key('terminal-workspace-search-panel')),
      findsOneWidget,
    );
  });

  testWidgets(
    'workspace search keyboard jump selects target and restores focus',
    (tester) async {
      final backend = _FakePtySessionBackend();
      final alpha = Directory.systemTemp.createTempSync('ianvs_ws_alpha_');
      final alphaRight = Directory.systemTemp.createTempSync(
        'ianvs_ws_alpha_right_',
      );
      final beta = Directory.systemTemp.createTempSync('ianvs_ws_beta_');
      addTearDown(() {
        alpha.deleteSync(recursive: true);
        alphaRight.deleteSync(recursive: true);
        beta.deleteSync(recursive: true);
      });
      await tester.pumpWidget(
        IanvsTerminalApp(
          backendFactory: () => backend,
          sessionRestoreStore: _sessionRestoreStore(
            state: TerminalSessionRestoreState(
              activeWindowIndex: 0,
              windows: <TerminalSessionRestoreWindow>[
                TerminalSessionRestoreWindow(
                  fallbackTitle: 'Window 1',
                  activeTabIndex: 0,
                  tabs: <TerminalSessionRestoreTab>[
                    TerminalSessionRestoreTab(
                      fallbackTitle: 'Workspace Alpha',
                      activePaneId: 1,
                      rootPane: TerminalSessionRestorePaneSplit(
                        direction: TerminalPaneSplitDirection.right,
                        first: TerminalSessionRestorePaneLeaf(
                          id: 1,
                          cwd: alpha.path,
                        ),
                        second: TerminalSessionRestorePaneLeaf(
                          id: 2,
                          cwd: alphaRight.path,
                        ),
                      ),
                    ),
                    TerminalSessionRestoreTab(
                      fallbackTitle: 'Workspace Beta',
                      activePaneId: 3,
                      rootPane: TerminalSessionRestorePaneLeaf(
                        id: 3,
                        cwd: beta.path,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      await _metaShiftShortcut(tester, LogicalKeyboardKey.keyO);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'ianvs-workspace-search',
      );
      expect(find.text('1/3'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(find.text('3/3'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(
        find.byKey(const Key('terminal-workspace-search-panel')),
        findsNothing,
      );
      expect(find.byKey(const Key('terminal-pane-active-3')), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'ianvs-modern-input',
      );

      await _tapHeaderControl(
        tester,
        find.byKey(const Key('terminal-restart-button')),
      );
      expect(backend.closedSessionIds, contains('session-3'));
    },
  );

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
    expect(closeOnlyTab.onPressed, isNull);
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
    expect(find.byKey(const Key('terminal-pane-header-1')), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-header-2')), findsOneWidget);
    expect(
      find.byKey(const Key('terminal-pane-context-chips-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-pane-context-chip-1-target')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-pane-context-chip-1-cwd')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-pane-context-chip-2-status')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('terminal-pane-menu-1')), findsOneWidget);
    final paneMenu = tester.widget<PopupMenuButton<String>>(
      find.byKey(const Key('terminal-pane-menu-1')),
    );
    final paneMenuValues = paneMenu
        .itemBuilder(
          tester.element(find.byKey(const Key('terminal-pane-menu-1'))),
        )
        .whereType<PopupMenuItem<String>>()
        .map((item) => item.value)
        .toList(growable: false);
    expect(
      paneMenuValues,
      containsAll(<String>[
        'focus',
        'split-right',
        'split-down',
        'move-to-new-tab',
        'session-context',
        'copy',
        'paste',
        'restart',
        'close',
      ]),
    );
    expect(
      find.byKey(const Key('terminal-pane-drag-handle-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-pane-drag-handle-2')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('terminal-pane-active-2')), findsOneWidget);
    expect(
      find.byKey(const Key('terminal-pane-active-marker-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-inactive-input-context-strip-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('terminal-inactive-modern-input-bar-1')),
      findsOneWidget,
    );
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
    expect(
      find.byKey(const Key('terminal-inactive-modern-input-bar-2')),
      findsOneWidget,
    );
    expect(_modernInputText(tester), isEmpty);

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-paste-button')),
    );
    expect(_modernInputText(tester), 'echo pane-one');
    expect(backend.writesBySession['session-1'], isNull);
    expect(backend.writesBySession['session-2'], isNull);
  });

  testWidgets('pane local header actions split and close selected panes', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await _selectHeaderOverflowAction(tester, 'split-right');
    await tester.tap(find.byKey(const Key('terminal-pane-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('terminal-pane-menu-split-down-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('terminal-pane-3')), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-active-3')), findsOneWidget);
    expect(
      find.byKey(const Key('terminal-pane-active-marker-3')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('terminal-pane-menu-3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('terminal-pane-menu-close-3')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('terminal-pane-3')), findsNothing);
    expect(find.byKey(const Key('terminal-pane-1')), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-2')), findsOneWidget);
  });

  testWidgets('pane menu can move a split pane into a new tab', (tester) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    await _selectHeaderOverflowAction(tester, 'split-right');
    await tester.tap(find.byKey(const Key('terminal-pane-menu-2')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('terminal-pane-menu-move-to-new-tab-2')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('terminal-tab-Local 1')), findsOneWidget);
    expect(find.byKey(const Key('terminal-tab-Local 2')), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-1')), findsNothing);
    expect(find.byKey(const Key('terminal-pane-2')), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-active-2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('terminal-tab-Local 1')));
    await tester.pump();

    expect(find.byKey(const Key('terminal-pane-1')), findsOneWidget);
    expect(find.byKey(const Key('terminal-pane-2')), findsNothing);
    expect(backend.createdSessionConfigs, hasLength(2));
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

  testWidgets('closing pane and tab prunes retired terminal focus nodes', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    await tester.pumpWidget(IanvsTerminalApp(backendFactory: () => backend));
    await tester.pump();

    expect(
      debugTerminalFocusNodeCount(
        tester.element(find.byType(IanvsTerminalShell)),
      ),
      1,
    );

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-split-right-button')),
    );
    expect(
      debugTerminalFocusNodeCount(
        tester.element(find.byType(IanvsTerminalShell)),
      ),
      2,
    );

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-close-pane-button')),
    );
    expect(
      debugTerminalFocusNodeCount(
        tester.element(find.byType(IanvsTerminalShell)),
      ),
      1,
    );

    await _tapHeaderControl(
      tester,
      find.byKey(const Key('terminal-new-tab-button')),
    );
    expect(
      debugTerminalFocusNodeCount(
        tester.element(find.byType(IanvsTerminalShell)),
      ),
      2,
    );

    final closeSecondTab = tester.widget<IconButton>(
      find.byKey(const Key('terminal-close-tab-Local 2')),
    );
    closeSecondTab.onPressed!();
    await tester.pump();

    expect(
      debugTerminalFocusNodeCount(
        tester.element(find.byType(IanvsTerminalShell)),
      ),
      1,
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

  testWidgets('session restore keeps inline block grouping visible', (
    tester,
  ) async {
    final backend = _FakePtySessionBackend();
    final restoreStore = _sessionRestoreStore();
    await tester.pumpWidget(
      IanvsTerminalApp(
        backendFactory: () => backend,
        initialBlocksForSession: _blocksForSession,
        sessionRestoreStore: restoreStore,
        sessionRestoreDebounceDuration: Duration.zero,
      ),
    );
    await tester.pump();

    final savedLeaf =
        restoreStore.load().tabs.single.rootPane
            as TerminalSessionRestorePaneLeaf;
    expect(savedLeaf.blocks, hasLength(2));

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

    expect(find.byKey(const Key('terminal-inline-block-rail')), findsOneWidget);
    expect(
      find.byKey(const Key('terminal-inline-block-chip-session-1-block-1')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('terminal-inline-active-block-card')),
        matching: find.textContaining('false'),
      ),
      findsOneWidget,
    );
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
        windows: <TerminalSessionRestoreWindow>[
          TerminalSessionRestoreWindow(
            fallbackTitle: 'Window 1',
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
    expect(
      find.byKey(const Key('settings-session-defaults-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('settings-startup-shell-field')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('settings-cwd-policy-split')), findsOneWidget);
    expect(find.byKey(const Key('settings-cwd-policy-tab')), findsOneWidget);
    expect(find.byKey(const Key('settings-cwd-policy-window')), findsOneWidget);

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

    await _selectHeaderOverflowAction(tester, 'settings');
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

    await _selectHeaderOverflowAction(tester, 'settings');
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

    await _selectHeaderOverflowAction(tester, 'settings');
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
  if (!tester.any(finder)) {
    final addAction = _addMenuActionForFinder(finder);
    if (addAction != null) {
      await _selectAddMenuAction(tester, addAction);
      return;
    }
    final overflowAction = _headerOverflowActionForFinder(finder);
    if (overflowAction != null) {
      await _selectHeaderOverflowAction(tester, overflowAction);
      return;
    }
  }
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _openBlockHistoryPanel(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('terminal-block-overview-button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _selectAddMenuAction(WidgetTester tester, String action) async {
  final addMenu = find.byKey(const Key('terminal-add-menu-button'));
  tester.widget<PopupMenuButton<String>>(addMenu).onSelected!(action);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _selectHeaderOverflowAction(
  WidgetTester tester,
  String action,
) async {
  final overflowMenu = find.byKey(
    const Key('terminal-header-overflow-menu-button'),
  );
  tester.widget<PopupMenuButton<String>>(overflowMenu).onSelected!(action);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

PopupMenuItem<String> _headerOverflowMenuItem(
  WidgetTester tester,
  String action,
) {
  final overflowMenu = find.byKey(
    const Key('terminal-header-overflow-menu-button'),
  );
  final popup = tester.widget<PopupMenuButton<String>>(overflowMenu);
  return popup
      .itemBuilder(tester.element(overflowMenu))
      .whereType<PopupMenuItem<String>>()
      .singleWhere((item) => item.value == action);
}

Future<void> _selectInlineBlockAction(
  WidgetTester tester,
  String action,
) async {
  final actionsMenu = find.byKey(
    const Key('terminal-inline-block-actions-button'),
  );
  tester.widget<PopupMenuButton<String>>(actionsMenu).onSelected!(action);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

String? _addMenuActionForFinder(Finder finder) {
  final description = finder.toString();
  if (description.contains('terminal-new-tab-button')) {
    return 'new-tab';
  }
  if (description.contains('terminal-new-window-button')) {
    return 'new-window';
  }
  if (description.contains('terminal-new-ssh-session-button')) {
    return 'new-ssh';
  }
  if (description.contains('terminal-saved-launch-configs-button')) {
    return 'saved-configs';
  }
  if (description.contains('terminal-launch-config-button')) {
    return 'launch-config';
  }
  return null;
}

String? _headerOverflowActionForFinder(Finder finder) {
  final description = finder.toString();
  if (description.contains('terminal-search-button')) {
    return 'search';
  }
  if (description.contains('terminal-workspace-search-button')) {
    return 'workspace-search';
  }
  if (description.contains('terminal-settings-button')) {
    return 'settings';
  }
  if (description.contains('terminal-close-window-button')) {
    return 'close-window';
  }
  if (description.contains('terminal-split-right-button')) {
    return 'split-right';
  }
  if (description.contains('terminal-split-down-button')) {
    return 'split-down';
  }
  if (description.contains('terminal-close-pane-button')) {
    return 'close-pane';
  }
  if (description.contains('terminal-session-context-button')) {
    return 'session-context';
  }
  if (description.contains('terminal-copy-button')) {
    return 'copy';
  }
  if (description.contains('terminal-paste-button')) {
    return 'paste';
  }
  if (description.contains('terminal-restart-button')) {
    return 'restart';
  }
  return null;
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

Future<void> _controlShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Future<void> _altShortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
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

Future<void> _sendShiftCharacterKey(
  WidgetTester tester,
  LogicalKeyboardKey logicalKey,
  PhysicalKeyboardKey physicalKey,
  String character,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(
    logicalKey,
    physicalKey: physicalKey,
    character: character,
  );
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
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
        recordedAt: '2026-05-04T09:00:00Z',
      ),
      TerminalBlock(
        id: 'session-1-block-2',
        sessionId: 'session-1',
        commandText: 'false',
        outputText: '',
        status: TerminalBlockStatus.failed,
        scrollbackOffset: 9,
        recordedAt: '2026-05-04T09:01:00Z',
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
        recordedAt: '2026-05-04T09:02:00Z',
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
    this.selectionTextResolver,
  });

  int failuresBeforeSuccess;
  final String selectedText;
  final String? Function(String sessionId, Map<String, Object?> request)?
  selectionTextResolver;
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
  final List<Map<String, Object?>> selectionRequests = <Map<String, Object?>>[];
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
  String? selectionText(String sessionId, String requestJson) {
    final request = (jsonDecode(requestJson) as Map).cast<String, Object?>();
    selectionRequests.add(request);
    return selectionTextResolver?.call(sessionId, request) ?? selectedText;
  }

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
