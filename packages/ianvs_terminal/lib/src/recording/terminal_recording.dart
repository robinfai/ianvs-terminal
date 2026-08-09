import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const int terminalRecordingSchemaVersion = 1;
const int terminalRecordingCheckpointSchemaVersion = 2;
const int terminalRecordingSemanticSchemaVersion = 3;
const int terminalRecordingGraphicAssetMaxCount = 128;
const int terminalRecordingGraphicAssetMaxBytes = 32 * 1024 * 1024;

enum TerminalRecordingInputPolicy { record, redact }

enum TerminalRecordingEventKind {
  sessionStarted,
  ptyOutput,
  userInput,
  resize,
  sessionExited,
  checkpoint,
  shellSemantic,
}

enum TerminalRecordingSemanticKind {
  commandStarted,
  commandFinished,
  directoryChanged,
  prompt,
  remoteSessionStarted,
  remoteSessionFinished,
}

enum TerminalRecordingFormatErrorCode {
  invalidJson,
  invalidRecord,
  missingMetadata,
  unsupportedSchemaVersion,
  unsupportedEventKind,
  sessionMismatch,
  invalidSequence,
  invalidMonotonicOffset,
  invalidPayload,
}

final class TerminalRecordingFormatException implements FormatException {
  const TerminalRecordingFormatException({
    required this.code,
    required this.message,
    required this.lineNumber,
  });

  final TerminalRecordingFormatErrorCode code;

  @override
  final String message;

  final int lineNumber;

  @override
  Object? get source => null;

  @override
  int? get offset => null;

  @override
  String toString() {
    return 'TerminalRecordingFormatException('
        '${code.name}, line $lineNumber): $message';
  }
}

final class TerminalRecordingMetadata {
  TerminalRecordingMetadata({
    this.schemaVersion = terminalRecordingSchemaVersion,
    required this.sessionId,
    required DateTime createdAtUtc,
    required this.inputPolicy,
  }) : createdAtUtc = createdAtUtc.toUtc();

  final int schemaVersion;
  final String sessionId;
  final DateTime createdAtUtc;
  final TerminalRecordingInputPolicy inputPolicy;
}

final class TerminalRecordingEvent {
  TerminalRecordingEvent._({
    this.schemaVersion = terminalRecordingSchemaVersion,
    required this.sessionId,
    required this.sequence,
    required this.monotonicOffset,
    required this.kind,
    required Map<String, Object?> payload,
  }) : payload = Map<String, Object?>.unmodifiable(payload);

  factory TerminalRecordingEvent.sessionStarted({
    int schemaVersion = terminalRecordingSchemaVersion,
    required String sessionId,
    required int sequence,
    required Duration monotonicOffset,
    required String terminalEmulation,
    required int cols,
    required int rows,
  }) {
    return TerminalRecordingEvent._(
      schemaVersion: schemaVersion,
      sessionId: sessionId,
      sequence: sequence,
      monotonicOffset: monotonicOffset,
      kind: TerminalRecordingEventKind.sessionStarted,
      payload: <String, Object?>{
        'terminal_emulation': terminalEmulation,
        'cols': cols,
        'rows': rows,
      },
    );
  }

  factory TerminalRecordingEvent.ptyOutput({
    int schemaVersion = terminalRecordingSchemaVersion,
    required String sessionId,
    required int sequence,
    required Duration monotonicOffset,
    required List<int> bytes,
  }) {
    return TerminalRecordingEvent._(
      schemaVersion: schemaVersion,
      sessionId: sessionId,
      sequence: sequence,
      monotonicOffset: monotonicOffset,
      kind: TerminalRecordingEventKind.ptyOutput,
      payload: <String, Object?>{'bytes_base64': base64Encode(bytes)},
    );
  }

  factory TerminalRecordingEvent.userInput({
    int schemaVersion = terminalRecordingSchemaVersion,
    required String sessionId,
    required int sequence,
    required Duration monotonicOffset,
    required List<int> bytes,
  }) {
    return TerminalRecordingEvent._(
      schemaVersion: schemaVersion,
      sessionId: sessionId,
      sequence: sequence,
      monotonicOffset: monotonicOffset,
      kind: TerminalRecordingEventKind.userInput,
      payload: <String, Object?>{'bytes_base64': base64Encode(bytes)},
    );
  }

  factory TerminalRecordingEvent.redactedUserInput({
    int schemaVersion = terminalRecordingSchemaVersion,
    required String sessionId,
    required int sequence,
    required Duration monotonicOffset,
    required int byteLength,
  }) {
    return TerminalRecordingEvent._(
      schemaVersion: schemaVersion,
      sessionId: sessionId,
      sequence: sequence,
      monotonicOffset: monotonicOffset,
      kind: TerminalRecordingEventKind.userInput,
      payload: <String, Object?>{'byte_length': byteLength, 'redacted': true},
    );
  }

  factory TerminalRecordingEvent.resize({
    int schemaVersion = terminalRecordingSchemaVersion,
    required String sessionId,
    required int sequence,
    required Duration monotonicOffset,
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  }) {
    return TerminalRecordingEvent._(
      schemaVersion: schemaVersion,
      sessionId: sessionId,
      sequence: sequence,
      monotonicOffset: monotonicOffset,
      kind: TerminalRecordingEventKind.resize,
      payload: <String, Object?>{
        'cols': cols,
        'rows': rows,
        'pixel_width': pixelWidth,
        'pixel_height': pixelHeight,
        'cell_width': cellWidth,
        'cell_height': cellHeight,
      },
    );
  }

  factory TerminalRecordingEvent.sessionExited({
    int schemaVersion = terminalRecordingSchemaVersion,
    required String sessionId,
    required int sequence,
    required Duration monotonicOffset,
    int? exitCode,
  }) {
    return TerminalRecordingEvent._(
      schemaVersion: schemaVersion,
      sessionId: sessionId,
      sequence: sequence,
      monotonicOffset: monotonicOffset,
      kind: TerminalRecordingEventKind.sessionExited,
      payload: <String, Object?>{'exit_code': exitCode},
    );
  }

  factory TerminalRecordingEvent.checkpoint({
    int schemaVersion = terminalRecordingCheckpointSchemaVersion,
    required String sessionId,
    required int sequence,
    required Duration monotonicOffset,
    required String checkpointId,
    required int sourceSequence,
  }) {
    return TerminalRecordingEvent._(
      schemaVersion: schemaVersion,
      sessionId: sessionId,
      sequence: sequence,
      monotonicOffset: monotonicOffset,
      kind: TerminalRecordingEventKind.checkpoint,
      payload: <String, Object?>{
        'checkpoint_id': checkpointId,
        'source_sequence': sourceSequence,
      },
    );
  }

