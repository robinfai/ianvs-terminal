part of 'shell_screen.dart';

extension _ShellScreenStateSearchCompletion on _ShellScreenState {
  void _openSearch({CommandBlockRowRange? scopedOutputRange}) {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    _mutateState(() {
      _isSearchOpen = true;
      _searchScopedOutputRange = scopedOutputRange;
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
      _searchMatches = const [];
      _activeSearchIndex = 0;
      _searchFocusRequestSerial += 1;
    });
    _requestSearchFocus();
  }

  void _searchScrollback(String query) {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    final result = ref
        .read(terminalRuntimeControllerProvider)
        .searchTextResult(activeSessionId, query, mode: _searchMode);
    final matches = _matchesInSearchScope(result.matches);
    final activeIndex = _defaultSearchActiveIndex(matches);
    _mutateState(() {
      _searchQuery = query;
      _searchErrorText = result.errorText;
      _searchMatches = matches;
      _activeSearchIndex = activeIndex;
    });
    if (matches.isNotEmpty) {
      ref
          .read(terminalRuntimeControllerProvider)
          .scrollViewportTo(
            activeSessionId,
            matches[activeIndex].scrollbackOffset,
          );
    }
    _rememberSearchRefreshFrameSignature(activeSessionId);
  }

  List<terminal.TerminalSearchMatch> _matchesInSearchScope(
    List<terminal.TerminalSearchMatch> matches,
  ) {
    final scopedOutputRange = _searchScopedOutputRange;
    if (scopedOutputRange == null) {
      return matches;
    }
    return [
      for (final match in matches)
        if (match.row >= scopedOutputRange.startRow &&
            match.row < scopedOutputRange.endRowExclusive)
          match,
    ];
  }

  int _defaultSearchActiveIndex(List<terminal.TerminalSearchMatch> matches) {
    return matches.isEmpty ? 0 : matches.length - 1;
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
    if (ref.read(sessionControllerProvider).activeSessionId != sessionId) {
      return false;
    }
    return true;
  }

