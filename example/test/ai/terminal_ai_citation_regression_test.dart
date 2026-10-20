import 'dart:async';

import 'package:app/features/ai/acp/agent_backend.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'terminal_ai_test.dart' show FakeTerminal, MemoryAiStore, contextFor;

class _StreamingAgent implements AgentBackend {
  final started = Completer<void>();
  final finished = Completer<void>();
  late AgentEventHandler events;

  @override
  Future<void> prompt(
    String prompt, {
    required AgentToolHandler tools,
    required AgentEventHandler events,
    required AiCancellation cancellation,
  }) {
    this.events = events;
    started.complete();
    return finished.future;
  }

  void append(String text) => events({
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  });

  @override
  Future<void> dispose() async {
    if (!finished.isCompleted) finished.complete();
  }
}

void main() {
  for (final size in [const Size(960, 700), const Size(390, 600)]) {
    testWidgets('streamed duplicate and overlapping evidence stays usable $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final terminal = FakeTerminal()
        ..context = contextFor(
          lastBlock: const AiBlockContext(
            id: 'docker-output',
            command: 'docker ps -a --size',
            output: 'one\ntwo\nthree\nfour\nfive\nsix',
            exitCode: 0,
            cwd: '/tmp',
            totalLines: 6,
            outputEndLine: 6,
          ),
        );
      final settings = AiSettingsController(
        MemoryAiStore(const AiConfiguration.acp(agentCommand: '/fixture')),
      );
      await settings.loaded;
      final agent = _StreamingAgent();
      final controller = TerminalAiController(
        settings: settings,
        terminal: terminal,
        agentFactory: (_) => agent,
      );
      addTearDown(() {
        controller.dispose();
        settings.dispose();
      });
      final opened = <AiEvidenceReference>[];
      final asking = controller.ask('Explain the existing output');
      await agent.started.future;
      agent.append('Initial evidence [block:docker-output:1-2]');
      await tester.pumpWidget(
        MaterialApp(
          theme: buildIanvsTerminalTheme(Brightness.light),
          home: Scaffold(
            body: TerminalAiWorkspace(
              controller: controller,
              onClose: () {},
              onShowEvidence: opened.add,
            ),
          ),
        ),
      );
      await tester.pump();
      Finder citation(int end) =>
          find.byKey(Key('ai-evidence-docker-output-0-$end'));
      expect(find.text('Evidence · 1–2'), findsOneWidget);
      final first = tester.element(find.text('Evidence · 1–2'));
      // Selection exists while the same message is incrementally rebuilt.
      await tester.longPress(find.text('Initial evidence', findRichText: true));
      await tester.pump();
      agent.append(
        ' Again [block:docker-output:1-2]. More [block:docker-output:1-6] and [block:docker-output:1-4].',
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Evidence · 1–2'), findsOneWidget);
      expect(find.text('Evidence · 1–6'), findsOneWidget);
      expect(find.text('Evidence · 1–4'), findsOneWidget);
      expect(tester.element(find.text('Evidence · 1–2')), same(first));
      // Dismiss the selection toolbar before interacting with citations.
      await tester.tap(find.byKey(const Key('ai-prompt')));
      await tester.pumpAndSettle();
      for (final end in [2, 6, 4]) {
        await tester.ensureVisible(citation(end));
        await tester.pumpAndSettle();
        await tester.tap(citation(end));
        await tester.pump();
      }
      expect(opened.map((r) => (r.id, r.startLine, r.endLine)), [
        ('docker-output', 0, 2),
        ('docker-output', 0, 6),
        ('docker-output', 0, 4),
      ]);
      // Repeated citations must not consume the visible distinct-reference cap.
      agent.append(
        '${List.filled(25, '[block:docker-output:1-2]').join(' ')} [block:docker-output:5-6] [block:unknown:1-2]',
      );
      await tester.pump();
      expect(find.text('Evidence · 5–6'), findsOneWidget);
      expect(find.byKey(const Key('ai-evidence-unknown-0-2')), findsNothing);
      agent.finished.complete();
      await asking;
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -100));
      await tester.pumpAndSettle();
      controller.newTask();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(terminal.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
