import 'dart:typed_data';

/// Minimal output boundary used by terminal input handling.
///
/// Keeping this capability separate from the runtime controller prevents the
/// terminal widget/input layer from depending on session orchestration.
abstract interface class TerminalInputSink {
  void sendInput(String sessionId, Uint8List bytes);
}
