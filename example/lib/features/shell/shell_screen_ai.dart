part of 'shell_screen.dart';

extension _ShellScreenAi on _ShellScreenState {
  bool get _mobileRequiresLlm =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  void _handleLlmConfigurationChanged() {
    if (!mounted ||
        !_mobileRequiresLlm ||
        ref.read(aiSettingsProvider).hasLlmConfiguration) {
      return;
    }
    for (final sessionId in _openAiSessions.toList()) {
      _takeOverAiInput(sessionId);
    }
  }

  ComposerPaneSession _composerFor(String sessionId) =>
      _composerSessions.putIfAbsent(
        sessionId,
        () =>
            ComposerPaneSession(
              sessionId: sessionId,
              runtime: ref.read(terminalRuntimeControllerProvider),
              mobileAiSettings: _mobileRequiresLlm
                  ? ref.read(aiSettingsProvider)
                  : null,
              preferredMode: ref
                  .read(sessionControllerProvider)
                  .preferredTerminalMode,
            )..addListener(() {
              scheduleMicrotask(() {
                if (!mounted) return;
                final session = _composerSessions[sessionId];
                if (session != null) {
                  ref
                      .read(sessionControllerProvider.notifier)
                      .updateTerminalMode(sessionId, session.mode.state);
                  _ensureUnifiedWorkspace(sessionId);
                }
              });
            }),
      );
  void _ensureUnifiedWorkspace(String sessionId) {
    if (mounted &&
        !_mobileConnectionsOpen &&
        _sessionState.activeSessionId == sessionId &&
        _composerSessions[sessionId]?.enabled == true &&
        !_openAiSessions.contains(sessionId) &&
        !_isSessionReadOnly(sessionId)) {
      _openAi(sessionId);
    }
  }

  bool _handleAiShortcut(KeyEvent event, String? activeSessionId) {
    if (event is KeyDownEvent &&
        activeSessionId != null &&
        !_shellModalInputBlocked &&
        event.logicalKey == LogicalKeyboardKey.keyI &&
        (defaultTargetPlatform == TargetPlatform.macOS
            ? HardwareKeyboard.instance.isMetaPressed
            : HardwareKeyboard.instance.isControlPressed)) {
      _toggleAi(activeSessionId);
      return true;
    }
    return false;
  }

  TerminalAiController _aiFor(String sessionId) =>
      _aiSessions.putIfAbsent(sessionId, () {
        final runtime = ref.read(terminalRuntimeControllerProvider);
        final controller = TerminalAiController(
          settings: ref.read(aiSettingsProvider),
          defaultInputIntent: InputIntent.command,
          terminal: TerminalAiConnections(
            sessionId: sessionId,
            terminal: _aiEndpoint(sessionId),
            scopeForSession: runtime.commandOccurrenceScopeFor,
            requestBlocks: runtime.commandBlocks,
          ),
        );
        final history = TerminalAiHistoryBinding(
          controller,
          ref.read(terminalAiHistoryRepositoryProvider),
          nativeBlocks: () =>
              _composerSessions[(controller.terminal as TerminalAiConnections)
                      .sessionId]
                  ?.blocks,
        );
        _aiHistory[controller] = history;
        unawaited(
          history.loaded.then((_) {
            // Restoration can add archived sources after the first Shell build.
            if (mounted && identical(_aiHistory[controller], history)) {
              _mutateState(() {});
            }
          }),
        );
        _synchronizeAiLifecycle(
          controller,
          WidgetsBinding.instance.lifecycleState,
        );
        return controller;
      });

  void _retireAiHistory(TerminalAiController controller) {
    final binding = _aiHistory.remove(controller);
    if (binding == null) return;
    binding.dispose();
    _retiredAiHistory.add(binding);
    unawaited(
      binding
          .flush(requireSaved: true)
          .then<void>(
            (_) {
              _retiredAiHistory.remove(binding);
            },
            onError: (Object _, StackTrace _) {
              // Keep the frozen snapshot for shutdown or a later flush to retry.
            },
          ),
    );
  }

  Future<void> _flushAiHistory({bool requireSaved = false}) async {
    await Future.wait(
      [
        ..._aiHistory.values,
        ..._retiredAiHistory,
      ].map((binding) => binding.flush(requireSaved: requireSaved)),
    );
  }

