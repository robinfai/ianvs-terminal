import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'defaults_appearance_dialog.dart';
import '../profiles/profile_editor.dart';
import '../profiles/profile_models.dart';
import '../sessions/session_controller.dart';
import '../sessions/session_state.dart';
import '../terminal/clipboard_bridge.dart';
import '../terminal/selection_controller.dart';
import '../terminal/terminal_input_controller.dart';
import '../terminal/terminal_viewport.dart';

enum _ShellLauncherAction { newTab, copy, paste }

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  final Map<String, SelectionController> _selectionControllers = {};
  final Map<String, FocusNode> _terminalFocusNodes = {};
  bool _isLauncherOpen = false;
  bool _isDefaultsOpen = false;

  bool get _usesMetaShortcuts {
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.iOS => true,
      _ => false,
    };
  }

  String _launcherShortcutLabel() {
    return _usesMetaShortcuts ? '⌘⇧P' : 'Ctrl+Shift+P';
  }

  String _newTabShortcutLabel() {
    return _usesMetaShortcuts ? '⌘T' : 'Ctrl+T';
  }

  String _sessionCopyShortcutLabel() {
    return _usesMetaShortcuts ? '⌘C' : 'Ctrl+C';
  }

  String _sessionPasteShortcutLabel() {
    return _usesMetaShortcuts ? '⌘V' : 'Ctrl+V';
  }

  void _restoreSessionFocus({
    required String? activeSessionIdBeforeOpen,
    required String? activeSessionIdAfterClose,
  }) {
    if (activeSessionIdBeforeOpen == null ||
        activeSessionIdAfterClose != activeSessionIdBeforeOpen) {
      return;
    }
    final focusNode = _terminalFocusNodes[activeSessionIdBeforeOpen];
    if (focusNode == null || !focusNode.canRequestFocus) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !focusNode.canRequestFocus) {
        return;
      }
      focusNode.requestFocus();
    });
  }

  TerminalProfile? _profileForId(
    List<TerminalProfile> profiles,
    String? profileId,
  ) {
    if (profiles.isEmpty) {
      return null;
    }
    for (final profile in profiles) {
      if (profile.id == profileId) {
        return profile;
      }
    }
    return null;
  }

  TerminalProfile? _effectiveDefaultProfileFor(
    List<TerminalProfile> profiles,
    String? effectiveDefaultProfileId,
  ) {
    return _profileForId(profiles, effectiveDefaultProfileId) ??
        (profiles.isEmpty ? null : profiles.first);
  }

  String _defaultSummary(
    List<TerminalProfile> profiles,
    String? configuredDefaultProfileId,
    String? effectiveDefaultProfileId,
  ) {
    final effectiveProfile = _effectiveDefaultProfileFor(
      profiles,
      effectiveDefaultProfileId,
    );
    if (configuredDefaultProfileId == null) {
      return 'Fallback default • ${effectiveProfile?.name ?? 'No profile available'}';
    }
    final configuredProfile = _profileForId(
      profiles,
      configuredDefaultProfileId,
    );
    return 'Configured default • ${configuredProfile?.name ?? effectiveProfile?.name ?? 'No profile available'}';
  }

  Future<void> _openDefaultsAndAppearance(
    BuildContext context,
    SessionController sessionController,
    SessionState sessionState,
  ) async {
    if (_isDefaultsOpen) {
      return;
    }

    setState(() {
      _isDefaultsOpen = true;
    });

    final activeSessionIdBeforeOpen = sessionState.activeSessionId;
    final selection = await showDialog<DefaultsAndAppearanceSelection>(
      context: context,
      barrierDismissible: true,
      requestFocus: true,
      builder: (dialogContext) => DefaultsAndAppearanceDialog(
        profiles: sessionState.profiles,
        configuredDefaultProfileId: sessionState.configuredDefaultProfileId,
        effectiveDefaultProfileId: sessionState.defaultProfileId,
        themeMode: sessionState.themeMode,
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isDefaultsOpen = false;
    });

    final stateBeforeSave = ref.read(sessionControllerProvider);
    if (selection != null) {
      if (selection.configuredDefaultProfileId !=
          stateBeforeSave.configuredDefaultProfileId) {
        if (selection.configuredDefaultProfileId == null) {
          await sessionController.resetDefaultProfile();
        } else {
          await sessionController.setDefaultProfile(
            selection.configuredDefaultProfileId!,
          );
        }
      }
      if (selection.themeMode != stateBeforeSave.themeMode) {
        await sessionController.setThemeMode(selection.themeMode);
      }
    }

    _restoreSessionFocus(
      activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
      activeSessionIdAfterClose: ref
          .read(sessionControllerProvider)
          .activeSessionId,
    );
  }

  Future<void> _copySelection(
    SessionController sessionController,
    String sessionId,
    SelectionController selectionController,
  ) async {
    final text = selectionController.textForFrame(
      sessionController.viewportFor(sessionId).frame,
    );
    if (text.isEmpty) {
      return;
    }
    await ClipboardBridge.copy(text);
  }

  Future<void> _pasteToSession(String sessionId) async {
    final text = await ClipboardBridge.paste();
    if (text.isEmpty) {
      return;
    }
    ref
        .read(terminalCoreClientProvider)
        .sendInput(sessionId, Uint8List.fromList(utf8.encode(text)));
  }

  Future<void> _openTopActionsLauncher(
    BuildContext context,
    SessionController sessionController,
    List<TerminalProfile> profiles,
    String? defaultProfileId,
  ) async {
    final defaultProfile = _effectiveDefaultProfileFor(
      profiles,
      defaultProfileId,
    );
    if (_isLauncherOpen || defaultProfile == null) {
      return;
    }

    setState(() {
      _isLauncherOpen = true;
    });

    final stateBeforeOpen = ref.read(sessionControllerProvider);
    final activeSessionIdBeforeOpen = stateBeforeOpen.activeSessionId;
    final hasActiveSession = activeSessionIdBeforeOpen != null;
    final action = await showDialog<_ShellLauncherAction>(
      context: context,
      barrierDismissible: true,
      requestFocus: true,
      builder: (dialogContext) {
        Widget actionTile({
          required IconData icon,
          required String title,
          required String subtitle,
          required _ShellLauncherAction value,
          required bool enabled,
          required String shortcutLabel,
        }) {
          return ListTile(
            leading: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: Text(
              shortcutLabel,
              style: Theme.of(dialogContext).textTheme.labelMedium?.copyWith(
                color: enabled
                    ? const Color(0xFF4B5563)
                    : const Color(0xFF9CA3AF),
                fontWeight: FontWeight.w700,
              ),
            ),
            enabled: enabled,
            onTap: enabled
                ? () => Navigator.of(dialogContext).pop(value)
                : null,
          );
        }

        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360, maxHeight: 420),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Top actions',
                            style: Theme.of(dialogContext).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close actions',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'App actions',
                        style: Theme.of(dialogContext).textTheme.labelLarge
                            ?.copyWith(
                              color: const Color(0xFF6B7280),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    actionTile(
                      icon: Icons.add_box_outlined,
                      title: 'New tab',
                      subtitle: 'App action • Open your default shell profile.',
                      value: _ShellLauncherAction.newTab,
                      enabled: true,
                      shortcutLabel: _newTabShortcutLabel(),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Session actions',
                        style: Theme.of(dialogContext).textTheme.labelLarge
                            ?.copyWith(
                              color: const Color(0xFF6B7280),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    if (!hasActiveSession)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Requires an active shell session.',
                            style: Theme.of(dialogContext).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFF6B7280)),
                          ),
                        ),
                      ),
                    actionTile(
                      icon: Icons.copy_rounded,
                      title: 'Copy selection',
                      subtitle:
                          'Session action • Copy the current terminal selection.',
                      value: _ShellLauncherAction.copy,
                      enabled: hasActiveSession,
                      shortcutLabel: _sessionCopyShortcutLabel(),
                    ),
                    actionTile(
                      icon: Icons.content_paste_rounded,
                      title: 'Paste clipboard',
                      subtitle:
                          'Session action • Send clipboard text to the active shell.',
                      value: _ShellLauncherAction.paste,
                      enabled: hasActiveSession,
                      shortcutLabel: _sessionPasteShortcutLabel(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _isLauncherOpen = false;
    });

    final currentState = ref.read(sessionControllerProvider);
    final currentSessionId = currentState.activeSessionId;
    switch (action) {
      case _ShellLauncherAction.newTab:
        sessionController.createSession(defaultProfile);
        return;
      case _ShellLauncherAction.copy:
        if (currentSessionId == null) {
          return;
        }
        final selectionController = _selectionControllers[currentSessionId];
        if (selectionController == null) {
          return;
        }
        await _copySelection(
          sessionController,
          currentSessionId,
          selectionController,
        );
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case _ShellLauncherAction.paste:
        if (currentSessionId == null) {
          return;
        }
        await _pasteToSession(currentSessionId);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case null:
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(sessionControllerProvider);
    final sessionController = ref.read(sessionControllerProvider.notifier);
    final activeSessionId = sessionState.activeSessionId;
    final defaultProfile = _effectiveDefaultProfileFor(
      sessionState.profiles,
      sessionState.defaultProfileId,
    );
    final defaultSummary = _defaultSummary(
      sessionState.profiles,
      sessionState.configuredDefaultProfileId,
      sessionState.defaultProfileId,
    );
    final themeSummary = 'Theme • ${themeModeLabel(sessionState.themeMode)}';
    final activeSelectionController = activeSessionId == null
        ? null
        : _selectionControllers.putIfAbsent(
            activeSessionId,
            SelectionController.new,
          );
    final activeFocusNode = activeSessionId == null
        ? null
        : _terminalFocusNodes.putIfAbsent(
            activeSessionId,
            () => FocusNode(debugLabel: 'shell-terminal-$activeSessionId'),
          );

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
        final isControlPressed = HardwareKeyboard.instance.isControlPressed;
        final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
        final isLauncherShortcut =
            (isMetaPressed || isControlPressed) &&
            isShiftPressed &&
            event.logicalKey == LogicalKeyboardKey.keyP;
        final isNewTabShortcut =
            (isMetaPressed || isControlPressed) &&
            event.logicalKey == LogicalKeyboardKey.keyT;

        if (_isDefaultsOpen && (isLauncherShortcut || isNewTabShortcut)) {
          return KeyEventResult.handled;
        }

        if (isLauncherShortcut) {
          _openTopActionsLauncher(
            context,
            sessionController,
            sessionState.profiles,
            sessionState.defaultProfileId,
          );
          return KeyEventResult.handled;
        }

        if (isNewTabShortcut) {
          if (_isLauncherOpen || defaultProfile == null) {
            return KeyEventResult.handled;
          }
          sessionController.createSession(defaultProfile);
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: Scaffold(
        body: Row(
          children: [
            _Sidebar(
              profiles: sessionState.profiles,
              defaultProfileId: sessionState.defaultProfileId,
              configuredDefaultProfileId:
                  sessionState.configuredDefaultProfileId,
              onCreateSession: sessionController.createSession,
              onEditProfile: (profile) async {
                final result = await showDialog<TerminalProfile>(
                  context: context,
                  builder: (context) =>
                      ProfileEditorDialog(initialValue: profile),
                );
                if (result != null) {
                  await sessionController.saveProfile(result);
                }
              },
              onShowDefaults: () => _openDefaultsAndAppearance(
                context,
                sessionController,
                sessionState,
              ),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFE7E1D4), Color(0xFFF7F4EA)],
                  ),
                ),
                child: Column(
                  children: [
                    if (activeSessionId != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: _ShellPanel(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const _ShellSectionLabel('Workspace'),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Shell workspace',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              color: const Color(0xFF111827),
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _sessionSummary(
                                          sessionState.tabs.length,
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: const Color(0xFF4B5563),
                                            ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Active session',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              color: const Color(0xFF6B7280),
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        defaultSummary,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: const Color(0xFF4B5563),
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        themeSummary,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: const Color(0xFF4B5563),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Tooltip(
                                  message:
                                      'Open top actions (${_launcherShortcutLabel()})',
                                  child: FilledButton.tonalIcon(
                                    onPressed: defaultProfile == null
                                        ? null
                                        : () => _openTopActionsLauncher(
                                            context,
                                            sessionController,
                                            sessionState.profiles,
                                            sessionState.defaultProfileId,
                                          ),
                                    icon: const Icon(Icons.apps_rounded),
                                    label: const Text('Actions'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (sessionState.tabs.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _ShellPanel(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    const _ShellSectionLabel('Session tabs'),
                                    const Spacer(),
                                    Text(
                                      '${sessionState.tabs.length} open',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF6B7280),
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 40,
                                  child: ListView(
                                    scrollDirection: Axis.horizontal,
                                    children: [
                                      for (final tab in sessionState.tabs)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          child: InputChip(
                                            selected:
                                                tab.sessionId ==
                                                activeSessionId,
                                            showCheckmark: false,
                                            backgroundColor: const Color(
                                              0xFFF3F4F6,
                                            ),
                                            selectedColor: const Color(
                                              0xFFE5E7EB,
                                            ),
                                            label: Text(tab.title),
                                            labelStyle: TextStyle(
                                              color:
                                                  tab.sessionId ==
                                                      activeSessionId
                                                  ? const Color(0xFF111827)
                                                  : const Color(0xFF4B5563),
                                              fontWeight:
                                                  tab.sessionId ==
                                                      activeSessionId
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                            ),
                                            onPressed: () => sessionController
                                                .activateSession(tab.sessionId),
                                            onDeleted: () => sessionController
                                                .closeSession(tab.sessionId),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: activeSessionId == null
                            ? Center(
                                child: _ShellPanel(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const _ShellSectionLabel(
                                          'Ready when you are',
                                        ),
                                        const SizedBox(height: 12),
                                        const Text(
                                          'Create a shell to get started',
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Reopen your default profile in one step.',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: const Color(0xFF4B5563),
                                              ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          defaultSummary,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: const Color(0xFF374151),
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          themeSummary,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: const Color(0xFF4B5563),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (mounted) {
                                      sessionController.resizeActiveSession(
                                        Size(
                                          constraints.maxWidth,
                                          constraints.maxHeight,
                                        ),
                                        MediaQuery.devicePixelRatioOf(context),
                                      );
                                    }
                                  });

                                  final selectionController =
                                      activeSelectionController!;
                                  final inputController =
                                      TerminalInputController(
                                        sessionId: activeSessionId,
                                        coreClient: ref.read(
                                          terminalCoreClientProvider,
                                        ),
                                        readSelection: () =>
                                            selectionController.textForFrame(
                                              sessionController
                                                  .viewportFor(activeSessionId)
                                                  .frame,
                                            ),
                                        copySelection: (text) =>
                                            ClipboardBridge.copy(text),
                                        readClipboard: ClipboardBridge.paste,
                                      );

                                  return Column(
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          child: DecoratedBox(
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF111827),
                                            ),
                                            child: TerminalViewport(
                                              focusNode: activeFocusNode,
                                              controller: sessionController
                                                  .viewportFor(activeSessionId),
                                              selectionController:
                                                  selectionController,
                                              inputController: inputController,
                                              onScrollLines: (delta) {
                                                ref
                                                    .read(
                                                      terminalCoreClientProvider,
                                                    )
                                                    .scrollViewport(
                                                      activeSessionId,
                                                      delta,
                                                    );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          FilledButton.tonal(
                                            onPressed: () => _copySelection(
                                              sessionController,
                                              activeSessionId,
                                              selectionController,
                                            ),
                                            child: const Text('Copy'),
                                          ),
                                          const SizedBox(width: 8),
                                          FilledButton.tonal(
                                            onPressed: () => _pasteToSession(
                                              activeSessionId,
                                            ),
                                            child: const Text('Paste'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: sessionState.profiles.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: defaultProfile == null
                    ? null
                    : () => sessionController.createSession(defaultProfile),
                label: const Text('New Tab'),
                icon: const Icon(Icons.add),
              ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.profiles,
    required this.defaultProfileId,
    required this.configuredDefaultProfileId,
    required this.onCreateSession,
    required this.onEditProfile,
    required this.onShowDefaults,
  });

  final List<TerminalProfile> profiles;
  final String? defaultProfileId;
  final String? configuredDefaultProfileId;
  final ValueChanged<TerminalProfile> onCreateSession;
  final ValueChanged<TerminalProfile> onEditProfile;
  final VoidCallback onShowDefaults;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF1F2937)),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'flutterm',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFFFDE68A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Profiles',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFF9FAFB),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onShowDefaults,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF9FAFB),
                      side: const BorderSide(color: Color(0xFF4B5563)),
                    ),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Defaults & appearance'),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: profiles.length,
                    itemBuilder: (context, index) {
                      final profile = profiles[index];
                      return Card(
                        color: const Color(0xFF374151),
                        child: ListTile(
                          title: Text(
                            profile.name,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            profile.id == defaultProfileId
                                ? configuredDefaultProfileId == profile.id
                                      ? '${profile.shell} • Configured default'
                                      : '${profile.shell} • Fallback default'
                                : profile.shell,
                            style: const TextStyle(color: Color(0xFFD1D5DB)),
                          ),
                          trailing: IconButton(
                            tooltip: 'Edit profile',
                            onPressed: () => onEditProfile(profile),
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: Color(0xFFD1D5DB),
                            ),
                          ),
                          leading: Icon(
                            profile.id == defaultProfileId
                                ? Icons.star
                                : Icons.terminal,
                            color: profile.id == defaultProfileId
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFF93C5FD),
                          ),
                          onTap: () => onCreateSession(profile),
                        ),
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

class _ShellPanel extends StatelessWidget {
  const _ShellPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }
}

class _ShellSectionLabel extends StatelessWidget {
  const _ShellSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: const Color(0xFF6B7280),
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }
}

String _sessionSummary(int count) {
  if (count == 1) {
    return '1 active session';
  }
  return '$count active sessions';
}
