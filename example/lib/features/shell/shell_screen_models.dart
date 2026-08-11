part of 'shell_screen.dart';

enum _ShellZmodemRecoveryAction { authorization, cancel }

class _ShellZmodemPickerRequest {
  _ShellZmodemPickerRequest({
    required this.requestId,
    required this.sessionId,
    required this.transferId,
  });

  final int requestId;
  final String sessionId;
  final String transferId;
  bool transferIsCurrent = true;
}

class _ShellZmodemTransferState {
  const _ShellZmodemTransferState({
    required this.event,
    required this.direction,
    required this.filename,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.modificationTimeSeconds,
    required this.fileCount,
    required this.completedFiles,
    required this.skippedFiles,
    required this.receiveDirectory,
    required this.errorMessage,
    required this.recoveryAction,
    this.cancelling = false,
  });

  factory _ShellZmodemTransferState.fromEvent(
    terminal.TerminalSessionZmodemEvent event, [
    _ShellZmodemTransferState? previous,
  ]) {
    final currentFileEnded =
        event.kind == terminal.TerminalZmodemEventKind.fileCompleted ||
        event.kind == terminal.TerminalZmodemEventKind.fileSkipped;
    return _ShellZmodemTransferState(
      event: event,
      direction: event.direction ?? previous?.direction,
      filename: currentFileEnded ? null : event.filename ?? previous?.filename,
      bytesTransferred:
          event.bytesTransferred ??
          (event.kind == terminal.TerminalZmodemEventKind.fileOffer
              ? 0
              : previous?.bytesTransferred),
      totalBytes: event.kind == terminal.TerminalZmodemEventKind.fileOffer
          ? event.size
          : event.totalBytes ?? previous?.totalBytes,
      modificationTimeSeconds:
          event.kind == terminal.TerminalZmodemEventKind.fileOffer
          ? event.modificationTimeSeconds
          : previous?.modificationTimeSeconds,
      fileCount: event.fileCount ?? previous?.fileCount,
      completedFiles: event.completedFiles ?? previous?.completedFiles,
      skippedFiles: event.skippedFiles ?? previous?.skippedFiles,
      receiveDirectory: previous?.receiveDirectory,
      errorMessage: previous?.errorMessage,
      recoveryAction: previous?.recoveryAction,
      cancelling: previous?.cancelling ?? false,
    );
  }

  final terminal.TerminalSessionZmodemEvent event;
  final terminal.TerminalZmodemDirection? direction;
  final String? filename;
  final int? bytesTransferred;
  final int? totalBytes;
  final int? modificationTimeSeconds;
  final int? fileCount;
  final int? completedFiles;
  final int? skippedFiles;
  final String? receiveDirectory;
  final String? errorMessage;
  final _ShellZmodemRecoveryAction? recoveryAction;
  final bool cancelling;

  String get transferId => event.transferId!;

  bool get canRetry => errorMessage != null && recoveryAction != null;

  _ShellZmodemTransferState withRecoverableError(
    terminal.TerminalSessionZmodemEvent recoveryEvent,
    String message,
    _ShellZmodemRecoveryAction action,
  ) {
    final next = _ShellZmodemTransferState.fromEvent(recoveryEvent, this);
    return _ShellZmodemTransferState(
      event: next.event,
      direction: next.direction,
      filename: next.filename,
      bytesTransferred: next.bytesTransferred,
      totalBytes: next.totalBytes,
      modificationTimeSeconds: next.modificationTimeSeconds,
      fileCount: next.fileCount,
      completedFiles: next.completedFiles,
      skippedFiles: next.skippedFiles,
      receiveDirectory: next.receiveDirectory,
      errorMessage: message,
      recoveryAction: action,
      cancelling: false,
    );
  }

  _ShellZmodemTransferState withReceiveDirectory(String directory) {
    return _ShellZmodemTransferState(
      event: event,
      direction: direction,
      filename: filename,
      bytesTransferred: bytesTransferred,
      totalBytes: totalBytes,
      modificationTimeSeconds: modificationTimeSeconds,
      fileCount: fileCount,
      completedFiles: completedFiles,
      skippedFiles: skippedFiles,
      receiveDirectory: directory,
      errorMessage: null,
      recoveryAction: null,
      cancelling: false,
    );
  }

