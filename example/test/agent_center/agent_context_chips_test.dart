import 'package:app/features/agent_center/agent_center.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentContextChipState', () {
    test('converts snapshot attachments into short stable chips', () {
      final snapshot = const AgentContextBuilder().build(
        const AgentContextSource(
          terminalSessionId: 'terminal-1',
          cwd: '/repo',
          selectedBlock: AgentCommandBlockSnapshot(
            id: 'block-1',
            command: 'flutter test',
          ),
          selectedOutput: AgentTerminalOutputSelection(
            text: 'a selected output line',
            blockId: 'block-1',
          ),
          lastFailedBlock: AgentCommandBlockSnapshot(
            id: 'block-2',
            command: 'dart analyze',
            exitCode: 1,
          ),
          recentCommands: <AgentRecentCommandSnapshot>[
            AgentRecentCommandSnapshot(
              command: 'pwd',
              status: AgentRecentCommandStatus.succeeded,
            ),
          ],
        ),
      );

      final chips = AgentContextChipState.fromSnapshot(snapshot);

      expect(
        chips.chips.map((chip) => chip.label),
        containsAll(<String>[
          'CWD',
          'Summary',
          'Block',
          'Selection',
          'Last failed',
          'Recent',
        ]),
      );
      expect(
        chips.chipByAttachmentId('last-failed-block:block-2')?.tone,
        AgentContextChipTone.danger,
      );
    });

    test('remove updates chip state and next request attachments', () {
      final state =
          AgentContextChipState.fromAttachments(const <AgentContextAttachment>[
            AgentContextAttachment(
              id: 'cwd',
              kind: AgentContextAttachmentKind.cwd,
              label: 'CWD',
              preview: '/repo',
              removable: false,
            ),
            AgentContextAttachment(
              id: 'selected-output',
              kind: AgentContextAttachmentKind.selectedOutput,
              label: 'Selected output',
              preview: 'output',
            ),
          ]);

      final updated = state.remove('selected-output');

      expect(updated.chipByAttachmentId('selected-output'), isNull);
      expect(updated.attachments.map((attachment) => attachment.id), <String>[
        'cwd',
      ]);
    });

    test('pin and unpin keep chip state in sync', () {
      final state =
          AgentContextChipState.fromAttachments(const <AgentContextAttachment>[
            AgentContextAttachment(
              id: 'manual',
              kind: AgentContextAttachmentKind.manualText,
              label: 'Note',
              preview: 'Remember this',
            ),
          ]);

      final pinned = state.pin('manual');
      final unpinned = pinned.unpin('manual');

      expect(pinned.chipByAttachmentId('manual')?.pinned, isTrue);
      expect(unpinned.chipByAttachmentId('manual')?.pinned, isFalse);
    });

    test('does not render sensitive or huge payload directly as chip text', () {
      final hugePayload = List<String>.filled(200, 'secret-token').join(' ');
      final state =
          AgentContextChipState.fromAttachments(<AgentContextAttachment>[
            AgentContextAttachment(
              id: 'manual',
              kind: AgentContextAttachmentKind.manualText,
              label: 'Note',
              preview: hugePayload,
              payload: hugePayload,
              sensitive: true,
            ),
          ]);

      final chip = state.chips.single;

      expect(chip.preview, 'Sensitive context hidden');
      expect(chip.preview, isNot(contains('secret-token')));
      expect(chip.detailsAvailable, isTrue);
      expect(chip.tone, AgentContextChipTone.warning);
    });

    test('truncates long non-sensitive previews', () {
      final state =
          AgentContextChipState.fromAttachments(<AgentContextAttachment>[
            AgentContextAttachment(
              id: 'visible-scrollback',
              kind: AgentContextAttachmentKind.visibleScrollback,
              label: 'Visible scrollback',
              preview: List<String>.filled(20, 'scrollback').join(' '),
            ),
          ]);

      expect(state.chips.single.preview.length, lessThanOrEqualTo(72));
      expect(state.chips.single.preview.endsWith('…'), isTrue);
    });
  });
}
