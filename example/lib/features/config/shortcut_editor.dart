import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/app_ui.dart';
import '../shell/shell_action_registry.dart';
import 'local_terminal_config_models.dart';
import 'local_terminal_keybinding_resolver.dart';

const List<TerminalKeyBindingScope> editableTerminalShortcutScopes = [
  TerminalKeyBindingScope.focusedApp,
  TerminalKeyBindingScope.terminalFocused,
];

class LocalTerminalShortcutFormatter {
  const LocalTerminalShortcutFormatter._();

  static String actionLabel(TerminalActionDescriptor descriptor) {
    final words = descriptor.label.split('_');
    if (words.isEmpty) {
      return descriptor.label;
    }
    return [_capitalize(words.first), ...words.skip(1)].join(' ');
  }

  static String categoryLabel(TerminalActionCategory category) {
    return switch (category) {
      TerminalActionCategory.app => 'App',
      TerminalActionCategory.session => 'Session',
      TerminalActionCategory.replay => 'Replay',
      TerminalActionCategory.pane => 'Pane',
      TerminalActionCategory.layout => 'Layout',
      TerminalActionCategory.navigation => 'Navigation',
      TerminalActionCategory.integration => 'Integration',
    };
  }

  static String scopeLabel(TerminalKeyBindingScope scope) {
    return switch (scope) {
      TerminalKeyBindingScope.focusedApp => 'App focused',
      TerminalKeyBindingScope.terminalFocused => 'Terminal focused',
      TerminalKeyBindingScope.global => 'App-wide fallback',
      TerminalKeyBindingScope.commandPaletteOpen => 'Command menu open',
    };
  }

  static String bindingLabel(LocalTerminalKeyBinding binding) {
    final parts = <String>[
      if (binding.control) '⌃',
      if (binding.alt) '⌥',
      if (binding.shift) '⇧',
      if (binding.meta) '⌘',
      _keyLabel(binding.key),
    ];
    return parts.join();
  }

  static String resolvedBindingLabel(
    TerminalActionId actionId,
    LocalTerminalKeybindingsConfig config,
  ) {
    final binding = currentBinding(actionId, config);
    return binding == null ? 'Not assigned' : bindingLabel(binding);
  }

  static LocalTerminalKeyBinding? currentBinding(
    TerminalActionId actionId,
    LocalTerminalKeybindingsConfig config,
  ) {
    if (config.disabledDefaultActions.contains(actionId)) {
      return null;
    }
    final override = config.overrides[actionId];
    if (override != null) {
      if (!override.enabled) {
        return null;
      }
      if (override.binding != null) {
        return override.binding;
      }
    }
    final defaultBinding =
        ShellActionRegistry.actions[actionId]?.defaultKeyBinding;
    if (defaultBinding == null) {
      return null;
    }
    return LocalTerminalKeyBinding(
      scope: defaultBinding.scope,
      key: defaultBinding.key.debugName ?? defaultBinding.key.keyLabel,
      meta: defaultBinding.meta,
      control: defaultBinding.control,
      shift: defaultBinding.shift,
      alt: defaultBinding.alt,
    );
  }

  static String _keyLabel(String raw) {
    final normalized = raw.trim();
    if (normalized.startsWith('Key ') && normalized.length > 4) {
      return normalized.substring(4).toUpperCase();
    }
    return switch (normalized.toLowerCase()) {
      'space' => 'Space',
      'arrow up' => '↑',
      'arrow down' => '↓',
      'arrow left' => '←',
      'arrow right' => '→',
      'comma' => ',',
      'period' => '.',
      'semicolon' => ';',
      'slash' => '/',
      'backslash' => r'\',
      'bracket left' => '[',
      'bracket right' => ']',
      'minus' => '-',
      'equal' => '=',
      _ => normalized,
    };
  }

  static String _capitalize(String value) {
    if (value.isEmpty) {
      return value;
    }
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }
}

