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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'frame_diff.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'frame_diff.pbenum.dart';

class TerminalFrameDiff extends $pb.GeneratedMessage {
  factory TerminalFrameDiff({
    $core.String? frameSchemaVersion,
    TerminalFrameKind? frameKind,
    $core.Iterable<TerminalRow>? rows,
    TerminalCursor? cursor,
    TerminalSelection? selection,
    $core.int? viewportRows,
    $core.int? viewportCols,
    $core.Iterable<TerminalDirtyRange>? dirtyRanges,
    $core.int? scrollbackOffset,
    $core.int? scrollbackMaxOffset,
    $core.int? viewportStartRow,
    $core.int? viewportRowShift,
    ColorRgb? defaultForeground,
    ColorRgb? defaultBackground,
    ColorRgb? cursorColor,
    TerminalFrameModes? modes,
    $core.String? windowTitle,
    $core.String? windowIconName,
    $core.Iterable<TerminalHyperlinkRange>? hyperlinks,
    $core.Iterable<TerminalInlineImage>? inlineImages,
    $core.Iterable<TerminalGraphicPlacement>? graphics,
    $fixnum.Int64? globalBottomRow,
    $core.String? pointerShape,
    $core.Iterable<TerminalSizedTextPlacement>? sizedText,
  }) {
    final result = create();
    if (frameSchemaVersion != null)
      result.frameSchemaVersion = frameSchemaVersion;
    if (frameKind != null) result.frameKind = frameKind;
    if (rows != null) result.rows.addAll(rows);
    if (cursor != null) result.cursor = cursor;
    if (selection != null) result.selection = selection;
    if (viewportRows != null) result.viewportRows = viewportRows;
    if (viewportCols != null) result.viewportCols = viewportCols;
    if (dirtyRanges != null) result.dirtyRanges.addAll(dirtyRanges);
    if (scrollbackOffset != null) result.scrollbackOffset = scrollbackOffset;
    if (scrollbackMaxOffset != null)
      result.scrollbackMaxOffset = scrollbackMaxOffset;
    if (viewportStartRow != null) result.viewportStartRow = viewportStartRow;
    if (viewportRowShift != null) result.viewportRowShift = viewportRowShift;
    if (defaultForeground != null) result.defaultForeground = defaultForeground;
    if (defaultBackground != null) result.defaultBackground = defaultBackground;
    if (cursorColor != null) result.cursorColor = cursorColor;
    if (modes != null) result.modes = modes;
    if (windowTitle != null) result.windowTitle = windowTitle;
    if (windowIconName != null) result.windowIconName = windowIconName;
    if (hyperlinks != null) result.hyperlinks.addAll(hyperlinks);
    if (inlineImages != null) result.inlineImages.addAll(inlineImages);
    if (graphics != null) result.graphics.addAll(graphics);
    if (globalBottomRow != null) result.globalBottomRow = globalBottomRow;
    if (pointerShape != null) result.pointerShape = pointerShape;
    if (sizedText != null) result.sizedText.addAll(sizedText);
    return result;
  }

  TerminalFrameDiff._();

