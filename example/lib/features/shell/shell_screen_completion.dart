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

class _TerminalAutoComposer extends StatelessWidget {
  const _TerminalAutoComposer({
    required this.controller,
    required this.focusNode,
    required this.inputMode,
    required this.classification,
    required this.contextChips,
    required this.contextOptions,
    required this.suggestions,
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
  final List<_UniversalInputToolOption> contextOptions;
  final List<String> suggestions;
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
  Widget build(BuildContext context) {
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
                    children: [
                      Icon(
                        _universalInputLeadingIcon(classification),
                        size: 18,
                        color: accent,
                      ),
                      const SizedBox(width: 6),
                      _UniversalInputToolMenuButton(
                        key: const Key('terminal-auto-composer-context'),
                        tooltip: 'Add context',
                        icon: Icons.alternate_email_rounded,
                        options: contextOptions,
                        palette: palette,
                        onSelected: onContextSelected,
                      ),
                      _UniversalInputToolMenuButton(
                        key: const Key('terminal-auto-composer-slash'),
                        tooltip: 'Slash commands',
                        icon: Icons.bolt_rounded,
                        options: _universalInputSlashCommandOptions,
                        palette: palette,
                        onSelected: onSlashCommandSelected,
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
                        child: TextField(
                          key: const Key('terminal-auto-composer-field'),
                          controller: controller,
                          focusNode: focusNode,
                          minLines: 1,
                          maxLines: 3,
                          textInputAction: TextInputAction.send,
                          style: Theme.of(context).textTheme.bodyMedium
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
                          onSubmitted: (_) {
                            if (controller.text.trimRight().isNotEmpty) {
                              onSend();
                            }
                          },
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
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    const Divider(height: 1),
                    const SizedBox(height: 4),
                    for (
                      var index = 0;
                      index < suggestions.length && index < 5;
                      index++
                    )
                      _AutoComposerSuggestionTile(
                        suggestion: suggestions[index],
                        active: index == activeIndex,
                        palette: palette,
                        onTap: () => onAcceptSuggestion(suggestions[index]),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
    required this.tooltip,
    required this.icon,
    required this.options,
    required this.palette,
    required this.onSelected,
  });

  final String tooltip;
  final IconData icon;
  final List<_UniversalInputToolOption> options;
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
  });

  final UniversalInputMode mode;
  final AppThemeTokens palette;
  final ValueChanged<UniversalInputMode> onModeChanged;

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
            key: const Key('terminal-auto-composer-mode-terminal'),
            mode: UniversalInputMode.terminal,
            currentMode: mode,
            icon: Icons.terminal_rounded,
            tooltip: 'Terminal mode',
            palette: palette,
            onModeChanged: onModeChanged,
          ),
          _UniversalInputModeButton(
            key: const Key('terminal-auto-composer-mode-auto'),
            mode: UniversalInputMode.auto,
            currentMode: mode,
            icon: Icons.auto_mode_rounded,
            tooltip: 'Auto mode',
            palette: palette,
            onModeChanged: onModeChanged,
          ),
          _UniversalInputModeButton(
            key: const Key('terminal-auto-composer-mode-agent'),
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
      key: Key('terminal-auto-composer-suggestion-$suggestion'),
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
            child: SizedBox(
              height: 30,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
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
                      child: Text(
                        suggestion,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: active
                              ? palette.textPrimary
                              : palette.textSubtle,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
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