  void _synchronizeAiSessionsLifecycle(AppLifecycleState state) {
    // Controllers survive tab switches and the connections home. Their owner,
    // rather than a mounted workspace, must pause every mobile task together.
    for (final controller in List.of(_aiSessions.values)) {
      _synchronizeAiLifecycle(controller, state);
    }
  }

  void _synchronizeAiLifecycle(
    TerminalAiController controller,
    AppLifecycleState? state,
  ) {
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    if (state == null || state == AppLifecycleState.resumed) {
      unawaited(controller.resumeFromBackground());
    } else {
      controller.suspendForBackground();
    }
  }

  TerminalAiRuntime _aiEndpoint(String sessionId) => TerminalAiRuntime(
    sessionId: sessionId,
    runtime: ref.read(terminalRuntimeControllerProvider),
    readPane: () =>
        _paneForSession(ref.read(sessionControllerProvider), sessionId),
    isReadOnly: () => _isSessionReadOnly(sessionId),
  );

  Future<void> _reconnectAi(
    String sessionId, {
    TerminalProfile? editedProfile,
  }) async {
    await _reconnectTerminalSession(sessionId, editedProfile: editedProfile);
  }

  Future<String?> _reconnectTerminalSession(
    String sessionId, {
    TerminalProfile? editedProfile,
  }) {
    if (!mounted) return Future<String?>.value();
    final state = ref.read(sessionControllerProvider);
    // A live successor only needs activation. Otherwise reconnect the latest
    // failed attempt, where the transferred AI and command draft now live.
    final source = state.liveReconnectionFor(sessionId) == null
        ? state.latestReconnectionFor(sessionId)
        : sessionId;
    if (_closingSessionIds.contains(source)) return Future<String?>.value();
    final existing = _terminalReconnects[source];
    if (existing != null) return existing;
    late final Future<String?> reconnect;
    reconnect = () async {
      try {
        return await _reconnectTerminalSessionOnce(
          source,
          editedProfile: editedProfile,
        );
      } finally {
        if (identical(_terminalReconnects[source], reconnect)) {
          if (mounted) {
            _mutateState(() {
              unawaited(_terminalReconnects.remove(source));
            });
          } else {
            unawaited(_terminalReconnects.remove(source));
          }
        }
      }
    }();
    _mutateState(() {
      _terminalReconnects[source] = reconnect;
    });
    return reconnect;
  }

  Future<String?> _reconnectTerminalSessionOnce(
    String sessionId, {
    TerminalProfile? editedProfile,
  }) async {
    if (!mounted || !_sessionExists(sessionId)) return null;
    final sessions = ref.read(sessionControllerProvider.notifier);
    if (ref.read(sessionControllerProvider).liveReconnectionFor(sessionId) !=
        null) {
      return sessions.reconnectSession(sessionId, editedProfile: editedProfile);
    }
    final ai = _aiSessions[sessionId];
    if (ai != null) {
      ai.takeOver();
      await ai.refreshContext(); // Finish inspecting original receipts first.
      if (!mounted || !identical(_aiSessions[sessionId], ai)) return null;
    }
    if (!mounted || !_sessionExists(sessionId)) return null;
    // A different entry point may have reconnected while receipts were read.
    // Reusing its target must not replace that target's draft or AI task.
    if (ref.read(sessionControllerProvider).liveReconnectionFor(sessionId) !=
        null) {
      return sessions.reconnectSession(sessionId, editedProfile: editedProfile);
    }
    final sourceComposer = _composerSessions[sessionId];
    final draft = sourceComposer?.controller.editor.value;
    final chosenMode = sourceComposer?.mode.chosenMode;
    final next = sessions.reconnectSession(
      sessionId,
      editedProfile: editedProfile,
    );
    if (next == null) return null;
    if (ai != null) {
      final connections = ai.terminal as TerminalAiConnections;
      ai.prepareForConnectionChange();
      connections.reconnect(
        sessionId: next,
        terminal: _aiEndpoint(next),
        originalBlocks: _composerSessions[sessionId]?.blocks,
      );
      _mutateState(() {
        _aiSessions.remove(sessionId);
        _aiSessions[next] = ai;
        if (_openAiSessions.remove(sessionId)) {
          _revokeManualInput(sessionId);
          _revokeManualInput(next);
          _openAiSessions.add(next);
        }
        final observed = _observedAiTargets.remove(sessionId);
        if (observed != null) _observedAiTargets[next] = observed;
      });
    }
    if (draft != null) _composerFor(next).controller.editor.value = draft;
    if (chosenMode == TerminalViewMode.normal) {
      _composerFor(next).selectMode(TerminalViewMode.normal);
    }
    await ai?.refreshContext(); // No inference, approval, or command replay.
    return next;
  }