  factory TerminalRecordingEvent.shellSemantic({
    int schemaVersion = terminalRecordingSemanticSchemaVersion,
    required String sessionId,
    required int sequence,
    required Duration monotonicOffset,
    required TerminalRecordingSemanticKind semanticKind,
    String? command,
    String? cwd,
    String? hostname,
    int? exitCode,
    bool remote = false,
  }) {
    return TerminalRecordingEvent._(
      schemaVersion: schemaVersion,
      sessionId: sessionId,
      sequence: sequence,
      monotonicOffset: monotonicOffset,
      kind: TerminalRecordingEventKind.shellSemantic,
      payload: <String, Object?>{
        'semantic_kind': _semanticKindName(semanticKind),
        'command': ?command,
        'cwd': ?cwd,
        'hostname': ?hostname,
        'exit_code': ?exitCode,
        'remote': remote,
      },
    );
  }

  final int schemaVersion;
  final String sessionId;
  final int sequence;
  final Duration monotonicOffset;
  final TerminalRecordingEventKind kind;
  final Map<String, Object?> payload;

  Uint8List? get bytes {
    final encoded = payload['bytes_base64'];
    if (encoded is! String) {
      return null;
    }
    try {
      return base64Decode(encoded);
    } on FormatException {
      return null;
    }
  }

  int? get redactedByteLength {
    if (payload['redacted'] != true) {
      return null;
    }
    final byteLength = payload['byte_length'];
    return byteLength is int ? byteLength : null;
  }

  String? get checkpointId {
    if (kind != TerminalRecordingEventKind.checkpoint) {
      return null;
    }
    final value = payload['checkpoint_id'];
    return value is String ? value : null;
  }

  int? get checkpointSourceSequence {
    if (kind != TerminalRecordingEventKind.checkpoint) {
      return null;
    }
    final value = payload['source_sequence'];
    return value is int ? value : null;
  }

  TerminalRecordingSemanticKind? get semanticKind =>
      kind == TerminalRecordingEventKind.shellSemantic
      ? _semanticKindFromName(payload['semantic_kind'])
      : null;

  String? get semanticCommand =>
      payload['command'] is String ? payload['command']! as String : null;

  String? get semanticCwd =>
      payload['cwd'] is String ? payload['cwd']! as String : null;

  String? get semanticHostname =>
      payload['hostname'] is String ? payload['hostname']! as String : null;

  int? get semanticExitCode =>
      payload['exit_code'] is int ? payload['exit_code']! as int : null;

  bool get semanticRemote => payload['remote'] == true;
}

final class TerminalRecordingSemanticEvent {
  const TerminalRecordingSemanticEvent({
    required this.monotonicOffset,
    required this.kind,
    this.command,
    this.cwd,
    this.hostname,
    this.exitCode,
    this.remote = false,
  });

  final Duration monotonicOffset;
  final TerminalRecordingSemanticKind kind;
  final String? command;
  final String? cwd;
  final String? hostname;
  final int? exitCode;
  final bool remote;
}

final class TerminalRecordingGraphicAsset {
  TerminalRecordingGraphicAsset({
    required this.assetId,
    required this.assetVersion,
    required this.width,
    required this.height,
    required List<int> rgba,
  }) : rgba = Uint8List.fromList(rgba).asUnmodifiableView();

