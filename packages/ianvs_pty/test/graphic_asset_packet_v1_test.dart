import 'dart:convert';
import 'dart:typed_data';

import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:test/test.dart';

void main() {
  group('PtyGraphicAssetPacketV1', () {
    test('decodes exact identity and ignores additive protobuf fields', () {
      final bytes = _packet(
        sessionId: '9',
        assetId: 42,
        assetVersion: 3,
        width: 1,
        height: 1,
        rgba: <int>[255, 0, 0, 255],
        additiveUnknownField: true,
      );

      final packet = PtyGraphicAssetPacketV1.decode(
        bytes,
        expectedSessionId: '9',
        expectedAssetId: 42,
        expectedAssetVersion: 3,
      );

      expect(packet.schemaVersion, 1);
      expect(packet.contract, 'ianvs-graphic-asset-packet-v1');
      expect(packet.messageClass, 'asset_transfer');
      expect(packet.messageName, 'graphic_asset');
      expect(packet.sessionId, '9');
      expect(packet.assetId, 42);
      expect(packet.assetVersion, 3);
      expect(packet.width, 1);
      expect(packet.height, 1);
      expect(packet.rgba, <int>[255, 0, 0, 255]);
      expect(() => packet.rgba[0] = 0, throwsUnsupportedError);
    });

    test('rejects malformed envelopes identity drift and RGBA drift', () {
      expect(
        () => PtyGraphicAssetPacketV1.decode(
          Uint8List.fromList(const <int>[0x0a]),
          expectedSessionId: '9',
          expectedAssetId: 42,
          expectedAssetVersion: 3,
        ),
        _throwsCode(PtyGraphicAssetPacketErrorCode.invalidProtobuf),
      );

      final valid = _packet(
        sessionId: '9',
        assetId: 42,
        assetVersion: 3,
        width: 1,
        height: 1,
        rgba: <int>[255, 0, 0, 255],
      );
      expect(
        () => PtyGraphicAssetPacketV1.decode(
          valid,
          expectedSessionId: '10',
          expectedAssetId: 42,
          expectedAssetVersion: 3,
        ),
        _throwsCode(PtyGraphicAssetPacketErrorCode.identityMismatch),
      );

      final sizeDrift = _packet(
        sessionId: '9',
        assetId: 42,
        assetVersion: 3,
        width: 2,
        height: 1,
        rgba: <int>[255, 0, 0, 255],
      );
      expect(
        () => PtyGraphicAssetPacketV1.decode(
          sizeDrift,
          expectedSessionId: '9',
          expectedAssetId: 42,
          expectedAssetVersion: 3,
        ),
        _throwsCode(PtyGraphicAssetPacketErrorCode.invalidPayload),
      );
    });

    test('rejects unsupported schema envelope drift and declared capacity', () {
      expect(
        () => PtyGraphicAssetPacketV1.decode(
          _packet(
            sessionId: '9',
            assetId: 42,
            assetVersion: 3,
            width: 1,
            height: 1,
            rgba: <int>[255, 0, 0, 255],
            schemaVersion: 2,
          ),
          expectedSessionId: '9',
          expectedAssetId: 42,
          expectedAssetVersion: 3,
        ),
        _throwsCode(PtyGraphicAssetPacketErrorCode.unsupportedSchemaVersion),
      );
      expect(
        () => PtyGraphicAssetPacketV1.decode(
          _packet(
            sessionId: '9',
            assetId: 42,
            assetVersion: 3,
            width: 1,
            height: 1,
            rgba: <int>[255, 0, 0, 255],
            messageName: 'graphic_asset_v2',
          ),
          expectedSessionId: '9',
          expectedAssetId: 42,
          expectedAssetVersion: 3,
        ),
        _throwsCode(PtyGraphicAssetPacketErrorCode.invalidEnvelope),
      );
      expect(
        () => PtyGraphicAssetPacketV1.decode(
          _packet(
            sessionId: '9',
            assetId: 42,
            assetVersion: 3,
            width: 25 * 1024 * 1024 + 1,
            height: 1,
            rgba: const <int>[],
          ),
          expectedSessionId: '9',
          expectedAssetId: 42,
          expectedAssetVersion: 3,
        ),
        _throwsCode(PtyGraphicAssetPacketErrorCode.capacityExceeded),
      );
    });
  });
}

Matcher _throwsCode(PtyGraphicAssetPacketErrorCode code) => throwsA(
  isA<PtyGraphicAssetPacketFormatException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

Uint8List _packet({
  required String sessionId,
  required int assetId,
  required int assetVersion,
  required int width,
  required int height,
  required List<int> rgba,
  int schemaVersion = 1,
  String messageName = 'graphic_asset',
  bool additiveUnknownField = false,
}) {
  final bytes = <int>[
    ..._varintField(1, schemaVersion),
    ..._bytesField(2, utf8.encode('ianvs-graphic-asset-packet-v1')),
    ..._bytesField(3, utf8.encode('asset_transfer')),
    ..._bytesField(4, utf8.encode(messageName)),
    ..._bytesField(5, utf8.encode(sessionId)),
    ..._bytesField(6, utf8.encode('$assetId')),
    ..._bytesField(7, utf8.encode('$assetVersion')),
    ..._varintField(8, width),
    ..._varintField(9, height),
    ..._bytesField(10, rgba),
    if (additiveUnknownField) ..._varintField(99, 1),
  ];
  return Uint8List.fromList(bytes);
}

List<int> _varintField(int fieldNumber, int value) => <int>[
  ..._varint(fieldNumber << 3),
  ..._varint(value),
];

List<int> _bytesField(int fieldNumber, List<int> value) => <int>[
  ..._varint((fieldNumber << 3) | 2),
  ..._varint(value.length),
  ...value,
];

List<int> _varint(int value) {
  final bytes = <int>[];
  var remaining = value;
  do {
    var byte = remaining & 0x7f;
    remaining >>= 7;
    if (remaining != 0) {
      byte |= 0x80;
    }
    bytes.add(byte);
  } while (remaining != 0);
  return bytes;
}
