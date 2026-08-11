import 'dart:ui' show Color, Size;

import '../terminal/terminal.dart' as terminal;

const int _fingerprintMask = 0x3fffffff;

int _mixFingerprint(int hash, int value) {
  return ((hash ^ value) * 16777619) & _fingerprintMask;
}

int _mixFingerprintString(int hash, String? value) {
  if (value == null) {
    return _mixFingerprint(hash, -1);
  }
  var mixed = _mixFingerprint(hash, value.length);
  for (final codeUnit in value.codeUnits) {
    mixed = _mixFingerprint(mixed, codeUnit);
  }
  return mixed;
}

int _mixFingerprintColor(int hash, Color? value) {
  return _mixFingerprint(hash, value?.toARGB32() ?? -1);
}

class InstantReplayFrame {
  const InstantReplayFrame({
    required this.sessionId,
    required this.capturedAt,
    required this.frame,
    required this.snapshot,
    this.viewportLogicalSize,
    this.viewportPixelSize,
    this.devicePixelRatio,
    this.windowContentSize,
    this.windowFrameSize,
  });

  final String sessionId;
  final DateTime capturedAt;
  final terminal.TerminalFrameDiff frame;
  final terminal.TerminalFrameDiff snapshot;
  final Size? viewportLogicalSize;
  final Size? viewportPixelSize;
  final double? devicePixelRatio;
  final Size? windowContentSize;
  final Size? windowFrameSize;

  String get text => _textForFrame(snapshot);
}

class InstantReplaySemanticEvent {
  const InstantReplaySemanticEvent({
    required this.sessionId,
    required this.capturedAt,
    required this.kind,
    this.command,
    this.cwd,
    this.hostname,
    this.exitCode,
    this.remote = false,
  });

  final String sessionId;
  final DateTime capturedAt;
  final terminal.TerminalRecordingSemanticKind kind;
  final String? command;
  final String? cwd;
  final String? hostname;
  final int? exitCode;
  final bool remote;
}

final class _StoredInstantReplayFrame {
  const _StoredInstantReplayFrame({
    required this.value,
    required this.fingerprint,
    required this.estimatedBytes,
  });

  final InstantReplayFrame value;
  final int fingerprint;
  final int estimatedBytes;

  _StoredInstantReplayFrame withValue(InstantReplayFrame nextValue) {
    return _StoredInstantReplayFrame(
      value: nextValue,
      fingerprint: fingerprint,
      estimatedBytes: estimatedBytes,
    );
  }
}

class InstantReplayStore {
  InstantReplayStore({
    this.frameLimit = 60,
    this.byteBudget = 16 * 1024 * 1024,
    this.minimumCaptureInterval = Duration.zero,
    DateTime Function()? now,
    void Function()? onFrameMaterialized,
    void Function(int byteLength)? onInlineImageFingerprint,
  }) : _now = now ?? DateTime.now,
       _onFrameMaterialized = onFrameMaterialized,
       _onInlineImageFingerprint = onInlineImageFingerprint;

  final int frameLimit;
  final int byteBudget;
  final Duration minimumCaptureInterval;
  final DateTime Function() _now;
  final void Function()? _onFrameMaterialized;
  final void Function(int byteLength)? _onInlineImageFingerprint;
  final Map<String, List<_StoredInstantReplayFrame>> _framesBySession =
      <String, List<_StoredInstantReplayFrame>>{};
  final Map<String, terminal.TerminalViewportState> _stateBySession =
      <String, terminal.TerminalViewportState>{};
  final Map<String, int> _stateBytesBySession = <String, int>{};
  final Map<String, DateTime> _lastMaterializedAtBySession =
      <String, DateTime>{};
  final Map<String, List<InstantReplaySemanticEvent>> _semanticsBySession =
      <String, List<InstantReplaySemanticEvent>>{};
  final Map<String, int> _semanticBytesBySession = <String, int>{};
  int _estimatedRetainedBytes = 0;

  int get estimatedRetainedBytes => _estimatedRetainedBytes;

  int get retainedSessionCount =>
      <String>{..._framesBySession.keys, ..._semanticsBySession.keys}.length;