  TerminalRecordingGraphicAsset._fromOwnedRgba({
    required this.assetId,
    required this.assetVersion,
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int assetId;
  final int assetVersion;
  final int width;
  final int height;
  final Uint8List rgba;
}

final class TerminalRecording {
  TerminalRecording({
    required this.metadata,
    List<TerminalRecordingGraphicAsset> graphicAssets = const [],
    required List<TerminalRecordingEvent> events,
  }) : graphicAssets = List<TerminalRecordingGraphicAsset>.unmodifiable(
         graphicAssets,
       ),
       events = List<TerminalRecordingEvent>.unmodifiable(events);

  final TerminalRecordingMetadata metadata;
  final List<TerminalRecordingGraphicAsset> graphicAssets;
  final List<TerminalRecordingEvent> events;
}

/// Merges trusted shell-integration metadata into an otherwise byte-oriented
/// native recording. Recordings without semantics are returned unchanged.
final class TerminalRecordingSemanticMerger {
  const TerminalRecordingSemanticMerger();

  TerminalRecording merge(
    TerminalRecording recording,
    Iterable<TerminalRecordingSemanticEvent> semanticEvents,
  ) {
    final semantics = semanticEvents.toList(growable: false);
    if (semantics.isEmpty) {
      return recording;
    }
    final duration = recording.events.isEmpty
        ? Duration.zero
        : recording.events.last.monotonicOffset;
    final candidates =
        <_TerminalRecordingMergeCandidate>[
          for (var index = 0; index < recording.events.length; index += 1)
            if (recording.events[index].kind !=
                TerminalRecordingEventKind.checkpoint)
              _TerminalRecordingMergeCandidate(
                offset: recording.events[index].monotonicOffset,
                sourceOrder: index * 2,
                kind: recording.events[index].kind,
                payload: recording.events[index].payload,
              ),
          for (var index = 0; index < semantics.length; index += 1)
            _TerminalRecordingMergeCandidate(
              offset: _clampRecordingOffset(
                semantics[index].monotonicOffset,
                duration,
              ),
              sourceOrder: index * 2 + 1,
              semantic: semantics[index],
            ),
        ]..sort((left, right) {
          final byOffset = left.offset.compareTo(right.offset);
          if (byOffset != 0) {
            return byOffset;
          }
          if (left.kind == TerminalRecordingEventKind.sessionStarted) {
            return -1;
          }
          if (right.kind == TerminalRecordingEventKind.sessionStarted) {
            return 1;
          }
          return left.sourceOrder.compareTo(right.sourceOrder);
        });
    final events = <TerminalRecordingEvent>[];
    for (final candidate in candidates) {
      final semantic = candidate.semantic;
      if (semantic != null) {
        events.add(
          TerminalRecordingEvent.shellSemantic(
            sessionId: recording.metadata.sessionId,
            sequence: events.length,
            monotonicOffset: candidate.offset,
            semanticKind: semantic.kind,
            command: semantic.command,
            cwd: semantic.cwd,
            hostname: semantic.hostname,
            exitCode: semantic.exitCode,
            remote: semantic.remote,
          ),
        );
        continue;
      }
      events.add(
        TerminalRecordingEvent._(
          schemaVersion: terminalRecordingSemanticSchemaVersion,
          sessionId: recording.metadata.sessionId,
          sequence: events.length,
          monotonicOffset: candidate.offset,
          kind: candidate.kind!,
          payload: candidate.payload!,
        ),
      );
    }
    return TerminalRecording(
      metadata: TerminalRecordingMetadata(
        schemaVersion: terminalRecordingSemanticSchemaVersion,
        sessionId: recording.metadata.sessionId,
        createdAtUtc: recording.metadata.createdAtUtc,
        inputPolicy: recording.metadata.inputPolicy,
      ),
      graphicAssets: recording.graphicAssets,
      events: events,
    );
  }
}

final class _TerminalRecordingMergeCandidate {
  const _TerminalRecordingMergeCandidate({
    required this.offset,
    required this.sourceOrder,
    this.kind,
    this.payload,
    this.semantic,
  });

  final Duration offset;
  final int sourceOrder;
  final TerminalRecordingEventKind? kind;
  final Map<String, Object?>? payload;
  final TerminalRecordingSemanticEvent? semantic;
}

Duration _clampRecordingOffset(Duration value, Duration max) {
  if (value < Duration.zero) {
    return Duration.zero;
  }
  if (value > max) {
    return max;
  }
  return value;
}

/// Upgrades a validated recording to at least v2 and attaches a bounded,
/// content-addressed set of decoded RGBA graphic assets while preserving
/// newer schema features such as shell semantics.
final class TerminalRecordingGraphicAssetBundler {
  const TerminalRecordingGraphicAssetBundler();

  TerminalRecording bundle(
    TerminalRecording recording, {
    required Iterable<TerminalRecordingGraphicAsset> graphicAssets,
  }) {
    const codec = TerminalRecordingCodec();
    final validated = codec.decode(codec.encode(recording));
    final combined = <(int, int), TerminalRecordingGraphicAsset>{};
    void addAsset(TerminalRecordingGraphicAsset asset) {
      final identity = (asset.assetId, asset.assetVersion);
      final existing = combined[identity];
      if (existing != null) {
        if (existing.width != asset.width ||
            existing.height != asset.height ||
            !_bytesEqual(existing.rgba, asset.rgba)) {
          throw ArgumentError.value(
            identity,
            'graphicAssets',
            'must not redefine an existing asset identity',
          );
        }
        return;
      }
      if (combined.length >= terminalRecordingGraphicAssetMaxCount) {
        _throwInvalidPayload(
          1,
          'Graphic asset count exceeds $terminalRecordingGraphicAssetMaxCount',
        );
      }
      combined[identity] = asset;
    }

    for (final asset in validated.graphicAssets) {
      addAsset(asset);
    }
    for (final asset in graphicAssets) {
      addAsset(asset);
    }
    final targetSchemaVersion =
        validated.metadata.schemaVersion <
            terminalRecordingCheckpointSchemaVersion
        ? terminalRecordingCheckpointSchemaVersion
        : validated.metadata.schemaVersion;
    final bundled = TerminalRecording(
      metadata: TerminalRecordingMetadata(
        schemaVersion: targetSchemaVersion,
        sessionId: validated.metadata.sessionId,
        createdAtUtc: validated.metadata.createdAtUtc,
        inputPolicy: validated.metadata.inputPolicy,
      ),
      graphicAssets: combined.values.toList(growable: false),
      events: <TerminalRecordingEvent>[
        for (final event in validated.events)
          TerminalRecordingEvent._(
            schemaVersion: targetSchemaVersion,
            sessionId: event.sessionId,
            sequence: event.sequence,
            monotonicOffset: event.monotonicOffset,
            kind: event.kind,
            payload: event.payload,
          ),
      ],
    );
    return codec.decode(codec.encode(bundled));
  }
}

final class TerminalRecordingCodec {
  const TerminalRecordingCodec();

  String encode(TerminalRecording recording) {
    _validateMetadata(recording.metadata, lineNumber: 1);
    final records = <Map<String, Object?>>[
      <String, Object?>{
        'record_type': 'metadata',
        'schema_version': recording.metadata.schemaVersion,
        'session_id': recording.metadata.sessionId,
        'created_at_utc': recording.metadata.createdAtUtc.toIso8601String(),
        'input_policy': _inputPolicyName(recording.metadata.inputPolicy),
      },
      ..._canonicalGraphicAssetRecords(recording),
    ];
    var previousOffsetMicros = -1;
    for (var index = 0; index < recording.events.length; index += 1) {
      final event = recording.events[index];
      final lineNumber = records.length + 1;
      _validateEvent(
        event,
        metadata: recording.metadata,
        expectedSequence: index,
        previousOffsetMicros: previousOffsetMicros,
        lineNumber: lineNumber,
      );
      previousOffsetMicros = event.monotonicOffset.inMicroseconds;
      records.add(<String, Object?>{
        'record_type': 'event',
        'schema_version': event.schemaVersion,
        'session_id': event.sessionId,
        'sequence': event.sequence,
        'monotonic_offset_micros': event.monotonicOffset.inMicroseconds,
        'event_kind': _eventKindName(event.kind),
        'payload': _canonicalPayload(event, lineNumber: lineNumber),
      });
    }
    return '${records.map(jsonEncode).join('\n')}\n';
  }

  TerminalRecording decode(String source) {
    final lines = const LineSplitter().convert(source);
    if (lines.isEmpty) {
      throw const TerminalRecordingFormatException(
        code: TerminalRecordingFormatErrorCode.missingMetadata,
        message: 'Recording metadata is required',
        lineNumber: 1,
      );
    }
    final metadataJson = _decodeLine(lines.first, lineNumber: 1);
    final metadata = _decodeMetadata(metadataJson, lineNumber: 1);
    final graphicAssetBlobs = <String, _TerminalRecordingGraphicAssetBlob>{};
    final referencedBlobIds = <String>{};
    final graphicAssets = <TerminalRecordingGraphicAsset>[];
    final graphicAssetIdentities = <(int, int)>{};
    final events = <TerminalRecordingEvent>[];
    var previousOffsetMicros = -1;
    var decodedGraphicAssetBytes = 0;
    var eventsStarted = false;
    for (var index = 1; index < lines.length; index += 1) {
      final lineNumber = index + 1;
      final json = _decodeLine(lines[index], lineNumber: lineNumber);
      final recordType = json['record_type'];
      if (recordType == 'graphic_asset_blob') {
        if (eventsStarted) {
          _throwInvalidRecord(
            lineNumber,
            'Graphic asset records must precede event records',
          );
        }
        if (graphicAssetBlobs.length >= terminalRecordingGraphicAssetMaxCount) {
          _throwInvalidPayload(
            lineNumber,
            'Graphic asset blob count exceeds $terminalRecordingGraphicAssetMaxCount',
          );
        }
        final blob = _decodeGraphicAssetBlob(
          json,
          metadata: metadata,
          lineNumber: lineNumber,
        );
        if (graphicAssetBlobs.containsKey(blob.blobId)) {
          _throwInvalidPayload(lineNumber, 'Duplicate graphic asset blob_id');
        }
        decodedGraphicAssetBytes += blob.rgba.length;
        if (decodedGraphicAssetBytes > terminalRecordingGraphicAssetMaxBytes) {
          _throwInvalidPayload(
            lineNumber,
            'Graphic asset bytes exceed $terminalRecordingGraphicAssetMaxBytes',
          );
        }
        graphicAssetBlobs[blob.blobId] = blob;
        continue;
      }
      if (recordType == 'graphic_asset') {
        if (eventsStarted) {
          _throwInvalidRecord(
            lineNumber,
            'Graphic asset records must precede event records',
          );
        }
        if (graphicAssets.length >= terminalRecordingGraphicAssetMaxCount) {
          _throwInvalidPayload(
            lineNumber,
            'Graphic asset count exceeds $terminalRecordingGraphicAssetMaxCount',
          );
        }
        final asset = _decodeGraphicAssetReference(
          json,
          metadata: metadata,
          blobs: graphicAssetBlobs,
          lineNumber: lineNumber,
        );
        final identity = (asset.assetId, asset.assetVersion);
        if (!graphicAssetIdentities.add(identity)) {
          _throwInvalidPayload(lineNumber, 'Duplicate graphic asset identity');
        }
        referencedBlobIds.add(json['blob_id']! as String);
        graphicAssets.add(asset);
        continue;
      }
      if (recordType != 'event') {
        _throwInvalidRecord(lineNumber, 'Unsupported recording record_type');
      }
      eventsStarted = true;
      final event = _decodeEvent(json, lineNumber: lineNumber);
      _validateEvent(
        event,
        metadata: metadata,
        expectedSequence: events.length,
        previousOffsetMicros: previousOffsetMicros,
        lineNumber: lineNumber,
      );
      events.add(event);
      previousOffsetMicros = event.monotonicOffset.inMicroseconds;
    }
    if (graphicAssetBlobs.keys.any(
      (blobId) => !referencedBlobIds.contains(blobId),
    )) {
      _throwInvalidPayload(
        1,
        'Recording contains an unreferenced graphic asset blob',
      );
    }
    return TerminalRecording(
      metadata: metadata,
      graphicAssets: graphicAssets,
      events: events,
    );
  }
}

List<Map<String, Object?>> _canonicalGraphicAssetRecords(
  TerminalRecording recording,
) {
  if (recording.graphicAssets.length > terminalRecordingGraphicAssetMaxCount) {
    _throwInvalidPayload(
      1,
      'Graphic asset count exceeds $terminalRecordingGraphicAssetMaxCount',
    );
  }
  final assets = recording.graphicAssets.toList(growable: false)
    ..sort((left, right) {
      final idOrder = left.assetId.compareTo(right.assetId);
      return idOrder != 0
          ? idOrder
          : left.assetVersion.compareTo(right.assetVersion);
    });
  if (assets.isEmpty) {
    return const <Map<String, Object?>>[];
  }
  if (recording.metadata.schemaVersion <
      terminalRecordingCheckpointSchemaVersion) {
    throw const TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.unsupportedSchemaVersion,
      message: 'Graphic asset bundles require recording schema v2',
      lineNumber: 1,
    );
  }
  final blobs = <String, _TerminalRecordingGraphicAssetBlob>{};
  final identities = <(int, int)>{};
  var totalBytes = 0;
  for (var index = 0; index < assets.length; index += 1) {
    final asset = assets[index];
    final lineNumber = index + 2;
    _validateGraphicAsset(asset, lineNumber: lineNumber);
    if (!identities.add((asset.assetId, asset.assetVersion))) {
      _throwInvalidPayload(lineNumber, 'Duplicate graphic asset identity');
    }
    final blobId = _graphicAssetBlobId(
      width: asset.width,
      height: asset.height,
      rgba: asset.rgba,
    );
    final existing = blobs[blobId];
    if (existing != null) {
      if (existing.width != asset.width ||
          existing.height != asset.height ||
          !_bytesEqual(existing.rgba, asset.rgba)) {
        _throwInvalidPayload(
          lineNumber,
          'Graphic asset content hash collision',
        );
      }
      continue;
    }
    totalBytes += asset.rgba.length;
    if (totalBytes > terminalRecordingGraphicAssetMaxBytes) {
      _throwInvalidPayload(
        lineNumber,
        'Graphic asset bytes exceed $terminalRecordingGraphicAssetMaxBytes',
      );
    }
    blobs[blobId] = _TerminalRecordingGraphicAssetBlob(
      blobId: blobId,
      width: asset.width,
      height: asset.height,
      rgba: asset.rgba,
    );
  }

  final records = <Map<String, Object?>>[];
  final sortedBlobs = blobs.values.toList(growable: false)
    ..sort((left, right) => left.blobId.compareTo(right.blobId));
  for (final blob in sortedBlobs) {
    records.add(<String, Object?>{
      'record_type': 'graphic_asset_blob',
      'schema_version': recording.metadata.schemaVersion,
      'blob_id': blob.blobId,
      'width': blob.width,
      'height': blob.height,
      'rgba_base64': base64Encode(blob.rgba),
    });
  }
  for (final asset in assets) {
    records.add(<String, Object?>{
      'record_type': 'graphic_asset',
      'schema_version': recording.metadata.schemaVersion,
      'session_id': recording.metadata.sessionId,
      'asset_id': asset.assetId,
      'asset_version': asset.assetVersion,
      'blob_id': _graphicAssetBlobId(
        width: asset.width,
        height: asset.height,
        rgba: asset.rgba,
      ),
    });
  }
  return records;
}

_TerminalRecordingGraphicAssetBlob _decodeGraphicAssetBlob(
  Map<String, Object?> json, {
  required TerminalRecordingMetadata metadata,
  required int lineNumber,
}) {
  _validateGraphicAssetRecordSchema(
    json,
    metadata: metadata,
    lineNumber: lineNumber,
  );
  final blobId = json['blob_id'];
  final width = json['width'];
  final height = json['height'];
  final encoded = json['rgba_base64'];
  if (blobId is! String ||
      !_isGraphicAssetBlobId(blobId) ||
      !_isPositiveInt(width) ||
      !_isPositiveInt(height) ||
      encoded is! String ||
      encoded.length > _terminalRecordingGraphicAssetMaxBase64Bytes) {
    _throwInvalidPayload(
      lineNumber,
      'Graphic asset blob fields are invalid or exceed bounds',
    );
  }
  final Uint8List rgba;
  try {
    rgba = base64Decode(encoded);
  } on FormatException {
    _throwInvalidPayload(
      lineNumber,
      'Graphic asset rgba_base64 must contain valid base64',
    );
  }
  final asset = TerminalRecordingGraphicAsset(
    assetId: 1,
    assetVersion: 1,
    width: width! as int,
    height: height! as int,
    rgba: rgba,
  );
  _validateGraphicAsset(asset, lineNumber: lineNumber);
  final expectedBlobId = _graphicAssetBlobId(
    width: asset.width,
    height: asset.height,
    rgba: asset.rgba,
  );
  if (blobId != expectedBlobId) {
    _throwInvalidPayload(
      lineNumber,
      'Graphic asset blob SHA-256 does not match its dimensions and bytes',
    );
  }
  return _TerminalRecordingGraphicAssetBlob(
    blobId: blobId,
    width: asset.width,
    height: asset.height,
    rgba: asset.rgba,
  );
}

TerminalRecordingGraphicAsset _decodeGraphicAssetReference(
  Map<String, Object?> json, {
  required TerminalRecordingMetadata metadata,
  required Map<String, _TerminalRecordingGraphicAssetBlob> blobs,
  required int lineNumber,
}) {
  _validateGraphicAssetRecordSchema(
    json,
    metadata: metadata,
    lineNumber: lineNumber,
  );
  final sessionId = json['session_id'];
  final assetId = json['asset_id'];
  final assetVersion = json['asset_version'];
  final blobId = json['blob_id'];
  if (sessionId != metadata.sessionId ||
      !_isPositiveInt(assetId) ||
      !_isPositiveInt(assetVersion) ||
      blobId is! String ||
      !_isGraphicAssetBlobId(blobId)) {
    _throwInvalidPayload(
      lineNumber,
      'Graphic asset reference identity is invalid',
    );
  }
  final blob = blobs[blobId];
  if (blob == null) {
    _throwInvalidPayload(
      lineNumber,
      'Graphic asset reference names a missing blob',
    );
  }
  return TerminalRecordingGraphicAsset._fromOwnedRgba(
    assetId: assetId! as int,
    assetVersion: assetVersion! as int,
    width: blob.width,
    height: blob.height,
    rgba: blob.rgba,
  );
}

void _validateGraphicAssetRecordSchema(
  Map<String, Object?> json, {
  required TerminalRecordingMetadata metadata,
  required int lineNumber,
}) {
  final schemaVersion = _schemaVersion(json, lineNumber: lineNumber);
  if (schemaVersion != metadata.schemaVersion ||
      schemaVersion < terminalRecordingCheckpointSchemaVersion) {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.unsupportedSchemaVersion,
      message: 'Graphic asset records require matching recording schema v2',
      lineNumber: lineNumber,
    );
  }
}

