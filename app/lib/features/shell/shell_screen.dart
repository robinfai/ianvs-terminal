import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../profiles/profile_editor.dart';
import '../profiles/profile_models.dart';
import '../sessions/session_controller.dart';
import '../sessions/session_state.dart';
import '../terminal/clipboard_bridge.dart';
import '../terminal/selection_controller.dart';
import '../terminal/terminal_input_controller.dart';
import '../terminal/terminal_viewport.dart';
import 'defaults_appearance_dialog.dart';
import 'package:app/features/shell/shell_acceptance.dart';
import 'reference_demo.dart';

enum _ShellCommandAction { newTab, copy, paste, defaults, profiles }

final shellAnimationsEnabledProvider = Provider<bool>((ref) => true);

sealed class _ProfilesSheetResult {
  const _ProfilesSheetResult();
}

final class _OpenProfileResult extends _ProfilesSheetResult {
  const _OpenProfileResult(this.profile);

  final TerminalProfile profile;
}

final class _EditProfileResult extends _ProfilesSheetResult {
  const _EditProfileResult(this.profile);

  final TerminalProfile profile;
}

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  final Map<String, SelectionController> _selectionControllers = {};
  final Map<String, FocusNode> _terminalFocusNodes = {};
  final Map<String, Size> _scheduledViewportSizes = {};
  bool _isCommandMenuOpen = false;
  bool _isDefaultsOpen = false;
  bool _isProfilesOpen = false;

  String get _visibleOverlay {
    if (_isDefaultsOpen) {
      return 'defaults';
    }
    if (_isProfilesOpen) {
      return 'profiles';
    }
    if (_isCommandMenuOpen) {
      return 'commandMenu';
    }
    return 'none';
  }

  void _publishAcceptanceSnapshot([SessionState? state]) {
    final SessionState snapshotState =
        state ?? ref.read(sessionControllerProvider);
    final activeSessionId = snapshotState.activeSessionId;
    final terminalRows = activeSessionId == null
        ? const []
        : ref
              .read(sessionControllerProvider.notifier)
              .viewportFor(activeSessionId)
              .frame
              .rows;
    String? terminalPreview;
    for (final row in terminalRows) {
      final text = row.text.trim();
      if (text.isNotEmpty) {
        terminalPreview = text;
        break;
      }
    }
    shellAcceptanceProbe.update(
      ShellAcceptanceSnapshot(
        commandMenuOpen: _isCommandMenuOpen,
        defaultsOpen: _isDefaultsOpen,
        profilesOpen: _isProfilesOpen,
        visibleOverlay: _visibleOverlay,
        terminalHasVisibleContent: terminalPreview != null,
        terminalPreview: terminalPreview,
        activeTabCount: snapshotState.tabs.length,
        activeSessionId: activeSessionId,
        themeMode: snapshotState.themeMode.name,
        snapshotVersion: shellAcceptanceProbe.current.snapshotVersion,
      ),
    );
  }

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

  void _focusSession(String? sessionId) {
    if (sessionId == null) {
      return;
    }
    final focusNode = _terminalFocusNodes[sessionId];
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

  void _restoreSessionFocus({
    required String? activeSessionIdBeforeOpen,
    required String? activeSessionIdAfterClose,
  }) {
    if (activeSessionIdBeforeOpen == null ||
        activeSessionIdAfterClose != activeSessionIdBeforeOpen) {
      return;
    }
    _focusSession(activeSessionIdBeforeOpen);
  }

  TerminalProfile? _profileForId(
    List<TerminalProfile> profiles,
    String? profileId,
  ) {
    if (profiles.isEmpty || profileId == null) {
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

  Future<void> _openDefaultsAndAppearance(
    SessionController sessionController,
    SessionState sessionState,
  ) async {
    if (_isDefaultsOpen) {
      return;
    }

    setState(() {
      _isDefaultsOpen = true;
    });
    _publishAcceptanceSnapshot(sessionState);

    final activeSessionIdBeforeOpen = sessionState.activeSessionId;
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    final selection = await showDialog<DefaultsAndAppearanceSelection>(
      context: context,
      barrierDismissible: true,
      requestFocus: true,
      animationStyle: animationsEnabled ? null : AnimationStyle.noAnimation,
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
    _publishAcceptanceSnapshot();

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

  Future<void> _openProfilesSheet(
    SessionController sessionController,
    SessionState sessionState,
  ) async {
    if (_isProfilesOpen) {
      return;
    }

    setState(() {
      _isProfilesOpen = true;
    });
    _publishAcceptanceSnapshot(sessionState);

    final activeSessionIdBeforeOpen = sessionState.activeSessionId;
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    final result = await showModalBottomSheet<_ProfilesSheetResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return _ProfilesSheet(
          profiles: sessionState.profiles,
          effectiveDefaultProfileId: sessionState.defaultProfileId,
        );
      },
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isProfilesOpen = false;
    });
    _publishAcceptanceSnapshot();

    switch (result) {
      case _OpenProfileResult(:final profile):
        sessionController.createSession(profile);
        _focusSession(ref.read(sessionControllerProvider).activeSessionId);
        return;
      case _EditProfileResult(:final profile):
        final edited = await showDialog<TerminalProfile>(
          context: context,
          builder: (dialogContext) =>
              ProfileEditorDialog(initialValue: profile),
        );
        if (edited != null) {
          await sessionController.saveProfile(edited);
        }
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: ref
              .read(sessionControllerProvider)
              .activeSessionId,
        );
        return;
      case null:
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: ref
              .read(sessionControllerProvider)
              .activeSessionId,
        );
        return;
    }
  }

  Future<void> _openCommandMenu(
    SessionController sessionController,
    SessionState sessionState,
  ) async {
    final defaultProfile = _effectiveDefaultProfileFor(
      sessionState.profiles,
      sessionState.defaultProfileId,
    );
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    if (_isCommandMenuOpen) {
      return;
    }

    setState(() {
      _isCommandMenuOpen = true;
    });
    _publishAcceptanceSnapshot(sessionState);

    final activeSessionIdBeforeOpen = sessionState.activeSessionId;
    final hasActiveSession = activeSessionIdBeforeOpen != null;
    final action = await showGeneralDialog<_ShellCommandAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close command menu',
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: animationsEnabled
          ? const Duration(milliseconds: 160)
          : Duration.zero,
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
      transitionBuilder: (dialogContext, animation, _, child) {
        if (!animationsEnabled) {
          return SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 10, right: 14),
                child: _ShellCommandMenu(
                  launcherShortcutLabel: _launcherShortcutLabel(),
                  newTabShortcutLabel: _newTabShortcutLabel(),
                  sessionCopyShortcutLabel: _sessionCopyShortcutLabel(),
                  sessionPasteShortcutLabel: _sessionPasteShortcutLabel(),
                  hasDefaultProfile: defaultProfile != null,
                  hasActiveSession: hasActiveSession,
                ),
              ),
            ),
          );
        }
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 10, right: 14),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -0.03),
                    end: Offset.zero,
                  ).animate(curved),
                  child: _ShellCommandMenu(
                    launcherShortcutLabel: _launcherShortcutLabel(),
                    newTabShortcutLabel: _newTabShortcutLabel(),
                    sessionCopyShortcutLabel: _sessionCopyShortcutLabel(),
                    sessionPasteShortcutLabel: _sessionPasteShortcutLabel(),
                    hasDefaultProfile: defaultProfile != null,
                    hasActiveSession: hasActiveSession,
                  ),
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
      _isCommandMenuOpen = false;
    });
    _publishAcceptanceSnapshot();

    final currentState = ref.read(sessionControllerProvider);
    final currentSessionId = currentState.activeSessionId;
    switch (action) {
      case _ShellCommandAction.newTab:
        if (defaultProfile == null) {
          return;
        }
        sessionController.createSession(defaultProfile);
        _focusSession(ref.read(sessionControllerProvider).activeSessionId);
        return;
      case _ShellCommandAction.copy:
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
      case _ShellCommandAction.paste:
        if (currentSessionId == null) {
          return;
        }
        await _pasteToSession(currentSessionId);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: currentSessionId,
        );
        return;
      case _ShellCommandAction.defaults:
        await _openDefaultsAndAppearance(sessionController, sessionState);
        return;
      case _ShellCommandAction.profiles:
        await _openProfilesSheet(sessionController, sessionState);
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
    final referenceDemoMode = ref.watch(referenceDemoModeProvider);
    _publishAcceptanceSnapshot(sessionState);
    final animationsEnabled = ref.watch(shellAnimationsEnabledProvider);
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
    final palette = _ShellPalette.fromBrightness(Theme.of(context).brightness);

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

        if ((_isDefaultsOpen || _isProfilesOpen) &&
            (isLauncherShortcut || isNewTabShortcut)) {
          return KeyEventResult.handled;
        }

        if (isLauncherShortcut) {
          _openCommandMenu(sessionController, sessionState);
          return KeyEventResult.handled;
        }

        if (isNewTabShortcut) {
          if (_isCommandMenuOpen || defaultProfile == null) {
            return KeyEventResult.handled;
          }
          sessionController.createSession(defaultProfile);
          _focusSession(ref.read(sessionControllerProvider).activeSessionId);
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: palette.background,
        body: ColoredBox(
          color: palette.background,
          child: Padding(
            padding: EdgeInsets.only(
              top: defaultTargetPlatform == TargetPlatform.macOS
                  ? 8
                  : MediaQuery.paddingOf(context).top + 8,
            ),
            child: Column(
              children: [
                _ShellChromeBar(
                  palette: palette,
                  tabs: sessionState.tabs,
                  activeSessionId: activeSessionId,
                  referenceDemoMode: referenceDemoMode,
                  onActivateSession: sessionController.activateSession,
                  onCloseSession: sessionController.closeSession,
                  onShowCommandMenu: () =>
                      _openCommandMenu(sessionController, sessionState),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: animationsEnabled
                        ? const Duration(milliseconds: 160)
                        : Duration.zero,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: activeSessionId == null
                        ? _ShellEmptyState(
                            key: const Key('shell-empty-state'),
                            palette: palette,
                            defaultSummary: defaultSummary,
                            onNewTab: defaultProfile == null
                                ? null
                                : () {
                                    sessionController.createSession(
                                      defaultProfile,
                                    );
                                    _focusSession(
                                      ref
                                          .read(sessionControllerProvider)
                                          .activeSessionId,
                                    );
                                  },
                          )
                        : LayoutBuilder(
                            key: ValueKey(activeSessionId),
                            builder: (context, constraints) {
                              final viewportSize = Size(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              );
                              final scheduledSize =
                                  _scheduledViewportSizes[activeSessionId];
                              if (scheduledSize != viewportSize) {
                                _scheduledViewportSizes[activeSessionId] =
                                    viewportSize;
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted) {
                                    sessionController.resizeActiveSession(
                                      viewportSize,
                                      MediaQuery.devicePixelRatioOf(context),
                                    );
                                  }
                                });
                              }

                              final selectionController =
                                  activeSelectionController!;
                              final inputController = TerminalInputController(
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

                              return RepaintBoundary(
                                key: const Key('shell-terminal-surface'),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: palette.terminalBackground,
                                    border: Border(
                                      top: BorderSide(color: palette.divider),
                                    ),
                                  ),
                                  child: TerminalViewport(
                                    focusNode: activeFocusNode,
                                    controller: sessionController.viewportFor(
                                      activeSessionId,
                                    ),
                                    selectionController: selectionController,
                                    inputController: inputController,
                                    onScrollLines: (delta) {
                                      ref
                                          .read(terminalCoreClientProvider)
                                          .scrollViewport(
                                            activeSessionId,
                                            delta,
                                          );
                                    },
                                    onScrollToOffset: (offset) {
                                      ref
                                          .read(terminalCoreClientProvider)
                                          .scrollViewportTo(
                                            activeSessionId,
                                            offset,
                                          );
                                    },
                                  ),
                                ),
                              );
                            },
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

class _ShellChromeBar extends StatelessWidget {
  const _ShellChromeBar({
    required this.palette,
    required this.tabs,
    required this.activeSessionId,
    required this.referenceDemoMode,
    required this.onActivateSession,
    required this.onCloseSession,
    required this.onShowCommandMenu,
  });

  final _ShellPalette palette;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final bool referenceDemoMode;
  final ValueChanged<String> onActivateSession;
  final ValueChanged<String> onCloseSession;
  final VoidCallback onShowCommandMenu;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('shell-chrome-bar'),
      decoration: BoxDecoration(
        color: palette.chromeBackground,
        border: Border(bottom: BorderSide(color: palette.divider)),
      ),
      child: SizedBox(
        height: 42,
        child: Row(
          children: [
            const SizedBox(width: 72),
            Expanded(
              child: referenceDemoMode
                  ? _ReferenceDemoTabStrip(
                      palette: palette,
                      tabs: tabs,
                      activeSessionId: activeSessionId,
                      onActivateSession: onActivateSession,
                    )
                  : _ShellTabStrip(
                      palette: palette,
                      tabs: tabs,
                      activeSessionId: activeSessionId,
                      onActivateSession: onActivateSession,
                      onCloseSession: onCloseSession,
                    ),
            ),
            if (!referenceDemoMode) ...[
              IconButton(
                key: const Key('shell-chrome-menu'),
                tooltip: 'Open command menu',
                onPressed: onShowCommandMenu,
                visualDensity: VisualDensity.compact,
                splashRadius: 16,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                iconSize: 18,
                icon: Icon(Icons.tune_rounded, color: palette.subtleText),
              ),
              const SizedBox(width: 8),
            ] else
              const SizedBox(width: 24),
          ],
        ),
      ),
    );
  }
}

class _ReferenceDemoTabStrip extends StatelessWidget {
  const _ReferenceDemoTabStrip({
    required this.palette,
    required this.tabs,
    required this.activeSessionId,
    required this.onActivateSession,
  });

  final _ShellPalette palette;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final ValueChanged<String> onActivateSession;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('shell-tab-strip'),
      children: [
        for (var index = 0; index < tabs.length; index++) ...[
          Expanded(
            child: _ReferenceDemoTab(
              palette: palette,
              tab: tabs[index],
              isActive: tabs[index].sessionId == activeSessionId,
              onActivate: () => onActivateSession(tabs[index].sessionId),
            ),
          ),
          if (index < tabs.length - 1)
            SizedBox(
              width: 1,
              height: double.infinity,
              child: ColoredBox(color: palette.divider),
            ),
        ],
      ],
    );
  }
}

