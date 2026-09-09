part of 'shell_screen.dart';

extension _ShellScreenStateSearchCompletion on _ShellScreenState {
  void _openSearch() {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    _mutateState(() {
      _isSearchOpen = true;
      _searchFocusRequestSerial += 1;
    });
    if (_searchQuery.isNotEmpty) {
      _searchScrollback(_searchQuery);
    }
    _requestSearchFocus();
  }

  void _requestSearchFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isSearchOpen) {
        return;
      }
      _searchFocusNode.requestFocus();
    });
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        if (!mounted || !_isSearchOpen) {
          return;
        }
        _searchFocusNode.requestFocus();
      }),
    );
  }

  void _clearSearch() {
    _mutateState(() {
      _searchQuery = '';
      _searchErrorText = null;
      _searchMatchesBySession = const {};
      _searchHits = const [];
      _activeSearchIndex = 0;
      _searchFocusRequestSerial += 1;
      _lastSearchScopeSessionSignature = null;
    });
    _requestSearchFocus();
  }

  void _searchScrollback(String query) {
    final sessionState = ref.read(sessionControllerProvider);
    if (sessionState.activeSessionId == null) {
      return;
    }
    if (query.isEmpty) {
      _mutateState(() {
        _searchQuery = query;
        _searchErrorText = null;
        _searchMatchesBySession = const {};
        _searchHits = const [];
        _activeSearchIndex = 0;
        _lastSearchScopeSessionSignature = null;
      });
      return;
    }
    final result = _searchScopedSessions(query, sessionState);
    final activeIndex = _defaultSearchActiveIndex(result.hits);
    final scopeSignature = _searchScopeSessionSignatureFor(result.sessions);
    _mutateState(() {
      _searchQuery = query;
      _searchErrorText = result.errorText;
      _searchMatchesBySession = result.matchesBySession;
      _searchHits = result.hits;
      _activeSearchIndex = activeIndex;
      _lastSearchScopeSessionSignature = scopeSignature;
    });
    if (result.hits.isNotEmpty) {
      _scrollToSearchHit(result.hits[activeIndex]);
    }
    _rememberSearchRefreshFrameSignatures(
      result.sessions.map((session) => session.sessionId),
    );
  }

  _ScopedSearchResult _searchScopedSessions(
    String query,
    SessionState sessionState,
  ) {
    final sessions = _searchSessionsForScope(sessionState);
    final runtime = ref.read(terminalRuntimeControllerProvider);
    final matchesBySession = <String, List<terminal.TerminalSearchMatch>>{};
    final hits = <_ScopedSearchMatch>[];

    for (final session in sessions) {
      final result = runtime.searchTextResult(
        session.sessionId,
        query,
        mode: _searchMode,
      );
      if (result.errorText != null) {
        return _ScopedSearchResult(
          sessions: sessions,
          matchesBySession:
              const <String, List<terminal.TerminalSearchMatch>>{},
          hits: const <_ScopedSearchMatch>[],
          errorText: result.errorText,
        );
      }
      matchesBySession[session.sessionId] = result.matches;
      for (final match in result.matches) {
        hits.add(_ScopedSearchMatch(session: session, match: match));
      }
    }

    return _ScopedSearchResult(
      sessions: sessions,
      matchesBySession: Map.unmodifiable(matchesBySession),
      hits: List.unmodifiable(hits),
    );
  }

  List<_SearchableSession> _searchSessionsForScope(SessionState sessionState) {
    final activeSessionId = sessionState.activeSessionId;
    if (activeSessionId == null) {
      return const <_SearchableSession>[];
    }
    final activeTab = _tabForSession(sessionState, activeSessionId);
    return switch (_searchScope) {
      _TerminalSearchScope.activePane => [
        _SearchableSession(
          sessionId: activeSessionId,
          title:
              activeTab?.paneFor(activeSessionId)?.title ??
              activeTab?.title ??
              context.l10n.activePane,
        ),
      ],
      _TerminalSearchScope.currentTab => [
        if (activeTab != null)
          for (final pane in activeTab.effectivePanes)
            _SearchableSession(sessionId: pane.sessionId, title: pane.title),
      ],
      _TerminalSearchScope.allTabs => _searchableSessions(sessionState),
    };
  }

  int _defaultSearchActiveIndex(List<_ScopedSearchMatch> hits) {
    return hits.isEmpty ? 0 : hits.length - 1;
  }

  String _searchScopeSessionSignature(SessionState sessionState) {
    return _searchScopeSessionSignatureFor(
      _searchSessionsForScope(sessionState),
    );
  }

  String _searchScopeSessionSignatureFor(
    Iterable<_SearchableSession> sessions,
  ) {
    final buffer = StringBuffer(_searchScope.wireName);
    for (final session in sessions) {
      buffer
        ..write('|')
        ..write(session.sessionId);
    }
    return buffer.toString();
  }

  void _syncSearchResultsForSessionScope(SessionState sessionState) {
    if (!_isSearchOpen ||
        _searchQuery.isEmpty ||
        sessionState.activeSessionId == null) {
      _lastSearchScopeSessionSignature = null;
      return;
    }
    final signature = _searchScopeSessionSignature(sessionState);
    if (signature == _lastSearchScopeSessionSignature) {
      return;
    }
    _lastSearchScopeSessionSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isSearchOpen || _searchQuery.isEmpty) {
        return;
      }
      final currentSessionState = ref.read(sessionControllerProvider);
      if (_searchScopeSessionSignature(currentSessionState) != signature) {
        return;
      }
      final activeSessionId = currentSessionState.activeSessionId;
      if (activeSessionId == null) {
        return;
      }
      _refreshSearchMatchesForSession(activeSessionId);
    });
  }

  void _refreshSearchMatchesAfterResize(String sessionId) {
    _refreshSearchMatchesForSession(sessionId);
  }

  void _refreshSearchMatchesAfterFrame(
    String sessionId,
    terminal.TerminalFrameDiff frame,
  ) {
    if (!_searchRefreshAllowedForSession(sessionId)) {
      return;
    }
    final signature = _searchRefreshFrameSignature(frame);
    if (_searchRefreshFrameSignatures[sessionId] == signature) {
      return;
    }
    _searchRefreshFrameSignatures[sessionId] = signature;
    _refreshSearchMatchesForSession(sessionId, frame: frame);
  }

  bool _searchRefreshAllowedForSession(String sessionId) {
    if (!_isSearchOpen || _searchQuery.isEmpty) {
      return false;
    }
    return _searchSessionsForScope(
      ref.read(sessionControllerProvider),
    ).any((session) => session.sessionId == sessionId);
  }

  void _refreshSearchMatchesForSession(
    String sessionId, {
    terminal.TerminalFrameDiff? frame,
  }) {
    if (!_searchRefreshAllowedForSession(sessionId)) {
      return;
    }
    final previousActiveIndex = _activeSearchIndex;
    final previousActiveHit =
        previousActiveIndex >= 0 && previousActiveIndex < _searchHits.length
        ? _searchHits[previousActiveIndex]
        : null;
    final result = _searchScopedSessions(
      _searchQuery,
      ref.read(sessionControllerProvider),
    );
    final scopeSignature = _searchScopeSessionSignatureFor(result.sessions);
    if (!mounted) {
      return;
    }
    _mutateState(() {
      _searchErrorText = result.errorText;
      _searchMatchesBySession = result.matchesBySession;
      _searchHits = result.hits;
      _activeSearchIndex = _refreshedSearchActiveIndex(
        result.hits,
        previousActiveHit: previousActiveHit,
        previousActiveIndex: previousActiveIndex,
      );
      _lastSearchScopeSessionSignature = scopeSignature;
    });
    if (frame == null) {
      _rememberSearchRefreshFrameSignatures(
        result.sessions.map((session) => session.sessionId),
      );
    }
  }

  void _rememberSearchRefreshFrameSignatures(Iterable<String> sessionIds) {
    for (final sessionId in sessionIds) {
      _rememberSearchRefreshFrameSignature(sessionId);
    }
  }

  void _rememberSearchRefreshFrameSignature(String sessionId) {
    final frame = ref
        .read(terminalRuntimeControllerProvider)
        .viewportFor(sessionId)
        .frame;
    _searchRefreshFrameSignatures[sessionId] = _searchRefreshFrameSignature(
      frame,
    );
  }

  String _searchRefreshFrameSignature(terminal.TerminalFrameDiff frame) {
    final buffer = StringBuffer()
      ..write(frame.viewportStartRow)
      ..write('|')
      ..write(frame.viewportRows)
      ..write('|')
      ..write(frame.viewportCols)
      ..write('|')
      ..write(frame.scrollbackOffset)
      ..write('|')
      ..write(frame.scrollbackMaxOffset)
      ..write('|')
      ..write(frame.rows.length);
    for (final row in frame.rows) {
      buffer
        ..write('|')
        ..write(row.index)
        ..write(':')
        ..write(row.wrapped ? 1 : 0)
        ..write(':')
        ..write(row.text);
    }
    return buffer.toString();
  }

  int _refreshedSearchActiveIndex(
    List<_ScopedSearchMatch> hits, {
    required _ScopedSearchMatch? previousActiveHit,
    required int previousActiveIndex,
  }) {
    if (hits.isEmpty) {
      return 0;
    }
    if (previousActiveHit == null) {
      return 0;
    }
    final exactIndex = _closestSearchMatchIndex(
      hits,
      previousActiveIndex,
      (hit) =>
          hit.session.sessionId == previousActiveHit.session.sessionId &&
          _sameSearchMatch(hit.match, previousActiveHit.match),
    );
    if (exactIndex != -1) {
      return exactIndex;
    }
    final stableContentIndex = _closestSearchMatchIndex(
      hits,
      previousActiveIndex,
      (hit) =>
          hit.session.sessionId == previousActiveHit.session.sessionId &&
          hit.match.scrollbackOffset ==
              previousActiveHit.match.scrollbackOffset &&
          hit.match.text == previousActiveHit.match.text,
    );
    if (stableContentIndex != -1) {
      return stableContentIndex;
    }
    return previousActiveIndex.clamp(0, hits.length - 1);
  }

  int _closestSearchMatchIndex(
    List<_ScopedSearchMatch> hits,
    int preferredIndex,
    bool Function(_ScopedSearchMatch hit) matchesIdentity,
  ) {
    var bestIndex = -1;
    var bestDistance = 1 << 30;
    for (var index = 0; index < hits.length; index += 1) {
      if (!matchesIdentity(hits[index])) {
        continue;
      }
      final distance = (index - preferredIndex).abs();
      if (distance < bestDistance) {
        bestIndex = index;
        bestDistance = distance;
      }
    }
    return bestIndex;
  }

  bool _sameSearchMatch(
    terminal.TerminalSearchMatch left,
    terminal.TerminalSearchMatch right,
  ) {
    return left.row == right.row &&
        left.startCol == right.startCol &&
        left.endCol == right.endCol &&
        left.scrollbackOffset == right.scrollbackOffset &&
        left.text == right.text;
  }

  void _setSearchMode(terminal.TerminalSearchMode value) {
    if (_searchMode == value) {
      return;
    }
    _mutateState(() {
      _searchMode = value;
      _searchErrorText = null;
      _searchMatchesBySession = const {};
      _searchHits = const [];
      _activeSearchIndex = 0;
      _lastSearchScopeSessionSignature = null;
    });
    if (_searchQuery.isNotEmpty) {
      _searchScrollback(_searchQuery);
    }
  }

  void _setSearchScope(_TerminalSearchScope value) {
    if (_searchScope == value) {
      return;
    }
    _mutateState(() {
      _searchScope = value;
      _searchErrorText = null;
      _searchMatchesBySession = const {};
      _searchHits = const [];
      _activeSearchIndex = 0;
      _lastSearchScopeSessionSignature = null;
    });
    if (_searchQuery.isNotEmpty) {
      _searchScrollback(_searchQuery);
    }
    _requestSearchFocus();
  }

  void _moveSearchMatch(int delta) {
    if (_searchHits.isEmpty) {
      return;
    }
    final nextIndex = (_activeSearchIndex + delta) % _searchHits.length;
    final normalizedIndex = nextIndex < 0
        ? nextIndex + _searchHits.length
        : nextIndex;
    _mutateState(() {
      _activeSearchIndex = normalizedIndex;
    });
    _scrollToSearchHit(_searchHits[normalizedIndex]);
  }

  void _scrollToSearchHit(_ScopedSearchMatch hit) {
    final sessionController = ref.read(sessionControllerProvider.notifier);
    final sessionId = hit.session.sessionId;
    _activateSession(sessionController, sessionId, requestFocus: false);
    ref
        .read(terminalRuntimeControllerProvider)
        .scrollViewportTo(sessionId, hit.match.scrollbackOffset);
  }

  List<terminal.TerminalSearchMatch> _searchMatchesForSession(
    String sessionId,
  ) {
    return _searchMatchesBySession[sessionId] ??
        const <terminal.TerminalSearchMatch>[];
  }

  int _activeSearchMatchIndexForSession(String sessionId) {
    if (!_isSearchOpen ||
        _activeSearchIndex < 0 ||
        _activeSearchIndex >= _searchHits.length) {
      return -1;
    }
    final activeHit = _searchHits[_activeSearchIndex];
    if (activeHit.session.sessionId != sessionId) {
      return -1;
    }
    final matches = _searchMatchesForSession(sessionId);
    return matches.indexWhere(
      (match) => _sameSearchMatch(match, activeHit.match),
    );
  }

  void _closeSearch() {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    _mutateState(() {
      _isSearchOpen = false;
    });
    if (activeSessionId != null) {
      _focusSession(activeSessionId);
    }
  }

  List<_SearchableSession> _searchableSessions(SessionState sessionState) {
    return [
      for (final tab in sessionState.tabs)
        for (final pane in tab.effectivePanes)
          _SearchableSession(sessionId: pane.sessionId, title: pane.title),
    ];
  }

  terminal.TerminalRow? _rowAtCursor(terminal.TerminalFrameDiff frame) {
    for (final row in frame.rows) {
      if (row.index == frame.cursor.row) {
        return row;
      }
    }
    if (frame.cursor.row >= 0 && frame.cursor.row < frame.rows.length) {
      return frame.rows[frame.cursor.row];
    }
    return null;
  }

  TerminalPane? _paneForSession(SessionState sessionState, String sessionId) {
    for (final tab in sessionState.tabs) {
      final pane = tab.paneFor(sessionId);
      if (pane != null) {
        return pane;
      }
    }
    return null;
  }

  bool _selectLastCommandOutput(
    SessionController sessionController,
    String sessionId,
    SelectionController selectionController,
  ) {
    final promptMarks = _effectivePromptMarksForSession(
      sessionId,
      sessionState: ref.read(sessionControllerProvider),
    );
    if (promptMarks.length < 2) {
      return false;
    }
    final startMark = promptMarks[promptMarks.length - 2];
    final endMark = promptMarks.last;
    final frame = sessionController.viewportFor(sessionId).frame;
    final startPromptRow = _viewportRowForGlobalLine(
      frame,
      startMark.globalLine,
    );
    final endPromptRow = _viewportRowForGlobalLine(frame, endMark.globalLine);
    if (startPromptRow == null || endPromptRow == null) {
      return false;
    }
    final startRow = startPromptRow + 1;
    final endRow = endPromptRow - 1;
    if (endRow < startRow) {
      return false;
    }
    selectionController.setSelection(
      terminal.TerminalSelection(
        startRow: startRow,
        startCol: 0,
        endRow: endRow,
        endCol: _rowEndColumn(frame, endRow),
      ),
    );
    _focusSession(sessionId);
    return true;
  }

  int _rowEndColumn(terminal.TerminalFrameDiff frame, int rowIndex) {
    for (final row in frame.rows) {
      if (row.index == rowIndex) {
        return terminal.TerminalTextCells.fromText(row.text).cellCount;
      }
    }
    return frame.viewportCols;
  }

  void _navigateShellPrompt(String sessionId, {required int direction}) {
    final promptMarks = _effectivePromptMarksForSession(sessionId);
    if (promptMarks.isEmpty) {
      return;
    }

    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(sessionId)
        .frame;
    final targetOffset = _shellPromptNavigationOffset(
      promptMarks,
      frame,
      frame.scrollbackOffset,
      direction: direction,
    );
    if (targetOffset == null) {
      return;
    }

    ref
        .read(terminalRuntimeControllerProvider)
        .scrollViewportTo(sessionId, targetOffset);
    _focusSession(sessionId);
  }

  List<TerminalShellPromptMark> _effectivePromptMarksForSession(
    String sessionId, {
    SessionState? sessionState,
  }) {
    final SessionState currentState =
        sessionState ?? ref.read(sessionControllerProvider);
    final pane = _paneForSession(currentState, sessionId);
    if (pane == null) {
      return const <TerminalShellPromptMark>[];
    }
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(sessionId)
        .frame;
    return _effectivePromptMarksForFrame(pane.shellIntegration, frame);
  }

  List<TerminalShellPromptMark> _effectivePromptMarksForFrame(
    TerminalShellIntegrationSnapshot integration,
    terminal.TerminalFrameDiff frame,
  ) {
    final fallback = _fallbackPromptMarkForFrame(integration, frame);
    if (fallback == null) {
      return integration.promptMarks;
    }
    if (integration.promptMarks.any(
      (mark) => mark.globalLine == fallback.globalLine,
    )) {
      return integration.promptMarks;
    }
    final merged = [...integration.promptMarks, fallback];
    merged.sort(_comparePromptMarksForDisplay);
    return merged;
  }

  TerminalShellPromptMark? _fallbackPromptMarkForFrame(
    TerminalShellIntegrationSnapshot integration,
    terminal.TerminalFrameDiff frame,
  ) {
    final hasShellIntegrationContext =
        integration.currentDirectory?.trim().isNotEmpty == true ||
        integration.lastCommand?.trim().isNotEmpty == true ||
        integration.recentCommands.isNotEmpty ||
        integration.recentDirectories.isNotEmpty;
    if (!hasShellIntegrationContext || frame.rows.isEmpty) {
      return null;
    }

    terminal.TerminalRow? anchorRow;
    final rowAtCursor = _rowAtCursor(frame);
    if (rowAtCursor != null && rowAtCursor.text.trimRight().isNotEmpty) {
      anchorRow = rowAtCursor;
    }
    if (anchorRow == null) {
      for (final logicalRow in _logicalRows(frame.rows).reversed) {
        if (logicalRow.text.trimRight().isEmpty) {
          continue;
        }
        anchorRow = logicalRow.endRow;
        break;
      }
    }
    if (anchorRow == null) {
      return null;
    }

    final globalLine = _globalLineForViewportRow(frame, anchorRow.index);
    if (globalLine == null) {
      return null;
    }
    return TerminalShellPromptMark(
      globalLine: globalLine,
      command: integration.lastCommand,
      cwd: integration.currentDirectory,
    );
  }

  int? _shellPromptNavigationOffset(
    List<TerminalShellPromptMark> marks,
    terminal.TerminalFrameDiff frame,
    int currentOffset, {
    required int direction,
  }) {
    final offsets =
        marks
            .map((mark) => _promptMarkOffsetForFrame(mark, frame))
            .whereType<int>()
            .toSet()
            .toList(growable: false)
          ..sort();
    if (offsets.isEmpty) {
      return null;
    }
    if (direction < 0) {
      for (final offset in offsets) {
        if (offset > currentOffset) {
          return offset;
        }
      }
      return offsets.last;
    }

    for (final offset in offsets.reversed) {
      if (offset < currentOffset) {
        return offset;
      }
    }
    return offsets.first;
  }
}

