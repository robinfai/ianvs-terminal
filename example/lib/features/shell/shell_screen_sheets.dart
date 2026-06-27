part of 'shell_screen.dart';

class _AdvancedPasteSheet extends StatefulWidget {
  const _AdvancedPasteSheet({required this.initialText});

  final String initialText;

  @override
  State<_AdvancedPasteSheet> createState() => _AdvancedPasteSheetState();
}

class _AdvancedPasteSheetState extends State<_AdvancedPasteSheet> {
  late final TextEditingController _textController;
  bool _escapeSpecialCharacters = false;
  bool _base64Encode = false;
  bool _appendNewline = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
    _textController.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_handleTextChanged);
    _textController.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    setState(() {});
  }

  String get _transformedText {
    return transformAdvancedPasteText(
      _textController.text,
      escapeSpecialCharacters: _escapeSpecialCharacters,
      base64Encode: _base64Encode,
      appendNewline: _appendNewline,
    );
  }

  int get _transformedByteCount {
    return utf8.encode(_transformedText).length;
  }

  void _send() {
    final text = _transformedText;
    if (text.isEmpty) {
      return;
    }
    Navigator.of(context).pop(_AdvancedPasteSendResult(text));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final transformedText = _transformedText;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        key: const Key('advanced-paste-sheet'),
        color: palette.overlay,
        borderRadius: BorderRadius.circular(palette.radius.xl),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Advanced Paste',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      AppActionButton(
                        tooltip: 'Close advanced paste',
                        tone: AppActionTone.ghost,
                        size: AppActionSize.dense,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icons.close_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  MergeSemantics(
                    child: Semantics(
                      label: 'Paste text',
                      textField: true,
                      child: TextField(
                        key: const Key('advanced-paste-text-field'),
                        controller: _textController,
                        minLines: 4,
                        maxLines: 8,
                        keyboardType: TextInputType.multiline,
                        decoration: const InputDecoration(
                          labelText: 'Text',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ShellSwitchTile(
                    tileKey: const Key('advanced-paste-escape'),
                    title: 'Escape special characters',
                    value: _escapeSpecialCharacters,
                    onChanged: (value) {
                      setState(() {
                        _escapeSpecialCharacters = value;
                      });
                    },
                  ),
                  _ShellSwitchTile(
                    tileKey: const Key('advanced-paste-base64'),
                    title: 'Base64 encode',
                    value: _base64Encode,
                    onChanged: (value) {
                      setState(() {
                        _base64Encode = value;
                      });
                    },
                  ),
                  _ShellSwitchTile(
                    tileKey: const Key('advanced-paste-newline'),
                    title: 'Append newline',
                    value: _appendNewline,
                    onChanged: (value) {
                      setState(() {
                        _appendNewline = value;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$_transformedByteCount byte${_transformedByteCount == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: palette.textSubtle,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      FilledButton.icon(
                        key: const Key('advanced-paste-send'),
                        onPressed: transformedText.isEmpty ? null : _send,
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: const Text('Paste'),
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
}

class _CapturedOutputSheet extends StatefulWidget {
  const _CapturedOutputSheet({
    required this.entries,
    required this.onClear,
    required this.onCopy,
  });

  final List<_CapturedOutputEntry> entries;
  final VoidCallback onClear;
  final ValueChanged<String> onCopy;

  @override
  State<_CapturedOutputSheet> createState() => _CapturedOutputSheetState();
}

class _CapturedOutputSheetState extends State<_CapturedOutputSheet> {
  late List<_CapturedOutputEntry> _entries;

  @override
  void initState() {
    super.initState();
    _entries = widget.entries;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        key: const Key('captured-output-sheet'),
        color: palette.overlay,
        borderRadius: BorderRadius.circular(palette.radius.xl),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Captured Output',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AppActionButton(
                      tooltip: 'Close captured output',
                      tone: AppActionTone.ghost,
                      size: AppActionSize.dense,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icons.close_rounded,
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      '${_entries.length} captured line${_entries.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: palette.textSubtle,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      key: const Key('captured-output-clear'),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.textSubtle,
                        disabledForegroundColor: palette.textMuted.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      onPressed: _entries.isEmpty
                          ? null
                          : () {
                              setState(() {
                                _entries = const [];
                              });
                              widget.onClear();
                            },
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('Clear'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: _entries.isEmpty
                      ? SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: _ShellGuidedEmptyState(
                              stateKey: const Key(
                                'captured-output-empty-state',
                              ),
                              stepKeyPrefix: 'captured-output-empty-step',
                              icon: Icons.outbox_rounded,
                              title: 'Start capturing matching output',
                              body:
                                  'Captured rows appear after a profile trigger or coprocess pattern matches terminal output.',
                              steps: const [
                                'Open Profiles and add a trigger pattern.',
                                'Run a command that prints the pattern.',
                                'Reopen Captured Output to review and copy matches.',
                              ],
                              palette: palette,
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _entries.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = _entries[index];
                            return _CapturedOutputEntryTile(
                              index: index,
                              entry: entry,
                              palette: palette,
                              onCopy: () => widget.onCopy(entry.text),
                            );
                          },
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

class _CapturedOutputEntryTile extends StatelessWidget {
  const _CapturedOutputEntryTile({
    required this.index,
    required this.entry,
    required this.palette,
    required this.onCopy,
  });

  final int index;
  final _CapturedOutputEntry entry;
  final AppThemeTokens palette;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return _ShellEntryTile(
      key: Key('captured-output-entry-$index'),
      leading: Icon(Icons.outbox_rounded, color: palette.textMuted),
      title: entry.text,
      titleMaxLines: 2,
      subtitle: 'Pattern ${entry.pattern} • Row ${entry.rowIndex}',
      subtitleMaxLines: 1,
      trailing: _buildEntryActionButton(
        key: Key('captured-output-copy-$index'),
        tooltip: 'Copy captured output',
        onPressed: onCopy,
        icon: Icons.copy_rounded,
      ),
    );
  }
}

class _AnnotationsSheet extends StatefulWidget {
  const _AnnotationsSheet({
    required this.entries,
    required this.selectedText,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_TerminalAnnotation> entries;
  final String selectedText;
  final _TerminalAnnotation Function(String note) onAdd;
  final ValueChanged<String> onRemove;

  @override
  State<_AnnotationsSheet> createState() => _AnnotationsSheetState();
}

class _AnnotationsSheetState extends State<_AnnotationsSheet> {
  late List<_TerminalAnnotation> _entries;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _entries = widget.entries;
    _noteController = TextEditingController();
    _noteController.addListener(_handleNoteChanged);
  }

  @override
  void dispose() {
    _noteController.removeListener(_handleNoteChanged);
    _noteController.dispose();
    super.dispose();
  }

  bool get _canSave {
    return widget.selectedText.trim().isNotEmpty &&
        _noteController.text.trim().isNotEmpty;
  }

  void _handleNoteChanged() {
    setState(() {});
  }

  void _save() {
    if (!_canSave) {
      return;
    }
    final annotation = widget.onAdd(_noteController.text);
    setState(() {
      _entries = [annotation, ..._entries];
      _noteController.clear();
    });
  }

  void _remove(_TerminalAnnotation annotation) {
    widget.onRemove(annotation.id);
    setState(() {
      _entries = [
        for (final current in _entries)
          if (current.id != annotation.id) current,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final hasSelection = widget.selectedText.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        key: const Key('annotations-sheet'),
        color: palette.overlay,
        borderRadius: BorderRadius.circular(palette.radius.xl),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Annotations',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AppActionButton(
                      buttonKey: const Key('annotations-close'),
                      tooltip: 'Close annotations',
                      tone: AppActionTone.ghost,
                      size: AppActionSize.dense,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icons.close_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (hasSelection)
                  DecoratedBox(
                    key: const Key('annotation-selection-preview'),
                    decoration: BoxDecoration(
                      color: palette.terminalSurface,
                      borderRadius: BorderRadius.circular(palette.radius.md),
                      border: Border.all(color: palette.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.selectedText,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontFamily: 'monospace',
                                height: 1.25,
                              ),
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    'Select terminal text to add an annotation.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
                  ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('annotation-note-field'),
                  controller: _noteController,
                  enabled: hasSelection,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    alignLabelWithHint: true,
                  ),
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    key: const Key('annotation-save'),
                    onPressed: _canSave ? _save : null,
                    icon: const Icon(Icons.add_comment_rounded, size: 18),
                    label: const Text('Add Annotation'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '${_entries.length} annotation${_entries.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: palette.textSubtle,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: _entries.isEmpty
                      ? SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: _ShellGuidedEmptyState(
                              stateKey: const Key('annotations-empty-state'),
                              stepKeyPrefix: 'annotations-empty-step',
                              icon: Icons.sticky_note_2_rounded,
                              title: hasSelection
                                  ? 'Add the first annotation'
                                  : 'Select output before annotating',
                              body: hasSelection
                                  ? 'Use the note field above to attach a note to the selected terminal output.'
                                  : 'Annotations are created from selected terminal text in the active pane.',
                              steps: hasSelection
                                  ? const [
                                      'Enter a note for the selected output.',
                                      'Save the annotation.',
                                      'Use the annotation badge to reopen notes later.',
                                    ]
                                  : const [
                                      'Select terminal output in the pane.',
                                      'Open Annotations again.',
                                      'Enter a note and save it.',
                                    ],
                              palette: palette,
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _entries.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final annotation = _entries[index];
                            return _AnnotationEntryTile(
                              index: index,
                              annotation: annotation,
                              palette: palette,
                              onRemove: () => _remove(annotation),
                            );
                          },
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

class _ShellGuidedEmptyState extends StatelessWidget {
  const _ShellGuidedEmptyState({
    required this.stateKey,
    required this.stepKeyPrefix,
    required this.icon,
    required this.title,
    required this.body,
    required this.steps,
    required this.palette,
  });

  final Key stateKey;
  final String stepKeyPrefix;
  final IconData icon;
  final String title;
  final String body;
  final List<String> steps;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      key: stateKey,
      decoration: BoxDecoration(
        color: palette.terminalSurface,
        borderRadius: BorderRadius.circular(palette.radius.md),
        border: Border.all(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: palette.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: textTheme.titleSmall?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: textTheme.bodySmall?.copyWith(
                          color: palette.textSubtle,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final step in steps.indexed) ...[
              _ShellGuidedEmptyStep(
                key: Key('$stepKeyPrefix-${step.$1}'),
                index: step.$1 + 1,
                text: step.$2,
                palette: palette,
              ),
              if (step.$1 != steps.length - 1) const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShellGuidedEmptyStep extends StatelessWidget {
  const _ShellGuidedEmptyStep({
    super.key,
    required this.index,
    required this.text,
    required this.palette,
  });

  final int index;
  final String text;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.chrome,
            shape: BoxShape.circle,
            border: Border.all(color: palette.border),
          ),
          child: SizedBox.square(
            dimension: 22,
            child: Center(
              child: Text(
                '$index',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.textPrimary,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _AnnotationEntryTile extends StatelessWidget {
  const _AnnotationEntryTile({
    required this.index,
    required this.annotation,
    required this.palette,
    required this.onRemove,
  });

  final int index;
  final _TerminalAnnotation annotation;
  final AppThemeTokens palette;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _ShellEntryTile(
      key: Key('annotation-entry-$index'),
      leading: Icon(Icons.sticky_note_2_rounded, color: palette.textMuted),
      title: annotation.note,
      titleMaxLines: 2,
      subtitle: annotation.selectedText.replaceAll('\n', ' ⏎ '),
      subtitleMaxLines: 2,
      trailing: _buildEntryActionButton(
        key: Key('annotation-remove-$index'),
        tooltip: 'Remove annotation',
        onPressed: onRemove,
        icon: Icons.delete_outline_rounded,
      ),
    );
  }
}

class _PasteHistorySheet extends StatefulWidget {
  const _PasteHistorySheet({
    required this.entries,
    required this.persistToDisk,
    required this.onPersistChanged,
    required this.onClear,
  });

  final List<PasteHistoryEntry> entries;
  final bool persistToDisk;
  final ValueChanged<bool> onPersistChanged;
  final VoidCallback onClear;

  @override
  State<_PasteHistorySheet> createState() => _PasteHistorySheetState();
}

class _PasteHistorySheetState extends State<_PasteHistorySheet> {
  late List<PasteHistoryEntry> _entries;
  late bool _persistToDisk;

  @override
  void initState() {
    super.initState();
    _entries = widget.entries;
    _persistToDisk = widget.persistToDisk;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        key: const Key('paste-history-sheet'),
        color: palette.overlay,
        borderRadius: BorderRadius.circular(palette.radius.xl),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Paste History',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AppActionButton(
                      tooltip: 'Close paste history',
                      tone: AppActionTone.ghost,
                      size: AppActionSize.dense,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icons.close_rounded,
                    ),
                  ],
                ),
                _ShellSwitchTile(
                  tileKey: const Key('paste-history-persist'),
                  title: 'Save History to Disk',
                  subtitle:
                      'Keep recent copied and pasted text across launches.',
                  value: _persistToDisk,
                  onChanged: (value) {
                    setState(() {
                      _persistToDisk = value;
                    });
                    widget.onPersistChanged(value);
                  },
                ),
                Row(
                  children: [
                    Text(
                      '${_entries.length} recent item${_entries.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: palette.textSubtle,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      key: const Key('paste-history-clear'),
                      style: TextButton.styleFrom(
                        foregroundColor: palette.textSubtle,
                        disabledForegroundColor: palette.textMuted.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      onPressed: _entries.isEmpty
                          ? null
                          : () {
                              setState(() {
                                _entries = const [];
                              });
                              widget.onClear();
                            },
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('Clear'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: _entries.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          child: Center(
                            child: Text(
                              'No copied or pasted text yet.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.textSubtle),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _entries.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = _entries[index];
                            return _PasteHistoryEntryTile(
                              index: index,
                              entry: entry,
                              palette: palette,
                              onTap: () => Navigator.of(
                                context,
                              ).pop(_PasteHistoryPickResult(entry)),
                            );
                          },
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

class _PasteHistoryEntryTile extends StatelessWidget {
  const _PasteHistoryEntryTile({
    required this.index,
    required this.entry,
    required this.palette,
    required this.onTap,
  });

  final int index;
  final PasteHistoryEntry entry;
  final AppThemeTokens palette;
  final VoidCallback onTap;

  String get _kindLabel {
    return switch (entry.kind) {
      PasteHistoryKind.copy => 'Copied',
      PasteHistoryKind.paste => 'Pasted',
    };
  }

  @override
  Widget build(BuildContext context) {
    final preview = entry.text.replaceAll('\n', ' ⏎ ');
    return _ShellEntryTile(
      key: Key('paste-history-entry-$index'),
      leading: Icon(
        entry.kind == PasteHistoryKind.copy
            ? Icons.copy_rounded
            : Icons.content_paste_rounded,
        color: palette.textMuted,
      ),
      title: preview,
      titleMaxLines: 2,
      subtitle: _kindLabel,
      onTap: onTap,
    );
  }
}

class _ShellEntryTile extends StatelessWidget {
  const _ShellEntryTile({
    super.key,
    this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.dense = false,
    this.titleMaxLines = 1,
    this.subtitleMaxLines = 1,
  });

  final Widget? leading;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dense;
  final int titleMaxLines;
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return ListTile(
      dense: dense,
      contentPadding: EdgeInsets.zero,
      leading: leading,
      title: Text(
        title,
        maxLines: titleMaxLines,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: subtitleMaxLines,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _ShellSwitchTile extends StatelessWidget {
  const _ShellSwitchTile({
    required this.tileKey,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final Key tileKey;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return SwitchListTile(
      key: tileKey,
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _PasswordManagerSheet extends StatefulWidget {
  const _PasswordManagerSheet({
    required this.entries,
    required this.promptDetected,
    required this.onAdd,
    required this.onRemove,
  });

  final List<PasswordManagerEntry> entries;
  final bool promptDetected;
  final PasswordManagerEntry Function({
    required String label,
    required String password,
  })
  onAdd;
  final ValueChanged<String> onRemove;

  @override
  State<_PasswordManagerSheet> createState() => _PasswordManagerSheetState();
}

class _PasswordManagerSheetState extends State<_PasswordManagerSheet> {
  late List<PasswordManagerEntry> _entries;
  late final TextEditingController _labelController;
  late final TextEditingController _passwordController;
  late final FocusNode _passwordFocusNode;

  bool get _canAddEntry => _passwordController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _entries = widget.entries;
    _labelController = TextEditingController();
    _passwordController = TextEditingController();
    _passwordFocusNode = FocusNode(debugLabel: 'password-manager-password');
    _passwordController.addListener(_handlePasswordChanged);
  }

  @override
  void dispose() {
    _passwordController.removeListener(_handlePasswordChanged);
    _labelController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _handlePasswordChanged() {
    setState(() {});
  }

  void _addEntry() {
    final password = _passwordController.text;
    if (!_canAddEntry) {
      return;
    }
    final entry = widget.onAdd(
      label: _labelController.text,
      password: password,
    );
    setState(() {
      _entries = [entry, ..._entries];
      _labelController.clear();
      _passwordController.clear();
    });
  }

  void _removeEntry(PasswordManagerEntry entry) {
    widget.onRemove(entry.id);
    setState(() {
      _entries = [
        for (final current in _entries)
          if (current.id != entry.id) current,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        key: const Key('password-manager-sheet'),
        color: palette.overlay,
        borderRadius: BorderRadius.circular(palette.radius.xl),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Password Manager',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AppActionButton(
                      tooltip: 'Close password manager',
                      tone: AppActionTone.ghost,
                      size: AppActionSize.dense,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icons.close_rounded,
                    ),
                  ],
                ),
                Text(
                  widget.promptDetected
                      ? 'Password prompt detected in the active session.'
                      : 'Open a password prompt before sending a password.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
                ),
                const SizedBox(height: 4),
                Text(
                  'Passwords are kept for this app session and can only be sent when the active terminal appears to be asking for one.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('password-manager-label-field'),
                  controller: _labelController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Label',
                    hintText: 'Server or account',
                  ),
                ),
                const SizedBox(height: 8),
                Semantics(
                  label: 'Password',
                  value: _passwordController.text.isEmpty
                      ? ''
                      : 'Password entered',
                  textField: true,
                  obscured: true,
                  excludeSemantics: true,
                  onTap: () => _passwordFocusNode.requestFocus(),
                  onSetText: (text) {
                    _passwordController.value = TextEditingValue(
                      text: text,
                      selection: TextSelection.collapsed(offset: text.length),
                    );
                  },
                  child: TextField(
                    key: const Key('password-manager-password-field'),
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Password'),
                    onSubmitted: (_) => _addEntry(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    key: const Key('password-manager-add'),
                    onPressed: _canAddEntry ? _addEntry : null,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add'),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: _entries.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'No saved passwords in this session. Add one above, then open a password prompt before sending.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: palette.textSubtle),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _entries.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = _entries[index];
                            return _PasswordManagerEntryTile(
                              index: index,
                              entry: entry,
                              promptDetected: widget.promptDetected,
                              palette: palette,
                              onSend: () => Navigator.of(
                                context,
                              ).pop(_PasswordManagerSendResult(entry)),
                              onRemove: () => _removeEntry(entry),
                            );
                          },
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

class _PasswordManagerEntryTile extends StatelessWidget {
  const _PasswordManagerEntryTile({
    required this.index,
    required this.entry,
    required this.promptDetected,
    required this.palette,
    required this.onSend,
    required this.onRemove,
  });

  final int index;
  final PasswordManagerEntry entry;
  final bool promptDetected;
  final AppThemeTokens palette;
  final VoidCallback onSend;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _ShellEntryTile(
      key: Key('password-manager-entry-$index'),
      leading: Icon(Icons.key_rounded, color: palette.textMuted),
      title: entry.label,
      subtitle: promptDetected
          ? 'Ready to send'
          : 'Waiting for password prompt',
      trailing: Wrap(
        spacing: 4,
        children: [
          _buildEntryActionButton(
            key: Key('password-manager-remove-$index'),
            tooltip: 'Remove password',
            onPressed: onRemove,
            icon: Icons.delete_outline_rounded,
          ),
          FilledButton(
            key: Key('password-manager-send-$index'),
            onPressed: promptDetected ? onSend : null,
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

class _CoprocessIndicator extends StatelessWidget {
  const _CoprocessIndicator({
    super.key,
    required this.command,
    required this.palette,
  });

  final String command;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Coprocess: $command',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(palette.radius.md),
          border: Border.all(color: palette.accent.withValues(alpha: 0.72)),
          boxShadow: palette.elevation.floating,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hub_rounded, size: 15, color: palette.accent),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  command,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalAnnotationBadge extends StatelessWidget {
  const _TerminalAnnotationBadge({
    super.key,
    required this.count,
    required this.palette,
    required this.onTap,
  });

  final int count;
  final AppThemeTokens palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(palette.radius.md),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.overlay.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(palette.radius.md),
            border: Border.all(color: palette.borderStrong),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sticky_note_2_rounded,
                  size: 16,
                  color: palette.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  '$count annotation${count == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
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

class _ShellWorkspaceCue extends StatelessWidget {
  const _ShellWorkspaceCue({required this.title, required this.palette});

  final String title;
  final AppThemeTokens palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('shell-workspace-focus-cue'),
      decoration: BoxDecoration(
        color: palette.overlay.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(palette.radius.lg),
        border: Border.all(color: palette.focusRing.withValues(alpha: 0.62)),
        boxShadow: palette.elevation.floating,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.keyboard_command_key_rounded,
              color: palette.accent,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
