part of 'shell_screen.dart';

enum _TerminalLinkMenuAction { open, copy, copyText, inspect }

extension _ShellScreenStateTerminalWorkspace on _ShellScreenState {
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
          activeTab: activeTab,
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
    required TerminalTab activeTab,
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
        activeTab: activeTab,
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
                activeTab: activeTab,
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
                final constrainedRatio = _constrainedPaneSplitRatio(
                  sessionController,
                  node,
                  nextRatio,
                );
                if ((constrainedRatio - node.ratio).abs() < 0.0001) {
                  return;
                }
                sessionController.resizePaneSplit(
                  first.firstLeafId,
                  node.id,
                  constrainedRatio,
                );
              },
            ),
            Expanded(
              flex: math.max(1, ((1 - node.ratio) * 1000).round()),
              child: _buildTerminalPaneLayoutNode(
                context: context,
                sessionController: sessionController,
                sessionState: sessionState,
                node: second,
                activeTab: activeTab,
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
    required TerminalTab activeTab,
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
    final defaultProfile = _effectiveDefaultProfileFor(
      sessionState.profiles,
      sessionState.defaultProfileId,
    );
    final showsPaneHeader = activeTab.effectivePanes.length > 1;
    final splitRightUnavailableReason = _splitAxisConflictReason(
      sessionState,
      sessionId,
      TerminalSplitAxis.horizontal,
    );
    final splitDownUnavailableReason = _splitAxisConflictReason(
      sessionState,
      sessionId,
      TerminalSplitAxis.vertical,
    );
    final paneManagementBlockedReason = _zoomedPaneManagementUnavailableReason(
      activeTab,
    );
    final splitRightBlockedReason =
        paneManagementBlockedReason ?? splitRightUnavailableReason;
    final splitDownBlockedReason =
        paneManagementBlockedReason ?? splitDownUnavailableReason;
    final paneIndex = math.max(
      0,
      activeTab.effectivePanes.indexWhere(
        (pane) => pane.sessionId == sessionId,
      ),
    );
    final hasHoveredLink = _hoveredTerminalLinkSessionId == sessionId;
    return LayoutBuilder(
      key: Key('shell-pane-$sessionId'),
      builder: (context, constraints) {
        final viewportController = sessionController.viewportFor(sessionId);
        final paneHeader = showsPaneHeader
            ? ListenableBuilder(
                listenable: viewportController,
                builder: (context, _) {
                  return _TerminalPaneHeader(
                    key: Key('shell-pane-header-$sessionId'),
                    palette: palette,
                    sessionId: sessionId,
                    title: pane.title,
                    subtitle:
                        'Pane ${paneIndex + 1}/${activeTab.effectivePanes.length}',
                    isActive: isActive,
                    isZoomed: _zoomedPaneSessionId == sessionId,
                    canZoom: activeTab.effectivePanes.length > 1,
                    indicators: _paneHeaderIndicatorsFor(
                      pane,
                      modes: viewportController.frame.modes,
                      readOnly: _isSessionReadOnly(sessionId),
                    ),
                    onActivate: () =>
                        _activateSession(sessionController, sessionId),
                    splitRightTooltip: splitRightBlockedReason == null
                        ? 'Split right'
                        : 'Split right unavailable: $splitRightBlockedReason',
                    onSplitRight:
                        defaultProfile == null ||
                            splitRightBlockedReason != null
                        ? null
                        : () => _splitSession(
                            sessionController,
                            sessionId,
                            defaultProfile,
                            TerminalSplitAxis.horizontal,
                          ),
                    splitDownTooltip: splitDownBlockedReason == null
                        ? 'Split down'
                        : 'Split down unavailable: $splitDownBlockedReason',
                    onSplitDown:
                        defaultProfile == null || splitDownBlockedReason != null
                        ? null
                        : () => _splitSession(
                            sessionController,
                            sessionId,
                            defaultProfile,
                            TerminalSplitAxis.vertical,
                          ),
                    onToggleZoom: activeTab.effectivePanes.length < 2
                        ? null
                        : () {
                            _mutateState(() {
                              _zoomedPaneSessionId =
                                  _zoomedPaneSessionId == sessionId
                                  ? null
                                  : sessionId;
                            });
                            _focusSession(sessionId);
                          },
                    onClose: () => _closeSession(
                      sessionController,
                      sessionState,
                      sessionId,
                    ),
                  );
                },
              )
            : null;

        return Listener(
          onPointerDown: (event) {
            if (!isActive && event.buttons != 0) {
              _activateSession(sessionController, sessionId);
            }
            final frame = sessionController.viewportFor(sessionId).frame;
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
            child: Column(
              children: [
                ?paneHeader,
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, terminalConstraints) {
                      final viewportSize = _terminalContentSizeFor(
                        terminalConstraints,
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
                              immediate: !_committedViewportSizes.containsKey(
                                sessionId,
                              ),
                            );
                          }
                        });
                      }
                      final attentionBurst = _osc1337AttentionBurstFor(
                        context: context,
                        sessionId: sessionId,
                        viewportController: viewportController,
                        viewportSize: terminalConstraints.biggest,
                        contentPadding: terminalViewportPadding,
                        palette: palette,
                      );
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: TerminalViewport(
                              key: _terminalViewportKeys.putIfAbsent(
                                sessionId,
                                GlobalKey.new,
                              ),
                              focusNode: focusNode,
                              controller: viewportController,
                              selectionController: selectionController,
                              inputController: inputController,
                              contentPadding: terminalViewportPadding,
                              onMeasuredCellSizeChanged: (cellSize) {
                                if (!mounted) {
                                  return;
                                }
                                if (_measuredTerminalCellSizes[sessionId] !=
                                    cellSize) {
                                  _mutateState(() {
                                    _measuredTerminalCellSizes[sessionId] =
                                        cellSize;
                                  });
                                }
                                _scheduleViewportResize(
                                  sessionController,
                                  sessionId,
                                  viewportSize,
                                  MediaQuery.devicePixelRatioOf(context),
                                  immediate: true,
                                );
                              },
                              colors: terminalColors,
                              font:
                                  terminalConfig?.display.font ??
                                  const terminal.TerminalFontConfig(),
                              cursor:
                                  terminalConfig?.display.cursor ??
                                  const terminal.TerminalCursorConfig(),
                              copyOnSelect:
                                  _clipboardConfig.copyOnSelect ||
                                  (terminalConfig?.interaction.copyOnSelect ??
                                      false),
                              optionDragMode:
                                  terminalConfig?.interaction.optionDragMode ??
                                  terminal
                                      .TerminalOptionDragMode
                                      .blockSelection,
                              searchMatches: _isSearchOpen
                                  ? _searchMatchesForSession(sessionId)
                                  : const <terminal.TerminalSearchMatch>[],
                              activeSearchMatchIndex: _isSearchOpen
                                  ? _activeSearchMatchIndexForSession(sessionId)
                                  : -1,
                              searchHighlightStyle:
                                  terminal.TerminalSearchHighlightStyle(
                                    activeFill: palette.accent.withValues(
                                      alpha: 0.34,
                                    ),
                                    inactiveFill: palette.warning.withValues(
                                      alpha: 0.22,
                                    ),
                                    activeBorder: palette.accent.withValues(
                                      alpha: 0.82,
                                    ),
                                    radius: 3,
                                  ),
                              graphicsCache: sessionController.graphicsCacheFor(
                                sessionId,
                              ),
                              benchmarkEventSink: ref.watch(
                                terminalGraphicsTraceSinkProvider,
                              ),
                              graphicsDiagnosticSessionId: sessionId,
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
                              onToggleBlock: (block) {
                                selectionController.clear();
                                ref
                                    .read(terminalRuntimeControllerProvider)
                                    .setBlockFolded(
                                      sessionId,
                                      block.id,
                                      folded: !block.folded,
                                    );
                              },
                              onDismissBlockRender: (block) {
                                selectionController.clear();
                                ref
                                    .read(terminalRuntimeControllerProvider)
                                    .setBlockRendered(
                                      sessionId,
                                      block.id,
                                      rendered: false,
                                    );
                              },
                              onOpenLinkTarget: (target) => unawaited(
                                _openTerminalLinkTarget(sessionId, target),
                              ),
                              onLinkHoverChanged: (target) =>
                                  _handleTerminalLinkHover(sessionId, target),
                              onLinkContextMenu: (target) =>
                                  _handleTerminalLinkContextMenu(
                                    sessionId,
                                    target,
                                  ),
                            ),
                          ),
                          if (!isActive && !hasHoveredLink)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: ColoredBox(
                                  key: Key('shell-pane-dim-$sessionId'),
                                  color: palette.inactiveScrim,
                                ),
                              ),
                            ),
                          ?attentionBurst,
                          if (isActive && _isSearchOpen)
                            Positioned(
                              top:
                                  _ShellScreenState._terminalOverlayPadding.top,
                              left: _ShellScreenState
                                  ._terminalOverlayPadding
                                  .left,
                              right: _ShellScreenState
                                  ._terminalOverlayPadding
                                  .right,
                              child: Align(
                                alignment: Alignment.topRight,
                                child: _TerminalSearchBar(
                                  query: _searchQuery,
                                  matches: _searchHits.length,
                                  activeIndex: _activeSearchIndex,
                                  searchScope: _searchScope,
                                  searchMode: _searchMode,
                                  errorText: _searchErrorText,
                                  palette: palette,
                                  focusNode: _searchFocusNode,
                                  focusRequestSerial: _searchFocusRequestSerial,
                                  onChanged: _searchScrollback,
                                  onClear: _clearSearch,
                                  onScopeChanged: _setSearchScope,
                                  onModeChanged: _setSearchMode,
                                  onPrevious: () => _moveSearchMatch(1),
                                  onNext: () => _moveSearchMatch(-1),
                                  onClose: _closeSearch,
                                  onPasteHandlerMounted:
                                      _attachSearchPasteHandler,
                                  onPasteHandlerUnmounted:
                                      _detachSearchPasteHandler,
                                ),
                              ),
                            ),
                          if (isActive &&
                              _isAutocompleteOpen &&
                              _autocompleteSessionId == sessionId)
                            Positioned(
                              top:
                                  _ShellScreenState._terminalOverlayPadding.top,
                              right: _ShellScreenState
                                  ._terminalOverlayPadding
                                  .right,
                              child: _TerminalAutocompleteMenu(
                                prefix: _autocompletePrefix,
                                suggestions: _autocompleteSuggestions,
                                activeIndex: _activeAutocompleteIndex,
                                palette: palette,
                                onPrevious: () =>
                                    _moveAutocompleteSelection(-1),
                                onNext: () => _moveAutocompleteSelection(1),
                                onAccept: _acceptAutocomplete,
                                onClose: _closeAutocomplete,
                              ),
                            ),
                          if (isActive &&
                              _isAutoComposerOpen &&
                              _autoComposerSessionId == sessionId)
                            Positioned(
                              left: _ShellScreenState
                                  ._terminalOverlayPadding
                                  .left,
                              right: _ShellScreenState
                                  ._terminalOverlayPadding
                                  .right,
                              bottom: _ShellScreenState
                                  ._terminalOverlayPadding
                                  .bottom,
                              child: _TerminalAutoComposer(
                                controller: _autoComposerController,
                                focusNode: _autoComposerFocusNode,
                                suggestions: _autoComposerSuggestions,
                                activeIndex: _activeAutoComposerIndex,
                                palette: palette,
                                onChanged: _updateAutoComposerSuggestions,
                                onPrevious: () =>
                                    _moveAutoComposerSuggestion(-1),
                                onNext: () => _moveAutoComposerSuggestion(1),
                                onAcceptSuggestion:
                                    _acceptAutoComposerSuggestion,
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
                              top:
                                  _ShellScreenState._terminalOverlayPadding.top,
                              right: _ShellScreenState
                                  ._terminalOverlayPadding
                                  .right,
                              child: _CoprocessIndicator(
                                key: Key(
                                  'terminal-coprocess-indicator-$sessionId',
                                ),
                                command: activeCoprocess.command,
                                palette: palette,
                              ),
                            ),
                          if (isActive &&
                              _isCopyModeOpen &&
                              _copyModeSessionId == sessionId)
                            Positioned(
                              top:
                                  _ShellScreenState._terminalOverlayPadding.top,
                              left: _ShellScreenState
                                  ._terminalOverlayPadding
                                  .left,
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
                              left: _ShellScreenState
                                  ._terminalOverlayPadding
                                  .left,
                              bottom: _ShellScreenState
                                  ._terminalOverlayPadding
                                  .bottom,
                              child: _TerminalAnnotationBadge(
                                key: Key(
                                  'terminal-annotation-badge-$sessionId',
                                ),
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
                              top:
                                  _ShellScreenState._terminalOverlayPadding.top,
                              right: _ShellScreenState
                                  ._terminalOverlayPadding
                                  .right,
                              child: IgnorePointer(
                                child: _ShellWorkspaceCue(
                                  title: _workspaceCueTitle,
                                  palette: palette,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget? _osc1337AttentionBurstFor({
    required BuildContext context,
    required String sessionId,
    required TerminalViewportController viewportController,
    required Size viewportSize,
    required EdgeInsets contentPadding,
    required AppThemeTokens palette,
  }) {
    final serial = _osc1337FireworksSerials[sessionId];
    final cellSize = _measuredTerminalCellSizes[sessionId];
    final frame = viewportController.frame;
    if (serial == null ||
        cellSize == null ||
        !cellSize.width.isFinite ||
        !cellSize.height.isFinite ||
        cellSize.width <= 0 ||
        cellSize.height <= 0 ||
        !viewportSize.width.isFinite ||
        !viewportSize.height.isFinite ||
        viewportSize.isEmpty ||
        frame.scrollbackOffset != 0 ||
        frame.viewportRows <= 0 ||
        frame.viewportCols <= 0) {
      return null;
    }

    const preferredExtent = 76.0;
    final extent = math.min(
      preferredExtent,
      math.min(viewportSize.width, viewportSize.height),
    );
    if (extent <= 0) {
      return null;
    }
    final cursorRow = frame.cursor.row.clamp(0, frame.viewportRows - 1).toInt();
    final cursorCol = frame.cursor.col.clamp(0, frame.viewportCols - 1).toInt();
    final rawCenter = Offset(
      contentPadding.left + (cursorCol + 0.5) * cellSize.width,
      contentPadding.top + (cursorRow + 0.5) * cellSize.height,
    );
    final center = Offset(
      rawCenter.dx.clamp(extent / 2, viewportSize.width - extent / 2),
      rawCenter.dy.clamp(extent / 2, viewportSize.height - extent / 2),
    );
    final reduceMotion =
        !ref.read(shellAnimationsEnabledProvider) ||
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false);

    return Positioned(
      key: Key('osc1337-fireworks-$sessionId'),
      left: center.dx - extent / 2,
      top: center.dy - extent / 2,
      width: extent,
      height: extent,
      child: _TerminalAttentionBurst(
        key: ValueKey<String>('osc1337-fireworks-$sessionId-$serial'),
        animate: !reduceMotion,
        colors: <Color>[palette.accent, palette.warning, palette.success],
      ),
    );
  }

  String? get _terminalLinkStatusLabel {
    final target = _hoveredTerminalLink;
    final uri = target?.uri;
    if (uri == null || uri.trim().isEmpty) {
      return null;
    }
    final prefix = target?.hasMismatchedVisibleText ?? false
        ? 'LINK CHECK'
        : 'LINK';
    return '$prefix ${_terminalLinkShortLabel(uri)}';
  }

  String? get _terminalLinkStatusTooltip {
    final target = _hoveredTerminalLink;
    final uri = target?.uri.trim();
    if (target == null || uri == null || uri.isEmpty) {
      return null;
    }
    return [
      if (target.hasMismatchedVisibleText)
        'OSC 8 link text differs from the target',
      if (_hoveredTerminalLinkSessionId case final sessionId?
          when _sessionIsInMultiPaneTab(sessionId))
        _terminalPaneContextLine(sessionId),
      'Target: $uri',
      if (target.visibleText != null && target.visibleText!.trim().isNotEmpty)
        'Text: ${target.visibleText!.trim()}',
      if (_hoveredTerminalLinkSessionId case final sessionId?
          when _sessionIsInMultiPaneTab(sessionId) &&
              _sessionNeedsFocus(sessionId))
        'Click to focus this pane.',
    ].join('\n');
  }

  double _constrainedPaneSplitRatio(
    SessionController sessionController,
    TerminalPaneLayoutNode node,
    double requestedRatio,
  ) {
    final axis = node.splitAxis;
    final first = node.first;
    final second = node.second;
    if (axis == null || first == null || second == null) {
      return requestedRatio;
    }

    final firstSize = _paneLayoutPrimaryCells(sessionController, first, axis);
    final secondSize = _paneLayoutPrimaryCells(sessionController, second, axis);
    final totalSize = firstSize + secondSize;
    final minimumSize = _minimumPanePrimaryCells(axis);
    if (totalSize <= 0 || totalSize < minimumSize * 2) {
      return node.ratio;
    }

    final lowerBound = minimumSize / totalSize;
    final upperBound = 1 - lowerBound;
    if (lowerBound >= upperBound) {
      return node.ratio;
    }
    return requestedRatio.clamp(lowerBound, upperBound).toDouble();
  }

  int _paneLayoutPrimaryCells(
    SessionController sessionController,
    TerminalPaneLayoutNode node,
    TerminalSplitAxis axis,
  ) {
    if (node.isLeaf) {
      final frame = sessionController.viewportFor(node.pane!.sessionId).frame;
      return axis == TerminalSplitAxis.horizontal
          ? frame.viewportCols
          : frame.viewportRows;
    }

    final firstSize = _paneLayoutPrimaryCells(
      sessionController,
      node.first!,
      axis,
    );
    final secondSize = _paneLayoutPrimaryCells(
      sessionController,
      node.second!,
      axis,
    );
    if (node.splitAxis == axis) {
      return firstSize + secondSize;
    }
    return math.max(firstSize, secondSize);
  }

  void _handleTerminalLinkHover(
    String sessionId,
    terminal.TerminalLinkTarget? target,
  ) {
    final previous = _hoveredTerminalLink;
    if (previous?.uri == target?.uri &&
        previous?.visibleText == target?.visibleText &&
        previous?.explicitHyperlink == target?.explicitHyperlink &&
        _hoveredTerminalLinkSessionId == (target == null ? null : sessionId)) {
      return;
    }
    if (!mounted) {
      return;
    }
    _mutateState(() {
      _hoveredTerminalLink = target;
      _hoveredTerminalLinkSessionId = target == null ? null : sessionId;
    });
  }

  bool _sessionIsInMultiPaneTab(String sessionId) {
    final tab = _tabForSession(ref.read(sessionControllerProvider), sessionId);
    return tab != null && tab.effectivePanes.length > 1;
  }

  String _terminalPaneContextLine(String sessionId) {
    final state = ref.read(sessionControllerProvider);
    final pane = _paneForSession(state, sessionId);
    final paneState = state.activeSessionId == sessionId
        ? 'active pane'
        : 'inactive pane';
    if (pane == null) {
      return 'Pane: $sessionId · $paneState';
    }
    return 'Pane: ${pane.title} ($sessionId) · $paneState';
  }

  Future<void> _openTerminalLinkTarget(
    String sessionId,
    terminal.TerminalLinkTarget target,
  ) {
    return _openTerminalLink(target.uri, sourceSessionId: sessionId);
  }

  Future<void> _handleTerminalLinkContextMenu(
    String sessionId,
    terminal.TerminalLinkTarget target,
  ) async {
    if (!mounted) {
      return;
    }
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (overlay is! RenderBox) {
      return;
    }
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(target.globalPosition.dx, target.globalPosition.dy, 1, 1),
      Offset.zero & overlay.size,
    );
    final action = await showMenu<_TerminalLinkMenuAction>(
      context: context,
      position: position,
      items: [
        const PopupMenuItem(
          value: _TerminalLinkMenuAction.open,
          child: Text('Open link'),
        ),
        const PopupMenuItem(
          value: _TerminalLinkMenuAction.copy,
          child: Text('Copy link'),
        ),
        PopupMenuItem(
          value: _TerminalLinkMenuAction.copyText,
          enabled: target.visibleText?.trim().isNotEmpty ?? false,
          child: const Text('Copy link text'),
        ),
        const PopupMenuItem(
          value: _TerminalLinkMenuAction.inspect,
          child: Text('Show target'),
        ),
      ],
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _TerminalLinkMenuAction.open:
        await _openTerminalLink(target.uri, sourceSessionId: sessionId);
      case _TerminalLinkMenuAction.copy:
        await ClipboardBridge.copy(target.uri);
        _showShellSnackBar('Copied link target');
      case _TerminalLinkMenuAction.copyText:
        final text = target.visibleText?.trim();
        if (text == null || text.isEmpty) {
          return;
        }
        await ClipboardBridge.copy(text);
        _showShellSnackBar('Copied link text');
      case _TerminalLinkMenuAction.inspect:
        _showShellSnackBar(_terminalLinkInspectionMessage(target));
    }
  }

  Future<void> _openTerminalLink(
    String url, {
    String? sourceSessionId,
    bool filePermissionGranted = false,
  }) async {
    final normalized = url.trim();
    final uri = Uri.tryParse(normalized);
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null ||
        scheme == null ||
        !const <String>{'http', 'https', 'file'}.contains(scheme) ||
        ((scheme == 'http' || scheme == 'https') && uri.host.isEmpty) ||
        (scheme == 'file' &&
            (uri.host.isNotEmpty || uri.path.isEmpty || uri.path == '/'))) {
      _showShellSnackBar(
        'Blocked link scheme: ${scheme == null || scheme.isEmpty ? 'unknown' : scheme}',
      );
      return;
    }
    if (scheme == 'file' &&
        !filePermissionGranted &&
        !await _confirmOpenFileLink(
          normalized,
          sourceSessionId: sourceSessionId,
        )) {
      _showShellSnackBar('Blocked file link');
      return;
    }
    try {
      await ref.read(shellExternalUrlOpenerProvider)(normalized);
    } on PlatformException catch (error) {
      final message = error.message?.trim();
      _showShellSnackBar(
        message == null || message.isEmpty
            ? 'Could not open link'
            : 'Could not open link: $message',
      );
    }
  }

  Future<bool> _confirmOpenFileLink(
    String url, {
    String? sourceSessionId,
  }) async {
    if (!mounted) {
      return false;
    }
    final sourceContext =
        sourceSessionId != null && _sessionIsInMultiPaneTab(sourceSessionId)
        ? _terminalPaneContextLine(sourceSessionId)
        : null;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Open local file link?'),
          content: SelectableText(
            [
              'The terminal is asking to open a local file URL.',
              if (sourceContext != null) 'Source: $sourceContext',
              '',
              url,
            ].join('\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Deny'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Open'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  String _terminalLinkInspectionMessage(terminal.TerminalLinkTarget target) {
    final visibleText = target.visibleText?.trim();
    if (target.hasMismatchedVisibleText &&
        visibleText != null &&
        visibleText.isNotEmpty) {
      return 'Link text "$visibleText" opens ${target.uri}';
    }
    return 'Link target: ${target.uri}';
  }

  String _terminalLinkShortLabel(String value) {
    final uri = Uri.tryParse(value.trim());
    final host = uri?.host.trim();
    if (host != null && host.isNotEmpty) {
      return host.length <= 22 ? host : '${host.substring(0, 19)}...';
    }
    final scheme = uri?.scheme.trim();
    if (scheme != null && scheme.isNotEmpty) {
      return scheme.toUpperCase();
    }
    return 'TARGET';
  }

  List<_TerminalPaneHeaderIndicator> _paneHeaderIndicatorsFor(
    TerminalPane pane, {
    required terminal.TerminalFrameModes modes,
    required bool readOnly,
  }) {
    final indicators = <_TerminalPaneHeaderIndicator>[];
    final contextLine = _terminalPaneContextLine(pane.sessionId);
    final focusLine = _sessionNeedsFocus(pane.sessionId)
        ? 'Click to focus this pane.'
        : null;
    void addModeIndicator({
      required String kind,
      required String label,
      required String tooltip,
      required IconData icon,
    }) {
      indicators.add(
        _TerminalPaneHeaderIndicator(
          kind: kind,
          label: label,
          tooltip: [contextLine, tooltip, ?focusLine].join('\n'),
          icon: icon,
        ),
      );
    }

    final hostname = pane.shellIntegration.hostname?.trim();
    final username = pane.shellIntegration.username?.trim();
    if (_shellHostIsRemote(hostname)) {
      indicators.add(
        _TerminalPaneHeaderIndicator(
          kind: 'remote',
          label: 'REMOTE ${_shortStatusValue(hostname!, max: 14)}',
          tooltip: [
            contextLine,
            'Remote context reported by shell integration.',
            'Host: $hostname',
            if (username != null && username.isNotEmpty) 'User: $username',
            'Local file actions stay disabled for remote paths.',
            ?focusLine,
          ].join('\n'),
          icon: Icons.cloud_outlined,
        ),
      );
    }

    final progressItems = _shellPaneActiveProgressItems(pane);
    if (progressItems.isNotEmpty) {
      final primaryProgress = _shellPanePrimaryProgress(pane)!;
      indicators.add(
        _TerminalPaneHeaderIndicator(
          kind: 'progress',
          label: _shortStatusValue(primaryProgress.displayLabel, max: 16),
          tooltip: progressItems.length == 1
              ? [
                  contextLine,
                  _progressStatusTooltip(primaryProgress),
                  ?focusLine,
                ].join('\n')
              : [
                  contextLine,
                  'Terminal progress in this pane.',
                  for (final progress in progressItems)
                    '${progress.displayLabel}: ${_progressStatusTooltip(progress)}',
                  ?focusLine,
                ].join('\n'),
          icon: Icons.timelapse_rounded,
        ),
      );
    }

    final notification = pane.recentNotifications.isEmpty
        ? null
        : pane.recentNotifications.first;
    if (notification != null) {
      indicators.add(
        _TerminalPaneHeaderIndicator(
          kind: 'notification',
          label:
              'NOTIFY ${_shortStatusValue(notification.title, max: 12)}'
              '${notification.count > 1 ? ' x${notification.count}' : ''}',
          tooltip: [
            contextLine,
            _notificationStatusTooltip(notification),
            ?focusLine,
          ].join('\n'),
          icon: Icons.notifications_none_rounded,
        ),
      );
    }

    final badge = pane.oscBadge?.trim();
    if (badge != null && badge.isNotEmpty) {
      indicators.add(
        _TerminalPaneHeaderIndicator(
          kind: 'badge',
          label: 'BADGE ${_shortStatusValue(badge, max: 12)}',
          tooltip: [
            contextLine,
            'OSC 1337 badge: $badge',
            ?focusLine,
          ].join('\n'),
          icon: Icons.badge_outlined,
        ),
      );
    }

    if (modes.alternateScreen) {
      addModeIndicator(
        kind: 'alt',
        label: 'ALT',
        tooltip: 'Alternate screen buffer is active.',
        icon: Icons.fullscreen_rounded,
      );
    }
    if (modes.mouseMode != 'off') {
      addModeIndicator(
        kind: 'mouse',
        label: 'MOUSE',
        tooltip:
            'Mouse reporting is active: ${_mouseModeStatusLabel(modes.mouseMode)}, ${_mouseEncodingStatusLabel(modes.mouseEncoding)}.',
        icon: Icons.mouse_outlined,
      );
    }
    if (modes.mimePaste) {
      addModeIndicator(
        kind: 'mime-paste',
        label: 'MIME PASTE',
        tooltip:
            'OSC 5522 paste events are active and take precedence over bracketed paste.',
        icon: Icons.content_paste_go_rounded,
      );
    } else if (modes.bracketedPaste) {
      addModeIndicator(
        kind: 'paste',
        label: 'PASTE',
        tooltip: 'Bracketed paste mode is active.',
        icon: Icons.content_paste_rounded,
      );
    }
    if (modes.focusTracking) {
      addModeIndicator(
        kind: 'focus',
        label: 'FOCUS',
        tooltip:
            'Focus reporting is active. The application receives focus-in and focus-out events.',
        icon: Icons.center_focus_strong_rounded,
      );
    }
    if (modes.kittyKeyboardFlags != 0) {
      addModeIndicator(
        kind: 'kitty-keyboard',
        label: 'KEYS',
        tooltip: _kittyKeyboardStatusTooltip(modes.kittyKeyboardFlags),
        icon: Icons.keyboard_alt_outlined,
      );
    }
    if (modes.synchronizedOutput) {
      addModeIndicator(
        kind: 'sync',
        label: 'SYNC',
        tooltip:
            'Synchronized output mode is active. Intermediate updates are held until the application flushes.',
        icon: Icons.sync_rounded,
      );
    }
    if (readOnly) {
      addModeIndicator(
        kind: 'read-only',
        label: 'READ ONLY',
        tooltip:
            'Read-only mode is enabled for this pane. Input and paste sends are blocked.',
        icon: Icons.lock_outline_rounded,
      );
    }
    return indicators;
  }
}

class _TerminalAttentionBurst extends StatefulWidget {
  const _TerminalAttentionBurst({
    super.key,
    required this.animate,
    required this.colors,
  });

  final bool animate;
  final List<Color> colors;

  @override
  State<_TerminalAttentionBurst> createState() =>
      _TerminalAttentionBurstState();
}

class _TerminalAttentionBurstState extends State<_TerminalAttentionBurst>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400),
      )..forward();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return IgnorePointer(
      child: Semantics(
        container: true,
        liveRegion: true,
        label: 'Terminal requested attention',
        child: RepaintBoundary(
          child: controller == null
              ? CustomPaint(
                  painter: _TerminalAttentionBurstPainter(
                    progress: 0.58,
                    colors: widget.colors,
                    staticFallback: true,
                  ),
                )
              : AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => CustomPaint(
                    painter: _TerminalAttentionBurstPainter(
                      progress: controller.value,
                      colors: widget.colors,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _TerminalAttentionBurstPainter extends CustomPainter {
  const _TerminalAttentionBurstPainter({
    required this.progress,
    required this.colors,
    this.staticFallback = false,
  });

  final double progress;
  final List<Color> colors;
  final bool staticFallback;

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty || size.isEmpty) {
      return;
    }
    final center = size.center(Offset.zero);
    final eased = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final opacity = staticFallback
        ? 0.88
        : (1 - Curves.easeIn.transform(progress)).clamp(0.0, 1.0);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = colors.first.withValues(alpha: opacity * 0.86);
    canvas.drawCircle(center, 7 + 20 * eased, ringPaint);

    for (var index = 0; index < 12; index += 1) {
      final angle = (math.pi * 2 * index / 12) - math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final innerRadius = 9 + 7 * eased;
      final outerRadius = 15 + (index.isEven ? 17 : 12) * eased;
      final color = colors[index % colors.length].withValues(
        alpha: opacity * (index.isEven ? 0.95 : 0.72),
      );
      final rayPaint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = index.isEven ? 2.2 : 1.5
        ..color = color;
      canvas.drawLine(
        center + direction * innerRadius,
        center + direction * outerRadius,
        rayPaint,
      );
      canvas.drawCircle(
        center + direction * (outerRadius + 2.5),
        index.isEven ? 2.2 : 1.5,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_TerminalAttentionBurstPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.staticFallback != staticFallback ||
        !listEquals(oldDelegate.colors, colors);
  }
}

class _TerminalPaneHeaderIndicator {
  const _TerminalPaneHeaderIndicator({
    required this.kind,
    required this.label,
    required this.tooltip,
    required this.icon,
  });

  final String kind;
  final String label;
  final String tooltip;
  final IconData icon;
}

class _TerminalPaneHeader extends StatelessWidget {
  const _TerminalPaneHeader({
    super.key,
    required this.palette,
    required this.sessionId,
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.isZoomed,
    required this.canZoom,
    required this.indicators,
    required this.onActivate,
    required this.splitRightTooltip,
    required this.onSplitRight,
    required this.splitDownTooltip,
    required this.onSplitDown,
    required this.onToggleZoom,
    required this.onClose,
  });

  final AppThemeTokens palette;
  final String sessionId;
  final String title;
  final String subtitle;
  final bool isActive;
  final bool isZoomed;
  final bool canZoom;
  final List<_TerminalPaneHeaderIndicator> indicators;
  final VoidCallback onActivate;
  final String splitRightTooltip;
  final VoidCallback? onSplitRight;
  final String splitDownTooltip;
  final VoidCallback? onSplitDown;
  final VoidCallback? onToggleZoom;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final foregroundColor = isActive ? palette.textPrimary : palette.textMuted;
    final metadataColor = isActive ? palette.textMuted : palette.textSubtle;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isActive
            ? palette.panelElevated.withValues(alpha: 0.88)
            : palette.chrome.withValues(alpha: 0.62),
        border: Border(
          bottom: BorderSide(
            color: isActive
                ? palette.focusRing.withValues(alpha: 0.36)
                : palette.border,
          ),
        ),
      ),
      child: SizedBox(
        height: 32,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 8, end: 5),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 230;
              final showLeadingIcon = constraints.maxWidth >= 210;
              final showSubtitle = constraints.maxWidth >= 260;
              final showSplitActions = !compact;
              final showIndicators = constraints.maxWidth >= 110;
              final showZoomAction = constraints.maxWidth >= 96;
              final showCloseAction = constraints.maxWidth >= 72;
              final actions = <Widget>[
                if (showSplitActions) ...[
                  _TerminalPaneHeaderAction(
                    buttonKey: Key('shell-pane-action-split-right-$sessionId'),
                    tooltip: splitRightTooltip,
                    icon: Icons.vertical_split_rounded,
                    palette: palette,
                    onPressed: onSplitRight,
                  ),
                  _TerminalPaneHeaderAction(
                    buttonKey: Key('shell-pane-action-split-down-$sessionId'),
                    tooltip: splitDownTooltip,
                    icon: Icons.horizontal_split_rounded,
                    palette: palette,
                    onPressed: onSplitDown,
                  ),
                ],
                if (showZoomAction)
                  _TerminalPaneHeaderAction(
                    buttonKey: Key('shell-pane-action-zoom-$sessionId'),
                    tooltip: isZoomed ? 'Unzoom pane' : 'Zoom pane',
                    icon: isZoomed
                        ? Icons.close_fullscreen_rounded
                        : Icons.open_in_full_rounded,
                    palette: palette,
                    onPressed: canZoom ? onToggleZoom : null,
                    selected: isZoomed,
                  ),
                if (showCloseAction)
                  _TerminalPaneHeaderAction(
                    buttonKey: Key('shell-pane-action-close-$sessionId'),
                    tooltip: 'Close pane',
                    icon: Icons.close_rounded,
                    palette: palette,
                    onPressed: onClose,
                  ),
              ];
              return Row(
                children: [
                  if (showLeadingIcon) ...[
                    Icon(
                      Icons.terminal_rounded,
                      size: 14,
                      color: metadataColor,
                      semanticLabel: isActive ? 'Active pane' : 'Inactive pane',
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            key: Key('shell-pane-header-title-$sessionId'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelMedium?.copyWith(
                              color: foregroundColor,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                        if (showSubtitle) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              subtitle,
                              key: Key('shell-pane-header-subtitle-$sessionId'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelSmall?.copyWith(
                                color: metadataColor,
                                fontWeight: FontWeight.w700,
                                height: 1,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!isActive && showIndicators && indicators.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: _TerminalPaneHeaderIndicatorStrip(
                        sessionId: sessionId,
                        indicators: indicators,
                        foregroundColor: foregroundColor,
                        borderColor: palette.border,
                        backgroundColor: palette.panel.withValues(alpha: 0.38),
                        onActivate: onActivate,
                      ),
                    ),
                  ],
                  if (isActive && actions.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    ...actions,
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TerminalPaneHeaderIndicatorChip extends StatelessWidget {
  const _TerminalPaneHeaderIndicatorChip({
    super.key,
    required this.indicator,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.onActivate,
  });

  final _TerminalPaneHeaderIndicator indicator;
  final Color foregroundColor;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final chip = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 112, minHeight: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                indicator.icon,
                size: 12,
                color: foregroundColor.withValues(alpha: 0.82),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  indicator.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foregroundColor,
                    fontSize: 10.5,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Tooltip(
      message: indicator.tooltip,
      child: Semantics(
        label: indicator.tooltip,
        button: true,
        onTap: onActivate,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onActivate,
            child: chip,
          ),
        ),
      ),
    );
  }
}

class _TerminalPaneHeaderIndicatorStrip extends StatelessWidget {
  const _TerminalPaneHeaderIndicatorStrip({
    required this.sessionId,
    required this.indicators,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.onActivate,
  });

  final String sessionId;
  final List<_TerminalPaneHeaderIndicator> indicators;
  final Color foregroundColor;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SingleChildScrollView(
        reverse: true,
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final indicator in indicators) ...[
              _TerminalPaneHeaderIndicatorChip(
                key: Key(
                  'shell-pane-header-indicator-${indicator.kind}-$sessionId',
                ),
                indicator: indicator,
                foregroundColor: foregroundColor,
                borderColor: borderColor,
                backgroundColor: backgroundColor,
                onActivate: onActivate,
              ),
              const SizedBox(width: 4),
            ],
          ],
        ),
      ),
    );
  }
}

class _TerminalPaneHeaderAction extends StatelessWidget {
  const _TerminalPaneHeaderAction({
    required this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.palette,
    required this.onPressed,
    this.selected = false,
  });

  final Key buttonKey;
  final String tooltip;
  final IconData icon;
  final AppThemeTokens palette;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = selected
        ? palette.focusRing
        : enabled
        ? palette.textMuted
        : palette.textSubtle.withValues(alpha: 0.54);
    return _buildCompactActionButton(
      key: buttonKey,
      tooltip: tooltip,
      icon: Icon(icon, color: color),
      onPressed: onPressed,
      splashRadius: 14,
      iconSize: 15,
      constraints: const BoxConstraints.tightFor(width: 26, height: 24),
      padding: EdgeInsets.zero,
      isSelected: selected,
      selectedIcon: Icon(icon, color: color),
    );
  }
}
