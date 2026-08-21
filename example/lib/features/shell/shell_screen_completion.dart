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
                        prefix.isEmpty
                            ? context.l10n.completions
                            : context.l10n.completePrefix(prefix),
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _buildCompactActionButton(
                      key: const Key('terminal-autocomplete-previous'),
                      tooltip: context.l10n.previousCompletion,
                      onPressed: suggestions.length < 2 ? null : onPrevious,
                      splashRadius: 14,
                      iconSize: 16,
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                    _buildCompactActionButton(
                      key: const Key('terminal-autocomplete-next'),
                      tooltip: context.l10n.nextCompletion,
                      onPressed: suggestions.length < 2 ? null : onNext,
                      splashRadius: 14,
                      iconSize: 16,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    _buildCompactActionButton(
                      key: const Key('terminal-autocomplete-close'),
                      tooltip: context.l10n.closeCompletions,
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
    required this.suggestions,
    required this.activeIndex,
    required this.palette,
    required this.onChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onAcceptSuggestion,
    required this.onSend,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> suggestions;
  final int activeIndex;
  final AppThemeTokens palette;
  final ValueChanged<String> onChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<String> onAcceptSuggestion;
  final VoidCallback onSend;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final canSend = controller.text.trimRight().isNotEmpty;
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
              border: Border.all(color: palette.accent.withValues(alpha: 0.34)),
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
                      Icon(
                        Icons.edit_note_rounded,
                        size: 18,
                        color: palette.accent,
                      ),
                      const SizedBox(width: 8),
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
                            hintText: context.l10n.composeCommand,
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
                        tooltip: context.l10n.previousCompletion,
                        onPressed: suggestions.length < 2 ? null : onPrevious,
                        splashRadius: 16,
                        iconSize: 18,
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      ),
                      _buildCompactActionButton(
                        key: const Key('terminal-auto-composer-next'),
                        tooltip: context.l10n.nextCompletion,
                        onPressed: suggestions.length < 2 ? null : onNext,
                        splashRadius: 16,
                        iconSize: 18,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                      _buildCompactActionButton(
                        key: const Key('terminal-auto-composer-send'),
                        tooltip: context.l10n.sendCommand,
                        onPressed: canSend ? onSend : null,
                        splashRadius: 16,
                        iconSize: 18,
                        icon: const Icon(Icons.send_rounded),
                      ),
                      _buildCompactActionButton(
                        key: const Key('terminal-auto-composer-close'),
                        tooltip: context.l10n.closeComposer,
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
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
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
                              ? FontWeight.w600
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
