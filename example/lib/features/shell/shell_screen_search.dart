part of 'shell_screen.dart';

/// macOS HIG body/control metrics, with app-owned spacing for this composite
/// search field. See output/search-review-20260925/apple-hig.md for sources.
abstract final class _SearchMetrics {
  static const bodySize = 13.0;
  static const bodyLineHeight = 16.0;
  static const secondarySize = 11.0;
  static const secondaryLineHeight = 14.0;
  static const controlTarget = 28.0;
  static const inset = 4.0;
  static const gap = 8.0;
  static const menuVerticalPadding = 6.0;
}

class _TerminalSearchBar extends StatefulWidget {
  const _TerminalSearchBar({
    required this.query,
    required this.matches,
    required this.activeIndex,
    required this.searchScope,
    required this.searchMode,
    required this.errorText,
    required this.palette,
    required this.focusNode,
    required this.focusRequestSerial,
    required this.onChanged,
    required this.onClear,
    required this.onScopeChanged,
    required this.onModeChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final String query;
  final int matches;
  final int activeIndex;
  final _TerminalSearchScope searchScope;
  final terminal.TerminalSearchMode searchMode;
  final String? errorText;
  final AppThemeTokens palette;
  final FocusNode focusNode;
  final int focusRequestSerial;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<_TerminalSearchScope> onScopeChanged;
  final ValueChanged<terminal.TerminalSearchMode> onModeChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  State<_TerminalSearchBar> createState() => _TerminalSearchBarState();
}

class _TerminalSearchBarState extends State<_TerminalSearchBar> {
  static const _searchBarMaxWidth = 520.0;
  static const _searchBarIdleWidth = 520.0;
  static const _searchBarCompactBreakpoint = 340.0;
  static const double _searchBarHorizontalInset = _SearchMetrics.gap;
  static const double _searchBarVerticalInset = _SearchMetrics.inset;

  // Compact desktop menus share the app's surfaces, type and shape tokens.
  // Keep a small inset around selected rows and a gap below the toolbar.
  static const double _searchMenuInset = _SearchMetrics.inset;

  late final TextEditingController _controller;
  final _modeFocusNode = FocusNode();
  final _scopeFocusNode = FocusNode();

  TextStyle get _controlTextStyle =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontSize: _SearchMetrics.bodySize,
        height: _SearchMetrics.bodyLineHeight / _SearchMetrics.bodySize,
        fontWeight: FontWeight.w400,
        color: widget.palette.textPrimary,
      );

  double get _textScale {
    final size = _controlTextStyle.fontSize!;
    return MediaQuery.textScalerOf(context).scale(size) / size;
  }

  double get _searchFieldEditHeight {
    final size = _controlTextStyle.fontSize!;
    return math.max(
      20,
      (MediaQuery.textScalerOf(context).scale(size) * _controlTextStyle.height!)
          .ceilToDouble(),
    );
  }

  double get _searchBarControlHeight => math.max(
    _SearchMetrics.controlTarget,
    _searchFieldEditHeight + _SearchMetrics.gap,
  );

  bool get _separateStatus => _textScale > 1.4 && widget.errorText == null;

  String? get _localizedErrorText =>
      widget.errorText == 'Invalid regular expression'
      ? context.l10n.invalidRegularExpression
      : widget.errorText;

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
    _modeFocusNode.dispose();
    _scopeFocusNode.dispose();
    super.dispose();
  }

  String get _counterText {
    if (widget.errorText != null) {
      return context.l10n.regexError;
    }
    if (widget.query.isEmpty) {
      return '';
    }
    if (widget.matches == 0) {
      return context.l10n.noMatches;
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

  Future<void> _pasteClipboardIntoQuery() async {
    final pastedText = await ClipboardBridge.paste();
    if (!mounted || pastedText.isEmpty) {
      return;
    }
    final value = _controller.value;
    final text = value.text;
    final selection = value.selection;

    int clampOffset(int offset) {
      if (offset < 0) {
        return 0;
      }
      if (offset > text.length) {
        return text.length;
      }
      return offset;
    }

    final start = selection.isValid
        ? clampOffset(math.min(selection.baseOffset, selection.extentOffset))
        : text.length;
    final end = selection.isValid
        ? clampOffset(math.max(selection.baseOffset, selection.extentOffset))
        : text.length;
    final nextText = text.replaceRange(start, end, pastedText);
    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + pastedText.length),
    );
    widget.focusNode.requestFocus();
    widget.onChanged(nextText);
  }