  List<InstantReplayFrame> framesFor(String sessionId) {
    return List<InstantReplayFrame>.unmodifiable(
      (_framesBySession[sessionId] ?? const <_StoredInstantReplayFrame>[]).map(
        (stored) => stored.value,
      ),
    );
  }

  List<InstantReplayFrame> framesForReplay(String sessionId) {
    return List<InstantReplayFrame>.unmodifiable(
      (_framesBySession[sessionId] ?? const <_StoredInstantReplayFrame>[])
          .reversed
          .map((stored) => stored.value),
    );
  }

  List<InstantReplaySemanticEvent> semanticsForReplay(String sessionId) {
    final frames = _framesBySession[sessionId];
    final semantics = _semanticsBySession[sessionId];
    if (frames == null ||
        frames.isEmpty ||
        semantics == null ||
        semantics.isEmpty) {
      return const <InstantReplaySemanticEvent>[];
    }
    final oldest = frames.last.value.capturedAt;
    final newest = frames.first.value.capturedAt;
    return List<InstantReplaySemanticEvent>.unmodifiable(
      semantics.where(
        (event) =>
            !event.capturedAt.isBefore(oldest) &&
            !event.capturedAt.isAfter(newest),
      ),
    );
  }

  void recordSemantic(
    String sessionId, {
    required terminal.TerminalRecordingSemanticKind kind,
    String? command,
    String? cwd,
    String? hostname,
    int? exitCode,
    bool remote = false,
  }) {
    if (frameLimit <= 0 || byteBudget <= 0) {
      clear(sessionId);
      return;
    }
    final events = _semanticsBySession.putIfAbsent(
      sessionId,
      () => <InstantReplaySemanticEvent>[],
    );
    final candidate = InstantReplaySemanticEvent(
      sessionId: sessionId,
      capturedAt: _now(),
      kind: kind,
      command: command,
      cwd: cwd,
      hostname: hostname,
      exitCode: exitCode,
      remote: remote,
    );
    if (events.isNotEmpty) {
      final previous = events.last;
      final sameCommand =
          previous.command == candidate.command ||
          previous.command == null ||
          candidate.command == null;
      if (previous.kind == candidate.kind &&
          sameCommand &&
          previous.remote == candidate.remote &&
          candidate.capturedAt.difference(previous.capturedAt) <
              const Duration(milliseconds: 80)) {
        final replacement = InstantReplaySemanticEvent(
          sessionId: sessionId,
          capturedAt: previous.capturedAt,
          kind: candidate.kind,
          command: candidate.command ?? previous.command,
          cwd: candidate.cwd ?? previous.cwd,
          hostname: candidate.hostname ?? previous.hostname,
          exitCode: candidate.exitCode ?? previous.exitCode,
          remote: candidate.remote,
        );
        final previousBytes = _estimateSemanticBytes(previous);
        final replacementBytes = _estimateSemanticBytes(replacement);
        events[events.length - 1] = replacement;
        _adjustSemanticBytes(sessionId, replacementBytes - previousBytes);
        _enforceByteBudget();
        return;
      }
    }
    events.add(candidate);
    _adjustSemanticBytes(sessionId, _estimateSemanticBytes(candidate));
    final maximumSemanticEvents = frameLimit * 4;
    if (events.length > maximumSemanticEvents) {
      final removeCount = events.length - maximumSemanticEvents;
      for (final event in events.take(removeCount)) {
        _adjustSemanticBytes(sessionId, -_estimateSemanticBytes(event));
      }
      events.removeRange(0, removeCount);
    }
    _enforceByteBudget();
  }

  void record(
    String sessionId,
    terminal.TerminalFrameDiff frame, {
    Size? viewportLogicalSize,
    Size? viewportPixelSize,
    double? devicePixelRatio,
    Size? windowContentSize,
    Size? windowFrameSize,
  }) {
    _recordFrame(
      sessionId,
      frame,
      viewportLogicalSize: viewportLogicalSize,
      viewportPixelSize: viewportPixelSize,
      devicePixelRatio: devicePixelRatio,
      windowContentSize: windowContentSize,
      windowFrameSize: windowFrameSize,
      forceCheckpoint: false,
    );
  }