class _ReferenceDemoTab extends StatelessWidget {
  const _ReferenceDemoTab({
    required this.palette,
    required this.tab,
    required this.isActive,
    required this.onActivate,
  });

  final _ShellPalette palette;
  final TerminalTab tab;
  final bool isActive;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'shell-tab-${tab.sessionId}',
      selected: isActive,
      button: true,
      child: TextButton(
        key: Key('shell-tab-${tab.sessionId}'),
        onPressed: onActivate,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: isActive ? palette.primaryText : palette.mutedText,
          shape: const RoundedRectangleBorder(),
        ),
        child: Center(
          child: Text(
            tab.title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: isActive ? palette.primaryText : palette.subtleText,
              fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellTabStrip extends StatelessWidget {
  const _ShellTabStrip({
    required this.palette,
    required this.tabs,
    required this.activeSessionId,
    required this.onActivateSession,
    required this.onCloseSession,
  });

  final _ShellPalette palette;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final ValueChanged<String> onActivateSession;
  final ValueChanged<String> onCloseSession;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('shell-tab-strip'),
      height: double.infinity,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => Container(
          width: 1,
          margin: const EdgeInsets.symmetric(vertical: 8),
          color: palette.divider,
        ),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final isActive = tab.sessionId == activeSessionId;
          return _ShellTabButton(
            palette: palette,
            tab: tab,
            isActive: isActive,
            onActivate: () => onActivateSession(tab.sessionId),
            onClose: () => onCloseSession(tab.sessionId),
          );
        },
      ),
    );
  }
}