  Future<void> _configureAiConnection(String sessionId) async {
    final ai = _aiSessions[sessionId];
    final pane = _paneForSession(
      ref.read(sessionControllerProvider),
      sessionId,
    );
    final profile = pane?.profileSnapshot;
    if (_isProfilesOpen ||
        ai == null ||
        pane?.isExited != true ||
        profile?.isSsh != true) {
      return;
    }
    ai.takeOver();
    _mutateState(() => _isProfilesOpen = true);
    final SshProfileEditorResult? result;
    try {
      await releaseTerminalInputForModal();
      if (!mounted) return;
      result = await showDialog<SshProfileEditorResult>(
        context: context,
        animationStyle: appDialogAnimation(context),
        useSafeArea: !context.usesMobileNavigation,
        builder: (_) => SshProfileEditorDialog(
          initialValue: profile!,
          allowSaveChoice: true,
          saveProfileAvailable: _customSshProfilesEnabled,
        ),
      );
    } finally {
      if (mounted) _mutateState(() => _isProfilesOpen = false);
    }
    if (!mounted || result == null || !identical(_aiSessions[sessionId], ai)) {
      return;
    }
    final sessions = ref.read(sessionControllerProvider.notifier);
    if (result.saveProfile &&
        !await _saveProfileWithFeedback(
          sessions,
          result.profile,
          clearSecrets: result.clearSecrets,
        )) {
      return;
    }
    if (mounted) await _reconnectAi(sessionId, editedProfile: result.profile);
  }

  Future<void> _configureMobileLlm(String sessionId) async {
    if (_isMobileLlmSetupOpen) return;
    _mutateState(() {
      _isMobileLlmSetupOpen = true;
      _revokeManualInput(sessionId);
    });
    try {
      await showAiSettings(context, ref.read(aiSettingsProvider));
    } finally {
      if (mounted) _mutateState(() => _isMobileLlmSetupOpen = false);
    }
  }