  /// Materializes the latest accumulated state regardless of sampling cadence.
  ///
  /// Opening replay uses this path so a burst received inside the normal
  /// capture interval cannot leave the replay view on a stale retained frame.
  void checkpoint(
    String sessionId,
    terminal.TerminalFrameDiff frame, {
    Size? viewportLogicalSize,
    Size? viewportPixelSize,
    double? devicePixelRatio,
    Size? windowContentSize,
    Size? windowFrameSize,
  }) {
    _recordFrame(
      sessionId,
      frame,
      viewportLogicalSize: viewportLogicalSize,
      viewportPixelSize: viewportPixelSize,
      devicePixelRatio: devicePixelRatio,
      windowContentSize: windowContentSize,
      windowFrameSize: windowFrameSize,
      forceCheckpoint: true,
    );
  }

  void _recordFrame(
    String sessionId,
    terminal.TerminalFrameDiff frame, {
    required Size? viewportLogicalSize,
    required Size? viewportPixelSize,
    required double? devicePixelRatio,
    required Size? windowContentSize,
    required Size? windowFrameSize,
    required bool forceCheckpoint,
  }) {
    if (!_isRecordableFrame(frame)) {
      return;
    }
    if (frameLimit <= 0 || byteBudget <= 0) {
      clear(sessionId);
      return;
    }
    final capturedAt = _now();
    final previousState = _stateBySession[sessionId];
    final restoredState =
        (previousState ?? terminal.TerminalViewportState.empty).applyFrame(
          frame,
          capturedAt: capturedAt,
        );
    _stateBySession[sessionId] = restoredState;
    final frames = _framesBySession.putIfAbsent(
      sessionId,
      () => <_StoredInstantReplayFrame>[],
    );
    final lastMaterializedAt = _lastMaterializedAtBySession[sessionId];
    final timeSinceMaterialization = lastMaterializedAt == null
        ? null
        : capturedAt.difference(lastMaterializedAt);
    if (!forceCheckpoint &&
        frames.isNotEmpty &&
        minimumCaptureInterval > Duration.zero &&
        timeSinceMaterialization != null &&
        timeSinceMaterialization >= Duration.zero &&
        timeSinceMaterialization < minimumCaptureInterval) {
      // Deltas are normally small. Account their retained payload as a
      // conservative upper bound without walking the accumulated full-screen
      // state or computing a visual fingerprint on this hot path. The next
      // materialized checkpoint replaces it with an exact snapshot estimate.
      _setStateEstimatedBytes(
        sessionId,
        frame.frameKind == terminal.TerminalFrameKind.snapshot ||
                previousState == null
            ? _estimateFrameBytes(restoredState.frame)
            : (_stateBytesBySession[sessionId] ?? 0) +
                  _estimateFrameBytes(frame),
      );
      frames[0] = frames.first.withValue(
        _mergeFrameMetadata(
          frames.first.value,
          viewportLogicalSize: viewportLogicalSize,
          viewportPixelSize: viewportPixelSize,
          devicePixelRatio: devicePixelRatio,
          windowContentSize: windowContentSize,
          windowFrameSize: windowFrameSize,
        ),
      );
      _enforceByteBudget();
      return;
    }
    _lastMaterializedAtBySession[sessionId] = capturedAt;
    _onFrameMaterialized?.call();
    final snapshot = restoredState
        .applySnapshot(restoredState.frame, capturedAt: capturedAt)
        .frame;
    final fingerprint = _frameFingerprint(snapshot);
    final snapshotBytes = _estimateFrameBytes(snapshot);
    _setStateEstimatedBytes(sessionId, snapshotBytes);
    final estimatedBytes = _estimateFrameBytes(frame) + snapshotBytes;
    final latestCapturedAt = frames.isEmpty
        ? null
        : frames.first.value.capturedAt;
    final hasNewSemanticBoundary =
        latestCapturedAt != null &&
        (_semanticsBySession[sessionId]?.any(
              (event) => event.capturedAt.isAfter(latestCapturedAt),
            ) ??
            false);
    if (frames.isNotEmpty &&
        frames.first.fingerprint == fingerprint &&
        !hasNewSemanticBoundary) {
      final previous = frames.first;
      final previousValue = previous.value;
      frames[0] = _StoredInstantReplayFrame(
        value: InstantReplayFrame(
          sessionId: sessionId,
          capturedAt: previousValue.capturedAt,
          frame: frame,
          snapshot: snapshot,
          viewportLogicalSize:
              viewportLogicalSize ?? previousValue.viewportLogicalSize,
          viewportPixelSize:
              viewportPixelSize ?? previousValue.viewportPixelSize,
          devicePixelRatio: devicePixelRatio ?? previousValue.devicePixelRatio,
          windowContentSize:
              windowContentSize ?? previousValue.windowContentSize,
          windowFrameSize: windowFrameSize ?? previousValue.windowFrameSize,
        ),
        fingerprint: fingerprint,
        estimatedBytes: estimatedBytes,
      );
      _estimatedRetainedBytes += estimatedBytes - previous.estimatedBytes;
      _enforceByteBudget();
      return;
    }
    final stored = _StoredInstantReplayFrame(
      value: InstantReplayFrame(
        sessionId: sessionId,
        capturedAt: capturedAt,
        frame: frame,
        snapshot: snapshot,
        viewportLogicalSize: viewportLogicalSize,
        viewportPixelSize: viewportPixelSize,
        devicePixelRatio: devicePixelRatio,
        windowContentSize: windowContentSize,
        windowFrameSize: windowFrameSize,
      ),
      fingerprint: fingerprint,
      estimatedBytes: estimatedBytes,
    );
    frames.insert(0, stored);
    _estimatedRetainedBytes += estimatedBytes;
    if (frames.length > frameLimit) {
      while (frames.length > frameLimit) {
        _removeFrameAt(sessionId, frames.length - 1);
      }
    }
    _pruneSemanticsBeforeOldestFrame(sessionId);
    _enforceByteBudget();
  }

