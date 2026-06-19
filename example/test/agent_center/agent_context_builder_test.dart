import 'package:app/features/agent_center/agent_center.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentContextBuilder', () {
    final startedAt = DateTime.utc(2026, 6, 19, 13);

    test('builds useful context for a normal terminal session', () {
      const builder = AgentContextBuilder();

      final snapshot = builder.build(
        AgentContextSource(
          terminalSessionId: 'terminal-1',
          cwd: '/Users/luobinghui/project',
          shell: '/bin/zsh',
          profileId: 'local-shell',
          profileName: 'Local Shell',
          readOnly: true,
          shellHookAvailable: true,
          recentCommands: <AgentRecentCommandSnapshot>[
            AgentRecentCommandSnapshot(
              command: 'git status',
              status: AgentRecentCommandStatus.succeeded,
              exitCode: 0,
            ),
          ],
          visibleScrollback: 'prompt\noutput',
        ),
      );

      expect(snapshot.terminalSessionId, 'terminal-1');
      expect(snapshot.cwd, '/Users/luobinghui/project');
      expect(snapshot.shell, '/bin/zsh');
      expect(snapshot.profileName, 'Local Shell');
      expect(snapshot.readOnly, isTrue);
      expect(snapshot.shellHookAvailable, isTrue);
      expect(snapshot.sessionSummary, isNotNull);
      expect(
        snapshot.sessionSummary?.toMemoryText(),
        contains('Recent commands: 1'),
      );
      expect(snapshot.recentCommands, hasLength(1));
      expect(snapshot.visibleScrollbackExcerpt, 'prompt\noutput');
      expect(
        snapshot.attachments.map((attachment) => attachment.kind),
        containsAll(<AgentContextAttachmentKind>[
          AgentContextAttachmentKind.cwd,
          AgentContextAttachmentKind.shell,
          AgentContextAttachmentKind.profile,
          AgentContextAttachmentKind.sessionSummary,
          AgentContextAttachmentKind.recentCommands,
          AgentContextAttachmentKind.visibleScrollback,
        ]),
      );
    });

    test('does not throw on empty or missing terminal state', () {
      const builder = AgentContextBuilder();

      final snapshot = builder.build(
        const AgentContextSource(terminalSessionId: 'terminal-empty'),
      );

      expect(snapshot.terminalSessionId, 'terminal-empty');
      expect(snapshot.cwd, isNull);
      expect(snapshot.sessionSummary, isNull);
      expect(snapshot.selectedBlock, isNull);
      expect(snapshot.lastFailedBlock, isNull);
      expect(snapshot.recentCommands, isEmpty);
      expect(snapshot.attachments, isEmpty);
    });

    test('represents selected and last failed blocks together', () {
      const builder = AgentContextBuilder();

      final snapshot = builder.build(
        AgentContextSource(
          terminalSessionId: 'terminal-1',
          selectedBlock: AgentCommandBlockSnapshot(
            id: 'block-selected',
            command: 'flutter test',
            outputExcerpt: 'All tests passed',
            startedAt: startedAt,
          ),
          lastFailedBlock: AgentCommandBlockSnapshot(
            id: 'block-failed',
            command: 'dart analyze',
            exitCode: 1,
            outputExcerpt: 'error: missing import',
            startedAt: startedAt.subtract(const Duration(minutes: 1)),
          ),
        ),
      );

      expect(snapshot.selectedBlock?.id, 'block-selected');
      expect(snapshot.lastFailedBlock?.id, 'block-failed');
      expect(
        snapshot.attachments.map((attachment) => attachment.id),
        containsAll(<String>[
          'selected-block:block-selected',
          'last-failed-block:block-failed',
        ]),
      );
    });

    test('trims selected output and visible scrollback budgets', () {
      const builder = AgentContextBuilder(
        selectedOutputMaxChars: 5,
        visibleScrollbackMaxChars: 4,
      );

      final snapshot = builder.build(
        const AgentContextSource(
          terminalSessionId: 'terminal-1',
          selectedOutput: AgentTerminalOutputSelection(
            text: '0123456789',
            blockId: 'block-1',
          ),
          visibleScrollback: 'abcdef',
        ),
      );

      expect(snapshot.selectedOutput?.text, '56789');
      expect(snapshot.visibleScrollbackExcerpt, 'cdef');
      expect(
        snapshot.attachments
            .firstWhere(
              (attachment) =>
                  attachment.kind == AgentContextAttachmentKind.selectedOutput,
            )
            .preview,
        '56789',
      );
    });

    test('limits recent commands for request context', () {
      const builder = AgentContextBuilder(recentCommandLimit: 2);

      final snapshot = builder.build(
        const AgentContextSource(
          terminalSessionId: 'terminal-1',
          recentCommands: <AgentRecentCommandSnapshot>[
            AgentRecentCommandSnapshot(
              command: 'one',
              status: AgentRecentCommandStatus.succeeded,
            ),
            AgentRecentCommandSnapshot(
              command: 'two',
              status: AgentRecentCommandStatus.succeeded,
            ),
            AgentRecentCommandSnapshot(
              command: 'three',
              status: AgentRecentCommandStatus.succeeded,
            ),
          ],
        ),
      );

      expect(
        snapshot.recentCommands.map((command) => command.command),
        <String>['one', 'two'],
      );
    });

    test('redacts request context before building snapshot and payloads', () {
      const builder = AgentContextBuilder(
        selectedOutputMaxChars: 400,
        visibleScrollbackMaxChars: 400,
        blockOutputMaxChars: 400,
        commandMaxChars: 400,
        recentCommandMaxChars: 400,
      );

      final snapshot = builder.build(
        AgentContextSource(
          terminalSessionId: 'terminal-1',
          cwd: '/repo/password=path-secret',
          selectedBlock: const AgentCommandBlockSnapshot(
            id: 'selected',
            command:
                'curl -H "Authorization: Bearer selectedbearersecret" https://example.test',
            outputExcerpt: 'token=selected-output-token',
          ),
          selectedOutput: const AgentTerminalOutputSelection(
            text: 'DEEPSEEK_API_KEY=selected-api-key\npassword=hunter2',
            blockId: 'selected',
          ),
          lastFailedBlock: const AgentCommandBlockSnapshot(
            id: 'failed',
            command: 'export API_TOKEN=failed-token-value && false',
            exitCode: 1,
            outputExcerpt:
                '-----BEGIN PRIVATE KEY-----\nprivate-key-body\n-----END PRIVATE KEY-----',
          ),
          recentCommands: const <AgentRecentCommandSnapshot>[
            AgentRecentCommandSnapshot(
              command: 'deploy --password recent-password --token recent-token',
              status: AgentRecentCommandStatus.failed,
              exitCode: 1,
            ),
          ],
          visibleScrollback:
              'Authorization: Bearer scrollbackbearersecret\nsecret=scrollback-secret',
        ),
      );

      final snapshotText = _snapshotDebugText(snapshot);

      expect(snapshotText, contains('[REDACTED]'));
      expect(snapshotText, isNot(contains('path-secret')));
      expect(snapshotText, isNot(contains('selectedbearersecret')));
      expect(snapshotText, isNot(contains('selected-output-token')));
      expect(snapshotText, isNot(contains('selected-api-key')));
      expect(snapshotText, isNot(contains('hunter2')));
      expect(snapshotText, isNot(contains('failed-token-value')));
      expect(snapshotText, isNot(contains('private-key-body')));
      expect(snapshotText, isNot(contains('recent-password')));
      expect(snapshotText, isNot(contains('recent-token')));
      expect(snapshotText, isNot(contains('scrollbackbearersecret')));
      expect(snapshotText, isNot(contains('scrollback-secret')));
    });

    test('applies budgets to commands and metadata fields', () {
      const builder = AgentContextBuilder(
        commandMaxChars: 4,
        metadataMaxChars: 5,
        recentCommandMaxChars: 6,
      );

      final snapshot = builder.build(
        const AgentContextSource(
          terminalSessionId: 'terminal-1',
          cwd: '/abcdef',
          selectedBlock: AgentCommandBlockSnapshot(
            id: 'selected',
            command: '0123456789',
          ),
          recentCommands: <AgentRecentCommandSnapshot>[
            AgentRecentCommandSnapshot(
              command: 'recent-command',
              status: AgentRecentCommandStatus.succeeded,
              cwd: '/recent-directory',
            ),
          ],
        ),
      );

      expect(snapshot.cwd, 'bcdef');
      expect(snapshot.selectedBlock?.command, '6789');
      expect(snapshot.recentCommands.single.command, 'ommand');
      expect(snapshot.recentCommands.single.cwd, 'ctory');
    });

    test('summarizes selected and failed command state for memory bridge', () {
      const builder = AgentContextBuilder();

      final snapshot = builder.build(
        const AgentContextSource(
          terminalSessionId: 'terminal-1',
          cwd: '/repo',
          profileName: 'Local Shell',
          selectedBlock: AgentCommandBlockSnapshot(
            id: 'block-selected',
            command: 'flutter test',
            exitCode: 0,
          ),
          lastFailedBlock: AgentCommandBlockSnapshot(
            id: 'block-failed',
            command: 'dart analyze',
            exitCode: 1,
          ),
          recentCommands: <AgentRecentCommandSnapshot>[
            AgentRecentCommandSnapshot(
              command: 'flutter test',
              status: AgentRecentCommandStatus.succeeded,
              exitCode: 0,
            ),
            AgentRecentCommandSnapshot(
              command: 'dart analyze',
              status: AgentRecentCommandStatus.failed,
              exitCode: 1,
            ),
          ],
        ),
      );

      expect(snapshot.sessionSummary, isNotNull);
      expect(snapshot.sessionSummary?.preview, contains('2 recent commands'));
      expect(
        snapshot.sessionSummary?.toMemoryText(),
        allOf(
          contains('CWD: /repo'),
          contains('Recent commands: 2 (1 failed)'),
          contains('Selected block: flutter test'),
          contains('Last failed: dart analyze (exit 1)'),
        ),
      );
      expect(
        snapshot.attachments
            .firstWhere(
              (attachment) =>
                  attachment.kind == AgentContextAttachmentKind.sessionSummary,
            )
            .id,
        'session-summary',
      );
    });
  });
}

