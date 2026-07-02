// This is a generated file - do not edit.
//
// Generated from frame_diff.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class TerminalFrameKind extends $pb.ProtobufEnum {
  static const TerminalFrameKind TERMINAL_FRAME_KIND_UNSPECIFIED =
      TerminalFrameKind._(
          0, _omitEnumNames ? '' : 'TERMINAL_FRAME_KIND_UNSPECIFIED');
  static const TerminalFrameKind TERMINAL_FRAME_KIND_SNAPSHOT =
      TerminalFrameKind._(
          1, _omitEnumNames ? '' : 'TERMINAL_FRAME_KIND_SNAPSHOT');
  static const TerminalFrameKind TERMINAL_FRAME_KIND_DELTA =
      TerminalFrameKind._(2, _omitEnumNames ? '' : 'TERMINAL_FRAME_KIND_DELTA');

  static const $core.List<TerminalFrameKind> values = <TerminalFrameKind>[
    TERMINAL_FRAME_KIND_UNSPECIFIED,
    TERMINAL_FRAME_KIND_SNAPSHOT,
    TERMINAL_FRAME_KIND_DELTA,
  ];

  static final $core.List<TerminalFrameKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static TerminalFrameKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const TerminalFrameKind._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