  void clear(String sessionId) {
    final frames = _framesBySession.remove(sessionId);
    if (frames != null) {
      for (final frame in frames) {
        _estimatedRetainedBytes -= frame.estimatedBytes;
      }
    }
    _stateBySession.remove(sessionId);
    _estimatedRetainedBytes -= _stateBytesBySession.remove(sessionId) ?? 0;
    _lastMaterializedAtBySession.remove(sessionId);
    _semanticsBySession.remove(sessionId);
    _estimatedRetainedBytes -= _semanticBytesBySession.remove(sessionId) ?? 0;
    _clampEstimatedBytes();
  }

  void enrichSessionMetadata(
    String sessionId, {
    Size? viewportLogicalSize,
    Size? viewportPixelSize,
    double? devicePixelRatio,
    Size? windowContentSize,
    Size? windowFrameSize,
  }) {
    final frames = _framesBySession[sessionId];
    if (frames == null || frames.isEmpty) {
      return;
    }
    for (var index = 0; index < frames.length; index += 1) {
      final stored = frames[index];
      final existing = stored.value;
      final existingViewportSize = existing.viewportLogicalSize;
      if (viewportLogicalSize == null && existingViewportSize != null) {
        continue;
      }
      if (existingViewportSize != null &&
          viewportLogicalSize != null &&
          existingViewportSize != viewportLogicalSize) {
        continue;
      }
      frames[index] = stored.withValue(
        _mergeFrameMetadata(
          existing,
          viewportLogicalSize: viewportLogicalSize,
          viewportPixelSize: viewportPixelSize,
          devicePixelRatio: devicePixelRatio,
          windowContentSize: windowContentSize,
          windowFrameSize: windowFrameSize,
        ),
      );
    }
  }

  bool _isRecordableFrame(terminal.TerminalFrameDiff frame) {
    return frame.viewportRows > 0 && frame.viewportCols > 0;
  }

