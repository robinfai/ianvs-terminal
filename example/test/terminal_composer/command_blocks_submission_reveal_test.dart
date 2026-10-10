import 'dart:async';

import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/terminal_composer/command_blocks_pane.dart';
import 'package:app/features/terminal_composer/composer_pane.dart';
import 'package:app/features/terminal_composer/terminal_mode.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../helpers/pump_app.dart';

class _Runtime extends Fake implements TerminalRuntimeController {
  final viewport = TerminalViewportController();
  final writes = <List<int>>[];
  final receipts = <String, Map<String, Object?>>{};
  final output = <Map<String, Object?>>[
    for (var i = 0; i < 30; i++) _block('old-$i', 'old command $i'),
  ];
  String ownership = 'ready';
  String contextId = 'root';
  String transport = 'shell';
  String? submissionId;
  bool publishReceipt = true;

  static Map<String, Object?> _block(
    String id,
    String command, {
    bool running = false,
  }) => {
    'id': id,
    'command': command,
    'cwd': '/tmp',
    'contextId': 'root',
    'running': running,
    'columns': 80,
    'totalLines': running ? 0 : 8,
    'exitCode': running ? null : 0,
    'lines': [
      if (!running)
        for (var i = 0; i < 8; i++)
          {'index': i, 'source_row': i + 100, 'text': '$command: output $i'},
    ],
  };

  @override
  TerminalViewportController? existingViewportFor(String sessionId) => viewport;
  @override
  Map<String, Object?>? liveScreen(String sessionId) => {
    'text': 'stable screen',
    'columns': 80,
    'rows': 24,
  };
  @override
  Map<String, Object?>? composerRequest(
    String sessionId,
    String operation,
    Map<String, Object?> payload,
  ) {
    if (operation == 'composer.state') {
      return {
        'state': ownership,
        'lease': ownership == 'ready' ? 'ready-lease' : null,
        'transport': transport,
        'contextId': contextId,
        'cwd': '/tmp',
        'dialect': 'zsh',
        'commandNames': ['sleep'],
      };
    }
    if (operation == 'composer.submit') {
      submissionId = payload['submissionId']! as String;
      ownership = 'running';
      output.add(_block('manual', payload['text']! as String, running: true));
      receipts[submissionId!] = {
        'submissionId': submissionId,
        'outcome': 'accepted',
        'blockId': 'manual',
      };
      return {'outcome': 'accepted'};
    }
    if (operation == 'composer.receipt') {
      return publishReceipt ? receipts[payload['submissionId']] : null;
    }
    return null;
  }

  @override
  Map<String, Object?>? commandBlocks(
    String sessionId, [
    Map<String, Object?> payload = const {},
  ]) => payload['id'] == null
      ? {'blocks': output}
      : {'block': output.firstWhere((block) => block['id'] == payload['id'])};
  @override
  void sendInput(String sessionId, Uint8List bytes) =>
      writes.add(List.of(bytes));
  @override
  void sendProtocolInput(String sessionId, Uint8List bytes) {}
}