  void _openAi(
    String sessionId, {
    String? prompt,
    terminal.CommandBlock? block,
    terminal.CommandBlock? range,
    List<terminal.CommandBlock> blocks = const [],
  }) {
    if (_mobileRequiresLlm &&
        !ref.read(aiSettingsProvider).hasLlmConfiguration) {
      unawaited(_configureMobileLlm(sessionId));
      return;
    }
    final ai = _aiFor(sessionId);
    if (_mobileRequiresLlm || !_openAiSessions.contains(sessionId)) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    final runtime =
        (ai.terminal as TerminalAiConnections).active as TerminalAiRuntime;
    if (range != null) {
      ai.attachContext(runtime.blockContext(range, useSnapshot: true));
    }
    for (final selected in [?block, ...blocks]) {
      ai.attachContext(runtime.blockContext(selected));
    }
    {
      final composer = _composerSessions[sessionId];
      composer?.selectMode(TerminalViewMode.blocks);
      // Migrate a pre-existing command draft only once. The unified controller
      // is the sole draft owner after entry, including ordinary-mode round trips.
      if (composer != null &&
          composer.controller.editor.text.isNotEmpty &&
          ai.draft.isEmpty) {
        ai.setDraft(composer.controller.editor.text);
        composer.controller.editor.clear();
      }
    }
    if (prompt != null) ai.setDraft(prompt);
    if (block != null && ai.draft.isEmpty) {
      final chinese = Localizations.localeOf(context).languageCode == 'zh';
      ai.setDraft(
        block.exitCode != null && block.exitCode != 0
            ? (chinese
                  ? '解释这条命令失败的原因，并提出修正。'
                  : 'Explain this failure and suggest a correction.')
            : (chinese ? '解释这个命令块。' : 'Explain this command block.'),
      );
    }
    _mutateState(() {
      if (!_openAiSessions.contains(sessionId)) {
        _revokeManualInput(sessionId);
        // Composer submits through its shell lease instead of the raw-input
        // epoch. Revoke that capability before an old Run callback can fire;
        // only the view notification waits until layout has finished.
        _composerSessions[sessionId]?.setVisible(
          false,
          deferNotification: true,
        );
      }
      _openAiSessions.add(sessionId);
      _observedAiTargets.remove(sessionId);
    });
    if (!_mobileRequiresLlm) ai.requestDraftFocus();
    if (prompt == null) {
      unawaited(ai.refreshContext());
      return;
    }
    final taskId = ai.taskId;
    final inputEpoch = _manualInputEpoch(sessionId);
    bool canStart() =>
        mounted &&
        identical(_aiSessions[sessionId], ai) &&
        ai.taskId == taskId &&
        _manualInputEpoch(sessionId) == inputEpoch &&
        _openAiSessions.contains(sessionId);
    // ask captures draft/source identity before settings or context can await.
    // A later close/reopen must not resurrect this entry point's old request.
    final submission = ai.ask(prompt, canStart: canStart);
    unawaited(() async {
      await submission;
      await ai.settings.loaded;
      if (mounted && canStart() && ai.settings.configuration == null) {
        await showAiSettings(context, ai.settings);
        // Saving settings does not submit a retained draft.
      }
    }());
  }

  void _toggleAi(String sessionId) {
    if (_openAiSessions.contains(sessionId) &&
        !_observedAiTargets.containsKey(sessionId)) {
      _observeAiTerminal(sessionId);
    } else {
      _openAi(sessionId);
    }
  }

  void _takeOverAiInput(String sessionId) {
    _aiSessions[sessionId]?.takeOver();
    if (_composerSessions[sessionId]?.enabled == true) {
      _composerSessions[sessionId]?.selectMode(TerminalViewMode.normal);
    }
    _mutateState(() {
      _revokeManualInput(sessionId);
      _openAiSessions.remove(sessionId);
      _observedAiTargets.remove(sessionId);
    });
    if (_sessionState.activeSessionId == sessionId) _focusSession(sessionId);
  }

  void _reinputAiCommand(String sessionId, String command) {
    if (!mounted) return;
    final pane = _paneForSession(
      ref.read(sessionControllerProvider),
      sessionId,
    );
    if (pane == null) return;
    if (!_mobileRequiresLlm ||
        ref.read(aiSettingsProvider).hasLlmConfiguration) {
      // An unavailable command editor must not replace the shared draft.
      if (!_mobileRequiresLlm) {
        final composer = _composerFor(sessionId);
        composer.updateEnvironment(
          pane,
          readOnly: _isSessionReadOnly(sessionId),
        );
        composer.refreshShellState();
        if (!composer.selectMode(TerminalViewMode.blocks)) {
          _showShellSnackBar(
            blockUnavailableMessage(
              context.l10n,
              composer.mode.state.unavailableReason,
            ),
          );
          return;
        }
      }
      final ai = _aiFor(sessionId);
      ai.takeOver();
      while (ai.attachments.isNotEmpty) {
        ai.removeAttachment(ai.attachments.length - 1);
      }
      ai.chooseInputIntent(InputIntentChoice.command);
      ai.setDraft(command);
      _activateSession(
        ref.read(sessionControllerProvider.notifier),
        sessionId,
        requestFocus: false,
      );
      _openAi(sessionId);
      return;
    }
    final composer = _composerFor(sessionId);
    composer.updateEnvironment(pane, readOnly: _isSessionReadOnly(sessionId));
    composer.refreshShellState();
    if (!composer.selectMode(TerminalViewMode.blocks)) {
      _showShellSnackBar(
        blockUnavailableMessage(
          context.l10n,
          composer.mode.state.unavailableReason,
        ),
      );
      return;
    }
    // Reinput is an explicit request to edit in this session. Reveal the
    // editor before replacing its draft, without changing the saved preference.
    composer.controller.editor.value = TextEditingValue(
      text: command,
      selection: TextSelection.collapsed(offset: command.length),
    );
    _activateSession(
      ref.read(sessionControllerProvider.notifier),
      sessionId,
      requestFocus: false,
    );
    _takeOverAiInput(sessionId);
  }