  int _frameFingerprint(terminal.TerminalFrameDiff frame) {
    var hash = _mixFingerprint(216613626, frame.viewportRows);
    hash = _mixFingerprint(hash, frame.viewportCols);
    hash = _mixFingerprint(hash, frame.scrollbackOffset);
    hash = _mixFingerprint(hash, frame.scrollbackMaxOffset);
    hash = _mixFingerprint(hash, frame.globalBottomRow ?? -1);
    hash = _mixFingerprint(hash, frame.viewportStartRow);
    hash = _mixFingerprint(hash, frame.viewportRowShift);
    hash = _mixFingerprint(hash, frame.cursor.row);
    hash = _mixFingerprint(hash, frame.cursor.col);
    hash = _mixFingerprint(hash, frame.cursor.visible ? 1 : 0);
    hash = _mixFingerprint(hash, frame.cursor.highlightLine ? 1 : 0);
    hash = _mixFingerprint(hash, frame.cursor.shape?.index ?? -1);
    hash = _mixFingerprint(hash, switch (frame.cursor.blink) {
      true => 1,
      false => 0,
      null => -1,
    });
    final selection = frame.selection;
    hash = _mixFingerprint(hash, selection?.startRow ?? -1);
    hash = _mixFingerprint(hash, selection?.startCol ?? -1);
    hash = _mixFingerprint(hash, selection?.endRow ?? -1);
    hash = _mixFingerprint(hash, selection?.endCol ?? -1);
    hash = _mixFingerprintColor(hash, frame.defaultForeground);
    hash = _mixFingerprintColor(hash, frame.defaultBackground);
    hash = _mixFingerprintColor(hash, frame.cursorColor);
    hash = _mixFingerprintColor(hash, frame.cursorGuideColor);
    hash = _mixFingerprintColor(hash, frame.selectionBackground);
    hash = _mixFingerprintColor(hash, frame.selectionForeground);
    hash = _mixFingerprintColor(hash, frame.linkColor);
    hash = _mixFingerprintColor(hash, frame.cursorTextColor);
    hash = _mixFingerprintColor(hash, frame.tabColor);
    hash = _mixFingerprint(hash, frame.pointerShape?.index ?? -1);
    hash = _mixFingerprintString(hash, frame.windowTitle);
    hash = _mixFingerprintString(hash, frame.windowIconName);
    hash = _mixFingerprintString(hash, frame.fontFamily);
    final modes = frame.modes;
    for (final enabled in <bool>[
      modes.alternateScreen,
      modes.alternateScroll,
      modes.applicationCursor,
      modes.applicationKeypad,
      modes.insertMode,
      modes.originMode,
      modes.lineFeedNewLineMode,
      modes.hideCursor,
      modes.bracketedPaste,
      modes.mimePaste,
      modes.focusTracking,
      modes.charProtected,
      modes.synchronizedOutput,
    ]) {
      hash = _mixFingerprint(hash, enabled ? 1 : 0);
    }
    hash = _mixFingerprintString(hash, modes.mouseMode);
    hash = _mixFingerprintString(hash, modes.mouseEncoding);
    hash = _mixFingerprint(hash, modes.kittyKeyboardFlags);
    var rowXor = 0;
    var rowSum = 0;
    for (final row in frame.rows) {
      var rowHash = _mixFingerprint(216613626, row.index);
      rowHash = _mixFingerprintString(rowHash, row.text);
      rowHash = _mixFingerprint(rowHash, row.wrapped ? 1 : 0);
      rowHash = _mixFingerprint(rowHash, row.sourceRow ?? -1);
      rowHash = _mixFingerprint(rowHash, row.sourceEndRow ?? -1);
      for (final run in row.styleRuns) {
        rowHash = _mixFingerprint(rowHash, run.start);
        rowHash = _mixFingerprint(rowHash, run.end);
        rowHash = _mixFingerprintColor(rowHash, run.foreground);
        rowHash = _mixFingerprintColor(rowHash, run.background);
        rowHash = _mixFingerprintColor(rowHash, run.underlineColor);
        for (final enabled in <bool>[
          run.bold,
          run.dim,
          run.italic,
          run.underline,
          run.blink,
          run.inverse,
        ]) {
          rowHash = _mixFingerprint(rowHash, enabled ? 1 : 0);
        }
      }
      rowXor ^= rowHash;
      rowSum = (rowSum + rowHash) & _fingerprintMask;
    }
    hash = _mixFingerprint(hash, frame.rows.length);
    hash = _mixFingerprint(hash, rowXor);
    hash = _mixFingerprint(hash, rowSum);
    for (final link in frame.hyperlinks) {
      hash = _mixFingerprint(hash, link.row);
      hash = _mixFingerprint(hash, link.startCol);
      hash = _mixFingerprint(hash, link.endCol);
      hash = _mixFingerprintString(hash, link.uri);
      hash = _mixFingerprintString(hash, link.protocolId);
    }
    for (final placement in frame.sizedText) {
      hash = _mixFingerprintString(hash, placement.text);
      hash = _mixFingerprint(hash, placement.row);
      hash = _mixFingerprint(hash, placement.col);
      hash = _mixFingerprint(hash, placement.widthCells);
      hash = _mixFingerprint(hash, placement.heightCells);
      hash = _mixFingerprint(hash, placement.sourceRowOffsetCells);
      hash = _mixFingerprint(hash, placement.visibleHeightCells);
      hash = _mixFingerprint(hash, placement.scale);
      hash = _mixFingerprint(hash, placement.subscaleN);
      hash = _mixFingerprint(hash, placement.subscaleD);
      hash = _mixFingerprint(hash, placement.verticalAlign);
      hash = _mixFingerprint(hash, placement.horizontalAlign);
      hash = _mixFingerprint(hash, placement.naturalWidth ? 1 : 0);
      hash = _mixFingerprintColor(hash, placement.foreground);
      hash = _mixFingerprintColor(hash, placement.background);
      hash = _mixFingerprintColor(hash, placement.underlineColor);
      for (final enabled in <bool>[
        placement.bold,
        placement.dim,
        placement.italic,
        placement.underline,
        placement.blink,
        placement.inverse,
      ]) {
        hash = _mixFingerprint(hash, enabled ? 1 : 0);
      }
    }
    for (final image in frame.inlineImages) {
      hash = _mixFingerprint(hash, image.row);
      hash = _mixFingerprint(hash, image.col);
      hash = _mixFingerprint(hash, image.widthCells);
      hash = _mixFingerprint(hash, image.heightCells);
      hash = _mixFingerprintString(hash, image.altText);
      // Snapshots and viewport shifts retain the same Uint8List instance. Its
      // identity plus length catches every in-model image replacement without
      // rescanning multi-megabyte payloads on the UI isolate. A new instance
      // with identical content may conservatively retain an extra checkpoint,
      // but a visual change cannot be folded into the previous one.
      _onInlineImageFingerprint?.call(image.bytes.length);
      hash = _mixFingerprint(hash, image.bytes.length);
      hash = _mixFingerprint(hash, identityHashCode(image.bytes));
    }
    for (final graphic in frame.graphics) {
      hash = _mixFingerprint(hash, graphic.renderId);
      hash = _mixFingerprint(hash, graphic.placementId);
      hash = _mixFingerprint(hash, graphic.assetKey.id);
      hash = _mixFingerprint(hash, graphic.assetKey.version);
      hash = _mixFingerprintString(hash, graphic.protocol);
      hash = _mixFingerprint(hash, graphic.row);
      hash = _mixFingerprint(hash, graphic.col);
      hash = _mixFingerprint(hash, graphic.widthPx);
      hash = _mixFingerprint(hash, graphic.heightPx);
      hash = _mixFingerprint(hash, graphic.widthCells);
      hash = _mixFingerprint(hash, graphic.heightCells);
      hash = _mixFingerprint(hash, graphic.sourceXOffsetPx);
      hash = _mixFingerprint(hash, graphic.visibleWidthPx);
      hash = _mixFingerprint(hash, graphic.sourceYOffsetPx);
      hash = _mixFingerprint(hash, graphic.visibleHeightPx);
      hash = _mixFingerprint(hash, graphic.zIndex);
      hash = _mixFingerprint(hash, graphic.xOffsetPx);
      hash = _mixFingerprint(hash, graphic.yOffsetPx);
      hash = _mixFingerprint(hash, graphic.preserveAspectRatio ? 1 : 0);
    }
    for (final block in frame.blocks) {
      hash = _mixFingerprintString(hash, block.id);
      hash = _mixFingerprintString(hash, block.blockType);
      hash = _mixFingerprint(hash, block.startRow);
      hash = _mixFingerprint(hash, block.endRow);
      hash = _mixFingerprint(hash, block.sourceStartRow);
      hash = _mixFingerprint(hash, block.sourceEndRow);
      hash = _mixFingerprint(hash, block.folded ? 1 : 0);
      hash = _mixFingerprint(hash, block.rendered ? 1 : 0);
      hash = _mixFingerprint(hash, block.hiddenRows);
    }
    for (final button in frame.inlineButtons) {
      hash = _mixFingerprint(hash, button.id);
      hash = _mixFingerprint(hash, button.kind.index);
      hash = _mixFingerprint(hash, button.row);
      hash = _mixFingerprint(hash, button.col);
      hash = _mixFingerprint(hash, button.code ?? -1);
      hash = _mixFingerprintString(hash, button.icon);
      hash = _mixFingerprintString(hash, button.blockId);
      hash = _mixFingerprint(hash, button.valid ? 1 : 0);
      hash = _mixFingerprint(hash, button.widthCells);
    }
    return hash;
  }

