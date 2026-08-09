class LocalTerminalVerificationEvidence {
  const LocalTerminalVerificationEvidence({required this.items});

  factory LocalTerminalVerificationEvidence.defaultRequiredPending({
    List<String> notes = const [],
  }) {
    return LocalTerminalVerificationEvidence(
      items: [
        for (final gate in defaultRequiredGates)
          LocalTerminalVerificationEvidenceItem(
            gate: gate,
            status: LocalTerminalVerificationStatus.pending,
            required: true,
            notes: notes,
          ),
      ],
    );
  }

  static const List<LocalTerminalVerificationGate> defaultRequiredGates = [
    LocalTerminalVerificationGate.unitTests,
    LocalTerminalVerificationGate.widgetTests,
    LocalTerminalVerificationGate.integrationTests,
    LocalTerminalVerificationGate.manualLocalShellSmoke,
    LocalTerminalVerificationGate.manualPasteFocusSafety,
    LocalTerminalVerificationGate.manualMultipaneBehavior,
    LocalTerminalVerificationGate.manualNotificationBehavior,
    LocalTerminalVerificationGate.manualHotkeyWindowFailurePath,
    LocalTerminalVerificationGate.staticAnalysis,
    LocalTerminalVerificationGate.formatting,
  ];

  final List<LocalTerminalVerificationEvidenceItem> items;

  bool get canClose {
    return defaultRequiredGates.every(gatePassed) &&
        requiredItems.every((item) => item.status.isPassed);
  }

  List<LocalTerminalVerificationEvidenceItem> get requiredItems {
    return items.where((item) => item.required).toList(growable: false);
  }

  List<LocalTerminalVerificationEvidenceItem> get blockingItems {
    return requiredItems
        .where((item) => !item.status.isPassed)
        .toList(growable: false);
  }

  List<LocalTerminalVerificationGate> get missingRequiredGates {
    return defaultRequiredGates
        .where(
          (gate) => !items.any((item) => item.gate == gate && item.required),
        )
        .toList(growable: false);
  }

  int get verificationGateBlockerCount {
    return blockingItems.length + missingRequiredGates.length;
  }

  bool gatePassed(LocalTerminalVerificationGate gate) {
    final matchingRequiredItems = items
        .where((item) => item.gate == gate && item.required)
        .toList(growable: false);
    return matchingRequiredItems.isNotEmpty &&
        matchingRequiredItems.every((item) => item.status.isPassed);
  }

  Map<String, Object?> toJson() {
    return {
      'canClose': canClose,
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'blockingItems': blockingItems
          .map((item) => item.gate.name)
          .toList(growable: false),
      'missingRequiredGates': missingRequiredGates
          .map((gate) => gate.name)
          .toList(growable: false),
      'verificationGateBlockerCount': verificationGateBlockerCount,
    };
  }
}

class LocalTerminalVerificationEvidenceItem {
  const LocalTerminalVerificationEvidenceItem({
    required this.gate,
    required this.status,
    required this.required,
    this.command,
    this.evidence = const [],
    this.notes = const [],
  });

  final LocalTerminalVerificationGate gate;
  final LocalTerminalVerificationStatus status;
  final bool required;
  final String? command;
  final List<String> evidence;
  final List<String> notes;

  Map<String, Object?> toJson() {
    return {
      'gate': gate.name,
      'status': status.name,
      'required': required,
      'command': command,
      'evidence': evidence,
      'notes': notes,
    };
  }
}

enum LocalTerminalVerificationGate {
  unitTests,
  widgetTests,
  integrationTests,
  manualLocalShellSmoke,
  manualPasteFocusSafety,
  manualMultipaneBehavior,
  manualNotificationBehavior,
  manualHotkeyWindowFailurePath,
  staticAnalysis,
  formatting,
}

enum LocalTerminalVerificationStatus { pending, passed, failed, skipped }

extension LocalTerminalVerificationStatusX on LocalTerminalVerificationStatus {
  bool get isPassed {
    return this == LocalTerminalVerificationStatus.passed;
  }
}
