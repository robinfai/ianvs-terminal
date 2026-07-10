import 'dart:convert';
import 'dart:typed_data';

import '../terminal/terminal_models.dart';
import '../transport/terminal_json_frame_decoder.dart';
import '../transport/terminal_protobuf_frame_decoder.dart';

final class TerminalDecodedFrame {
  const TerminalDecodedFrame({required this.frame, required this.metrics});

  final TerminalFrameDiff frame;
  final TerminalFrameDecodeMetrics? metrics;
}

final class TerminalFrameDecodeMetrics {
  const TerminalFrameDecodeMetrics({
    required this.rawFrameBytes,
    required this.jsonDecodeMicros,
    this.wireFormat = 'json',
    this.protobufDecodeMicros = 0,
    this.nativeFrameStats = const <String, Object?>{},
  });

  final int rawFrameBytes;
  final String wireFormat;
  final int jsonDecodeMicros;
  final int protobufDecodeMicros;
  final Map<String, Object?> nativeFrameStats;
}

final class TerminalFrameDecoder {
  const TerminalFrameDecoder({
    this.collectMetrics = false,
    this.jsonDecoder = const TerminalJsonFrameDecoder(),
    this.protobufDecoder = const TerminalProtobufFrameDecoder(),
  });

  final bool collectMetrics;
  final TerminalJsonFrameDecoder jsonDecoder;
  final TerminalProtobufFrameDecoder protobufDecoder;

  TerminalDecodedFrame? decode(String rawFrame) => decodeJson(rawFrame);

  TerminalDecodedFrame? decodeJson(String rawFrame) {
    final decodeWatch = collectMetrics ? (Stopwatch()..start()) : null;
    final frame = jsonDecoder.decode(rawFrame);
    if (frame == null) {
      return null;
    }
    decodeWatch?.stop();
    return TerminalDecodedFrame(
      frame: frame,
      metrics: collectMetrics
          ? TerminalFrameDecodeMetrics(
              rawFrameBytes: utf8.encode(rawFrame).length,
              jsonDecodeMicros: decodeWatch?.elapsedMicroseconds ?? 0,
            )
          : null,
    );
  }

  TerminalDecodedFrame? decodeProtobuf(Uint8List rawFrame) {
    final decodeWatch = collectMetrics ? (Stopwatch()..start()) : null;
    final frame = protobufDecoder.decode(rawFrame);
    if (frame == null) {
      return null;
    }
    decodeWatch?.stop();
    return TerminalDecodedFrame(
      frame: frame,
      metrics: collectMetrics
          ? TerminalFrameDecodeMetrics(
              rawFrameBytes: rawFrame.length,
              wireFormat: 'protobuf',
              jsonDecodeMicros: 0,
              protobufDecodeMicros: decodeWatch?.elapsedMicroseconds ?? 0,
            )
          : null,
    );
  }
}
