part of 'shell_screen.dart';

extension _ShellScreenStateEvents on _ShellScreenState {
  bool get _shellModalInputBlocked =>
      _isCommandMenuOpen ||
      _isDefaultsOpen ||
      _isProfilesOpen ||
      ModalRoute.of(context)?.isCurrent == false;

  void _handleTerminalUiEffect(TerminalUiEffect effect) {
    final coordinator = ref.read(terminalEventCoordinatorProvider);
    if (!mounted || !coordinator.isCurrentUiEffect(effect)) {
      return;
    }
    switch (effect) {
      case TerminalSessionUiEffect():
        _handleTerminalSessionEvent(
          effect.event,
          exitContext: effect.exitContext,
        );
      case TerminalZmodemUiEffect():
        _handleZmodemEvent(effect.event);
      case TerminalZmodemDeferredFailureUiEffect():
        _handleZmodemDeferredWriteFailure(effect.diagnostic);
    }
  }

  Future<void> _handleNativePasteMenu() async {
    final editableText = focusedEditableTextForCurrentRoute();
    if (editableText != null) {
      await editableText.pasteText(SelectionChangedCause.toolbar);
      return;
    }
    if (_shellModalInputBlocked) return;
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

  void _handleTerminalSessionEvent(
    terminal.TerminalSessionEvent event, {
    TerminalSessionExitUiContext? exitContext,
  }) {
    switch (event) {
      case terminal.TerminalSessionSshAuthPromptEvent():
        unawaited(
          _sshAuthPromptPresenter.enqueue(context, event, ({
            required event,
            required responses,
            required cancel,
          }) {
            return ref
                .read(terminalRuntimeControllerProvider)
                .respondSshAuthentication(
                  event.sessionId,
                  challengeId: event.challengeId!,
                  responses: responses,
                  cancel: cancel,
                );
          }),
        );
      case terminal.TerminalSessionSshHostKeyPromptEvent():
        _sshHostKeyPromptPresenter.present(
          context,
          event,
          ref.read(terminalRuntimeControllerProvider),
        );
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
        _notifySessionExit(
          event.sessionId,
          event.exitCode,
          exitContext: exitContext,
        );
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
      _showShellSnackBar(context.l10n.osc1337OpenUrlBlockedByPolicy);
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
              ? dialogContext.l10n.localFile
              : dialogContext.l10n.protocolHost(scheme.toUpperCase(), uri.host);
          return AlertDialog(
            key: const Key('osc1337-open-url-dialog'),
            title: Text(dialogContext.l10n.openTerminalRequestedUrlQuestion),
            content: SelectableText(
              [
                dialogContext.l10n.terminalRequestedUrlWarning,
                if (sourceContext != null)
                  dialogContext.l10n.sourceValue(sourceContext),
                dialogContext.l10n.destinationValue(destination),
                '',
                url,
              ].join('\n'),
            ),
            actions: [
              TextButton(
                key: const Key('osc1337-open-url-deny'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(dialogContext.l10n.deny),
              ),
              FilledButton(
                key: const Key('osc1337-open-url-approve'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(dialogContext.l10n.open),
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
      _showShellSnackBar(context.l10n.osc1337OpenUrlBlocked);
      return;
    }
    if (ref.read(sessionControllerProvider).activeSessionId !=
        event.sessionId) {
      _showShellSnackBar(context.l10n.osc1337OpenUrlSourceInactive);
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
            title: Text(dialogContext.l10n.allowFutureVariableReportsQuestion),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dialogContext.l10n.variableReportDeniedHelp),
                  if (sourceContext != null) ...[
                    SizedBox(height: appTheme.spacing.md),
                    Text(dialogContext.l10n.sourceValue(sourceContext)),
                  ],
                  SizedBox(height: appTheme.spacing.md),
                  Text(dialogContext.l10n.variable),
                  SizedBox(height: appTheme.spacing.xs),
                  SelectableText(
                    name,
                    key: const Key('osc1337-report-variable-name'),
                  ),
                  SizedBox(height: appTheme.spacing.md),
                  Text(dialogContext.l10n.variableReportPrivacyHelp),
                ],
              ),
            ),
            actions: [
              TextButton(
                key: const Key('osc1337-report-variable-not-now'),
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(dialogContext.l10n.notNow),
              ),
              TextButton(
                key: const Key('osc1337-report-variable-allow'),
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(LocalTerminalReportVariablePolicy.allow),
                child: Text(dialogContext.l10n.alwaysAllow),
              ),
              FilledButton(
                key: const Key('osc1337-report-variable-deny'),
                autofocus: true,
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(LocalTerminalReportVariablePolicy.deny),
                child: Text(dialogContext.l10n.alwaysDeny),
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
      _showShellSnackBar(context.l10n.variableDecisionSourceInactive);
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
          ? context.l10n.futureVariableReportsAllowed(name)
          : context.l10n.futureVariableReportsDenied(name),
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
          context.l10n.receivedFile(
            event.filename!,
            _osc1337FileSizeLabel(event.size!),
          ),
        ),
        duration: const Duration(seconds: 30),
        showCloseIcon: true,
        action: SnackBarAction(
          key: Key('osc1337-file-download-save-$downloadId'),
          label: context.l10n.save,
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
    final l10n = context.l10n;
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
      _showShellSnackBar(l10n.couldNotOpenSaveDialog);
      return;
    }
    if (path == null) {
      runtime.discardFileDownload(event);
      if (mounted) {
        _showShellSnackBar(l10n.receivedFileDiscarded);
      }
      return;
    }

    final bytes = runtime.takeFileDownload(event);
    if (bytes == null || bytes.length != event.size) {
      _showShellSnackBar(l10n.receivedFileUnavailable);
      return;
    }
    try {
      await ref.read(shellFileDownloadWriterProvider)(path, bytes);
    } on Object {
      _showShellSnackBar(l10n.couldNotSaveFile(event.filename!));
      return;
    }
    if (mounted) {
      _showShellSnackBar(l10n.savedFile(event.filename!));
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
      context.l10n.fileDownloadRejected(String.fromCharCodes(reason)),
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
    _showShellSnackBar(context.l10n.fileUploadRequestBlocked);
  }

  void _handleZmodemDeferredWriteFailure(
    terminal.TerminalSessionZmodemDeferredWriteFailedDiagnostic diagnostic,
  ) {
    if (!mounted) {
      return;
    }
    final unconfirmedChunks = diagnostic.unconfirmedChunks;
    final unconfirmedBytes = diagnostic.unconfirmedBytes;
    final message = context.l10n.zmodemTransportFailed(
      diagnostic.sessionId,
      unconfirmedBytes,
      unconfirmedChunks,
    );
    _mutateState(() {
      _zmodemTransportFailureSessionIds.add(diagnostic.sessionId);
    });
    ref.read(sessionControllerProvider.notifier).reportRuntimeError(message);
    if (ref.read(sessionControllerProvider).activeSessionId ==
        diagnostic.sessionId) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  void _signalInactiveZmodem(
    String sessionId, {
    required String title,
    required String body,
  }) {
    if (!_notificationSessionIsInactive(sessionId)) {
      return;
    }
    if (!_sessionsWithNewOutput.contains(sessionId)) {
      _mutateState(() {
        _sessionsWithNewOutput.add(sessionId);
      });
    }
    if (!_activityNotificationsEnabled) {
      return;
    }
    _sendShellNotification(
      title: context.l10n.notificationInSession(
        title,
        _sessionTitleForNotification(sessionId),
      ),
      body: body,
      identifier: 'ianvs-terminal.zmodem.$sessionId',
    );
  }

  void _handleZmodemEvent(terminal.TerminalSessionZmodemEvent event) {
    if (!event.isValid || !mounted) {
      return;
    }
    final transferId = event.transferId!;
    final authorizationKey = '${event.sessionId}:$transferId';
    if (event.isTerminal) {
      _invalidateZmodemPickerRequest(event.sessionId, transferId);
      final activeTransfer = _zmodemTransfers[event.sessionId];
      final hasPreservedReceive = event.hasRecoverableReceiveStaging;
      final replacesUnknownTransfer =
          activeTransfer?.event.isReconciliationRequired ?? false;
      final runtimeTransferId = ref
          .read(terminalRuntimeControllerProvider)
          .activeZmodemTransferIdFor(event.sessionId);
      final preservesCurrentReconciliation =
          replacesUnknownTransfer &&
          runtimeTransferId != null &&
          runtimeTransferId != transferId;
      if (activeTransfer?.transferId != transferId &&
          !replacesUnknownTransfer &&
          !hasPreservedReceive) {
        return;
      }
      _mutateState(() {
        if ((activeTransfer?.transferId == transferId &&
                !preservesCurrentReconciliation) ||
            (replacesUnknownTransfer && !preservesCurrentReconciliation)) {
          _zmodemTransfers.remove(event.sessionId);
        }
        _zmodemAuthorizedTransferIds.remove(authorizationKey);
        if (hasPreservedReceive) {
          _zmodemRecoveries[authorizationKey] = event;
        }
      });
      if (hasPreservedReceive) {
        _signalInactiveZmodem(
          event.sessionId,
          title: context.l10n.zmodemFilePreserved,
          body: context.l10n.zmodemFilePreservedBody,
        );
        return;
      }
      final message = switch (event.kind) {
        terminal.TerminalZmodemEventKind.completed =>
          _zmodemTransportFailureSessionIds.contains(event.sessionId)
              ? null
              : event.direction == terminal.TerminalZmodemDirection.receive
              ? context.l10n.zmodemReceiveCompleted
              : context.l10n.zmodemSendCompleted,
        terminal.TerminalZmodemEventKind.cancelled =>
          _zmodemTransportFailureSessionIds.contains(event.sessionId)
              ? null
              : context.l10n.zmodemTransferCancelled,
        terminal.TerminalZmodemEventKind.failed
            when event.reason == 'publish_failed' &&
                event.stagingPreserved == true =>
          context.l10n.zmodemPreservedUnavailable,
        terminal.TerminalZmodemEventKind.failed =>
          context.l10n.zmodemTransferFailed(
            event.reason ?? context.l10n.protocolError,
          ),
        _ => null,
      };
      if (message != null) {
        if (ref.read(sessionControllerProvider).activeSessionId ==
            event.sessionId) {
          _showShellSnackBar(message);
        } else {
          _pendingZmodemTerminalMessages[event.sessionId] = message;
          _signalInactiveZmodem(
            event.sessionId,
            title: context.l10n.zmodemTransferUpdate,
            body: message,
          );
        }
      }
      return;
    }

    final previous = _zmodemTransfers[event.sessionId];
    if (previous != null &&
        previous.transferId != transferId &&
        !previous.event.isReconciliationRequired &&
        !event.isReconciliationRequired) {
      return;
    }
    var next = _ShellZmodemTransferState.fromEvent(event, previous);
    final authorizationWasUnconfirmed =
        previous?.recoveryAction == _ShellZmodemRecoveryAction.authorization;
    final nativeProvedAuthorization = switch (event.kind) {
      terminal.TerminalZmodemEventKind.started ||
      terminal.TerminalZmodemEventKind.progress ||
      terminal.TerminalZmodemEventKind.fileCompleted ||
      terminal.TerminalZmodemEventKind.fileSkipped => true,
      _ => false,
    };
    if (authorizationWasUnconfirmed && nativeProvedAuthorization) {
      next = next.clearRecoverableError();
      if (ref.read(sessionControllerProvider).activeSessionId ==
          event.sessionId) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    }
    _mutateState(() {
      _zmodemTransfers[event.sessionId] = next;
      if (authorizationWasUnconfirmed && nativeProvedAuthorization) {
        // A started/progress event is stronger evidence than a lost or
        // malformed accept response: native already committed the authority.
        // Restore the de-duplication key so a later file offer in the same
        // receive batch cannot reopen the picker and authorize twice.
        _zmodemAuthorizedTransferIds.add(authorizationKey);
      }
    });
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (event.isReconciliationRequired && activeSessionId != event.sessionId) {
      _signalInactiveZmodem(
        event.sessionId,
        title: context.l10n.zmodemTransferNeedsAttention,
        body: context.l10n.zmodemStateLost,
      );
      return;
    }
    if (event.kind == terminal.TerminalZmodemEventKind.fileSkipped &&
        activeSessionId == event.sessionId) {
      _showShellSnackBar(
        event.filename == null
            ? context.l10n.remoteSkippedZmodemFile
            : context.l10n.remoteSkippedNamedFile(event.filename!),
      );
    }

    final needsSendAuthorization =
        event.kind == terminal.TerminalZmodemEventKind.detected &&
        event.direction == terminal.TerminalZmodemDirection.send;
    final needsReceiveAuthorization =
        event.kind == terminal.TerminalZmodemEventKind.fileOffer &&
        event.direction == terminal.TerminalZmodemDirection.receive;
    if (!needsSendAuthorization && !needsReceiveAuthorization) {
      return;
    }
    final runtime = ref.read(terminalRuntimeControllerProvider);
    final requiredFeature = needsSendAuthorization
        ? 'zmodem.send.v1'
        : 'zmodem.receive.v1';
    if (!runtime.supportsRuntimeFeature(requiredFeature) ||
        !WindowBridge.supportsZmodemFileDialogs) {
      final message = !runtime.supportsRuntimeFeature(requiredFeature)
          ? context.l10n.zmodemDirectionUnsupported
          : context.l10n.zmodemFileSelectionUnavailable;
      final cancelled = runtime.cancelZmodem(event);
      if (!cancelled) {
        _setZmodemRecoverableError(
          event,
          '$message ${context.l10n.retryCancellation}',
          _ShellZmodemRecoveryAction.cancel,
        );
      } else if (activeSessionId == event.sessionId) {
        _showShellSnackBar('$message ${context.l10n.transferWasCancelled}');
      }
      if (activeSessionId != event.sessionId) {
        _signalInactiveZmodem(
          event.sessionId,
          title: cancelled
              ? context.l10n.zmodemRequestCancelled
              : context.l10n.zmodemRequestNeedsAttention,
          body: cancelled
              ? '$message ${context.l10n.inactiveTransferWasCancelled}'
              : '$message ${context.l10n.focusPaneRetryCancellation}',
        );
      }
      return;
    }
    if (activeSessionId != event.sessionId) {
      final cancelled = runtime.cancelZmodem(event);
      if (!cancelled) {
        _setZmodemRecoverableError(
          event,
          context.l10n.couldNotCancelAfterSessionChanged,
          _ShellZmodemRecoveryAction.cancel,
        );
      }
      _signalInactiveZmodem(
        event.sessionId,
        title: cancelled
            ? context.l10n.zmodemRequestCancelled
            : context.l10n.zmodemRequestNeedsAttention,
        body: cancelled
            ? context.l10n.remoteZmodemRequestCancelled(
                needsSendAuthorization ? 'send' : 'receive',
              )
            : context.l10n.remoteZmodemRequestCancelFailed(
                needsSendAuthorization ? 'send' : 'receive',
              ),
      );
      return;
    }
    if (!_zmodemAuthorizedTransferIds.add(authorizationKey)) {
      return;
    }
    if (needsSendAuthorization) {
      unawaited(_authorizeZmodemSend(event));
    } else {
      unawaited(_authorizeZmodemReceive(event));
    }
  }

  Future<void> _authorizeZmodemReceive(
    terminal.TerminalSessionZmodemEvent event,
  ) async {
    final runtime = ref.read(terminalRuntimeControllerProvider);
    if (runtime.activeZmodemTransferIdFor(event.sessionId) !=
        event.transferId) {
      return;
    }
    final pickerRequest = _beginZmodemPickerRequest(event);
    if (pickerRequest == null) {
      _setZmodemRecoverableError(
        event,
        context.l10n.zmodemPickerAlreadyOpen,
        _ShellZmodemRecoveryAction.authorization,
      );
      return;
    }
    String? destination;
    Object? pickerError;
    try {
      destination = await WindowBridge.chooseZmodemReceiveDirectory();
    } on Object catch (error) {
      pickerError = error;
    }
    if (!mounted) {
      _finishZmodemPickerRequest(pickerRequest);
      return;
    }
    if (!_isCurrentZmodemPickerRequest(event, pickerRequest)) {
      _finishZmodemPickerRequest(pickerRequest);
      _showZmodemPickerResultIgnored(event);
      return;
    }
    _finishZmodemPickerRequest(pickerRequest);
    if (pickerError != null) {
      if (pickerError is MissingPluginException ||
          pickerError is UnsupportedError) {
        final message = context.l10n.zmodemDestinationSelectionUnavailable;
        if (!runtime.cancelZmodem(event)) {
          _setZmodemRecoverableError(
            event,
            '$message ${context.l10n.retryCancellation}',
            _ShellZmodemRecoveryAction.cancel,
          );
        } else {
          _showShellSnackBar('$message ${context.l10n.transferWasCancelled}');
        }
        return;
      }
      _setZmodemRecoverableError(
        event,
        context.l10n.couldNotOpenDestinationPicker,
        _ShellZmodemRecoveryAction.authorization,
      );
      return;
    }
    if (ref.read(sessionControllerProvider).activeSessionId !=
        event.sessionId) {
      if (!runtime.cancelZmodem(event)) {
        final message = context.l10n.sessionChangedCancellationFailed;
        _setZmodemRecoverableError(
          event,
          message,
          _ShellZmodemRecoveryAction.cancel,
        );
        _signalInactiveZmodem(
          event.sessionId,
          title: context.l10n.zmodemTransferNeedsAttention,
          body: message,
        );
      }
      return;
    }
    if (destination == null) {
      _setZmodemRecoverableError(
        event,
        context.l10n.destinationSelectionCancelled,
        _ShellZmodemRecoveryAction.authorization,
      );
      return;
    }
    if (!runtime.acceptZmodemReceive(event, destination: destination)) {
      _setZmodemRecoverableError(
        event,
        context.l10n.couldNotAuthorizeDestination,
        _ShellZmodemRecoveryAction.authorization,
      );
      return;
    }
    _rememberZmodemReceiveDirectory(event, destination);
  }

  Future<void> _authorizeZmodemSend(
    terminal.TerminalSessionZmodemEvent event,
  ) async {
    final runtime = ref.read(terminalRuntimeControllerProvider);
    if (runtime.activeZmodemTransferIdFor(event.sessionId) !=
        event.transferId) {
      return;
    }
    final pickerRequest = _beginZmodemPickerRequest(event);
    if (pickerRequest == null) {
      _setZmodemRecoverableError(
        event,
        context.l10n.zmodemPickerAlreadyOpen,
        _ShellZmodemRecoveryAction.authorization,
      );
      return;
    }
    List<String>? files;
    Object? pickerError;
    try {
      files = await WindowBridge.chooseZmodemSendFiles();
    } on Object catch (error) {
      pickerError = error;
    }
    if (!mounted) {
      _finishZmodemPickerRequest(pickerRequest);
      return;
    }
    if (!_isCurrentZmodemPickerRequest(event, pickerRequest)) {
      _finishZmodemPickerRequest(pickerRequest);
      _showZmodemPickerResultIgnored(event);
      return;
    }
    _finishZmodemPickerRequest(pickerRequest);
    if (pickerError != null) {
      if (pickerError is MissingPluginException ||
          pickerError is UnsupportedError) {
        final message = context.l10n.zmodemFileSelectionUnavailable;
        if (!runtime.cancelZmodem(event)) {
          _setZmodemRecoverableError(
            event,
            '$message ${context.l10n.retryCancellation}',
            _ShellZmodemRecoveryAction.cancel,
          );
        } else {
          _showShellSnackBar('$message ${context.l10n.transferWasCancelled}');
        }
        return;
      }
      _setZmodemRecoverableError(
        event,
        context.l10n.couldNotOpenFilePicker,
        _ShellZmodemRecoveryAction.authorization,
      );
      return;
    }
    if (ref.read(sessionControllerProvider).activeSessionId !=
        event.sessionId) {
      if (!runtime.cancelZmodem(event)) {
        final message = context.l10n.sessionChangedCancellationFailed;
        _setZmodemRecoverableError(
          event,
          message,
          _ShellZmodemRecoveryAction.cancel,
        );
        _signalInactiveZmodem(
          event.sessionId,
          title: context.l10n.zmodemTransferNeedsAttention,
          body: message,
        );
      }
      return;
    }
    if (files == null) {
      _setZmodemRecoverableError(
        event,
        context.l10n.fileSelectionCancelled,
        _ShellZmodemRecoveryAction.authorization,
      );
      return;
    }
    if (files.length > 256) {
      _setZmodemRecoverableError(
        event,
        context.l10n.zmodemFileLimit,
        _ShellZmodemRecoveryAction.authorization,
      );
      return;
    }
    if (!runtime.acceptZmodemSend(event, files: files)) {
      _setZmodemRecoverableError(
        event,
        context.l10n.couldNotAuthorizeFiles,
        _ShellZmodemRecoveryAction.authorization,
      );
      return;
    }
    _clearZmodemRecoverableError(event);
  }

  _ShellZmodemPickerRequest? _beginZmodemPickerRequest(
    terminal.TerminalSessionZmodemEvent event,
  ) {
    final transferId = event.transferId;
    if (transferId == null || _zmodemPickerRequest != null) {
      return null;
    }
    _zmodemPickerRequestSeed += 1;
    final request = _ShellZmodemPickerRequest(
      requestId: _zmodemPickerRequestSeed,
      sessionId: event.sessionId,
      transferId: transferId,
    );
    _zmodemPickerRequest = request;
    return request;
  }

  bool _isCurrentZmodemPickerRequest(
    terminal.TerminalSessionZmodemEvent event,
    _ShellZmodemPickerRequest request,
  ) {
    return _zmodemPickerRequest?.requestId == request.requestId &&
        identical(_zmodemPickerRequest, request) &&
        request.transferIsCurrent &&
        request.sessionId == event.sessionId &&
        request.transferId == event.transferId &&
        ref
                .read(terminalRuntimeControllerProvider)
                .activeZmodemTransferIdFor(event.sessionId) ==
            event.transferId;
  }

  void _finishZmodemPickerRequest(_ShellZmodemPickerRequest request) {
    if (identical(_zmodemPickerRequest, request)) {
      _zmodemPickerRequest = null;
    }
  }

  void _invalidateZmodemPickerRequest(String sessionId, [String? transferId]) {
    final request = _zmodemPickerRequest;
    if (request == null ||
        request.sessionId != sessionId ||
        (transferId != null && request.transferId != transferId)) {
      return;
    }
    request.transferIsCurrent = false;
  }

  void _showZmodemPickerResultIgnored(
    terminal.TerminalSessionZmodemEvent event,
  ) {
    final message = context.l10n.zmodemPickerResultIgnored;
    final current = _zmodemTransfers[event.sessionId];
    final recoveryAction = current?.recoveryAction;
    if (current != null && recoveryAction != null) {
      _mutateState(() {
        _zmodemTransfers[event.sessionId] = current.withRecoverableError(
          current.event,
          message,
          recoveryAction,
        );
      });
    }
    if (ref.read(sessionControllerProvider).activeSessionId ==
        event.sessionId) {
      _showShellSnackBar(message);
    }
  }

  void _rememberZmodemReceiveDirectory(
    terminal.TerminalSessionZmodemEvent event,
    String destination,
  ) {
    if (!mounted) {
      return;
    }
    final current = _zmodemTransfers[event.sessionId];
    if (current?.transferId != event.transferId) {
      return;
    }
    _mutateState(() {
      _zmodemTransfers[event.sessionId] = current!.withReceiveDirectory(
        destination,
      );
    });
  }

  void _cancelZmodemTransfer(_ShellZmodemTransferState transfer) {
    if (transfer.cancelling) {
      return;
    }
    final runtime = ref.read(terminalRuntimeControllerProvider);
    if (runtime.cancelZmodem(transfer.event)) {
      final current = _zmodemTransfers[transfer.event.sessionId];
      if (current?.transferId == transfer.transferId) {
        _mutateState(() {
          _zmodemTransfers[transfer.event.sessionId] = current!
              .markCancelling();
        });
      }
    } else {
      _setZmodemRecoverableError(
        transfer.event,
        context.l10n.couldNotCancelZmodem,
        _ShellZmodemRecoveryAction.cancel,
      );
    }
  }

  void _retryZmodemOperation(_ShellZmodemTransferState transfer) {
    switch (transfer.recoveryAction) {
      case _ShellZmodemRecoveryAction.authorization:
        _clearZmodemRecoverableError(transfer.event);
        final event = transfer.event;
        if (event.kind == terminal.TerminalZmodemEventKind.detected) {
          unawaited(_authorizeZmodemSend(event));
        } else {
          unawaited(_authorizeZmodemReceive(event));
        }
      case _ShellZmodemRecoveryAction.cancel:
        _clearZmodemRecoverableError(transfer.event);
        _cancelZmodemTransfer(transfer.clearRecoverableError());
      case null:
        break;
    }
  }

  void _setZmodemRecoverableError(
    terminal.TerminalSessionZmodemEvent event,
    String message,
    _ShellZmodemRecoveryAction action,
  ) {
    if (!mounted) {
      return;
    }
    final transferId = event.transferId;
    final current = _zmodemTransfers[event.sessionId];
    if (transferId == null || current?.transferId != transferId) {
      return;
    }
    _mutateState(() {
      _zmodemAuthorizedTransferIds.remove('${event.sessionId}:$transferId');
      _zmodemTransfers[event.sessionId] = current!.withRecoverableError(
        event,
        message,
        action,
      );
    });
    if (ref.read(sessionControllerProvider).activeSessionId ==
        event.sessionId) {
      _showShellSnackBar(message);
    }
  }

  void _clearZmodemRecoverableError(terminal.TerminalSessionZmodemEvent event) {
    if (!mounted) {
      return;
    }
    final current = _zmodemTransfers[event.sessionId];
    if (current?.transferId != event.transferId ||
        current?.errorMessage == null) {
      return;
    }
    _mutateState(() {
      _zmodemTransfers[event.sessionId] = current!.clearRecoverableError();
    });
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
    final sessionState = ref.read(sessionControllerProvider);
    final tab = _tabForSession(sessionState, event.sessionId);
    final context = tab == null
        ? null
        : _terminalViewportKeys[(
                tabId: tab.sessionId,
                sessionId: event.sessionId,
              )]
              ?.currentContext;
    final renderObject = context?.findRenderObject();
    final cellSize = _measuredTerminalCellSizes[event.sessionId];
    if (renderObject is! RenderBox ||
        cellSize == null ||
        !renderObject.hasSize) {
      return null;
    }
    final local = renderObject.globalToLocal(event.position);
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
        context.l10n.allowClipboardCopyQuestion(protocolName),
      terminal.TerminalClipboardOperation.pasteRequest =>
        context.l10n.allowPasteReadQuestion(protocolName),
      terminal.TerminalClipboardOperation.mimeWrite =>
        context.l10n.allowClipboardWriteQuestion(protocolName),
      terminal.TerminalClipboardOperation.mimeRead =>
        context.l10n.allowClipboardReadQuestion(protocolName),
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
              child: Text(context.l10n.deny),
            ),
            if (request.canRememberPassword)
              TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(terminal.TerminalClipboardAuthorization.allowSession),
                child: Text(context.l10n.alwaysAllowLower),
              ),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(terminal.TerminalClipboardAuthorization.allowOnce),
              child: Text(context.l10n.allow),
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
        label: context.l10n.session,
        value: _osc52SessionDetailValue(request.sessionId),
      ),
      _Osc52PromptDetail(
        label: context.l10n.selection,
        value: request.selection ?? 'c',
      ),
      if (request.mimeTypes.isNotEmpty)
        _Osc52PromptDetail(
          label: context.l10n.mimeTypes,
          value: request.mimeTypes.join(', '),
        ),
      if (request.applicationName != null)
        _Osc52PromptDetail(
          label: context.l10n.application,
          value: request.applicationName!,
        ),
      if (request.characterCount != null || request.byteCount != null)
        _Osc52PromptDetail(
          label: context.l10n.size,
          value: [
            if (request.characterCount != null)
              context.l10n.characterCount(request.characterCount!),
            if (request.byteCount != null)
              context.l10n.byteCount(request.byteCount!),
          ].join(' / '),
        ),
    ];
    final preview = request.textPreview;
    final previewText = preview == null
        ? context.l10n.previewUnavailable
        : preview.isEmpty
        ? context.l10n.clipboardEmpty
        : _visibleOsc52Preview(preview) +
              (request.textPreviewTruncated
                  ? '\n... ${context.l10n.previewTruncated}'
                  : '');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isPasteRequest
                ? context.l10n.terminalRequestsClipboardRead
                : context.l10n.terminalRequestsClipboardWrite,
          ),
          if (request.canRememberPassword) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.alwaysAllowClipboardHelp,
              style: textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: details),
          const SizedBox(height: 12),
          Text(context.l10n.preview, style: textTheme.labelLarge),
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
            context.l10n.trustedSessionsOnly,
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
      return context.l10n.current;
    }
    final pane = _paneForSession(state, resolvedSessionId);
    final paneState =
        (state.activeSessionId == resolvedSessionId
                ? context.l10n.activePane
                : context.l10n.inactivePane)
            .toLowerCase();
    return pane == null
        ? context.l10n.paneContextUntitled(resolvedSessionId, paneState)
        : context.l10n.paneContextTitled(
            pane.title,
            resolvedSessionId,
            paneState,
          );
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
        context.l10n.oscClipboardCopied(protocolName, count ?? 0),
      (
        terminal.TerminalClipboardOperation.copy,
        terminal.TerminalClipboardDecision.blocked,
      ) =>
        context.l10n.oscClipboardCopyBlocked(protocolName),
      (
        terminal.TerminalClipboardOperation.copy,
        terminal.TerminalClipboardDecision.invalidPayload,
      ) =>
        context.l10n.oscClipboardCopyInvalid(protocolName),
      (
        terminal.TerminalClipboardOperation.pasteRequest,
        terminal.TerminalClipboardDecision.allowed,
      ) =>
        context.l10n.oscPasteReadReplied(protocolName, count ?? 0),
      (
        terminal.TerminalClipboardOperation.pasteRequest,
        terminal.TerminalClipboardDecision.blocked,
      ) =>
        context.l10n.oscPasteReadBlocked(protocolName),
      (
        terminal.TerminalClipboardOperation.pasteRequest,
        terminal.TerminalClipboardDecision.invalidPayload,
      ) =>
        context.l10n.oscPasteReadInvalid(protocolName),
      (
        terminal.TerminalClipboardOperation.mimeWrite,
        terminal.TerminalClipboardDecision.allowed,
      ) =>
        context.l10n.oscMimeWriteSucceeded(
          event.mimeTypes.length,
          event.byteCount ?? 0,
        ),
      (
        terminal.TerminalClipboardOperation.mimeWrite,
        terminal.TerminalClipboardDecision.blocked,
      ) =>
        context.l10n.oscMimeWriteBlocked,
      (
        terminal.TerminalClipboardOperation.mimeWrite,
        terminal.TerminalClipboardDecision.invalidPayload,
      ) =>
        context.l10n.oscMimeWriteFailed,
      (
        terminal.TerminalClipboardOperation.mimeRead,
        terminal.TerminalClipboardDecision.allowed,
      ) =>
        context.l10n.oscMimeReadSucceeded(
          event.mimeTypes.length,
          event.byteCount ?? 0,
        ),
      (
        terminal.TerminalClipboardOperation.mimeRead,
        terminal.TerminalClipboardDecision.blocked,
      ) =>
        context.l10n.oscMimeReadBlocked,
      (
        terminal.TerminalClipboardOperation.mimeRead,
        terminal.TerminalClipboardDecision.invalidPayload,
      ) =>
        context.l10n.oscMimeReadFailed,
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
    final visibleTitle = title.isEmpty
        ? context.l10n.terminalNotification
        : title;
    final visibleMessage = message.isEmpty ? visibleTitle : message;
    if (!_activityNotificationsEnabled ||
        !_notificationSessionIsInactive(event.sessionId) ||
        (event.action != 'update' &&
            !_activityNotificationAllowed(event.sessionId))) {
      return;
    }
    final remoteContext = _oscNotificationRemoteContext(event.sessionId);
    _sendShellNotification(
      title: remoteContext == null
          ? context.l10n.notificationInSession(
              visibleTitle,
              _sessionTitleForNotification(event.sessionId),
            )
          : context.l10n.notificationOnRemoteInSession(
              visibleTitle,
              remoteContext,
              _sessionTitleForNotification(event.sessionId),
            ),
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
      _sendOrScheduleActivityNotification(sessionId);
    }
  }

  void _sendOrScheduleActivityNotification(String sessionId) {
    if (_activityNotificationAllowed(sessionId)) {
      _activityNotificationTrailingTimers.remove(sessionId)?.cancel();
      _sendShellNotification(
        title: context.l10n.notificationInSession(
          context.l10n.activity,
          _sessionTitleForNotification(sessionId),
        ),
        body: context.l10n.newTerminalOutputAvailable,
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
          title: context.l10n.notificationInSession(
            context.l10n.activity,
            _sessionTitleForNotification(sessionId),
          ),
          body: context.l10n.newTerminalOutputAvailable,
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

  void _notifySessionExit(
    String sessionId,
    int? exitCode, {
    TerminalSessionExitUiContext? exitContext,
  }) {
    final sessionTitle = switch (exitContext) {
      TerminalSessionExitUiContext(
        :final title,
        :final paneIndex,
        :final paneCount,
      ) =>
        _exitSessionTitle(
          sessionId: sessionId,
          title: title,
          paneIndex: paneIndex,
          paneCount: paneCount,
        ),
      null => _sessionTitleForNotification(sessionId),
    };
    _sendShellNotification(
      title: context.l10n.sessionEnded,
      body: context.l10n.sessionExitedBody(
        sessionTitle,
        exitCode?.toString() ?? 'none',
      ),
      identifier:
          'ianvs-terminal.exit.$sessionId.${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  String _exitSessionTitle({
    required String sessionId,
    required String title,
    required int paneIndex,
    required int paneCount,
  }) {
    final trimmedTitle = title.trim();
    if (paneCount < 2) {
      return trimmedTitle.isEmpty
          ? context.l10n.sessionNamed(sessionId)
          : trimmedTitle;
    }
    final paneLabel = context.l10n.paneNamed(paneIndex + 1);
    return trimmedTitle.isEmpty
        ? '$paneLabel ($sessionId)'
        : '$trimmedTitle $paneLabel ($sessionId)';
  }

  void _notifyBell(String sessionId) {
    if (!_bellNotificationsEnabled) {
      return;
    }
    _sendShellNotification(
      title: context.l10n.notificationInSession(
        context.l10n.bell,
        _sessionTitleForNotification(sessionId),
      ),
      body: context.l10n.terminalRequestedAttentionBody,
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
    final exitCode = event.exitCode;
    _sendShellNotification(
      title: _commandFinishedNotificationTitle(event.sessionId),
      body: exitCode == null ? null : context.l10n.exitCode(exitCode),
      identifier:
          'ianvs-terminal.command.${event.sessionId}.${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  String _commandFinishedNotificationTitle(String sessionId) {
    final remoteContext = _oscNotificationRemoteContext(sessionId);
    if (remoteContext != null) {
      return context.l10n.commandFinishedOnRemoteInSession(
        remoteContext,
        _sessionTitleForNotification(sessionId),
      );
    }
    if (!_sessionIsInMultiPaneTab(sessionId)) {
      return context.l10n.commandFinished;
    }
    return context.l10n.commandFinishedInSession(
      _sessionTitleForNotification(sessionId),
    );
  }

  Future<void> _loadNotificationPreferences() async {
    try {
      final configBootstrap = await _loadNotificationConfig();
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
            configBootstrap.config.notifications.commandFinished;
        _bellNotificationsEnabled = configBootstrap.config.notifications.bell;
        _activityNotificationsEnabled =
            configBootstrap.config.notifications.activity;
      });
    } on Object catch (error) {
      if (mounted) {
        _showShellSnackBar(
          context.l10n.terminalSettingsCouldNotLoad(error.toString()),
        );
      }
    }
  }

  Future<LocalTerminalConfigBootstrapResult> _loadNotificationConfig() async {
    return ref.read(localTerminalConfigLoaderProvider).load();
  }

  Future<void> _saveNotificationPreferences() async {
    final notifications = TerminalAppNotifications(
      commandFinished: _commandFinishedNotificationsEnabled,
      bell: _bellNotificationsEnabled,
      activity: _activityNotificationsEnabled,
    );
    final localConfig = await _loadLocalNotificationConfigForSave();
    final nextConfig = await ref
        .read(localTerminalConfigRepositoryProvider)
        .update(
          (current) => current.copyWith(
            notifications: LocalTerminalNotificationsConfig(
              enabled:
                  notifications.commandFinished ||
                  notifications.bell ||
                  notifications.activity,
              commandFinished: notifications.commandFinished,
              bell: notifications.bell,
              activity: notifications.activity,
            ),
          ),
          fallback: localConfig,
        );
    _notificationConfigSource = LocalTerminalConfigBootstrapSource.localConfig;
    _notificationLocalConfig = nextConfig;
  }

  Future<LocalTerminalConfigDocument>
  _loadLocalNotificationConfigForSave() async {
    final repository = ref.read(localTerminalConfigRepositoryProvider);
    if (_notificationConfigSource ==
        LocalTerminalConfigBootstrapSource.localConfig) {
      return await repository.load() ?? _notificationLocalConfig;
    }
    return await repository.load() ?? _notificationLocalConfig;
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
      context.l10n.hotkeyWindowUnavailable,
      if (status != null) context.l10n.shortcutValue(status.shortcut),
      if (status?.errorCode != null)
        context.l10n.errorValue(status!.errorCode!.toString()),
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
