import 'dart:typed_data';

import 'package:ianvs_pty/ianvs_pty.dart';

export 'package:ianvs_pty/ianvs_pty.dart'
    show
        NativePtyBackend,
        PtyBindings,
        PtyEvent,
        PtySessionBackend,
        PtySessionConfigV1Backend,
        PtySessionFramePacketV1Backend,
        PtySessionRequestV1Backend;

export 'ios_sandbox_shell_backend.dart' show IosSandboxShellBackend;

PtySessionBackend loadDefaultPtySessionBackend() {
  return NativePtyBackend.load(emitRuntimeEventGapDiagnostics: true);
}

/// A deliberately inert backend used by the iOS reference experience.
///
/// iOS applications cannot spawn an unrestricted local shell. Keeping this
/// backend in Dart lets the terminal viewport retain selection, scrolling, and
/// keyboard plumbing without loading the macOS native PTY library.
class ReferenceDemoPtySessionBackend
    implements PtySessionBackend, PtySessionFramePacketV1Backend {
  @override
  int ping() => 1;

  @override
  void closeSession(String sessionId) {}

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  }) {}

  @override
  void writeInput(String sessionId, List<int> bytes) {}

  @override
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {}

  @override
  Uint8List? takeFramePacketV1Protobuf(
    String sessionId, {
    required int? afterSequence,
  }) => null;

  @override
  List<PtyEvent> pollEvents(String sessionId) => const <PtyEvent>[];
}
