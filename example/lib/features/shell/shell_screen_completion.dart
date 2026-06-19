part of 'shell_screen.dart';

class _TerminalAutocompleteMenu extends StatelessWidget {
  const _TerminalAutocompleteMenu({
    required this.prefix,
    required this.suggestions,
    required this.activeIndex,
    required this.palette,
    required this.onPrevious,
    required this.onNext,
    required this.onAccept,
    required this.onClose,
  });

  final String prefix;
  final List<String> suggestions;
  final int activeIndex;
  final AppThemeTokens palette;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<String> onAccept;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('terminal-autocomplete-menu'),
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.overlay.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(palette.radius.md),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 4, 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_fix_high_rounded,
                      size: 15,
                      color: palette.accent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        prefix.isEmpty ? 'Completions' : 'Complete "$prefix"',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _buildCompactActionButton(
                      key: const Key('terminal-autocomplete-previous'),
                      tooltip: 'Previous completion',
                      onPressed: suggestions.length < 2 ? null : onPrevious,
                      splashRadius: 14,
                      iconSize: 16,
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                    _buildCompactActionButton(
                      key: const Key('terminal-autocomplete-next'),
                      tooltip: 'Next completion',
                      onPressed: suggestions.length < 2 ? null : onNext,
                      splashRadius: 14,
                      iconSize: 16,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    _buildCompactActionButton(
                      key: const Key('terminal-autocomplete-close'),
                      tooltip: 'Close completions',
                      onPressed: onClose,
                      splashRadius: 14,
                      iconSize: 16,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (var index = 0; index < suggestions.length; index++)
                _AutocompleteSuggestionTile(
                  suggestion: suggestions[index],
                  active: index == activeIndex,
                  palette: palette,
                  onTap: () => onAccept(suggestions[index]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalAutoComposer extends StatefulWidget {
  const _TerminalAutoComposer({
    required this.controller,
    required this.focusNode,
    required this.inputMode,
    required this.classification,
    required this.contextChips,
    required this.contextOptions,
    required this.suggestions,
    this.suggestionDetails = const <String, CommandDraft>{},
    this.suggestionsLoading = false,
    required this.activeIndex,
    required this.modelLabel,
    required this.palette,
    required this.onModeChanged,
    required this.onChanged,
    required this.onContextSelected,
    required this.onSlashCommandSelected,
    required this.onModelSelected,
    required this.onPrevious,
    required this.onNext,
    required this.onAcceptSuggestion,
    required this.onSend,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final UniversalInputMode inputMode;
  final UniversalInputClassification classification;
  final List<String> contextChips;
  final List<UniversalInputToolOption> contextOptions;
  final List<String> suggestions;
  final Map<String, CommandDraft> suggestionDetails;
  final bool suggestionsLoading;
  final int activeIndex;
  final String modelLabel;
  final AppThemeTokens palette;
  final ValueChanged<UniversalInputMode> onModeChanged;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onContextSelected;
  final ValueChanged<String> onSlashCommandSelected;
  final ValueChanged<String> onModelSelected;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<String> onAcceptSuggestion;
  final VoidCallback onSend;
  final VoidCallback onClose;

  @override
  State<_TerminalAutoComposer> createState() => _TerminalAutoComposerState();
}

class _TerminalAutoComposerState extends State<_TerminalAutoComposer> {
  final GlobalKey<PopupMenuButtonState<String>> _contextMenuKey =
      GlobalKey<PopupMenuButtonState<String>>();
  final GlobalKey<PopupMenuButtonState<String>> _slashMenuKey =
      GlobalKey<PopupMenuButtonState<String>>();

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final focusNode = widget.focusNode;
    final inputMode = widget.inputMode;
    final classification = widget.classification;
    final contextChips = widget.contextChips;
    final contextOptions = widget.contextOptions;
    final suggestions = widget.suggestions;
    final suggestionDetails = widget.suggestionDetails;
    final suggestionsLoading = widget.suggestionsLoading;
    final activeIndex = widget.activeIndex;
    final modelLabel = widget.modelLabel;
    final palette = widget.palette;
    final onModeChanged = widget.onModeChanged;
    final onChanged = widget.onChanged;
    final onModelSelected = widget.onModelSelected;
    final onPrevious = widget.onPrevious;
    final onNext = widget.onNext;
    final onAcceptSuggestion = widget.onAcceptSuggestion;
    final onSend = widget.onSend;
    final onClose = widget.onClose;
    final canSend = controller.text.trimRight().isNotEmpty;
    final accent = _universalInputAccentColor(palette, classification);
    final statusLabel = _universalInputStatusLabel(inputMode, classification);
    return Material(
      key: const Key('terminal-auto-composer'),
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.overlay.withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(palette.radius.lg),
              border: Border.all(color: accent.withValues(alpha: 0.42)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _UniversalInputModeSwitcher(
                        mode: inputMode,
                        palette: palette,
                        onModeChanged: onModeChanged,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _UniversalInputStatusPill(
                          key: const Key(
                            'terminal-auto-composer-detection-label',
                          ),
                          label: statusLabel,
                          accent: accent,
                          palette: palette,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _UniversalInputModelBadge(
                        label: modelLabel,
                        palette: palette,
                      ),
                    ],
                  ),
                  if (contextChips.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final chip in contextChips) ...[
                              _UniversalInputContextChip(
                                label: chip,
                                palette: palette,
                              ),
                              const SizedBox(width: 5),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Icon(
                          _universalInputLeadingIcon(classification),
                          size: 18,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _UniversalInputToolMenuButton(
                        key: const Key('terminal-auto-composer-context'),
                        menuButtonKey: _contextMenuKey,
                        tooltip: 'Add context',
                        icon: Icons.alternate_email_rounded,
                        options: contextOptions,
                        palette: palette,
                        onSelected: _handleContextSelected,
                      ),
                      _UniversalInputToolMenuButton(
                        key: const Key('terminal-auto-composer-slash'),
                        menuButtonKey: _slashMenuKey,
                        tooltip: 'Slash commands',
                        icon: Icons.bolt_rounded,
                        options: _universalInputSlashCommandOptions,
                        palette: palette,
                        onSelected: _handleSlashCommandSelected,
                      ),
                      _UniversalInputToolMenuButton(
                        key: const Key('terminal-auto-composer-model'),
                        tooltip: 'Model picker',
                        icon: Icons.tune_rounded,
                        options: _universalInputModelOptions,
                        palette: palette,
                        onSelected: onModelSelected,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _UniversalInputAutocompleteField(
                          fieldKey: const Key('terminal-auto-composer-field'),
                          controller: controller,
                          focusNode: focusNode,
                          hintText: _universalInputFieldHint(
                            inputMode,
                            classification,
                          ),
                          suggestions: suggestions,
                          suggestionDetails: suggestionDetails,
                          suggestionsLoading: suggestionsLoading,
                          activeIndex: activeIndex,
                          palette: palette,
                          textStyle: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                          decoration: InputDecoration(
                            hintText: _universalInputFieldHint(
                              inputMode,
                              classification,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: onChanged,
                          onPrevious: onPrevious,
                          onNext: onNext,
                          onAcceptSuggestion: onAcceptSuggestion,
                          onSend: onSend,
                          onContextTrigger: () =>
                              _contextMenuKey.currentState?.showButtonMenu(),
                          onSlashTrigger: () =>
                              _slashMenuKey.currentState?.showButtonMenu(),
                        ),
                      ),
                      _buildCompactActionButton(
                        key: const Key('terminal-auto-composer-previous'),
                        tooltip: 'Previous completion',
                        onPressed: suggestions.length < 2 ? null : onPrevious,
                        splashRadius: 16,
                        iconSize: 18,
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      ),
                      _buildCompactActionButton(
                        key: const Key('terminal-auto-composer-next'),
                        tooltip: 'Next completion',
                        onPressed: suggestions.length < 2 ? null : onNext,
                        splashRadius: 16,
                        iconSize: 18,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                      _buildCompactActionButton(
                        key: const Key('terminal-auto-composer-send'),
                        tooltip: _universalInputSendTooltip(classification),
                        onPressed: canSend ? onSend : null,
                        splashRadius: 16,
                        iconSize: 18,
                        icon: Icon(
                          classification.isNaturalLanguage
                              ? Icons.auto_fix_high_rounded
                              : Icons.send_rounded,
                        ),
                      ),
                      _buildCompactActionButton(
                        key: const Key('terminal-auto-composer-close'),
                        tooltip: 'Close composer',
                        onPressed: onClose,
                        splashRadius: 16,
                        iconSize: 18,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleContextSelected(String value) {
    if (_removeInlineTrigger('@')) {
      widget.onChanged(widget.controller.text);
    }
    widget.onContextSelected(value);
  }

  void _handleSlashCommandSelected(String value) {
    if (_removeInlineTrigger('/')) {
      widget.onChanged(widget.controller.text);
    }
    widget.onSlashCommandSelected(value);
  }

  bool _removeInlineTrigger(String trigger) {
    return _removeUniversalInputInlineTrigger(widget.controller, trigger);
  }
}

class _UniversalInputAutocompleteField extends StatelessWidget {
  const _UniversalInputAutocompleteField({
    required this.fieldKey,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.suggestions,
    this.suggestionDetails = const <String, CommandDraft>{},
    this.suggestionsLoading = false,
    required this.activeIndex,
    required this.palette,
    required this.onChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onAcceptSuggestion,
    required this.onSend,
    required this.onContextTrigger,
    required this.onSlashTrigger,
    this.onAcceptCorrection,
    this.onDismissCorrection,
    this.enabled = true,
    this.autofocus = false,
    this.semanticLabel,
    this.textStyle,
    this.decoration,
    this.maxLines = 8,
    this.maxHeight,
    this.suggestionLimit = 5,
    this.suggestionKeyPrefix = 'terminal-auto-composer',
  });

  final Key fieldKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final List<String> suggestions;
  final Map<String, CommandDraft> suggestionDetails;
  final bool suggestionsLoading;
  final int activeIndex;
  final AppThemeTokens palette;
  final ValueChanged<String> onChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<String> onAcceptSuggestion;
  final VoidCallback onSend;
  final VoidCallback onContextTrigger;
  final VoidCallback onSlashTrigger;
  final VoidCallback? onAcceptCorrection;
  final VoidCallback? onDismissCorrection;
  final bool enabled;
  final bool autofocus;
  final String? semanticLabel;
  final TextStyle? textStyle;
  final InputDecoration? decoration;
  final int? maxLines;
  final double? maxHeight;
  final int suggestionLimit;
  final String suggestionKeyPrefix;

  @override
  Widget build(BuildContext context) {
    final effectiveActiveIndex = suggestions.isEmpty
        ? -1
        : activeIndex.clamp(0, suggestions.length - 1);
    final field = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleKeyEvent,
      child: TextField(
        key: fieldKey,
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        autofocus: autofocus,
        minLines: 1,
        maxLines: maxLines,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        style: textStyle,
        decoration:
            decoration ??
            InputDecoration(
              hintText: hintText,
              border: InputBorder.none,
              isDense: true,
            ),
        onChanged: _handleChanged,
      ),
    );
    final semanticField = semanticLabel == null
        ? field
        : Semantics(
            container: true,
            enabled: enabled,
            label: semanticLabel,
            textField: true,
            child: field,
          );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (maxHeight == null)
          semanticField
        else
          Flexible(
            fit: FlexFit.loose,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight!),
              child: semanticField,
            ),
          ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          const Divider(height: 1),
          const SizedBox(height: 4),
          for (
            var index = 0;
            index < suggestions.length && index < suggestionLimit;
            index++
          )
            _AutoComposerSuggestionTile(
              suggestion: suggestions[index],
              draft: suggestionDetails[suggestions[index]],
              active: index == effectiveActiveIndex,
              palette: palette,
              keyPrefix: suggestionKeyPrefix,
              onTap: () => onAcceptSuggestion(suggestions[index]),
            ),
        ] else if (suggestionsLoading) ...[
          const SizedBox(height: 6),
          const Divider(height: 1),
          const SizedBox(height: 4),
          _UniversalInputLoadingSuggestionTile(palette: palette),
        ],
      ],
    );
    return content;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!enabled) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_hasActiveComposing) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final isEnter =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (isEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        if (event is! KeyRepeatEvent) {
          _insertTextAtSelection(controller, '\n');
          onChanged(controller.text);
        }
        return KeyEventResult.handled;
      }
      if (event is! KeyRepeatEvent && controller.text.trimRight().isNotEmpty) {
        onSend();
      }
      return KeyEventResult.handled;
    }
    if (suggestions.length > 1 && key == LogicalKeyboardKey.arrowUp) {
      onPrevious();
      return KeyEventResult.handled;
    }
    if (suggestions.length > 1 && key == LogicalKeyboardKey.arrowDown) {
      onNext();
      return KeyEventResult.handled;
    }
    if (suggestions.isNotEmpty && key == LogicalKeyboardKey.tab) {
      if (event is! KeyRepeatEvent) {
        final suggestionIndex = activeIndex.clamp(0, suggestions.length - 1);
        onAcceptSuggestion(suggestions[suggestionIndex]);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight &&
        onAcceptCorrection != null &&
        controller.text.trim().isEmpty) {
      if (event is! KeyRepeatEvent) {
        onAcceptCorrection!();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && onDismissCorrection != null) {
      if (event is! KeyRepeatEvent) {
        onDismissCorrection!();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool get _hasActiveComposing {
    final composing = controller.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  void _handleChanged(String text) {
    onChanged(text);
    final trigger = _universalInputInlineTriggerFor(text, controller.selection);
    switch (trigger) {
      case _UniversalInputInlineTrigger.context:
        onContextTrigger();
      case _UniversalInputInlineTrigger.slash:
        onSlashTrigger();
      case null:
        break;
    }
  }
}

class _UniversalInputStatusPill extends StatelessWidget {
  const _UniversalInputStatusPill({
    super.key,
    required this.label,
    required this.accent,
    required this.palette,
  });

  final String label;
  final Color accent;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(palette.radius.sm),
          border: Border.all(color: accent.withValues(alpha: 0.26)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _UniversalInputModelBadge extends StatelessWidget {
  const _UniversalInputModelBadge({required this.label, required this.palette});

  final String label;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.chrome.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(palette.radius.sm),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(
          label,
          key: const Key('terminal-auto-composer-model-label'),
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: palette.textSubtle,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _UniversalInputToolMenuButton extends StatelessWidget {
  const _UniversalInputToolMenuButton({
    super.key,
    this.menuButtonKey,
    required this.tooltip,
    required this.icon,
    required this.options,
    required this.palette,
    required this.onSelected,
  });

  final GlobalKey<PopupMenuButtonState<String>>? menuButtonKey;
  final String tooltip;
  final IconData icon;
  final List<UniversalInputToolOption> options;
  final AppThemeTokens palette;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: Semantics(
        button: true,
        excludeSemantics: true,
        label: tooltip,
        child: PopupMenuButton<String>(
          key: menuButtonKey,
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          splashRadius: 16,
          iconSize: 17,
          color: palette.overlay,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(palette.radius.md),
            side: BorderSide(color: palette.border),
          ),
          icon: Icon(icon, color: palette.textMuted),
          onSelected: onSelected,
          itemBuilder: (context) {
            return [
              for (final option in options)
                PopupMenuItem<String>(
                  value: option.value,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(option.icon, size: 18, color: palette.accent),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.label,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: palette.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            if (option.detail != null)
                              Text(
                                option.detail!,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: palette.textSubtle),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ];
          },
        ),
      ),
    );
  }
}

class _UniversalInputModeSwitcher extends StatelessWidget {
  const _UniversalInputModeSwitcher({
    required this.mode,
    required this.palette,
    required this.onModeChanged,
    this.keyPrefix = 'terminal-auto-composer',
  });

  final UniversalInputMode mode;
  final AppThemeTokens palette;
  final ValueChanged<UniversalInputMode> onModeChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.chrome.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(palette.radius.md),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _UniversalInputModeButton(
            key: Key('$keyPrefix-mode-terminal'),
            mode: UniversalInputMode.terminal,
            currentMode: mode,
            icon: Icons.terminal_rounded,
            tooltip: 'Terminal mode',
            palette: palette,
            onModeChanged: onModeChanged,
          ),
          _UniversalInputModeButton(
            key: Key('$keyPrefix-mode-auto'),
            mode: UniversalInputMode.auto,
            currentMode: mode,
            icon: Icons.auto_mode_rounded,
            tooltip: 'Auto mode',
            palette: palette,
            onModeChanged: onModeChanged,
          ),
          _UniversalInputModeButton(
            key: Key('$keyPrefix-mode-agent'),
            mode: UniversalInputMode.agent,
            currentMode: mode,
            icon: Icons.auto_awesome_rounded,
            tooltip: 'Agent mode',
            palette: palette,
            onModeChanged: onModeChanged,
          ),
        ],
      ),
    );
  }
}

class _UniversalInputModeButton extends StatelessWidget {
  const _UniversalInputModeButton({
    super.key,
    required this.mode,
    required this.currentMode,
    required this.icon,
    required this.tooltip,
    required this.palette,
    required this.onModeChanged,
  });

  final UniversalInputMode mode;
  final UniversalInputMode currentMode;
  final IconData icon;
  final String tooltip;
  final AppThemeTokens palette;
  final ValueChanged<UniversalInputMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final selected = mode == currentMode;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(palette.radius.sm),
          onTap: () => onModeChanged(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            width: 30,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? palette.selected.withValues(alpha: 0.85)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(palette.radius.sm),
            ),
            child: Icon(
              icon,
              size: 16,
              color: selected ? palette.accent : palette.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _UniversalInputContextChip extends StatelessWidget {
  const _UniversalInputContextChip({
    required this.label,
    required this.palette,
  });

  final String label;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.chrome.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(palette.radius.sm),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: palette.textSubtle,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

Color _universalInputAccentColor(
  AppThemeTokens palette,
  UniversalInputClassification classification,
) {
  return switch (classification.kind) {
    UniversalInputKind.naturalLanguage => palette.accent,
    UniversalInputKind.command => palette.success,
    UniversalInputKind.empty => palette.textMuted,
  };
}

IconData _universalInputLeadingIcon(
  UniversalInputClassification classification,
) {
  return switch (classification.kind) {
    UniversalInputKind.naturalLanguage => Icons.auto_awesome_rounded,
    UniversalInputKind.command => Icons.terminal_rounded,
    UniversalInputKind.empty => Icons.edit_note_rounded,
  };
}

String _universalInputStatusLabel(
  UniversalInputMode mode,
  UniversalInputClassification classification,
) {
  if (classification.kind == UniversalInputKind.empty) {
    return switch (mode) {
      UniversalInputMode.auto => 'Auto-detect ready',
      UniversalInputMode.terminal => 'Terminal mode',
      UniversalInputMode.agent => 'Agent mode',
    };
  }
  if (mode == UniversalInputMode.auto) {
    return classification.isNaturalLanguage
        ? 'Auto detected natural language'
        : 'Auto detected command';
  }
  return classification.isNaturalLanguage
      ? 'Agent natural language'
      : 'Terminal command';
}

String _universalInputFieldHint(
  UniversalInputMode mode,
  UniversalInputClassification classification,
) {
  if (classification.isNaturalLanguage) {
    return 'Ask in natural language';
  }
  if (classification.isCommand) {
    return 'Type a shell command';
  }
  return switch (mode) {
    UniversalInputMode.auto => 'Ask or type a command',
    UniversalInputMode.terminal => 'Type a shell command',
    UniversalInputMode.agent => 'Ask in natural language',
  };
}

String _universalInputSendTooltip(UniversalInputClassification classification) {
  return classification.isNaturalLanguage ? 'Suggest command' : 'Send command';
}

enum _UniversalInputInlineTrigger { context, slash }

_UniversalInputInlineTrigger? _universalInputInlineTriggerFor(
  String text,
  TextSelection selection,
) {
  if (!selection.isValid || !selection.isCollapsed) {
    return null;
  }
  final tokenRange = _universalInputCurrentTokenRange(
    text,
    selection.baseOffset,
  );
  if (tokenRange == null) {
    return null;
  }
  final token = text.substring(tokenRange.start, tokenRange.end);
  return switch (token) {
    '@' => _UniversalInputInlineTrigger.context,
    '/' => _UniversalInputInlineTrigger.slash,
    _ => null,
  };
}

TextRange? _universalInputCurrentTokenRange(String text, int cursor) {
  if (text.isEmpty) {
    return null;
  }
  final safeCursor = cursor.clamp(0, text.length).toInt();
  var start = safeCursor;
  while (start > 0 && !_universalInputTokenBoundary(text[start - 1])) {
    start -= 1;
  }
  var end = safeCursor;
  while (end < text.length && !_universalInputTokenBoundary(text[end])) {
    end += 1;
  }
  if (start == end) {
    return null;
  }
  return TextRange(start: start, end: end);
}

bool _universalInputTokenBoundary(String character) {
  return character.trim().isEmpty;
}

bool _removeUniversalInputInlineTrigger(
  TextEditingController controller,
  String trigger,
) {
  final selection = controller.selection;
  if (!selection.isValid || !selection.isCollapsed) {
    return false;
  }
  final tokenRange = _universalInputCurrentTokenRange(
    controller.text,
    selection.baseOffset,
  );
  if (tokenRange == null) {
    return false;
  }
  final token = controller.text.substring(tokenRange.start, tokenRange.end);
  if (token != trigger) {
    return false;
  }
  final nextText = controller.text.replaceRange(
    tokenRange.start,
    tokenRange.end,
    '',
  );
  controller.value = TextEditingValue(
    text: nextText,
    selection: TextSelection.collapsed(offset: tokenRange.start),
    composing: TextRange.empty,
  );
  return true;
}

void _insertTextAtSelection(
  TextEditingController controller,
  String insertedText,
) {
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
  final nextText = currentText.replaceRange(
    replaceStart,
    replaceEnd,
    insertedText,
  );
  final nextOffset = replaceStart + insertedText.length;
  controller.value = current.copyWith(
    text: nextText,
    selection: TextSelection.collapsed(offset: nextOffset),
    composing: TextRange.empty,
  );
}

class _AutocompleteSuggestionTile extends StatelessWidget {
  const _AutocompleteSuggestionTile({
    required this.suggestion,
    required this.active,
    required this.palette,
    required this.onTap,
  });

  final String suggestion;
  final bool active;
  final AppThemeTokens palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: Key('terminal-autocomplete-suggestion-$suggestion'),
      label: suggestion,
      button: true,
      selected: active,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: ColoredBox(
            color: active
                ? palette.accent.withValues(alpha: 0.14)
                : Colors.transparent,
            child: SizedBox(
              height: 30,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    suggestion,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: active ? palette.textPrimary : palette.textSubtle,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AutoComposerSuggestionTile extends StatelessWidget {
  const _AutoComposerSuggestionTile({
    required this.suggestion,
    this.draft,
    required this.active,
    required this.palette,
    required this.onTap,
    this.keyPrefix = 'terminal-auto-composer',
  });

  final String suggestion;
  final CommandDraft? draft;
  final bool active;
  final AppThemeTokens palette;
  final VoidCallback onTap;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: Key('$keyPrefix-suggestion-$suggestion'),
      label: suggestion,
      button: true,
      selected: active,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(palette.radius.sm),
          child: ColoredBox(
            color: active
                ? palette.accent.withValues(alpha: 0.14)
                : Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: draft == null ? 30 : 46),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  children: [
                    Icon(
                      active
                          ? Icons.keyboard_return_rounded
                          : Icons.subdirectory_arrow_right_rounded,
                      size: 15,
                      color: active ? palette.accent : palette.textSubtle,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            suggestion,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: active
                                      ? palette.textPrimary
                                      : palette.textSubtle,
                                  fontWeight: active
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  fontFamily: 'monospace',
                                ),
                          ),
                          if (draft != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              '${draft!.source.label} · ${draft!.riskLevel.label} · ${draft!.reason}',
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: palette.textMuted),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UniversalInputLoadingSuggestionTile extends StatelessWidget {
  const _UniversalInputLoadingSuggestionTile({required this.palette});

  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('universal-input-suggestions-loading'),
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Center(
              child: SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Generating command suggestion...',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: palette.textSubtle,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