class _ShellTabButton extends StatelessWidget {
  const _ShellTabButton({
    required this.palette,
    required this.tab,
    required this.isActive,
    required this.onActivate,
    required this.onClose,
  });

  final _ShellPalette palette;
  final TerminalTab tab;
  final bool isActive;
  final VoidCallback onActivate;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'shell-tab-${tab.sessionId}',
      selected: isActive,
      button: true,
      child: TextButton(
        key: Key('shell-tab-${tab.sessionId}'),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: isActive ? palette.primaryText : palette.mutedText,
          shape: const RoundedRectangleBorder(),
        ),
        onPressed: onActivate,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 140),
              style: Theme.of(context).textTheme.titleSmall!.copyWith(
                color: isActive ? palette.primaryText : palette.mutedText,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
              child: Text(tab.title, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'Close ${tab.title}',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: Icon(
                  Icons.close_rounded,
                  size: 12,
                  color: isActive
                      ? palette.mutedText
                      : palette.subtleText.withValues(alpha: 0.72),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellEmptyState extends StatelessWidget {
  const _ShellEmptyState({
    super.key,
    required this.palette,
    required this.defaultSummary,
    required this.onNewTab,
  });

  final _ShellPalette palette;
  final String defaultSummary;
  final VoidCallback? onNewTab;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.terminalBackground,
        border: Border(top: BorderSide(color: palette.divider)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No active sessions',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: palette.primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Open a new tab to start a shell session.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.mutedText,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Text(
                  defaultSummary,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.subtleText,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('shell-empty-new-tab'),
                  onPressed: onNewTab,
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('New Tab'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellCommandMenu extends StatelessWidget {
  const _ShellCommandMenu({
    required this.launcherShortcutLabel,
    required this.newTabShortcutLabel,
    required this.sessionCopyShortcutLabel,
    required this.sessionPasteShortcutLabel,
    required this.hasDefaultProfile,
    required this.hasActiveSession,
  });

  final String launcherShortcutLabel;
  final String newTabShortcutLabel;
  final String sessionCopyShortcutLabel;
  final String sessionPasteShortcutLabel;
  final bool hasDefaultProfile;
  final bool hasActiveSession;

  @override
  Widget build(BuildContext context) {
    final palette = _ShellPalette.fromBrightness(Theme.of(context).brightness);

    Widget sectionLabel(String text) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: palette.subtleText,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.24,
            ),
          ),
        ),
      );
    }

    return Material(
      key: const Key('shell-command-menu-overlay'),
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 500),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.overlayBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.divider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Top actions',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: palette.primaryText,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close actions',
                          onPressed: () => Navigator.of(context).pop(),
                          visualDensity: VisualDensity.compact,
                          splashRadius: 16,
                          icon: Icon(
                            Icons.close_rounded,
                            color: palette.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  sectionLabel('App actions'),
                  _ShellCommandTile(
                    key: const Key('shell-new-tab'),
                    icon: Icons.add_box_outlined,
                    title: 'New tab',
                    subtitle: 'App action • Open the default shell profile.',
                    shortcutLabel: newTabShortcutLabel,
                    enabled: hasDefaultProfile,
                    onTap: () =>
                        Navigator.of(context).pop(_ShellCommandAction.newTab),
                  ),
                  _ShellCommandTile(
                    key: const Key('shell-command-defaults'),
                    icon: Icons.tune_rounded,
                    title: 'Defaults & appearance',
                    subtitle:
                        'App action • Pick the default profile and theme.',
                    enabled: true,
                    onTap: () =>
                        Navigator.of(context).pop(_ShellCommandAction.defaults),
                  ),
                  _ShellCommandTile(
                    key: const Key('shell-command-profiles'),
                    icon: Icons.folder_open_rounded,
                    title: 'Profiles…',
                    subtitle: 'App action • Open or edit shell profiles.',
                    enabled: true,
                    onTap: () =>
                        Navigator.of(context).pop(_ShellCommandAction.profiles),
                  ),
                  sectionLabel('Session actions'),
                  if (!hasActiveSession)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Requires an active shell session.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.subtleText),
                        ),
                      ),
                    ),
                  _ShellCommandTile(
                    icon: Icons.copy_rounded,
                    title: 'Copy selection',
                    subtitle: 'Session action • Copy the current selection.',
                    shortcutLabel: sessionCopyShortcutLabel,
                    enabled: hasActiveSession,
                    onTap: () =>
                        Navigator.of(context).pop(_ShellCommandAction.copy),
                  ),
                  _ShellCommandTile(
                    icon: Icons.content_paste_rounded,
                    title: 'Paste clipboard',
                    subtitle:
                        'Session action • Paste clipboard into the shell.',
                    shortcutLabel: sessionPasteShortcutLabel,
                    enabled: hasActiveSession,
                    onTap: () =>
                        Navigator.of(context).pop(_ShellCommandAction.paste),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.keyboard_command_key_rounded,
                          size: 16,
                          color: palette.subtleText,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Open command menu with $launcherShortcutLabel',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: palette.subtleText),
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
      ),
    );
  }
}

