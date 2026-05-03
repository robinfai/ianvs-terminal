import 'package:flutter_test/flutter_test.dart';

import 'package:ianvs_terminal/src/session_metadata.dart';
import 'package:ianvs_terminal/src/terminal_blocks.dart';

void main() {
  test('ssh metadata derives badges compact label and preferred tab title', () {
    const metadata = TerminalSessionMetadata(
      kind: TerminalSessionKind.ssh,
      host: 'prod.example.internal',
      account: 'ops-user',
      environment: 'prod-use1',
      project: 'payments-api',
      safetyContext: TerminalSafetyContext(
        identity: 'robin.oncall',
        authorizationSource: 'Ianvs Access',
        validUntil: '2026-05-03T18:00:00Z',
      ),
    );

    expect(metadata.isSsh, isTrue);
    expect(metadata.compactContextLabel, 'payments-api');
    expect(metadata.preferredTabTitle, 'payments-api');
    expect(metadata.targetBadges, <String>[
      'Host prod.example.internal',
      'Account ops-user',
      'Env prod-use1',
      'Project payments-api',
    ]);
    expect(metadata.safetyContext.badges, <String>[
      'Identity robin.oncall',
      'Source Ianvs Access',
      'Valid until 2026-05-03T18:00:00Z',
    ]);
  });

  test('audit snapshot summarizes completed blocks and skips running ones', () {
    const metadata = TerminalSessionMetadata(
      kind: TerminalSessionKind.ssh,
      environment: 'prod-eu',
      project: 'ledger',
    );
    final snapshot = buildTerminalSessionAuditSnapshot(
      metadata: metadata,
      exportedAt: DateTime.utc(2026, 5, 3, 10, 30),
      blocks: const <TerminalBlock>[
        TerminalBlock(
          id: 'block-1',
          sessionId: 'session-1',
          commandText: 'kubectl get pods',
          outputText: 'pod-a\npod-b\n',
          status: TerminalBlockStatus.succeeded,
          scrollbackOffset: 0,
        ),
        TerminalBlock(
          id: 'block-2',
          sessionId: 'session-1',
          commandText: 'tail -f app.log',
          outputText: '',
          status: TerminalBlockStatus.running,
          scrollbackOffset: 8,
        ),
      ],
    );

    expect(snapshot.exportedAt, '2026-05-03T10:30:00.000Z');
    expect(snapshot.entries.length, 1);
    expect(snapshot.entries.single.commandText, 'kubectl get pods');
    expect(snapshot.entries.single.outputSummary, 'pod-a pod-b');
    expect(snapshot.entries.single.targetEnvironment, 'prod-eu');
  });

  test('audit snapshot preserves block completion context', () {
    const metadata = TerminalSessionMetadata(
      kind: TerminalSessionKind.ssh,
      environment: 'prod-new',
      project: 'ledger',
    );
    final snapshot = buildTerminalSessionAuditSnapshot(
      metadata: metadata,
      exportedAt: DateTime.utc(2026, 5, 3, 10, 30),
      blocks: const <TerminalBlock>[
        TerminalBlock(
          id: 'block-1',
          sessionId: 'session-1',
          commandText: 'kubectl rollout status deploy/api',
          outputText: 'done\n',
          status: TerminalBlockStatus.succeeded,
          scrollbackOffset: 12,
          recordedAt: '2026-05-03T09:45:00.000Z',
          targetEnvironment: 'prod-old',
        ),
      ],
    );

    expect(snapshot.entries.single.recordedAt, '2026-05-03T09:45:00.000Z');
    expect(snapshot.entries.single.targetEnvironment, 'prod-old');
  });
}