  int _estimateFrameBytes(terminal.TerminalFrameDiff frame) {
    var bytes =
        256 +
        _estimateStringBytes(frame.frameSchemaVersion) +
        _estimateStringBytes(frame.windowTitle) +
        _estimateStringBytes(frame.windowIconName) +
        _estimateStringBytes(frame.fontFamily) +
        _estimateStringBytes(frame.modes.mouseMode) +
        _estimateStringBytes(frame.modes.mouseEncoding);
    for (final row in frame.rows) {
      bytes += 64 + row.text.length * 2 + row.styleRuns.length * 32;
    }
    bytes += frame.dirtyRanges.length * 16;
    for (final link in frame.hyperlinks) {
      bytes +=
          48 +
          _estimateStringBytes(link.uri) +
          _estimateStringBytes(link.protocolId);
    }
    for (final placement in frame.sizedText) {
      bytes += 96 + _estimateStringBytes(placement.text);
    }
    for (final image in frame.inlineImages) {
      bytes += 128 + image.bytes.length + _estimateStringBytes(image.altText);
    }
    for (final graphic in frame.graphics) {
      bytes += 128 + _estimateStringBytes(graphic.protocol);
    }
    for (final block in frame.blocks) {
      bytes +=
          64 +
          _estimateStringBytes(block.id) +
          _estimateStringBytes(block.blockType);
    }
    for (final button in frame.inlineButtons) {
      bytes +=
          64 +
          _estimateStringBytes(button.icon) +
          _estimateStringBytes(button.blockId);
    }
    return bytes;
  }