class ShortcutEditorPanel extends StatefulWidget {
  const ShortcutEditorPanel({
    super.key,
    required this.config,
    required this.onChanged,
  });

  final LocalTerminalKeybindingsConfig config;
  final ValueChanged<LocalTerminalKeybindingsConfig> onChanged;

  @override
  State<ShortcutEditorPanel> createState() => _ShortcutEditorPanelState();
}

class _ShortcutEditorPanelState extends State<ShortcutEditorPanel> {
  final TextEditingController _filterController = TextEditingController();
  TerminalActionCategory? _category;

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  List<TerminalActionDescriptor> get _visibleActions {
    final query = _filterController.text.trim().toLowerCase();
    final actions = ShellActionRegistry.actions.values
        .where((descriptor) {
          if (!ShellActionRegistry.hasUserEntryPoint(descriptor.id) ||
              descriptor.id == TerminalActionId.activateTab) {
            return false;
          }
          if (_category != null && descriptor.category != _category) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          final label = LocalTerminalShortcutFormatter.actionLabel(descriptor);
          return '$label ${descriptor.label} ${descriptor.category.name}'
              .toLowerCase()
              .contains(query);
        })
        .toList(growable: false);
    actions.sort((left, right) {
      final categoryOrder = left.category.index.compareTo(right.category.index);
      if (categoryOrder != 0) {
        return categoryOrder;
      }
      return LocalTerminalShortcutFormatter.actionLabel(
        left,
      ).compareTo(LocalTerminalShortcutFormatter.actionLabel(right));
    });
    return actions;
  }

  List<ResolvedLocalTerminalKeyBindingConflict> get _conflicts {
    return LocalTerminalKeyBindingResolver.conflicts(
      LocalTerminalKeyBindingResolver.resolve(config: widget.config),
    );
  }

  Set<TerminalActionId> get _conflictingActionIds {
    return {for (final conflict in _conflicts) ...conflict.actionIds};
  }

  bool _isCustomized(TerminalActionId actionId) {
    return widget.config.disabledDefaultActions.contains(actionId) ||
        widget.config.overrides.containsKey(actionId);
  }

  void _setBinding(TerminalActionId actionId, LocalTerminalKeyBinding binding) {
    final disabled = <TerminalActionId>{...widget.config.disabledDefaultActions}
      ..remove(actionId);
    final overrides = <TerminalActionId, LocalTerminalKeyBindingOverride>{
      ...widget.config.overrides,
      actionId: LocalTerminalKeyBindingOverride(binding: binding),
    };
    widget.onChanged(
      LocalTerminalKeybindingsConfig(
        disabledDefaultActions: Set.unmodifiable(disabled),
        overrides: Map.unmodifiable(overrides),
      ),
    );
  }

  void _disableBinding(TerminalActionId actionId) {
    final disabled = <TerminalActionId>{...widget.config.disabledDefaultActions}
      ..remove(actionId);
    final overrides = <TerminalActionId, LocalTerminalKeyBindingOverride>{
      ...widget.config.overrides,
      actionId: const LocalTerminalKeyBindingOverride(enabled: false),
    };
    widget.onChanged(
      LocalTerminalKeybindingsConfig(
        disabledDefaultActions: Set.unmodifiable(disabled),
        overrides: Map.unmodifiable(overrides),
      ),
    );
  }

  void _restoreBinding(TerminalActionId actionId) {
    final disabled = <TerminalActionId>{...widget.config.disabledDefaultActions}
      ..remove(actionId);
    final overrides = <TerminalActionId, LocalTerminalKeyBindingOverride>{
      ...widget.config.overrides,
    }..remove(actionId);
    widget.onChanged(
      LocalTerminalKeybindingsConfig(
        disabledDefaultActions: Set.unmodifiable(disabled),
        overrides: Map.unmodifiable(overrides),
      ),
    );
  }

