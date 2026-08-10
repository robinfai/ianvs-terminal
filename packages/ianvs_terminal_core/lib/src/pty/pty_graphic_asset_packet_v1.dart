import 'dart:typed_data';

import 'package:protobuf/protobuf.dart';

import 'proto/graphic_asset.pb.dart' as graphic_pb;

const int ptyGraphicAssetPacketSchemaVersion = 1;
const String ptyGraphicAssetPacketContract = 'ianvs-graphic-asset-packet-v1';
const int ptyGraphicAssetPacketMaxRgbaBytes = 100 * 1024 * 1024;
const int ptyGraphicAssetPacketMaxEncodedBytes =
    ptyGraphicAssetPacketMaxRgbaBytes + 4096;

enum PtyGraphicAssetPacketErrorCode {
  invalidProtobuf,
  unsupportedSchemaVersion,
  invalidEnvelope,
  identityMismatch,
  invalidPayload,
  capacityExceeded,
}

final class PtyGraphicAssetPacketFormatException implements FormatException {
  const PtyGraphicAssetPacketFormatException({
    required this.code,
    required this.message,
  });

  final PtyGraphicAssetPacketErrorCode code;

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() =>
      'PtyGraphicAssetPacketFormatException(${code.name}): $message';
}

final class PtyGraphicAssetPacketV1 {
  PtyGraphicAssetPacketV1._({
    required this.schemaVersion,
    required this.contract,
    required this.messageClass,
    required this.messageName,
    required this.sessionId,
    required this.assetId,
    required this.assetVersion,
    required this.width,
    required this.height,
    required Uint8List rgba,
  }) : rgba = rgba.asUnmodifiableView();

  factory PtyGraphicAssetPacketV1.decode(
    Uint8List bytes, {
    required String expectedSessionId,
    required int expectedAssetId,
    required int expectedAssetVersion,
  }) {
    if (bytes.isEmpty) {
      throw const PtyGraphicAssetPacketFormatException(
        code: PtyGraphicAssetPacketErrorCode.invalidProtobuf,
        message: 'Graphic Asset Packet v1 must not be empty',
      );
    }
    if (bytes.length > ptyGraphicAssetPacketMaxEncodedBytes) {
      throw const PtyGraphicAssetPacketFormatException(
        code: PtyGraphicAssetPacketErrorCode.capacityExceeded,
        message: 'Graphic Asset Packet v1 exceeds its encoded byte limit',
      );
    }

    final graphic_pb.GraphicAssetPacketV1 decoded;
    try {
      decoded = graphic_pb.GraphicAssetPacketV1.fromBuffer(bytes);
    } on InvalidProtocolBufferException {
      throw const PtyGraphicAssetPacketFormatException(
        code: PtyGraphicAssetPacketErrorCode.invalidProtobuf,
        message: 'Graphic Asset Packet v1 is not valid Protobuf',
      );
    }
    if (decoded.schemaVersion != ptyGraphicAssetPacketSchemaVersion) {
      throw PtyGraphicAssetPacketFormatException(
        code: PtyGraphicAssetPacketErrorCode.unsupportedSchemaVersion,
        message:
            'Unsupported Graphic Asset Packet schema '
            '${decoded.schemaVersion}',
      );
    }
    if (decoded.contract != ptyGraphicAssetPacketContract ||
        decoded.messageClass != 'asset_transfer' ||
        decoded.messageName != 'graphic_asset') {
      throw const PtyGraphicAssetPacketFormatException(
        code: PtyGraphicAssetPacketErrorCode.invalidEnvelope,
        message: 'Graphic Asset Packet v1 envelope identity is invalid',
      );
    }

    final sessionId = _positiveUint64(decoded.sessionId);
    final assetId = _positiveUint64(decoded.assetId);
    final assetVersion = _positiveUint64(decoded.assetVersion);
    final expectedSession = _positiveUint64(expectedSessionId);
    if (sessionId == null ||
        assetId == null ||
        assetVersion == null ||
        expectedSession == null ||
        expectedAssetId <= 0 ||
        expectedAssetVersion <= 0 ||
        sessionId != expectedSession ||
        assetId != BigInt.from(expectedAssetId) ||
        assetVersion != BigInt.from(expectedAssetVersion)) {
      throw const PtyGraphicAssetPacketFormatException(
        code: PtyGraphicAssetPacketErrorCode.identityMismatch,
        message: 'Graphic Asset Packet v1 identity does not match its request',
      );
    }

    final rgba = decoded.rgba;
    final expectedRgbaBytes = decoded.width * decoded.height * 4;
    if (decoded.width <= 0 || decoded.height <= 0) {
      throw const PtyGraphicAssetPacketFormatException(
        code: PtyGraphicAssetPacketErrorCode.invalidPayload,
        message: 'Graphic Asset Packet dimensions and RGBA length are invalid',
      );
    }
    if (expectedRgbaBytes > ptyGraphicAssetPacketMaxRgbaBytes) {
      throw const PtyGraphicAssetPacketFormatException(
        code: PtyGraphicAssetPacketErrorCode.capacityExceeded,
        message: 'Graphic Asset Packet RGBA exceeds its decoded byte limit',
      );
    }
    if (rgba.length != expectedRgbaBytes) {
      throw const PtyGraphicAssetPacketFormatException(
        code: PtyGraphicAssetPacketErrorCode.invalidPayload,
        message: 'Graphic Asset Packet dimensions and RGBA length are invalid',
      );
    }
    return PtyGraphicAssetPacketV1._(
      schemaVersion: decoded.schemaVersion,
      contract: decoded.contract,
      messageClass: decoded.messageClass,
      messageName: decoded.messageName,
      sessionId: sessionId.toString(),
      assetId: assetId.toInt(),
      assetVersion: assetVersion.toInt(),
      width: decoded.width,
      height: decoded.height,
      rgba: Uint8List.fromList(rgba),
    );
  }

  final int schemaVersion;
  final String contract;
  final String messageClass;
  final String messageName;
  final String sessionId;
  final int assetId;
  final int assetVersion;
  final int width;
  final int height;
  final Uint8List rgba;
}

final RegExp _positiveUint64Pattern = RegExp(r'^[1-9][0-9]*$');
final BigInt _maxUint64 = BigInt.parse('18446744073709551615');

BigInt? _positiveUint64(String value) {
  if (!_positiveUint64Pattern.hasMatch(value)) {
    return null;
  }
  final parsed = BigInt.parse(value);
  return parsed <= _maxUint64 ? parsed : null;
}