  int _estimateStringBytes(String? value) => (value?.length ?? 0) * 2;

  void _setStateEstimatedBytes(String sessionId, int nextBytes) {
    final previousBytes = _stateBytesBySession[sessionId] ?? 0;
    _stateBytesBySession[sessionId] = nextBytes;
    _estimatedRetainedBytes += nextBytes - previousBytes;
    _clampEstimatedBytes();
  }

  int _estimateSemanticBytes(InstantReplaySemanticEvent event) {
    return 96 +
        (event.command?.length ?? 0) * 2 +
        (event.cwd?.length ?? 0) * 2 +
        (event.hostname?.length ?? 0) * 2;
  }

  void _adjustSemanticBytes(String sessionId, int delta) {
    final next = (_semanticBytesBySession[sessionId] ?? 0) + delta;
    if (next <= 0) {
      _semanticBytesBySession.remove(sessionId);
    } else {
      _semanticBytesBySession[sessionId] = next;
    }
    _estimatedRetainedBytes += delta;
    _clampEstimatedBytes();
  }

  void _removeFrameAt(String sessionId, int index) {
    final frames = _framesBySession[sessionId];
    if (frames == null || index < 0 || index >= frames.length) {
      return;
    }
    final removed = frames.removeAt(index);
    _estimatedRetainedBytes -= removed.estimatedBytes;
    if (frames.isEmpty) {
      _framesBySession.remove(sessionId);
      _stateBySession.remove(sessionId);
      _estimatedRetainedBytes -= _stateBytesBySession.remove(sessionId) ?? 0;
      _lastMaterializedAtBySession.remove(sessionId);
      final semanticBytes = _semanticBytesBySession.remove(sessionId) ?? 0;
      _estimatedRetainedBytes -= semanticBytes;
      _semanticsBySession.remove(sessionId);
    }
    _clampEstimatedBytes();
  }