  Widget _aiChromeAction(String sessionId) {
    final ai = _aiSessions[sessionId];
    Widget button() {
      final chinese = Localizations.localeOf(context).languageCode == 'zh';
      final showTerminal =
          _openAiSessions.contains(sessionId) &&
          !_observedAiTargets.containsKey(sessionId);
      final label = showTerminal
          ? (chinese ? '只读查看终端' : 'View terminal (read-only)')
          : ai?.canApprove == true
          ? (chinese ? 'AI · 有待确认命令' : 'AI · action needs review')
          : ai?.busy == true
          ? (chinese ? 'AI · 任务进行中' : 'AI · task in progress')
          : (chinese ? 'Block + AI 工作区' : 'Block + AI workspace');
      return Tooltip(
        message: label,
        child: TextButton(
          key: Key('terminal-ai-open-$sessionId'),
          style: TextButton.styleFrom(
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          onPressed: () => _toggleAi(sessionId),
          child: Semantics(
            label: label,
            child: Badge(
              backgroundColor: context.appTheme.accent,
              isLabelVisible: ai?.canApprove == true || ai?.busy == true,
              child: !_mobileRequiresLlm
                  ? Icon(
                      showTerminal
                          ? Icons.terminal
                          : Icons.auto_awesome_outlined,
                      size: 18,
                    )
                  : Text(
                      showTerminal
                          ? (chinese ? '终端预览' : 'Preview')
                          : 'Block + AI',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        ),
      );
    }

    // Ordinary terminals do not create a task. Block + AI entry creates
    // its shared controller without starting inference or submitting input.
    return ai == null
        ? button()
        : ListenableBuilder(listenable: ai, builder: (_, _) => button());
  }

  AiTranscriptEntry? _humanRunningAction(String sessionId) {
    final ai = _aiSessions[sessionId];
    if (ai == null || !ai.canUseHumanCommandInput || ai.targetChanged) {
      return null;
    }
    final action = ai.transcript
        .where((entry) => entry.action != null)
        .lastOrNull;
    return ai.isUserCommand(action?.action) &&
            action?.action?.kind == AiActionKind.runCommand &&
            action?.state == AiEntryState.accepted &&
            action?.target?.sessionId == sessionId &&
            action?.submissionId != null &&
            action?.blockId != null
        ? action
        : null;
  }

  bool _humanBlockInputAllowed(
    String sessionId,
    String taskId,
    AiTranscriptEntry action,
    int epoch,
  ) {
    if (!mounted ||
        epoch != _manualInputEpoch(sessionId) ||
        !_openAiSessions.contains(sessionId) ||
        _observedAiTargets.containsKey(sessionId) ||
        _sessionState.activeSessionId != sessionId ||
        _readerControllers[sessionId]?.blocksInput == true ||
        ModalRoute.of(context)?.isCurrent == false ||
        _isSessionReadOnly(sessionId) ||
        _aiSessions[sessionId]?.taskId != taskId ||
        _humanRunningAction(sessionId)?.id != action.id) {
      return false;
    }
    final runtime = ref.read(terminalRuntimeControllerProvider);
    final state = runtime.composerRequest(
      sessionId,
      'composer.state',
      const {},
    );
    if (state?['state'] != 'running' ||
        state?['contextId'] != action.target?.contextId) {
      return false;
    }
    final receipt = runtime.composerRequest(sessionId, 'composer.receipt', {
      'submissionId': action.submissionId,
    });
    return receipt?['outcome'] == 'accepted' &&
        receipt?['submissionId'] == action.submissionId &&
        receipt?['blockId'] == action.blockId &&
        receipt?['running'] == true;
  }

  Widget _aiOverlay(
    String sessionId,
    AppThemeTokens palette, {
    required String targetLabel,
    required BuildContext paneContext,
    required bool active,
    AiTimelineBuilder? timelineBuilder,
    ValueChanged<AiEvidenceReference>? onShowEvidence,
    bool fullScreenTerminal = false,
    terminal.TerminalFontConfig font = const terminal.TerminalFontConfig(),
    TerminalViewportColors? colors,
  }) {
    if (_openAiSessions.contains(sessionId)) {
      final connections = _aiFor(sessionId).terminal as TerminalAiConnections;
      final retained = connections.hasRetainedSources;
      Widget workspace(bool dual) => TerminalAiWorkspace(
        key: ValueKey('ai-workspace-$sessionId'),
        controller: _aiFor(sessionId),
        active: active,
        canInteract: () =>
            mounted &&
            _openAiSessions.contains(sessionId) &&
            (dual || !_observedAiTargets.containsKey(sessionId)) &&
            _sessionState.activeSessionId == sessionId,
        compactMobile: paneContext.usesMobileNavigation,
        unifiedWorkspace: true,
        commandSession: _composerFor(sessionId),
        targetLabel: targetLabel,
        onOpenLink: (url) =>
            unawaited(_openTerminalLink(url, sourceSessionId: sessionId)),
        timelineBuilder: retained && !fullScreenTerminal
            ? (items, scroll, followTail) => TerminalAiRetainedTimeline(
                controller: _aiFor(sessionId),
                unifiedWorkspace: true,
                items: items,
                scroll: scroll,
                followTail: followTail,
                font: font,
                sourceLabelFor: (source) => _paneForSession(
                  ref.read(sessionControllerProvider),
                  source,
                )?.title,
                onReinput: (command) => _reinputAiCommand(sessionId, command),
                onOpenLinkTarget: (target) =>
                    unawaited(_openTerminalLinkTarget(sessionId, target)),
                onLinkContextMenu: (target) => unawaited(
                  _handleTerminalLinkContextMenu(sessionId, target),
                ),
              )
            : timelineBuilder,
        onShowEvidence: retained
            ? (reference) => unawaited(
                _showRetainedEvidence(paneContext, sessionId, reference, font),
              )
            : onShowEvidence,
        fullScreenTerminal: fullScreenTerminal,
        onClose: () => _observeAiTerminal(sessionId),
        onTakeOver: () => _takeOverAiInput(sessionId),
        onObserveTerminal: () => _observeAiTerminal(sessionId),
        onInspectOriginalTarget: retained
            ? () {
                final original = _aiFor(sessionId).originalTarget?.sessionId;
                _observeAiTerminal(sessionId, targetSessionId: original);
              }
            : null,
        onReconnect:
            _paneForSession(
                      ref.read(sessionControllerProvider),
                      sessionId,
                    )?.isExited ==
                    true &&
                _paneForSession(
                      ref.read(sessionControllerProvider),
                      sessionId,
                    )?.profileSnapshot?.isSsh ==
                    true
            ? () => _reconnectAi(sessionId)
            : null,
        onConfigureTerminal:
            _paneForSession(
                  ref.read(sessionControllerProvider),
                  sessionId,
                )?.profileSnapshot?.isSsh ==
                true
            ? () => _configureAiConnection(sessionId)
            : null,
      );
      // Keep the original Composer's secondary-click focus boundary when its
      // editor is hosted by the unified workspace instead of ComposerPane.
      return Actions(
        actions: {
          EditableTextTapOutsideIntent: _PaneComposerTapOutsideAction(),
        },
        child: _presentAiWorkspace(
          sessionId,
          workspaceBuilder: workspace,
          targetLabel: targetLabel,
          font: font,
          colors: colors,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _showRetainedEvidence(
    BuildContext paneContext,
    String sessionId,
    AiEvidenceReference reference,
    terminal.TerminalFontConfig font,
  ) async {
    final command = await showRetainedAiEvidence(
      paneContext,
      controller: _aiFor(sessionId),
      reference: reference,
      font: font,
      sourceLabelFor: (source) =>
          _paneForSession(ref.read(sessionControllerProvider), source)?.title,
    );
    if (command != null && mounted) {
      _reinputAiCommand(sessionId, command);
    }
  }
}
