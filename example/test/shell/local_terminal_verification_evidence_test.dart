import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/shell/local_terminal_verification_evidence.dart';

void main() {
  test('cannot close when only some required verification gates passed', () {
    const evidence = LocalTerminalVerificationEvidence(
      items: [
        LocalTerminalVerificationEvidenceItem(
          gate: LocalTerminalVerificationGate.unitTests,
          status: LocalTerminalVerificationStatus.passed,
          required: true,
          command:
              'bash tools/local_terminal_verification_capture.sh run '
              'all-automated',
        ),
        LocalTerminalVerificationEvidenceItem(
          gate: LocalTerminalVerificationGate.staticAnalysis,
          status: LocalTerminalVerificationStatus.passed,
          required: true,
          command: 'flutter analyze',
        ),
      ],
    );

    expect(evidence.canClose, isFalse);
    expect(
      evidence.gatePassed(LocalTerminalVerificationGate.unitTests),
      isTrue,
    );
    expect(
      evidence.gatePassed(LocalTerminalVerificationGate.staticAnalysis),
      isTrue,
    );
    expect(
      evidence.gatePassed(LocalTerminalVerificationGate.integrationTests),
      isFalse,
    );
    expect(
      evidence.missingRequiredGates,
      contains(LocalTerminalVerificationGate.integrationTests),
    );
    expect(
      evidence.toJson()['missingRequiredGates'],
      contains('integrationTests'),
    );
  });

  test('can close when every default required verification gate passed', () {
    final evidence = LocalTerminalVerificationEvidence(
      items: [
        for (final gate
            in LocalTerminalVerificationEvidence.defaultRequiredGates)
          LocalTerminalVerificationEvidenceItem(
            gate: gate,
            status: LocalTerminalVerificationStatus.passed,
            required: true,
          ),
      ],
    );

    expect(evidence.canClose, isTrue);
    expect(evidence.blockingItems, isEmpty);
    expect(evidence.missingRequiredGates, isEmpty);
    expect(evidence.verificationGateBlockerCount, 0);
  });

  test('keeps pending and skipped required gates as blockers', () {
    const evidence = LocalTerminalVerificationEvidence(
      items: [
        LocalTerminalVerificationEvidenceItem(
          gate: LocalTerminalVerificationGate.unitTests,
          status: LocalTerminalVerificationStatus.pending,
          required: true,
        ),
        LocalTerminalVerificationEvidenceItem(
          gate: LocalTerminalVerificationGate.manualLocalShellSmoke,
          status: LocalTerminalVerificationStatus.skipped,
          required: true,
          notes: ['Needs an interactive macOS shell run.'],
        ),
      ],
    );

    expect(evidence.canClose, isFalse);
    expect(evidence.blockingItems, hasLength(2));
    expect(evidence.missingRequiredGates, isNotEmpty);
    expect(
      evidence.verificationGateBlockerCount,
      2 + evidence.missingRequiredGates.length,
    );
    expect(evidence.toJson()['blockingItems'], [
      'unitTests',
      'manualLocalShellSmoke',
    ]);
  });

  test('default required evidence starts as fully blocked', () {
    final evidence = LocalTerminalVerificationEvidence.defaultRequiredPending(
      notes: const ['awaiting production wiring verification'],
    );

    expect(evidence.canClose, isFalse);
    expect(
      evidence.requiredItems,
      hasLength(LocalTerminalVerificationEvidence.defaultRequiredGates.length),
    );
    expect(
      evidence.blockingItems,
      hasLength(LocalTerminalVerificationEvidence.defaultRequiredGates.length),
    );
    expect(evidence.missingRequiredGates, isEmpty);
    expect(
      evidence.verificationGateBlockerCount,
      LocalTerminalVerificationEvidence.defaultRequiredGates.length,
    );
    expect(
      evidence.gatePassed(LocalTerminalVerificationGate.unitTests),
      isFalse,
    );
  });

  test('missing gate is not considered passed', () {
    const evidence = LocalTerminalVerificationEvidence(
      items: [
        LocalTerminalVerificationEvidenceItem(
          gate: LocalTerminalVerificationGate.unitTests,
          status: LocalTerminalVerificationStatus.passed,
          required: true,
        ),
      ],
    );

    expect(
      evidence.gatePassed(LocalTerminalVerificationGate.unitTests),
      isTrue,
    );
    expect(
      evidence.gatePassed(LocalTerminalVerificationGate.staticAnalysis),
      isFalse,
    );
    expect(
      evidence.missingRequiredGates,
      contains(LocalTerminalVerificationGate.staticAnalysis),
    );
  });
}
