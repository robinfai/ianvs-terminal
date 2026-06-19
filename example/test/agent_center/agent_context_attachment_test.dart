import 'package:app/features/agent_center/agent_center.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentContextAttachmentSet', () {
    const cwd = AgentContextAttachment(
      id: 'cwd',
      kind: AgentContextAttachmentKind.cwd,
      label: 'CWD',
      preview: '/repo',
      removable: false,
    );
    const output = AgentContextAttachment(
      id: 'selected-output:block-1',
      kind: AgentContextAttachmentKind.selectedOutput,
      label: 'Selected output',
      preview: 'test output',
    );

    test('upserts attachments by id', () {
      const set = AgentContextAttachmentSet(
        attachments: <AgentContextAttachment>[output],
      );

      final updated = set.upsert(
        output.copyWith(preview: 'new output', userPinned: true),
      );

      expect(updated.attachments, hasLength(1));
      expect(updated.byId(output.id)?.preview, 'new output');
      expect(updated.byId(output.id)?.userPinned, isTrue);
    });

    test('remove excludes removable context from the next Agent request', () {
      const set = AgentContextAttachmentSet(
        attachments: <AgentContextAttachment>[cwd, output],
      );

      final updated = set.remove(output.id);

      expect(updated.byId(output.id), isNull);
      expect(updated.byId(cwd.id), isNotNull);
    });

    test('remove preserves non-removable context', () {
      const set = AgentContextAttachmentSet(
        attachments: <AgentContextAttachment>[cwd],
      );

      final updated = set.remove(cwd.id);

      expect(updated.byId(cwd.id), isNotNull);
    });

    test('pins and unpins user-controlled context', () {
      const set = AgentContextAttachmentSet(
        attachments: <AgentContextAttachment>[output],
      );

      final pinned = set.pin(output.id);
      final unpinned = pinned.unpin(output.id);

      expect(pinned.byId(output.id)?.userPinned, isTrue);
      expect(unpinned.byId(output.id)?.userPinned, isFalse);
    });
  });

  group('previewContextText', () {
    test('normalizes whitespace and truncates long text', () {
      expect(
        previewContextText('  first\nsecond\tthird  ', maxLength: 13),
        'first second…',
      );
    });

    test('returns empty label for blank text', () {
      expect(previewContextText('  '), 'No preview');
    });
  });
}
