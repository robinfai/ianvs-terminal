part of 'shell_screen.dart';

class _ShellShortcut {
  const _ShellShortcut(this.action, {this.tabIndex});

  final TerminalActionId action;
  final int? tabIndex;
}

final shellAnimationsEnabledProvider = Provider<bool>((ref) => true);

final pasteHistoryRepositoryProvider = Provider<PasteHistoryRepository>((ref) {
  return PasteHistoryRepository();
});

final instantReplayStoreProvider = Provider<InstantReplayStore>((ref) {
  return InstantReplayStore();
});

final passwordManagerStoreProvider = Provider<PasswordManagerStore>((ref) {
  return PasswordManagerStore();
});

final RegExp _passwordPromptPattern = RegExp(
  r'(?:password|passphrase)(?:\s+for\s+[^:]+)?\s*:\s*$',
  caseSensitive: false,
);

typedef ShellNotificationSender =
    Future<void> Function({
      required String title,
      String? body,
      String? identifier,
    });

final shellNotificationSenderProvider = Provider<ShellNotificationSender>((
  ref,
) {
  return WindowBridge.showNotification;
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

final class _InstantReplayWorkspaceSession {
  const _InstantReplayWorkspaceSession({
    required this.sourceSessionId,
    required this.sourceLabel,
    required this.retentionFrameLimit,
    required this.frames,
  });

  final String sourceSessionId;
  final String sourceLabel;
  final int retentionFrameLimit;
  final List<InstantReplayFrame> frames;
}

final class _InstantReplaySearchHit {
  const _InstantReplaySearchHit({
    required this.frameIndex,
    required this.matchIndex,
  });

  final int frameIndex;
  final int matchIndex;
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
  });

  final String id;
  final String sessionId;
  final String selectedText;
  final String note;
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
