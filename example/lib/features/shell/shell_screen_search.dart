part of 'shell_screen.dart';

class _TerminalSearchBar extends StatefulWidget {
  const _TerminalSearchBar({
    required this.query,
    required this.matches,
    required this.activeIndex,
    required this.searchMode,
    required this.errorText,
    required this.palette,
    required this.focusNode,
    required this.focusRequestSerial,
    required this.onChanged,
    required this.onClear,
    required this.onModeChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final String query;
  final int matches;
  final int activeIndex;
  final terminal.TerminalSearchMode searchMode;
  final String? errorText;
  final AppThemeTokens palette;
  final FocusNode focusNode;
  final int focusRequestSerial;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<terminal.TerminalSearchMode> onModeChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  State<_TerminalSearchBar> createState() => _TerminalSearchBarState();
}

class _TerminalSearchBarState extends State<_TerminalSearchBar> {
  static const _searchBarMaxWidth = 544.0;
  static const _searchBarIdleWidth = 544.0;
  static const _searchBarCompactBreakpoint = 430.0;
  static const _searchBarControlHeight = 40.0;
  static const _searchFieldEditHeight = 24.0;
  static const _searchBarHorizontalInset = 8.0;
  static const _searchBarVerticalInset = 8.0;

  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusAndSelectQuery();
    });
  }

  @override
  void didUpdateWidget(_TerminalSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) {
      _controller.value = _controller.value.copyWith(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
        composing: TextRange.empty,
      );
    }
    if (oldWidget.focusRequestSerial != widget.focusRequestSerial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _focusAndSelectQuery();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _counterText {
    if (widget.errorText != null) {
      return 'Regex error';
    }
    if (widget.query.isEmpty) {
      return '';
    }
    if (widget.matches == 0) {
      return 'No matches';
    }
    return '${widget.activeIndex + 1}/${widget.matches}';
  }

  void _focusAndSelectQuery() {
    widget.focusNode.requestFocus();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  String _searchModeLabel(terminal.TerminalSearchMode mode) {
    return switch (mode) {
      terminal.TerminalSearchMode.smartCaseSubstring => 'Smart Case Substring',
      terminal.TerminalSearchMode.caseSensitiveSubstring =>
        'Case-Sensitive Substring',
      terminal.TerminalSearchMode.caseInsensitiveSubstring =>
        'Case-Insensitive Substring',
      terminal.TerminalSearchMode.caseSensitiveRegex => 'Case-Sensitive Regex',
      terminal.TerminalSearchMode.caseInsensitiveRegex =>
        'Case-Insensitive Regex',
    };
  }

  Widget _searchModeMark(terminal.TerminalSearchMode mode) {
    final palette = widget.palette;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: palette.textPrimary,
      fontWeight: FontWeight.w800,
      height: 1,
    );
    return switch (mode) {
      terminal.TerminalSearchMode.smartCaseSubstring => Icon(
        Icons.manage_search_rounded,
        size: 17,
        color: palette.textPrimary,
      ),
      terminal.TerminalSearchMode.caseSensitiveSubstring => Text(
        'Aa',
        style: style,
      ),
      terminal.TerminalSearchMode.caseInsensitiveSubstring => Text(
        'aa',
        style: style,
      ),
      terminal.TerminalSearchMode.caseSensitiveRegex => Text(
        '.*',
        style: style,
      ),
      terminal.TerminalSearchMode.caseInsensitiveRegex => Text(
        '.*i',
        style: style,
      ),
    };
  }

  Widget _buildSearchModeButton(
    BuildContext context,
    MenuController controller,
  ) {
    final palette = widget.palette;
    return Tooltip(
      message: 'Search filter: ${_searchModeLabel(widget.searchMode)}',
      child: Semantics(
        button: true,
        label: 'Search filter',
        child: InkWell(
          key: const Key('terminal-search-mode'),
          borderRadius: BorderRadius.circular(palette.radius.sm),
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(palette.radius.sm),
            ),
            child: SizedBox(
              width: 40,
              height: _searchBarControlHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 22,
                    child: Center(child: _searchModeMark(widget.searchMode)),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: palette.textSubtle,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSearchModeMenuChildren(BuildContext context) {
    final palette = widget.palette;
    final textTheme = Theme.of(context).textTheme;
    final modes = terminal.TerminalSearchMode.values;

    Widget item(terminal.TerminalSearchMode mode) {
      final selected = mode == widget.searchMode;
      return MenuItemButton(
        key: Key('terminal-search-mode-${mode.wireName}'),
        onPressed: () {
          widget.onModeChanged(mode);
        },
        style: ButtonStyle(
          minimumSize: WidgetStateProperty.all(const Size(336, 34)),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          backgroundColor: WidgetStateProperty.all(
            selected ? palette.selected : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.all(palette.textPrimary),
          overlayColor: WidgetStateProperty.all(
            palette.accent.withValues(alpha: 0.12),
          ),
        ),
        leadingIcon: selected
            ? Icon(Icons.check_rounded, size: 18, color: palette.textPrimary)
            : const SizedBox(width: 18, height: 18),
        child: Text(
          _searchModeLabel(mode),
          style: textTheme.bodyMedium?.copyWith(
            color: palette.textPrimary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      );
    }

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(
          'Filter',
          style: textTheme.titleSmall?.copyWith(
            color: palette.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Divider(color: palette.border),
      item(modes[0]),
      Divider(color: palette.border),
      item(modes[1]),
      item(modes[2]),
      Divider(color: palette.border),
      item(modes[3]),
      item(modes[4]),
    ];
  }

  Widget _buildSearchModeMenu(BuildContext context) {
    final palette = widget.palette;
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(palette.overlay),
        elevation: WidgetStateProperty.all(8.0),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(vertical: 6),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(palette.radius.md),
            side: BorderSide(color: palette.borderStrong),
          ),
        ),
      ),
      menuChildren: _buildSearchModeMenuChildren(context),
      builder: (context, controller, child) {
        return _buildSearchModeButton(context, controller);
      },
    );
  }

  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (isShiftPressed) {
        widget.onPrevious();
      } else {
        widget.onNext();
      }
      return KeyEventResult.handled;
    }
    if (isMetaPressed && event.logicalKey == LogicalKeyboardKey.keyF) {
      _focusAndSelectQuery();
      return KeyEventResult.handled;
    }
    if (isMetaPressed && event.logicalKey == LogicalKeyboardKey.keyA) {
      _focusAndSelectQuery();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildInlineSearchClearButton() {
    return _buildCompactActionButton(
      key: const Key('terminal-search-clear'),
      tooltip: 'Clear search text',
      onPressed: widget.onClear,
      splashRadius: 14,
      iconSize: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 22, height: 22),
      icon: Icon(Icons.cancel_rounded, color: widget.palette.textSubtle),
    );
  }

  Widget _buildInlineSearchStatus(BuildContext context) {
    if (_counterText.isEmpty) {
      return const SizedBox.shrink();
    }
    final foreground = _statusForeground(context);
    return Semantics(
      liveRegion: true,
      label: 'Search result: $_counterText',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 78),
        child: Padding(
          key: const Key('terminal-search-status'),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            _counterText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: foreground.withValues(alpha: 0.92),
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final palette = widget.palette;
    final textTheme = Theme.of(context).textTheme;
    final baseTextStyle = textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final inputTextStyle = baseTextStyle.copyWith(
      color: palette.textPrimary,
      fontWeight: FontWeight.w600,
      height: 1.1,
    );
    final hintTextStyle = baseTextStyle.copyWith(
      color: palette.textSubtle,
      fontWeight: FontWeight.w500,
      height: 1.1,
    );
    return AnimatedBuilder(
      animation: widget.focusNode,
      builder: (context, _) {
        final focused = widget.focusNode.hasFocus;
        return SizedBox(
          key: const Key('terminal-search-input'),
          height: _searchBarControlHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.chrome.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(palette.radius.sm),
              border: Border.all(
                color: focused ? palette.focusRing : palette.border,
                width: focused ? 1.4 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 2, right: 8),
              child: Row(
                children: [
                  _buildSearchModeMenu(context),
                  Expanded(
                    child: Focus(
                      onKeyEvent: _handleSearchKeyEvent,
                      child: Semantics(
                        label: 'Search terminal output',
                        textField: true,
                        child: SizedBox(
                          height: _searchBarControlHeight,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              height: _searchFieldEditHeight,
                              child: TextField(
                                key: const Key('terminal-search-field'),
                                focusNode: widget.focusNode,
                                controller: _controller,
                                autofocus: true,
                                textInputAction: TextInputAction.search,
                                textAlignVertical: TextAlignVertical.center,
                                minLines: 1,
                                maxLines: 1,
                                cursorColor: palette.focusRing,
                                strutStyle: StrutStyle.fromTextStyle(
                                  inputTextStyle,
                                  forceStrutHeight: true,
                                ),
                                onChanged: widget.onChanged,
                                onSubmitted: (_) => widget.onNext(),
                                style: inputTextStyle,
                                decoration: InputDecoration(
                                  isCollapsed: true,
                                  filled: false,
                                  fillColor: Colors.transparent,
                                  contentPadding: EdgeInsets.zero,
                                  hintText: 'Search',
                                  hintStyle: hintTextStyle,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_counterText.isNotEmpty)
                    _buildInlineSearchStatus(context),
                  if (widget.query.isNotEmpty) const SizedBox(width: 2),
                  if (widget.query.isNotEmpty) _buildInlineSearchClearButton(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _statusForeground(BuildContext context) {
    if (widget.errorText != null) {
      return Theme.of(context).colorScheme.onErrorContainer;
    }
    if (widget.matches == 0 && widget.query.isNotEmpty) {
      return widget.palette.warning;
    }
    return widget.palette.textPrimary;
  }

  List<Widget> _buildSearchNavigationButtons(BoxConstraints constraints) {
    return [
      _buildCompactActionButton(
        key: const Key('terminal-search-previous'),
        tooltip: 'Previous match',
        onPressed: widget.matches == 0 ? null : widget.onPrevious,
        splashRadius: 18,
        iconSize: 24,
        padding: EdgeInsets.zero,
        constraints: constraints,
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      _buildCompactActionButton(
        key: const Key('terminal-search-next'),
        tooltip: 'Next match',
        onPressed: widget.matches == 0 ? null : widget.onNext,
        splashRadius: 18,
        iconSize: 24,
        padding: EdgeInsets.zero,
        constraints: constraints,
        icon: const Icon(Icons.chevron_right_rounded),
      ),
    ];
  }

  Widget _buildSearchCloseButton(BoxConstraints constraints) {
    return _buildCompactActionButton(
      key: const Key('terminal-search-close'),
      tooltip: 'Close search',
      onPressed: widget.onClose,
      splashRadius: 16,
      iconSize: 22,
      padding: EdgeInsets.zero,
      constraints: constraints,
      icon: const Icon(Icons.close_rounded),
    );
  }

  Widget _buildRegularSearchRow(
    BuildContext context,
    BoxConstraints actionButtonConstraints,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _buildSearchField(context)),
        const SizedBox(width: 12),
        ..._buildSearchNavigationButtons(actionButtonConstraints),
        const SizedBox(width: 4),
        _buildSearchCloseButton(actionButtonConstraints),
      ],
    );
  }

  Widget _buildCompactSearchRows(
    BuildContext context,
    BoxConstraints actionButtonConstraints,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _buildSearchField(context)),
        const SizedBox(width: 8),
        _buildSearchCloseButton(actionButtonConstraints),
      ],
    );
  }

  Widget _buildSearchPanel(BuildContext context, {required bool compact}) {
    final palette = widget.palette;
    const actionButtonConstraints = BoxConstraints.tightFor(
      width: 34,
      height: 40,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.overlay.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(palette.radius.lg),
        border: Border.all(
          color: widget.errorText == null
              ? palette.borderStrong.withValues(alpha: 0.72)
              : Theme.of(context).colorScheme.error.withValues(alpha: 0.55),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _searchBarHorizontalInset,
          vertical: _searchBarVerticalInset,
        ),
        child: compact
            ? _buildCompactSearchRows(context, actionButtonConstraints)
            : _buildRegularSearchRow(context, actionButtonConstraints),
      ),
    );
  }

  double get _preferredBarWidth {
    if (widget.query.isEmpty && widget.errorText == null) {
      return _searchBarIdleWidth;
    }
    return _searchBarMaxWidth;
  }

  @override
  Widget build(BuildContext context) {
    final preferredWidth = _preferredBarWidth;
    return Material(
      key: const Key('terminal-search-bar'),
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : preferredWidth;
          final width = math.min(preferredWidth, availableWidth);
          final compact = width < _searchBarCompactBreakpoint;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: width,
                child: _buildSearchPanel(context, compact: compact),
              ),
              if (widget.errorText != null)
                _TerminalSearchErrorPopover(
                  errorText: widget.errorText!,
                  palette: widget.palette,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TerminalSearchErrorPopover extends StatelessWidget {
  const _TerminalSearchErrorPopover({
    required this.errorText,
    required this.palette,
  });

  final String errorText;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6, right: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 276),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.errorContainer.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(palette.radius.md),
            border: Border.all(
              color: colorScheme.error.withValues(alpha: 0.55),
            ),
            boxShadow: palette.elevation.floating,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    errorText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlobalSearchSheet extends StatefulWidget {
  const _GlobalSearchSheet({required this.sessions, required this.onSearch});

  final List<_SearchableSession> sessions;
  final List<_GlobalSearchResult> Function(
    String query,
    List<_SearchableSession> sessions,
  )
  onSearch;

  @override
  State<_GlobalSearchSheet> createState() => _GlobalSearchSheetState();
}

class _GlobalSearchSheetState extends State<_GlobalSearchSheet> {
  String _query = '';
  List<_GlobalSearchResult> _results = const [];

  String get _scopeText {
    final count = widget.sessions.length;
    final noun = count == 1 ? 'session' : 'sessions';
    return 'Searching across $count $noun';
  }

  void _handleQueryChanged(String value) {
    setState(() {
      _query = value;
      _results = widget.onSearch(value, widget.sessions);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final resultCount = _results.length;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Material(
        key: const Key('terminal-global-search-sheet'),
        color: palette.panel,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(palette.radius.lg),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('terminal-global-search-field'),
                          autofocus: true,
                          onChanged: _handleQueryChanged,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: palette.textPrimary),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.manage_search_rounded),
                            hintText: 'Global search',
                            isDense: true,
                            filled: true,
                            fillColor: palette.overlay,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                palette.radius.sm,
                              ),
                              borderSide: BorderSide(color: palette.border),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$resultCount matches',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: palette.textSubtle,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(width: 8),
                      _buildSheetCloseButton(
                        buttonKey: const Key('terminal-global-search-close'),
                        tooltip: 'Close global search',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: _query.trim().isEmpty
                        ? Center(
                            child: Text(
                              _scopeText,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.textMuted),
                            ),
                          )
                        : resultCount == 0
                        ? Center(
                            child: Text(
                              'No matches',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.textMuted),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: resultCount,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final result = _results[index];
                              return _ShellEntryTile(
                                key: Key(
                                  'terminal-global-search-result-${result.session.sessionId}-$index',
                                ),
                                dense: true,
                                title: result.match.text,
                                subtitle:
                                    '${result.session.title} • row ${result.match.row + 1}',
                                subtitleMaxLines: 1,
                                trailing: const Icon(
                                  Icons.keyboard_return_rounded,
                                  size: 18,
                                ),
                                onTap: () => Navigator.of(context).pop(result),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
