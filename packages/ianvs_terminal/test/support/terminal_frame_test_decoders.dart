import 'package:ianvs_terminal/src/runtime/terminal_frame_decoder.dart';
import 'package:ianvs_terminal/src/runtime/terminal_frame_packet_v1.dart';
import 'package:ianvs_terminal/src/transport/terminal_json_frame_decoder.dart';
import 'package:ianvs_terminal/src/transport/terminal_protobuf_frame_codec.dart';
import 'package:ianvs_terminal/src/transport/terminal_protobuf_frame_decoder.dart';
import 'package:ianvs_terminal/src/transport/terminal_protobuf_frame_packet_codec.dart';

TerminalFrameDecoder terminalFrameTestDecoder({bool collectMetrics = false}) {
  return TerminalFrameDecoder(
    collectMetrics: collectMetrics,
    jsonDecoder: const TerminalJsonFrameDecoder(),
    protobufDecoder: const TerminalProtobufFrameDecoder(),
  );
}

TerminalFramePacketV1Decoder terminalFramePacketTestDecoder() {
  return const TerminalFramePacketV1Decoder(
    frameCodec: TerminalProtobufFrameCodec(),
    packetCodec: TerminalProtobufFramePacketCodec(),
  );
}