  _ShellZmodemTransferState clearRecoverableError() {
    return _ShellZmodemTransferState(
      event: event,
      direction: direction,
      filename: filename,
      bytesTransferred: bytesTransferred,
      totalBytes: totalBytes,
      modificationTimeSeconds: modificationTimeSeconds,
      fileCount: fileCount,
      completedFiles: completedFiles,
      skippedFiles: skippedFiles,
      receiveDirectory: receiveDirectory,
      errorMessage: null,
      recoveryAction: null,
      cancelling: false,
    );
  }

  _ShellZmodemTransferState markCancelling() {
    return _ShellZmodemTransferState(
      event: event,
      direction: direction,
      filename: filename,
      bytesTransferred: bytesTransferred,
      totalBytes: totalBytes,
      modificationTimeSeconds: modificationTimeSeconds,
      fileCount: fileCount,
      completedFiles: completedFiles,
      skippedFiles: skippedFiles,
      receiveDirectory: receiveDirectory,
      errorMessage: null,
      recoveryAction: null,
      cancelling: true,
    );
  }

  double? get progress {
    final transferred = bytesTransferred;
    final total = totalBytes;
    if (transferred == null || total == null || total <= 0) {
      return null;
    }
    return (transferred / total).clamp(0.0, 1.0);
  }

  String get title => switch (direction) {
    terminal.TerminalZmodemDirection.receive => 'Receiving with ZMODEM',
    terminal.TerminalZmodemDirection.send => 'Sending with ZMODEM',
    null => 'ZMODEM transfer',
  };

  String get detail {
    if (cancelling) {
      return 'Cancelling transfer · terminal input paused';
    }
    final error = errorMessage;
    if (error != null) {
      return error;
    }
    final name = filename;
    final bytes = bytesTransferred;
    final total = totalBytes;
    final count = fileCount;
    final completed = completedFiles;
    final skipped = skippedFiles;
    if (name != null && bytes != null && total != null) {
      return '$name · ${_zmodemByteLabel(bytes)} / ${_zmodemByteLabel(total)}'
          '${_modificationTimeLabel()}';
    }
    if (name != null && total != null) {
      return '$name · ${_zmodemByteLabel(total)}${_modificationTimeLabel()}';
    }
    if (name != null &&
        event.kind == terminal.TerminalZmodemEventKind.fileOffer) {
      return '$name · unknown size · waiting for authorization';
    }
    if (count != null) {
      final processed = (completed ?? 0) + (skipped ?? 0);
      final countLabel = completed == null && skipped == null
          ? '$count files'
          : '$processed / $count files';
      final skippedLabel = skipped == null || skipped == 0
          ? ''
          : ' · $skipped skipped';
      final bytesLabel = bytes == null || total == null
          ? ''
          : ' · ${_zmodemByteLabel(bytes)} / ${_zmodemByteLabel(total)}';
      return '$countLabel$skippedLabel$bytesLabel · terminal input paused';
    }
    return switch (event.kind) {
      terminal.TerminalZmodemEventKind.detected ||
      terminal.TerminalZmodemEventKind.fileOffer =>
        'Waiting for file authorization · terminal input paused',
      _ when event.isReconciliationRequired =>
        'Transfer state lost · retry cancellation · terminal input paused',
      _ => 'Transfer in progress · terminal input paused',
    };
  }

  String _modificationTimeLabel() {
    final seconds = modificationTimeSeconds;
    if (seconds == null) {
      return '';
    }
    final modified = DateTime.fromMillisecondsSinceEpoch(
      seconds * Duration.millisecondsPerSecond,
      isUtc: true,
    );
    final value = modified
        .toIso8601String()
        .replaceFirst('T', ' ')
        .split('.')
        .first;
    return ' · modified $value UTC';
  }

