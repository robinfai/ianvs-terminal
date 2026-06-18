import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum TerminalActionId {
  openLauncher,
  openCommandMenu,
  openActionSearch,
  newTab,
  duplicateCurrentCwd,
  reopenClosedTab,
  toolbelt,
  splitRight,
  splitDown,
  focusNextPane,
  focusPreviousPane,
  resizePane,
  swapPane,
  zoomPane,
  closePane,
  reopenClosedPane,
  closeActiveTab,
  openDefaults,
  activateTab,
  copy,
  copyMode,
  copyCommandOutput,
  copyBlockOutput,
  saveBlockOutput,
  openInReview,
  searchWithinBlock,
  reInputBlockCommand,
  rerunBlockCommand,
  paste,
  advancedPaste,
  pasteHistory,
  toggleReadOnly,
  clearScrollback,
  shellIntegrationUtilities,
  selectCommandOutput,
  openRecentDirectory,
  tmuxIntegration,
  coprocess,
  annotations,
  capturedOutput,
  passwordManager,
  instantReplay,
  openHistoryPeek,
  replayFromCommandBlock,
  saveCommandSnapshot,
  compareLastCommandRun,
  markCommandBlock,
  search,
  nextSearchMatch,
  previousSearchMatch,
  clearSearch,
  globalSearch,
  autocomplete,
  autoComposer,
  hotkeyWindow,
  defaults,
  profiles,
  dynamicProfiles,
  requestQuitConfirmation,
  previousPrompt,
  nextPrompt,
  toggleCommandFinishedNotify,
  toggleBellNotify,
  toggleActivityMonitor,
  exportScrollback,
  exportDiagnostics,
  openThemePicker,
  applyTheme,
  applyLayoutTemplate,
}

enum TerminalActionCategory {
  app,
  session,
  pane,
  workspace,
  navigation,
  integration,
}

enum TerminalKeyBindingScope {
  global,
  focusedApp,
  terminalFocused,
  commandPaletteOpen,
}

enum TerminalInputPolicy { terminalFirst, appFirst, performableOnly }

class TerminalKeyBinding {
  const TerminalKeyBinding({
    required this.scope,
    required this.key,
    this.meta = false,
    this.control = false,
    this.shift = false,
    this.alt = false,
  });

  final TerminalKeyBindingScope scope;
  final LogicalKeyboardKey key;
  final bool meta;
  final bool control;
  final bool shift;
  final bool alt;

  bool conflictsWith(TerminalKeyBinding other) {
    return scope == other.scope &&
        key == other.key &&
        meta == other.meta &&
        control == other.control &&
        shift == other.shift &&
        alt == other.alt;
  }

  String get signature {
    final parts = <String>[
      scope.name,
      if (meta) 'meta',
      if (control) 'control',
      if (shift) 'shift',
      if (alt) 'alt',
      key.debugName ?? key.keyLabel,
    ];
    return parts.join('+');
  }
}

class TerminalKeyBindingConflict {
  const TerminalKeyBindingConflict({
    required this.binding,
    required this.actionIds,
  });

  final TerminalKeyBinding binding;
  final Set<TerminalActionId> actionIds;
}

class TerminalActionDescriptor {
  const TerminalActionDescriptor({
    required this.id,
    required this.label,
    required this.category,
    this.enabledByDefault = true,
    this.commandPaletteVisible = true,
    this.shortcutHint,
    this.defaultKeyBinding,
    this.terminalInputPolicy = TerminalInputPolicy.performableOnly,
    this.icon,
    this.requiresActiveSession = false,
  });

  final TerminalActionId id;
  final String label;
  final TerminalActionCategory category;
  final bool enabledByDefault;
  final bool commandPaletteVisible;
  final String? shortcutHint;
  final TerminalKeyBinding? defaultKeyBinding;
  final TerminalInputPolicy terminalInputPolicy;
  final IconData? icon;
  final bool requiresActiveSession;
}

