import 'local_terminal_real_wiring_backlog_evidence.dart';
import 'local_terminal_verification_evidence.dart';

class LocalTerminalVerificationEvidenceRecorder {
  const LocalTerminalVerificationEvidenceRecorder({required this.evidence});

  factory LocalTerminalVerificationEvidenceRecorder.pending({
    List<String> notes = const [],
  }) {
    return LocalTerminalVerificationEvidenceRecorder(
      evidence: LocalTerminalVerificationEvidence.defaultRequiredPending(
        notes: notes,
      ),
    );
  }

  final LocalTerminalVerificationEvidence evidence;

  LocalTerminalVerificationEvidenceRecorder record({
    required LocalTerminalVerificationGate gate,
    required LocalTerminalVerificationStatus status,
    bool required = true,
    String? command,
    List<String> output = const [],
    List<String> notes = const [],
  }) {
    final replacement = LocalTerminalVerificationEvidenceItem(
      gate: gate,
      status: status,
      required: required,
      command: command,
      evidence: output,
      notes: notes,
    );
    var replaced = false;
    final items = <LocalTerminalVerificationEvidenceItem>[
      for (final item in evidence.items)
        if (item.gate == gate && item.required == required)
          replacement
        else
          item,
    ];

    replaced = evidence.items.any(
      (item) => item.gate == gate && item.required == required,
    );
    if (!replaced) {
      items.add(replacement);
    }

    return LocalTerminalVerificationEvidenceRecorder(
      evidence: LocalTerminalVerificationEvidence(items: items),
    );
  }

  LocalTerminalVerificationEvidenceRecorder recordAll(
    Iterable<LocalTerminalVerificationGateRecord> records,
  ) {
    var recorder = this;
    for (final record in records) {
      recorder = recorder.record(
        gate: record.gate,
        status: record.status,
        required: record.required,
        command: record.command,
        output: record.output,
        notes: record.notes,
      );
    }
    return recorder;
  }

  LocalTerminalVerificationEvidenceRecorder recordPassed({
    required LocalTerminalVerificationGate gate,
    String? command,
    List<String> output = const [],
    List<String> notes = const [],
  }) {
    return record(
      gate: gate,
      status: LocalTerminalVerificationStatus.passed,
      command: command,
      output: output,
      notes: notes,
    );
  }

  LocalTerminalVerificationEvidenceRecorder recordFailed({
    required LocalTerminalVerificationGate gate,
    String? command,
    List<String> output = const [],
    List<String> notes = const [],
  }) {
    return record(
      gate: gate,
      status: LocalTerminalVerificationStatus.failed,
      command: command,
      output: output,
      notes: notes,
    );
  }

  LocalTerminalRealWiringTaskEvidence toBacklogEvidence() {
    return LocalTerminalRealWiringTaskEvidence.fromVerificationEvidence(
      evidence,
    );
  }
}

class LocalTerminalVerificationGateRecord {
  const LocalTerminalVerificationGateRecord({
    required this.gate,
    required this.status,
    this.required = true,
    this.command,
    this.output = const [],
    this.notes = const [],
  });

  const LocalTerminalVerificationGateRecord.passed({
    required this.gate,
    this.required = true,
    this.command,
    this.output = const [],
    this.notes = const [],
  }) : status = LocalTerminalVerificationStatus.passed;

  const LocalTerminalVerificationGateRecord.failed({
    required this.gate,
    this.required = true,
    this.command,
    this.output = const [],
    this.notes = const [],
  }) : status = LocalTerminalVerificationStatus.failed;

  final LocalTerminalVerificationGate gate;
  final LocalTerminalVerificationStatus status;
  final bool required;
  final String? command;
  final List<String> output;
  final List<String> notes;
}
