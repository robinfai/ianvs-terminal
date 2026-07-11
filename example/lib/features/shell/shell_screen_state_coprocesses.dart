part of 'shell_screen.dart';

extension _ShellScreenStateCoprocesses on _ShellScreenState {
  void _feedCoprocess(
    String sessionId,
    terminal.TerminalFrameDiff frame, {
    required int frameSequence,
  }) {
    final currentCoprocess = _coprocesses[sessionId];
    if (currentCoprocess == null) {
      return;
    }
    var nextCoprocess = currentCoprocess;
    final seenKeys = _coprocessInputKeysBySession.putIfAbsent(
      sessionId,
      () => <String>{},
    );
    String? pendingResponse;
    for (final logicalRow in _logicalRows(frame.rows)) {
      final input = logicalRow.text.trimRight();
      if (input.trim().isEmpty) {
        continue;
      }
      final inputKey = [
        _frameDedupeScope(frame, frameSequence),
        logicalRow.endRow.index,
        input,
      ].join('\u0000');
      if (!seenKeys.add(inputKey)) {
        continue;
      }
      _trimCoprocessInputHistory(seenKeys);
      nextCoprocess = nextCoprocess.copyWith(
        inputLineCount: nextCoprocess.inputLineCount + 1,
        lastInput: input,
      );
      if (pendingResponse == null &&
          _coprocessPatternMatches(nextCoprocess.pattern, input)) {
        pendingResponse = nextCoprocess.response;
      }
    }
    if (nextCoprocess != currentCoprocess && mounted) {
      _mutateState(() {
        _coprocesses = <String, _ShellCoprocess>{
          ..._coprocesses,
          sessionId: nextCoprocess,
        };
      });
    }
    if (pendingResponse != null) {
      _sendPlainTextToSession(sessionId, pendingResponse);
    }
  }

  void _trimCoprocessInputHistory(Set<String> seenKeys) {
    while (seenKeys.length > _ShellScreenState._coprocessInputHistoryLimit) {
      seenKeys.remove(seenKeys.first);
    }
  }

  bool _coprocessPatternMatches(String pattern, String input) {
    final trimmedPattern = pattern.trim();
    if (trimmedPattern.isEmpty) {
      return false;
    }
    try {
      return RegExp(trimmedPattern, caseSensitive: false).hasMatch(input);
    } on FormatException {
      return input.toLowerCase().contains(trimmedPattern.toLowerCase());
    }
  }

  void _startCoprocess(String sessionId, _CoprocessStartRequest request) {
    _coprocessInputKeysBySession[sessionId] = <String>{};
    _mutateState(() {
      _coprocesses = <String, _ShellCoprocess>{
        ..._coprocesses,
        sessionId: _ShellCoprocess(
          command: request.command,
          pattern: request.pattern,
          response: request.response,
        ),
      };
    });
  }

  void _stopCoprocess(String sessionId) {
    if (!_coprocesses.containsKey(sessionId)) {
      _coprocessInputKeysBySession.remove(sessionId);
      return;
    }
    _coprocessInputKeysBySession.remove(sessionId);
    _mutateState(() {
      _coprocesses = <String, _ShellCoprocess>{
        for (final entry in _coprocesses.entries)
          if (entry.key != sessionId) entry.key: entry.value,
      };
    });
  }

  void _runProfileTriggers(
    String sessionId,
    terminal.TerminalFrameDiff frame, {
    required int frameSequence,
  }) {
    final profile = _profileForSession(sessionId);
    if (profile == null || profile.triggers.isEmpty) {
      return;
    }
    final seenMatches = _triggerMatchesBySession.putIfAbsent(
      sessionId,
      () => <String>{},
    );
    for (final logicalRow in _logicalRows(frame.rows)) {
      final text = logicalRow.text;
      if (text.isEmpty) {
        continue;
      }
      for (final trigger in profile.triggers) {
        final regex = _regexForTrigger(trigger);
        if (regex == null) {
          continue;
        }
        if (!regex.hasMatch(text)) {
          continue;
        }
        final matchKey = _triggerMatchKey(
          trigger,
          logicalRow,
          frameScope: _frameDedupeScope(frame, frameSequence),
        );
        if (!seenMatches.add(matchKey)) {
          continue;
        }
        _trimTriggerMatchHistory(seenMatches);
        _recordCapturedOutput(sessionId, trigger, logicalRow);
        _runProfileTrigger(sessionId, trigger, text);
      }
    }
  }

  void _recordCapturedOutput(
    String sessionId,
    TerminalProfileTrigger trigger,
    _LogicalTerminalRow logicalRow,
  ) {
    final text = logicalRow.text.trimRight();
    if (text.trim().isEmpty) {
      return;
    }
    final entry = _CapturedOutputEntry(
      id: 'capture-${_nextCapturedOutputId++}',
      sessionId: sessionId,
      pattern: trigger.pattern,
      text: text,
      rowIndex: logicalRow.endRow.index,
    );
    _mutateState(() {
      _capturedOutputEntries = <_CapturedOutputEntry>[
        entry,
        ..._capturedOutputEntries,
      ].take(_ShellScreenState._capturedOutputLimit).toList(growable: false);
    });
  }

