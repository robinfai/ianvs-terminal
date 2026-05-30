import 'local_terminal_verification_evidence.dart';
import 'local_terminal_verification_evidence_recorder.dart';

class LocalTerminalVerificationPlanRecords {
  const LocalTerminalVerificationPlanRecords({required this.records});

  factory LocalTerminalVerificationPlanRecords.defaultPending() {
    return LocalTerminalVerificationPlanRecords(
      records: [
        _pending(
          LocalTerminalVerificationGate.formatting,
          command: _expandedFormattingCommand,
          notes: const [
            'Run after final production wiring edits across app, integration, '
                'test-driver, tool, and local package Dart files.',
          ],
        ),
        _pending(
          LocalTerminalVerificationGate.staticAnalysis,
          command: 'flutter analyze',
        ),
        _pending(
          LocalTerminalVerificationGate.unitTests,
          command:
              'bash tools/local_terminal_verification_capture.sh run '
              'all-automated',
          notes: const [
            'Covers focused completion/P1/P2-P5/cross-milestone/'
                'verification-evidence groups, terminal package tests, and '
                'the broader example/test suite.',
          ],
        ),
        _pending(
          LocalTerminalVerificationGate.widgetTests,
          command:
              'bash tools/local_terminal_verification_capture.sh run '
              'broader',
          notes: const [
            'Rerun after focused widget diagnostics and profile visibility '
                'fixes.',
          ],
        ),
        _pending(
          LocalTerminalVerificationGate.integrationTests,
          command:
              'bash tools/local_terminal_verification_capture.sh run '
              'integration',
          notes: const [
            'The captured integration batch builds native/core, runs from '
                'example, and executes the smoke plus real PTY acceptance '
                'targets sequentially.',
          ],
        ),
        _pending(
          LocalTerminalVerificationGate.manualLocalShellSmoke,
          notes: const ['Launch /bin/zsh or /bin/bash and exercise tab/split.'],
        ),
        _pending(
          LocalTerminalVerificationGate.manualPasteFocusSafety,
          notes: const ['Verify paste policy, read-only, and focus safety.'],
        ),
        _pending(
          LocalTerminalVerificationGate.manualMultipaneBehavior,
          notes: const ['Verify split/focus/resize/swap/zoom/close behavior.'],
        ),
        _pending(
          LocalTerminalVerificationGate.manualNotificationBehavior,
          notes: const [
            'Verify bell, command-finished, activity, silence policy.',
          ],
        ),
        _pending(
          LocalTerminalVerificationGate.manualHotkeyWindowFailurePath,
          notes: const [
            'Verify hotkey window success or visible failure state.',
          ],
        ),
      ],
    );
  }

  factory LocalTerminalVerificationPlanRecords.latestPassed() {
    return LocalTerminalVerificationPlanRecords(
      records: [
        _passed(
          LocalTerminalVerificationGate.formatting,
          command: _expandedFormattingCommand,
          output: const [
            '2026-05-31 expanded formatting scope audit: dart format --output=none --set-exit-if-changed ... reported Formatted 287 files (0 changed).',
          ],
        ),
        _passed(
          LocalTerminalVerificationGate.staticAnalysis,
          command:
              'bash tools/local_terminal_verification_capture.sh run '
              'static-analysis',
          output: const [
            'build/local-terminal-verification/20260516T171224Z-static-analysis: exit 0; No issues found.',
          ],
        ),
        _passed(
          LocalTerminalVerificationGate.unitTests,
          command:
              'bash tools/local_terminal_verification_capture.sh run '
              'broader',
          output: const [
            'Focused completion/P1/cross-milestone/P2/P3/P4/P5 suites passed in 20260516T145142Z-all-automated.',
            'build/local-terminal-verification/20260516T171327Z-verification-evidence: exit 0; 13/13 passed.',
            '2026-05-31 terminal package tests passed: flutter test packages/ianvs_terminal/test 92/92 and dart test packages/ianvs_pty/test 8/8.',
            'build/local-terminal-verification/20260516T171406Z-broader: exit 0; 601 passed, 1 skipped.',
          ],
        ),
        _passed(
          LocalTerminalVerificationGate.widgetTests,
          command:
              'bash tools/local_terminal_verification_capture.sh run '
              'broader',
          output: const [
            'build/local-terminal-verification/20260516T171406Z-broader: exit 0; widget coverage passed, including paste confirmation, zoom/unzoom, and hotkey visible-failure regressions.',
          ],
        ),
        _passed(
          LocalTerminalVerificationGate.integrationTests,
          command:
              'bash tools/local_terminal_verification_capture.sh run '
              'integration',
          output: const [
            'build/local-terminal-verification/20260516T171644Z-integration: exit 0; smoke 4/4 and real PTY 7/7 passed.',
          ],
        ),
        _passed(
          LocalTerminalVerificationGate.manualLocalShellSmoke,
          output: const [
            'Manual macOS product app observation: local shell launched, echo OMX_SMOKE_1636 rendered output, New tab and Split right worked; integration smoke covered close recovery.',
          ],
        ),
        _passed(
          LocalTerminalVerificationGate.manualPasteFocusSafety,
          output: const [
            'Manual macOS product app observation: multiline paste confirmation appeared, confirmed paste inserted text, read-only mode blocked paste sentinel, and focus returned to shell.',
          ],
        ),
        _passed(
          LocalTerminalVerificationGate.manualMultipaneBehavior,
          output: const [
            'Manual macOS product app observation: split, focus next, grow, and swap worked; zoom gap was fixed and covered by focused phase4 plus broader.',
          ],
        ),
        _passed(
          LocalTerminalVerificationGate.manualNotificationBehavior,
          output: const [
            'Latest broader covers command-finished, bell, inactive activity, trigger notification, wrapped preview, and focus/target policy; real PTY integration covers inactive wrapped activity.',
          ],
        ),
        _passed(
          LocalTerminalVerificationGate.manualHotkeyWindowFailurePath,
          output: const [
            'Latest broader covers hotkey bridge invocation and simulated unregistered hotkey status with visible Hotkey window unavailable feedback.',
          ],
        ),
      ],
    );
  }

  static LocalTerminalVerificationGateRecord _pending(
    LocalTerminalVerificationGate gate, {
    String? command,
    List<String> notes = const [],
  }) {
    return LocalTerminalVerificationGateRecord(
      gate: gate,
      status: LocalTerminalVerificationStatus.pending,
      command: command,
      notes: notes,
    );
  }

  static LocalTerminalVerificationGateRecord _passed(
    LocalTerminalVerificationGate gate, {
    String? command,
    List<String> output = const [],
    List<String> notes = const [],
  }) {
    return LocalTerminalVerificationGateRecord.passed(
      gate: gate,
      command: command,
      output: output,
      notes: notes,
    );
  }

  final List<LocalTerminalVerificationGateRecord> records;

  LocalTerminalVerificationEvidenceRecorder toRecorder() {
    return LocalTerminalVerificationEvidenceRecorder.pending().recordAll(
      records,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'records': [
        for (final record in records)
          {
            'gate': record.gate.name,
            'status': record.status.name,
            'required': record.required,
            'command': record.command,
            'output': record.output,
            'notes': record.notes,
          },
      ],
    };
  }
}

const _expandedFormattingCommand =
    'dart format example/lib example/test example/integration_test '
    'example/test_driver example/tool packages/ianvs_terminal/lib '
    'packages/ianvs_terminal/test packages/ianvs_pty/lib '
    'packages/ianvs_pty/test';
