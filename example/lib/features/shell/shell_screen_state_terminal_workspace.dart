part of 'shell_screen.dart';

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
    final hasPaneAffordanceHeader =
        isActive &&
        !_isSearchOpen &&
        !_isAutocompleteOpen &&
        !_isAutoComposerOpen &&
        !_isCopyModeOpen &&
        (activeTab.effectivePanes.length > 1 ||
            _zoomedPaneSessionId == sessionId);
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
    final paneIndex = math.max(
      0,
      activeTab.effectivePanes.indexWhere(
        (pane) => pane.sessionId == sessionId,
      ),
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

        return Listener(
          onPointerDown: (event) {
            if (!isActive && (event.buttons & kPrimaryMouseButton) != 0) {
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
            child: Stack(
              children: [
                Positioned.fill(
                  child: TerminalViewport(
                    focusNode: focusNode,
                    controller: viewportController,
                    selectionController: selectionController,
                    inputController: inputController,
                    contentPadding: terminalViewportPadding,
                    onMeasuredCellSizeChanged: (cellSize) {
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
                        (terminalConfig?.interaction.copyOnSelect ?? false),
                    optionDragMode:
                        terminalConfig?.interaction.optionDragMode ??
                        terminal.TerminalOptionDragMode.blockSelection,
                    searchMatches: _isSearchOpen
                        ? _searchMatchesForSession(sessionId)
                        : const <terminal.TerminalSearchMatch>[],
                    activeSearchMatchIndex: _isSearchOpen
                        ? _activeSearchMatchIndexForSession(sessionId)
                        : -1,
                    searchHighlightStyle: terminal.TerminalSearchHighlightStyle(
                      activeFill: palette.accent.withValues(alpha: 0.34),
                      inactiveFill: palette.warning.withValues(alpha: 0.22),
                      activeBorder: palette.accent.withValues(alpha: 0.82),
                      radius: 3,
                    ),
                    graphicsCache: sessionController.graphicsCacheFor(
                      sessionId,
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
                    onOpenLink: (url) =>
                        unawaited(WindowBridge.openExternalUrl(url)),
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
                if (hasPaneAffordanceHeader)
                  Positioned(
                    top: _ShellScreenState._terminalOverlayPadding.top,
                    left: _ShellScreenState._terminalOverlayPadding.left,
                    child: _TerminalPaneHeader(
                      key: Key('shell-pane-header-$sessionId'),
                      palette: palette,
                      sessionId: sessionId,
                      maxWidth: math.max(
                        0,
                        constraints.maxWidth -
                            _ShellScreenState._terminalOverlayPadding.left -
                            _ShellScreenState._terminalOverlayPadding.right,
                      ),
                      title:
                          'Pane ${paneIndex + 1}/${activeTab.effectivePanes.length}',
                      isZoomed: _zoomedPaneSessionId == sessionId,
                      canZoom: activeTab.effectivePanes.length > 1,
                      onSplitRight:
                          defaultProfile == null ||
                              splitRightUnavailableReason != null
                          ? null
                          : () => _splitActiveSession(
                              sessionController,
                              defaultProfile,
                              TerminalSplitAxis.horizontal,
                            ),
                      onSplitDown:
                          defaultProfile == null ||
                              splitDownUnavailableReason != null
                          ? null
                          : () => _splitActiveSession(
                              sessionController,
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
                    bottom: _ShellScreenState._terminalOverlayPadding.bottom,
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
                if (isActive && annotations.isNotEmpty && !_isAutoComposerOpen)
                  Positioned(
                    left: _ShellScreenState._terminalOverlayPadding.left,
                    bottom: _ShellScreenState._terminalOverlayPadding.bottom,
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
  }
}

class _TerminalPaneHeader extends StatelessWidget {
  const _TerminalPaneHeader({
    super.key,
    required this.palette,
    required this.sessionId,
    required this.maxWidth,
    required this.title,
    required this.isZoomed,
    required this.canZoom,
    required this.onSplitRight,
    required this.onSplitDown,
    required this.onToggleZoom,
    required this.onClose,
  });

  final AppThemeTokens palette;
  final String sessionId;
  final double maxWidth;
  final String title;
  final bool isZoomed;
  final bool canZoom;
  final VoidCallback? onSplitRight;
  final VoidCallback? onSplitDown;
  final VoidCallback? onToggleZoom;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.panelElevated.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(palette.radius.md),
          border: Border.all(color: palette.focusRing.withValues(alpha: 0.36)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  key: Key('shell-pane-header-title-$sessionId'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: palette.textMuted,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _TerminalPaneHeaderAction(
                buttonKey: Key('shell-pane-action-split-right-$sessionId'),
                tooltip: 'Split right',
                icon: Icons.vertical_split_rounded,
                palette: palette,
                onPressed: onSplitRight,
              ),
              _TerminalPaneHeaderAction(
                buttonKey: Key('shell-pane-action-split-down-$sessionId'),
                tooltip: 'Split down',
                icon: Icons.horizontal_split_rounded,
                palette: palette,
                onPressed: onSplitDown,
              ),
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
              _TerminalPaneHeaderAction(
                buttonKey: Key('shell-pane-action-close-$sessionId'),
                tooltip: 'Close pane',
                icon: Icons.close_rounded,
                palette: palette,
                onPressed: onClose,
              ),
            ],
          ),
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