void _validateGraphicAsset(
  TerminalRecordingGraphicAsset asset, {
  required int lineNumber,
}) {
  final expectedBytes = asset.width * asset.height * 4;
  if (asset.assetId <= 0 ||
      asset.assetVersion <= 0 ||
      asset.width <= 0 ||
      asset.height <= 0 ||
      expectedBytes > terminalRecordingGraphicAssetMaxBytes ||
      asset.rgba.length != expectedBytes) {
    _throwInvalidPayload(
      lineNumber,
      'Graphic asset identity, dimensions or RGBA byte length is invalid',
    );
  }
}

String _graphicAssetBlobId({
  required int width,
  required int height,
  required List<int> rgba,
}) {
  final collector = _TerminalRecordingDigestCollector();
  final sink = sha256.startChunkedConversion(collector);
  sink.add(utf8.encode('$width:$height:'));
  sink.add(rgba);
  sink.close();
  return 'sha256:${collector.digest}';
}

bool _isGraphicAssetBlobId(String value) =>
    RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(value);

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

const int _terminalRecordingGraphicAssetMaxBase64Bytes =
    ((terminalRecordingGraphicAssetMaxBytes + 2) ~/ 3) * 4;

final class _TerminalRecordingGraphicAssetBlob {
  const _TerminalRecordingGraphicAssetBlob({
    required this.blobId,
    required this.width,
    required this.height,
    required this.rgba,
  });