  static String _zmodemByteLabel(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _ShellShortcut {
  const _ShellShortcut(this.action, {this.tabIndex});

  final TerminalActionId action;
  final int? tabIndex;
}

enum _ShellSessionDragOrigin { tab, pane }

enum _ShellPaneDropEdge { left, right, top, bottom }

class _ShellSessionDragData {
  const _ShellSessionDragData({
    required this.sessionId,
    required this.title,
    required this.origin,
  });

  final String sessionId;
  final String title;
  final _ShellSessionDragOrigin origin;
}

class _ShellPaneDropTarget {
  const _ShellPaneDropTarget({
    required this.sessionId,
    required this.edge,
    this.previewSessionId,
  });

  final String sessionId;
  final _ShellPaneDropEdge edge;
  final String? previewSessionId;

  String get displaySessionId => previewSessionId ?? sessionId;

  TerminalSplitAxis get axis => switch (edge) {
    _ShellPaneDropEdge.left ||
    _ShellPaneDropEdge.right => TerminalSplitAxis.horizontal,
    _ShellPaneDropEdge.top ||
    _ShellPaneDropEdge.bottom => TerminalSplitAxis.vertical,
  };

  bool get before => switch (edge) {
    _ShellPaneDropEdge.left || _ShellPaneDropEdge.top => true,
    _ShellPaneDropEdge.right || _ShellPaneDropEdge.bottom => false,
  };

  String get label => switch (edge) {
    _ShellPaneDropEdge.left => 'Split left',
    _ShellPaneDropEdge.right => 'Split right',
    _ShellPaneDropEdge.top => 'Split above',
    _ShellPaneDropEdge.bottom => 'Split below',
  };
}

final shellAnimationsEnabledProvider = Provider<bool>((ref) => true);

final pasteHistoryRepositoryProvider = Provider<PasteHistoryRepository>((ref) {
  return PasteHistoryRepository();
});

final instantReplayStoreProvider = Provider<InstantReplayStore>((ref) {
  return InstantReplayStore(
    minimumCaptureInterval: const Duration(milliseconds: 100),
  );
});

final passwordManagerStoreProvider = Provider<PasswordManagerStore>((ref) {
  return PasswordManagerStore();
});

@visibleForTesting
final shellHiddenRedesignEntryPointsProvider = Provider<bool>((ref) => false);

final RegExp _passwordPromptPattern = RegExp(
  r'(?:password|passphrase)(?:\s+for\s+[^:]+)?\s*:\s*$',
  caseSensitive: false,
);

typedef ShellNotificationSender =
    Future<void> Function({
      required String title,
      String? body,
      String? identifier,
      int? expiresAfterMs,
    });

typedef ShellNotificationCloser = Future<void> Function(String identifier);

final shellNotificationSenderProvider = Provider<ShellNotificationSender>((
  ref,
) {
  return WindowBridge.showNotification;
});

final shellNotificationCloserProvider = Provider<ShellNotificationCloser>((
  ref,
) {
  return WindowBridge.closeNotification;
});

sealed class _PasteHistorySheetResult {
  const _PasteHistorySheetResult();
}

final class _PasteHistoryPickResult extends _PasteHistorySheetResult {
  const _PasteHistoryPickResult(this.entry);

  final PasteHistoryEntry entry;
}

sealed class _AdvancedPasteSheetResult {
  const _AdvancedPasteSheetResult();
}

final class _AdvancedPasteSendResult extends _AdvancedPasteSheetResult {
  const _AdvancedPasteSendResult(this.text);

  final String text;
}

sealed class _PasswordManagerSheetResult {
  const _PasswordManagerSheetResult();
}

final class _PasswordManagerSendResult extends _PasswordManagerSheetResult {
  const _PasswordManagerSendResult(this.entry);

  final PasswordManagerEntry entry;
}

final class _InstantReplayLayoutSession {
  const _InstantReplayLayoutSession({
    required this.sourceSessionId,
    required this.sourceLabel,
    required this.retentionFrameLimit,
    required this.frames,
    this.semanticEvents = const <InstantReplaySemanticEvent>[],
  });

  final String sourceSessionId;
  final String sourceLabel;
  final int retentionFrameLimit;
  final List<InstantReplayFrame> frames;
  final List<InstantReplaySemanticEvent> semanticEvents;
}

typedef _InstantReplaySearchMatchKey = ({
  int row,
  int startCol,
  int endCol,
  String normalizedText,
  int scrollbackOffset,
});

final class _InstantReplaySearchHit {
  const _InstantReplaySearchHit({
    required this.firstFrameIndex,
    required this.lastFrameIndex,
    required this.matchIndex,
    required this.matchKey,
  });

  final int firstFrameIndex;
  final int lastFrameIndex;
  final int matchIndex;
  final _InstantReplaySearchMatchKey matchKey;

  bool contains({
    required int frameIndex,
    required _InstantReplaySearchMatchKey key,
  }) {
    return frameIndex >= firstFrameIndex &&
        frameIndex <= lastFrameIndex &&
        key == matchKey;
  }

  _InstantReplaySearchHit extendThrough(int frameIndex) {
    return _InstantReplaySearchHit(
      firstFrameIndex: firstFrameIndex,
      lastFrameIndex: frameIndex,
      matchIndex: matchIndex,
      matchKey: matchKey,
    );
  }
}

final class _InstantReplayIdleGapMarker {
  const _InstantReplayIdleGapMarker({
    required this.value,
    required this.tooltip,
  });

  final double value;
  final String tooltip;
}

class _SearchableSession {
  const _SearchableSession({required this.sessionId, required this.title});

  final String sessionId;
  final String title;
}

enum _TerminalSearchScope {
  activePane,
  currentTab,
  allTabs;

  String get label {
    return switch (this) {
      _TerminalSearchScope.activePane => 'Active pane',
      _TerminalSearchScope.currentTab => 'Current tab',
      _TerminalSearchScope.allTabs => 'All tabs',
    };
  }

  String get shortLabel {
    return switch (this) {
      _TerminalSearchScope.activePane => 'Pane',
      _TerminalSearchScope.currentTab => 'Tab',
      _TerminalSearchScope.allTabs => 'All',
    };
  }

  String get wireName {
    return switch (this) {
      _TerminalSearchScope.activePane => 'active_pane',
      _TerminalSearchScope.currentTab => 'current_tab',
      _TerminalSearchScope.allTabs => 'all_tabs',
    };
  }
}

final class _ScopedSearchMatch {
  const _ScopedSearchMatch({required this.session, required this.match});

  final _SearchableSession session;
  final terminal.TerminalSearchMatch match;
}

final class _ScopedSearchResult {
  const _ScopedSearchResult({
    required this.sessions,
    required this.matchesBySession,
    required this.hits,
    this.errorText,
  });

  final List<_SearchableSession> sessions;
  final Map<String, List<terminal.TerminalSearchMatch>> matchesBySession;
  final List<_ScopedSearchMatch> hits;
  final String? errorText;
}

class _GlobalSearchResult {
  const _GlobalSearchResult({required this.session, required this.match});

  final _SearchableSession session;
  final terminal.TerminalSearchMatch match;
}

class _TerminalAnnotation {
  const _TerminalAnnotation({
    required this.id,
    required this.sessionId,
    required this.selectedText,
    required this.note,
    this.source = 'user',
    this.startRow,
    this.startCol,
    this.endRow,
    this.endCol,
    this.textRefreshAttempts = 0,
  });

  final String id;
  final String sessionId;
  final String selectedText;
  final String note;
  final String source;
  final int? startRow;
  final int? startCol;
  final int? endRow;
  final int? endCol;
  final int textRefreshAttempts;

  bool get hasTerminalRange =>
      startRow != null &&
      startRow! >= 0 &&
      startCol != null &&
      startCol! >= 0 &&
      endRow != null &&
      endRow! >= startRow! &&
      endCol != null &&
      endCol! >= 0;

  _TerminalAnnotation copyWith({
    String? selectedText,
    int? textRefreshAttempts,
  }) {
    return _TerminalAnnotation(
      id: id,
      sessionId: sessionId,
      selectedText: selectedText ?? this.selectedText,
      note: note,
      source: source,
      startRow: startRow,
      startCol: startCol,
      endRow: endRow,
      endCol: endCol,
      textRefreshAttempts: textRefreshAttempts ?? this.textRefreshAttempts,
    );
  }
}

class _CapturedOutputEntry {
  const _CapturedOutputEntry({
    required this.id,
    required this.sessionId,
    required this.pattern,
    required this.text,
    required this.rowIndex,
  });

  final String id;
  final String sessionId;
  final String pattern;
  final String text;
  final int rowIndex;
}

class _LogicalTerminalRow {
  const _LogicalTerminalRow({
    required this.startRow,
    required this.endRow,
    required this.text,
  });

  final terminal.TerminalRow startRow;
  final terminal.TerminalRow endRow;
  final String text;
}

class _CoprocessStartRequest {
  const _CoprocessStartRequest({
    required this.command,
    required this.pattern,
    required this.response,
  });

  final String command;
  final String pattern;
  final String response;
}

class _ShellCoprocess {
  const _ShellCoprocess({
    required this.command,
    required this.pattern,
    required this.response,
    this.inputLineCount = 0,
    this.lastInput,
  });

  final String command;
  final String pattern;
  final String response;
  final int inputLineCount;
  final String? lastInput;

  _ShellCoprocess copyWith({int? inputLineCount, String? lastInput}) {
    return _ShellCoprocess(
      command: command,
      pattern: pattern,
      response: response,
      inputLineCount: inputLineCount ?? this.inputLineCount,
      lastInput: lastInput ?? this.lastInput,
    );
  }
}
