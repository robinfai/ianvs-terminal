part of 'shell_screen.dart';

extension _ShellScreenStateEvents on _ShellScreenState {
  Future<void> _handleNativePasteMenu() async {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    await _pasteToSession(activeSessionId);
  }

  Future<void> _handleNativeFindMenu(NativeFindAction action) async {
    if (!mounted) {
      return;
    }
    switch (action) {
      case NativeFindAction.next:
        if (!_isSearchOpen) {
          _openSearch();
          return;
        }
        _moveSearchMatch(1);
        return;
      case NativeFindAction.previous:
        if (!_isSearchOpen) {
          _openSearch();
          return;
        }
        _moveSearchMatch(-1);
        return;
      case NativeFindAction.show:
      case NativeFindAction.replace:
      case NativeFindAction.useSelection:
      case NativeFindAction.jumpToSelection:
        _openSearch();
        return;
    }
  }

  void _handleTerminalSessionEvent(terminal.TerminalSessionEvent event) {
    switch (event) {
      case terminal.TerminalSessionFrameEvent(:final sessionId, :final frame):
        final frameSequence =
            (_terminalFrameSequenceBySession[sessionId] ?? 0) + 1;
        _terminalFrameSequenceBySession[sessionId] = frameSequence;
        _recordInstantReplayFrame(sessionId, frame);
        _markNewOutputBadge(sessionId, frame);
        _feedCoprocess(sessionId, frame, frameSequence: frameSequence);
        _runProfileTriggers(sessionId, frame, frameSequence: frameSequence);
        _notifyInactiveActivity(sessionId, frame);
        _refreshSearchMatchesAfterFrame(sessionId, frame);
        _scheduleRenderableSessionSwap(sessionId);
      case terminal.TerminalSessionExitEvent():
        _terminalFrameSequenceBySession.remove(event.sessionId);
        _lastNewOutputFramePreviews.remove(event.sessionId);
        _searchRefreshFrameSignatures.remove(event.sessionId);
        _sessionsSeenForNewOutputBadges.remove(event.sessionId);
        _sessionsWithNewOutput.remove(event.sessionId);
        _triggerMatchesBySession.remove(event.sessionId);
        _stopCoprocess(event.sessionId);
        _clearCapturedOutput(event.sessionId);
        _notifySessionExit(event.sessionId, event.exitCode);
      case terminal.TerminalSessionBellEvent():
        _notifyBell(event.sessionId);
      case terminal.TerminalSessionShellHookEvent():
        _notifyShellHook(event);
      case terminal.TerminalSessionShellContextEvent():
        break;
      case terminal.TerminalSessionShellCommandEvent():
        break;
      case terminal.TerminalSessionShellUserVarEvent():
        break;
      case terminal.TerminalSessionNotificationEvent():
        _handleOscNotification(event);
      case terminal.TerminalSessionProgressEvent():
        break;
      case terminal.TerminalSessionBadgeEvent():
        break;
      case terminal.TerminalSessionClipboardEvent():
        _handleOsc52ClipboardEvent(event);
    }
  }

