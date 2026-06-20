import 'package:app/features/agent_center/agent_center.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentConversationPane', () {
    final createdAt = DateTime.utc(2026, 6, 19, 12);

    testWidgets('renders an empty dedicated Agent surface with context chips', (
      tester,
    ) async {
      await _pumpPane(
        tester,
        contextChips: <AgentContextChipModel>[
          _chip(label: 'CWD', preview: '/Users/example'),
        ],
      );

      expect(find.byKey(const Key('agent-conversation-pane')), findsOneWidget);
      expect(find.text('Agent conversation'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('No Agent messages yet'), findsOneWidget);
      expect(find.text('CWD'), findsOneWidget);
    });

    testWidgets('renders user and assistant messages', (tester) async {
      final conversation =
          AgentConversation.empty(
                id: 'conversation-1',
                title: 'Build help',
                now: createdAt,
              )
              .appendMessage(
                AgentMessage.userText(
                  id: 'message-1',
                  conversationId: 'conversation-1',
                  text: 'Why did the test fail?',
                  createdAt: createdAt.add(const Duration(seconds: 1)),
                ),
              )
              .appendMessage(
                AgentMessage.assistantText(
                  id: 'message-2',
                  conversationId: 'conversation-1',
                  text: 'The failing assertion expected a command proposal.',
                  createdAt: createdAt.add(const Duration(seconds: 2)),
                ),
              );

      await _pumpPane(tester, conversation: conversation);

      expect(find.text('Build help'), findsOneWidget);
      expect(find.text('Why did the test fail?'), findsOneWidget);
      expect(
        find.text('The failing assertion expected a command proposal.'),
        findsOneWidget,
      );
      expect(find.text('Complete'), findsOneWidget);
    });

    testWidgets('renders command proposals without executing them', (
      tester,
    ) async {
      final proposal = AgentCommandProposal(
        id: 'proposal-1',
        conversationId: 'conversation-1',
        command: 'git status --short',
        cwd: '/repo',
        explanation: 'Inspect local changes before editing.',
        riskLevel: AgentCommandRiskLevel.low,
        requiresConfirmation: false,
        warnings: const <String>['Read-only inspection.'],
        detectedEffects: const <String>['No files are modified.'],
        createdAt: createdAt,
      );
      final conversation =
          AgentConversation.empty(
            id: 'conversation-1',
            now: createdAt,
          ).appendMessage(
            AgentMessage(
              id: 'message-1',
              conversationId: 'conversation-1',
              role: AgentMessageRole.assistant,
              parts: <AgentMessagePart>[
                AgentMessagePart.text('Try this first.'),
                AgentMessagePart.commandProposal(proposal),
              ],
              createdAt: createdAt,
            ),
          );
      AgentCommandProposal? inserted;
      AgentCommandProposal? reviewed;

      await _pumpPane(
        tester,
        conversation: conversation,
        onInsertProposal: (value) => inserted = value,
        onReviewProposal: (value) => reviewed = value,
      );

      expect(find.text('Proposed command'), findsOneWidget);
      expect(find.text('git status --short'), findsOneWidget);
      expect(find.text('Low risk'), findsOneWidget);

      await tester.tap(find.byKey(const Key('agent-command-proposal-review')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('agent-command-proposal-insert')));
      await tester.pump();

      expect(reviewed, same(proposal));
      expect(inserted, same(proposal));
    });

    testWidgets('exposes cancellation for streaming responses', (tester) async {
      var cancelled = false;
      final conversation =
          AgentConversation.empty(
            id: 'conversation-1',
            now: createdAt,
          ).appendMessage(
            AgentMessage.assistantText(
              id: 'message-1',
              conversationId: 'conversation-1',
              text: 'Working',
              status: AgentMessageStatus.streaming,
              createdAt: createdAt,
            ),
          );

      await _pumpPane(
        tester,
        conversation: conversation,
        onCancelStreaming: () => cancelled = true,
      );

      expect(find.text('Streaming'), findsNWidgets(2));

      await tester.tap(find.byKey(const Key('agent-conversation-cancel')));
      await tester.pump();

      expect(cancelled, isTrue);
    });

    testWidgets('shows a waiting state for empty streaming conversations', (
      tester,
    ) async {
      var cancelled = false;
      final conversation = AgentConversation.empty(
        id: 'conversation-1',
        now: createdAt,
      ).markStreaming(createdAt.add(const Duration(seconds: 1)));

      await _pumpPane(
        tester,
        conversation: conversation,
        onCancelStreaming: () => cancelled = true,
      );

      expect(find.text('Streaming'), findsOneWidget);
      expect(find.text('Waiting for Agent response'), findsOneWidget);
      expect(
        find.text(
          'The Agent is preparing a response. You can cancel if it takes too long.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('agent-conversation-cancel')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('agent-conversation-cancel')));
      await tester.pump();

      expect(cancelled, isTrue);
    });
  });
}

Future<void> _pumpPane(
  WidgetTester tester, {
  AgentConversation? conversation,
  List<AgentContextChipModel> contextChips = const <AgentContextChipModel>[],
  ValueChanged<AgentCommandProposal>? onInsertProposal,
  ValueChanged<AgentCommandProposal>? onReviewProposal,
  VoidCallback? onCancelStreaming,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildIanvsTerminalTheme(Brightness.light),
      darkTheme: buildIanvsTerminalTheme(Brightness.dark),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 620,
            height: 420,
            child: AgentConversationPane(
              conversation: conversation,
              contextChips: contextChips,
              onInsertProposal: onInsertProposal,
              onReviewProposal: onReviewProposal,
              onCancelStreaming: onCancelStreaming,
            ),
          ),
        ),
      ),
    ),
  );
}

AgentContextChipModel _chip({required String label, required String preview}) {
  return AgentContextChipModel(
    attachmentId: label,
    kind: AgentContextAttachmentKind.manualText,
    label: label,
    preview: preview,
    semanticLabel: '$label: $preview',
    tone: AgentContextChipTone.normal,
  );
}