  void _refreshSearchMatchesForSession(
    String sessionId, {
    terminal.TerminalFrameDiff? frame,
  }) {
    if (!_searchRefreshAllowedForSession(sessionId)) {
      return;
    }
    final previousActiveIndex = _activeSearchIndex;
    final previousActiveMatch =
        previousActiveIndex >= 0 && previousActiveIndex < _searchMatches.length
        ? _searchMatches[previousActiveIndex]
        : null;
    final result = ref
        .read(terminalRuntimeControllerProvider)
        .searchTextResult(sessionId, _searchQuery, mode: _searchMode);
    final matches = _matchesInSearchScope(result.matches);
    if (!mounted) {
      return;
    }
    _mutateState(() {
      _searchErrorText = result.errorText;
      _searchMatches = matches;
      _activeSearchIndex = _refreshedSearchActiveIndex(
        matches,
        previousActiveMatch: previousActiveMatch,
        previousActiveIndex: previousActiveIndex,
      );
    });
    if (frame == null) {
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
    List<terminal.TerminalSearchMatch> matches, {
    required terminal.TerminalSearchMatch? previousActiveMatch,
    required int previousActiveIndex,
  }) {
    if (matches.isEmpty) {
      return 0;
    }
    if (previousActiveMatch == null) {
      return 0;
    }
    final exactIndex = _closestSearchMatchIndex(
      matches,
      previousActiveIndex,
      (match) =>
          match.row == previousActiveMatch.row &&
          match.startCol == previousActiveMatch.startCol &&
          match.endCol == previousActiveMatch.endCol &&
          match.scrollbackOffset == previousActiveMatch.scrollbackOffset &&
          match.text == previousActiveMatch.text,
    );
    if (exactIndex != -1) {
      return exactIndex;
    }
    final stableContentIndex = _closestSearchMatchIndex(
      matches,
      previousActiveIndex,
      (match) =>
          match.scrollbackOffset == previousActiveMatch.scrollbackOffset &&
          match.text == previousActiveMatch.text,
    );
    if (stableContentIndex != -1) {
      return stableContentIndex;
    }
    return previousActiveIndex.clamp(0, matches.length - 1).toInt();
  }

  int _closestSearchMatchIndex(
    List<terminal.TerminalSearchMatch> matches,
    int preferredIndex,
    bool Function(terminal.TerminalSearchMatch match) matchesIdentity,
  ) {
    var bestIndex = -1;
    var bestDistance = 1 << 30;
    for (var index = 0; index < matches.length; index += 1) {
      if (!matchesIdentity(matches[index])) {
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

  void _setSearchMode(terminal.TerminalSearchMode value) {
    if (_searchMode == value) {
      return;
    }
    _mutateState(() {
      _searchMode = value;
      _searchErrorText = null;
      _searchMatches = const [];
      _activeSearchIndex = 0;
    });
    if (_searchQuery.isNotEmpty) {
      _searchScrollback(_searchQuery);
    }
  }

  void _moveSearchMatch(int delta) {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null || _searchMatches.isEmpty) {
      return;
    }
    final nextIndex = (_activeSearchIndex + delta) % _searchMatches.length;
    final normalizedIndex = nextIndex < 0
        ? nextIndex + _searchMatches.length
        : nextIndex;
    _mutateState(() {
      _activeSearchIndex = normalizedIndex;
    });
    ref
        .read(terminalRuntimeControllerProvider)
        .scrollViewportTo(
          activeSessionId,
          _searchMatches[normalizedIndex].scrollbackOffset,
        );
  }

  void _closeSearch() {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    _mutateState(() {
      _isSearchOpen = false;
      _searchScopedOutputRange = null;
    });
    if (activeSessionId != null) {
      if (_commandInputVisibleForSession(activeSessionId)) {
        _restoreCommandInputFocus(activeSessionId);
        return;
      }
      _focusSession(activeSessionId);
    }
  }

  Future<void> _openGlobalSearch(SessionState sessionState) async {
    final sessions = _searchableSessions(sessionState);
    if (sessions.isEmpty) {
      return;
    }
    final result = await showModalBottomSheet<_GlobalSearchResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _GlobalSearchSheet(sessions: sessions, onSearch: _searchAllSessions),
    );
    if (!mounted || result == null) {
      _focusSession(ref.read(sessionControllerProvider).activeSessionId);
      return;
    }
    final sessionController = ref.read(sessionControllerProvider.notifier);
    sessionController.activateSession(result.session.sessionId);
    ref
        .read(terminalRuntimeControllerProvider)
        .scrollViewportTo(
          result.session.sessionId,
          result.match.scrollbackOffset,
        );
    _focusSession(result.session.sessionId);
  }

  List<_SearchableSession> _searchableSessions(SessionState sessionState) {
    return [
      for (final tab in sessionState.tabs)
        for (final pane in tab.effectivePanes)
          _SearchableSession(sessionId: pane.sessionId, title: pane.title),
    ];
  }

  List<_GlobalSearchResult> _searchAllSessions(
    String query,
    List<_SearchableSession> sessions,
  ) {
    if (query.trim().isEmpty) {
      return const <_GlobalSearchResult>[];
    }
    final runtime = ref.read(terminalRuntimeControllerProvider);
    return [
      for (final session in sessions)
        for (final match in runtime.searchText(session.sessionId, query))
          _GlobalSearchResult(session: session, match: match),
    ];
  }

  void _openAutocomplete() {
    final sessionState = ref.read(sessionControllerProvider);
    final activeSessionId = sessionState.activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(activeSessionId)
        .frame;
    final prefix = _autocompletePrefixForFrame(frame);
    final suggestions = _mergeAutocompleteSuggestions([
      _shellCommandAutocompleteSuggestions(
        sessionState,
        activeSessionId,
        prefix,
      ),
      _autocompleteSuggestionsForFrame(frame, prefix),
    ]);
    if (suggestions.isEmpty) {
      return;
    }

    _mutateState(() {
      _isAutocompleteOpen = true;
      _isSearchOpen = false;
      _autocompletePrefix = prefix;
      _autocompleteSuggestions = suggestions;
      _activeAutocompleteIndex = 0;
    });
  }

  String _autocompletePrefixForFrame(terminal.TerminalFrameDiff frame) {
    final row = _rowAtCursor(frame);
    if (row == null) {
      return '';
    }
    final beforeCursor = terminal.TerminalTextCells.fromText(
      row.text,
    ).sliceColumns(0, frame.cursor.col);
    return RegExp(r'[A-Za-z0-9_./:-]+$').firstMatch(beforeCursor)?.group(0) ??
        '';
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

  List<String> _autocompleteSuggestionsForFrame(
    terminal.TerminalFrameDiff frame,
    String prefix,
  ) {
    final normalizedPrefix = prefix.toLowerCase();
    final seen = <String>{};
    final suggestions = <String>[];
    final wordPattern = RegExp(r'[A-Za-z0-9_./:-]{2,}');

    for (final row in frame.rows.reversed) {
      final matches = wordPattern.allMatches(row.text).toList().reversed;
      for (final match in matches) {
        final word = match.group(0)!;
        final normalizedWord = word.toLowerCase();
        if (word == prefix ||
            (normalizedPrefix.isNotEmpty &&
                !normalizedWord.startsWith(normalizedPrefix)) ||
            word.length <= prefix.length ||
            !seen.add(normalizedWord)) {
          continue;
        }
        suggestions.add(word);
        if (suggestions.length >= 8) {
          return suggestions;
        }
      }
    }

    return suggestions;
  }

  List<String> _shellCommandAutocompleteSuggestions(
    SessionState sessionState,
    String sessionId,
    String prefix,
  ) {
    final pane = _paneForSession(sessionState, sessionId);
    if (pane == null) {
      return const <String>[];
    }
    final normalizedPrefix = prefix.toLowerCase();
    final seen = <String>{};
    final suggestions = <String>[];
    final wordPattern = RegExp(r'[A-Za-z0-9_./:-]{2,}');
    for (final command in pane.shellIntegration.recentCommands) {
      final normalizedCommand = command.toLowerCase();
      if (command != prefix &&
          command.length > prefix.length &&
          (normalizedPrefix.isEmpty ||
              normalizedCommand.startsWith(normalizedPrefix)) &&
          seen.add(normalizedCommand)) {
        suggestions.add(command);
        if (suggestions.length >= 8) {
          return suggestions;
        }
      }
      for (final match in wordPattern.allMatches(command)) {
        final word = match.group(0)!;
        final normalizedWord = word.toLowerCase();
        if (word == prefix ||
            (normalizedPrefix.isNotEmpty &&
                !normalizedWord.startsWith(normalizedPrefix)) ||
            word.length <= prefix.length ||
            !seen.add(normalizedWord)) {
          continue;
        }
        suggestions.add(word);
        if (suggestions.length >= 8) {
          return suggestions;
        }
      }
    }
    return suggestions;
  }

  List<String> _mergeAutocompleteSuggestions(List<List<String>> groups) {
    final seen = <String>{};
    final merged = <String>[];
    for (final group in groups) {
      for (final suggestion in group) {
        if (!seen.add(suggestion.toLowerCase())) {
          continue;
        }
        merged.add(suggestion);
        if (merged.length >= 8) {
          return merged;
        }
      }
    }
    return merged;
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

  void _moveAutocompleteSelection(int delta) {
    if (_autocompleteSuggestions.isEmpty) {
      return;
    }
    final nextIndex =
        (_activeAutocompleteIndex + delta) % _autocompleteSuggestions.length;
    _mutateState(() {
      _activeAutocompleteIndex = nextIndex < 0
          ? nextIndex + _autocompleteSuggestions.length
          : nextIndex;
    });
  }

  void _closeAutocomplete() {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    _mutateState(() {
      _isAutocompleteOpen = false;
      _autocompletePrefix = '';
      _autocompleteSuggestions = const [];
      _activeAutocompleteIndex = 0;
    });
    _focusSession(activeSessionId);
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
    final startRow = startMark.scrollbackOffset + 1;
    final endRow = endMark.scrollbackOffset - 1;
    if (endRow < startRow) {
      return false;
    }
    final frame = sessionController.viewportFor(sessionId).frame;
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

  void _acceptAutocomplete(String suggestion) {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    final suffix =
        suggestion.toLowerCase().startsWith(_autocompletePrefix.toLowerCase())
        ? suggestion.substring(_autocompletePrefix.length)
        : suggestion;
    if (suffix.isNotEmpty) {
      _sendPlainTextToSession(activeSessionId, suffix);
    }
    _closeAutocomplete();
  }

  void _openAutoComposer() {
    final sessionState = ref.read(sessionControllerProvider);
    final activeSessionId = sessionState.activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    _autoComposerController.clear();
    final inputState = _autoComposerInputStateForText('', sessionState);
    _mutateState(() {
      _isAutoComposerOpen = true;
      _isSearchOpen = false;
      _isAutocompleteOpen = false;
      _isCopyModeOpen = false;
      _universalInputPinnedContextChips = const [];
      _autoComposerClassification = inputState.classification;
      _autoComposerSuggestions = inputState.suggestions;
      _activeAutoComposerIndex = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isAutoComposerOpen) {
        return;
      }
      _autoComposerFocusNode.requestFocus();
    });
  }

  void _closeAutoComposer() {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    _mutateState(() {
      _isAutoComposerOpen = false;
      _autoComposerSuggestions = const [];
      _activeAutoComposerIndex = 0;
      _universalInputPinnedContextChips = const [];
      _autoComposerClassification = UniversalInputClassification.empty(
        mode: _universalInputMode,
      );
    });
    _focusSession(activeSessionId);
  }

  void _updateAutoComposerSuggestions(String text) {
    if (_handleUniversalInputModePrefix(text)) {
      return;
    }
    final inputState = _autoComposerInputStateForText(text);
    _mutateState(() {
      _autoComposerClassification = inputState.classification;
      _autoComposerSuggestions = inputState.suggestions;
      _activeAutoComposerIndex = 0;
    });
  }

  bool _handleUniversalInputModePrefix(String text) {
    final mode = switch (text) {
      '* ' || '＊ ' => UniversalInputMode.agent,
      '! ' || '！ ' => UniversalInputMode.terminal,
      _ => null,
    };
    if (mode == null) {
      return false;
    }

    _autoComposerController.clear();
    final inputState = _autoComposerInputStateForText('', null, mode);
    _mutateState(() {
      _universalInputMode = mode;
      _autoComposerClassification = inputState.classification;
      _autoComposerSuggestions = inputState.suggestions;
      _activeAutoComposerIndex = 0;
    });
    return true;
  }

  void _setUniversalInputMode(UniversalInputMode mode) {
    if (_universalInputMode == mode) {
      return;
    }
    final inputState = _autoComposerInputStateForText(
      _autoComposerController.text,
      null,
      mode,
    );
    _mutateState(() {
      _universalInputMode = mode;
      _autoComposerClassification = inputState.classification;
      _autoComposerSuggestions = inputState.suggestions;
      _activeAutoComposerIndex = 0;
    });
    _autoComposerFocusNode.requestFocus();
  }

  void _cycleUniversalInputMode() {
    final nextMode = switch (_universalInputMode) {
      UniversalInputMode.auto => UniversalInputMode.agent,
      UniversalInputMode.agent => UniversalInputMode.terminal,
      UniversalInputMode.terminal => UniversalInputMode.auto,
    };
    _setUniversalInputMode(nextMode);
  }

  _AutoComposerInputState _autoComposerInputStateForText(
    String text, [
    SessionState? sessionState,
    UniversalInputMode? mode,
  ]) {
    final SessionState state =
        sessionState ?? ref.read(sessionControllerProvider);
    final activeSessionId = state.activeSessionId;
    final classification = UniversalInputClassifier(
      commandVocabulary: activeSessionId == null
          ? const <String>{}
          : _universalInputCommandVocabularyFor(state, activeSessionId),
    ).classify(text, mode: mode ?? _universalInputMode);
    return _AutoComposerInputState(
      classification: classification,
      suggestions: _autoComposerSuggestionsForText(text, state, classification),
    );
  }

  Set<String> _universalInputCommandVocabularyFor(
    SessionState sessionState,
    String sessionId,
  ) {
    final vocabulary = <String>{};
    final pane = _paneForSession(sessionState, sessionId);
    final shellIntegration = pane?.shellIntegration;
    if (shellIntegration == null) {
      return vocabulary;
    }
    for (final command in shellIntegration.recentCommands) {
      final firstToken = _firstShellToken(command);
      if (firstToken != null) {
        vocabulary.add(firstToken);
      }
    }
    return vocabulary;
  }

  String? _firstShellToken(String command) {
    final match = RegExp(r'^\s*([A-Za-z0-9_./:-]+)').firstMatch(command);
    return match?.group(1)?.toLowerCase();
  }

  List<String> _universalInputContextChipsFor(
    TerminalPane pane,
    TerminalProfile? profile,
  ) {
    final integration = pane.shellIntegration;
    final chips = <String>[];
    final cwd = integration.currentDirectory;
    if (cwd != null && cwd.trim().isNotEmpty) {
      chips.add('cwd ${_compactDirectoryName(cwd)}');
    }
    if (profile != null && profile.name.trim().isNotEmpty) {
      chips.add(profile.name.trim());
    }
    final exitCode = integration.lastExitCode;
    if (exitCode != null) {
      chips.add(exitCode == 0 ? 'last ok' : 'last exit $exitCode');
    }
    final lastCommand = integration.lastCommand;
    if (lastCommand != null && lastCommand.trim().isNotEmpty) {
      chips.add('last ${_compactText(lastCommand, 28)}');
    }
    for (final chip in _universalInputPinnedContextChips) {
      if (!chips.contains(chip)) {
        chips.add(chip);
      }
    }
    return chips.take(7).toList(growable: false);
  }

  List<_UniversalInputToolOption> _universalInputContextOptionsFor(
    TerminalPane pane,
    TerminalProfile? profile,
  ) {
    final integration = pane.shellIntegration;
    final options = <_UniversalInputToolOption>[];
    final cwd = integration.currentDirectory;
    if (cwd != null && cwd.trim().isNotEmpty) {
      options.add(
        _UniversalInputToolOption(
          id: 'cwd',
          label: '@cwd',
          value: '@cwd ${_compactDirectoryName(cwd)}',
          icon: Icons.folder_rounded,
          detail: cwd,
        ),
      );
    }
    final lastCommand = integration.lastCommand;
    if (lastCommand != null && lastCommand.trim().isNotEmpty) {
      options.add(
        _UniversalInputToolOption(
          id: 'last-command',
          label: '@last-command',
          value: '@last ${_compactText(lastCommand, 28)}',
          icon: Icons.history_rounded,
          detail: _compactText(lastCommand, 48),
        ),
      );
    }
    final exitCode = integration.lastExitCode;
    if (exitCode != null) {
      options.add(
        _UniversalInputToolOption(
          id: 'last-status',
          label: '@last-status',
          value: exitCode == 0 ? '@status ok' : '@status exit $exitCode',
          icon: exitCode == 0
              ? Icons.check_circle_rounded
              : Icons.error_outline_rounded,
          detail: exitCode == 0 ? 'Last command succeeded' : 'Exit $exitCode',
        ),
      );
    }
    if (profile != null && profile.name.trim().isNotEmpty) {
      options.add(
        _UniversalInputToolOption(
          id: 'profile',
          label: '@profile',
          value: '@profile ${_compactText(profile.name.trim(), 28)}',
          icon: Icons.badge_rounded,
          detail: profile.name.trim(),
        ),
      );
    }
    if (options.isEmpty) {
      options.add(
        const _UniversalInputToolOption(
          id: 'session',
          label: '@session',
          value: '@session active shell',
          icon: Icons.terminal_rounded,
          detail: 'Active shell',
        ),
      );
    }
    return options;
  }

  void _addUniversalInputContextChip(String value) {
    _mutateState(() {
      if (!_universalInputPinnedContextChips.contains(value)) {
        _universalInputPinnedContextChips = [
          ..._universalInputPinnedContextChips,
          value,
        ];
      }
    });
    _autoComposerFocusNode.requestFocus();
  }

  void _insertUniversalInputSnippet(String snippet) {
    final currentText = _autoComposerController.text;
    final separator = currentText.trimRight().isEmpty || snippet.startsWith(' ')
        ? ''
        : ' ';
    final nextText = '${currentText.trimRight()}$separator$snippet';
    _autoComposerController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    _updateAutoComposerSuggestions(nextText);
    _autoComposerFocusNode.requestFocus();
  }

  void _setUniversalInputModel(String modelLabel) {
    _mutateState(() {
      _universalInputModelLabel = modelLabel;
    });
    _autoComposerFocusNode.requestFocus();
  }

  String _compactDirectoryName(String path) {
    final trimmed = path.trim();
    final withoutTrailingSlash = trimmed.endsWith('/') && trimmed.length > 1
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    final segments = withoutTrailingSlash.split('/');
    final last = segments.isEmpty ? withoutTrailingSlash : segments.last;
    return _compactText(last.isEmpty ? withoutTrailingSlash : last, 28);
  }

  List<String> _autoComposerSuggestionsForText(
    String text, [
    SessionState? sessionState,
    UniversalInputClassification? classification,
  ]) {
    if (classification?.isNaturalLanguage ?? false) {
      return universalInputCommandSuggestionsForText(
        text,
      ).map((suggestion) => suggestion.command).toList(growable: false);
    }
    final SessionState state =
        sessionState ?? ref.read(sessionControllerProvider);
    final activeSessionId = state.activeSessionId;
    if (activeSessionId == null) {
      return const <String>[];
    }
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(activeSessionId)
        .frame;
    final prefix = _autoComposerPrefixForText(text);
    return _mergeAutocompleteSuggestions([
      _shellCommandAutocompleteSuggestions(state, activeSessionId, prefix),
      _autocompleteSuggestionsForFrame(frame, prefix),
    ]);
  }

  String _autoComposerPrefixForText(String text) {
    return RegExp(r'[A-Za-z0-9_./:-]+$').firstMatch(text)?.group(0) ?? '';
  }

  void _moveAutoComposerSuggestion(int delta) {
    if (_autoComposerSuggestions.isEmpty) {
      return;
    }
    final nextIndex =
        (_activeAutoComposerIndex + delta) % _autoComposerSuggestions.length;
    _mutateState(() {
      _activeAutoComposerIndex = nextIndex < 0
          ? nextIndex + _autoComposerSuggestions.length
          : nextIndex;
    });
  }

  void _acceptAutoComposerSuggestion(String suggestion) {
    final currentText = _autoComposerController.text;
    final prefix = _autoComposerPrefixForText(currentText);
    final replaceWholeInput = _autoComposerClassification.isNaturalLanguage;
    final nextText = replaceWholeInput || prefix.isEmpty
        ? suggestion
        : '${currentText.substring(0, currentText.length - prefix.length)}'
              '$suggestion';
    _autoComposerController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    final nextMode = replaceWholeInput
        ? UniversalInputMode.auto
        : _universalInputMode;
    final inputState = _autoComposerInputStateForText(nextText, null, nextMode);
    _mutateState(() {
      _universalInputMode = nextMode;
      _autoComposerClassification = inputState.classification;
      _autoComposerSuggestions = inputState.suggestions;
      _activeAutoComposerIndex = 0;
    });
    _autoComposerFocusNode.requestFocus();
  }

  void _sendAutoComposerCommand() {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    final command = _autoComposerController.text.trimRight();
    if (command.isEmpty) {
      return;
    }
    final inputState = _autoComposerInputStateForText(command);
    if (inputState.classification.isNaturalLanguage) {
      if (inputState.suggestions.isNotEmpty) {
        final suggestion = inputState.suggestions.first;
        _autoComposerController.value = TextEditingValue(
          text: suggestion,
          selection: TextSelection.collapsed(offset: suggestion.length),
        );
        final terminalState = _autoComposerInputStateForText(
          suggestion,
          null,
          UniversalInputMode.auto,
        );
        _mutateState(() {
          _universalInputMode = UniversalInputMode.auto;
          _autoComposerClassification = terminalState.classification;
          _autoComposerSuggestions = terminalState.suggestions;
          _activeAutoComposerIndex = 0;
        });
        _autoComposerFocusNode.requestFocus();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Suggested command inserted. Press Enter to run it.'),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Natural language detected. Choose a command suggestion or switch to Terminal mode.',
          ),
        ),
      );
      _autoComposerFocusNode.requestFocus();
      return;
    }
    if (!_sendPlainTextToSession(activeSessionId, '$command\n')) {
      return;
    }
    _autoComposerController.clear();
    _closeAutoComposer();
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
    final target = _shellPromptNavigationTarget(
      promptMarks,
      frame.scrollbackOffset,
      direction: direction,
    );
    if (target == null) {
      return;
    }

    ref
        .read(terminalRuntimeControllerProvider)
        .scrollViewportTo(sessionId, target.scrollbackOffset);
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

  TerminalShellIntegrationSnapshot _integrationWithEffectivePromptMarks(
    String sessionId,
    TerminalShellIntegrationSnapshot integration,
  ) {
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(sessionId)
        .frame;
    return integration.copyWith(
      promptMarks: _effectivePromptMarksForFrame(integration, frame),
    );
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
      (mark) => mark.scrollbackOffset == fallback.scrollbackOffset,
    )) {
      return integration.promptMarks;
    }
    final merged = [...integration.promptMarks, fallback];
    merged.sort((a, b) => a.scrollbackOffset.compareTo(b.scrollbackOffset));
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

    return TerminalShellPromptMark(
      scrollbackOffset: (frame.scrollbackMaxOffset - anchorRow.index).clamp(
        0,
        frame.scrollbackMaxOffset,
      ),
      command: integration.lastCommand,
      cwd: integration.currentDirectory,
    );
  }

  TerminalShellPromptMark? _shellPromptNavigationTarget(
    List<TerminalShellPromptMark> marks,
    int currentOffset, {
    required int direction,
  }) {
    if (direction < 0) {
      for (final mark in marks) {
        if (mark.scrollbackOffset > currentOffset) {
          return mark;
        }
      }
      return marks.last;
    }

    for (final mark in marks.reversed) {
      if (mark.scrollbackOffset < currentOffset) {
        return mark;
      }
    }
    return marks.first;
  }
}