void main() {
  group('$CommandBlocksPane explicit submission reveal', () {
    late _Runtime runtime;
    late ComposerPaneSession session;
    late FocusNode liveFocus;

    setUp(() {
      runtime = _Runtime();
      liveFocus = FocusNode(debugLabel: 'Fixture live terminal');
      session =
          ComposerPaneSession(
            sessionId: 'local',
            runtime: runtime,
            preferredMode: TerminalViewMode.blocks,
          )..updateEnvironment(
            const TerminalPane(
              sessionId: 'local',
              title: 'Local',
              profileId: 'local',
            ),
            readOnly: false,
          );
      session.setVisible(true);
    });
    Future<void> dispose(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      liveFocus.dispose();
      runtime.viewport.dispose();
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 35; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    test('a child must negotiate its own shell before offering Blocks', () {
      try {
        session.updateEnvironment(
          const TerminalPane(
            sessionId: 'local',
            title: 'Child shell',
            profileId: 'local',
            shellIntegration: TerminalShellIntegrationSnapshot(
              contextId: 'child',
              contextKind: 'shell',
            ),
          ),
          readOnly: false,
        );
        expect(
          session.mode.state.unavailableReason,
          BlockUnavailableReason.checking,
        );
        expect(session.selectMode(TerminalViewMode.blocks), isFalse);
        runtime.contextId = 'child';
        runtime.transport = 'local';
        session.refreshShellState();
        expect(
          session.mode.state.unavailableReason,
          BlockUnavailableReason.nestedShell,
        );
        expect(session.selectMode(TerminalViewMode.blocks), isFalse);
        runtime.transport = 'shell';
        session.refreshShellState();
        expect(session.mode.state.canUseBlocks, isTrue);
        expect(session.mode.state.mode, TerminalViewMode.normal);
        expect(session.selectMode(TerminalViewMode.blocks), isTrue);
      } finally {
        session.dispose();
        liveFocus.dispose();
        runtime.viewport.dispose();
      }
    });

    Future<ScrollController> mount(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final input = TerminalInputController(
        sessionId: 'local',
        runtime: runtime,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );
      await tester.pumpApp(
        Column(
          children: [
            Expanded(
              child: CommandBlocksPane(
                session: session,
                viewport: runtime.viewport,
                input: input,
                terminalFocus: liveFocus,
                active: true,
                font: const TerminalFontConfig(),
                onMeasuredCellSizeChanged: (_) {},
                onOpenLinkTarget: (_) {},
                child: const SizedBox.shrink(),
              ),
            ),
            ComposerPane(
              session: session,
              targetLabel: 'Local',
              active: true,
              available: true,
              onTerminalFocus: liveFocus.requestFocus,
              terminalFocus: liveFocus,
            ),
          ],
        ),
      );
      await settle(tester);
      final timeline = find.byType(CommandTimelineView);
      final scroll = tester.widget<CommandTimelineView>(timeline).controller;
      // Real wheel input detaches following before choosing an old position.
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getTopLeft(timeline) + const Offset(3, 180),
          scrollDelta: const Offset(0, -200),
        ),
      );
      await tester.pump();
      scroll.jumpTo(0);
      await settle(tester);
      expect(scroll.offset, closeTo(0, .1));
      return scroll;
    }

    testWidgets(
      'reveals only the accepted manual receipt, restores live input, and does not follow again',
      (tester) async {
        try {
          final scroll = await mount(tester);
          runtime.publishReceipt = false;
          await tester.enterText(
            find.byKey(const Key('composer-editor')),
            'sleep 30',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await settle(tester);
          expect(session.controller.ownership, ComposerOwnership.running);
          expect(scroll.offset, closeTo(0, .1));
          expect(
            find.byWidgetPredicate(
              (w) => w is CommandBlockTerminal && w.block.id == 'manual',
            ),
            findsNothing,
          );

          // A newer unrelated block cannot substitute for the manual receipt.
          runtime.output.add(_Runtime._block('agent', 'background AI command'));
          session.blocks.refresh();
          final original = runtime.receipts[runtime.submissionId]!;
          runtime.receipts[runtime.submissionId!] = {
            'submissionId': 'different-submission',
            'outcome': 'accepted',
            'blockId': 'agent',
          };
          runtime.publishReceipt = true;
          runtime.viewport.updateFrame(TerminalFrameDiff.empty);
          await settle(tester);
          expect(scroll.offset, closeTo(0, .1));
          runtime.receipts[runtime.submissionId!] = original;
          runtime.viewport.updateFrame(TerminalFrameDiff.empty);
          await settle(tester);
          final manual = find.byWidgetPredicate(
            (w) => w is CommandBlockTerminal && w.block.id == 'manual',
          );
          expect(manual, findsOneWidget);
          expect(scroll.offset, greaterThan(0));
          expect(liveFocus.hasFocus, isTrue);
          expect(session.blocks.activeId, isNull);
          expect(session.blocks.selected, isEmpty);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          expect(runtime.writes, [
            [3],
          ]);

          final reveal = session.blocks.revealRevision;
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position:
                  tester.getTopLeft(find.byType(CommandTimelineView)) +
                  const Offset(3, 180),
              scrollDelta: const Offset(0, -200),
            ),
          );
          await tester.pump();
          scroll.jumpTo(0);
          await settle(tester);
          expect(
            find.byKey(const ValueKey('command-block-old-0')),
            findsOneWidget,
          );
          expect(scroll.position.extentAfter, greaterThan(1000));
          final readingOffset = scroll.offset;
          runtime.viewport.updateFrame(TerminalFrameDiff.empty);
          await settle(tester);
          expect(scroll.offset, closeTo(readingOffset, .1));
          expect(session.blocks.revealRevision, reveal);
          expect(tester.takeException(), isNull);
        } finally {
          await dispose(tester);
        }
      },
    );

    testWidgets(
      'a completed command reveal preserves the restored editor focus',
      (tester) async {
        try {
          final scroll = await mount(tester);
          runtime.publishReceipt = false;
          final editor = find.byKey(const Key('composer-editor'));
          await tester.enterText(editor, 'sleep 0');
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await settle(tester);
          expect(session.controller.ownership, ComposerOwnership.running);
          expect(scroll.offset, closeTo(0, .1));

          // A fast command can return input to the editor before its block
          // receipt becomes visible to the coalesced presentation refresh.
          runtime.ownership = 'ready';
          runtime.output[runtime.output.indexWhere(
            (block) => block['id'] == 'manual',
          )] = _Runtime._block(
            'manual',
            'sleep 0',
          );
          session.refreshShellState();
          await tester.pump();
          expect(session.editorFocus.hasFocus, isTrue);
          runtime.publishReceipt = true;
          await settle(tester);

          expect(scroll.offset, greaterThan(0));
          expect(
            find.byWidgetPredicate(
              (w) => w is CommandBlockTerminal && w.block.id == 'manual',
            ),
            findsOneWidget,
          );
          expect(session.editorFocus.hasFocus, isTrue);
          expect(session.blocks.activeId, isNull);
          expect(runtime.writes, isEmpty);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await tester.pump();
          expect(session.blocks.activeId, 'manual');
          expect(session.editorFocus.hasFocus, isFalse);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          expect(session.editorFocus.hasFocus, isTrue);
          expect(tester.takeException(), isNull);
        } finally {
          await dispose(tester);
        }
      },
    );

    for (final destination in ['settings', 'inactive']) {
      testWidgets(
        'a fast command does not restore editing after focus moves to $destination',
        (tester) async {
          try {
            await mount(tester);
            runtime.publishReceipt = false;
            await tester.enterText(
              find.byKey(const Key('composer-editor')),
              'sleep 0',
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await settle(tester);
            expect(session.controller.ownership, ComposerOwnership.running);
            if (destination == 'settings') {
              unawaited(
                showDialog<void>(
                  context: tester.element(find.byType(ComposerPane)),
                  builder: (_) => const AlertDialog(
                    title: Text('Settings'),
                    content: TextField(autofocus: true),
                  ),
                ),
              );
              await tester.pumpAndSettle();
            } else {
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.inactive,
              );
              await tester.pump();
            }
            final owner = FocusManager.instance.primaryFocus;
            runtime.ownership = 'ready';
            runtime.output[runtime.output.indexWhere(
              (block) => block['id'] == 'manual',
            )] = _Runtime._block(
              'manual',
              'sleep 0',
            );
            session.refreshShellState();
            await tester.pump();
            await tester.pump();
            expect(FocusManager.instance.primaryFocus, same(owner));
            expect(session.editorFocus.hasFocus, isFalse);
          } finally {
            await dispose(tester);
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await tester.pump();
          }
        },
      );
    }

    testWidgets(
      'background commands preserve the reading anchor without a Composer submission',
      (tester) async {
        try {
          final scroll = await mount(tester);
          final reveal = session.blocks.revealRevision;
          runtime.ownership = 'running';
          runtime.output.add(
            _Runtime._block('agent', 'background AI command', running: true),
          );
          session.refreshShellState();
          session.blocks.refresh();
          await settle(tester);
          expect(scroll.offset, closeTo(0, .1));
          expect(session.blocks.revealRevision, reveal);
          expect(
            find.byWidgetPredicate(
              (w) => w is CommandBlockTerminal && w.block.running,
            ),
            findsNothing,
          );
          expect(runtime.writes, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await dispose(tester);
        }
      },
    );
  });
}