  final String blobId;
  final int width;
  final int height;
  final Uint8List rgba;
}

final class _TerminalRecordingDigestCollector implements Sink<Digest> {
  Digest? _digest;

  Digest get digest => _digest!;

  @override
  void add(Digest data) {
    if (_digest != null) {
      throw StateError('SHA-256 conversion emitted more than one digest');
    }
    _digest = data;
  }

  @override
  void close() {}
}

Map<String, Object?> _decodeLine(String line, {required int lineNumber}) {
  if (line.trim().isEmpty) {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.invalidRecord,
      message: 'Recording lines must not be empty',
      lineNumber: lineNumber,
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.invalidJson,
      message: 'Recording line is not valid JSON',
      lineNumber: lineNumber,
    );
  }
  final json = _stringKeyedMap(decoded);
  if (json == null) {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.invalidRecord,
      message: 'Recording line must be a JSON object',
      lineNumber: lineNumber,
    );
  }
  return json;
}

TerminalRecordingMetadata _decodeMetadata(
  Map<String, Object?> json, {
  required int lineNumber,
}) {
  if (json['record_type'] != 'metadata') {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.missingMetadata,
      message: 'The first recording line must contain metadata',
      lineNumber: lineNumber,
    );
  }
  final schemaVersion = _schemaVersion(json, lineNumber: lineNumber);
  final sessionId = _requiredSessionId(json, lineNumber: lineNumber);
  final createdAtValue = json['created_at_utc'];
  final createdAtUtc = createdAtValue is String
      ? DateTime.tryParse(createdAtValue)
      : null;
  if (createdAtUtc == null || !createdAtUtc.isUtc) {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.invalidRecord,
      message: 'created_at_utc must be an ISO-8601 UTC timestamp',
      lineNumber: lineNumber,
    );
  }
  final inputPolicy = switch (json['input_policy']) {
    'record' => TerminalRecordingInputPolicy.record,
    'redact' => TerminalRecordingInputPolicy.redact,
    _ => null,
  };
  if (inputPolicy == null) {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.invalidRecord,
      message: 'input_policy must be record or redact',
      lineNumber: lineNumber,
    );
  }
  return TerminalRecordingMetadata(
    schemaVersion: schemaVersion,
    sessionId: sessionId,
    createdAtUtc: createdAtUtc,
    inputPolicy: inputPolicy,
  );
}

TerminalRecordingEvent _decodeEvent(
  Map<String, Object?> json, {
  required int lineNumber,
}) {
  if (json['record_type'] != 'event') {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.invalidRecord,
      message: 'Expected an event recording line',
      lineNumber: lineNumber,
    );
  }
  final schemaVersion = _schemaVersion(json, lineNumber: lineNumber);
  final sessionId = _requiredSessionId(json, lineNumber: lineNumber);
  final sequence = json['sequence'];
  if (sequence is! int || sequence < 0) {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.invalidSequence,
      message: 'sequence must be a non-negative integer',
      lineNumber: lineNumber,
    );
  }
  final offsetMicros = json['monotonic_offset_micros'];
  if (offsetMicros is! int || offsetMicros < 0) {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.invalidMonotonicOffset,
      message: 'monotonic_offset_micros must be a non-negative integer',
      lineNumber: lineNumber,
    );
  }
  final kind = _eventKindFromName(
    json['event_kind'],
    schemaVersion: schemaVersion,
  );
  if (kind == null) {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.unsupportedEventKind,
      message:
          'event_kind is not supported by recording schema v$schemaVersion',
      lineNumber: lineNumber,
    );
  }
  final payload = _stringKeyedMap(json['payload']);
  if (payload == null) {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.invalidPayload,
      message: 'payload must be a JSON object',
      lineNumber: lineNumber,
    );
  }
  return TerminalRecordingEvent._(
    schemaVersion: schemaVersion,
    sessionId: sessionId,
    sequence: sequence,
    monotonicOffset: Duration(microseconds: offsetMicros),
    kind: kind,
    payload: payload,
  );
}

