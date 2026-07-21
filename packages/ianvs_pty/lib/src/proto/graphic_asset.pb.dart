// This is a generated file - do not edit.
//
// Generated from graphic_asset.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

class GraphicAssetPacketV1 extends $pb.GeneratedMessage {
  factory GraphicAssetPacketV1({
    $core.int? schemaVersion,
    $core.String? contract,
    $core.String? messageClass,
    $core.String? messageName,
    $core.String? sessionId,
    $core.String? assetId,
    $core.String? assetVersion,
    $core.int? width,
    $core.int? height,
    $core.List<$core.int>? rgba,
  }) {
    final result = create();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (contract != null) result.contract = contract;
    if (messageClass != null) result.messageClass = messageClass;
    if (messageName != null) result.messageName = messageName;
    if (sessionId != null) result.sessionId = sessionId;
    if (assetId != null) result.assetId = assetId;
    if (assetVersion != null) result.assetVersion = assetVersion;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (rgba != null) result.rgba = rgba;
    return result;
  }

  GraphicAssetPacketV1._();

  factory GraphicAssetPacketV1.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GraphicAssetPacketV1.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GraphicAssetPacketV1',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'graphic_asset'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'contract')
    ..aOS(3, _omitFieldNames ? '' : 'messageClass')
    ..aOS(4, _omitFieldNames ? '' : 'messageName')
    ..aOS(5, _omitFieldNames ? '' : 'sessionId')
    ..aOS(6, _omitFieldNames ? '' : 'assetId')
    ..aOS(7, _omitFieldNames ? '' : 'assetVersion')
    ..aI(8, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(9, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        10, _omitFieldNames ? '' : 'rgba', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GraphicAssetPacketV1 clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GraphicAssetPacketV1 copyWith(void Function(GraphicAssetPacketV1) updates) =>
      super.copyWith((message) => updates(message as GraphicAssetPacketV1))
          as GraphicAssetPacketV1;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GraphicAssetPacketV1 create() => GraphicAssetPacketV1._();
  @$core.override
  GraphicAssetPacketV1 createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GraphicAssetPacketV1 getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GraphicAssetPacketV1>(create);
  static GraphicAssetPacketV1? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get contract => $_getSZ(1);
  @$pb.TagNumber(2)
  set contract($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasContract() => $_has(1);
  @$pb.TagNumber(2)
  void clearContract() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get messageClass => $_getSZ(2);
  @$pb.TagNumber(3)
  set messageClass($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMessageClass() => $_has(2);
  @$pb.TagNumber(3)
  void clearMessageClass() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get messageName => $_getSZ(3);
  @$pb.TagNumber(4)
  set messageName($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMessageName() => $_has(3);
  @$pb.TagNumber(4)
  void clearMessageName() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get sessionId => $_getSZ(4);
  @$pb.TagNumber(5)
  set sessionId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSessionId() => $_has(4);
  @$pb.TagNumber(5)
  void clearSessionId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get assetId => $_getSZ(5);
  @$pb.TagNumber(6)
  set assetId($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAssetId() => $_has(5);
  @$pb.TagNumber(6)
  void clearAssetId() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get assetVersion => $_getSZ(6);
  @$pb.TagNumber(7)
  set assetVersion($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasAssetVersion() => $_has(6);
  @$pb.TagNumber(7)
  void clearAssetVersion() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get width => $_getIZ(7);
  @$pb.TagNumber(8)
  set width($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasWidth() => $_has(7);
  @$pb.TagNumber(8)
  void clearWidth() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get height => $_getIZ(8);
  @$pb.TagNumber(9)
  set height($core.int value) => $_setUnsignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasHeight() => $_has(8);
  @$pb.TagNumber(9)
  void clearHeight() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.List<$core.int> get rgba => $_getN(9);
  @$pb.TagNumber(10)
  set rgba($core.List<$core.int> value) => $_setBytes(9, value);
  @$pb.TagNumber(10)
  $core.bool hasRgba() => $_has(9);
  @$pb.TagNumber(10)
  void clearRgba() => $_clearField(10);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
