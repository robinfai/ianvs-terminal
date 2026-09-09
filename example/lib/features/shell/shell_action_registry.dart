import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum TerminalActionId {
  openLauncher,
  openCommandMenu,
  newTab,
  newSshSession,
  openTerminalAtFolder,
  openRecording,
  duplicateCurrentCwd,
  reopenClosedTab,
  openSftpPanel,
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
  copyCommandOutput,
  paste,
  toggleReadOnly,
  toggleSessionRecording,
  clearBuffer,
  instantReplay,
  search,
  nextSearchMatch,
  previousSearchMatch,
  clearSearch,
  defaults,
  profiles,
  requestQuitConfirmation,
  previousPrompt,
  nextPrompt,
  exportScrollback,
  exportDiagnostics,
}

enum TerminalActionCategory {
  app,
  session,
  replay,
  pane,
  layout,
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
    TerminalActionId.newSshSession: TerminalActionDescriptor(
      id: TerminalActionId.newSshSession,
      label: 'new_ssh_session',
      category: TerminalActionCategory.app,
      commandPaletteVisible: false,
      shortcutHint: 'cmd+shift+T',
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.focusedApp,
        meta: true,
        shift: true,
        key: LogicalKeyboardKey.keyT,
      ),
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.dns_outlined,
      requiresActiveSession: false,
    ),
    TerminalActionId.openTerminalAtFolder: TerminalActionDescriptor(
      id: TerminalActionId.openTerminalAtFolder,
      label: 'new_tab_at_folder',
      category: TerminalActionCategory.app,
      icon: Icons.create_new_folder_outlined,
      requiresActiveSession: false,
    ),
    TerminalActionId.openRecording: TerminalActionDescriptor(
      id: TerminalActionId.openRecording,
      label: 'open_recording_for_replay',
      category: TerminalActionCategory.replay,
      icon: Icons.video_file_outlined,
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
    TerminalActionId.openSftpPanel: TerminalActionDescriptor(
      id: TerminalActionId.openSftpPanel,
      label: 'open_sftp_panel',
      category: TerminalActionCategory.integration,
      terminalInputPolicy: TerminalInputPolicy.appFirst,
      icon: Icons.folder_open,
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
      category: TerminalActionCategory.layout,
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
    TerminalActionId.copyCommandOutput: TerminalActionDescriptor(
      id: TerminalActionId.copyCommandOutput,
      label: 'copy_command_output',
      category: TerminalActionCategory.integration,
      icon: Icons.copy_all,
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
    TerminalActionId.toggleReadOnly: TerminalActionDescriptor(
      id: TerminalActionId.toggleReadOnly,
      label: 'toggle_read_only',
      category: TerminalActionCategory.session,
      icon: Icons.lock,
      requiresActiveSession: true,
    ),
    TerminalActionId.toggleSessionRecording: TerminalActionDescriptor(
      id: TerminalActionId.toggleSessionRecording,
      label: 'toggle_replay_recording',
      category: TerminalActionCategory.replay,
      icon: Icons.fiber_manual_record,
      requiresActiveSession: true,
    ),
    TerminalActionId.clearBuffer: TerminalActionDescriptor(
      id: TerminalActionId.clearBuffer,
      label: 'clear_buffer',
      category: TerminalActionCategory.layout,
      shortcutHint: 'cmd+K',
      defaultKeyBinding: TerminalKeyBinding(
        scope: TerminalKeyBindingScope.terminalFocused,
        meta: true,
        key: LogicalKeyboardKey.keyK,
      ),
      terminalInputPolicy: TerminalInputPolicy.performableOnly,
      icon: Icons.clear_all,
      requiresActiveSession: true,
    ),
    TerminalActionId.instantReplay: TerminalActionDescriptor(
      id: TerminalActionId.instantReplay,
      label: 'replay_recent_activity',
      category: TerminalActionCategory.replay,
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
    TerminalActionId.search: TerminalActionDescriptor(
      id: TerminalActionId.search,
      label: 'search_scrollback',
      category: TerminalActionCategory.layout,
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
      category: TerminalActionCategory.layout,
      icon: Icons.keyboard_arrow_down,
      requiresActiveSession: true,
    ),
    TerminalActionId.previousSearchMatch: TerminalActionDescriptor(
      id: TerminalActionId.previousSearchMatch,
      label: 'previous_search_match',
      category: TerminalActionCategory.layout,
      icon: Icons.keyboard_arrow_up,
      requiresActiveSession: true,
    ),
    TerminalActionId.clearSearch: TerminalActionDescriptor(
      id: TerminalActionId.clearSearch,
      label: 'clear_search',
      category: TerminalActionCategory.layout,
      icon: Icons.search_off,
      requiresActiveSession: true,
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
    TerminalActionId.exportScrollback: TerminalActionDescriptor(
      id: TerminalActionId.exportScrollback,
      label: 'export_scrollback',
      category: TerminalActionCategory.layout,
      icon: Icons.ios_share,
      requiresActiveSession: true,
    ),
    TerminalActionId.exportDiagnostics: TerminalActionDescriptor(
      id: TerminalActionId.exportDiagnostics,
      label: 'export_diagnostics',
      category: TerminalActionCategory.layout,
      icon: Icons.bug_report,
      requiresActiveSession: true,
    ),
  };

  static const Set<TerminalActionId> releaseActionIds = {
    TerminalActionId.openLauncher,
    TerminalActionId.openCommandMenu,
    TerminalActionId.newTab,
    TerminalActionId.newSshSession,
    TerminalActionId.openTerminalAtFolder,
    TerminalActionId.openRecording,
    TerminalActionId.duplicateCurrentCwd,
    TerminalActionId.reopenClosedTab,
    TerminalActionId.openSftpPanel,
    TerminalActionId.splitRight,
    TerminalActionId.splitDown,
    TerminalActionId.focusNextPane,
    TerminalActionId.focusPreviousPane,
    TerminalActionId.resizePane,
    TerminalActionId.swapPane,
    TerminalActionId.zoomPane,
    TerminalActionId.closePane,
    TerminalActionId.reopenClosedPane,
    TerminalActionId.closeActiveTab,
    TerminalActionId.openDefaults,
    TerminalActionId.activateTab,
    TerminalActionId.copy,
    TerminalActionId.copyCommandOutput,
    TerminalActionId.paste,
    TerminalActionId.toggleReadOnly,
    TerminalActionId.toggleSessionRecording,
    TerminalActionId.clearBuffer,
    TerminalActionId.instantReplay,
    TerminalActionId.search,
    TerminalActionId.nextSearchMatch,
    TerminalActionId.previousSearchMatch,
    TerminalActionId.clearSearch,
    TerminalActionId.defaults,
    TerminalActionId.profiles,
    TerminalActionId.requestQuitConfirmation,
    TerminalActionId.previousPrompt,
    TerminalActionId.nextPrompt,
    TerminalActionId.exportScrollback,
    TerminalActionId.exportDiagnostics,
  };

  static bool has(TerminalActionId id) {
    return actions.containsKey(id);
  }

  static bool requiresActiveSession(TerminalActionId id) {
    return actions[id]?.requiresActiveSession ?? false;
  }

  static bool commandPaletteVisible(TerminalActionId id) {
    final descriptor = actions[id];
    return descriptor != null &&
        hasUserEntryPoint(id) &&
        descriptor.commandPaletteVisible;
  }

  static bool hasUserEntryPoint(TerminalActionId id) {
    return actions.containsKey(id) && releaseActionIds.contains(id);
  }

  static List<TerminalKeyBindingConflict> defaultKeyBindingConflicts() {
    final bindingsBySignature =
        <String, MapEntry<TerminalKeyBinding, Set<TerminalActionId>>>{};

    for (final entry in actions.entries) {
      if (!hasUserEntryPoint(entry.key)) {
        continue;
      }
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
