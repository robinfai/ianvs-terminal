import 'package:app/features/ai/acp/agent_backend.dart';
import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/ai/terminal_ai_controller.dart';
import 'package:app/features/ai/terminal_ai_workspace.dart';
import 'package:app/ui/components/app_prompt_surface.dart';
import 'package:app/ui/foundation/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_agent_chat/ianvs_agent_chat.dart';

import 'terminal_ai_test.dart' show FakeTerminal, MemoryAiStore;

class _ContentAgent implements AgentBackend {
  @override
  Future<void> prompt(
    String prompt, {
    required AgentToolHandler tools,
    required AgentEventHandler events,
    required AiCancellation cancellation,
  }) async {
    events({
      'sessionUpdate': 'trail_content',
      'kind': 'plan',
      'text': 'Plan',
      'metadata': {
        'entries': [
          {'content': 'Inspect current terminal', 'status': 'pending'},
        ],
      },
    });
    events({
      'sessionUpdate': 'trail_content',
      'kind': 'tool_call',
      'text': 'Terminal activity',
      'metadata': {
        'toolCallId': 'tool',
        'status': 'completed',
        'rawInput': {
          'server': 'trail_terminal',
          'tool': 'run_command',
          'arguments': {'operation_id': 'unverified', 'command': 'pwd'},
        },
        'rawOutput': 'DO NOT COPY TERMINAL OUTPUT',
        'content': [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': 'DO NOT COPY TERMINAL OUTPUT'},
          },
        ],
      },
    });
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  for (final mobile in [true, false]) {
    testWidgets(
      'shared tool and plan embed without duplicate output mobile=$mobile',
      (tester) async {
        tester.view.physicalSize = Size(mobile ? 320 : 1000, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final settings = AiSettingsController(MemoryAiStore());
        await settings.loaded;
        await settings.save(
          const AiConfiguration.acp(agentCommand: '/fixture'),
        );
        final terminal = FakeTerminal();
        final controller = TerminalAiController(
          settings: settings,
          terminal: terminal,
          agentFactory: (_) => _ContentAgent(),
        );
        addTearDown(controller.dispose);
        addTearDown(settings.dispose);
        await controller.ask('Inspect');
        await tester.pumpWidget(
          MaterialApp(
            theme: buildIanvsTerminalTheme(
              Brightness.dark,
              platform: mobile ? TargetPlatform.iOS : TargetPlatform.macOS,
            ),
            home: Scaffold(
              body: TerminalAiWorkspace(
                controller: controller,
                onClose: () {},
                compactMobile: mobile,
                unifiedWorkspace: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ChatPlanCard), findsOneWidget);
        expect(find.byType(ChatToolCard), findsOneWidget);
        expect(
          tester.widget<ChatToolCard>(find.byType(ChatToolCard)).showDetails,
          isFalse,
        );
        expect(
          find.textContaining('DO NOT COPY TERMINAL OUTPUT'),
          findsNothing,
        );
        expect(find.byType(AppPromptSurface), findsOneWidget);
        expect(find.byKey(const Key('ai-prompt')), findsOneWidget);
        expect(terminal.writes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