  String _searchModeLabel(terminal.TerminalSearchMode mode) {
    return switch (mode) {
      terminal.TerminalSearchMode.smartCaseSubstring =>
        context.l10n.smartCaseSubstring,
      terminal.TerminalSearchMode.caseSensitiveSubstring =>
        context.l10n.caseSensitiveSubstring,
      terminal.TerminalSearchMode.caseInsensitiveSubstring =>
        context.l10n.caseInsensitiveSubstring,
      terminal.TerminalSearchMode.caseSensitiveRegex =>
        context.l10n.caseSensitiveRegex,
      terminal.TerminalSearchMode.caseInsensitiveRegex =>
        context.l10n.caseInsensitiveRegex,
    };
  }

  String _searchScopeLabel(_TerminalSearchScope scope) {
    return switch (scope) {
      _TerminalSearchScope.activePane => context.l10n.activePane,
      _TerminalSearchScope.currentTab => context.l10n.currentTab,
      _TerminalSearchScope.allTabs => context.l10n.allTabs,
    };
  }

  String _searchScopeShortLabel(_TerminalSearchScope scope) {
    return switch (scope) {
      _TerminalSearchScope.activePane => context.l10n.paneShort,
      _TerminalSearchScope.currentTab => context.l10n.tabShort,
      _TerminalSearchScope.allTabs => context.l10n.all,
    };
  }

