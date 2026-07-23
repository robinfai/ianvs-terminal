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
        _recordInstantReplayShellHook(event);
        _notifyShellHook(event);
      case terminal.TerminalSessionShellContextEvent():
        _recordInstantReplayShellContext(event);
      case terminal.TerminalSessionShellCommandEvent():
        _recordInstantReplayShellCommand(event);
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
      case terminal.TerminalSessionFileDownloadEvent():
        _handleOsc1337FileDownload(event);
      case terminal.TerminalSessionFileDownloadFailedEvent():
        _handleOsc1337FileDownloadFailure(event);
      case terminal.TerminalSessionFileUploadDeniedEvent():
        _handleOsc1337FileUploadDenied(event);
      case terminal.TerminalSessionCellSizeReportRequestEvent():
        // The reusable runtime already replied using its committed cell metric.
        break;
      case terminal.TerminalSessionClearCapturedOutputEvent():
        if (event.isValid) {
          _clearCapturedOutput(event.sessionId);
        }
      case terminal.TerminalSessionReportVariableRequestEvent():
        _handleOsc1337ReportVariableRequest(event);
      case terminal.TerminalSessionOpenUrlRequestEvent():
        _handleOsc1337OpenUrlRequest(event);
      case terminal.TerminalSessionAttentionRequestEvent():
        _handleOsc1337AttentionRequest(event);
      case terminal.TerminalSessionResetEvent():
        unawaited(_osc72DragDropController.resetSession(event.sessionId));
        _clearPresentationStateForSession(event.sessionId);
      case terminal.TerminalSessionClipboardEvent():
        _handleOsc52ClipboardEvent(event);
      case terminal.TerminalSessionBackendErrorEvent():
        break;
    }
  }

  void _handleOsc1337OpenUrlRequest(
    terminal.TerminalSessionOpenUrlRequestEvent event,
  ) {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (!event.isValid || activeSessionId != event.sessionId || !mounted) {
      return;
    }
    if (_hostActionsConfig.osc1337OpenUrl ==
        LocalTerminalOpenUrlPolicy.disabled) {
      _showShellSnackBar('OSC 1337 Open URL blocked by policy');
      return;
    }
    final now = _clock();
    final lastPromptAt = _lastOsc1337OpenUrlPromptAt;
    if (_osc1337OpenUrlPromptActive ||
        (lastPromptAt != null &&
            now.difference(lastPromptAt) <
                _ShellScreenState._osc1337OpenUrlPromptCooldown)) {
      return;
    }
    _osc1337OpenUrlPromptActive = true;
    _lastOsc1337OpenUrlPromptAt = now;
    unawaited(_confirmOsc1337OpenUrl(event));
  }

  void _handleOsc1337ReportVariableRequest(
    terminal.TerminalSessionReportVariableRequestEvent event,
  ) {
    final name = event.name;
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    final now = _clock();
    final lastPromptAt = _lastOsc1337ReportVariablePromptAt;
    if (!event.isSupported ||
        name == null ||
        activeSessionId != event.sessionId ||
        _hostActionsConfig.osc1337ReportVariables.containsKey(name) ||
        _osc1337ReportVariablePromptActive ||
        (lastPromptAt != null &&
            now.difference(lastPromptAt) <
                _ShellScreenState._osc1337ReportVariablePromptCooldown) ||
        !mounted) {
      return;
    }
    _osc1337ReportVariablePromptActive = true;
    _lastOsc1337ReportVariablePromptAt = now;
    unawaited(_confirmOsc1337ReportVariable(event, name));
  }

  void _handleOsc1337AttentionRequest(
    terminal.TerminalSessionAttentionRequestEvent event,
  ) {
    if (!event.isValid || !_sessionExists(event.sessionId)) {
      return;
    }
    if (event.action == 'no') {
      unawaited(_cancelOsc1337AttentionRequest(event.sessionId));
      return;
    }
    if (_hostActionsConfig.osc1337RequestAttention !=
        LocalTerminalRequestAttentionPolicy.allow) {
      return;
    }
    if (event.action == 'fireworks') {
      _showOsc1337Fireworks(event.sessionId);
      return;
    }
    unawaited(
      _requestOsc1337SystemAttention(
        event.sessionId,
        critical: event.action == 'yes',
      ),
    );
  }

  Future<void> _requestOsc1337SystemAttention(
    String sessionId, {
    required bool critical,
  }) async {
    if (!_sessionExists(sessionId) ||
        _hostActionsConfig.osc1337RequestAttention !=
            LocalTerminalRequestAttentionPolicy.allow ||
        _osc1337AttentionRequestsPending.contains(sessionId)) {
      return;
    }
    final now = _clock();
    final lastSessionRequest = _lastOsc1337SystemAttentionAt[sessionId];
    final lastGlobalRequest = _lastOsc1337GlobalSystemAttentionAt;
    if ((lastSessionRequest != null &&
            now.difference(lastSessionRequest) <
                _ShellScreenState._osc1337SystemAttentionSessionCooldown) ||
        (lastGlobalRequest != null &&
            now.difference(lastGlobalRequest) <
                _ShellScreenState._osc1337SystemAttentionGlobalCooldown)) {
      return;
    }
    final reservedSessions = <String>{
      ..._osc1337AttentionRequestIds.keys,
      ..._osc1337AttentionRequestsPending,
    };
    if (!_osc1337AttentionRequestIds.containsKey(sessionId) &&
        reservedSessions.length >=
            _ShellScreenState._osc1337MaxOutstandingAttentionRequests) {
      return;
    }

    final epoch = (_osc1337AttentionEpochs[sessionId] ?? 0) + 1;
    _osc1337AttentionEpochs[sessionId] = epoch;
    _osc1337AttentionRequestsPending.add(sessionId);
    _lastOsc1337SystemAttentionAt[sessionId] = now;
    _lastOsc1337GlobalSystemAttentionAt = now;

    final previousRequestId = _osc1337AttentionRequestIds.remove(sessionId);
    if (previousRequestId != null) {
      await _userAttentionBridge.cancel(previousRequestId);
    }
    if (!_sessionExists(sessionId) ||
        _hostActionsConfig.osc1337RequestAttention !=
            LocalTerminalRequestAttentionPolicy.allow ||
        _osc1337AttentionEpochs[sessionId] != epoch) {
      _osc1337AttentionRequestsPending.remove(sessionId);
      return;
    }

    final requestId = await _userAttentionBridge.request(
      critical
          ? NativeUserAttentionType.critical
          : NativeUserAttentionType.informational,
    );
    _osc1337AttentionRequestsPending.remove(sessionId);
    if (requestId == null) {
      return;
    }
    if (!_sessionExists(sessionId) ||
        _hostActionsConfig.osc1337RequestAttention !=
            LocalTerminalRequestAttentionPolicy.allow ||
        _osc1337AttentionEpochs[sessionId] != epoch) {
      await _userAttentionBridge.cancel(requestId);
      return;
    }
    final superseded = _osc1337AttentionRequestIds[sessionId];
    if (superseded != null && superseded != requestId) {
      await _userAttentionBridge.cancel(superseded);
    }
    _osc1337AttentionRequestIds[sessionId] = requestId;
  }

  Future<void> _cancelOsc1337AttentionRequest(String sessionId) async {
    _osc1337AttentionEpochs[sessionId] =
        (_osc1337AttentionEpochs[sessionId] ?? 0) + 1;
    _osc1337AttentionRequestsPending.remove(sessionId);
    _lastOsc1337SystemAttentionAt.remove(sessionId);
    final requestId = _osc1337AttentionRequestIds.remove(sessionId);
    if (requestId != null) {
      await _userAttentionBridge.cancel(requestId);
    }
  }

  Future<void> _cancelAllOsc1337AttentionRequests() async {
    final sessionIds = <String>{
      ..._osc1337AttentionRequestIds.keys,
      ..._osc1337AttentionRequestsPending,
    };
    final requestIds = _osc1337AttentionRequestIds.values.toList(
      growable: false,
    );
    for (final sessionId in sessionIds) {
      _osc1337AttentionEpochs[sessionId] =
          (_osc1337AttentionEpochs[sessionId] ?? 0) + 1;
    }
    _osc1337AttentionRequestIds.clear();
    _osc1337AttentionRequestsPending.clear();
    _lastOsc1337SystemAttentionAt.clear();
    _lastOsc1337GlobalSystemAttentionAt = null;
    await Future.wait(requestIds.map(_userAttentionBridge.cancel));
  }

  void _showOsc1337Fireworks(String sessionId) {
    final now = _clock();
    final lastShown = _lastOsc1337FireworksAt[sessionId];
    if (lastShown != null &&
        now.difference(lastShown) <
            _ShellScreenState._osc1337FireworksCooldown) {
      return;
    }
    _lastOsc1337FireworksAt[sessionId] = now;
    _osc1337FireworksTimers.remove(sessionId)?.cancel();
    _mutateState(() {
      _osc1337FireworksSerials[sessionId] =
          (_osc1337FireworksSerials[sessionId] ?? 0) + 1;
    });
    _osc1337FireworksTimers[sessionId] = Timer(
      _ShellScreenState._osc1337FireworksLifetime,
      () {
        _osc1337FireworksTimers.remove(sessionId);
        if (!mounted) {
          return;
        }
        _mutateState(() {
          _osc1337FireworksSerials.remove(sessionId);
        });
      },
    );
  }

  Future<void> _confirmOsc1337OpenUrl(
    terminal.TerminalSessionOpenUrlRequestEvent event,
  ) async {
    final url = event.url!;
    final uri = Uri.parse(url);
    final scheme = uri.scheme.toLowerCase();
    final sourceContext = _sessionIsInMultiPaneTab(event.sessionId)
        ? _terminalPaneContextLine(event.sessionId)
        : null;
    bool? approved;
    try {
      approved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final destination = scheme == 'file'
              ? 'Local file'
              : '${scheme.toUpperCase()} host: ${uri.host}';
          return AlertDialog(
            key: const Key('osc1337-open-url-dialog'),
            title: const Text('Open terminal-requested URL?'),
            content: SelectableText(
              [
                'The active terminal requested permission to open this URL. Terminal output can be untrusted.',
                if (sourceContext != null) 'Source: $sourceContext',
                'Destination: $destination',
                '',
                url,
              ].join('\n'),
            ),
            actions: [
              TextButton(
                key: const Key('osc1337-open-url-deny'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Deny'),
              ),
              FilledButton(
                key: const Key('osc1337-open-url-approve'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Open'),
              ),
            ],
          );
        },
      );
    } finally {
      _osc1337OpenUrlPromptActive = false;
    }
    if (!mounted) {
      return;
    }
    if (approved != true) {
      _showShellSnackBar('OSC 1337 Open URL blocked');
      return;
    }
    if (ref.read(sessionControllerProvider).activeSessionId !=
        event.sessionId) {
      _showShellSnackBar(
        'OSC 1337 Open URL blocked: source is no longer active',
      );
      return;
    }
    await _openTerminalLink(
      url,
      sourceSessionId: event.sessionId,
      filePermissionGranted: true,
    );
  }

  Future<void> _confirmOsc1337ReportVariable(
    terminal.TerminalSessionReportVariableRequestEvent event,
    String name,
  ) async {
    final sourceContext = _sessionIsInMultiPaneTab(event.sessionId)
        ? _terminalPaneContextLine(event.sessionId)
        : null;
    LocalTerminalReportVariablePolicy? decision;
    try {
      decision = await showDialog<LocalTerminalReportVariablePolicy>(
        context: context,
        builder: (dialogContext) {
          final appTheme = dialogContext.appTheme;
          return AlertDialog(
            key: const Key('osc1337-report-variable-dialog'),
            title: const Text('Allow future variable reports?'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'The current request was denied and received an empty response. Choose whether future terminal programs may read this variable.',
                  ),
                  if (sourceContext != null) ...[
                    SizedBox(height: appTheme.spacing.md),
                    Text('Source: $sourceContext'),
                  ],
                  SizedBox(height: appTheme.spacing.md),
                  const Text('Variable'),
                  SizedBox(height: appTheme.spacing.xs),
                  SelectableText(
                    name,
                    key: const Key('osc1337-report-variable-name'),
                  ),
                  SizedBox(height: appTheme.spacing.md),
                  const Text(
                    'Ianvs only reports session-owned title, dimensions, shell context, and user.* values. It never reads host environment variables or files for this request.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                key: const Key('osc1337-report-variable-not-now'),
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Not Now'),
              ),
              TextButton(
                key: const Key('osc1337-report-variable-allow'),
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(LocalTerminalReportVariablePolicy.allow),
                child: const Text('Always Allow'),
              ),
              FilledButton(
                key: const Key('osc1337-report-variable-deny'),
                autofocus: true,
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(LocalTerminalReportVariablePolicy.deny),
                child: const Text('Always Deny'),
              ),
            ],
          );
        },
      );
    } finally {
      _osc1337ReportVariablePromptActive = false;
    }
    if (!mounted || decision == null) {
      return;
    }
    if (ref.read(sessionControllerProvider).activeSessionId !=
        event.sessionId) {
      _showShellSnackBar(
        'Variable-reporting decision not saved: source is no longer active',
      );
      return;
    }
    await ref
        .read(sessionControllerProvider.notifier)
        .setOsc1337ReportVariableDecision(name, decision);
    if (!mounted) {
      return;
    }
    final decisions = <String, LocalTerminalReportVariablePolicy>{
      ..._hostActionsConfig.osc1337ReportVariables,
    }..remove(name);
    while (decisions.length >= maxLocalTerminalReportVariableDecisions) {
      decisions.remove(decisions.keys.first);
    }
    decisions[name] = decision;
    _mutateState(() {
      _hostActionsConfig = _hostActionsConfig.copyWith(
        osc1337ReportVariables: Map.unmodifiable(decisions),
      );
    });
    _showShellSnackBar(
      decision == LocalTerminalReportVariablePolicy.allow
          ? 'Future reports of $name are allowed'
          : 'Future reports of $name are denied',
    );
  }

  void _handleOsc1337FileDownload(
    terminal.TerminalSessionFileDownloadEvent event,
  ) {
    final runtime = ref.read(terminalRuntimeControllerProvider);
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (!event.isValid || activeSessionId != event.sessionId || !mounted) {
      runtime.discardFileDownload(event);
      return;
    }

    final downloadId = event.downloadId!;
    final messenger = ScaffoldMessenger.of(context);
    var actionClaimed = false;
    final controller = messenger.showSnackBar(
      SnackBar(
        key: Key('osc1337-file-download-$downloadId'),
        content: Text(
          'Received ${event.filename} (${_osc1337FileSizeLabel(event.size!)})',
        ),
        duration: const Duration(seconds: 30),
        showCloseIcon: true,
        action: SnackBarAction(
          key: Key('osc1337-file-download-save-$downloadId'),
          label: 'Save',
          onPressed: () {
            actionClaimed = true;
            unawaited(_saveOsc1337FileDownload(event));
          },
        ),
      ),
    );
    unawaited(
      controller.closed.then((reason) {
        if (!actionClaimed && reason != SnackBarClosedReason.action) {
          runtime.discardFileDownload(event);
        }
      }),
    );
  }

  Future<void> _saveOsc1337FileDownload(
    terminal.TerminalSessionFileDownloadEvent event,
  ) async {
    final runtime = ref.read(terminalRuntimeControllerProvider);
    if (!mounted ||
        ref.read(sessionControllerProvider).activeSessionId !=
            event.sessionId) {
      runtime.discardFileDownload(event);
      return;
    }

    String? path;
    try {
      path = await WindowBridge.chooseFileDownloadLocation(
        suggestedName: event.filename!,
      );
    } on Object {
      runtime.discardFileDownload(event);
      _showShellSnackBar('Could not open the save dialog');
      return;
    }
    if (path == null) {
      runtime.discardFileDownload(event);
      if (mounted) {
        _showShellSnackBar('Received file discarded');
      }
      return;
    }

    final bytes = runtime.takeFileDownload(event);
    if (bytes == null || bytes.length != event.size) {
      _showShellSnackBar('Received file is no longer available');
      return;
    }
    try {
      await ref.read(shellFileDownloadWriterProvider)(path, bytes);
    } on Object {
      _showShellSnackBar('Could not save ${event.filename}');
      return;
    }
    if (mounted) {
      _showShellSnackBar('Saved ${event.filename}');
    }
  }

  void _handleOsc1337FileDownloadFailure(
    terminal.TerminalSessionFileDownloadFailedEvent event,
  ) {
    if (!mounted ||
        ref.read(sessionControllerProvider).activeSessionId !=
            event.sessionId) {
      return;
    }
    final reason = event.reason.runes.take(120).toList(growable: false);
    _showShellSnackBar(
      'File download rejected: ${String.fromCharCodes(reason)}',
    );
  }

  void _handleOsc1337FileUploadDenied(
    terminal.TerminalSessionFileUploadDeniedEvent event,
  ) {
    if (!mounted ||
        ref.read(sessionControllerProvider).activeSessionId !=
            event.sessionId) {
      return;
    }
    _showShellSnackBar('File upload request blocked');
  }

  String _osc1337FileSizeLabel(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
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
    _showShellSnackBar(_osc52SnackBarMessageFor(event));
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

  void _handleOscNotificationInteraction(
    _ShellNotificationInteraction interaction,
  ) {
    if (interaction.notification.identifier == null ||
        interaction.notification.source != 'osc99') {
      return;
    }
    final controller = ref.read(sessionControllerProvider.notifier);
    switch (interaction.kind) {
      case _ShellNotificationInteractionKind.activate:
        controller.reportSessionNotificationAction(
          interaction.sessionId,
          interaction.notification,
        );
      case _ShellNotificationInteractionKind.button:
        controller.reportSessionNotificationAction(
          interaction.sessionId,
          interaction.notification,
          buttonNumber: interaction.buttonNumber,
        );
      case _ShellNotificationInteractionKind.dismiss:
        controller.dismissSessionNotification(
          interaction.sessionId,
          interaction.notification,
        );
    }
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
      _hostActionsConfig = configBootstrap.config.hostActions;
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
