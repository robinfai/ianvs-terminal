part of 'shell_screen.dart';

extension _ShellScreenAi on _ShellScreenState {
  ComposerPaneSession _composerFor(String sessionId) =>
      _composerSessions.putIfAbsent(
        sessionId,
        () =>
            ComposerPaneSession(
              sessionId: sessionId,
              runtime: ref.read(terminalRuntimeControllerProvider),
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
                }
              });
            }),
      );
  bool _handleAiShortcut(KeyEvent event, String? activeSessionId) {
    if (event is KeyDownEvent &&
        activeSessionId != null &&
        !_shellModalInputBlocked &&
        event.logicalKey == LogicalKeyboardKey.keyI &&
        (defaultTargetPlatform == TargetPlatform.macOS
            ? HardwareKeyboard.instance.isMetaPressed
            : HardwareKeyboard.instance.isControlPressed)) {
      _openAiSessions.contains(activeSessionId)
          ? _closeAi(activeSessionId)
          : _openAi(activeSessionId);
      return true;
    }
    return false;
  }

  TerminalAiController _aiFor(String sessionId) => _aiSessions.putIfAbsent(
    sessionId,
    () => TerminalAiController(
      settings: ref.read(aiSettingsProvider),
      terminal: TerminalAiConnections(
        sessionId: sessionId,
        terminal: _aiEndpoint(sessionId),
        requestBlocks: (source, request) => ref
            .read(terminalRuntimeControllerProvider)
            .commandBlocks(source, request),
      ),
    ),
  );

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
    final draft = _composerSessions[sessionId]?.controller.editor.value;
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
        if (_openAiSessions.remove(sessionId)) _openAiSessions.add(next);
      });
    }
    if (draft != null) _composerFor(next).controller.editor.value = draft;
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

  void _openAi(
    String sessionId, {
    String? prompt,
    terminal.CommandBlock? block,
    terminal.CommandBlock? range,
    List<terminal.CommandBlock> blocks = const [],
  }) {
    final ai = _aiFor(sessionId);
    FocusManager.instance.primaryFocus?.unfocus();
    final runtime =
        (ai.terminal as TerminalAiConnections).active as TerminalAiRuntime;
    if (range != null) {
      ai.attachContext(runtime.blockContext(range, useSnapshot: true));
    }
    for (final selected in [?block, ...blocks]) {
      ai.attachContext(runtime.blockContext(selected));
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
    _mutateState(() => _openAiSessions.add(sessionId));
    unawaited(() async {
      await ai.refreshContext();
      if (!mounted) return;
      if (prompt == null) return;
      await ai.settings.loaded;
      if (!mounted) return;
      if (ai.settings.configuration == null) {
        await showAiSettings(context, ai.settings);
        return; // Saving settings does not submit a retained draft.
      }
      if (!_openAiSessions.contains(sessionId)) return;
      unawaited(ai.ask(prompt));
    }());
  }

  void _closeAi(String sessionId) {
    _aiSessions[sessionId]?.takeOver();
    _mutateState(() => _openAiSessions.remove(sessionId));
    _focusSession(sessionId);
  }

  void _reinputAiCommand(String sessionId, String command) {
    if (!mounted) return;
    final pane = _paneForSession(
      ref.read(sessionControllerProvider),
      sessionId,
    );
    if (pane == null) return;
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
    _closeAi(sessionId);
  }

  Widget _aiChromeAction(String sessionId) {
    final ai = _aiSessions[sessionId];
    Widget button() {
      final chinese = Localizations.localeOf(context).languageCode == 'zh';
      final label = ai?.canApprove == true
          ? (chinese ? 'AI · 有待确认命令' : 'AI · action needs review')
          : ai?.busy == true
          ? (chinese ? 'AI · 任务进行中' : 'AI · task in progress')
          : (chinese ? 'AI 任务' : 'AI task');
      return Tooltip(
        message: label,
        child: TextButton(
          key: Key('terminal-ai-open-$sessionId'),
          style: TextButton.styleFrom(
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          onPressed: () => _openAiSessions.contains(sessionId)
              ? _closeAi(sessionId)
              : _openAi(sessionId),
          child: Semantics(
            label: label,
            child: Badge(
              backgroundColor: context.appTheme.accent,
              isLabelVisible: ai?.canApprove == true || ai?.busy == true,
              child: const Text('AI'),
            ),
          ),
        ),
      );
    }

    // Showing a terminal must not create a task or retain its native history
    // as an AI source. The first explicit AI action creates its controller.
    return ai == null
        ? button()
        : ListenableBuilder(listenable: ai, builder: (_, _) => button());
  }

  Widget _aiOverlay(
    String sessionId,
    AppThemeTokens palette, {
    required String targetLabel,
    AiTimelineBuilder? timelineBuilder,
    ValueChanged<AiEvidenceReference>? onShowEvidence,
    bool fullScreenTerminal = false,
    terminal.TerminalFontConfig font = const terminal.TerminalFontConfig(),
  }) {
    if (_openAiSessions.contains(sessionId)) {
      final connections = _aiFor(sessionId).terminal as TerminalAiConnections;
      final retained = connections.hasRetainedSources;
      return TerminalAiWorkspace(
        key: ValueKey('ai-workspace-$sessionId'),
        controller: _aiFor(sessionId),
        targetLabel: targetLabel,
        onOpenLink: (url) =>
            unawaited(_openTerminalLink(url, sourceSessionId: sessionId)),
        timelineBuilder: retained && !fullScreenTerminal
            ? (items, scroll, followTail) => TerminalAiRetainedTimeline(
                controller: _aiFor(sessionId),
                items: items,
                scroll: scroll,
                followTail: followTail,
                font: font,
                onReinput: (command) => _reinputAiCommand(sessionId, command),
                onOpenLinkTarget: (target) =>
                    unawaited(_openTerminalLinkTarget(sessionId, target)),
              )
            : timelineBuilder,
        onShowEvidence: retained
            ? (reference) =>
                  unawaited(_showRetainedEvidence(sessionId, reference, font))
            : onShowEvidence,
        fullScreenTerminal: fullScreenTerminal,
        onClose: () => _closeAi(sessionId),
        onInspectOriginalTarget: retained
            ? () {
                final original = _aiFor(sessionId).originalTarget?.sessionId;
                _closeAi(sessionId);
                if (original != null) {
                  ref
                      .read(sessionControllerProvider.notifier)
                      .activateSession(original);
                }
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
    }
    return const SizedBox.shrink();
  }

  Future<void> _showRetainedEvidence(
    String sessionId,
    AiEvidenceReference reference,
    terminal.TerminalFontConfig font,
  ) async {
    final command = await showRetainedAiEvidence(
      context,
      controller: _aiFor(sessionId),
      reference: reference,
      font: font,
    );
    if (command != null && mounted) {
      _reinputAiCommand(sessionId, command);
    }
  }
}
