import '../terminal/terminal_models.dart';

final class TerminalDecodedFrame {
  const TerminalDecodedFrame({required this.frame, required this.metrics});

  final TerminalFrameDiff frame;
  final TerminalFrameDecodeMetrics? metrics;
}

final class TerminalFrameDecodeMetrics {
  const TerminalFrameDecodeMetrics({
    required this.rawFrameBytes,
    required this.jsonDecodeMicros,
    this.wireFormat = 'frame-packet.protobuf.v1',
    this.protobufDecodeMicros = 0,
    this.nativeFrameStats = const <String, Object?>{},
  });

  final int rawFrameBytes;
  final String wireFormat;
  final int jsonDecodeMicros;
  final int protobufDecodeMicros;
  final Map<String, Object?> nativeFrameStats;
}