  TerminalProfile? _profileForSession(String sessionId) {
    final state = ref.read(sessionControllerProvider);
    for (final tab in state.tabs) {
      final pane = tab.paneFor(sessionId);
      if (pane == null) {
        continue;
      }
      final snapshot = pane.profileSnapshot;
      if (snapshot != null) {
        return snapshot;
      }
      for (final profile in state.profiles) {
        if (profile.id == pane.profileId) {
          return profile;
        }
      }
      return null;
    }
    return null;
  }

  RegExp? _regexForTrigger(TerminalProfileTrigger trigger) {
    final cacheKey = _triggerRegexCacheKey(trigger);
    if (_profileTriggerRegexCache.containsKey(cacheKey)) {
      return _profileTriggerRegexCache[cacheKey];
    }

    RegExp? regex;
    try {
      regex = RegExp(trigger.pattern, caseSensitive: trigger.caseSensitive);
    } on FormatException {
      regex = null;
    }
    if (_profileTriggerRegexCache.length >=
        _ShellScreenState._profileTriggerRegexCacheLimit) {
      _profileTriggerRegexCache.clear();
    }
    _profileTriggerRegexCache[cacheKey] = regex;
    return regex;
  }

  String _triggerRegexCacheKey(TerminalProfileTrigger trigger) {
    return '${trigger.caseSensitive ? '1' : '0'}\u0000${trigger.pattern}';
  }

  void _trimTriggerMatchHistory(Set<String> seenMatches) {
    while (seenMatches.length > _ShellScreenState._triggerMatchHistoryLimit) {
      seenMatches.remove(seenMatches.first);
    }
  }

  String _triggerMatchKey(
    TerminalProfileTrigger trigger,
    _LogicalTerminalRow logicalRow, {
    required String frameScope,
  }) {
    return [
      frameScope,
      trigger.pattern,
      trigger.action.name,
      trigger.value ?? '',
      trigger.caseSensitive,
      logicalRow.endRow.index,
      logicalRow.text,
    ].join('\u0000');
  }

  String _frameDedupeScope(
    terminal.TerminalFrameDiff frame,
    int frameSequence,
  ) {
    return frame.frameKind == terminal.TerminalFrameKind.delta
        ? 'delta:$frameSequence'
        : 'snapshot';
  }

  void _runProfileTrigger(
    String sessionId,
    TerminalProfileTrigger trigger,
    String rowText,
  ) {
    switch (trigger.action) {
      case TerminalProfileTriggerAction.notify:
        _sendShellNotification(
          title:
              'Trigger matched in ${_sessionTitleForNotification(sessionId)}',
          body: rowText.trim(),
          identifier:
              'ianvs-terminal.trigger.$sessionId.${trigger.pattern.hashCode}.${DateTime.now().microsecondsSinceEpoch}',
        );
      case TerminalProfileTriggerAction.sendText:
        final value = trigger.value;
        if (value == null || value.isEmpty) {
          return;
        }
        if (_isSessionReadOnly(sessionId)) {
          return;
        }
        ref
            .read(terminalRuntimeControllerProvider)
            .sendInput(sessionId, Uint8List.fromList(utf8.encode(value)));
    }
  }

  bool _sessionIsInactive(String sessionId) {
    return ref.read(sessionControllerProvider).activeSessionId != sessionId;
  }

  bool _notificationSessionIsInactive(String sessionId) {
    return _sessionIsInactive(sessionId);
  }

  bool _activityNotificationAllowed(String sessionId) {
    final now = DateTime.now();
    final lastNotification = _lastActivityNotificationAt[sessionId];
    if (lastNotification != null &&
        now.difference(lastNotification) < const Duration(seconds: 30)) {
      return false;
    }
    _lastActivityNotificationAt[sessionId] = now;
    return true;
  }

  String? _framePreview(terminal.TerminalFrameDiff frame) {
    for (final logicalRow in _logicalRows(frame.rows).reversed) {
      final text = logicalRow.text.trim();
      if (text.isNotEmpty) {
        return text.length <= _ShellScreenState._activityPreviewMaxCharacters
            ? text
            : text.substring(
                text.length - _ShellScreenState._activityPreviewMaxCharacters,
              );
      }
    }
    return null;
  }

  String _sessionTitleForNotification(String sessionId) {
    final state = ref.read(sessionControllerProvider);
    for (final tab in state.tabs) {
      final panes = tab.effectivePanes;
      final paneIndex = panes.indexWhere((pane) => pane.sessionId == sessionId);
      if (paneIndex >= 0) {
        final pane = panes[paneIndex];
        final title = pane.title.trim();
        if (panes.length < 2) {
          return title.isEmpty ? 'Session $sessionId' : title;
        }
        final paneLabel = 'pane ${paneIndex + 1}';
        return title.isEmpty
            ? '$paneLabel ($sessionId)'
            : '$title $paneLabel ($sessionId)';
      }
    }
    return 'Session $sessionId';
  }

  void _sendShellNotification({
    required String title,
    String? body,
    required String identifier,
  }) {
    unawaited(
      _dispatchShellNotification(
        title: title,
        body: body,
        identifier: identifier,
      ),
    );
  }
}