void _validateMetadata(
  TerminalRecordingMetadata metadata, {
  required int lineNumber,
}) {
  if (!_isSupportedSchemaVersion(metadata.schemaVersion)) {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.unsupportedSchemaVersion,
      message: 'Unsupported recording schema version ${metadata.schemaVersion}',
      lineNumber: lineNumber,
    );
  }
  if (metadata.sessionId.trim().isEmpty) {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.invalidRecord,
      message: 'session_id must not be empty',
      lineNumber: lineNumber,
    );
  }
}

void _validateEvent(
  TerminalRecordingEvent event, {
  required TerminalRecordingMetadata metadata,
  required int expectedSequence,
  required int previousOffsetMicros,
  required int lineNumber,
}) {
  if (!_isSupportedSchemaVersion(event.schemaVersion)) {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.unsupportedSchemaVersion,
      message: 'Unsupported recording schema version ${event.schemaVersion}',
      lineNumber: lineNumber,
    );
  }
  if (event.schemaVersion != metadata.schemaVersion) {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.unsupportedSchemaVersion,
      message: 'Event schema version does not match recording metadata',
      lineNumber: lineNumber,
    );
  }
  if (event.sessionId != metadata.sessionId) {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.sessionMismatch,
      message: 'Event session_id does not match recording metadata',
      lineNumber: lineNumber,
    );
  }
  if (event.sequence != expectedSequence) {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.invalidSequence,
      message: 'Expected sequence $expectedSequence, got ${event.sequence}',
      lineNumber: lineNumber,
    );
  }
  final offsetMicros = event.monotonicOffset.inMicroseconds;
  if (offsetMicros < 0 || offsetMicros < previousOffsetMicros) {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.invalidMonotonicOffset,
      message: 'Event monotonic offsets must be non-negative and ordered',
      lineNumber: lineNumber,
    );
  }
  _validatePayload(
    event,
    inputPolicy: metadata.inputPolicy,
    lineNumber: lineNumber,
  );
}

void _validatePayload(
  TerminalRecordingEvent event, {
  required TerminalRecordingInputPolicy inputPolicy,
  required int lineNumber,
}) {
  final payload = event.payload;
  switch (event.kind) {
    case TerminalRecordingEventKind.sessionStarted:
      if (!_isNonEmptyString(payload['terminal_emulation']) ||
          !_isPositiveInt(payload['cols']) ||
          !_isPositiveInt(payload['rows'])) {
        _throwInvalidPayload(
          lineNumber,
          'session_started requires terminal_emulation, cols and rows',
        );
      }
    case TerminalRecordingEventKind.ptyOutput:
      _validatedBytes(payload, lineNumber: lineNumber);
    case TerminalRecordingEventKind.userInput:
      if (inputPolicy == TerminalRecordingInputPolicy.record) {
        if (payload['redacted'] == true) {
          _throwInvalidPayload(
            lineNumber,
            'record input policy requires user input bytes',
          );
        }
        _validatedBytes(payload, lineNumber: lineNumber);
      } else {
        final byteLength = payload['byte_length'];
        if (payload['redacted'] != true ||
            byteLength is! int ||
            byteLength < 0 ||
            payload.containsKey('bytes_base64')) {
          _throwInvalidPayload(
            lineNumber,
            'redact input policy requires only a non-negative byte_length',
          );
        }
      }
    case TerminalRecordingEventKind.resize:
      if (!_isPositiveInt(payload['cols']) ||
          !_isPositiveInt(payload['rows']) ||
          !_isNonNegativeInt(payload['pixel_width']) ||
          !_isNonNegativeInt(payload['pixel_height']) ||
          !_isNonNegativeInt(payload['cell_width']) ||
          !_isNonNegativeInt(payload['cell_height'])) {
        _throwInvalidPayload(
          lineNumber,
          'resize dimensions must be positive cells and non-negative pixels',
        );
      }
    case TerminalRecordingEventKind.sessionExited:
      if (payload['exit_code'] != null && payload['exit_code'] is! int) {
        _throwInvalidPayload(
          lineNumber,
          'exit_code must be an integer or null',
        );
      }
    case TerminalRecordingEventKind.checkpoint:
      final checkpointId = payload['checkpoint_id'];
      final sourceSequence = payload['source_sequence'];
      if (event.schemaVersion < terminalRecordingCheckpointSchemaVersion ||
          checkpointId is! String ||
          checkpointId.trim().isEmpty ||
          utf8.encode(checkpointId).length > 128 ||
          sourceSequence is! int ||
          sourceSequence < 0 ||
          sourceSequence >= event.sequence) {
        _throwInvalidPayload(
          lineNumber,
          'checkpoint requires a bounded checkpoint_id and an earlier source_sequence',
        );
      }
    case TerminalRecordingEventKind.shellSemantic:
      final semanticKind = _semanticKindFromName(payload['semantic_kind']);
      if (event.schemaVersion < terminalRecordingSemanticSchemaVersion ||
          semanticKind == null ||
          !_isOptionalBoundedString(payload['command'], 512) ||
          !_isOptionalBoundedString(payload['cwd'], 1024) ||
          !_isOptionalBoundedString(payload['hostname'], 255) ||
          (payload['exit_code'] != null && payload['exit_code'] is! int) ||
          payload['remote'] is! bool) {
        _throwInvalidPayload(
          lineNumber,
          'shell_semantic requires bounded semantic metadata',
        );
      }
  }
}

Map<String, Object?> _canonicalPayload(
  TerminalRecordingEvent event, {
  required int lineNumber,
}) {
  final payload = event.payload;
  return switch (event.kind) {
    TerminalRecordingEventKind.sessionStarted => <String, Object?>{
      'terminal_emulation': payload['terminal_emulation'],
      'cols': payload['cols'],
      'rows': payload['rows'],
    },
    TerminalRecordingEventKind.ptyOutput => <String, Object?>{
      'bytes_base64': base64Encode(
        _validatedBytes(payload, lineNumber: lineNumber),
      ),
    },
    TerminalRecordingEventKind.userInput when payload['redacted'] == true =>
      <String, Object?>{
        'byte_length': payload['byte_length'],
        'redacted': true,
      },
    TerminalRecordingEventKind.userInput => <String, Object?>{
      'bytes_base64': base64Encode(
        _validatedBytes(payload, lineNumber: lineNumber),
      ),
    },
    TerminalRecordingEventKind.resize => <String, Object?>{
      'cols': payload['cols'],
      'rows': payload['rows'],
      'pixel_width': payload['pixel_width'],
      'pixel_height': payload['pixel_height'],
      'cell_width': payload['cell_width'],
      'cell_height': payload['cell_height'],
    },
    TerminalRecordingEventKind.sessionExited => <String, Object?>{
      'exit_code': payload['exit_code'],
    },
    TerminalRecordingEventKind.checkpoint => <String, Object?>{
      'checkpoint_id': payload['checkpoint_id'],
      'source_sequence': payload['source_sequence'],
    },
    TerminalRecordingEventKind.shellSemantic => <String, Object?>{
      'semantic_kind': payload['semantic_kind'],
      if (payload['command'] != null) 'command': payload['command'],
      if (payload['cwd'] != null) 'cwd': payload['cwd'],
      if (payload['hostname'] != null) 'hostname': payload['hostname'],
      if (payload['exit_code'] != null) 'exit_code': payload['exit_code'],
      'remote': payload['remote'],
    },
  };
}

