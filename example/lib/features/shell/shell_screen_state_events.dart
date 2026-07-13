part of 'shell_screen.dart';

extension _ShellScreenStateEvents on _ShellScreenState {
  Future<void> _handleNativePasteMenu() async {
    if (_isSearchOpen) {
      await _searchPasteHandler?.call();
      return;
    }
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
        _refreshProtocolAnnotationText(sessionId);
        _scheduleRenderableSessionSwap(sessionId);
      case terminal.TerminalSessionExitEvent():
        unawaited(_osc72DragDropController.resetSession(event.sessionId));
        _clearPresentationStateForSession(event.sessionId);
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
      case terminal.TerminalSessionAnnotationEvent():
        _handleOscAnnotation(event);
      case terminal.TerminalSessionNotificationEvent():
        _handleOscNotification(event);
      case terminal.TerminalSessionProgressEvent():
        break;
      case terminal.TerminalSessionBadgeEvent():
        break;
      case terminal.TerminalSessionTabStatusEvent():
        break;
      case terminal.TerminalSessionContextEvent():
        break;
      case terminal.TerminalSessionDragDropCommandEvent():
        unawaited(_osc72DragDropController.handleCommand(event));
      case terminal.TerminalSessionCellSizeReportRequestEvent():
        // The reusable runtime already replied using its committed cell metric.
        break;
      case terminal.TerminalSessionResetEvent():
        unawaited(_osc72DragDropController.resetSession(event.sessionId));
        _clearPresentationStateForSession(event.sessionId);
      case terminal.TerminalSessionClipboardEvent():
        _handleOsc52ClipboardEvent(event);
      case terminal.TerminalSessionBackendErrorEvent():
        break;
    }
  }

  Future<void> _handleNativeOsc72DragEvent(NativeOsc72DragEvent event) {
    return _osc72DragDropController.handleNativeEvent(
      event,
      resolveLocation: _osc72LocationFor,
    );
  }

  void _handleOscAnnotation(terminal.TerminalSessionAnnotationEvent event) {
    if (event.source != 'iterm1337') {
      return;
    }
    final message = event.message?.trim();
    final startRow = event.startRow;
    final startCol = event.startCol;
    final endRow = event.endRow;
    final endCol = event.endCol;
    if (message == null ||
        message.isEmpty ||
        message.runes.length > 1024 ||
        startRow == null ||
        startRow < 0 ||
        startCol == null ||
        startCol < 0 ||
        endRow == null ||
        endRow < startRow ||
        endCol == null ||
        endCol < 0) {
      return;
    }
    _addAnnotation(
      sessionId: event.sessionId,
      selectedText: event.selectedText ?? '',
      note: message,
      source: 'iterm1337',
      startRow: startRow,
      startCol: startCol,
      endRow: endRow,
      endCol: endCol,
    );
    _refreshProtocolAnnotationText(event.sessionId);

    final sessionState = ref.read(sessionControllerProvider);
    if (!event.visible || sessionState.activeSessionId != event.sessionId) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final currentState = ref.read(sessionControllerProvider);
      if (currentState.activeSessionId != event.sessionId) {
        return;
      }
      final selectionController = _selectionControllers.putIfAbsent(
        event.sessionId,
        SelectionController.new,
      );
      unawaited(
        _openAnnotations(
          ref.read(sessionControllerProvider.notifier),
          event.sessionId,
          selectionController,
        ),
      );
    });
  }

  Osc72DropLocation? _osc72LocationFor(NativeOsc72DragEvent event) {
    final context = _terminalViewportKeys[event.sessionId]?.currentContext;
    final renderObject = context?.findRenderObject();
    final cellSize = _measuredTerminalCellSizes[event.sessionId];
    if (renderObject is! RenderBox ||
        cellSize == null ||
        !renderObject.hasSize) {
      return null;
    }
    final local = renderObject.globalToLocal(event.position);
    final sessionState = ref.read(sessionControllerProvider);
    final padding = EdgeInsets.all(sessionState.terminalViewportPadding);
    final x = local.dx - padding.left;
    final y = local.dy - padding.top;
    final contentWidth = renderObject.size.width - padding.horizontal;
    final contentHeight = renderObject.size.height - padding.vertical;
    if (x < 0 || y < 0 || x >= contentWidth || y >= contentHeight) {
      return null;
    }
    return Osc72DropLocation(
      cellX: (x / cellSize.width).floor(),
      cellY: (y / cellSize.height).floor(),
      pixelX: x.floor(),
      pixelY: y.floor(),
    );
  }

  Future<terminal.TerminalClipboardAuthorization> _confirmOsc52Access(
    SessionOsc52PromptRequest request,
  ) async {
    if (!mounted) {
      return terminal.TerminalClipboardAuthorization.denied;
    }
    final protocolName = _oscProtocolDisplayName(request.protocol);
    final promptTitle = switch (request.operation) {
      terminal.TerminalClipboardOperation.copy =>
        'Allow $protocolName clipboard copy?',
      terminal.TerminalClipboardOperation.pasteRequest =>
        'Allow $protocolName paste read?',
      terminal.TerminalClipboardOperation.mimeWrite =>
        'Allow ${_oscProtocolDisplayName(request.protocol)} clipboard write?',
      terminal.TerminalClipboardOperation.mimeRead =>
        'Allow ${_oscProtocolDisplayName(request.protocol)} clipboard read?',
    };
    final result = await showDialog<terminal.TerminalClipboardAuthorization>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(promptTitle),
          content: _buildOsc52PromptContent(request),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(terminal.TerminalClipboardAuthorization.denied),
              child: const Text('Deny'),
            ),
            if (request.canRememberPassword)
              TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(terminal.TerminalClipboardAuthorization.allowSession),
                child: const Text('Always allow'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(terminal.TerminalClipboardAuthorization.allowOnce),
              child: const Text('Allow'),
            ),
          ],
        );
      },
    );
    return result ?? terminal.TerminalClipboardAuthorization.denied;
  }

  Widget _buildOsc52PromptContent(SessionOsc52PromptRequest request) {
    final isPasteRequest =
        request.operation == terminal.TerminalClipboardOperation.pasteRequest ||
        request.operation == terminal.TerminalClipboardOperation.mimeRead;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final details = <Widget>[
      _Osc52PromptDetail(
        label: 'Session',
        value: _osc52SessionDetailValue(request.sessionId),
      ),
      _Osc52PromptDetail(label: 'Selection', value: request.selection ?? 'c'),
      if (request.mimeTypes.isNotEmpty)
        _Osc52PromptDetail(
          label: 'MIME types',
          value: request.mimeTypes.join(', '),
        ),
      if (request.applicationName != null)
        _Osc52PromptDetail(
          label: 'Application',
          value: request.applicationName!,
        ),
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
          if (request.canRememberPassword) ...[
            const SizedBox(height: 8),
            Text(
              '“Always allow” permits future OSC 5522 clipboard reads and writes that use this exact application name and password, only for the current terminal session.',
              style: textTheme.bodySmall,
            ),
          ],
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
    _osc52StatusClearTimer?.cancel();
    _mutateState(() {
      _lastOsc52StatusLabel = label;
      _lastOsc52StatusEvent = event;
      _lastOsc52StatusSessionId = event.sessionId;
    });
    _showShellSnackBar(_osc52SnackBarMessageFor(event));
    _osc52StatusClearTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) {
        return;
      }
      _mutateState(() {
        _lastOsc52StatusLabel = null;
        _lastOsc52StatusEvent = null;
        _lastOsc52StatusSessionId = null;
      });
    });
  }

  String _osc52StatusLabelFor(terminal.TerminalSessionClipboardEvent event) {
    final operation = switch (event.operation) {
      terminal.TerminalClipboardOperation.copy => 'COPY',
      terminal.TerminalClipboardOperation.pasteRequest => 'PASTE',
      terminal.TerminalClipboardOperation.mimeWrite => 'MIME WRITE',
      terminal.TerminalClipboardOperation.mimeRead => 'MIME READ',
    };
    final decision = switch (event.decision) {
      terminal.TerminalClipboardDecision.allowed => 'OK',
      terminal.TerminalClipboardDecision.blocked => 'BLOCKED',
      terminal.TerminalClipboardDecision.invalidPayload => 'INVALID',
    };
    return '${event.protocol.toUpperCase()} $operation $decision';
  }

  String _osc52StatusTooltipFor(terminal.TerminalSessionClipboardEvent event) {
    final operation = switch (event.operation) {
      terminal.TerminalClipboardOperation.copy => 'clipboard write',
      terminal.TerminalClipboardOperation.pasteRequest => 'clipboard read',
      terminal.TerminalClipboardOperation.mimeWrite =>
        'multi-format clipboard write',
      terminal.TerminalClipboardOperation.mimeRead =>
        'multi-format clipboard read',
    };
    final decision = switch (event.decision) {
      terminal.TerminalClipboardDecision.allowed => 'allowed',
      terminal.TerminalClipboardDecision.blocked => 'blocked',
      terminal.TerminalClipboardDecision.invalidPayload => 'invalid payload',
    };
    return [
      '${_oscProtocolDisplayName(event.protocol)} $operation $decision',
      'Session: ${_osc52SessionDetailValue(event.sessionId)}',
      if (event.selection != null) 'Selection: ${event.selection}',
      if (event.characterCount != null) 'Characters: ${event.characterCount}',
      if (event.byteCount != null) 'Bytes: ${event.byteCount}',
      if (event.mimeTypes.isNotEmpty)
        'MIME types: ${event.mimeTypes.join(', ')}',
      if (event.textPreview != null)
        'Preview: ${_visibleOsc52Preview(event.textPreview!)}'
            '${event.textPreviewTruncated ? '\n... preview truncated' : ''}',
      if (_osc52BlockedCount > 0) 'Blocked in this window: $_osc52BlockedCount',
      if (_osc52StatusShouldOfferPaneFocus(event)) 'Click to focus this pane.',
    ].join('\n');
  }

  String _oscProtocolDisplayName(String protocol) =>
      switch (protocol.toLowerCase()) {
        'osc52' => 'OSC 52',
        'osc5522' => 'OSC 5522',
        'iterm1337' => 'iTerm2 OSC 1337',
        _ => protocol.toUpperCase(),
      };

  bool _osc52StatusShouldOfferPaneFocus(
    terminal.TerminalSessionClipboardEvent event,
  ) {
    final state = ref.read(sessionControllerProvider);
    final tab = _tabForSession(state, event.sessionId);
    return tab != null &&
        tab.effectivePanes.length > 1 &&
        state.activeSessionId != event.sessionId;
  }

  String _osc52SessionDetailValue(String? sessionId) {
    final state = ref.read(sessionControllerProvider);
    final resolvedSessionId = sessionId ?? state.activeSessionId;
    if (resolvedSessionId == null) {
      return 'current';
    }
    final pane = _paneForSession(state, resolvedSessionId);
    final paneState = state.activeSessionId == resolvedSessionId
        ? 'active pane'
        : 'inactive pane';
    if (pane == null) {
      return '$resolvedSessionId · $paneState';
    }
    return '${pane.title} ($resolvedSessionId) · $paneState';
  }

  String _osc52SnackBarMessageFor(
    terminal.TerminalSessionClipboardEvent event,
  ) {
    final count = event.characterCount;
    final protocolName = _oscProtocolDisplayName(event.protocol);
    final message = switch ((event.operation, event.decision)) {
      (
        terminal.TerminalClipboardOperation.copy,
        terminal.TerminalClipboardDecision.allowed,
      ) =>
        '$protocolName copied ${count ?? 0} characters to the clipboard',
      (
        terminal.TerminalClipboardOperation.copy,
        terminal.TerminalClipboardDecision.blocked,
      ) =>
        '$protocolName clipboard copy blocked by policy',
      (
        terminal.TerminalClipboardOperation.copy,
        terminal.TerminalClipboardDecision.invalidPayload,
      ) =>
        '$protocolName clipboard copy ignored: invalid payload',
      (
        terminal.TerminalClipboardOperation.pasteRequest,
        terminal.TerminalClipboardDecision.allowed,
      ) =>
        '$protocolName paste read replied with ${count ?? 0} characters',
      (
        terminal.TerminalClipboardOperation.pasteRequest,
        terminal.TerminalClipboardDecision.blocked,
      ) =>
        '$protocolName paste read blocked by policy',
      (
        terminal.TerminalClipboardOperation.pasteRequest,
        terminal.TerminalClipboardDecision.invalidPayload,
      ) =>
        '$protocolName paste read ignored: invalid payload',
      (
        terminal.TerminalClipboardOperation.mimeWrite,
        terminal.TerminalClipboardDecision.allowed,
      ) =>
        'OSC 5522 wrote ${event.mimeTypes.length} MIME types (${event.byteCount ?? 0} bytes)',
      (
        terminal.TerminalClipboardOperation.mimeWrite,
        terminal.TerminalClipboardDecision.blocked,
      ) =>
        'OSC 5522 MIME clipboard write blocked by policy',
      (
        terminal.TerminalClipboardOperation.mimeWrite,
        terminal.TerminalClipboardDecision.invalidPayload,
      ) =>
        'OSC 5522 MIME clipboard write failed',
      (
        terminal.TerminalClipboardOperation.mimeRead,
        terminal.TerminalClipboardDecision.allowed,
      ) =>
        'OSC 5522 replied with ${event.mimeTypes.length} MIME types (${event.byteCount ?? 0} bytes)',
      (
        terminal.TerminalClipboardOperation.mimeRead,
        terminal.TerminalClipboardDecision.blocked,
      ) =>
        'OSC 5522 MIME clipboard read blocked by policy',
      (
        terminal.TerminalClipboardOperation.mimeRead,
        terminal.TerminalClipboardDecision.invalidPayload,
      ) =>
        'OSC 5522 MIME clipboard read failed',
    };
    if (!_osc52StatusShouldOfferPaneFocus(event)) {
      return message;
    }
    return '$message · ${_osc52SessionDetailValue(event.sessionId)}';
  }

  void _handleOscNotification(terminal.TerminalSessionNotificationEvent event) {
    final protocolIdentifier = event.identifier?.trim();
    final systemIdentifier =
        protocolIdentifier == null || protocolIdentifier.isEmpty
        ? null
        : 'ianvs-terminal.osc.${event.sessionId}.$protocolIdentifier';
    if (event.isClose) {
      if (systemIdentifier != null) {
        unawaited(ref.read(shellNotificationCloserProvider)(systemIdentifier));
      }
      return;
    }
    final title = event.title.trim();
    final message = event.message.trim();
    final visibleTitle = title.isEmpty ? 'Terminal notification' : title;
    final visibleMessage = message.isEmpty ? visibleTitle : message;
    _showShellSnackBar(
      _oscNotificationSnackBarMessage(
        event,
        title: visibleTitle,
        message: visibleMessage,
      ),
    );
    if (!_activityNotificationsEnabled ||
        !_notificationSessionIsInactive(event.sessionId) ||
        (event.action != 'update' &&
            !_activityNotificationAllowed(event.sessionId))) {
      return;
    }
    final remoteContext = _oscNotificationRemoteContext(event.sessionId);
    _sendShellNotification(
      title: remoteContext == null
          ? '$visibleTitle in ${_sessionTitleForNotification(event.sessionId)}'
          : '$visibleTitle on $remoteContext in ${_sessionTitleForNotification(event.sessionId)}',
      body: visibleMessage,
      identifier:
          systemIdentifier ??
          'ianvs-terminal.osc.${event.sessionId}.${DateTime.now().microsecondsSinceEpoch}',
      expiresAfterMs: event.expiresAfterMs,
    );
  }

  String _oscNotificationSnackBarMessage(
    terminal.TerminalSessionNotificationEvent event, {
    required String title,
    required String message,
  }) {
    final baseMessage = '$title: $message';
    if (!_notificationSessionIsInactive(event.sessionId)) {
      return baseMessage;
    }
    return '$baseMessage · ${_terminalPaneContextLine(event.sessionId)}';
  }

  String? _oscNotificationRemoteContext(String sessionId) {
    final state = ref.read(sessionControllerProvider);
    final pane = _paneForSession(state, sessionId);
    final hostname = pane?.shellIntegration.hostname?.trim();
    if (!_shellHostIsRemote(hostname)) {
      return null;
    }
    final username = pane?.shellIntegration.username?.trim();
    if (username != null && username.isNotEmpty) {
      return '$username@$hostname';
    }
    return hostname;
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
        preview != null) {
      _sendOrScheduleActivityNotification(sessionId, preview);
    }
  }

  void _sendOrScheduleActivityNotification(String sessionId, String preview) {
    if (_activityNotificationAllowed(sessionId)) {
      _activityNotificationTrailingTimers.remove(sessionId)?.cancel();
      _sendShellNotification(
        title: 'Activity in ${_sessionTitleForNotification(sessionId)}',
        body: preview,
        identifier: 'ianvs-terminal.activity.$sessionId',
      );
      return;
    }

    _activityNotificationTrailingTimers.remove(sessionId)?.cancel();
    _activityNotificationTrailingTimers[sessionId] = Timer(
      _ShellScreenState._activityNotificationTrailingDelay,
      () {
        _activityNotificationTrailingTimers.remove(sessionId);
        if (!mounted ||
            !_activityNotificationsEnabled ||
            !_notificationSessionIsInactive(sessionId)) {
          return;
        }
        final latestPreview = _lastActivityFramePreviews[sessionId];
        if (latestPreview == null) {
          return;
        }
        _lastActivityNotificationAt[sessionId] = DateTime.now();
        _sendShellNotification(
          title: 'Activity in ${_sessionTitleForNotification(sessionId)}',
          body: latestPreview,
          identifier: 'ianvs-terminal.activity.$sessionId',
        );
      },
    );
  }

  void _markNewOutputBadge(String sessionId, terminal.TerminalFrameDiff frame) {
    final preview = _framePreview(frame);
    final hasSeenSession = !_sessionsSeenForNewOutputBadges.add(sessionId);
    final previousPreview = _lastNewOutputFramePreviews[sessionId];
    _lastNewOutputFramePreviews[sessionId] = preview;
    if (!hasSeenSession ||
        previousPreview == preview ||
        preview == null ||
        !_sessionIsInactive(sessionId)) {
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
      title: _commandFinishedNotificationTitle(event.sessionId),
      body: [
        if (command != null && command.trim().isNotEmpty) command.trim(),
        if (exitCode != null) 'Exit code $exitCode',
      ].join('\n'),
      identifier:
          'ianvs-terminal.command.${event.sessionId}.${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  String _commandFinishedNotificationTitle(String sessionId) {
    final remoteContext = _oscNotificationRemoteContext(sessionId);
    if (remoteContext != null) {
      return 'Command finished on $remoteContext in ${_sessionTitleForNotification(sessionId)}';
    }
    if (!_sessionIsInMultiPaneTab(sessionId)) {
      return 'Command finished';
    }
    return 'Command finished in ${_sessionTitleForNotification(sessionId)}';
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