class _ShellCommandTile extends StatelessWidget {
  const _ShellCommandTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    this.shortcutLabel,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final String? shortcutLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = _ShellPalette.fromBrightness(Theme.of(context).brightness);
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(
        icon,
        color: enabled ? palette.primaryText : palette.subtleText,
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: enabled ? palette.primaryText : palette.subtleText,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: palette.subtleText),
      ),
      trailing: shortcutLabel == null
          ? null
          : Text(
              shortcutLabel!,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: enabled ? palette.mutedText : palette.subtleText,
                fontWeight: FontWeight.w700,
              ),
            ),
      enabled: enabled,
      onTap: enabled ? onTap : null,
    );
  }
}

class _ProfilesSheet extends StatelessWidget {
  const _ProfilesSheet({
    required this.profiles,
    required this.effectiveDefaultProfileId,
  });

  final List<TerminalProfile> profiles;
  final String? effectiveDefaultProfileId;

  @override
  Widget build(BuildContext context) {
    final palette = _ShellPalette.fromBrightness(Theme.of(context).brightness);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Material(
        key: const Key('profiles-sheet'),
        color: palette.overlayBackground,
        borderRadius: BorderRadius.circular(20),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Profiles',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.primaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close profiles',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: palette.mutedText),
                    ),
                  ],
                ),
                Text(
                  'Open a tab with any saved profile or edit its shell settings.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.subtleText),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: profiles.length,
                    separatorBuilder: (_, _) =>
                        Divider(color: palette.divider, height: 1),
                    itemBuilder: (context, index) {
                      final profile = profiles[index];
                      final isDefault = profile.id == effectiveDefaultProfileId;
                      return ListTile(
                        key: Key('profile-entry-${profile.id}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          profile.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: palette.primaryText,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        subtitle: Text(
                          isDefault
                              ? '${profile.shell} • Default profile'
                              : profile.shell,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.subtleText),
                        ),
                        trailing: IconButton(
                          tooltip: 'Edit ${profile.name}',
                          onPressed: () => Navigator.of(
                            context,
                          ).pop(_EditProfileResult(profile)),
                          icon: Icon(
                            Icons.edit_outlined,
                            color: palette.mutedText,
                          ),
                        ),
                        onTap: () => Navigator.of(
                          context,
                        ).pop(_OpenProfileResult(profile)),
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

class _ShellPalette {
  const _ShellPalette({
    required this.background,
    required this.chromeBackground,
    required this.overlayBackground,
    required this.terminalBackground,
    required this.divider,
    required this.primaryText,
    required this.mutedText,
    required this.subtleText,
    required this.accent,
  });

  factory _ShellPalette.fromBrightness(Brightness brightness) {
    if (brightness == Brightness.light) {
      return const _ShellPalette(
        background: Color(0xFFF4F4F4),
        chromeBackground: Color(0xFFEDEDED),
        overlayBackground: Color(0xFFFFFFFF),
        terminalBackground: Color(0xFF000000),
        divider: Color(0xFFD2D2D2),
        primaryText: Color(0xFF111111),
        mutedText: Color(0xFF4A4A4A),
        subtleText: Color(0xFF747474),
        accent: Color(0xFFF6C344),
      );
    }
    return const _ShellPalette(
      background: Color(0xFF000000),
      chromeBackground: Color(0xFF0E0E0E),
      overlayBackground: Color(0xFF111111),
      terminalBackground: Color(0xFF000000),
      divider: Color(0xFF262626),
      primaryText: Color(0xFFF5F5F5),
      mutedText: Color(0xFFB8B8B8),
      subtleText: Color(0xFF8A8A8A),
      accent: Color(0xFFF6C344),
    );
  }

  final Color background;
  final Color chromeBackground;
  final Color overlayBackground;
  final Color terminalBackground;
  final Color divider;
  final Color primaryText;
  final Color mutedText;
  final Color subtleText;
  final Color accent;
}
