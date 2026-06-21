part of 'shell_screen.dart';

const bool _hideDefaultTerminalWhenCommandBlocksVisible = true;

@visibleForTesting
String? shellCommandBlocksRunningBlockId(
  ShellCommandBlocksOverlayViewModel viewModel,
) {
  for (final block in viewModel.blocks) {
    if (block.outputUsesLiveTerminal) {
      return block.id;
    }
  }
  return null;
}

@visibleForTesting
String? shellCommandBlocksNativeTerminalBlockId({
  required ShellCommandBlocksOverlayViewModel viewModel,
  required terminal.TerminalFrameModes modes,
}) {
  return shellCommandBlocksNativeTerminalBlockIdForRunningBlock(
    runningBlockId: shellCommandBlocksRunningBlockId(viewModel),
    modes: modes,
  );
}

@visibleForTesting
String? shellCommandBlocksNativeTerminalBlockIdForRunningBlock({
  required String? runningBlockId,
  required terminal.TerminalFrameModes modes,
}) {
  if (runningBlockId == null) {
    return null;
  }
  return runningBlockId;
}

@visibleForTesting
bool shellCommandBlocksShouldUseNativeTerminal({
  required terminal.TerminalFrameModes modes,
  required String? nativeTerminalBlockId,
}) {
  return modes.alternateScreen || nativeTerminalBlockId != null;
}

@visibleForTesting
bool shellCommandBlocksShouldRenderOverlay({
  required ShellCommandBlocksOverlayViewModel viewModel,
  required terminal.TerminalFrameModes modes,
  required String? nativeTerminalBlockId,
}) {
  return !viewModel.isEmpty &&
      !shellCommandBlocksShouldUseNativeTerminal(
        modes: modes,
        nativeTerminalBlockId: nativeTerminalBlockId,
      );
}

@visibleForTesting
bool shellCommandBlocksShouldEmbedLiveTerminal({
  required ShellCommandBlocksOverlayViewModel viewModel,
  required terminal.TerminalFrameModes modes,
  required String? nativeTerminalBlockId,
}) {
  if (shellCommandBlocksShouldUseNativeTerminal(
    modes: modes,
    nativeTerminalBlockId: nativeTerminalBlockId,
  )) {
    return false;
  }
  return viewModel.blocks.any((block) => block.outputUsesLiveTerminal);
}

@visibleForTesting
bool shellCommandBlocksShouldHideDefaultTerminal({
  required bool hideWhenVisible,
  required ShellCommandBlocksOverlayViewModel viewModel,
  required terminal.TerminalFrameModes modes,
  required String? nativeTerminalBlockId,
}) {
  return hideWhenVisible &&
      !viewModel.isEmpty &&
      !shellCommandBlocksShouldUseNativeTerminal(
        modes: modes,
        nativeTerminalBlockId: nativeTerminalBlockId,
      );
}

@visibleForTesting
bool shellCommandBlocksShouldShowLaunchHero({
  required CommandBlocksHistoryFeatureFlags flags,
  required ShellCommandBlocksOverlayViewModel viewModel,
  required terminal.TerminalFrameModes modes,
  required String? nativeTerminalBlockId,
  required bool launchHeroDismissed,
}) {
  return flags.enabled &&
      flags.commandBlocks &&
      !launchHeroDismissed &&
      viewModel.isEmpty &&
      !shellCommandBlocksShouldUseNativeTerminal(
        modes: modes,
        nativeTerminalBlockId: nativeTerminalBlockId,
      );
}

@visibleForTesting
bool shellCommandInputVisibleForCommandBlocks({
  required CommandBlocksHistoryFeatureFlags flags,
  required terminal.TerminalFrameModes modes,
  required String? nativeTerminalBlockId,
}) {
  return flags.enabled &&
      flags.commandBlocks &&
      !shellCommandBlocksShouldUseNativeTerminal(
        modes: modes,
        nativeTerminalBlockId: nativeTerminalBlockId,
      );
}

class _ShellLaunchHero extends StatelessWidget {
  const _ShellLaunchHero({required this.palette, required this.directory});

  final AppThemeTokens palette;
  final String? directory;

