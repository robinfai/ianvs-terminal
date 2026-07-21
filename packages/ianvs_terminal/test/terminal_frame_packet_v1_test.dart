import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fixnum/fixnum.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/src/proto/frame_diff.pb.dart' as frame_pb;
import 'package:ianvs_terminal/src/runtime/terminal_frame_decoder.dart';
import 'package:ianvs_terminal/src/runtime/terminal_frame_packet_v1.dart';
import 'package:ianvs_terminal/src/runtime/terminal_frame_transport_coordinator.dart';

import 'support/terminal_frame_wire_fixture.dart';

void main() {
  group(TerminalFramePacketV1Decoder, () {
    test(
      'decodes exact identity and the unchanged nested Frame projection',
      () {
        final frame = _snapshotFrame();
        final bytes = _packetBytes(sessionId: '7', sequence: 0, frame: frame);

        final packet = const TerminalFramePacketV1Decoder().decode(
          bytes,
          expectedSessionId: '7',
          afterSequence: null,
        );

        expect(packet.sessionId, '7');
        expect(packet.sequence, 0);
        expect(packet.timestampMicros, 123);
        expect(packet.frameSchemaVersion, 'terminal-frame-diff-v1');
        expect(
          terminalFrameProjection(packet.frame),
          terminalFrameProjection(
            TerminalFrameDecoder()
                .decodeProtobuf(Uint8List.fromList(frame.writeToBuffer()))!
                .frame,
          ),
        );
      },
    );

    test('rejects cross-session data and a gapped Delta', () {
      final delta = completeTerminalFrameWireFixture().protobuf.deepCopy()
        ..frameKind = frame_pb.TerminalFrameKind.TERMINAL_FRAME_KIND_DELTA;
      final decoder = const TerminalFramePacketV1Decoder();

      expect(
        () => decoder.decode(
          _packetBytes(sessionId: '8', sequence: 1, frame: delta),
          expectedSessionId: '7',
          afterSequence: 0,
        ),
        throwsA(
          isA<TerminalFramePacketContractException>().having(
            (error) => error.code,
            'code',
            'frame_packet_session_mismatch',
          ),
        ),
      );
      expect(
        () => decoder.decode(
          _packetBytes(sessionId: '7', sequence: 2, frame: delta),
          expectedSessionId: '7',
          afterSequence: 0,
        ),
        throwsA(
          isA<TerminalFramePacketContractException>().having(
            (error) => error.code,
            'code',
            'frame_packet_sequence_gap',
          ),
        ),
      );
    });

    test('accepts a forward Snapshot as an explicit resynchronization', () {
      final packet = const TerminalFramePacketV1Decoder().decode(
        _packetBytes(sessionId: '7', sequence: 4, frame: _snapshotFrame()),
        expectedSessionId: '7',
        afterSequence: 1,
      );

      expect(packet.sequence, 4);
      expect(packet.frame.frameKind.name, 'snapshot');
    });
  });

  group(TerminalFrameTransportCoordinator, () {
    test(
      'automatic prefers packets and acknowledges only accepted sequence',
      () {
        final backend = _PacketBackend()
          ..packets.add(
            _packetBytes(sessionId: '7', sequence: 0, frame: _snapshotFrame()),
          )
          ..packets.add(Uint8List.fromList(const <int>[0xff]))
          ..packets.add(
            _packetBytes(sessionId: '7', sequence: 1, frame: _snapshotFrame()),
          );
        final errors = <Object>[];
        final coordinator = TerminalFrameTransportCoordinator(
          backend: backend,
          decoder: const TerminalFrameDecoder(),
          preference: TerminalFrameWireFormatPreference.automatic,
          onRequestError: (_, _, error, _) => errors.add(error),
        );

        expect(coordinator.take('7'), isNotNull);
        expect(coordinator.take('7'), isNull);
        expect(coordinator.take('7'), isNotNull);
        coordinator.removeSession('7');
        backend.packets.add(
          _packetBytes(sessionId: '7', sequence: 0, frame: _snapshotFrame()),
        );
        expect(coordinator.take('7'), isNotNull);

        expect(backend.afterSequences, <int?>[null, 0, 0, null]);
        expect(backend.legacyProtobufCalls, 0);
        expect(backend.jsonCalls, 0);
        expect(errors, hasLength(1));
      },
    );

    test('explicit JSON never probes the packet capability', () {
      final backend = _PacketBackend();
      final coordinator = TerminalFrameTransportCoordinator(
        backend: backend,
        decoder: const TerminalFrameDecoder(),
        preference: TerminalFrameWireFormatPreference.json,
      );

      coordinator.take('7');

      expect(backend.afterSequences, isEmpty);
      expect(backend.jsonCalls, 1);
    });
  });
}

Uint8List _packetBytes({
  required String sessionId,
  required int sequence,
  required frame_pb.TerminalFrameDiff frame,
}) {
  final packet = frame_pb.TerminalFramePacketV1(
    schemaVersion: 1,
    contract: 'ianvs-terminal-frame-packet-v1',
    messageClass: 'frame',
    messageName: 'frame_diff',
    sessionId: sessionId,
    sequence: Int64(sequence),
    timestampMicros: Int64(123),
    frameSchemaVersion: 'terminal-frame-diff-v1',
    frame: frame,
  );
  return Uint8List.fromList(packet.writeToBuffer());
}

frame_pb.TerminalFrameDiff _snapshotFrame() {
  return completeTerminalFrameWireFixture().protobuf.deepCopy()
    ..frameKind = frame_pb.TerminalFrameKind.TERMINAL_FRAME_KIND_SNAPSHOT;
}

final class _PacketBackend
    implements
        PtySessionBackend,
        PtySessionFramePacketV1Backend,
        PtySessionProtobufFrameBackend {
  final List<Uint8List?> packets = <Uint8List?>[];
  final List<int?> afterSequences = <int?>[];
  int legacyProtobufCalls = 0;
  int jsonCalls = 0;

  @override
  bool get supportsFramePacketV1 => true;

  @override
  Uint8List? takeFramePacketV1Protobuf(
    String sessionId, {
    required int? afterSequence,
  }) {
    afterSequences.add(afterSequence);
    return packets.isEmpty ? null : packets.removeAt(0);
  }

  @override
  bool get supportsProtobufFrameDiffs => true;

  @override
  Uint8List? takeFrameDiffProtobuf(String sessionId) {
    legacyProtobufCalls += 1;
    return null;
  }

  @override
  String? takeFrameDiffJson(String sessionId) {
    jsonCalls += 1;
    return null;
  }

  @override
  int ping() => 42;

  @override
  String createSession(String sessionConfigJson) => '7';

  @override
  void closeSession(String sessionId) {}

  @override
  List<PtyEvent> pollEvents(String sessionId) => const <PtyEvent>[];

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
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {}

  @override
  void writeInput(String sessionId, List<int> bytes) {}
}
