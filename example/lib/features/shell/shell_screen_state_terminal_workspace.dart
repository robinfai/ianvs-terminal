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
  if (modes.alternateScreen) {
    return runningBlockId;
  }
  return null;
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

extension _ShellScreenStateTerminalWorkspace on _ShellScreenState {
  List<ShellCommandBlock> _commandBlocksForSession(String sessionId) {
    if (!_commandBlocksHistoryFeatureFlags.enabled ||
        !_commandBlocksHistoryFeatureFlags.commandBlocks) {
      return const <ShellCommandBlock>[];
    }
    return _commandBlockSnapshotsBySession[sessionId]?.blocks ??
        const <ShellCommandBlock>[];
  }

  List<ShellCommandBlock> _historyPeekBlocksForSession(String sessionId) {
    return _commandBlocksForSession(sessionId);
  }

  bool _hasHistoryPeekBlocksForSession(String sessionId) {
    return _commandBlocksForSession(sessionId).isNotEmpty;
  }

  String? get _activeCommandBlockId => null;

  String? _runningCommandBlockIdForSession(String sessionId) {
    final blocks = _commandBlocksForSession(sessionId);
    for (final block in blocks.reversed) {
      if (block.status == ShellCommandBlockStatus.running) {
        return block.id;
      }
    }
    return null;
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

  void _submitCommandInput(String sessionId, String command) {
    final text = command.trim();
    if (text.isEmpty || _isSessionReadOnly(sessionId)) {
      return;
    }
    _recordSubmittedCommandBlockPreviewCapture(sessionId, text);
    ref
        .read(terminalRuntimeControllerProvider)
        .sendInput(sessionId, Uint8List.fromList(utf8.encode('$text\n')));
    _commandInputFocusNodeFor(sessionId).requestFocus();
  }

  void _openHistoryPeek() {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null ||
        !_commandBlocksHistoryFeatureFlags.enabled ||
        !_commandBlocksHistoryFeatureFlags.commandBlocks ||
        !_commandBlocksHistoryFeatureFlags.historyPeek ||
        !_hasHistoryPeekBlocksForSession(activeSessionId)) {
      return;
    }
    _mutateState(() {
      _isToolbeltOpen = false;
      _isHistoryPeekOpen = true;
    });
  }

  void _closeHistoryPeek() {
    if (!_isHistoryPeekOpen) {
      return;
    }
    _mutateState(() {
      _isHistoryPeekOpen = false;
    });
  }

  bool _historyPeekVisibleForSession(String sessionId) {
    return _isHistoryPeekOpen &&
        _commandBlocksHistoryFeatureFlags.enabled &&
        _commandBlocksHistoryFeatureFlags.commandBlocks &&
        _commandBlocksHistoryFeatureFlags.historyPeek &&
        _hasHistoryPeekBlocksForSession(sessionId);
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
    final contextChips = _contextChipsForPane(
      sessionState: sessionState,
      pane: pane,
      profile: profile,
    );

    return LayoutBuilder(
      key: Key('shell-pane-$sessionId'),
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
                  viewportCols: frame.viewportCols,
                  activeBlockId: _activeCommandBlockId,
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

            return Listener(
              onPointerDown: (event) {
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
                              _measuredTerminalCellSizes[sessionId]?.height ??
                              terminal.terminalFallbackCellSize.height,
                          colors: terminalColors,
                          font: terminalFont,
                          cursor: terminalCursor,
                          contentPadding: terminalViewportPadding,
                          liveTerminalRows: frame.viewportRows,
                          liveTerminalBuilder: embedLiveTerminal
                              ? (context, block) =>
                                    buildSessionTerminalViewport(
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
                    if (isActive &&
                        !_isSearchOpen &&
                        !_isCommandSearchOpen &&
                        !_isCommandActionSearchOpen &&
                        !_isAutocompleteOpen &&
                        !_isAutoComposerOpen &&
                        !_isCopyModeOpen &&
                        contextChips.chips.isNotEmpty)
                      Positioned(
                        top: _ShellScreenState._terminalOverlayPadding.top,
                        left: _ShellScreenState._terminalOverlayPadding.left,
                        right: _ShellScreenState._terminalOverlayPadding.right,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: ContextChips(
                            chips: contextChips.chips,
                            onIntent: (intent) => _handleContextChipIntent(
                              sessionController: sessionController,
                              sessionState: sessionState,
                              sessionId: sessionId,
                              intent: intent,
                            ),
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
                            onExplicitExecute: (command) => unawaited(
                              _executeCommandSearchSelection(
                                sessionId,
                                command,
                              ),
                            ),
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
                          suggestions: _autoComposerSuggestions,
                          activeIndex: _activeAutoComposerIndex,
                          palette: palette,
                          onChanged: _updateAutoComposerSuggestions,
                          onPrevious: () => _moveAutoComposerSuggestion(-1),
                          onNext: () => _moveAutoComposerSuggestion(1),
                          onAcceptSuggestion: _acceptAutoComposerSuggestion,
                          onSend: _sendAutoComposerCommand,
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
  }
}