  Future<bool> _confirmOsc52Access(SessionOsc52PromptRequest request) async {
    if (!mounted) {
      return false;
    }
    final isPasteRequest =
        request.operation == terminal.TerminalClipboardOperation.pasteRequest;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            isPasteRequest
                ? 'Allow OSC 52 paste read?'
                : 'Allow OSC 52 clipboard copy?',
          ),
          content: _buildOsc52PromptContent(request),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Deny'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Allow'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Widget _buildOsc52PromptContent(SessionOsc52PromptRequest request) {
    final isPasteRequest =
        request.operation == terminal.TerminalClipboardOperation.pasteRequest;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final details = <Widget>[
      _Osc52PromptDetail(
        label: 'Session',
        value: request.sessionId ?? 'current',
      ),
      _Osc52PromptDetail(label: 'Selection', value: request.selection ?? 'c'),
      if (request.characterCount != null || request.byteCount != null)
        _Osc52PromptDetail(
          label: 'Size',
          value: [
            if (request.characterCount != null)
              '${request.characterCount} characters',
            if (request.byteCount != null) '${request.byteCount} bytes',
          ].join(' / '),
        ),
    ];
    final preview = request.textPreview;
    final previewText = preview == null
        ? 'Preview unavailable'
        : preview.isEmpty
        ? 'Clipboard is empty'
        : _visibleOsc52Preview(preview) +
              (request.textPreviewTruncated ? '\n... preview truncated' : '');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isPasteRequest
                ? 'The terminal is requesting clipboard contents and will send them back to the session if allowed.'
                : 'The terminal wants to write the following text to your clipboard.',
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: details),
          const SizedBox(height: 12),
          Text('Preview', style: textTheme.labelLarge),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 132),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.56,
                ),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.72),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(10),
                child: SelectableText(previewText, style: textTheme.bodySmall),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Only allow this for trusted sessions.',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _visibleOsc52Preview(String value) {
    final buffer = StringBuffer();
    for (final codePoint in value.runes) {
      if (codePoint == 0x0a || codePoint == 0x09) {
        buffer.writeCharCode(codePoint);
      } else if (codePoint == 0x0d) {
        buffer.write(r'\r');
      } else if (codePoint < 0x20 || codePoint == 0x7f) {
        buffer.write(r'\x');
        buffer.write(codePoint.toRadixString(16).padLeft(2, '0'));
      } else {
        buffer.writeCharCode(codePoint);
      }
    }
    return buffer.toString();
  }

  void _handleOsc52ClipboardEvent(
    terminal.TerminalSessionClipboardEvent event,
  ) {
    if (!mounted) {
      return;
    }
    if (event.decision == terminal.TerminalClipboardDecision.blocked) {
      _osc52BlockedCount += 1;
    }
    final label = _osc52StatusLabelFor(event);
    final tooltip = _osc52StatusTooltipFor(event);
    _osc52StatusClearTimer?.cancel();
    _mutateState(() {
      _lastOsc52StatusLabel = label;
      _lastOsc52StatusTooltip = tooltip;
    });
    _showShellSnackBar(_osc52SnackBarMessageFor(event));
    _osc52StatusClearTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _lastOsc52StatusLabel = null;
        _lastOsc52StatusTooltip = null;
      });
    });
  }

  String _osc52StatusLabelFor(terminal.TerminalSessionClipboardEvent event) {
    final operation = switch (event.operation) {
      terminal.TerminalClipboardOperation.copy => 'COPY',
      terminal.TerminalClipboardOperation.pasteRequest => 'PASTE',
    };
    final decision = switch (event.decision) {
      terminal.TerminalClipboardDecision.allowed => 'OK',
      terminal.TerminalClipboardDecision.blocked => 'BLOCKED',
      terminal.TerminalClipboardDecision.invalidPayload => 'INVALID',
    };
    return 'OSC52 $operation $decision';
  }

  String _osc52StatusTooltipFor(terminal.TerminalSessionClipboardEvent event) {
    final operation = switch (event.operation) {
      terminal.TerminalClipboardOperation.copy => 'clipboard write',
      terminal.TerminalClipboardOperation.pasteRequest => 'clipboard read',
    };
    final decision = switch (event.decision) {
      terminal.TerminalClipboardDecision.allowed => 'allowed',
      terminal.TerminalClipboardDecision.blocked => 'blocked',
      terminal.TerminalClipboardDecision.invalidPayload => 'invalid payload',
    };
    return [
      'OSC 52 $operation $decision',
      'Session: ${event.sessionId}',
      if (event.selection != null) 'Selection: ${event.selection}',
      if (event.characterCount != null) 'Characters: ${event.characterCount}',
      if (event.byteCount != null) 'Bytes: ${event.byteCount}',
      if (event.textPreview != null)
        'Preview: ${_visibleOsc52Preview(event.textPreview!)}'
            '${event.textPreviewTruncated ? '\n... preview truncated' : ''}',
      if (_osc52BlockedCount > 0) 'Blocked in this window: $_osc52BlockedCount',
    ].join('\n');
  }

  String _osc52SnackBarMessageFor(
    terminal.TerminalSessionClipboardEvent event,
  ) {
    final count = event.characterCount;
    return switch ((event.operation, event.decision)) {
      (
        terminal.TerminalClipboardOperation.copy,
        terminal.TerminalClipboardDecision.allowed,
      ) =>
        'OSC 52 copied ${count ?? 0} characters to the clipboard',
      (
        terminal.TerminalClipboardOperation.copy,
        terminal.TerminalClipboardDecision.blocked,
      ) =>
        'OSC 52 clipboard copy blocked by policy',
      (
        terminal.TerminalClipboardOperation.copy,
        terminal.TerminalClipboardDecision.invalidPayload,
      ) =>
        'OSC 52 clipboard copy ignored: invalid payload',
      (
        terminal.TerminalClipboardOperation.pasteRequest,
        terminal.TerminalClipboardDecision.allowed,
      ) =>
        'OSC 52 paste read replied with ${count ?? 0} characters',
      (
        terminal.TerminalClipboardOperation.pasteRequest,
        terminal.TerminalClipboardDecision.blocked,
      ) =>
        'OSC 52 paste read blocked by policy',
      (
        terminal.TerminalClipboardOperation.pasteRequest,
        terminal.TerminalClipboardDecision.invalidPayload,
      ) =>
        'OSC 52 paste read ignored: invalid payload',
    };
  }

  void _handleOscNotification(terminal.TerminalSessionNotificationEvent event) {
    final title = event.title.trim();
    final message = event.message.trim();
    final visibleTitle = title.isEmpty ? 'Terminal notification' : title;
    final visibleMessage = message.isEmpty ? visibleTitle : message;
    _showShellSnackBar('$visibleTitle: $visibleMessage');
    if (!_activityNotificationsEnabled ||
        !_notificationSessionIsInactive(event.sessionId) ||
        !_activityNotificationAllowed(event.sessionId)) {
      return;
    }
    _sendShellNotification(
      title:
          '$visibleTitle in ${_sessionTitleForNotification(event.sessionId)}',
      body: visibleMessage,
      identifier:
          'ianvs-terminal.osc.${event.sessionId}.${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  void _notifyInactiveActivity(
    String sessionId,
    terminal.TerminalFrameDiff frame,
  ) {
    if (!_activityNotificationsEnabled) {
      return;
    }
    final preview = _framePreview(frame);
    final hasSeenSession = !_sessionsSeenForActivityNotifications.add(
      sessionId,
    );
    final previousPreview = _lastActivityFramePreviews[sessionId];
    _lastActivityFramePreviews[sessionId] = preview;
    if (hasSeenSession &&
        previousPreview != preview &&
        _notificationSessionIsInactive(sessionId) &&
        preview != null &&
        _activityNotificationAllowed(sessionId)) {
      _sendShellNotification(
        title: 'Activity in ${_sessionTitleForNotification(sessionId)}',
        body: preview,
        identifier: 'ianvs-terminal.activity.$sessionId',
      );
    }
  }

  void _markNewOutputBadge(String sessionId, terminal.TerminalFrameDiff frame) {
    final preview = _framePreview(frame);
    final hasSeenSession = !_sessionsSeenForNewOutputBadges.add(sessionId);
    final previousPreview = _lastNewOutputFramePreviews[sessionId];
    _lastNewOutputFramePreviews[sessionId] = preview;
    if (!hasSeenSession ||
        previousPreview == preview ||
        preview == null ||
        !_sessionTabIsInactive(sessionId)) {
      return;
    }
    if (_sessionsWithNewOutput.contains(sessionId)) {
      return;
    }
    if (!mounted) {
      return;
    }
    _mutateState(() {
      _sessionsWithNewOutput.add(sessionId);
    });
  }

  void _notifySessionExit(String sessionId, int? exitCode) {
    _sendShellNotification(
      title: 'Session ended',
      body:
          '${_sessionTitleForNotification(sessionId)} exited${exitCode == null ? '' : ' with code $exitCode'}.',
      identifier:
          'ianvs-terminal.exit.$sessionId.${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  void _notifyBell(String sessionId) {
    if (!_bellNotificationsEnabled) {
      return;
    }
    _sendShellNotification(
      title: 'Bell in ${_sessionTitleForNotification(sessionId)}',
      body: 'The terminal requested attention.',
      identifier: 'ianvs-terminal.bell.$sessionId',
    );
  }

  void _notifyShellHook(terminal.TerminalSessionShellHookEvent event) {
    if (event.hook != 'command_finished') {
      return;
    }
    if (!_commandFinishedNotificationsEnabled) {
      return;
    }
    final command = event.command;
    final exitCode = event.exitCode;
    _sendShellNotification(
      title: 'Command finished',
      body: [
        if (command != null && command.trim().isNotEmpty) command.trim(),
        if (exitCode != null) 'Exit code $exitCode',
      ].join('\n'),
      identifier:
          'ianvs-terminal.command.${event.sessionId}.${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  Future<void> _loadNotificationPreferences() async {
    final configBootstrap = await _loadNotificationConfig();
    final preferences = LocalTerminalConfigPreferencesAdapter.toAppPreferences(
      configBootstrap.config,
    );
    if (!mounted) {
      return;
    }
    _mutateState(() {
      _notificationConfigSource = configBootstrap.source;
      _notificationLocalConfig = configBootstrap.config;
      _keybindingsConfig = configBootstrap.config.keybindings;
      _clipboardConfig = configBootstrap.config.clipboard;
      _bracketedPastePolicy = configBootstrap.config.paste.bracketedPaste;
      _pastePolicy = _pastePolicyFromConfig(configBootstrap.config.paste);
      _pasteHistoryPolicy = _pasteHistoryPolicyFromConfig(
        configBootstrap.config.paste,
      );
      _pasteHistoryEntries = _pasteHistoryEntries
          .take(_effectivePasteHistoryLimit)
          .toList();
      _commandFinishedNotificationsEnabled =
          preferences.notifications.commandFinished;
      _bellNotificationsEnabled = preferences.notifications.bell;
      _activityNotificationsEnabled = preferences.notifications.activity;
    });
  }

  Future<LocalTerminalConfigBootstrapResult> _loadNotificationConfig() async {
    try {
      return await ref.read(localTerminalConfigLoaderProvider).load();
    } on Object {
      final legacyPreferences = await ref
          .read(appPreferencesRepositoryProvider)
          .load();
      return LocalTerminalConfigBootstrap.resolve(
        localConfig: null,
        legacyAppPreferences: legacyPreferences,
      );
    }
  }

  Future<void> _saveNotificationPreferences() async {
    final notifications = TerminalAppNotifications(
      commandFinished: _commandFinishedNotificationsEnabled,
      bell: _bellNotificationsEnabled,
      activity: _activityNotificationsEnabled,
    );
    final localConfig = await _loadLocalNotificationConfigForSave();
    if (localConfig != null) {
      final nextConfig = localConfig.copyWith(
        notifications: LocalTerminalNotificationsConfig(
          enabled:
              notifications.commandFinished ||
              notifications.bell ||
              notifications.activity,
          commandFinished: notifications.commandFinished,
          bell: notifications.bell,
          activity: notifications.activity,
        ),
      );
      _notificationConfigSource =
          LocalTerminalConfigBootstrapSource.localConfig;
      _notificationLocalConfig = nextConfig;
      await ref.read(localTerminalConfigRepositoryProvider).save(nextConfig);
      return;
    }

    final repository = ref.read(appPreferencesRepositoryProvider);
    final preferences =
        await repository.load() ?? const TerminalAppPreferencesDocument();
    await repository.save(preferences.copyWith(notifications: notifications));
  }

  Future<LocalTerminalConfigDocument?>
  _loadLocalNotificationConfigForSave() async {
    final repository = ref.read(localTerminalConfigRepositoryProvider);
    if (_notificationConfigSource ==
        LocalTerminalConfigBootstrapSource.localConfig) {
      return await repository.load() ?? _notificationLocalConfig;
    }
    return repository.load();
  }

  LocalTerminalPastePolicy _pastePolicyFromConfig(
    LocalTerminalPasteConfig config,
  ) {
    return LocalTerminalPastePolicy(
      confirmLargePaste: config.confirmLargePaste,
      confirmMultilinePaste: config.confirmMultilinePaste,
      historySize: config.historySize,
    );
  }

  LocalTerminalPasteHistoryPolicy _pasteHistoryPolicyFromConfig(
    LocalTerminalPasteConfig config,
  ) {
    return LocalTerminalPasteHistoryPolicy(
      enabled: config.historySize > 0,
      maxEntries: config.historySize,
    );
  }

  terminal.TerminalFrameModes _pasteModesFor(
    terminal.TerminalFrameModes frameModes,
  ) {
    return switch (_bracketedPastePolicy) {
      LocalTerminalBracketedPastePolicy.auto => frameModes,
      LocalTerminalBracketedPastePolicy.force =>
        const terminal.TerminalFrameModes(bracketedPaste: true),
      LocalTerminalBracketedPastePolicy.plain =>
        terminal.TerminalFrameModes.empty,
    };
  }

  Future<bool> _toggleHotkeyWindowWithFeedback() async {
    final status = await WindowBridge.hotkeyStatus();
    if (status != null && !status.registered) {
      _showHotkeyWindowFailure(status);
      return false;
    }
    try {
      await WindowBridge.toggleHotkeyWindow();
      return true;
    } on PlatformException catch (error) {
      _showHotkeyWindowFailure(status, error: error);
      return false;
    }
  }

  void _showHotkeyWindowFailure(
    HotkeyWindowStatus? status, {
    PlatformException? error,
  }) {
    if (!mounted) {
      return;
    }
    final details = <String>[
      'Hotkey window unavailable',
      if (status != null) 'shortcut: ${status.shortcut}',
      if (status?.errorCode != null) 'error: ${status!.errorCode}',
      if (error?.message != null && error!.message!.trim().isNotEmpty)
        error.message!.trim(),
    ].join(' - ');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(details)));
  }
}

class _Osc52PromptDetail extends StatelessWidget {
  const _Osc52PromptDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: '$label: $value',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer.withValues(alpha: 0.44),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.72),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Text(
            '$label: $value',
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.onSecondaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}
