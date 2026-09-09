part of 'shell_screen.dart';

extension _ShellScreenStateTriggers on _ShellScreenState {
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
        _runProfileTrigger(sessionId, trigger, text);
      }
    }
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

  String _zmodemRecoverySourceLabel(String sessionId) {
    final title = _sessionTitleForNotification(sessionId);
    if (title == 'Session $sessionId' || title.endsWith('($sessionId)')) {
      return title;
    }
    return '$title (session $sessionId)';
  }

  void _sendShellNotification({
    required String title,
    String? body,
    required String identifier,
    int? expiresAfterMs,
  }) {
    unawaited(
      _dispatchShellNotification(
        title: title,
        body: body,
        identifier: identifier,
        expiresAfterMs: expiresAfterMs,
      ),
    );
  }
}