  void _removeSemanticAt(String sessionId, int index) {
    final events = _semanticsBySession[sessionId];
    if (events == null || index < 0 || index >= events.length) {
      return;
    }
    final removed = events.removeAt(index);
    _adjustSemanticBytes(sessionId, -_estimateSemanticBytes(removed));
    if (events.isEmpty) {
      _semanticsBySession.remove(sessionId);
      _semanticBytesBySession.remove(sessionId);
    }
  }

  void _pruneSemanticsBeforeOldestFrame(String sessionId) {
    final frames = _framesBySession[sessionId];
    final semantics = _semanticsBySession[sessionId];
    if (frames == null || frames.isEmpty || semantics == null) {
      return;
    }
    final oldest = frames.last.value.capturedAt;
    while (semantics.isNotEmpty &&
        semantics.first.capturedAt.isBefore(oldest)) {
      _removeSemanticAt(sessionId, 0);
    }
  }

  void _enforceByteBudget() {
    if (byteBudget <= 0) {
      for (final sessionId in <String>{
        ..._framesBySession.keys,
        ..._semanticsBySession.keys,
      }.toList(growable: false)) {
        clear(sessionId);
      }
      return;
    }
    while (_estimatedRetainedBytes > byteBudget) {
      String? oldestFrameSession;
      DateTime? oldestFrameTime;
      for (final entry in _framesBySession.entries) {
        if (entry.value.isEmpty) {
          continue;
        }
        final capturedAt = entry.value.last.value.capturedAt;
        if (oldestFrameTime == null || capturedAt.isBefore(oldestFrameTime)) {
          oldestFrameTime = capturedAt;
          oldestFrameSession = entry.key;
        }
      }
      String? oldestSemanticSession;
      DateTime? oldestSemanticTime;
      for (final entry in _semanticsBySession.entries) {
        if (entry.value.isEmpty) {
          continue;
        }
        final capturedAt = entry.value.first.capturedAt;
        if (oldestSemanticTime == null ||
            capturedAt.isBefore(oldestSemanticTime)) {
          oldestSemanticTime = capturedAt;
          oldestSemanticSession = entry.key;
        }
      }
      if (oldestFrameSession == null && oldestSemanticSession == null) {
        _estimatedRetainedBytes = 0;
        return;
      }
      if (oldestSemanticSession != null &&
          (oldestFrameTime == null ||
              oldestSemanticTime!.isBefore(oldestFrameTime))) {
        _removeSemanticAt(oldestSemanticSession, 0);
      } else {
        final frameSession = oldestFrameSession!;
        final frames = _framesBySession[frameSession]!;
        _removeFrameAt(frameSession, frames.length - 1);
        _pruneSemanticsBeforeOldestFrame(frameSession);
      }
    }
  }

  void _clampEstimatedBytes() {
    if (_estimatedRetainedBytes < 0) {
      _estimatedRetainedBytes = 0;
    }
  }

  InstantReplayFrame _mergeFrameMetadata(
    InstantReplayFrame existing, {
    Size? viewportLogicalSize,
    Size? viewportPixelSize,
    double? devicePixelRatio,
    Size? windowContentSize,
    Size? windowFrameSize,
  }) {
    return InstantReplayFrame(
      sessionId: existing.sessionId,
      capturedAt: existing.capturedAt,
      frame: existing.frame,
      snapshot: existing.snapshot,
      viewportLogicalSize: viewportLogicalSize ?? existing.viewportLogicalSize,
      viewportPixelSize: viewportPixelSize ?? existing.viewportPixelSize,
      devicePixelRatio: devicePixelRatio ?? existing.devicePixelRatio,
      windowContentSize: windowContentSize ?? existing.windowContentSize,
      windowFrameSize: windowFrameSize ?? existing.windowFrameSize,
    );
  }
}

String _textForFrame(terminal.TerminalFrameDiff frame) {
  final rows = frame.rows.toList()..sort((a, b) => a.index.compareTo(b.index));
  final lines = rows.map((row) => row.text.trimRight()).toList();
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  return lines.join('\n').trimRight();
}