  factory TerminalFrameDiff.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TerminalFrameDiff.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TerminalFrameDiff',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'frame_diff'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'frameSchemaVersion')
    ..aE<TerminalFrameKind>(2, _omitFieldNames ? '' : 'frameKind',
        enumValues: TerminalFrameKind.values)
    ..pPM<TerminalRow>(3, _omitFieldNames ? '' : 'rows',
        subBuilder: TerminalRow.create)
    ..aOM<TerminalCursor>(4, _omitFieldNames ? '' : 'cursor',
        subBuilder: TerminalCursor.create)
    ..aOM<TerminalSelection>(5, _omitFieldNames ? '' : 'selection',
        subBuilder: TerminalSelection.create)
    ..aI(6, _omitFieldNames ? '' : 'viewportRows',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'viewportCols',
        fieldType: $pb.PbFieldType.OU3)
    ..pPM<TerminalDirtyRange>(8, _omitFieldNames ? '' : 'dirtyRanges',
        subBuilder: TerminalDirtyRange.create)
    ..aI(9, _omitFieldNames ? '' : 'scrollbackOffset',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(10, _omitFieldNames ? '' : 'scrollbackMaxOffset',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(11, _omitFieldNames ? '' : 'viewportStartRow',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(12, _omitFieldNames ? '' : 'viewportRowShift')
    ..aOM<ColorRgb>(13, _omitFieldNames ? '' : 'defaultForeground',
        subBuilder: ColorRgb.create)
    ..aOM<ColorRgb>(14, _omitFieldNames ? '' : 'defaultBackground',
        subBuilder: ColorRgb.create)
    ..aOM<ColorRgb>(15, _omitFieldNames ? '' : 'cursorColor',
        subBuilder: ColorRgb.create)
    ..aOM<TerminalFrameModes>(16, _omitFieldNames ? '' : 'modes',
        subBuilder: TerminalFrameModes.create)
    ..aOS(17, _omitFieldNames ? '' : 'windowTitle')
    ..aOS(18, _omitFieldNames ? '' : 'windowIconName')
    ..pPM<TerminalHyperlinkRange>(19, _omitFieldNames ? '' : 'hyperlinks',
        subBuilder: TerminalHyperlinkRange.create)
    ..pPM<TerminalInlineImage>(20, _omitFieldNames ? '' : 'inlineImages',
        subBuilder: TerminalInlineImage.create)
    ..pPM<TerminalGraphicPlacement>(21, _omitFieldNames ? '' : 'graphics',
        subBuilder: TerminalGraphicPlacement.create)
    ..a<$fixnum.Int64>(
        22, _omitFieldNames ? '' : 'globalBottomRow', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(23, _omitFieldNames ? '' : 'pointerShape')
    ..pPM<TerminalSizedTextPlacement>(24, _omitFieldNames ? '' : 'sizedText',
        subBuilder: TerminalSizedTextPlacement.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalFrameDiff clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalFrameDiff copyWith(void Function(TerminalFrameDiff) updates) =>
      super.copyWith((message) => updates(message as TerminalFrameDiff))
          as TerminalFrameDiff;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TerminalFrameDiff create() => TerminalFrameDiff._();
  @$core.override
  TerminalFrameDiff createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TerminalFrameDiff getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TerminalFrameDiff>(create);
  static TerminalFrameDiff? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get frameSchemaVersion => $_getSZ(0);
  @$pb.TagNumber(1)
  set frameSchemaVersion($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFrameSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearFrameSchemaVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  TerminalFrameKind get frameKind => $_getN(1);
  @$pb.TagNumber(2)
  set frameKind(TerminalFrameKind value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasFrameKind() => $_has(1);
  @$pb.TagNumber(2)
  void clearFrameKind() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<TerminalRow> get rows => $_getList(2);

  @$pb.TagNumber(4)
  TerminalCursor get cursor => $_getN(3);
  @$pb.TagNumber(4)
  set cursor(TerminalCursor value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasCursor() => $_has(3);
  @$pb.TagNumber(4)
  void clearCursor() => $_clearField(4);
  @$pb.TagNumber(4)
  TerminalCursor ensureCursor() => $_ensure(3);

  @$pb.TagNumber(5)
  TerminalSelection get selection => $_getN(4);
  @$pb.TagNumber(5)
  set selection(TerminalSelection value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasSelection() => $_has(4);
  @$pb.TagNumber(5)
  void clearSelection() => $_clearField(5);
  @$pb.TagNumber(5)
  TerminalSelection ensureSelection() => $_ensure(4);

  @$pb.TagNumber(6)
  $core.int get viewportRows => $_getIZ(5);
  @$pb.TagNumber(6)
  set viewportRows($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasViewportRows() => $_has(5);
  @$pb.TagNumber(6)
  void clearViewportRows() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get viewportCols => $_getIZ(6);
  @$pb.TagNumber(7)
  set viewportCols($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasViewportCols() => $_has(6);
  @$pb.TagNumber(7)
  void clearViewportCols() => $_clearField(7);

  @$pb.TagNumber(8)
  $pb.PbList<TerminalDirtyRange> get dirtyRanges => $_getList(7);

  @$pb.TagNumber(9)
  $core.int get scrollbackOffset => $_getIZ(8);
  @$pb.TagNumber(9)
  set scrollbackOffset($core.int value) => $_setUnsignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasScrollbackOffset() => $_has(8);
  @$pb.TagNumber(9)
  void clearScrollbackOffset() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get scrollbackMaxOffset => $_getIZ(9);
  @$pb.TagNumber(10)
  set scrollbackMaxOffset($core.int value) => $_setUnsignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasScrollbackMaxOffset() => $_has(9);
  @$pb.TagNumber(10)
  void clearScrollbackMaxOffset() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get viewportStartRow => $_getIZ(10);
  @$pb.TagNumber(11)
  set viewportStartRow($core.int value) => $_setUnsignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasViewportStartRow() => $_has(10);
  @$pb.TagNumber(11)
  void clearViewportStartRow() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.int get viewportRowShift => $_getIZ(11);
  @$pb.TagNumber(12)
  set viewportRowShift($core.int value) => $_setSignedInt32(11, value);
  @$pb.TagNumber(12)
  $core.bool hasViewportRowShift() => $_has(11);
  @$pb.TagNumber(12)
  void clearViewportRowShift() => $_clearField(12);

  @$pb.TagNumber(13)
  ColorRgb get defaultForeground => $_getN(12);
  @$pb.TagNumber(13)
  set defaultForeground(ColorRgb value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasDefaultForeground() => $_has(12);
  @$pb.TagNumber(13)
  void clearDefaultForeground() => $_clearField(13);
  @$pb.TagNumber(13)
  ColorRgb ensureDefaultForeground() => $_ensure(12);

  @$pb.TagNumber(14)
  ColorRgb get defaultBackground => $_getN(13);
  @$pb.TagNumber(14)
  set defaultBackground(ColorRgb value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasDefaultBackground() => $_has(13);
  @$pb.TagNumber(14)
  void clearDefaultBackground() => $_clearField(14);
  @$pb.TagNumber(14)
  ColorRgb ensureDefaultBackground() => $_ensure(13);

  @$pb.TagNumber(15)
  ColorRgb get cursorColor => $_getN(14);
  @$pb.TagNumber(15)
  set cursorColor(ColorRgb value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasCursorColor() => $_has(14);
  @$pb.TagNumber(15)
  void clearCursorColor() => $_clearField(15);
  @$pb.TagNumber(15)
  ColorRgb ensureCursorColor() => $_ensure(14);

  @$pb.TagNumber(16)
  TerminalFrameModes get modes => $_getN(15);
  @$pb.TagNumber(16)
  set modes(TerminalFrameModes value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasModes() => $_has(15);
  @$pb.TagNumber(16)
  void clearModes() => $_clearField(16);
  @$pb.TagNumber(16)
  TerminalFrameModes ensureModes() => $_ensure(15);

  @$pb.TagNumber(17)
  $core.String get windowTitle => $_getSZ(16);
  @$pb.TagNumber(17)
  set windowTitle($core.String value) => $_setString(16, value);
  @$pb.TagNumber(17)
  $core.bool hasWindowTitle() => $_has(16);
  @$pb.TagNumber(17)
  void clearWindowTitle() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.String get windowIconName => $_getSZ(17);
  @$pb.TagNumber(18)
  set windowIconName($core.String value) => $_setString(17, value);
  @$pb.TagNumber(18)
  $core.bool hasWindowIconName() => $_has(17);
  @$pb.TagNumber(18)
  void clearWindowIconName() => $_clearField(18);

  @$pb.TagNumber(19)
  $pb.PbList<TerminalHyperlinkRange> get hyperlinks => $_getList(18);

  @$pb.TagNumber(20)
  $pb.PbList<TerminalInlineImage> get inlineImages => $_getList(19);

  @$pb.TagNumber(21)
  $pb.PbList<TerminalGraphicPlacement> get graphics => $_getList(20);

  @$pb.TagNumber(22)
  $fixnum.Int64 get globalBottomRow => $_getI64(21);
  @$pb.TagNumber(22)
  set globalBottomRow($fixnum.Int64 value) => $_setInt64(21, value);
  @$pb.TagNumber(22)
  $core.bool hasGlobalBottomRow() => $_has(21);
  @$pb.TagNumber(22)
  void clearGlobalBottomRow() => $_clearField(22);

  @$pb.TagNumber(23)
  $core.String get pointerShape => $_getSZ(22);
  @$pb.TagNumber(23)
  set pointerShape($core.String value) => $_setString(22, value);
  @$pb.TagNumber(23)
  $core.bool hasPointerShape() => $_has(22);
  @$pb.TagNumber(23)
  void clearPointerShape() => $_clearField(23);

  @$pb.TagNumber(24)
  $pb.PbList<TerminalSizedTextPlacement> get sizedText => $_getList(23);
}

class TerminalRow extends $pb.GeneratedMessage {
  factory TerminalRow({
    $core.int? index,
    $core.String? text,
    $core.bool? wrapped,
    $fixnum.Int64? modifiedAtMicros,
    $core.Iterable<TerminalStyleRun>? styleRuns,
  }) {
    final result = create();
    if (index != null) result.index = index;
    if (text != null) result.text = text;
    if (wrapped != null) result.wrapped = wrapped;
    if (modifiedAtMicros != null) result.modifiedAtMicros = modifiedAtMicros;
    if (styleRuns != null) result.styleRuns.addAll(styleRuns);
    return result;
  }

  TerminalRow._();

  factory TerminalRow.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TerminalRow.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TerminalRow',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'frame_diff'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'index', fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..aOB(3, _omitFieldNames ? '' : 'wrapped')
    ..aInt64(4, _omitFieldNames ? '' : 'modifiedAtMicros')
    ..pPM<TerminalStyleRun>(5, _omitFieldNames ? '' : 'styleRuns',
        subBuilder: TerminalStyleRun.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalRow clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalRow copyWith(void Function(TerminalRow) updates) =>
      super.copyWith((message) => updates(message as TerminalRow))
          as TerminalRow;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TerminalRow create() => TerminalRow._();
  @$core.override
  TerminalRow createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TerminalRow getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TerminalRow>(create);
  static TerminalRow? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get index => $_getIZ(0);
  @$pb.TagNumber(1)
  set index($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIndex() => $_has(0);
  @$pb.TagNumber(1)
  void clearIndex() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get wrapped => $_getBF(2);
  @$pb.TagNumber(3)
  set wrapped($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasWrapped() => $_has(2);
  @$pb.TagNumber(3)
  void clearWrapped() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get modifiedAtMicros => $_getI64(3);
  @$pb.TagNumber(4)
  set modifiedAtMicros($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasModifiedAtMicros() => $_has(3);
  @$pb.TagNumber(4)
  void clearModifiedAtMicros() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<TerminalStyleRun> get styleRuns => $_getList(4);
}

class TerminalStyleRun extends $pb.GeneratedMessage {
  factory TerminalStyleRun({
    $core.int? start,
    $core.int? end,
    ColorRgb? foreground,
    ColorRgb? background,
    $core.bool? bold,
    $core.bool? dim,
    $core.bool? italic,
    $core.bool? underline,
    $core.bool? blink,
    $core.bool? inverse,
  }) {
    final result = create();
    if (start != null) result.start = start;
    if (end != null) result.end = end;
    if (foreground != null) result.foreground = foreground;
    if (background != null) result.background = background;
    if (bold != null) result.bold = bold;
    if (dim != null) result.dim = dim;
    if (italic != null) result.italic = italic;
    if (underline != null) result.underline = underline;
    if (blink != null) result.blink = blink;
    if (inverse != null) result.inverse = inverse;
    return result;
  }

  TerminalStyleRun._();

  factory TerminalStyleRun.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TerminalStyleRun.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TerminalStyleRun',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'frame_diff'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'start', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'end', fieldType: $pb.PbFieldType.OU3)
    ..aOM<ColorRgb>(3, _omitFieldNames ? '' : 'foreground',
        subBuilder: ColorRgb.create)
    ..aOM<ColorRgb>(4, _omitFieldNames ? '' : 'background',
        subBuilder: ColorRgb.create)
    ..aOB(5, _omitFieldNames ? '' : 'bold')
    ..aOB(6, _omitFieldNames ? '' : 'dim')
    ..aOB(7, _omitFieldNames ? '' : 'italic')
    ..aOB(8, _omitFieldNames ? '' : 'underline')
    ..aOB(9, _omitFieldNames ? '' : 'blink')
    ..aOB(10, _omitFieldNames ? '' : 'inverse')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalStyleRun clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalStyleRun copyWith(void Function(TerminalStyleRun) updates) =>
      super.copyWith((message) => updates(message as TerminalStyleRun))
          as TerminalStyleRun;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TerminalStyleRun create() => TerminalStyleRun._();
  @$core.override
  TerminalStyleRun createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TerminalStyleRun getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TerminalStyleRun>(create);
  static TerminalStyleRun? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get start => $_getIZ(0);
  @$pb.TagNumber(1)
  set start($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStart() => $_has(0);
  @$pb.TagNumber(1)
  void clearStart() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get end => $_getIZ(1);
  @$pb.TagNumber(2)
  set end($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEnd() => $_has(1);
  @$pb.TagNumber(2)
  void clearEnd() => $_clearField(2);

  @$pb.TagNumber(3)
  ColorRgb get foreground => $_getN(2);
  @$pb.TagNumber(3)
  set foreground(ColorRgb value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasForeground() => $_has(2);
  @$pb.TagNumber(3)
  void clearForeground() => $_clearField(3);
  @$pb.TagNumber(3)
  ColorRgb ensureForeground() => $_ensure(2);

  @$pb.TagNumber(4)
  ColorRgb get background => $_getN(3);
  @$pb.TagNumber(4)
  set background(ColorRgb value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasBackground() => $_has(3);
  @$pb.TagNumber(4)
  void clearBackground() => $_clearField(4);
  @$pb.TagNumber(4)
  ColorRgb ensureBackground() => $_ensure(3);

  @$pb.TagNumber(5)
  $core.bool get bold => $_getBF(4);
  @$pb.TagNumber(5)
  set bold($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBold() => $_has(4);
  @$pb.TagNumber(5)
  void clearBold() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get dim => $_getBF(5);
  @$pb.TagNumber(6)
  set dim($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDim() => $_has(5);
  @$pb.TagNumber(6)
  void clearDim() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get italic => $_getBF(6);
  @$pb.TagNumber(7)
  set italic($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasItalic() => $_has(6);
  @$pb.TagNumber(7)
  void clearItalic() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get underline => $_getBF(7);
  @$pb.TagNumber(8)
  set underline($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasUnderline() => $_has(7);
  @$pb.TagNumber(8)
  void clearUnderline() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get blink => $_getBF(8);
  @$pb.TagNumber(9)
  set blink($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasBlink() => $_has(8);
  @$pb.TagNumber(9)
  void clearBlink() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.bool get inverse => $_getBF(9);
  @$pb.TagNumber(10)
  set inverse($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasInverse() => $_has(9);
  @$pb.TagNumber(10)
  void clearInverse() => $_clearField(10);
}

class ColorRgb extends $pb.GeneratedMessage {
  factory ColorRgb({
    $core.bool? present,
    $core.int? rgb,
  }) {
    final result = create();
    if (present != null) result.present = present;
    if (rgb != null) result.rgb = rgb;
    return result;
  }

  ColorRgb._();

  factory ColorRgb.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ColorRgb.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ColorRgb',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'frame_diff'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'present')
    ..aI(2, _omitFieldNames ? '' : 'rgb', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ColorRgb clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ColorRgb copyWith(void Function(ColorRgb) updates) =>
      super.copyWith((message) => updates(message as ColorRgb)) as ColorRgb;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ColorRgb create() => ColorRgb._();
  @$core.override
  ColorRgb createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ColorRgb getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ColorRgb>(create);
  static ColorRgb? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get present => $_getBF(0);
  @$pb.TagNumber(1)
  set present($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPresent() => $_has(0);
  @$pb.TagNumber(1)
  void clearPresent() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get rgb => $_getIZ(1);
  @$pb.TagNumber(2)
  set rgb($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRgb() => $_has(1);
  @$pb.TagNumber(2)
  void clearRgb() => $_clearField(2);
}

class TerminalCursor extends $pb.GeneratedMessage {
  factory TerminalCursor({
    $core.int? row,
    $core.int? col,
    $core.bool? visible,
    $core.String? shape,
    $core.bool? blink,
  }) {
    final result = create();
    if (row != null) result.row = row;
    if (col != null) result.col = col;
    if (visible != null) result.visible = visible;
    if (shape != null) result.shape = shape;
    if (blink != null) result.blink = blink;
    return result;
  }

  TerminalCursor._();

  factory TerminalCursor.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TerminalCursor.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TerminalCursor',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'frame_diff'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'row', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'col', fieldType: $pb.PbFieldType.OU3)
    ..aOB(3, _omitFieldNames ? '' : 'visible')
    ..aOS(4, _omitFieldNames ? '' : 'shape')
    ..aOB(5, _omitFieldNames ? '' : 'blink')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalCursor clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalCursor copyWith(void Function(TerminalCursor) updates) =>
      super.copyWith((message) => updates(message as TerminalCursor))
          as TerminalCursor;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TerminalCursor create() => TerminalCursor._();
  @$core.override
  TerminalCursor createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TerminalCursor getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TerminalCursor>(create);
  static TerminalCursor? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get row => $_getIZ(0);
  @$pb.TagNumber(1)
  set row($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRow() => $_has(0);
  @$pb.TagNumber(1)
  void clearRow() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get col => $_getIZ(1);
  @$pb.TagNumber(2)
  set col($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCol() => $_has(1);
  @$pb.TagNumber(2)
  void clearCol() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get visible => $_getBF(2);
  @$pb.TagNumber(3)
  set visible($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasVisible() => $_has(2);
  @$pb.TagNumber(3)
  void clearVisible() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get shape => $_getSZ(3);
  @$pb.TagNumber(4)
  set shape($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasShape() => $_has(3);
  @$pb.TagNumber(4)
  void clearShape() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get blink => $_getBF(4);
  @$pb.TagNumber(5)
  set blink($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBlink() => $_has(4);
  @$pb.TagNumber(5)
  void clearBlink() => $_clearField(5);
}

class TerminalSelection extends $pb.GeneratedMessage {
  factory TerminalSelection({
    $core.bool? present,
    $core.int? startRow,
    $core.int? startCol,
    $core.int? endRow,
    $core.int? endCol,
  }) {
    final result = create();
    if (present != null) result.present = present;
    if (startRow != null) result.startRow = startRow;
    if (startCol != null) result.startCol = startCol;
    if (endRow != null) result.endRow = endRow;
    if (endCol != null) result.endCol = endCol;
    return result;
  }

  TerminalSelection._();

  factory TerminalSelection.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TerminalSelection.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TerminalSelection',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'frame_diff'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'present')
    ..aI(2, _omitFieldNames ? '' : 'startRow', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'startCol', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'endRow', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'endCol', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalSelection clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalSelection copyWith(void Function(TerminalSelection) updates) =>
      super.copyWith((message) => updates(message as TerminalSelection))
          as TerminalSelection;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TerminalSelection create() => TerminalSelection._();
  @$core.override
  TerminalSelection createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TerminalSelection getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TerminalSelection>(create);
  static TerminalSelection? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get present => $_getBF(0);
  @$pb.TagNumber(1)
  set present($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPresent() => $_has(0);
  @$pb.TagNumber(1)
  void clearPresent() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get startRow => $_getIZ(1);
  @$pb.TagNumber(2)
  set startRow($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStartRow() => $_has(1);
  @$pb.TagNumber(2)
  void clearStartRow() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get startCol => $_getIZ(2);
  @$pb.TagNumber(3)
  set startCol($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStartCol() => $_has(2);
  @$pb.TagNumber(3)
  void clearStartCol() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get endRow => $_getIZ(3);
  @$pb.TagNumber(4)
  set endRow($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEndRow() => $_has(3);
  @$pb.TagNumber(4)
  void clearEndRow() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get endCol => $_getIZ(4);
  @$pb.TagNumber(5)
  set endCol($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasEndCol() => $_has(4);
  @$pb.TagNumber(5)
  void clearEndCol() => $_clearField(5);
}

class TerminalDirtyRange extends $pb.GeneratedMessage {
  factory TerminalDirtyRange({
    $core.int? start,
    $core.int? end,
  }) {
    final result = create();
    if (start != null) result.start = start;
    if (end != null) result.end = end;
    return result;
  }

  TerminalDirtyRange._();

  factory TerminalDirtyRange.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TerminalDirtyRange.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TerminalDirtyRange',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'frame_diff'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'start', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'end', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalDirtyRange clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalDirtyRange copyWith(void Function(TerminalDirtyRange) updates) =>
      super.copyWith((message) => updates(message as TerminalDirtyRange))
          as TerminalDirtyRange;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TerminalDirtyRange create() => TerminalDirtyRange._();
  @$core.override
  TerminalDirtyRange createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TerminalDirtyRange getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TerminalDirtyRange>(create);
  static TerminalDirtyRange? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get start => $_getIZ(0);
  @$pb.TagNumber(1)
  set start($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStart() => $_has(0);
  @$pb.TagNumber(1)
  void clearStart() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get end => $_getIZ(1);
  @$pb.TagNumber(2)
  set end($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEnd() => $_has(1);
  @$pb.TagNumber(2)
  void clearEnd() => $_clearField(2);
}

class TerminalFrameModes extends $pb.GeneratedMessage {
  factory TerminalFrameModes({
    $core.bool? alternateScreen,
    $core.bool? alternateScroll,
    $core.bool? applicationCursor,
    $core.bool? applicationKeypad,
    $core.bool? insertMode,
    $core.bool? originMode,
    $core.bool? lineFeedNewLineMode,
    $core.bool? hideCursor,
    $core.bool? bracketedPaste,
    $core.bool? focusTracking,
    $core.bool? charProtected,
    $core.String? mouseMode,
    $core.String? mouseEncoding,
    $core.int? kittyKeyboardFlags,
    $core.bool? synchronizedOutput,
  }) {
    final result = create();
    if (alternateScreen != null) result.alternateScreen = alternateScreen;
    if (alternateScroll != null) result.alternateScroll = alternateScroll;
    if (applicationCursor != null) result.applicationCursor = applicationCursor;
    if (applicationKeypad != null) result.applicationKeypad = applicationKeypad;
    if (insertMode != null) result.insertMode = insertMode;
    if (originMode != null) result.originMode = originMode;
    if (lineFeedNewLineMode != null)
      result.lineFeedNewLineMode = lineFeedNewLineMode;
    if (hideCursor != null) result.hideCursor = hideCursor;
    if (bracketedPaste != null) result.bracketedPaste = bracketedPaste;
    if (focusTracking != null) result.focusTracking = focusTracking;
    if (charProtected != null) result.charProtected = charProtected;
    if (mouseMode != null) result.mouseMode = mouseMode;
    if (mouseEncoding != null) result.mouseEncoding = mouseEncoding;
    if (kittyKeyboardFlags != null)
      result.kittyKeyboardFlags = kittyKeyboardFlags;
    if (synchronizedOutput != null)
      result.synchronizedOutput = synchronizedOutput;
    return result;
  }

  TerminalFrameModes._();

  factory TerminalFrameModes.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TerminalFrameModes.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TerminalFrameModes',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'frame_diff'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'alternateScreen')
    ..aOB(2, _omitFieldNames ? '' : 'alternateScroll')
    ..aOB(3, _omitFieldNames ? '' : 'applicationCursor')
    ..aOB(4, _omitFieldNames ? '' : 'applicationKeypad')
    ..aOB(5, _omitFieldNames ? '' : 'insertMode')
    ..aOB(6, _omitFieldNames ? '' : 'originMode')
    ..aOB(7, _omitFieldNames ? '' : 'lineFeedNewLineMode')
    ..aOB(8, _omitFieldNames ? '' : 'hideCursor')
    ..aOB(9, _omitFieldNames ? '' : 'bracketedPaste')
    ..aOB(10, _omitFieldNames ? '' : 'focusTracking')
    ..aOB(11, _omitFieldNames ? '' : 'charProtected')
    ..aOS(12, _omitFieldNames ? '' : 'mouseMode')
    ..aOS(13, _omitFieldNames ? '' : 'mouseEncoding')
    ..aI(14, _omitFieldNames ? '' : 'kittyKeyboardFlags',
        fieldType: $pb.PbFieldType.OU3)
    ..aOB(15, _omitFieldNames ? '' : 'synchronizedOutput')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalFrameModes clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalFrameModes copyWith(void Function(TerminalFrameModes) updates) =>
      super.copyWith((message) => updates(message as TerminalFrameModes))
          as TerminalFrameModes;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TerminalFrameModes create() => TerminalFrameModes._();
  @$core.override
  TerminalFrameModes createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TerminalFrameModes getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TerminalFrameModes>(create);
  static TerminalFrameModes? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get alternateScreen => $_getBF(0);
  @$pb.TagNumber(1)
  set alternateScreen($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAlternateScreen() => $_has(0);
  @$pb.TagNumber(1)
  void clearAlternateScreen() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get alternateScroll => $_getBF(1);
  @$pb.TagNumber(2)
  set alternateScroll($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAlternateScroll() => $_has(1);
  @$pb.TagNumber(2)
  void clearAlternateScroll() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get applicationCursor => $_getBF(2);
  @$pb.TagNumber(3)
  set applicationCursor($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasApplicationCursor() => $_has(2);
  @$pb.TagNumber(3)
  void clearApplicationCursor() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get applicationKeypad => $_getBF(3);
  @$pb.TagNumber(4)
  set applicationKeypad($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasApplicationKeypad() => $_has(3);
  @$pb.TagNumber(4)
  void clearApplicationKeypad() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get insertMode => $_getBF(4);
  @$pb.TagNumber(5)
  set insertMode($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasInsertMode() => $_has(4);
  @$pb.TagNumber(5)
  void clearInsertMode() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get originMode => $_getBF(5);
  @$pb.TagNumber(6)
  set originMode($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasOriginMode() => $_has(5);
  @$pb.TagNumber(6)
  void clearOriginMode() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get lineFeedNewLineMode => $_getBF(6);
  @$pb.TagNumber(7)
  set lineFeedNewLineMode($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasLineFeedNewLineMode() => $_has(6);
  @$pb.TagNumber(7)
  void clearLineFeedNewLineMode() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get hideCursor => $_getBF(7);
  @$pb.TagNumber(8)
  set hideCursor($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasHideCursor() => $_has(7);
  @$pb.TagNumber(8)
  void clearHideCursor() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get bracketedPaste => $_getBF(8);
  @$pb.TagNumber(9)
  set bracketedPaste($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasBracketedPaste() => $_has(8);
  @$pb.TagNumber(9)
  void clearBracketedPaste() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.bool get focusTracking => $_getBF(9);
  @$pb.TagNumber(10)
  set focusTracking($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasFocusTracking() => $_has(9);
  @$pb.TagNumber(10)
  void clearFocusTracking() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.bool get charProtected => $_getBF(10);
  @$pb.TagNumber(11)
  set charProtected($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(11)
  $core.bool hasCharProtected() => $_has(10);
  @$pb.TagNumber(11)
  void clearCharProtected() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get mouseMode => $_getSZ(11);
  @$pb.TagNumber(12)
  set mouseMode($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasMouseMode() => $_has(11);
  @$pb.TagNumber(12)
  void clearMouseMode() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get mouseEncoding => $_getSZ(12);
  @$pb.TagNumber(13)
  set mouseEncoding($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasMouseEncoding() => $_has(12);
  @$pb.TagNumber(13)
  void clearMouseEncoding() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.int get kittyKeyboardFlags => $_getIZ(13);
  @$pb.TagNumber(14)
  set kittyKeyboardFlags($core.int value) => $_setUnsignedInt32(13, value);
  @$pb.TagNumber(14)
  $core.bool hasKittyKeyboardFlags() => $_has(13);
  @$pb.TagNumber(14)
  void clearKittyKeyboardFlags() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.bool get synchronizedOutput => $_getBF(14);
  @$pb.TagNumber(15)
  set synchronizedOutput($core.bool value) => $_setBool(14, value);
  @$pb.TagNumber(15)
  $core.bool hasSynchronizedOutput() => $_has(14);
  @$pb.TagNumber(15)
  void clearSynchronizedOutput() => $_clearField(15);
}

class TerminalHyperlinkRange extends $pb.GeneratedMessage {
  factory TerminalHyperlinkRange({
    $core.int? row,
    $core.int? startCol,
    $core.int? endCol,
    $core.String? uri,
    $core.String? protocolId,
  }) {
    final result = create();
    if (row != null) result.row = row;
    if (startCol != null) result.startCol = startCol;
    if (endCol != null) result.endCol = endCol;
    if (uri != null) result.uri = uri;
    if (protocolId != null) result.protocolId = protocolId;
    return result;
  }

  TerminalHyperlinkRange._();

  factory TerminalHyperlinkRange.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TerminalHyperlinkRange.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TerminalHyperlinkRange',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'frame_diff'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'row', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'startCol', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'endCol', fieldType: $pb.PbFieldType.OU3)
    ..aOS(4, _omitFieldNames ? '' : 'uri')
    ..aOS(5, _omitFieldNames ? '' : 'protocolId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalHyperlinkRange clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalHyperlinkRange copyWith(
          void Function(TerminalHyperlinkRange) updates) =>
      super.copyWith((message) => updates(message as TerminalHyperlinkRange))
          as TerminalHyperlinkRange;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TerminalHyperlinkRange create() => TerminalHyperlinkRange._();
  @$core.override
  TerminalHyperlinkRange createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TerminalHyperlinkRange getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TerminalHyperlinkRange>(create);
  static TerminalHyperlinkRange? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get row => $_getIZ(0);
  @$pb.TagNumber(1)
  set row($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRow() => $_has(0);
  @$pb.TagNumber(1)
  void clearRow() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get startCol => $_getIZ(1);
  @$pb.TagNumber(2)
  set startCol($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStartCol() => $_has(1);
  @$pb.TagNumber(2)
  void clearStartCol() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get endCol => $_getIZ(2);
  @$pb.TagNumber(3)
  set endCol($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasEndCol() => $_has(2);
  @$pb.TagNumber(3)
  void clearEndCol() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get uri => $_getSZ(3);
  @$pb.TagNumber(4)
  set uri($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasUri() => $_has(3);
  @$pb.TagNumber(4)
  void clearUri() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get protocolId => $_getSZ(4);
  @$pb.TagNumber(5)
  set protocolId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasProtocolId() => $_has(4);
  @$pb.TagNumber(5)
  void clearProtocolId() => $_clearField(5);
}

class TerminalSizedTextPlacement extends $pb.GeneratedMessage {
  factory TerminalSizedTextPlacement({
    $core.String? text,
    $core.int? row,
    $core.int? col,
    $core.int? widthCells,
    $core.int? heightCells,
    $core.int? sourceRowOffsetCells,
    $core.int? visibleHeightCells,
    $core.int? scale,
    $core.int? subscaleN,
    $core.int? subscaleD,
    $core.int? verticalAlign,
    $core.int? horizontalAlign,
    $core.bool? naturalWidth,
    ColorRgb? foreground,
    ColorRgb? background,
    $core.bool? bold,
    $core.bool? dim,
    $core.bool? italic,
    $core.bool? underline,
    $core.bool? blink,
    $core.bool? inverse,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (row != null) result.row = row;
    if (col != null) result.col = col;
    if (widthCells != null) result.widthCells = widthCells;
    if (heightCells != null) result.heightCells = heightCells;
    if (sourceRowOffsetCells != null)
      result.sourceRowOffsetCells = sourceRowOffsetCells;
    if (visibleHeightCells != null)
      result.visibleHeightCells = visibleHeightCells;
    if (scale != null) result.scale = scale;
    if (subscaleN != null) result.subscaleN = subscaleN;
    if (subscaleD != null) result.subscaleD = subscaleD;
    if (verticalAlign != null) result.verticalAlign = verticalAlign;
    if (horizontalAlign != null) result.horizontalAlign = horizontalAlign;
    if (naturalWidth != null) result.naturalWidth = naturalWidth;
    if (foreground != null) result.foreground = foreground;
    if (background != null) result.background = background;
    if (bold != null) result.bold = bold;
    if (dim != null) result.dim = dim;
    if (italic != null) result.italic = italic;
    if (underline != null) result.underline = underline;
    if (blink != null) result.blink = blink;
    if (inverse != null) result.inverse = inverse;
    return result;
  }

  TerminalSizedTextPlacement._();

  factory TerminalSizedTextPlacement.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TerminalSizedTextPlacement.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TerminalSizedTextPlacement',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'frame_diff'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aI(2, _omitFieldNames ? '' : 'row', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'col', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'widthCells', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'heightCells',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'sourceRowOffsetCells',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'visibleHeightCells',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(8, _omitFieldNames ? '' : 'scale', fieldType: $pb.PbFieldType.OU3)
    ..aI(9, _omitFieldNames ? '' : 'subscaleN', fieldType: $pb.PbFieldType.OU3)
    ..aI(10, _omitFieldNames ? '' : 'subscaleD', fieldType: $pb.PbFieldType.OU3)
    ..aI(11, _omitFieldNames ? '' : 'verticalAlign',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(12, _omitFieldNames ? '' : 'horizontalAlign',
        fieldType: $pb.PbFieldType.OU3)
    ..aOB(13, _omitFieldNames ? '' : 'naturalWidth')
    ..aOM<ColorRgb>(14, _omitFieldNames ? '' : 'foreground',
        subBuilder: ColorRgb.create)
    ..aOM<ColorRgb>(15, _omitFieldNames ? '' : 'background',
        subBuilder: ColorRgb.create)
    ..aOB(16, _omitFieldNames ? '' : 'bold')
    ..aOB(17, _omitFieldNames ? '' : 'dim')
    ..aOB(18, _omitFieldNames ? '' : 'italic')
    ..aOB(19, _omitFieldNames ? '' : 'underline')
    ..aOB(20, _omitFieldNames ? '' : 'blink')
    ..aOB(21, _omitFieldNames ? '' : 'inverse')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalSizedTextPlacement clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalSizedTextPlacement copyWith(
          void Function(TerminalSizedTextPlacement) updates) =>
      super.copyWith(
              (message) => updates(message as TerminalSizedTextPlacement))
          as TerminalSizedTextPlacement;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TerminalSizedTextPlacement create() => TerminalSizedTextPlacement._();
  @$core.override
  TerminalSizedTextPlacement createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TerminalSizedTextPlacement getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TerminalSizedTextPlacement>(create);
  static TerminalSizedTextPlacement? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get row => $_getIZ(1);
  @$pb.TagNumber(2)
  set row($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRow() => $_has(1);
  @$pb.TagNumber(2)
  void clearRow() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get col => $_getIZ(2);
  @$pb.TagNumber(3)
  set col($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCol() => $_has(2);
  @$pb.TagNumber(3)
  void clearCol() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get widthCells => $_getIZ(3);
  @$pb.TagNumber(4)
  set widthCells($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasWidthCells() => $_has(3);
  @$pb.TagNumber(4)
  void clearWidthCells() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get heightCells => $_getIZ(4);
  @$pb.TagNumber(5)
  set heightCells($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasHeightCells() => $_has(4);
  @$pb.TagNumber(5)
  void clearHeightCells() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get sourceRowOffsetCells => $_getIZ(5);
  @$pb.TagNumber(6)
  set sourceRowOffsetCells($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSourceRowOffsetCells() => $_has(5);
  @$pb.TagNumber(6)
  void clearSourceRowOffsetCells() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get visibleHeightCells => $_getIZ(6);
  @$pb.TagNumber(7)
  set visibleHeightCells($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasVisibleHeightCells() => $_has(6);
  @$pb.TagNumber(7)
  void clearVisibleHeightCells() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get scale => $_getIZ(7);
  @$pb.TagNumber(8)
  set scale($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasScale() => $_has(7);
  @$pb.TagNumber(8)
  void clearScale() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get subscaleN => $_getIZ(8);
  @$pb.TagNumber(9)
  set subscaleN($core.int value) => $_setUnsignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasSubscaleN() => $_has(8);
  @$pb.TagNumber(9)
  void clearSubscaleN() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get subscaleD => $_getIZ(9);
  @$pb.TagNumber(10)
  set subscaleD($core.int value) => $_setUnsignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasSubscaleD() => $_has(9);
  @$pb.TagNumber(10)
  void clearSubscaleD() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get verticalAlign => $_getIZ(10);
  @$pb.TagNumber(11)
  set verticalAlign($core.int value) => $_setUnsignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasVerticalAlign() => $_has(10);
  @$pb.TagNumber(11)
  void clearVerticalAlign() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.int get horizontalAlign => $_getIZ(11);
  @$pb.TagNumber(12)
  set horizontalAlign($core.int value) => $_setUnsignedInt32(11, value);
  @$pb.TagNumber(12)
  $core.bool hasHorizontalAlign() => $_has(11);
  @$pb.TagNumber(12)
  void clearHorizontalAlign() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.bool get naturalWidth => $_getBF(12);
  @$pb.TagNumber(13)
  set naturalWidth($core.bool value) => $_setBool(12, value);
  @$pb.TagNumber(13)
  $core.bool hasNaturalWidth() => $_has(12);
  @$pb.TagNumber(13)
  void clearNaturalWidth() => $_clearField(13);

  @$pb.TagNumber(14)
  ColorRgb get foreground => $_getN(13);
  @$pb.TagNumber(14)
  set foreground(ColorRgb value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasForeground() => $_has(13);
  @$pb.TagNumber(14)
  void clearForeground() => $_clearField(14);
  @$pb.TagNumber(14)
  ColorRgb ensureForeground() => $_ensure(13);

  @$pb.TagNumber(15)
  ColorRgb get background => $_getN(14);
  @$pb.TagNumber(15)
  set background(ColorRgb value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasBackground() => $_has(14);
  @$pb.TagNumber(15)
  void clearBackground() => $_clearField(15);
  @$pb.TagNumber(15)
  ColorRgb ensureBackground() => $_ensure(14);

  @$pb.TagNumber(16)
  $core.bool get bold => $_getBF(15);
  @$pb.TagNumber(16)
  set bold($core.bool value) => $_setBool(15, value);
  @$pb.TagNumber(16)
  $core.bool hasBold() => $_has(15);
  @$pb.TagNumber(16)
  void clearBold() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.bool get dim => $_getBF(16);
  @$pb.TagNumber(17)
  set dim($core.bool value) => $_setBool(16, value);
  @$pb.TagNumber(17)
  $core.bool hasDim() => $_has(16);
  @$pb.TagNumber(17)
  void clearDim() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.bool get italic => $_getBF(17);
  @$pb.TagNumber(18)
  set italic($core.bool value) => $_setBool(17, value);
  @$pb.TagNumber(18)
  $core.bool hasItalic() => $_has(17);
  @$pb.TagNumber(18)
  void clearItalic() => $_clearField(18);

  @$pb.TagNumber(19)
  $core.bool get underline => $_getBF(18);
  @$pb.TagNumber(19)
  set underline($core.bool value) => $_setBool(18, value);
  @$pb.TagNumber(19)
  $core.bool hasUnderline() => $_has(18);
  @$pb.TagNumber(19)
  void clearUnderline() => $_clearField(19);

  @$pb.TagNumber(20)
  $core.bool get blink => $_getBF(19);
  @$pb.TagNumber(20)
  set blink($core.bool value) => $_setBool(19, value);
  @$pb.TagNumber(20)
  $core.bool hasBlink() => $_has(19);
  @$pb.TagNumber(20)
  void clearBlink() => $_clearField(20);

  @$pb.TagNumber(21)
  $core.bool get inverse => $_getBF(20);
  @$pb.TagNumber(21)
  set inverse($core.bool value) => $_setBool(20, value);
  @$pb.TagNumber(21)
  $core.bool hasInverse() => $_has(20);
  @$pb.TagNumber(21)
  void clearInverse() => $_clearField(21);
}

class TerminalInlineImage extends $pb.GeneratedMessage {
  factory TerminalInlineImage({
    $core.String? data,
    $core.String? mimeType,
    $core.int? row,
    $core.int? col,
    $core.int? widthCells,
    $core.int? heightCells,
    $core.String? altText,
  }) {
    final result = create();
    if (data != null) result.data = data;
    if (mimeType != null) result.mimeType = mimeType;
    if (row != null) result.row = row;
    if (col != null) result.col = col;
    if (widthCells != null) result.widthCells = widthCells;
    if (heightCells != null) result.heightCells = heightCells;
    if (altText != null) result.altText = altText;
    return result;
  }

  TerminalInlineImage._();

  factory TerminalInlineImage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TerminalInlineImage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TerminalInlineImage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'frame_diff'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'data')
    ..aOS(2, _omitFieldNames ? '' : 'mimeType')
    ..aI(3, _omitFieldNames ? '' : 'row', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'col', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'widthCells', fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'heightCells',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(7, _omitFieldNames ? '' : 'altText')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalInlineImage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalInlineImage copyWith(void Function(TerminalInlineImage) updates) =>
      super.copyWith((message) => updates(message as TerminalInlineImage))
          as TerminalInlineImage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TerminalInlineImage create() => TerminalInlineImage._();
  @$core.override
  TerminalInlineImage createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TerminalInlineImage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TerminalInlineImage>(create);
  static TerminalInlineImage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get data => $_getSZ(0);
  @$pb.TagNumber(1)
  set data($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get mimeType => $_getSZ(1);
  @$pb.TagNumber(2)
  set mimeType($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMimeType() => $_has(1);
  @$pb.TagNumber(2)
  void clearMimeType() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get row => $_getIZ(2);
  @$pb.TagNumber(3)
  set row($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRow() => $_has(2);
  @$pb.TagNumber(3)
  void clearRow() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get col => $_getIZ(3);
  @$pb.TagNumber(4)
  set col($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCol() => $_has(3);
  @$pb.TagNumber(4)
  void clearCol() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get widthCells => $_getIZ(4);
  @$pb.TagNumber(5)
  set widthCells($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasWidthCells() => $_has(4);
  @$pb.TagNumber(5)
  void clearWidthCells() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get heightCells => $_getIZ(5);
  @$pb.TagNumber(6)
  set heightCells($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasHeightCells() => $_has(5);
  @$pb.TagNumber(6)
  void clearHeightCells() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get altText => $_getSZ(6);
  @$pb.TagNumber(7)
  set altText($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasAltText() => $_has(6);
  @$pb.TagNumber(7)
  void clearAltText() => $_clearField(7);
}

class TerminalGraphicAssetKey extends $pb.GeneratedMessage {
  factory TerminalGraphicAssetKey({
    $fixnum.Int64? assetId,
    $fixnum.Int64? assetVersion,
  }) {
    final result = create();
    if (assetId != null) result.assetId = assetId;
    if (assetVersion != null) result.assetVersion = assetVersion;
    return result;
  }

  TerminalGraphicAssetKey._();

  factory TerminalGraphicAssetKey.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TerminalGraphicAssetKey.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TerminalGraphicAssetKey',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'frame_diff'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'assetId', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'assetVersion', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalGraphicAssetKey clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalGraphicAssetKey copyWith(
          void Function(TerminalGraphicAssetKey) updates) =>
      super.copyWith((message) => updates(message as TerminalGraphicAssetKey))
          as TerminalGraphicAssetKey;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TerminalGraphicAssetKey create() => TerminalGraphicAssetKey._();
  @$core.override
  TerminalGraphicAssetKey createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TerminalGraphicAssetKey getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TerminalGraphicAssetKey>(create);
  static TerminalGraphicAssetKey? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get assetId => $_getI64(0);
  @$pb.TagNumber(1)
  set assetId($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAssetId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAssetId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get assetVersion => $_getI64(1);
  @$pb.TagNumber(2)
  set assetVersion($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAssetVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearAssetVersion() => $_clearField(2);
}

class TerminalGraphicPlacement extends $pb.GeneratedMessage {
  factory TerminalGraphicPlacement({
    $fixnum.Int64? placementId,
    $fixnum.Int64? renderId,
    TerminalGraphicAssetKey? assetKey,
    $core.String? protocol,
    $core.int? row,
    $core.int? col,
    $core.int? widthPx,
    $core.int? heightPx,
    $core.int? widthCells,
    $core.int? heightCells,
    $core.int? sourceXOffsetPx,
    $core.int? visibleWidthPx,
    $core.int? sourceYOffsetPx,
    $core.int? visibleHeightPx,
    $core.int? zIndex,
    $core.int? xOffsetPx,
    $core.int? yOffsetPx,
    $core.bool? preserveAspectRatio,
  }) {
    final result = create();
    if (placementId != null) result.placementId = placementId;
    if (renderId != null) result.renderId = renderId;
    if (assetKey != null) result.assetKey = assetKey;
    if (protocol != null) result.protocol = protocol;
    if (row != null) result.row = row;
    if (col != null) result.col = col;
    if (widthPx != null) result.widthPx = widthPx;
    if (heightPx != null) result.heightPx = heightPx;
    if (widthCells != null) result.widthCells = widthCells;
    if (heightCells != null) result.heightCells = heightCells;
    if (sourceXOffsetPx != null) result.sourceXOffsetPx = sourceXOffsetPx;
    if (visibleWidthPx != null) result.visibleWidthPx = visibleWidthPx;
    if (sourceYOffsetPx != null) result.sourceYOffsetPx = sourceYOffsetPx;
    if (visibleHeightPx != null) result.visibleHeightPx = visibleHeightPx;
    if (zIndex != null) result.zIndex = zIndex;
    if (xOffsetPx != null) result.xOffsetPx = xOffsetPx;
    if (yOffsetPx != null) result.yOffsetPx = yOffsetPx;
    if (preserveAspectRatio != null)
      result.preserveAspectRatio = preserveAspectRatio;
    return result;
  }

  TerminalGraphicPlacement._();

  factory TerminalGraphicPlacement.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TerminalGraphicPlacement.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TerminalGraphicPlacement',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'frame_diff'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'placementId', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'renderId', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<TerminalGraphicAssetKey>(3, _omitFieldNames ? '' : 'assetKey',
        subBuilder: TerminalGraphicAssetKey.create)
    ..aOS(4, _omitFieldNames ? '' : 'protocol')
    ..aI(5, _omitFieldNames ? '' : 'row', fieldType: $pb.PbFieldType.OU3)
    ..aI(6, _omitFieldNames ? '' : 'col', fieldType: $pb.PbFieldType.OU3)
    ..aI(7, _omitFieldNames ? '' : 'widthPx', fieldType: $pb.PbFieldType.OU3)
    ..aI(8, _omitFieldNames ? '' : 'heightPx', fieldType: $pb.PbFieldType.OU3)
    ..aI(9, _omitFieldNames ? '' : 'widthCells', fieldType: $pb.PbFieldType.OU3)
    ..aI(10, _omitFieldNames ? '' : 'heightCells',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(11, _omitFieldNames ? '' : 'sourceXOffsetPx',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(12, _omitFieldNames ? '' : 'visibleWidthPx',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(13, _omitFieldNames ? '' : 'sourceYOffsetPx',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(14, _omitFieldNames ? '' : 'visibleHeightPx',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(15, _omitFieldNames ? '' : 'zIndex')
    ..aI(16, _omitFieldNames ? '' : 'xOffsetPx')
    ..aI(17, _omitFieldNames ? '' : 'yOffsetPx')
    ..aOB(18, _omitFieldNames ? '' : 'preserveAspectRatio')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalGraphicPlacement clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TerminalGraphicPlacement copyWith(
          void Function(TerminalGraphicPlacement) updates) =>
      super.copyWith((message) => updates(message as TerminalGraphicPlacement))
          as TerminalGraphicPlacement;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TerminalGraphicPlacement create() => TerminalGraphicPlacement._();
  @$core.override
  TerminalGraphicPlacement createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TerminalGraphicPlacement getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TerminalGraphicPlacement>(create);
  static TerminalGraphicPlacement? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get placementId => $_getI64(0);
  @$pb.TagNumber(1)
  set placementId($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPlacementId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlacementId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get renderId => $_getI64(1);
  @$pb.TagNumber(2)
  set renderId($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRenderId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRenderId() => $_clearField(2);

  @$pb.TagNumber(3)
  TerminalGraphicAssetKey get assetKey => $_getN(2);
  @$pb.TagNumber(3)
  set assetKey(TerminalGraphicAssetKey value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasAssetKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearAssetKey() => $_clearField(3);
  @$pb.TagNumber(3)
  TerminalGraphicAssetKey ensureAssetKey() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get protocol => $_getSZ(3);
  @$pb.TagNumber(4)
  set protocol($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasProtocol() => $_has(3);
  @$pb.TagNumber(4)
  void clearProtocol() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get row => $_getIZ(4);
  @$pb.TagNumber(5)
  set row($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRow() => $_has(4);
  @$pb.TagNumber(5)
  void clearRow() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get col => $_getIZ(5);
  @$pb.TagNumber(6)
  set col($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCol() => $_has(5);
  @$pb.TagNumber(6)
  void clearCol() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get widthPx => $_getIZ(6);
  @$pb.TagNumber(7)
  set widthPx($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasWidthPx() => $_has(6);
  @$pb.TagNumber(7)
  void clearWidthPx() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get heightPx => $_getIZ(7);
  @$pb.TagNumber(8)
  set heightPx($core.int value) => $_setUnsignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasHeightPx() => $_has(7);
  @$pb.TagNumber(8)
  void clearHeightPx() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get widthCells => $_getIZ(8);
  @$pb.TagNumber(9)
  set widthCells($core.int value) => $_setUnsignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasWidthCells() => $_has(8);
  @$pb.TagNumber(9)
  void clearWidthCells() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get heightCells => $_getIZ(9);
  @$pb.TagNumber(10)
  set heightCells($core.int value) => $_setUnsignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasHeightCells() => $_has(9);
  @$pb.TagNumber(10)
  void clearHeightCells() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get sourceXOffsetPx => $_getIZ(10);
  @$pb.TagNumber(11)
  set sourceXOffsetPx($core.int value) => $_setUnsignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasSourceXOffsetPx() => $_has(10);
  @$pb.TagNumber(11)
  void clearSourceXOffsetPx() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.int get visibleWidthPx => $_getIZ(11);
  @$pb.TagNumber(12)
  set visibleWidthPx($core.int value) => $_setUnsignedInt32(11, value);
  @$pb.TagNumber(12)
  $core.bool hasVisibleWidthPx() => $_has(11);
  @$pb.TagNumber(12)
  void clearVisibleWidthPx() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.int get sourceYOffsetPx => $_getIZ(12);
  @$pb.TagNumber(13)
  set sourceYOffsetPx($core.int value) => $_setUnsignedInt32(12, value);
  @$pb.TagNumber(13)
  $core.bool hasSourceYOffsetPx() => $_has(12);
  @$pb.TagNumber(13)
  void clearSourceYOffsetPx() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.int get visibleHeightPx => $_getIZ(13);
  @$pb.TagNumber(14)
  set visibleHeightPx($core.int value) => $_setUnsignedInt32(13, value);
  @$pb.TagNumber(14)
  $core.bool hasVisibleHeightPx() => $_has(13);
  @$pb.TagNumber(14)
  void clearVisibleHeightPx() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.int get zIndex => $_getIZ(14);
  @$pb.TagNumber(15)
  set zIndex($core.int value) => $_setSignedInt32(14, value);
  @$pb.TagNumber(15)
  $core.bool hasZIndex() => $_has(14);
  @$pb.TagNumber(15)
  void clearZIndex() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.int get xOffsetPx => $_getIZ(15);
  @$pb.TagNumber(16)
  set xOffsetPx($core.int value) => $_setSignedInt32(15, value);
  @$pb.TagNumber(16)
  $core.bool hasXOffsetPx() => $_has(15);
  @$pb.TagNumber(16)
  void clearXOffsetPx() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.int get yOffsetPx => $_getIZ(16);
  @$pb.TagNumber(17)
  set yOffsetPx($core.int value) => $_setSignedInt32(16, value);
  @$pb.TagNumber(17)
  $core.bool hasYOffsetPx() => $_has(16);
  @$pb.TagNumber(17)
  void clearYOffsetPx() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.bool get preserveAspectRatio => $_getBF(17);
  @$pb.TagNumber(18)
  set preserveAspectRatio($core.bool value) => $_setBool(17, value);
  @$pb.TagNumber(18)
  $core.bool hasPreserveAspectRatio() => $_has(17);
  @$pb.TagNumber(18)
  void clearPreserveAspectRatio() => $_clearField(18);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