String _snapshotDebugText(AgentContextSnapshot snapshot) {
  final buffer = StringBuffer()
    ..writeln(snapshot.cwd)
    ..writeln(snapshot.shell)
    ..writeln(snapshot.profileId)
    ..writeln(snapshot.profileName)
    ..writeln(snapshot.visibleScrollbackExcerpt)
    ..writeln(snapshot.sessionSummary?.preview)
    ..writeln(snapshot.sessionSummary?.toMemoryText());
  _writeBlock(buffer, snapshot.selectedBlock);
  _writeSelection(buffer, snapshot.selectedOutput);
  _writeBlock(buffer, snapshot.lastFailedBlock);
  for (final command in snapshot.recentCommands) {
    _writeRecentCommand(buffer, command);
  }
  for (final attachment in snapshot.attachments) {
    buffer
      ..writeln(attachment.id)
      ..writeln(attachment.label)
      ..writeln(attachment.preview);
    _writePayload(buffer, attachment.payload);
  }
  return buffer.toString();
}

void _writePayload(StringBuffer buffer, Object? payload) {
  if (payload is AgentCommandBlockSnapshot) {
    _writeBlock(buffer, payload);
  } else if (payload is AgentTerminalOutputSelection) {
    _writeSelection(buffer, payload);
  } else if (payload is AgentSessionSummary) {
    buffer
      ..writeln(payload.preview)
      ..writeln(payload.toMemoryText());
  } else if (payload is List<AgentRecentCommandSnapshot>) {
    for (final command in payload) {
      _writeRecentCommand(buffer, command);
    }
  } else if (payload is Map<String, Object?>) {
    for (final entry in payload.entries) {
      buffer
        ..writeln(entry.key)
        ..writeln(entry.value);
    }
  } else {
    buffer.writeln(payload);
  }
}

void _writeBlock(StringBuffer buffer, AgentCommandBlockSnapshot? block) {
  buffer
    ..writeln(block?.command)
    ..writeln(block?.cwd)
    ..writeln(block?.outputExcerpt);
}

void _writeSelection(
  StringBuffer buffer,
  AgentTerminalOutputSelection? selection,
) {
  buffer
    ..writeln(selection?.text)
    ..writeln(selection?.blockId);
}

void _writeRecentCommand(
  StringBuffer buffer,
  AgentRecentCommandSnapshot command,
) {
  buffer
    ..writeln(command.command)
    ..writeln(command.cwd);
}
