enum TerminalWireFrameKind { snapshot, delta }

abstract final class TerminalWireCompatibility {
  static const String currentFrameSchemaVersion = 'terminal-frame-diff-v1';

  static String frameSchemaVersion(Object? value) {
    if (value is! String) {
      return currentFrameSchemaVersion;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? currentFrameSchemaVersion : trimmed;
  }

  static TerminalWireFrameKind frameKindFromJson(Object? value) {
    if (value is String && value.trim().toLowerCase() == 'delta') {
      return TerminalWireFrameKind.delta;
    }
    return TerminalWireFrameKind.snapshot;
  }

  static TerminalWireFrameKind frameKindFromProtobuf(int value) {
    return value == 2
        ? TerminalWireFrameKind.delta
        : TerminalWireFrameKind.snapshot;
  }
}