  Widget _searchModeMark(terminal.TerminalSearchMode mode) {
    final palette = widget.palette;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: palette.textPrimary,
      fontWeight: FontWeight.w700,
      height: 1,
    );
    return switch (mode) {
      terminal.TerminalSearchMode.smartCaseSubstring => Icon(
        Icons.manage_search_rounded,
        size: 15,
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
      message: context.l10n.searchFilterValue(
        _searchModeLabel(widget.searchMode),
      ),
      child: Semantics(
        button: true,
        label: context.l10n.searchFilter,
        value: _searchModeLabel(widget.searchMode),
        expanded: controller.isOpen,
        child: InkWell(
          key: const Key('terminal-search-mode'),
          focusNode: _modeFocusNode,
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
              color: controller.isOpen ? palette.selected : Colors.transparent,
              borderRadius: BorderRadius.circular(palette.radius.sm),
            ),
            child: SizedBox(
              width: 18 * math.max(1, _textScale) + 14,
              height: _searchBarControlHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18 * math.max(1, _textScale),
                    child: Center(child: _searchModeMark(widget.searchMode)),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 14,
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
    const modes = terminal.TerminalSearchMode.values;

    Widget item(terminal.TerminalSearchMode mode) {
      final selected = mode == widget.searchMode;
      return MenuItemButton(
        key: Key('terminal-search-mode-${mode.wireName}'),
        onPressed: () {
          widget.onModeChanged(mode);
        },
        style: _searchMenuItemStyle(selected: selected),
        leadingIcon: selected
            ? Icon(Icons.check_rounded, size: 16, color: palette.textPrimary)
            : const SizedBox(width: 16, height: 16),
        child: Semantics(
          selected: selected,
          child: Text(_searchModeLabel(mode), style: _searchMenuTextStyle),
        ),
      );
    }

    return [
      _searchMenuHeading(context.l10n.filter),
      item(modes[0]),
      item(modes[1]),
      item(modes[2]),
      _searchMenuDivider(),
      item(modes[3]),
      item(modes[4]),
    ];
  }

  Widget _buildSearchModeMenu(BuildContext context) {
    return MenuAnchor(
      childFocusNode: _modeFocusNode,
      alignmentOffset: const Offset(0, _SearchMetrics.gap),
      style: _searchMenuStyle(),
      menuChildren: _buildSearchModeMenuChildren(context),
      builder: (context, controller, child) {
        return _buildSearchModeButton(context, controller);
      },
    );
  }

  MenuStyle _searchMenuStyle() => MenuStyle(
    backgroundColor: WidgetStatePropertyAll(widget.palette.overlay),
    elevation: const WidgetStatePropertyAll(4),
    padding: const WidgetStatePropertyAll(EdgeInsets.all(_searchMenuInset)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(widget.palette.radius.md),
        side: BorderSide(color: widget.palette.border),
      ),
    ),
  );

  TextStyle get _searchMenuTextStyle => _controlTextStyle;

  ButtonStyle _searchMenuItemStyle({required bool selected}) => ButtonStyle(
    // Let the longest localized label determine width, as a native menu does.
    minimumSize: const WidgetStatePropertyAll(
      Size(0, _SearchMetrics.controlTarget),
    ),
    textStyle: WidgetStatePropertyAll(_controlTextStyle),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(
        horizontal: _SearchMetrics.gap,
        vertical: _SearchMetrics.menuVerticalPadding,
      ),
    ),
    backgroundColor: WidgetStatePropertyAll(
      selected ? widget.palette.selected : Colors.transparent,
    ),
    foregroundColor: WidgetStatePropertyAll(widget.palette.textPrimary),
    overlayColor: WidgetStatePropertyAll(
      widget.palette.accent.withValues(alpha: 0.12),
    ),
  );

  Widget _searchMenuHeading(String text) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: _SearchMetrics.gap,
      vertical: _SearchMetrics.inset,
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        fontSize: _SearchMetrics.secondarySize,
        height:
            _SearchMetrics.secondaryLineHeight / _SearchMetrics.secondarySize,
        color: widget.palette.textMuted,
        fontWeight: FontWeight.w400,
      ),
    ),
  );

  Widget _searchMenuDivider() =>
      Divider(height: 9, indent: 8, endIndent: 8, color: widget.palette.border);

  IconData _searchScopeIcon(_TerminalSearchScope scope) {
    return switch (scope) {
      _TerminalSearchScope.activePane => Icons.splitscreen_rounded,
      _TerminalSearchScope.currentTab => Icons.tab_rounded,
      _TerminalSearchScope.allTabs => Icons.grid_view_rounded,
    };
  }

  Widget _buildSearchScopeButton(
    BuildContext context,
    MenuController controller,
  ) {
    final palette = widget.palette;
    return Tooltip(
      message: context.l10n.searchScopeValue(
        _searchScopeLabel(widget.searchScope),
      ),
      child: Semantics(
        button: true,
        label: context.l10n.searchScopeValue(
          _searchScopeLabel(widget.searchScope),
        ),
        expanded: controller.isOpen,
        child: InkWell(
          key: const Key('terminal-search-scope'),
          focusNode: _scopeFocusNode,
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
              color: palette.selected.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(palette.radius.sm),
              border: Border.all(color: palette.border.withValues(alpha: 0.7)),
            ),
            child: SizedBox(
              width: 48 + 24 * (math.max(1, _textScale) - 1),
              height: _searchBarControlHeight,
              child: Center(
                child: Text(
                  _searchScopeShortLabel(widget.searchScope),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _controlTextStyle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSearchScopeMenuChildren(BuildContext context) {
    final palette = widget.palette;

    Widget item(_TerminalSearchScope scope) {
      final selected = scope == widget.searchScope;
      return MenuItemButton(
        key: Key('terminal-search-scope-${scope.wireName}'),
        onPressed: () {
          widget.onScopeChanged(scope);
        },
        style: _searchMenuItemStyle(selected: selected),
        leadingIcon: Icon(
          selected ? Icons.check_rounded : _searchScopeIcon(scope),
          size: 16,
          color: palette.textPrimary,
        ),
        child: Semantics(
          selected: selected,
          child: Text(_searchScopeLabel(scope), style: _searchMenuTextStyle),
        ),
      );
    }

    return [
      _searchMenuHeading(context.l10n.scope),
      for (final scope in _TerminalSearchScope.values) item(scope),
    ];
  }

  Widget _buildSearchScopeMenu(BuildContext context) {
    return MenuAnchor(
      childFocusNode: _scopeFocusNode,
      alignmentOffset: const Offset(0, _SearchMetrics.gap),
      style: _searchMenuStyle(),
      menuChildren: _buildSearchScopeMenuChildren(context),
      builder: (context, controller, child) {
        return _buildSearchScopeButton(context, controller);
      },
    );
  }

  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final usesMetaPaste = switch (defaultTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.iOS => true,
      _ => false,
    };
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
    if (event.logicalKey == LogicalKeyboardKey.keyV &&
        (usesMetaPaste ? isMetaPressed : isControlPressed)) {
      unawaited(_pasteClipboardIntoQuery());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildInlineSearchClearButton() {
    return _buildCompactActionButton(
      key: const Key('terminal-search-clear'),
      tooltip: context.l10n.clearSearchText,
      onPressed: widget.onClear,
      splashRadius: 12,
      iconSize: 15,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: _SearchMetrics.controlTarget,
        height: _SearchMetrics.controlTarget,
      ),
      icon: Icon(Icons.cancel_rounded, color: widget.palette.textSubtle),
    );
  }

  Widget _buildInlineSearchStatus(
    BuildContext context, {
    bool belowBar = false,
  }) {
    if (_counterText.isEmpty) {
      return const SizedBox.shrink();
    }
    final foreground = _statusForeground(context);
    if (widget.errorText != null) {
      return Semantics(
        liveRegion: true,
        label: _localizedErrorText,
        child: Tooltip(
          message: _localizedErrorText,
          child: Padding(
            key: const Key('terminal-search-status'),
            padding: const EdgeInsets.symmetric(
              horizontal: _SearchMetrics.inset,
            ),
            child: Icon(
              Icons.error_outline_rounded,
              size: 16,
              color: foreground,
            ),
          ),
        ),
      );
    }
    return Semantics(
      liveRegion: true,
      label: context.l10n.searchResultValue(_counterText),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: belowBar ? _preferredBarWidth : 68,
        ),
        child: Padding(
          key: const Key('terminal-search-status'),
          padding: const EdgeInsets.symmetric(horizontal: _SearchMetrics.inset),
          child: Text(
            _counterText,
            maxLines: belowBar ? null : 1,
            overflow: belowBar ? TextOverflow.visible : TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: foreground.withValues(alpha: 0.92),
              fontWeight: FontWeight.w400,
              height: 15 / 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context, {bool compact = false}) {
    final palette = widget.palette;
    final inputTextStyle = _controlTextStyle;
    final hintTextStyle = _controlTextStyle.copyWith(color: palette.textSubtle);
    return AnimatedBuilder(
      animation: widget.focusNode,
      builder: (context, _) {
        return SizedBox(
          key: const Key('terminal-search-input'),
          height: _searchBarControlHeight,
          child: Padding(
            padding: EdgeInsets.zero,
            child: Row(
              children: [
                _buildSearchModeMenu(context),
                const SizedBox(width: _SearchMetrics.inset),
                _buildSearchScopeMenu(context),
                const SizedBox(width: _SearchMetrics.gap),
                Expanded(
                  child: Focus(
                    onKeyEvent: _handleSearchKeyEvent,
                    child: Semantics(
                      label: context.l10n.searchTerminalOutput,
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
                                hintText: context.l10n.search,
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
                if (_counterText.isNotEmpty &&
                    !_separateStatus &&
                    (!compact || widget.errorText != null))
                  _buildInlineSearchStatus(context),
                if (widget.query.isNotEmpty)
                  const SizedBox(width: _SearchMetrics.inset),
                if (widget.query.isNotEmpty) _buildInlineSearchClearButton(),
              ],
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
        tooltip: context.l10n.previousMatch,
        onPressed: widget.matches == 0 ? null : widget.onPrevious,
        splashRadius: 13,
        iconSize: 18,
        padding: EdgeInsets.zero,
        constraints: constraints,
        icon: Icon(
          Icons.chevron_left_rounded,
          color: widget.matches == 0
              ? widget.palette.textSubtle.withValues(alpha: 0.45)
              : null,
        ),
      ),
      _buildCompactActionButton(
        key: const Key('terminal-search-next'),
        tooltip: context.l10n.nextMatch,
        onPressed: widget.matches == 0 ? null : widget.onNext,
        splashRadius: 13,
        iconSize: 18,
        padding: EdgeInsets.zero,
        constraints: constraints,
        icon: Icon(
          Icons.chevron_right_rounded,
          color: widget.matches == 0
              ? widget.palette.textSubtle.withValues(alpha: 0.45)
              : null,
        ),
      ),
    ];
  }

  Widget _buildSearchCloseButton(BoxConstraints constraints) {
    return _buildCompactActionButton(
      key: const Key('terminal-search-close'),
      tooltip: context.l10n.closeSearch,
      onPressed: widget.onClose,
      splashRadius: 13,
      iconSize: 17,
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
        const SizedBox(width: _SearchMetrics.gap),
        _searchToolbarDivider(context),
        const SizedBox(width: _SearchMetrics.gap),
        ..._buildSearchNavigationButtons(actionButtonConstraints),
        const SizedBox(width: _SearchMetrics.inset),
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
        Expanded(child: _buildSearchField(context, compact: true)),
        const SizedBox(width: _SearchMetrics.gap),
        _searchToolbarDivider(context),
        const SizedBox(width: _SearchMetrics.gap),
        _buildSearchCloseButton(actionButtonConstraints),
      ],
    );
  }

  Widget _searchToolbarDivider(BuildContext context) {
    return SizedBox(
      width: 1,
      height: 18,
      child: ColoredBox(color: widget.palette.border.withValues(alpha: 0.72)),
    );
  }

  Widget _buildSearchPanel(BuildContext context, {required bool compact}) {
    final palette = widget.palette;
    final actionButtonConstraints = BoxConstraints.tightFor(
      width: _SearchMetrics.controlTarget,
      height: _searchBarControlHeight,
    );
    return AnimatedBuilder(
      animation: widget.focusNode,
      builder: (context, _) {
        final focused = widget.focusNode.hasFocus;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: palette.overlay.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(palette.radius.md),
            border: Border.all(
              color: widget.errorText != null
                  ? Theme.of(context).colorScheme.error.withValues(alpha: 0.55)
                  : focused
                  ? palette.focusRing.withValues(alpha: 0.88)
                  : palette.borderStrong.withValues(alpha: 0.68),
              width: focused ? 1.2 : 1,
            ),
            boxShadow: palette.elevation.floating,
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
      },
    );
  }

  Widget _buildMobileSearch(BuildContext context) => Material(
    key: const Key('terminal-search-bar'),
    color: widget.palette.panel,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('terminal-search-field'),
                  focusNode: widget.focusNode,
                  controller: _controller,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.search,
                  onChanged: widget.onChanged,
                  onSubmitted: (_) => widget.focusNode.unfocus(),
                  decoration: InputDecoration(
                    hintText: context.l10n.searchTerminalOutput,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: widget.query.isEmpty
                        ? null
                        : IconButton(
                            key: const Key('terminal-search-clear'),
                            tooltip: context.l10n.clearSearchText,
                            onPressed: widget.onClear,
                            icon: const Icon(Icons.cancel_outlined),
                          ),
                  ),
                ),
              ),
              IconButton(
                key: const Key('terminal-search-close'),
                tooltip: context.l10n.closeSearch,
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  _localizedErrorText ?? _counterText,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              PopupMenuButton<terminal.TerminalSearchMode>(
                key: const Key('mobile-terminal-search-options'),
                tooltip: context.l10n.mobileAdvanced,
                icon: const Icon(Icons.tune_rounded),
                onSelected: widget.onModeChanged,
                itemBuilder: (context) => [
                  for (final mode in terminal.TerminalSearchMode.values)
                    CheckedPopupMenuItem(
                      value: mode,
                      checked: mode == widget.searchMode,
                      child: Text(_searchModeLabel(mode)),
                    ),
                ],
              ),
              IconButton(
                key: const Key('terminal-search-previous'),
                tooltip: context.l10n.previousMatch,
                onPressed: widget.matches == 0 ? null : widget.onPrevious,
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
              IconButton(
                key: const Key('terminal-search-next'),
                tooltip: context.l10n.nextMatch,
                onPressed: widget.matches == 0 ? null : widget.onNext,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  double get _preferredBarWidth {
    if (widget.query.isEmpty && widget.errorText == null) {
      return _searchBarIdleWidth;
    }
    return _searchBarMaxWidth;
  }

  @override
  Widget build(BuildContext context) {
    if (context.usesMobileNavigation) return _buildMobileSearch(context);
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
              if (_counterText.isNotEmpty &&
                  (_separateStatus || compact) &&
                  widget.errorText == null)
                Padding(
                  padding: const EdgeInsets.only(
                    top: _SearchMetrics.inset,
                    right: _SearchMetrics.gap,
                  ),
                  child: _buildInlineSearchStatus(context, belowBar: true),
                ),
              if (widget.errorText != null)
                _TerminalSearchErrorPopover(
                  errorText: _localizedErrorText!,
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
                      fontWeight: FontWeight.w600,
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