  @override
  Widget build(BuildContext context) {
    final trimmedDirectory = directory?.trim();
    final directoryLabel = trimmedDirectory == null || trimmedDirectory.isEmpty
        ? null
        : _commandDockPathLabel(trimmedDirectory);
    return Semantics(
      container: true,
      label: 'Shell launch surface',
      child: DecoratedBox(
        key: const Key('shell-launch-hero'),
        decoration: BoxDecoration(
          color: palette.terminalSurface,
          border: Border(top: BorderSide(color: palette.terminalFrame)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: palette.spacing.xl,
                vertical: palette.spacing.xxl,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.panel.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(palette.radius.lg),
                        border: Border.all(color: palette.border),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(palette.spacing.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: palette.chrome.withValues(alpha: 0.74),
                                borderRadius: BorderRadius.circular(
                                  palette.radius.md,
                                ),
                                border: Border.all(color: palette.border),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(palette.spacing.md),
                                child: Icon(
                                  Icons.terminal_rounded,
                                  size: 24,
                                  color: palette.accent,
                                ),
                              ),
                            ),
                            SizedBox(height: palette.spacing.lg),
                            Text(
                              'Local shell',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: palette.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            if (directoryLabel != null) ...[
                              SizedBox(height: palette.spacing.sm),
                              Text(
                                directoryLabel,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: palette.textSubtle,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'monospace',
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

@visibleForTesting
StickyCommandHeaderResolution shellCommandBlocksStickyHeaderResolution({
  required ShellCommandBlockSnapshot snapshot,
  required String sessionId,
  required int viewportStartRow,
  required int viewportRows,
  required terminal.TerminalFrameModes modes,
  required bool shellIntegrationEnabled,
  ShellCommandBlockCommandCenterAdapter adapter =
      const ShellCommandBlockCommandCenterAdapter(),
  StickyCommandHeaderResolver resolver = const StickyCommandHeaderResolver(),
}) {
  final visibleStartRow = math.max(0, viewportStartRow);
  final visibleRows = math.max(1, viewportRows);
  return resolver.resolve(
    blocks: adapter.commandBlocksFor(snapshot: snapshot, sessionId: sessionId),
    viewport: StickyCommandHeaderViewport(
      scope: CommandBlockScope(sessionId),
      visibleRange: CommandBlockRowRange(
        startRow: visibleStartRow,
        endRowExclusive: visibleStartRow + visibleRows,
      ),
      altBufferActive: modes.alternateScreen,
    ),
    shellIntegrationEnabled: shellIntegrationEnabled,
  );
}

@visibleForTesting
CommandBlockNavigationResult shellCommandBlocksNavigationResult({
  required ShellCommandBlockSnapshot snapshot,
  required String sessionId,
  required String? selectedBlockId,
  required CommandBlockNavigationTarget target,
  required bool shellIntegrationEnabled,
  ShellCommandBlockCommandCenterAdapter adapter =
      const ShellCommandBlockCommandCenterAdapter(),
  CommandBlockNavigationController controller =
      const CommandBlockNavigationController(),
}) {
  return controller.navigate(
    CommandBlockRangeState.fromBlocks(
      adapter.commandBlocksFor(snapshot: snapshot, sessionId: sessionId),
      shellIntegrationEnabled: shellIntegrationEnabled,
    ),
    state: CommandBlockNavigationState(
      scope: CommandBlockScope(sessionId),
      selectedBlockId: selectedBlockId,
    ),
    target: target,
  );
}

@visibleForTesting
String shellCommandBlocksNavigationMessage(
  CommandBlockNavigationDisabledReason? reason,
) {
  return switch (reason) {
    CommandBlockNavigationDisabledReason.shellIntegrationDisabled =>
      'Shell integration is not available for command block navigation.',
    CommandBlockNavigationDisabledReason.noCommandBlocks =>
      'No command blocks are available to navigate.',
    CommandBlockNavigationDisabledReason.missingInputRange =>
      'Command block navigation needs command input ranges.',
    CommandBlockNavigationDisabledReason.noPreviousBlock =>
      'No previous command block is available.',
    CommandBlockNavigationDisabledReason.noNextBlock =>
      'No next command block is available.',
    CommandBlockNavigationDisabledReason.noFailedBlock =>
      'No failed command block is available.',
    null => 'Command block navigation is unavailable.',
  };
}

extension _ShellScreenStateTerminalWorkspace on _ShellScreenState {
  List<ShellCommandBlock> _commandBlocksForSession(String sessionId) {
    if (!_commandBlocksHistoryFeatureFlags.enabled ||
        !_commandBlocksHistoryFeatureFlags.commandBlocks) {
      return const <ShellCommandBlock>[];
    }
    return _commandBlockSnapshotsBySession[sessionId]?.blocks ??
        const <ShellCommandBlock>[];
  }

  void _toggleCommandBlockBookmark(String sessionId, String blockId) {
    final trimmedBlockId = blockId.trim();
    if (trimmedBlockId.isEmpty) {
      return;
    }
    _mutateState(() {
      final current = Set<String>.of(
        _bookmarkedCommandBlockIdsBySession[sessionId] ?? const <String>{},
      );
      if (!current.remove(trimmedBlockId)) {
        current.add(trimmedBlockId);
      }
      if (current.isEmpty) {
        _bookmarkedCommandBlockIdsBySession.remove(sessionId);
      } else {
        _bookmarkedCommandBlockIdsBySession[sessionId] =
            Set<String>.unmodifiable(current);
      }
      _selectedCommandBlockIdsBySession[sessionId] = trimmedBlockId;
    });
  }

  void _selectCommandBlock(String sessionId, String blockId) {
    final trimmedBlockId = blockId.trim();
    if (trimmedBlockId.isEmpty) {
      return;
    }
    _mutateState(() {
      _selectedCommandBlockIdsBySession[sessionId] = trimmedBlockId;
    });
    _focusSession(sessionId);
  }

  String? _activeCommandBlockIdForSession(String sessionId) {
    return _selectedCommandBlockIdsBySession[sessionId];
  }

  KeyEventResult? _handleSelectedCommandBlockNavigationKey(
    KeyEvent event,
    String? activeSessionId,
  ) {
    if (activeSessionId == null ||
        !_selectedCommandBlockIdsBySession.containsKey(activeSessionId) ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return null;
    }

    final target = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => CommandBlockNavigationTarget.previous,
      LogicalKeyboardKey.arrowDown => CommandBlockNavigationTarget.next,
      _ => null,
    };
    if (target == null) {
      return null;
    }

    _navigateCommandBlock(
      activeSessionId,
      target,
      showBlockedFeedback: event is! KeyRepeatEvent,
    );
    return KeyEventResult.handled;
  }

  bool _navigateCommandBlock(
    String sessionId,
    CommandBlockNavigationTarget target, {
    bool showBlockedFeedback = false,
  }) {
    final result = shellCommandBlocksNavigationResult(
      snapshot:
          _commandBlockSnapshotsBySession[sessionId] ??
          const ShellCommandBlockSnapshot(),
      sessionId: sessionId,
      selectedBlockId: _selectedCommandBlockIdsBySession[sessionId],
      target: target,
      shellIntegrationEnabled:
          _commandBlocksHistoryFeatureFlags.enabled &&
          _commandBlocksHistoryFeatureFlags.commandBlocks,
    );
    if (!result.enabled) {
      if (showBlockedFeedback && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                shellCommandBlocksNavigationMessage(result.disabledReason),
              ),
            ),
          );
      }
      return false;
    }
    final intent = result.intent;
    final blockId = intent.blockId;
    final row = intent.row;
    if (intent.kind != CommandBlockNavigationIntentKind.scrollToBlock ||
        blockId == null ||
        row == null) {
      return false;
    }
    _mutateState(() {
      _selectedCommandBlockIdsBySession[sessionId] = blockId;
    });
    ref
        .read(terminalRuntimeControllerProvider)
        .scrollViewportTo(sessionId, row);
    _focusSession(sessionId);
    return true;
  }

  String? _runningCommandBlockIdForSession(String sessionId) {
    final blocks = _commandBlocksForSession(sessionId);
    for (final block in blocks.reversed) {
      if (block.status == ShellCommandBlockStatus.running) {
        return block.id;
      }
    }
    return null;
  }

  void _dismissLaunchHeroForSession(String sessionId) {
    if (_dismissedLaunchHeroSessionIds.contains(sessionId)) {
      return;
    }
    _mutateState(() {
      _dismissedLaunchHeroSessionIds.add(sessionId);
    });
  }

  String? _syncNativeTerminalCommandBlockIdForSession(
    String sessionId,
    terminal.TerminalFrameModes modes, {
    String? runningBlockId,
  }) {
    final nativeTerminalBlockId =
        shellCommandBlocksNativeTerminalBlockIdForRunningBlock(
          runningBlockId:
              runningBlockId ?? _runningCommandBlockIdForSession(sessionId),
          modes: modes,
        );
    if (nativeTerminalBlockId == null) {
      _nativeTerminalCommandBlockIdsBySession.remove(sessionId);
    } else {
      _nativeTerminalCommandBlockIdsBySession[sessionId] =
          nativeTerminalBlockId;
      _nativeTerminalCommandBlockIdsSeenBySession
          .putIfAbsent(sessionId, () => <String>{})
          .add(nativeTerminalBlockId);
    }
    return nativeTerminalBlockId;
  }

  Map<String, List<terminal.TerminalRow>> _capturedCommandBlockRowsForSession(
    String sessionId,
  ) {
    final capturedRows =
        _commandBlockPreviewRowsBySession[sessionId] ??
        const <String, List<terminal.TerminalRow>>{};
    final nativeBlockIds =
        _nativeTerminalCommandBlockIdsSeenBySession[sessionId];
    if (nativeBlockIds == null || nativeBlockIds.isEmpty) {
      return capturedRows;
    }
    return <String, List<terminal.TerminalRow>>{
      ...capturedRows,
      for (final blockId in nativeBlockIds)
        blockId: const <terminal.TerminalRow>[],
    };
  }

  TextEditingController _commandInputControllerFor(String sessionId) {
    return _commandInputControllers.putIfAbsent(
      sessionId,
      TextEditingController.new,
    );
  }

  FocusNode _commandInputFocusNodeFor(String sessionId) {
    return _commandInputFocusNodes.putIfAbsent(
      sessionId,
      () => FocusNode(debugLabel: 'shell-command-input-$sessionId'),
    );
  }

  bool _commandInputVisibleForSession(String sessionId) {
    final frame = ref
        .read(sessionControllerProvider.notifier)
        .viewportFor(sessionId)
        .frame;
    final nativeTerminalBlockId = _syncNativeTerminalCommandBlockIdForSession(
      sessionId,
      frame.modes,
    );
    return shellCommandInputVisibleForCommandBlocks(
      flags: _commandBlocksHistoryFeatureFlags,
      modes: frame.modes,
      nativeTerminalBlockId: nativeTerminalBlockId,
    );
  }

  void _focusCommandInput(String sessionId) {
    final focusNode = _commandInputFocusNodeFor(sessionId);
    if (!focusNode.canRequestFocus) {
      return;
    }
    focusNode.requestFocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
  }

  void _restoreCommandInputFocus(String sessionId) {
    _focusCommandInput(sessionId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusCommandInput(sessionId);
    });
  }

  void _primeCommandInput(String sessionId, String command) {
    final controller = _commandInputControllerFor(sessionId);
    controller.value = TextEditingValue(
      text: command,
      selection: TextSelection.collapsed(offset: command.length),
      composing: TextRange.empty,
    );
    _restoreCommandInputFocus(sessionId);
  }

  void _insertTextIntoCommandInput(String sessionId, String text) {
    if (text.isEmpty) {
      return;
    }
    final controller = _commandInputControllerFor(sessionId);
    final current = controller.value;
    final currentText = current.text;
    final selection = current.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, currentText.length).toInt()
        : currentText.length;
    final end = selection.isValid
        ? selection.end.clamp(0, currentText.length).toInt()
        : currentText.length;
    final replaceStart = math.min(start, end);
    final replaceEnd = math.max(start, end);
    final nextText = currentText.replaceRange(replaceStart, replaceEnd, text);
    final nextOffset = replaceStart + text.length;
    controller.value = current.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
    _restoreCommandInputFocus(sessionId);
  }

  Future<bool> _submitCommandInput(String sessionId, String command) async {
    if (command.trim().isEmpty || _isSessionReadOnly(sessionId)) {
      _restoreCommandInputFocus(sessionId);
      return false;
    }
    _recordSubmittedCommandBlockPreviewCapture(sessionId, command);
    final didSubmit = command.contains('\n') || command.contains('\r')
        ? await _sendCommandInputTextWithPasteConfirmation(
            sessionId,
            '$command\n',
          )
        : _sendPlainTextToSession(
            sessionId,
            '$command\n',
            refocusSession: false,
          );
    if (didSubmit) {
      _dismissLaunchHeroForSession(sessionId);
      _dismissActiveCommandCorrection();
      _commandInputFocusNodeFor(sessionId).unfocus();
      _focusSession(sessionId);
    } else {
      _restoreCommandInputFocus(sessionId);
    }
    return didSubmit;
  }

  Future<bool> _sendCommandInputTextWithPasteConfirmation(
    String sessionId,
    String text,
  ) async {
    if (text.isEmpty || _isSessionReadOnly(sessionId)) {
      return false;
    }
    final decision = LocalTerminalPasteDecisionResolver.resolve(
      text: text,
      readOnly: _isSessionReadOnly(sessionId),
      pastePolicy: _pastePolicy,
      historyPolicy: _pasteHistoryPolicy,
    );
    switch (decision.kind) {
      case LocalTerminalPasteDecisionKind.blockedReadOnly:
        return false;
      case LocalTerminalPasteDecisionKind.requireConfirmation:
        final confirmed = await _confirmPaste(decision);
        if (!confirmed) {
          return false;
        }
      case LocalTerminalPasteDecisionKind.sendImmediately:
        break;
    }
    return _sendPlainTextToSession(
      sessionId,
      decision.text,
      refocusSession: false,
    );
  }

  Future<bool> _routeCommandThroughCommandInput(
    String sessionId,
    String command, {
    required bool execute,
  }) async {
    _primeCommandInput(sessionId, command);
    if (!execute) {
      return true;
    }
    final didSubmit = await _submitCommandInput(sessionId, command);
    if (didSubmit) {
      _commandInputControllerFor(sessionId).clear();
    }
    return didSubmit;
  }

  String _normalizedCommandInputTextForExecution(String command) {
    return command.replaceFirst(RegExp(r'(?:\r\n|\r|\n)$'), '');
  }

  void _openCommandSearchForActiveSession() {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    _openCommandSearch(activeSessionId);
  }

  Widget _buildTerminalWorkspace({
    required BuildContext context,
    required SessionController sessionController,
    required SessionState sessionState,
    required TerminalTab activeTab,
    required String activeSessionId,
    required AppThemeTokens palette,
    required KeyEventResult Function(KeyEvent event) onHostKeyEvent,
  }) {
    final zoomedPaneSessionId = _zoomedPaneSessionId;
    final zoomedPane = zoomedPaneSessionId == null
        ? null
        : activeTab.paneFor(zoomedPaneSessionId);
    final paneLayout = zoomedPane == null
        ? activeTab.effectivePaneLayout
        : TerminalPaneLayoutNode.leaf(zoomedPane);
    final terminalBackground = _tabTerminalBackgroundColor(
      context,
      sessionState,
      activeTab,
    );

    return RepaintBoundary(
      key: const Key('shell-terminal-surface'),
      child: DecoratedBox(
        decoration: BoxDecoration(color: terminalBackground),
        child: _buildTerminalPaneLayoutNode(
          context: context,
          sessionController: sessionController,
          sessionState: sessionState,
          node: paneLayout,
          activeSessionId: activeSessionId,
          palette: palette,
          terminalBackground: terminalBackground,
          onHostKeyEvent: onHostKeyEvent,
        ),
      ),
    );
  }

  Widget _buildTerminalPaneLayoutNode({
    required BuildContext context,
    required SessionController sessionController,
    required SessionState sessionState,
    required TerminalPaneLayoutNode node,
    required String activeSessionId,
    required AppThemeTokens palette,
    required Color terminalBackground,
    required KeyEventResult Function(KeyEvent event) onHostKeyEvent,
  }) {
    if (node.isLeaf) {
      final pane = node.pane!;
      return _buildTerminalPane(
        context: context,
        sessionController: sessionController,
        sessionState: sessionState,
        pane: pane,
        isActive: pane.sessionId == activeSessionId,
        palette: palette,
        onHostKeyEvent: onHostKeyEvent,
      );
    }

    final direction = node.splitAxis == TerminalSplitAxis.horizontal
        ? Axis.horizontal
        : Axis.vertical;
    final first = node.first!;
    final second = node.second!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availablePrimarySize =
            (direction == Axis.horizontal
                ? constraints.maxWidth
                : constraints.maxHeight) -
            _ShellScreenState._paneDividerDragThickness;
        return Flex(
          direction: direction,
          children: [
            Expanded(
              flex: math.max(1, (node.ratio * 1000).round()),
              child: _buildTerminalPaneLayoutNode(
                context: context,
                sessionController: sessionController,
                sessionState: sessionState,
                node: first,
                activeSessionId: activeSessionId,
                palette: palette,
                terminalBackground: terminalBackground,
                onHostKeyEvent: onHostKeyEvent,
              ),
            ),
            _PaneDividerHandle(
              key: Key(
                'shell-pane-divider-${first.firstLeafId}-${second.firstLeafId}',
              ),
              direction: direction,
              thickness: _ShellScreenState._paneDividerDragThickness,
              terminalBackground: terminalBackground,
              palette: palette,
              onDragUpdate: (primaryDelta) {
                if (availablePrimarySize <= 0 ||
                    !availablePrimarySize.isFinite) {
                  return;
                }
                final nextRatio =
                    node.ratio + (primaryDelta / availablePrimarySize);
                sessionController.resizeActivePaneSplit(node.id, nextRatio);
              },
            ),
            Expanded(
              flex: math.max(1, ((1 - node.ratio) * 1000).round()),
              child: _buildTerminalPaneLayoutNode(
                context: context,
                sessionController: sessionController,
                sessionState: sessionState,
                node: second,
                activeSessionId: activeSessionId,
                palette: palette,
                terminalBackground: terminalBackground,
                onHostKeyEvent: onHostKeyEvent,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTerminalPane({
    required BuildContext context,
    required SessionController sessionController,
    required SessionState sessionState,
    required TerminalPane pane,
    required bool isActive,
    required AppThemeTokens palette,
    required KeyEventResult Function(KeyEvent event) onHostKeyEvent,
  }) {
    final sessionId = pane.sessionId;
    final focusNode = _focusNodeFor(sessionId);
    final selectionController = _selectionControllers.putIfAbsent(
      sessionId,
      SelectionController.new,
    );
    final profile = _profileForPane(pane, sessionState.profiles);
    final terminalConfig = profile?.toSessionConfig();
    final terminalColors = _terminalColorsForProfile(context, profile);
    final inputController = TerminalInputController(
      sessionId: sessionId,
      runtime: ref.read(terminalRuntimeControllerProvider),
      readFrame: () => sessionController.viewportFor(sessionId).frame,
      emulation:
          terminalConfig?.emulation ?? terminal.TerminalEmulation.xterm256,
      readSelection: () => _selectionTextForSession(
        sessionController,
        sessionId,
        selectionController,
      ),
      copySelection: ClipboardBridge.copy,
      readClipboard: ClipboardBridge.paste,
      readOnly: () => _isSessionReadOnly(sessionId),
    );
    final annotations = _annotationsForSession(sessionId);
    final activeCoprocess = _coprocesses[sessionId];
    final terminalViewportPadding = _terminalViewportPaddingFor(sessionState);
    final paneBody = LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = _terminalContentSizeFor(
          constraints,
          terminalViewportPadding,
        );
        final scheduledSize = _scheduledViewportSizes[sessionId];
        if (scheduledSize != viewportSize) {
          _scheduledViewportSizes[sessionId] = viewportSize;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _mutateState(() {});
              _scheduleViewportResize(
                sessionController,
                sessionId,
                viewportSize,
                MediaQuery.devicePixelRatioOf(context),
                immediate: !_committedViewportSizes.containsKey(sessionId),
              );
            }
          });
        }
        final viewportController = sessionController.viewportFor(sessionId);
        final terminalFont =
            terminalConfig?.display.font ?? const terminal.TerminalFontConfig();
        final terminalCursor =
            terminalConfig?.display.cursor ??
            const terminal.TerminalCursorConfig();
        void handleMeasuredCellSizeChanged(Size cellSize) {
          if (!mounted) {
            return;
          }
          if (_measuredTerminalCellSizes[sessionId] != cellSize) {
            _mutateState(() {
              _measuredTerminalCellSizes[sessionId] = cellSize;
            });
          }
          _scheduleViewportResize(
            sessionController,
            sessionId,
            viewportSize,
            MediaQuery.devicePixelRatioOf(context),
            immediate: true,
          );
        }

        Widget buildSessionTerminalViewport({
          Key? key,
          required EdgeInsets contentPadding,
          FocusNode? terminalFocusNode,
          ValueChanged<Size>? onMeasuredCellSizeChanged,
        }) {
          return TerminalViewport(
            key: key,
            focusNode: terminalFocusNode,
            controller: viewportController,
            selectionController: selectionController,
            inputController: inputController,
            contentPadding: contentPadding,
            onMeasuredCellSizeChanged: onMeasuredCellSizeChanged,
            colors: terminalColors,
            font: terminalFont,
            cursor: terminalCursor,
            copyOnSelect:
                _clipboardConfig.copyOnSelect ||
                (terminalConfig?.interaction.copyOnSelect ?? false),
            optionDragMode:
                terminalConfig?.interaction.optionDragMode ??
                terminal.TerminalOptionDragMode.blockSelection,
            searchMatches: isActive && _isSearchOpen
                ? _searchMatches
                : const <terminal.TerminalSearchMatch>[],
            activeSearchMatchIndex: isActive && _isSearchOpen
                ? _activeSearchIndex
                : -1,
            searchHighlightStyle: terminal.TerminalSearchHighlightStyle(
              activeFill: palette.accent.withValues(alpha: 0.34),
              inactiveFill: palette.warning.withValues(alpha: 0.22),
              activeBorder: palette.accent.withValues(alpha: 0.82),
              radius: 3,
            ),
            onHostKeyEvent: onHostKeyEvent,
            onScrollLines: (delta) {
              ref
                  .read(terminalRuntimeControllerProvider)
                  .scrollViewport(sessionId, delta);
            },
            onScrollToOffset: (offset) {
              ref
                  .read(terminalRuntimeControllerProvider)
                  .scrollViewportTo(sessionId, offset);
            },
            onOpenLink: (url) => unawaited(WindowBridge.openExternalUrl(url)),
          );
        }

        return ListenableBuilder(
          listenable: viewportController,
          builder: (context, _) {
            final frame = viewportController.frame;
            final commandBlocksViewModel =
                ShellCommandBlockViewModelBuilder.build(
                  blocks: _commandBlocksForSession(sessionId),
                  viewportStartRow: frame.viewportStartRow,
                  viewportEndRow:
                      frame.viewportStartRow + frame.viewportRows - 1,
                  flags: _commandBlocksHistoryFeatureFlags,
                  visibleRows: frame.rows,
                  capturedRowsByBlockId: _capturedCommandBlockRowsForSession(
                    sessionId,
                  ),
                  bookmarkedBlockIds:
                      _bookmarkedCommandBlockIdsBySession[sessionId] ??
                      const <String>{},
                  viewportCols: frame.viewportCols,
                  activeBlockId: _activeCommandBlockIdForSession(sessionId),
                );
            final nativeTerminalBlockId =
                _syncNativeTerminalCommandBlockIdForSession(
                  sessionId,
                  frame.modes,
                  runningBlockId: shellCommandBlocksRunningBlockId(
                    commandBlocksViewModel,
                  ),
                );
            final renderCommandBlocksOverlay =
                shellCommandBlocksShouldRenderOverlay(
                  viewModel: commandBlocksViewModel,
                  modes: frame.modes,
                  nativeTerminalBlockId: nativeTerminalBlockId,
                );
            final embedLiveTerminal = shellCommandBlocksShouldEmbedLiveTerminal(
              viewModel: commandBlocksViewModel,
              modes: frame.modes,
              nativeTerminalBlockId: nativeTerminalBlockId,
            );
            final hideDefaultTerminal =
                shellCommandBlocksShouldHideDefaultTerminal(
                  hideWhenVisible: _hideDefaultTerminalWhenCommandBlocksVisible,
                  viewModel: commandBlocksViewModel,
                  modes: frame.modes,
                  nativeTerminalBlockId: nativeTerminalBlockId,
                );
            final showLaunchHero = shellCommandBlocksShouldShowLaunchHero(
              flags: _commandBlocksHistoryFeatureFlags,
              viewModel: commandBlocksViewModel,
              modes: frame.modes,
              nativeTerminalBlockId: nativeTerminalBlockId,
              launchHeroDismissed: _dismissedLaunchHeroSessionIds.contains(
                sessionId,
              ),
            );
            return Listener(
              onPointerDown: (event) {
                if (showLaunchHero &&
                    (event.buttons & kPrimaryMouseButton) != 0) {
                  _dismissLaunchHeroForSession(sessionId);
                }
                if (!isActive && (event.buttons & kPrimaryMouseButton) != 0) {
                  _activateSession(sessionController, sessionId);
                }
                final shouldMiddlePaste =
                    frame.modes.mouseMode == 'off' &&
                    (event.buttons & kMiddleMouseButton) != 0;
                if (shouldMiddlePaste) {
                  unawaited(_pasteToSession(sessionId));
                }
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isActive
                        ? palette.focusRing.withValues(alpha: 0.78)
                        : Colors.transparent,
                    width: isActive ? 1.5 : 1,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Stack(
                        children: [
                          if (hideDefaultTerminal)
                            Positioned.fill(
                              child: ColoredBox(
                                color: terminalColors.canvasBackground,
                              ),
                            )
                          else
                            Positioned.fill(
                              child: buildSessionTerminalViewport(
                                terminalFocusNode: focusNode,
                                contentPadding: terminalViewportPadding,
                                onMeasuredCellSizeChanged:
                                    handleMeasuredCellSizeChanged,
                              ),
                            ),
                          if (renderCommandBlocksOverlay)
                            Positioned.fill(
                              child: ShellCommandBlocksOverlay(
                                viewModel: commandBlocksViewModel,
                                rowHeight:
                                    _measuredTerminalCellSizes[sessionId]
                                        ?.height ??
                                    terminal.terminalFallbackCellSize.height,
                                colors: terminalColors,
                                font: terminalFont,
                                cursor: terminalCursor,
                                contentPadding: terminalViewportPadding,
                                liveTerminalRows: frame.viewportRows,
                                liveTerminalBuilder: embedLiveTerminal
                                    ? (
                                        context,
                                        block,
                                      ) => buildSessionTerminalViewport(
                                        key: Key(
                                          'shell-command-block-live-terminal-'
                                          'viewport-${block.id}',
                                        ),
                                        contentPadding: EdgeInsets.zero,
                                        onMeasuredCellSizeChanged:
                                            hideDefaultTerminal
                                            ? handleMeasuredCellSizeChanged
                                            : null,
                                      )
                                    : null,
                                onOpenBlockActions: (block, anchorRect) =>
                                    unawaited(
                                      _openContextChipBlockActions(
                                        sessionController: sessionController,
                                        sessionState: sessionState,
                                        sessionId: sessionId,
                                        blockId: block.id,
                                        anchorRect: anchorRect,
                                        showSelectedBlockChip: false,
                                      ),
                                    ),
                                onSelectBlock: (block) =>
                                    _selectCommandBlock(sessionId, block.id),
                                onToggleBlockBookmark: (block) =>
                                    _toggleCommandBlockBookmark(
                                      sessionId,
                                      block.id,
                                    ),
                              ),
                            ),
                          if (showLaunchHero)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: _ShellLaunchHero(
                                  palette: palette,
                                  directory:
                                      pane.shellIntegration.currentDirectory ??
                                      profile?.cwd,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!isActive)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(
                            key: Key('shell-pane-dim-$sessionId'),
                            color: palette.inactiveScrim,
                          ),
                        ),
                      ),
                    if (isActive && _isSearchOpen)
                      Positioned(
                        top: _ShellScreenState._terminalOverlayPadding.top,
                        left: _ShellScreenState._terminalOverlayPadding.left,
                        right: _ShellScreenState._terminalOverlayPadding.right,
                        child: Align(
                          alignment: Alignment.topRight,
                          child: _TerminalSearchBar(
                            query: _searchQuery,
                            matches: _searchMatches.length,
                            activeIndex: _activeSearchIndex,
                            searchMode: _searchMode,
                            errorText: _searchErrorText,
                            palette: palette,
                            focusNode: _searchFocusNode,
                            focusRequestSerial: _searchFocusRequestSerial,
                            onChanged: _searchScrollback,
                            onClear: _clearSearch,
                            onModeChanged: _setSearchMode,
                            onPrevious: () => _moveSearchMatch(1),
                            onNext: () => _moveSearchMatch(-1),
                            onClose: _closeSearch,
                          ),
                        ),
                      ),
                    if (isActive && _isCommandSearchOpen)
                      Positioned(
                        top: _ShellScreenState._terminalOverlayPadding.top,
                        left: _ShellScreenState._terminalOverlayPadding.left,
                        right: _ShellScreenState._terminalOverlayPadding.right,
                        child: Align(
                          alignment: Alignment.topRight,
                          child: CommandSearchOverlay(
                            controller: _commandSearchControllerFor(sessionId),
                            onInsert: (command) => unawaited(
                              _insertCommandSearchSelection(sessionId, command),
                            ),
                            onViewBlock: (blockId) => _viewCommandSearchBlock(
                              sessionController: sessionController,
                              sessionState: sessionState,
                              sessionId: sessionId,
                              blockId: blockId,
                            ),
                            onAskAgent:
                                _commandCenterFeatureFlags
                                    .agentCommandSearchActions
                                ? (request) =>
                                      _askAgentAboutCommandSearchResult(
                                        sessionId: sessionId,
                                        request: request,
                                      )
                                : null,
                            onClose: _closeCommandSearch,
                          ),
                        ),
                      ),
                    if (isActive && _isCommandActionSearchOpen)
                      Positioned(
                        top: _ShellScreenState._terminalOverlayPadding.top,
                        left: _ShellScreenState._terminalOverlayPadding.left,
                        right: _ShellScreenState._terminalOverlayPadding.right,
                        child: Align(
                          alignment: Alignment.topRight,
                          child: CommandActionSearchOverlay(
                            controller: _commandActionSearchControllerFor(
                              sessionId,
                            ),
                            onOpenAction: (actionId) => unawaited(
                              _openCommandActionSearchAction(
                                sessionId,
                                actionId,
                              ),
                            ),
                            onInsertSavedCommandItem: (item) => unawaited(
                              _insertCommandActionSearchSavedCommand(
                                sessionId,
                                item,
                              ),
                            ),
                            onClose: _closeCommandActionSearch,
                          ),
                        ),
                      ),
                    if (isActive && _isAutocompleteOpen)
                      Positioned(
                        top: _ShellScreenState._terminalOverlayPadding.top,
                        right: _ShellScreenState._terminalOverlayPadding.right,
                        child: _TerminalAutocompleteMenu(
                          prefix: _autocompletePrefix,
                          suggestions: _autocompleteSuggestions,
                          activeIndex: _activeAutocompleteIndex,
                          palette: palette,
                          onPrevious: () => _moveAutocompleteSelection(-1),
                          onNext: () => _moveAutocompleteSelection(1),
                          onAccept: _acceptAutocomplete,
                          onClose: _closeAutocomplete,
                        ),
                      ),
                    if (isActive && _isAutoComposerOpen)
                      Positioned(
                        left: _ShellScreenState._terminalOverlayPadding.left,
                        right: _ShellScreenState._terminalOverlayPadding.right,
                        bottom:
                            _ShellScreenState._terminalOverlayPadding.bottom,
                        child: _TerminalAutoComposer(
                          controller: _autoComposerController,
                          focusNode: _autoComposerFocusNode,
                          inputMode: _universalInputMode,
                          classification: _autoComposerClassification,
                          contextChips: _universalInputContextChipsFor(
                            pane,
                            profile,
                          ),
                          contextOptions: _universalInputContextOptionsFor(
                            pane,
                            profile,
                          ),
                          suggestions: _autoComposerSuggestions,
                          suggestionDetails: _commandDraftDetailsByCommand(
                            _autoComposerCommandDrafts,
                          ),
                          suggestionsLoading: _autoComposerCommandDraftsLoading,
                          activeIndex: _activeAutoComposerIndex,
                          modelLabel: _effectiveUniversalInputModelLabel,
                          availableModes: _availableUniversalInputModes,
                          modelOptions: _availableUniversalInputModelOptions,
                          palette: palette,
                          onModeChanged: _setUniversalInputMode,
                          onChanged: _updateAutoComposerSuggestions,
                          onContextSelected: _addUniversalInputContextChip,
                          onSlashCommandSelected: _insertUniversalInputSnippet,
                          onModelSelected: _setUniversalInputModel,
                          onPrevious: () => _moveAutoComposerSuggestion(-1),
                          onNext: () => _moveAutoComposerSuggestion(1),
                          onAcceptSuggestion: _acceptAutoComposerSuggestion,
                          onSend: () => unawaited(_sendAutoComposerCommand()),
                          onClose: _closeAutoComposer,
                        ),
                      ),
                    if (isActive &&
                        activeCoprocess != null &&
                        !_isSearchOpen &&
                        !_isAutocompleteOpen &&
                        !_isAutoComposerOpen)
                      Positioned(
                        top: _ShellScreenState._terminalOverlayPadding.top,
                        right: _ShellScreenState._terminalOverlayPadding.right,
                        child: _CoprocessIndicator(
                          key: Key('terminal-coprocess-indicator-$sessionId'),
                          command: activeCoprocess.command,
                          palette: palette,
                        ),
                      ),
                    if (isActive && _isCopyModeOpen)
                      Positioned(
                        top: _ShellScreenState._terminalOverlayPadding.top,
                        left: _ShellScreenState._terminalOverlayPadding.left,
                        child: IgnorePointer(
                          child: _ShellWorkspaceCue(
                            title: 'Copy mode',
                            palette: palette,
                          ),
                        ),
                      ),
                    if (isActive &&
                        annotations.isNotEmpty &&
                        !_isAutoComposerOpen)
                      Positioned(
                        left: _ShellScreenState._terminalOverlayPadding.left,
                        bottom:
                            _ShellScreenState._terminalOverlayPadding.bottom,
                        child: _TerminalAnnotationBadge(
                          key: Key('terminal-annotation-badge-$sessionId'),
                          count: annotations.length,
                          palette: palette,
                          onTap: () => unawaited(
                            _openAnnotations(
                              sessionController,
                              sessionId,
                              selectionController,
                            ),
                          ),
                        ),
                      ),
                    if (isActive && _showWorkspaceCue)
                      Positioned(
                        top: _ShellScreenState._terminalOverlayPadding.top,
                        right: _ShellScreenState._terminalOverlayPadding.right,
                        child: IgnorePointer(
                          child: _ShellWorkspaceCue(
                            title: _workspaceCueTitle,
                            palette: palette,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    return Semantics(
      key: Key('shell-pane-$sessionId'),
      container: true,
      explicitChildNodes: true,
      label: isActive
          ? 'Active terminal pane $sessionId'
          : 'Inactive terminal pane $sessionId',
      selected: isActive,
      child: paneBody,
    );
  }
}
