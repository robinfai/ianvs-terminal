import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/src/runtime/terminal_frame_decoder.dart';

import 'support/terminal_frame_wire_fixture.dart';

void main() {
  group(TerminalFrameDecoder, () {
    test('decode remains an exact JSON compatibility alias', () {
      final fixture = completeTerminalFrameWireFixture();
      const decoder = TerminalFrameDecoder();

      final legacy = decoder.decode(fixture.jsonString);
      final explicit = decoder.decodeJson(fixture.jsonString);

      expect(legacy, isNotNull);
      expect(explicit, isNotNull);
      expect(
        terminalFrameProjection(legacy!.frame),
        terminalFrameProjection(explicit!.frame),
      );
    });

    test('decodeJson and decodeProtobuf project a complete valid frame', () {
      final fixture = completeTerminalFrameWireFixture();
      const decoder = TerminalFrameDecoder();

      final json = decoder.decodeJson(fixture.jsonString);
      final protobuf = decoder.decodeProtobuf(fixture.protobufBytes);

      expect(json, isNotNull);
      expect(protobuf, isNotNull);
      expect(
        terminalFrameProjection(json!.frame),
        terminalFrameProjection(protobuf!.frame),
      );
    });

    test('returns null for malformed JSON and a JSON array', () {
      const decoder = TerminalFrameDecoder(collectMetrics: true);

      expect(decoder.decodeJson('{'), isNull);
      expect(
        decoder.decodeJson(jsonEncode(<Object?>['not', 'an', 'object'])),
        isNull,
      );
    });

    test('returns null for malformed protobuf', () {
      const decoder = TerminalFrameDecoder(collectMetrics: true);

      expect(
        decoder.decodeProtobuf(Uint8List.fromList(const <int>[0xff])),
        isNull,
      );
    });

    test('JSON metrics use UTF-8 bytes and only JSON decode time', () {
      final fixture = completeTerminalFrameWireFixture();
      const decoder = TerminalFrameDecoder(collectMetrics: true);

      final decoded = decoder.decodeJson(fixture.jsonString);

      expect(decoded, isNotNull);
      expect(decoded!.metrics, isNotNull);
      expect(decoded.metrics!.wireFormat, 'json');
      expect(
        decoded.metrics!.rawFrameBytes,
        utf8.encode(fixture.jsonString).length,
      );
      expect(decoded.metrics!.jsonDecodeMicros, greaterThanOrEqualTo(0));
      expect(decoded.metrics!.protobufDecodeMicros, 0);
    });

    test(
      'protobuf metrics use payload bytes and only protobuf decode time',
      () {
        final fixture = completeTerminalFrameWireFixture();
        const decoder = TerminalFrameDecoder(collectMetrics: true);

        final decoded = decoder.decodeProtobuf(fixture.protobufBytes);

        expect(decoded, isNotNull);
        expect(decoded!.metrics, isNotNull);
        expect(decoded.metrics!.wireFormat, 'protobuf');
        expect(decoded.metrics!.rawFrameBytes, fixture.protobufBytes.length);
        expect(decoded.metrics!.jsonDecodeMicros, 0);
        expect(decoded.metrics!.protobufDecodeMicros, greaterThanOrEqualTo(0));
      },
    );

    test('metrics are null for both formats when collection is disabled', () {
      final fixture = completeTerminalFrameWireFixture();
      const decoder = TerminalFrameDecoder();

      expect(decoder.decodeJson(fixture.jsonString)!.metrics, isNull);
      expect(decoder.decodeProtobuf(fixture.protobufBytes)!.metrics, isNull);
    });
  });
}