class ShellActionRegistry {
  const ShellActionRegistry._();

  static const Map<TerminalActionId, TerminalActionDescriptor> actions = {
    TerminalActionId.newTab: TerminalActionDescriptor(
      id: TerminalActionId.newTab,
      label: 'new_tab',
      category: TerminalActionCategory.app,
      shortcutHint: 'cmd+T',
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.focusedApp,
        meta: true,
        key: LogicalKeyboardKey.keyT,
      ),
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.add,
      requiresActiveSession: false,
    ),
    TerminalActionId.duplicateCurrentCwd: TerminalActionDescriptor(
      id: TerminalActionId.duplicateCurrentCwd,
      label: 'duplicate_current_cwd',
      category: TerminalActionCategory.session,
      icon: Icons.copy_all,
      requiresActiveSession: true,
    ),
    TerminalActionId.reopenClosedTab: TerminalActionDescriptor(
      id: TerminalActionId.reopenClosedTab,
      label: 'reopen_closed_tab',
      category: TerminalActionCategory.session,
      icon: Icons.restore,
      requiresActiveSession: false,
    ),
    TerminalActionId.openLauncher: TerminalActionDescriptor(
      id: TerminalActionId.openLauncher,
      label: 'open_launcher',
      category: TerminalActionCategory.app,
      shortcutHint: 'cmd+shift+P',
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.focusedApp,
        meta: true,
        shift: true,
        key: LogicalKeyboardKey.keyP,
      ),
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.rocket_launch,
      requiresActiveSession: false,
    ),
    TerminalActionId.openCommandMenu: TerminalActionDescriptor(
      id: TerminalActionId.openCommandMenu,
      label: 'open_command_menu',
      category: TerminalActionCategory.app,
      shortcutHint: 'cmd+shift+P',
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.menu,
      requiresActiveSession: false,
    ),
    TerminalActionId.openActionSearch: TerminalActionDescriptor(
      id: TerminalActionId.openActionSearch,
      label: 'open_action_search',
      category: TerminalActionCategory.workspace,
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.manage_search,
      requiresActiveSession: true,
    ),
    TerminalActionId.toolbelt: TerminalActionDescriptor(
      id: TerminalActionId.toolbelt,
      label: 'toolbelt',
      category: TerminalActionCategory.session,
      shortcutHint: null,
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.view_sidebar,
      requiresActiveSession: true,
    ),
    TerminalActionId.splitRight: TerminalActionDescriptor(
      id: TerminalActionId.splitRight,
      label: 'split_right',
      category: TerminalActionCategory.pane,
      shortcutHint: 'cmd+D',
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.terminalFocused,
        meta: true,
        key: LogicalKeyboardKey.keyD,
      ),
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.vertical_split,
      requiresActiveSession: true,
    ),
    TerminalActionId.splitDown: TerminalActionDescriptor(
      id: TerminalActionId.splitDown,
      label: 'split_down',
      category: TerminalActionCategory.pane,
      shortcutHint: 'cmd+shift+D',
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.terminalFocused,
        meta: true,
        shift: true,
        key: LogicalKeyboardKey.keyD,
      ),
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.horizontal_split,
      requiresActiveSession: true,
    ),
    TerminalActionId.focusNextPane: TerminalActionDescriptor(
      id: TerminalActionId.focusNextPane,
      label: 'focus_next_pane',
      category: TerminalActionCategory.pane,
      icon: Icons.keyboard_tab,
      requiresActiveSession: true,
    ),
    TerminalActionId.focusPreviousPane: TerminalActionDescriptor(
      id: TerminalActionId.focusPreviousPane,
      label: 'focus_previous_pane',
      category: TerminalActionCategory.pane,
      icon: Icons.keyboard_tab,
      requiresActiveSession: true,
    ),
    TerminalActionId.resizePane: TerminalActionDescriptor(
      id: TerminalActionId.resizePane,
      label: 'resize_pane',
      category: TerminalActionCategory.pane,
      icon: Icons.open_with,
      requiresActiveSession: true,
    ),
    TerminalActionId.swapPane: TerminalActionDescriptor(
      id: TerminalActionId.swapPane,
      label: 'swap_pane',
      category: TerminalActionCategory.pane,
      icon: Icons.swap_horiz,
      requiresActiveSession: true,
    ),
    TerminalActionId.zoomPane: TerminalActionDescriptor(
      id: TerminalActionId.zoomPane,
      label: 'zoom_pane',
      category: TerminalActionCategory.pane,
      icon: Icons.zoom_out_map,
      requiresActiveSession: true,
    ),
    TerminalActionId.closePane: TerminalActionDescriptor(
      id: TerminalActionId.closePane,
      label: 'close_pane',
      category: TerminalActionCategory.pane,
      icon: Icons.close,
      requiresActiveSession: true,
    ),
    TerminalActionId.reopenClosedPane: TerminalActionDescriptor(
      id: TerminalActionId.reopenClosedPane,
      label: 'reopen_closed_pane',
      category: TerminalActionCategory.pane,
      icon: Icons.restore,
      requiresActiveSession: true,
    ),
    TerminalActionId.closeActiveTab: TerminalActionDescriptor(
      id: TerminalActionId.closeActiveTab,
      label: 'close_active_tab',
      category: TerminalActionCategory.session,
      shortcutHint: 'cmd+W',
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.focusedApp,
        meta: true,
        key: LogicalKeyboardKey.keyW,
      ),
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.tab,
      requiresActiveSession: true,
    ),
    TerminalActionId.openDefaults: TerminalActionDescriptor(
      id: TerminalActionId.openDefaults,
      label: 'open_defaults',
      category: TerminalActionCategory.app,
      shortcutHint: 'cmd+,',
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.focusedApp,
        meta: true,
        key: LogicalKeyboardKey.comma,
      ),
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.tune,
      requiresActiveSession: false,
    ),
    TerminalActionId.activateTab: TerminalActionDescriptor(
      id: TerminalActionId.activateTab,
      label: 'activate_tab',
      category: TerminalActionCategory.workspace,
      enabledByDefault: false,
      commandPaletteVisible: false,
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.tab,
      requiresActiveSession: true,
    ),
    TerminalActionId.copy: TerminalActionDescriptor(
      id: TerminalActionId.copy,
      label: 'copy',
      category: TerminalActionCategory.session,
      shortcutHint: 'cmd+C',
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.terminalFocused,
        meta: true,
        key: LogicalKeyboardKey.keyC,
      ),
      terminalInputPolicy: TerminalInputPolicy.performableOnly,
      icon: Icons.copy,
      requiresActiveSession: true,
    ),
    TerminalActionId.copyMode: TerminalActionDescriptor(
      id: TerminalActionId.copyMode,
      label: 'copy_mode',
      category: TerminalActionCategory.session,
      shortcutHint: 'cmd+shift+C',
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.terminalFocused,
        meta: true,
        shift: true,
        key: LogicalKeyboardKey.keyC,
      ),
      terminalInputPolicy: TerminalInputPolicy.performableOnly,
      icon: Icons.select_all,
      requiresActiveSession: true,
    ),
    TerminalActionId.copyCommandOutput: TerminalActionDescriptor(
      id: TerminalActionId.copyCommandOutput,
      label: 'copy_command_output',
      category: TerminalActionCategory.integration,
      icon: Icons.copy_all,
      requiresActiveSession: true,
    ),
    TerminalActionId.copyBlockOutput: TerminalActionDescriptor(
      id: TerminalActionId.copyBlockOutput,
      label: 'copy_block_output',
      category: TerminalActionCategory.integration,
      icon: Icons.copy_all,
      requiresActiveSession: true,
    ),
    TerminalActionId.saveBlockOutput: TerminalActionDescriptor(
      id: TerminalActionId.saveBlockOutput,
      label: 'save_block_output',
      category: TerminalActionCategory.integration,
      icon: Icons.save_alt,
      requiresActiveSession: true,
    ),
    TerminalActionId.openInReview: TerminalActionDescriptor(
      id: TerminalActionId.openInReview,
      label: 'open_in_review',
      category: TerminalActionCategory.integration,
      icon: Icons.rate_review,
      requiresActiveSession: true,
    ),
    TerminalActionId.searchWithinBlock: TerminalActionDescriptor(
      id: TerminalActionId.searchWithinBlock,
      label: 'search_within_block',
      category: TerminalActionCategory.integration,
      icon: Icons.manage_search,
      requiresActiveSession: true,
    ),
    TerminalActionId.reInputBlockCommand: TerminalActionDescriptor(
      id: TerminalActionId.reInputBlockCommand,
      label: 'reinput_block_command',
      category: TerminalActionCategory.integration,
      terminalInputPolicy: TerminalInputPolicy.performableOnly,
      icon: Icons.keyboard_return,
      requiresActiveSession: true,
    ),
    TerminalActionId.rerunBlockCommand: TerminalActionDescriptor(
      id: TerminalActionId.rerunBlockCommand,
      label: 'rerun_block_command',
      category: TerminalActionCategory.integration,
      terminalInputPolicy: TerminalInputPolicy.performableOnly,
      icon: Icons.replay,
      requiresActiveSession: true,
    ),
    TerminalActionId.paste: TerminalActionDescriptor(
      id: TerminalActionId.paste,
      label: 'paste',
      category: TerminalActionCategory.session,
      shortcutHint: 'cmd+V',
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.terminalFocused,
        meta: true,
        key: LogicalKeyboardKey.keyV,
      ),
      terminalInputPolicy: TerminalInputPolicy.performableOnly,
      icon: Icons.content_paste,
      requiresActiveSession: true,
    ),
    TerminalActionId.advancedPaste: TerminalActionDescriptor(
      id: TerminalActionId.advancedPaste,
      label: 'advanced_paste',
      category: TerminalActionCategory.session,
      terminalInputPolicy: TerminalInputPolicy.performableOnly,
      icon: Icons.assignment,
      requiresActiveSession: true,
    ),
    TerminalActionId.pasteHistory: TerminalActionDescriptor(
      id: TerminalActionId.pasteHistory,
      label: 'paste_history',
      category: TerminalActionCategory.session,
      shortcutHint: 'cmd+shift+H',
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.terminalFocused,
        meta: true,
        shift: true,
        key: LogicalKeyboardKey.keyH,
      ),
      terminalInputPolicy: TerminalInputPolicy.performableOnly,
      icon: Icons.history,
      requiresActiveSession: true,
    ),
    TerminalActionId.toggleReadOnly: TerminalActionDescriptor(
      id: TerminalActionId.toggleReadOnly,
      label: 'toggle_read_only',
      category: TerminalActionCategory.session,
      icon: Icons.lock,
      requiresActiveSession: true,
    ),
    TerminalActionId.clearScrollback: TerminalActionDescriptor(
      id: TerminalActionId.clearScrollback,
      label: 'clear_scrollback',
      category: TerminalActionCategory.workspace,
      icon: Icons.clear_all,
      requiresActiveSession: true,
    ),
    TerminalActionId.shellIntegrationUtilities: TerminalActionDescriptor(
      id: TerminalActionId.shellIntegrationUtilities,
      label: 'shell_integration',
      category: TerminalActionCategory.integration,
      icon: Icons.integration_instructions,
      requiresActiveSession: true,
    ),
    TerminalActionId.selectCommandOutput: TerminalActionDescriptor(
      id: TerminalActionId.selectCommandOutput,
      label: 'select_command_output',
      category: TerminalActionCategory.integration,
      icon: Icons.fact_check,
      requiresActiveSession: true,
    ),
    TerminalActionId.openRecentDirectory: TerminalActionDescriptor(
      id: TerminalActionId.openRecentDirectory,
      label: 'open_recent_directory',
      category: TerminalActionCategory.integration,
      icon: Icons.folder,
      requiresActiveSession: true,
    ),
    TerminalActionId.tmuxIntegration: TerminalActionDescriptor(
      id: TerminalActionId.tmuxIntegration,
      label: 'tmux_integration',
      category: TerminalActionCategory.integration,
      icon: Icons.account_tree,
      requiresActiveSession: true,
    ),
    TerminalActionId.coprocess: TerminalActionDescriptor(
      id: TerminalActionId.coprocess,
      label: 'coprocess',
      category: TerminalActionCategory.integration,
      icon: Icons.hub,
      requiresActiveSession: true,
    ),
    TerminalActionId.annotations: TerminalActionDescriptor(
      id: TerminalActionId.annotations,
      label: 'annotations',
      category: TerminalActionCategory.session,
      icon: Icons.note,
      requiresActiveSession: true,
    ),
    TerminalActionId.capturedOutput: TerminalActionDescriptor(
      id: TerminalActionId.capturedOutput,
      label: 'captured_output',
      category: TerminalActionCategory.session,
      icon: Icons.outbox,
      requiresActiveSession: true,
    ),
    TerminalActionId.passwordManager: TerminalActionDescriptor(
      id: TerminalActionId.passwordManager,
      label: 'password_manager',
      category: TerminalActionCategory.session,
      icon: Icons.password,
      requiresActiveSession: true,
    ),
    TerminalActionId.instantReplay: TerminalActionDescriptor(
      id: TerminalActionId.instantReplay,
      label: 'instant_replay',
      category: TerminalActionCategory.session,
      shortcutHint: 'alt+cmd+B',
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.terminalFocused,
        meta: true,
        alt: true,
        key: LogicalKeyboardKey.keyB,
      ),
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.replay,
      requiresActiveSession: true,
    ),
    TerminalActionId.openHistoryPeek: TerminalActionDescriptor(
      id: TerminalActionId.openHistoryPeek,
      label: 'command_search',
      category: TerminalActionCategory.navigation,
      shortcutHint: 'ctrl+R',
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.search,
      requiresActiveSession: true,
    ),
    TerminalActionId.replayFromCommandBlock: TerminalActionDescriptor(
      id: TerminalActionId.replayFromCommandBlock,
      label: 'replay_from_command_block',
      category: TerminalActionCategory.navigation,
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.replay,
      requiresActiveSession: true,
    ),
    TerminalActionId.saveCommandSnapshot: TerminalActionDescriptor(
      id: TerminalActionId.saveCommandSnapshot,
      label: 'save_command_snapshot',
      category: TerminalActionCategory.integration,
      commandPaletteVisible: false,
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.bookmark_add,
      requiresActiveSession: true,
    ),
    TerminalActionId.compareLastCommandRun: TerminalActionDescriptor(
      id: TerminalActionId.compareLastCommandRun,
      label: 'compare_last_command_run',
      category: TerminalActionCategory.integration,
      commandPaletteVisible: false,
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.compare_arrows,
      requiresActiveSession: true,
    ),
    TerminalActionId.markCommandBlock: TerminalActionDescriptor(
      id: TerminalActionId.markCommandBlock,
      label: 'mark_command_block',
      category: TerminalActionCategory.integration,
      commandPaletteVisible: false,
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.bookmark_border,
      requiresActiveSession: true,
    ),
    TerminalActionId.search: TerminalActionDescriptor(
      id: TerminalActionId.search,
      label: 'search_scrollback',
      category: TerminalActionCategory.workspace,
      shortcutHint: 'cmd+F',
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.terminalFocused,
        meta: true,
        key: LogicalKeyboardKey.keyF,
      ),
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.search,
      requiresActiveSession: true,
    ),
    TerminalActionId.nextSearchMatch: TerminalActionDescriptor(
      id: TerminalActionId.nextSearchMatch,
      label: 'next_search_match',
      category: TerminalActionCategory.workspace,
      icon: Icons.keyboard_arrow_down,
      requiresActiveSession: true,
    ),
    TerminalActionId.previousSearchMatch: TerminalActionDescriptor(
      id: TerminalActionId.previousSearchMatch,
      label: 'previous_search_match',
      category: TerminalActionCategory.workspace,
      icon: Icons.keyboard_arrow_up,
      requiresActiveSession: true,
    ),
    TerminalActionId.clearSearch: TerminalActionDescriptor(
      id: TerminalActionId.clearSearch,
      label: 'clear_search',
      category: TerminalActionCategory.workspace,
      icon: Icons.search_off,
      requiresActiveSession: true,
    ),
    TerminalActionId.globalSearch: TerminalActionDescriptor(
      id: TerminalActionId.globalSearch,
      label: 'global_search',
      category: TerminalActionCategory.workspace,
      icon: Icons.manage_search,
      requiresActiveSession: true,
    ),
    TerminalActionId.autocomplete: TerminalActionDescriptor(
      id: TerminalActionId.autocomplete,
      label: 'autocomplete',
      category: TerminalActionCategory.session,
      shortcutHint: 'cmd+; (semicolon)',
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.terminalFocused,
        meta: true,
        key: LogicalKeyboardKey.semicolon,
      ),
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.auto_fix_high,
      requiresActiveSession: true,
    ),
    TerminalActionId.autoComposer: TerminalActionDescriptor(
      id: TerminalActionId.autoComposer,
      label: 'auto_composer',
      category: TerminalActionCategory.session,
      icon: Icons.edit_note,
      requiresActiveSession: true,
    ),
    TerminalActionId.hotkeyWindow: TerminalActionDescriptor(
      id: TerminalActionId.hotkeyWindow,
      label: 'hotkey_window',
      category: TerminalActionCategory.app,
      shortcutHint: 'alt+cmd+Space',
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.focusedApp,
        meta: true,
        alt: true,
        key: LogicalKeyboardKey.space,
      ),
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.keyboard,
      requiresActiveSession: false,
    ),
    TerminalActionId.defaults: TerminalActionDescriptor(
      id: TerminalActionId.defaults,
      label: 'defaults',
      category: TerminalActionCategory.app,
      icon: Icons.tune,
      requiresActiveSession: false,
    ),
    TerminalActionId.profiles: TerminalActionDescriptor(
      id: TerminalActionId.profiles,
      label: 'profiles',
      category: TerminalActionCategory.app,
      icon: Icons.folder_open,
      requiresActiveSession: false,
    ),
    TerminalActionId.dynamicProfiles: TerminalActionDescriptor(
      id: TerminalActionId.dynamicProfiles,
      label: 'dynamic_profiles',
      category: TerminalActionCategory.app,
      icon: Icons.data_object,
      requiresActiveSession: false,
    ),
    TerminalActionId.requestQuitConfirmation: TerminalActionDescriptor(
      id: TerminalActionId.requestQuitConfirmation,
      label: 'request_quit_confirmation',
      category: TerminalActionCategory.app,
      requiresActiveSession: false,
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.focusedApp,
        meta: true,
        key: LogicalKeyboardKey.keyQ,
      ),
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      commandPaletteVisible: false,
      icon: Icons.exit_to_app,
    ),
    TerminalActionId.previousPrompt: TerminalActionDescriptor(
      id: TerminalActionId.previousPrompt,
      label: 'previous_prompt',
      category: TerminalActionCategory.navigation,
      shortcutHint: 'cmd+shift+↑',
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.terminalFocused,
        meta: true,
        shift: true,
        key: LogicalKeyboardKey.arrowUp,
      ),
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.keyboard_arrow_up,
      requiresActiveSession: true,
      commandPaletteVisible: false,
    ),
    TerminalActionId.nextPrompt: TerminalActionDescriptor(
      id: TerminalActionId.nextPrompt,
      label: 'next_prompt',
      category: TerminalActionCategory.navigation,
      shortcutHint: 'cmd+shift+↓',
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.terminalFocused,
        meta: true,
        shift: true,
        key: LogicalKeyboardKey.arrowDown,
      ),
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.keyboard_arrow_down,
      requiresActiveSession: true,
      commandPaletteVisible: false,
    ),
    TerminalActionId.toggleCommandFinishedNotify: TerminalActionDescriptor(
      id: TerminalActionId.toggleCommandFinishedNotify,
      label: 'toggle_command_finished_notify',
      category: TerminalActionCategory.integration,
      icon: Icons.notifications_active,
      requiresActiveSession: true,
    ),
    TerminalActionId.toggleBellNotify: TerminalActionDescriptor(
      id: TerminalActionId.toggleBellNotify,
      label: 'toggle_bell_notify',
      category: TerminalActionCategory.integration,
      icon: Icons.notifications,
      requiresActiveSession: true,
    ),
    TerminalActionId.toggleActivityMonitor: TerminalActionDescriptor(
      id: TerminalActionId.toggleActivityMonitor,
      label: 'toggle_activity_monitor',
      category: TerminalActionCategory.integration,
      icon: Icons.notifications,
      requiresActiveSession: true,
    ),
    TerminalActionId.exportScrollback: TerminalActionDescriptor(
      id: TerminalActionId.exportScrollback,
      label: 'export_scrollback',
      category: TerminalActionCategory.workspace,
      icon: Icons.ios_share,
      requiresActiveSession: true,
    ),
    TerminalActionId.exportDiagnostics: TerminalActionDescriptor(
      id: TerminalActionId.exportDiagnostics,
      label: 'export_diagnostics',
      category: TerminalActionCategory.workspace,
      icon: Icons.bug_report,
      requiresActiveSession: true,
    ),
    TerminalActionId.openThemePicker: TerminalActionDescriptor(
      id: TerminalActionId.openThemePicker,
      label: 'open_theme_picker',
      category: TerminalActionCategory.app,
      icon: Icons.palette,
      requiresActiveSession: false,
    ),
    TerminalActionId.applyTheme: TerminalActionDescriptor(
      id: TerminalActionId.applyTheme,
      label: 'apply_theme',
      category: TerminalActionCategory.app,
      icon: Icons.format_paint,
      requiresActiveSession: false,
    ),
    TerminalActionId.applyLayoutTemplate: TerminalActionDescriptor(
      id: TerminalActionId.applyLayoutTemplate,
      label: 'apply_layout_template',
      category: TerminalActionCategory.workspace,
      icon: Icons.dashboard,
      requiresActiveSession: false,
    ),
  };

  static bool has(TerminalActionId id) {
    return actions.containsKey(id);
  }

  static bool requiresActiveSession(TerminalActionId id) {
    return actions[id]?.requiresActiveSession ?? false;
  }

  static bool commandPaletteVisible(TerminalActionId id) {
    return actions[id]?.commandPaletteVisible ?? false;
  }

  static List<TerminalKeyBindingConflict> defaultKeyBindingConflicts() {
    final bindingsBySignature =
        <String, MapEntry<TerminalKeyBinding, Set<TerminalActionId>>>{};

    for (final entry in actions.entries) {
      final binding = entry.value.defaultKeyBinding;
      if (binding == null) {
        continue;
      }

      final existing = bindingsBySignature[binding.signature];
      if (existing == null) {
        bindingsBySignature[binding.signature] = MapEntry(
          binding,
          <TerminalActionId>{entry.key},
        );
        continue;
      }

      existing.value.add(entry.key);
    }

    return bindingsBySignature.values
        .where((entry) => entry.value.length > 1)
        .map(
          (entry) => TerminalKeyBindingConflict(
            binding: entry.key,
            actionIds: Set<TerminalActionId>.unmodifiable(entry.value),
          ),
        )
        .toList(growable: false);
  }
}