Uint8List _validatedBytes(
  Map<String, Object?> payload, {
  required int lineNumber,
}) {
  final encoded = payload['bytes_base64'];
  if (encoded is! String) {
    _throwInvalidPayload(lineNumber, 'bytes_base64 must be a string');
  }
  try {
    return base64Decode(encoded);
  } on FormatException {
    _throwInvalidPayload(lineNumber, 'bytes_base64 must contain valid base64');
  }
}

int _schemaVersion(Map<String, Object?> json, {required int lineNumber}) {
  final version = json['schema_version'];
  if (version is! int || !_isSupportedSchemaVersion(version)) {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.unsupportedSchemaVersion,
      message: 'Unsupported recording schema version $version',
      lineNumber: lineNumber,
    );
  }
  return version;
}

String _requiredSessionId(
  Map<String, Object?> json, {
  required int lineNumber,
}) {
  final sessionId = json['session_id'];
  if (!_isNonEmptyString(sessionId)) {
    throw TerminalRecordingFormatException(
      code: TerminalRecordingFormatErrorCode.invalidRecord,
      message: 'session_id must be a non-empty string',
      lineNumber: lineNumber,
    );
  }
  return sessionId! as String;
}

Never _throwInvalidPayload(int lineNumber, String message) {
  throw TerminalRecordingFormatException(
    code: TerminalRecordingFormatErrorCode.invalidPayload,
    message: message,
    lineNumber: lineNumber,
  );
}

Never _throwInvalidRecord(int lineNumber, String message) {
  throw TerminalRecordingFormatException(
    code: TerminalRecordingFormatErrorCode.invalidRecord,
    message: message,
    lineNumber: lineNumber,
  );
}