int? _promptMarkOffsetForFrame(
  TerminalShellPromptMark mark,
  terminal.TerminalFrameDiff frame,
) {
  return terminalPromptMarkScrollbackOffset(
    mark,
    globalBottomRow: frame.globalBottomRow,
    scrollbackMaxOffset: frame.scrollbackMaxOffset,
  );
}

int? _globalLineForViewportRow(terminal.TerminalFrameDiff frame, int rowIndex) {
  final globalBottomRow = frame.globalBottomRow;
  if (globalBottomRow == null ||
      globalBottomRow < 0 ||
      frame.viewportRows <= 0 ||
      rowIndex < 0 ||
      rowIndex >= frame.viewportRows) {
    return null;
  }
  final displayedBottom = globalBottomRow - frame.scrollbackOffset;
  final displayedTop = displayedBottom - (frame.viewportRows - 1);
  final globalLine = displayedTop + rowIndex;
  return globalLine < 0 ? null : globalLine;
}

int? _viewportRowForGlobalLine(
  terminal.TerminalFrameDiff frame,
  int? globalLine,
) {
  final globalBottomRow = frame.globalBottomRow;
  if (globalBottomRow == null ||
      globalBottomRow < 0 ||
      frame.viewportRows <= 0 ||
      globalLine == null ||
      globalLine < 0) {
    return null;
  }
  final displayedBottom = globalBottomRow - frame.scrollbackOffset;
  final displayedTop = displayedBottom - (frame.viewportRows - 1);
  final row = globalLine - displayedTop;
  return row >= 0 && row < frame.viewportRows ? row : null;
}

int _comparePromptMarksForDisplay(
  TerminalShellPromptMark left,
  TerminalShellPromptMark right,
) {
  return left.globalLine.compareTo(right.globalLine);
}