  Future<void> _editBinding(TerminalActionDescriptor descriptor) async {
    final current = LocalTerminalShortcutFormatter.currentBinding(
      descriptor.id,
      widget.config,
    );
    final result = await showDialog<_ShortcutCaptureResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ShortcutCaptureDialog(
        actionLabel: LocalTerminalShortcutFormatter.actionLabel(descriptor),
        initialBinding: current,
        suggestedScope:
            descriptor.defaultKeyBinding?.scope ??
            (descriptor.requiresActiveSession
                ? TerminalKeyBindingScope.terminalFocused
                : TerminalKeyBindingScope.focusedApp),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    if (result.clear) {
      _disableBinding(descriptor.id);
      return;
    }
    final binding = result.binding;
    if (binding != null) {
      _setBinding(descriptor.id, binding);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final conflicts = _conflicts;
    final conflictingActionIds = _conflictingActionIds;
    final visibleActions = _visibleActions;
    final hasCustomizations =
        widget.config.disabledDefaultActions.isNotEmpty ||
        widget.config.overrides.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'Keyboard shortcuts',
          description:
              'Select a shortcut to record a new key combination. Changes apply immediately after saving.',
        ),
        SizedBox(height: theme.spacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final search = Semantics(
              label: 'Filter shortcut actions',
              container: true,
              explicitChildNodes: true,
              child: TextField(
                key: const Key('shortcut-editor-filter'),
                controller: _filterController,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded),
                  labelText: 'Filter actions',
                ),
                onChanged: (_) => setState(() {}),
              ),
            );
            final category = AppDropdownFormField<TerminalActionCategory?>(
              key: const Key('shortcut-editor-category'),
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Category',
              ),
              items: [
                const DropdownMenuItem<TerminalActionCategory?>(
                  value: null,
                  child: Text('All actions'),
                ),
                for (final value in TerminalActionCategory.values)
                  DropdownMenuItem<TerminalActionCategory?>(
                    value: value,
                    child: Text(
                      LocalTerminalShortcutFormatter.categoryLabel(value),
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _category = value),
            );
            final restore = AppActionButton(
              buttonKey: const Key('shortcut-editor-restore-all'),
              tone: AppActionTone.secondary,
              size: AppActionSize.compact,
              icon: Icons.restart_alt_rounded,
              label: 'Restore all defaults',
              onPressed: hasCustomizations
                  ? () =>
                        widget.onChanged(const LocalTerminalKeybindingsConfig())
                  : null,
            );
            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  search,
                  SizedBox(height: theme.spacing.sm),
                  category,
                  SizedBox(height: theme.spacing.sm),
                  Align(alignment: Alignment.centerLeft, child: restore),
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 3, child: search),
                SizedBox(width: theme.spacing.sm),
                Expanded(flex: 2, child: category),
                SizedBox(width: theme.spacing.sm),
                restore,
              ],
            );
          },
        ),
        if (conflicts.isNotEmpty) ...[
          SizedBox(height: theme.spacing.sm),
          _ShortcutConflictSummary(conflicts: conflicts),
        ],
        SizedBox(height: theme.spacing.sm),
        AppPanel(
          key: const Key('shortcut-editor-list-panel'),
          tone: AppPanelTone.panel,
          child: SizedBox(
            height: 360,
            child: visibleActions.isEmpty
                ? const AppEmptyState(
                    title: 'No matching actions',
                    message: 'Try another action name or category.',
                  )
                : Scrollbar(
                    child: ListView.separated(
                      key: const Key('shortcut-editor-list'),
                      itemCount: visibleActions.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: theme.border),
                      itemBuilder: (context, index) {
                        final descriptor = visibleActions[index];
                        return _ShortcutActionRow(
                          descriptor: descriptor,
                          config: widget.config,
                          customized: _isCustomized(descriptor.id),
                          conflicted: conflictingActionIds.contains(
                            descriptor.id,
                          ),
                          onEdit: () => _editBinding(descriptor),
                          onDisable: () => _disableBinding(descriptor.id),
                          onRestore: () => _restoreBinding(descriptor.id),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ShortcutConflictSummary extends StatelessWidget {
  const _ShortcutConflictSummary({required this.conflicts});

  final List<ResolvedLocalTerminalKeyBindingConflict> conflicts;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Semantics(
      key: const Key('shortcut-editor-conflict-summary'),
      liveRegion: true,
      container: true,
      label:
          '${conflicts.length} shortcut ${conflicts.length == 1 ? 'conflict' : 'conflicts'}. Resolve conflicts before saving.',
      child: AppPanel(
        tone: AppPanelTone.danger,
        padding: EdgeInsets.all(theme.spacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: theme.danger),
            SizedBox(width: theme.spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Resolve shortcut conflicts before saving',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: theme.spacing.xs),
                  for (final conflict in conflicts)
                    Text(
                      _conflictDescription(conflict),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: theme.textSubtle),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _conflictDescription(
    ResolvedLocalTerminalKeyBindingConflict conflict,
  ) {
    final labels =
        conflict.actionIds
            .map((actionId) => ShellActionRegistry.actions[actionId])
            .whereType<TerminalActionDescriptor>()
            .map(LocalTerminalShortcutFormatter.actionLabel)
            .toList(growable: false)
          ..sort();
    final resolved = LocalTerminalKeyBinding(
      scope: _scopeFromSignature(conflict.signature),
      key: conflict.signature.split('+').last,
      meta: conflict.signature.contains('+meta+'),
      control: conflict.signature.contains('+control+'),
      shift: conflict.signature.contains('+shift+'),
      alt: conflict.signature.contains('+alt+'),
    );
    return '${LocalTerminalShortcutFormatter.bindingLabel(resolved)} · ${labels.join(' and ')}';
  }

  TerminalKeyBindingScope _scopeFromSignature(String signature) {
    final scopeName = signature.split('+').first;
    return TerminalKeyBindingScope.values.firstWhere(
      (scope) => scope.name == scopeName,
      orElse: () => TerminalKeyBindingScope.focusedApp,
    );
  }
}

class _ShortcutActionRow extends StatelessWidget {
  const _ShortcutActionRow({
    required this.descriptor,
    required this.config,
    required this.customized,
    required this.conflicted,
    required this.onEdit,
    required this.onDisable,
    required this.onRestore,
  });

  final TerminalActionDescriptor descriptor;
  final LocalTerminalKeybindingsConfig config;
  final bool customized;
  final bool conflicted;
  final VoidCallback onEdit;
  final VoidCallback onDisable;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final actionLabel = LocalTerminalShortcutFormatter.actionLabel(descriptor);
    final binding = LocalTerminalShortcutFormatter.currentBinding(
      descriptor.id,
      config,
    );
    final disabled = binding == null && customized;
    final stateLabel = conflicted
        ? 'Conflict'
        : disabled
        ? 'Disabled'
        : customized
        ? 'Custom'
        : binding == null
        ? 'Unassigned'
        : 'Default';

    return Semantics(
      container: true,
      label:
          '$actionLabel, $stateLabel, ${binding == null ? 'no shortcut' : LocalTerminalShortcutFormatter.bindingLabel(binding)}',
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: theme.spacing.md,
          vertical: theme.spacing.sm,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final identity = Row(
              children: [
                Icon(
                  descriptor.icon ?? Icons.bolt_rounded,
                  size: 18,
                  color: conflicted ? theme.danger : theme.textMuted,
                ),
                SizedBox(width: theme.spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        actionLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: theme.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: theme.spacing.xs),
                      Text(
                        '${LocalTerminalShortcutFormatter.categoryLabel(descriptor.category)} · $stateLabel${binding == null ? '' : ' · ${LocalTerminalShortcutFormatter.scopeLabel(binding.scope)}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: conflicted ? theme.danger : theme.textSubtle,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            final controls = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppActionButton(
                  buttonKey: Key('shortcut-edit-${descriptor.id.name}'),
                  tone: conflicted
                      ? AppActionTone.danger
                      : AppActionTone.secondary,
                  size: AppActionSize.compact,
                  icon: Icons.keyboard_rounded,
                  label: binding == null
                      ? 'Add shortcut'
                      : LocalTerminalShortcutFormatter.bindingLabel(binding),
                  tooltip: 'Edit shortcut for $actionLabel',
                  onPressed: onEdit,
                ),
                if (binding != null) ...[
                  SizedBox(width: theme.spacing.xs),
                  AppActionButton(
                    buttonKey: Key('shortcut-disable-${descriptor.id.name}'),
                    tone: AppActionTone.ghost,
                    size: AppActionSize.compact,
                    icon: Icons.link_off_rounded,
                    tooltip: 'Disable shortcut for $actionLabel',
                    onPressed: onDisable,
                  ),
                ],
                if (customized) ...[
                  SizedBox(width: theme.spacing.xs),
                  AppActionButton(
                    buttonKey: Key('shortcut-restore-${descriptor.id.name}'),
                    tone: AppActionTone.ghost,
                    size: AppActionSize.compact,
                    icon: Icons.restart_alt_rounded,
                    tooltip: 'Restore default shortcut for $actionLabel',
                    onPressed: onRestore,
                  ),
                ],
              ],
            );
            if (constraints.maxWidth < 500) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  identity,
                  SizedBox(height: theme.spacing.sm),
                  Align(alignment: Alignment.centerRight, child: controls),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: identity),
                SizedBox(width: theme.spacing.md),
                controls,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ShortcutCaptureResult {
  const _ShortcutCaptureResult.binding(this.binding) : clear = false;
  const _ShortcutCaptureResult.clear() : binding = null, clear = true;

  final LocalTerminalKeyBinding? binding;
  final bool clear;
}

class _ShortcutCaptureDialog extends StatefulWidget {
  const _ShortcutCaptureDialog({
    required this.actionLabel,
    required this.initialBinding,
    required this.suggestedScope,
  });

  final String actionLabel;
  final LocalTerminalKeyBinding? initialBinding;
  final TerminalKeyBindingScope suggestedScope;

  @override
  State<_ShortcutCaptureDialog> createState() => _ShortcutCaptureDialogState();
}

class _ShortcutCaptureDialogState extends State<_ShortcutCaptureDialog> {
  late TerminalKeyBindingScope _scope;
  LocalTerminalKeyBinding? _candidate;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initialScope = widget.initialBinding?.scope ?? widget.suggestedScope;
    _scope = editableTerminalShortcutScopes.contains(initialScope)
        ? initialScope
        : TerminalKeyBindingScope.focusedApp;
    _candidate = widget.initialBinding == null
        ? null
        : _bindingWithScope(widget.initialBinding!, _scope);
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    if (_modifierKeys.contains(key)) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    final keyboard = HardwareKeyboard.instance;
    final meta = keyboard.isMetaPressed;
    final control = keyboard.isControlPressed;
    final shift = keyboard.isShiftPressed;
    final alt = keyboard.isAltPressed;
    if ((key == LogicalKeyboardKey.backspace ||
            key == LogicalKeyboardKey.delete) &&
        !meta &&
        !control &&
        !shift &&
        !alt) {
      Navigator.of(context).pop(const _ShortcutCaptureResult.clear());
      return KeyEventResult.handled;
    }
    if (!meta && !control && !alt && !_functionKeys.contains(key)) {
      setState(() {
        _candidate = null;
        _error =
            'Use Command, Control, or Option with the key. Unmodified function keys are also allowed.';
      });
      return KeyEventResult.handled;
    }

    setState(() {
      _candidate = LocalTerminalKeyBinding(
        scope: _scope,
        key: key.debugName ?? key.keyLabel,
        meta: meta,
        control: control,
        shift: shift,
        alt: alt,
      );
      _error = null;
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return AlertDialog(
      key: const Key('shortcut-capture-dialog'),
      title: const Text('Record shortcut'),
      content: SizedBox(
        width: 420,
        child: Focus(
          key: const Key('shortcut-capture-focus'),
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.actionLabel,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: theme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: theme.spacing.md),
              AppDropdownFormField<TerminalKeyBindingScope>(
                key: const Key('shortcut-capture-scope'),
                initialValue: _scope,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Active when',
                ),
                items: [
                  for (final scope in editableTerminalShortcutScopes)
                    DropdownMenuItem(
                      value: scope,
                      child: Text(
                        LocalTerminalShortcutFormatter.scopeLabel(scope),
                      ),
                    ),
                ],
                onChanged: (scope) {
                  if (scope == null) {
                    return;
                  }
                  setState(() {
                    _scope = scope;
                    if (_candidate != null) {
                      _candidate = _bindingWithScope(_candidate!, scope);
                    }
                  });
                },
              ),
              SizedBox(height: theme.spacing.md),
              Semantics(
                liveRegion: true,
                label: _candidate == null
                    ? 'Waiting for shortcut'
                    : 'Recorded ${LocalTerminalShortcutFormatter.bindingLabel(_candidate!)}',
                child: AppPanel(
                  tone: _error == null
                      ? AppPanelTone.selected
                      : AppPanelTone.danger,
                  padding: EdgeInsets.all(theme.spacing.xl),
                  child: Column(
                    children: [
                      Icon(
                        Icons.keyboard_rounded,
                        color: _error == null ? theme.accent : theme.danger,
                      ),
                      SizedBox(height: theme.spacing.sm),
                      Text(
                        _candidate == null
                            ? 'Press a shortcut'
                            : LocalTerminalShortcutFormatter.bindingLabel(
                                _candidate!,
                              ),
                        key: const Key('shortcut-capture-value'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: theme.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: theme.spacing.xs),
                      Text(
                        _error ??
                            'Press Escape to cancel, or Delete to disable this shortcut.',
                        key: _error == null
                            ? null
                            : const Key('shortcut-capture-error'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _error == null
                              ? theme.textSubtle
                              : theme.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('shortcut-capture-disable'),
          onPressed: () =>
              Navigator.of(context).pop(const _ShortcutCaptureResult.clear()),
          child: const Text('Disable shortcut'),
        ),
        FilledButton(
          key: const Key('shortcut-capture-apply'),
          onPressed: _candidate == null
              ? null
              : () => Navigator.of(
                  context,
                ).pop(_ShortcutCaptureResult.binding(_candidate)),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  LocalTerminalKeyBinding _bindingWithScope(
    LocalTerminalKeyBinding binding,
    TerminalKeyBindingScope scope,
  ) {
    return LocalTerminalKeyBinding(
      scope: scope,
      key: binding.key,
      meta: binding.meta,
      control: binding.control,
      shift: binding.shift,
      alt: binding.alt,
    );
  }
}

final Set<LogicalKeyboardKey> _modifierKeys = {
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
};

final Set<LogicalKeyboardKey> _functionKeys = {
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
  LogicalKeyboardKey.f13,
  LogicalKeyboardKey.f14,
  LogicalKeyboardKey.f15,
  LogicalKeyboardKey.f16,
  LogicalKeyboardKey.f17,
  LogicalKeyboardKey.f18,
  LogicalKeyboardKey.f19,
  LogicalKeyboardKey.f20,
  LogicalKeyboardKey.f21,
  LogicalKeyboardKey.f22,
  LogicalKeyboardKey.f23,
  LogicalKeyboardKey.f24,
};