Map<String, Object?>? _stringKeyedMap(Object? value) {
  if (value is! Map<Object?, Object?>) {
    return null;
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      return null;
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

bool _isNonEmptyString(Object? value) {
  return value is String && value.trim().isNotEmpty;
}

bool _isPositiveInt(Object? value) => value is int && value > 0;

bool _isNonNegativeInt(Object? value) => value is int && value >= 0;

String _inputPolicyName(TerminalRecordingInputPolicy policy) {
  return switch (policy) {
    TerminalRecordingInputPolicy.record => 'record',
    TerminalRecordingInputPolicy.redact => 'redact',
  };
}

String _eventKindName(TerminalRecordingEventKind kind) {
  return switch (kind) {
    TerminalRecordingEventKind.sessionStarted => 'session_started',
    TerminalRecordingEventKind.ptyOutput => 'pty_output',
    TerminalRecordingEventKind.userInput => 'user_input',
    TerminalRecordingEventKind.resize => 'resize',
    TerminalRecordingEventKind.sessionExited => 'session_exited',
    TerminalRecordingEventKind.checkpoint => 'checkpoint',
    TerminalRecordingEventKind.shellSemantic => 'shell_semantic',
  };
}

TerminalRecordingEventKind? _eventKindFromName(
  Object? value, {
  required int schemaVersion,
}) {
  return switch (value) {
    'session_started' => TerminalRecordingEventKind.sessionStarted,
    'pty_output' => TerminalRecordingEventKind.ptyOutput,
    'user_input' => TerminalRecordingEventKind.userInput,
    'resize' => TerminalRecordingEventKind.resize,
    'session_exited' => TerminalRecordingEventKind.sessionExited,
    'checkpoint'
        when schemaVersion >= terminalRecordingCheckpointSchemaVersion =>
      TerminalRecordingEventKind.checkpoint,
    'shell_semantic'
        when schemaVersion >= terminalRecordingSemanticSchemaVersion =>
      TerminalRecordingEventKind.shellSemantic,
    _ => null,
  };
}

bool _isSupportedSchemaVersion(int version) {
  return version == terminalRecordingSchemaVersion ||
      version == terminalRecordingCheckpointSchemaVersion ||
      version == terminalRecordingSemanticSchemaVersion;
}

String _semanticKindName(TerminalRecordingSemanticKind kind) {
  return switch (kind) {
    TerminalRecordingSemanticKind.commandStarted => 'command_started',
    TerminalRecordingSemanticKind.commandFinished => 'command_finished',
    TerminalRecordingSemanticKind.directoryChanged => 'directory_changed',
    TerminalRecordingSemanticKind.prompt => 'prompt',
    TerminalRecordingSemanticKind.remoteSessionStarted =>
      'remote_session_started',
    TerminalRecordingSemanticKind.remoteSessionFinished =>
      'remote_session_finished',
  };
}

TerminalRecordingSemanticKind? _semanticKindFromName(Object? value) {
  return switch (value) {
    'command_started' => TerminalRecordingSemanticKind.commandStarted,
    'command_finished' => TerminalRecordingSemanticKind.commandFinished,
    'directory_changed' => TerminalRecordingSemanticKind.directoryChanged,
    'prompt' => TerminalRecordingSemanticKind.prompt,
    'remote_session_started' =>
      TerminalRecordingSemanticKind.remoteSessionStarted,
    'remote_session_finished' =>
      TerminalRecordingSemanticKind.remoteSessionFinished,
    _ => null,
  };
}

bool _isOptionalBoundedString(Object? value, int maxBytes) {
  return value == null ||
      (value is String &&
          value.trim().isNotEmpty &&
          utf8.encode(value).length <= maxBytes);
}

/// Deterministically upgrades a validated Recording v1/v2 stream with
/// persisted checkpoint markers. Native replay materializes each marker into
/// a complete terminal snapshot when that point in the stream is reached.
final class TerminalRecordingCheckpointPlanner {
  const TerminalRecordingCheckpointPlanner({
    this.playableEventsPerCheckpoint = 256,
    this.maxCheckpoints = 64,
  });

  final int playableEventsPerCheckpoint;
  final int maxCheckpoints;

  TerminalRecording addCheckpoints(TerminalRecording recording) {
    if (playableEventsPerCheckpoint < 1 || playableEventsPerCheckpoint > 4096) {
      throw ArgumentError.value(
        playableEventsPerCheckpoint,
        'playableEventsPerCheckpoint',
        'must be between 1 and 4096',
      );
    }
    if (maxCheckpoints < 2 || maxCheckpoints > 64) {
      throw ArgumentError.value(
        maxCheckpoints,
        'maxCheckpoints',
        'must be between 2 and 64',
      );
    }

    const codec = TerminalRecordingCodec();
    final validated = codec.decode(codec.encode(recording));
    final sourceEvents = validated.events
        .where((event) => event.kind != TerminalRecordingEventKind.checkpoint)
        .toList(growable: false);
    if (sourceEvents.isEmpty ||
        sourceEvents.first.kind != TerminalRecordingEventKind.sessionStarted) {
      throw ArgumentError.value(
        recording,
        'recording',
        'must begin with session_started',
      );
    }

    final checkpointSources = <int>[0];
    final boundary = _TerminalRecordingCheckpointBoundary();
    var playableSinceCheckpoint = 0;
    int? lastSafePlayableSource;
    for (
      var sourceSequence = 1;
      sourceSequence < sourceEvents.length;
      sourceSequence += 1
    ) {
      final kind = sourceEvents[sourceSequence].kind;
      if (kind != TerminalRecordingEventKind.ptyOutput &&
          kind != TerminalRecordingEventKind.resize) {
        continue;
      }
      if (kind == TerminalRecordingEventKind.ptyOutput) {
        boundary.add(sourceEvents[sourceSequence].bytes!);
      }
      playableSinceCheckpoint += 1;
      if (!boundary.isSafe) {
        continue;
      }
      lastSafePlayableSource = sourceSequence;
      if (playableSinceCheckpoint >= playableEventsPerCheckpoint) {
        checkpointSources.add(sourceSequence);
        playableSinceCheckpoint = 0;
      }
    }
    if (lastSafePlayableSource != null &&
        checkpointSources.last != lastSafePlayableSource) {
      checkpointSources.add(lastSafePlayableSource);
    }
    if (checkpointSources.length > maxCheckpoints) {
      throw ArgumentError.value(
        checkpointSources.length,
        'recording',
        'requires more than $maxCheckpoints checkpoints under this policy',
      );
    }

    final targetSchemaVersion =
        validated.metadata.schemaVersion <
            terminalRecordingCheckpointSchemaVersion
        ? terminalRecordingCheckpointSchemaVersion
        : validated.metadata.schemaVersion;
    final plannedEvents = <TerminalRecordingEvent>[];
    final checkpointSourceSet = checkpointSources.toSet();
    for (
      var sourceSequence = 0;
      sourceSequence < sourceEvents.length;
      sourceSequence += 1
    ) {
      final event = sourceEvents[sourceSequence];
      plannedEvents.add(
        TerminalRecordingEvent._(
          schemaVersion: targetSchemaVersion,
          sessionId: event.sessionId,
          sequence: plannedEvents.length,
          monotonicOffset: event.monotonicOffset,
          kind: event.kind,
          payload: event.payload,
        ),
      );
      if (checkpointSourceSet.contains(sourceSequence)) {
        plannedEvents.add(
          TerminalRecordingEvent.checkpoint(
            schemaVersion: targetSchemaVersion,
            sessionId: event.sessionId,
            sequence: plannedEvents.length,
            monotonicOffset: event.monotonicOffset,
            checkpointId: 'checkpoint-$sourceSequence',
            sourceSequence: sourceSequence,
          ),
        );
      }
    }

    return TerminalRecording(
      metadata: TerminalRecordingMetadata(
        schemaVersion: targetSchemaVersion,
        sessionId: validated.metadata.sessionId,
        createdAtUtc: validated.metadata.createdAtUtc,
        inputPolicy: validated.metadata.inputPolicy,
      ),
      graphicAssets: validated.graphicAssets,
      events: plannedEvents,
    );
  }
}

enum _TerminalRecordingCheckpointBoundaryState {
  ground,
  escape,
  csi,
  osc,
  controlString,
  oscEscape,
  controlStringEscape,
}

final class _TerminalRecordingCheckpointBoundary {
  _TerminalRecordingCheckpointBoundaryState _state =
      _TerminalRecordingCheckpointBoundaryState.ground;

  bool get isSafe => _state == _TerminalRecordingCheckpointBoundaryState.ground;

  void add(List<int> bytes) {
    for (final byte in bytes) {
      _addByte(byte);
    }
  }

  void _addByte(int byte) {
    if (byte == 0x18 || byte == 0x1a || byte == 0x9c) {
      _state = _TerminalRecordingCheckpointBoundaryState.ground;
      return;
    }
    switch (_state) {
      case _TerminalRecordingCheckpointBoundaryState.ground:
        _state = switch (byte) {
          0x1b => _TerminalRecordingCheckpointBoundaryState.escape,
          0x9b => _TerminalRecordingCheckpointBoundaryState.csi,
          0x9d => _TerminalRecordingCheckpointBoundaryState.osc,
          0x90 ||
          0x98 ||
          0x9e ||
          0x9f => _TerminalRecordingCheckpointBoundaryState.controlString,
          _ => _TerminalRecordingCheckpointBoundaryState.ground,
        };
      case _TerminalRecordingCheckpointBoundaryState.escape:
        _state = switch (byte) {
          0x1b => _TerminalRecordingCheckpointBoundaryState.escape,
          0x5b => _TerminalRecordingCheckpointBoundaryState.csi,
          0x5d => _TerminalRecordingCheckpointBoundaryState.osc,
          0x50 ||
          0x58 ||
          0x5e ||
          0x5f => _TerminalRecordingCheckpointBoundaryState.controlString,
          >= 0x20 && <= 0x2f =>
            _TerminalRecordingCheckpointBoundaryState.escape,
          _ => _TerminalRecordingCheckpointBoundaryState.ground,
        };
      case _TerminalRecordingCheckpointBoundaryState.csi:
        if (byte == 0x1b) {
          _state = _TerminalRecordingCheckpointBoundaryState.escape;
        } else if (byte >= 0x40 && byte <= 0x7e) {
          _state = _TerminalRecordingCheckpointBoundaryState.ground;
        }
      case _TerminalRecordingCheckpointBoundaryState.osc:
        if (byte == 0x07) {
          _state = _TerminalRecordingCheckpointBoundaryState.ground;
        } else if (byte == 0x1b) {
          _state = _TerminalRecordingCheckpointBoundaryState.oscEscape;
        }
      case _TerminalRecordingCheckpointBoundaryState.controlString:
        if (byte == 0x1b) {
          _state =
              _TerminalRecordingCheckpointBoundaryState.controlStringEscape;
        }
      case _TerminalRecordingCheckpointBoundaryState.oscEscape:
        if (byte == 0x5c || byte == 0x07) {
          _state = _TerminalRecordingCheckpointBoundaryState.ground;
        } else if (byte != 0x1b) {
          _state = _TerminalRecordingCheckpointBoundaryState.osc;
        }
      case _TerminalRecordingCheckpointBoundaryState.controlStringEscape:
        if (byte == 0x5c) {
          _state = _TerminalRecordingCheckpointBoundaryState.ground;
        } else if (byte != 0x1b) {
          _state = _TerminalRecordingCheckpointBoundaryState.controlString;
        }
    }
  }
}
