import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;

import '../../ui/app_ui.dart';
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
import 'window_bridge.dart';

enum _ShellCommandAction { newTab, copy, paste, search, defaults, profiles }

enum _ShellShortcutAction {
  openLauncher,
  newTab,
  closeActiveTab,
  openDefaults,
  requestQuitConfirmation,
  activateTab,
}

class _ShellShortcut {
  const _ShellShortcut(this.action, {this.tabIndex});

  final _ShellShortcutAction action;
  final int? tabIndex;
}

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
  static const _workspaceCueDuration = Duration(milliseconds: 1400);
  static const _viewportResizeDebounce = Duration(milliseconds: 240);
  static const _terminalViewportPadding = EdgeInsets.fromLTRB(16, 10, 18, 14);

  final Map<String, SelectionController> _selectionControllers = {};
  final Map<String, FocusNode> _terminalFocusNodes = {};
  final Map<String, Size> _scheduledViewportSizes = {};
  final Map<String, Size> _committedViewportSizes = {};
  Timer? _workspaceCueTimer;
  Timer? _viewportResizeTimer;
  bool _isCommandMenuOpen = false;
  bool _isDefaultsOpen = false;
  bool _isProfilesOpen = false;
  bool _isSearchOpen = false;
  bool _activeTerminalHasFocus = false;
  bool _recentlyClosedLastSession = false;
  bool _showWorkspaceCue = false;
  bool _showReturningCueOnNextFocus = false;
  int _lastObservedTabCount = 0;
  String _searchQuery = '';
  List<TerminalSearchMatch> _searchMatches = const [];
  int _activeSearchIndex = 0;

  @override
  void dispose() {
    _workspaceCueTimer?.cancel();
    _viewportResizeTimer?.cancel();
    for (final focusNode in _terminalFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

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
    final terminalFrame = activeSessionId == null
        ? null
        : ref
              .read(sessionControllerProvider.notifier)
              .viewportFor(activeSessionId)
              .frame;
    final terminalRows = terminalFrame?.rows ?? const [];
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
        terminalFrameSnapshot: terminalFrame == null
            ? null
            : <String, Object?>{
                'viewportRows': terminalFrame.viewportRows,
                'viewportCols': terminalFrame.viewportCols,
                'scrollbackOffset': terminalFrame.scrollbackOffset,
                'scrollbackMaxOffset': terminalFrame.scrollbackMaxOffset,
                'rows': terminalFrame.rows
                    .map(
                      (row) => <String, Object?>{
                        'index': row.index,
                        'text': row.text,
                        'wrapped': row.wrapped,
                      },
                    )
                    .toList(),
              },
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

  String get _workspaceCueTitle => 'Back in shell';

  _ShellShortcut? _shortcutActionFor(KeyEvent event) {
    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final usesMetaShortcuts =
        _usesMetaShortcuts || ref.read(referenceDemoModeProvider);
    final usesAppModifier = usesMetaShortcuts
        ? isMetaPressed && !isControlPressed
        : isControlPressed && !isMetaPressed;

    if (usesAppModifier && !isShiftPressed) {
      final platformAction = switch (event.logicalKey) {
        LogicalKeyboardKey.keyQ => _ShellShortcutAction.requestQuitConfirmation,
        LogicalKeyboardKey.keyW => _ShellShortcutAction.closeActiveTab,
        LogicalKeyboardKey.comma => _ShellShortcutAction.openDefaults,
        _ => null,
      };
      if (platformAction != null) {
        return _ShellShortcut(platformAction);
      }
      final tabIndex = _tabShortcutIndexFor(event.logicalKey);
      if (tabIndex != null) {
        return _ShellShortcut(
          _ShellShortcutAction.activateTab,
          tabIndex: tabIndex,
        );
      }
    }

    if (usesAppModifier &&
        isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyP) {
      return const _ShellShortcut(_ShellShortcutAction.openLauncher);
    }

    if (usesAppModifier && event.logicalKey == LogicalKeyboardKey.keyT) {
      return const _ShellShortcut(_ShellShortcutAction.newTab);
    }

    return null;
  }

  int? _tabShortcutIndexFor(LogicalKeyboardKey key) {
    return switch (key) {
      LogicalKeyboardKey.digit1 || LogicalKeyboardKey.numpad1 => 0,
      LogicalKeyboardKey.digit2 || LogicalKeyboardKey.numpad2 => 1,
      LogicalKeyboardKey.digit3 || LogicalKeyboardKey.numpad3 => 2,
      LogicalKeyboardKey.digit4 || LogicalKeyboardKey.numpad4 => 3,
      LogicalKeyboardKey.digit5 || LogicalKeyboardKey.numpad5 => 4,
      LogicalKeyboardKey.digit6 || LogicalKeyboardKey.numpad6 => 5,
      LogicalKeyboardKey.digit7 || LogicalKeyboardKey.numpad7 => 6,
      LogicalKeyboardKey.digit8 || LogicalKeyboardKey.numpad8 => 7,
      LogicalKeyboardKey.digit9 || LogicalKeyboardKey.numpad9 => 8,
      _ => null,
    };
  }

  Size _terminalContentSizeFor(BoxConstraints constraints) {
    return Size(
      (constraints.maxWidth - _terminalViewportPadding.horizontal)
          .clamp(1.0, double.infinity)
          .toDouble(),
      (constraints.maxHeight - _terminalViewportPadding.vertical)
          .clamp(1.0, double.infinity)
          .toDouble(),
    );
  }

  void _commitViewportResize(
    SessionController sessionController,
    String sessionId,
    Size viewportSize,
    double devicePixelRatio,
  ) {
    if (!mounted ||
        ref.read(sessionControllerProvider).activeSessionId != sessionId) {
      return;
    }
    sessionController.resizeActiveSession(viewportSize, devicePixelRatio);
    _committedViewportSizes[sessionId] = viewportSize;
  }

  void _scheduleViewportResize(
    SessionController sessionController,
    String sessionId,
    Size viewportSize,
    double devicePixelRatio, {
    required bool immediate,
  }) {
    _scheduledViewportSizes[sessionId] = viewportSize;
    _viewportResizeTimer?.cancel();
    _viewportResizeTimer = null;
    if (immediate) {
      _commitViewportResize(
        sessionController,
        sessionId,
        viewportSize,
        devicePixelRatio,
      );
      return;
    }

    _viewportResizeTimer = Timer(_viewportResizeDebounce, () {
      _commitViewportResize(
        sessionController,
        sessionId,
        viewportSize,
        devicePixelRatio,
      );
    });
  }

  String get _emptyStateTitle {
    return _recentlyClosedLastSession
        ? 'Shell workspace is idle'
        : 'Start a shell workspace';
  }

  String get _emptyStateMessage {
    return _recentlyClosedLastSession
        ? 'The last session has closed. Open a new tab to keep working in the shell workspace.'
        : 'Open a new tab to start working in the shell workspace.';
  }

  FocusNode _focusNodeFor(String sessionId) {
    return _terminalFocusNodes.putIfAbsent(sessionId, () {
      final focusNode = FocusNode(debugLabel: 'shell-terminal-$sessionId');
      focusNode.addListener(
        () => _handleTerminalFocusChanged(sessionId, focusNode),
      );
      return focusNode;
    });
  }

  void _handleTerminalFocusChanged(String sessionId, FocusNode focusNode) {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId != sessionId) {
      return;
    }

    final hasFocus = focusNode.hasFocus;
    final shouldShowCue = hasFocus && _showReturningCueOnNextFocus;
    if (_activeTerminalHasFocus == hasFocus &&
        _showWorkspaceCue == shouldShowCue) {
      return;
    }

    _workspaceCueTimer?.cancel();
    _workspaceCueTimer = null;
    setState(() {
      _activeTerminalHasFocus = hasFocus;
      if (hasFocus) {
        _showWorkspaceCue = shouldShowCue;
        _showReturningCueOnNextFocus = false;
      } else {
        _showWorkspaceCue = false;
      }
    });

    if (shouldShowCue) {
      _workspaceCueTimer = Timer(_workspaceCueDuration, () {
        if (!mounted || !_showWorkspaceCue) {
          return;
        }
        setState(() {
          _showWorkspaceCue = false;
        });
      });
    }
  }

  void _scheduleReturningCue() {
    _showReturningCueOnNextFocus = true;
    _recentlyClosedLastSession = false;
  }

  void _syncPresentationState(SessionState sessionState) {
    final currentTabCount = sessionState.tabs.length;
    if (currentTabCount == 0 && _lastObservedTabCount > 0) {
      _recentlyClosedLastSession = true;
      _activeTerminalHasFocus = false;
      _showWorkspaceCue = false;
    } else if (currentTabCount > 0 && _lastObservedTabCount == 0) {
      _recentlyClosedLastSession = false;
    }
    if (sessionState.activeSessionId == null) {
      _activeTerminalHasFocus = false;
      _showWorkspaceCue = false;
      _isSearchOpen = false;
      _searchQuery = '';
      _searchMatches = const [];
      _activeSearchIndex = 0;
      _workspaceCueTimer?.cancel();
      _workspaceCueTimer = null;
    }
    _lastObservedTabCount = currentTabCount;
  }

  void _createSession(
    SessionController sessionController,
    TerminalProfile profile, {
    required bool returningToWorkspace,
  }) {
    if (returningToWorkspace) {
      _scheduleReturningCue();
    }
    sessionController.createSession(profile);
    _focusSession(ref.read(sessionControllerProvider).activeSessionId);
  }

  void _activateSession(SessionController sessionController, String sessionId) {
    _scheduleReturningCue();
    sessionController.activateSession(sessionId);
    _focusSession(sessionId);
  }

  void _closeSession(
    SessionController sessionController,
    SessionState sessionState,
    String sessionId,
  ) {
    final closesLastSession = sessionState.tabs.length == 1;
    if (closesLastSession) {
      _recentlyClosedLastSession = true;
    }
    _scheduledViewportSizes.remove(sessionId);
    _committedViewportSizes.remove(sessionId);
    sessionController.closeSession(sessionId);
    final nextActiveSessionId = ref
        .read(sessionControllerProvider)
        .activeSessionId;
    if (nextActiveSessionId != null) {
      _scheduleReturningCue();
      _focusSession(nextActiveSessionId);
    }
  }

  void _focusSession(String? sessionId) {
    if (sessionId == null) {
      return;
    }
    final focusNode = _focusNodeFor(sessionId);
    if (!focusNode.canRequestFocus) {
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
    _scheduleReturningCue();
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

  terminal.TerminalViewportColors _terminalColorsForProfile(
    BuildContext context,
    TerminalProfile? profile,
  ) {
    return resolveTerminalColors(
      context,
      profileAppearance: profile?.appearance,
    ).viewport;
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
      return 'Current new-tab profile • ${effectiveProfile?.name ?? 'No profile available'}';
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
    final text = _selectionTextForSession(
      sessionController,
      sessionId,
      selectionController,
    );
    if (text.isEmpty) {
      return;
    }
    await ClipboardBridge.copy(text);
  }

  String _selectionTextForSession(
    SessionController sessionController,
    String sessionId,
    SelectionController selectionController,
  ) {
    final frame = sessionController.viewportFor(sessionId).frame;
    final selection = selectionController.selection;
    if (selection == null) {
      return '';
    }
    if (ref.read(referenceDemoModeProvider)) {
      return selectionController.textForFrame(frame);
    }
    final text = ref
        .read(terminalRuntimeControllerProvider)
        .selectionText(
          sessionId,
          selection,
          block: selectionController.isBlockSelection,
        );
    return text ?? selectionController.textForFrame(frame);
  }

  Future<void> _pasteToSession(String sessionId) async {
    final text = await ClipboardBridge.paste();
    if (text.isEmpty) {
      return;
    }
    final sessionState = ref.read(sessionControllerProvider);
    final sessionController = ref.read(sessionControllerProvider.notifier);
    String? profileId;
    for (final tab in sessionState.tabs) {
      if (tab.sessionId == sessionId) {
        profileId = tab.profileId;
        break;
      }
    }
    final profile = _profileForId(sessionState.profiles, profileId);
    final terminalConfig = profile?.toSessionConfig();
    final frame = sessionController.viewportFor(sessionId).frame;
    ref
        .read(terminalRuntimeControllerProvider)
        .sendInput(
          sessionId,
          TerminalInputController.clipboardPasteBytesFor(
            emulation:
                terminalConfig?.emulation ??
                terminal.TerminalEmulation.xterm256,
            modes: frame.modes,
            text: text,
          ),
        );
  }

  void _openSearch() {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    setState(() {
      _isSearchOpen = true;
      _searchQuery = '';
      _searchMatches = const [];
      _activeSearchIndex = 0;
    });
  }

  void _searchScrollback(String query) {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null) {
      return;
    }
    final matches = ref
        .read(terminalRuntimeControllerProvider)
        .searchText(activeSessionId, query);
    setState(() {
      _searchQuery = query;
      _searchMatches = matches;
      _activeSearchIndex = 0;
    });
    if (matches.isNotEmpty) {
      ref
          .read(terminalRuntimeControllerProvider)
          .scrollViewportTo(activeSessionId, matches.first.scrollbackOffset);
    }
  }

  void _moveSearchMatch(int delta) {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    if (activeSessionId == null || _searchMatches.isEmpty) {
      return;
    }
    final nextIndex = (_activeSearchIndex + delta) % _searchMatches.length;
    final normalizedIndex = nextIndex < 0
        ? nextIndex + _searchMatches.length
        : nextIndex;
    setState(() {
      _activeSearchIndex = normalizedIndex;
    });
    ref
        .read(terminalRuntimeControllerProvider)
        .scrollViewportTo(
          activeSessionId,
          _searchMatches[normalizedIndex].scrollbackOffset,
        );
  }

  void _closeSearch() {
    final activeSessionId = ref.read(sessionControllerProvider).activeSessionId;
    setState(() {
      _isSearchOpen = false;
      _searchQuery = '';
      _searchMatches = const [];
      _activeSearchIndex = 0;
    });
    if (activeSessionId != null) {
      ref
          .read(terminalRuntimeControllerProvider)
          .scrollViewportTo(activeSessionId, 0);
      _focusSession(activeSessionId);
    }
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

    if (selection != null) {
      if (selection.openProfiles) {
        await _openProfilesSheet(
          sessionController,
          ref.read(sessionControllerProvider),
        );
        return;
      }
      final stateBeforeSave = ref.read(sessionControllerProvider);
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
        _createSession(
          sessionController,
          profile,
          returningToWorkspace: activeSessionIdBeforeOpen == null,
        );
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
        _createSession(
          sessionController,
          defaultProfile,
          returningToWorkspace: activeSessionIdBeforeOpen == null,
        );
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
      case _ShellCommandAction.search:
        if (currentSessionId == null) {
          return;
        }
        _openSearch();
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
    _syncPresentationState(sessionState);
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
    TerminalTab? activeTab;
    if (activeSessionId != null) {
      for (final tab in sessionState.tabs) {
        if (tab.sessionId == activeSessionId) {
          activeTab = tab;
          break;
        }
      }
    }
    final activeProfile = activeTab == null
        ? null
        : activeTab.profileSnapshot ??
              _profileForId(sessionState.profiles, activeTab.profileId);
    final activeFocusNode = activeSessionId == null
        ? null
        : _focusNodeFor(activeSessionId);
    final palette = context.appTheme;
    final terminalColors = _terminalColorsForProfile(context, activeProfile);

    KeyEventResult handleShellShortcut(KeyEvent event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final shortcut = _shortcutActionFor(event);
      if (shortcut == null) {
        return KeyEventResult.ignored;
      }

      if (shortcut.action == _ShellShortcutAction.requestQuitConfirmation) {
        if (event is KeyRepeatEvent) {
          return KeyEventResult.handled;
        }
        unawaited(WindowBridge.requestQuitConfirmation());
        return KeyEventResult.handled;
      }

      if (_isCommandMenuOpen || _isDefaultsOpen || _isProfilesOpen) {
        return KeyEventResult.handled;
      }

      if (event is KeyRepeatEvent) {
        return KeyEventResult.handled;
      }

      switch (shortcut.action) {
        case _ShellShortcutAction.openLauncher:
          unawaited(_openCommandMenu(sessionController, sessionState));
          return KeyEventResult.handled;
        case _ShellShortcutAction.newTab:
          if (defaultProfile == null) {
            return KeyEventResult.handled;
          }
          _createSession(
            sessionController,
            defaultProfile,
            returningToWorkspace: activeSessionId == null,
          );
          return KeyEventResult.handled;
        case _ShellShortcutAction.closeActiveTab:
          if (activeSessionId == null) {
            return KeyEventResult.handled;
          }
          _closeSession(sessionController, sessionState, activeSessionId);
          return KeyEventResult.handled;
        case _ShellShortcutAction.openDefaults:
          unawaited(
            _openDefaultsAndAppearance(sessionController, sessionState),
          );
          return KeyEventResult.handled;
        case _ShellShortcutAction.requestQuitConfirmation:
          return KeyEventResult.handled;
        case _ShellShortcutAction.activateTab:
          final tabIndex = shortcut.tabIndex;
          if (tabIndex == null || tabIndex >= sessionState.tabs.length) {
            return KeyEventResult.handled;
          }
          final tab = sessionState.tabs[tabIndex];
          if (tab.sessionId == activeSessionId) {
            _focusSession(tab.sessionId);
            return KeyEventResult.handled;
          }
          _activateSession(sessionController, tab.sessionId);
          return KeyEventResult.handled;
      }
    }

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) => handleShellShortcut(event),
      child: Scaffold(
        backgroundColor: palette.canvas,
        body: ColoredBox(
          color: palette.canvas,
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
                  onActivateSession: (sessionId) =>
                      _activateSession(sessionController, sessionId),
                  onCloseSession: (sessionId) =>
                      _closeSession(sessionController, sessionState, sessionId),
                  onShowCommandMenu: () =>
                      _openCommandMenu(sessionController, sessionState),
                ),
                if (sessionState.configurationWarnings.isNotEmpty)
                  _ShellConfigurationWarningsBanner(
                    palette: palette,
                    warnings: sessionState.configurationWarnings,
                    onReviewProfiles: () => _openProfilesSheet(
                      sessionController,
                      ref.read(sessionControllerProvider),
                    ),
                    onDismiss: sessionController.dismissConfigurationWarnings,
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
                            title: _emptyStateTitle,
                            message: _emptyStateMessage,
                            defaultSummary: defaultSummary,
                            onNewTab: defaultProfile == null
                                ? null
                                : () {
                                    _createSession(
                                      sessionController,
                                      defaultProfile,
                                      returningToWorkspace: true,
                                    );
                                  },
                          )
                        : LayoutBuilder(
                            key: ValueKey(activeSessionId),
                            builder: (context, constraints) {
                              final viewportSize = _terminalContentSizeFor(
                                constraints,
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
                                    _scheduleViewportResize(
                                      sessionController,
                                      activeSessionId,
                                      viewportSize,
                                      MediaQuery.devicePixelRatioOf(context),
                                      immediate: !_committedViewportSizes
                                          .containsKey(activeSessionId),
                                    );
                                  }
                                });
                              }

                              final selectionController =
                                  activeSelectionController!;
                              final terminalConfig = activeProfile
                                  ?.toSessionConfig();
                              final inputController = TerminalInputController(
                                sessionId: activeSessionId,
                                runtime: ref.read(
                                  terminalRuntimeControllerProvider,
                                ),
                                readFrame: () => sessionController
                                    .viewportFor(activeSessionId)
                                    .frame,
                                emulation:
                                    terminalConfig?.emulation ??
                                    terminal.TerminalEmulation.xterm256,
                                readSelection: () => _selectionTextForSession(
                                  sessionController,
                                  activeSessionId,
                                  selectionController,
                                ),
                                copySelection: (text) =>
                                    ClipboardBridge.copy(text),
                                readClipboard: ClipboardBridge.paste,
                              );

                              return RepaintBoundary(
                                key: const Key('shell-terminal-surface'),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: palette.terminalSurface,
                                    border: Border(
                                      top: BorderSide(color: palette.border),
                                    ),
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: TerminalViewport(
                                          focusNode: activeFocusNode,
                                          controller: sessionController
                                              .viewportFor(activeSessionId),
                                          selectionController:
                                              selectionController,
                                          inputController: inputController,
                                          contentPadding:
                                              _terminalViewportPadding,
                                          onMeasuredCellSizeChanged: (_) {
                                            if (!mounted) {
                                              return;
                                            }
                                            _scheduleViewportResize(
                                              sessionController,
                                              activeSessionId,
                                              viewportSize,
                                              MediaQuery.devicePixelRatioOf(
                                                context,
                                              ),
                                              immediate: true,
                                            );
                                          },
                                          colors: terminalColors,
                                          font:
                                              terminalConfig?.display.font ??
                                              const terminal.TerminalFontConfig(),
                                          cursor:
                                              terminalConfig?.display.cursor ??
                                              const terminal.TerminalCursorConfig(),
                                          copyOnSelect:
                                              terminalConfig
                                                  ?.interaction
                                                  .copyOnSelect ??
                                              false,
                                          optionDragMode:
                                              terminalConfig
                                                  ?.interaction
                                                  .optionDragMode ??
                                              terminal
                                                  .TerminalOptionDragMode
                                                  .blockSelection,
                                          onHostKeyEvent: handleShellShortcut,
                                          onScrollLines: (delta) {
                                            ref
                                                .read(
                                                  terminalRuntimeControllerProvider,
                                                )
                                                .scrollViewport(
                                                  activeSessionId,
                                                  delta,
                                                );
                                          },
                                          onScrollToOffset: (offset) {
                                            ref
                                                .read(
                                                  terminalRuntimeControllerProvider,
                                                )
                                                .scrollViewportTo(
                                                  activeSessionId,
                                                  offset,
                                                );
                                          },
                                          onOpenLink: (url) => unawaited(
                                            WindowBridge.openExternalUrl(url),
                                          ),
                                        ),
                                      ),
                                      if (_isSearchOpen)
                                        Positioned(
                                          top: _terminalViewportPadding.top,
                                          right: _terminalViewportPadding.right,
                                          child: _TerminalSearchBar(
                                            query: _searchQuery,
                                            matches: _searchMatches.length,
                                            activeIndex: _activeSearchIndex,
                                            palette: palette,
                                            onChanged: _searchScrollback,
                                            onPrevious: () =>
                                                _moveSearchMatch(-1),
                                            onNext: () => _moveSearchMatch(1),
                                            onClose: _closeSearch,
                                          ),
                                        ),
                                      if (_showWorkspaceCue)
                                        Positioned(
                                          top: _terminalViewportPadding.top,
                                          right: _terminalViewportPadding.right,
                                          child: IgnorePointer(
                                            child: _ShellWorkspaceCue(
                                              title: _workspaceCueTitle,
                                              palette: palette,
                                            ),
                                          ),
                                        ),
                                    ],
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

  final AppThemeTokens palette;
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
        color: palette.chrome,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: SizedBox(
        height: 40,
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
                  width: 32,
                  height: 32,
                ),
                iconSize: 16,
                icon: Icon(Icons.tune_rounded, color: palette.textSubtle),
              ),
              const SizedBox(width: 6),
            ] else
              const SizedBox(width: 20),
          ],
        ),
      ),
    );
  }
}

class _ShellConfigurationWarningsBanner extends StatelessWidget {
  const _ShellConfigurationWarningsBanner({
    required this.palette,
    required this.warnings,
    required this.onReviewProfiles,
    required this.onDismiss,
  });

  final AppThemeTokens palette;
  final List<TerminalProfileLoadWarning> warnings;
  final Future<void> Function() onReviewProfiles;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('shell-configuration-warnings'),
      decoration: BoxDecoration(
        color: palette.overlay,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: palette.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Some terminal profile values were ignored and reset to safe defaults.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      for (final warning in warnings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            terminalProfileLoadWarningMessage(warning),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.textSubtle),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('shell-configuration-warnings-dismiss'),
                  tooltip: 'Dismiss configuration warnings',
                  onPressed: onDismiss,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, color: palette.textSubtle),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                FilledButton.tonal(
                  key: const Key('shell-configuration-warnings-review'),
                  onPressed: () => unawaited(onReviewProfiles()),
                  child: const Text('Review Profiles'),
                ),
                const SizedBox(width: 6),
                TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
              ],
            ),
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

  final AppThemeTokens palette;
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
              shortcutIndex: index < 9 ? index + 1 : null,
              isActive: tabs[index].sessionId == activeSessionId,
              onActivate: () => onActivateSession(tabs[index].sessionId),
            ),
          ),
          if (index < tabs.length - 1)
            SizedBox(
              width: 1,
              height: double.infinity,
              child: ColoredBox(color: palette.border),
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
    required this.shortcutIndex,
    required this.isActive,
    required this.onActivate,
  });

  final AppThemeTokens palette;
  final TerminalTab tab;
  final int? shortcutIndex;
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
          foregroundColor: isActive ? palette.textPrimary : palette.textMuted,
          shape: const RoundedRectangleBorder(),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (shortcutIndex != null) ...[
                Text(
                  '⌘$shortcutIndex',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isActive ? palette.textMuted : palette.textSubtle,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                tab.title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: isActive ? palette.textPrimary : palette.textSubtle,
                  fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ],
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

  final AppThemeTokens palette;
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
          margin: const EdgeInsets.symmetric(vertical: 6),
          color: palette.border,
        ),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final isActive = tab.sessionId == activeSessionId;
          return _ShellTabButton(
            palette: palette,
            tab: tab,
            shortcutIndex: index < 9 ? index + 1 : null,
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
    required this.shortcutIndex,
    required this.isActive,
    required this.onActivate,
    required this.onClose,
  });

  final AppThemeTokens palette;
  final TerminalTab tab;
  final int? shortcutIndex;
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
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -1, vertical: -2),
          foregroundColor: isActive ? palette.textPrimary : palette.textMuted,
          shape: const RoundedRectangleBorder(),
        ),
        onPressed: onActivate,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (shortcutIndex != null) ...[
                Text(
                  '⌘$shortcutIndex',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isActive ? palette.textMuted : palette.textSubtle,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
              ],
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 140),
              style: Theme.of(context).textTheme.titleSmall!.copyWith(
                color: isActive ? palette.textPrimary : palette.textMuted,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
              child: Text(tab.title, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Close ${tab.title}',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: Icon(
                  Icons.close_rounded,
                  size: 11,
                  color: isActive
                      ? palette.textMuted
                      : palette.textSubtle.withValues(alpha: 0.72),
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
    required this.title,
    required this.message,
    required this.defaultSummary,
    required this.onNewTab,
  });

  final AppThemeTokens palette;
  final String title;
  final String message;
  final String defaultSummary;
  final VoidCallback? onNewTab;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.terminalSurface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppEmptyState(
            title: title,
            message: message,
            supportingText: defaultSummary,
            action: AppActionButton(
              buttonKey: const Key('shell-empty-new-tab'),
              icon: Icons.add_box_outlined,
              label: 'New Tab',
              onPressed: onNewTab,
            ),
          ),
        ),
      ),
    );
  }
}

class _TerminalSearchBar extends StatelessWidget {
  const _TerminalSearchBar({
    required this.query,
    required this.matches,
    required this.activeIndex,
    required this.palette,
    required this.onChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final String query;
  final int matches;
  final int activeIndex;
  final AppThemeTokens palette;
  final ValueChanged<String> onChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  String get _counterText {
    if (matches == 0) {
      return query.isEmpty ? '0 of 0' : 'No matches';
    }
    return '${activeIndex + 1} of $matches';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('terminal-search-bar'),
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
          width: 304,
          height: 38,
          child: Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('terminal-search-field'),
                  autofocus: true,
                  onChanged: onChanged,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search',
                    hintStyle: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: palette.textSubtle),
                    border: InputBorder.none,
                  ),
                ),
              ),
              Text(
                _counterText,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: matches == 0 && query.isNotEmpty
                      ? palette.textMuted
                      : palette.textSubtle,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                key: const Key('terminal-search-previous'),
                tooltip: 'Previous match',
                onPressed: matches == 0 ? null : onPrevious,
                visualDensity: VisualDensity.compact,
                splashRadius: 16,
                iconSize: 16,
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
              IconButton(
                key: const Key('terminal-search-next'),
                tooltip: 'Next match',
                onPressed: matches == 0 ? null : onNext,
                visualDensity: VisualDensity.compact,
                splashRadius: 16,
                iconSize: 16,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
              IconButton(
                key: const Key('terminal-search-close'),
                tooltip: 'Close search',
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
                splashRadius: 16,
                iconSize: 16,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
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
        border: Border.all(color: palette.accent.withValues(alpha: 0.38)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
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
    final palette = context.appTheme;

    Widget sectionLabel(String text) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: palette.textSubtle,
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
        constraints: const BoxConstraints(maxWidth: 340, maxHeight: 460),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.overlay,
            borderRadius: BorderRadius.circular(palette.radius.lg),
            border: Border.all(color: palette.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 2, 2, 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Top actions',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: palette.textPrimary,
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
                            color: palette.textMuted,
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
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Requires an active shell session.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textSubtle),
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
                  _ShellCommandTile(
                    icon: Icons.search_rounded,
                    title: 'Search scrollback',
                    subtitle: 'Session action • Find text in local output.',
                    enabled: hasActiveSession,
                    onTap: () =>
                        Navigator.of(context).pop(_ShellCommandAction.search),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.keyboard_command_key_rounded,
                          size: 16,
                          color: palette.textSubtle,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Open command menu with $launcherShortcutLabel',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: palette.textSubtle),
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
    final palette = context.appTheme;
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(palette.radius.lg),
      ),
      leading: Icon(
        icon,
        color: enabled ? palette.textPrimary : palette.textSubtle,
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: enabled ? palette.textPrimary : palette.textSubtle,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: palette.textSubtle),
      ),
      trailing: shortcutLabel == null
          ? null
          : Text(
              shortcutLabel!,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: enabled ? palette.textMuted : palette.textSubtle,
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
    final palette = context.appTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        key: const Key('profiles-sheet'),
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
                        'Profiles',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close profiles',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: palette.textMuted),
                    ),
                  ],
                ),
                Text(
                  'Open a tab with any saved profile or edit its terminal settings.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.textSubtle),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: profiles.length,
                    separatorBuilder: (_, _) =>
                        Divider(color: palette.border, height: 1),
                    itemBuilder: (context, index) {
                      final profile = profiles[index];
                      final isDefault = profile.id == effectiveDefaultProfileId;
                      final summary = _profileSummary(
                        profile,
                        isDefault: isDefault,
                      );
                      return ListTile(
                        key: Key('profile-entry-${profile.id}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          profile.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        subtitle: Text(
                          summary,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: palette.textSubtle),
                        ),
                        trailing: IconButton(
                          tooltip: 'Edit ${profile.name}',
                          onPressed: () => Navigator.of(
                            context,
                          ).pop(_EditProfileResult(profile)),
                          icon: Icon(
                            Icons.edit_outlined,
                            color: palette.textMuted,
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

  String _profileSummary(TerminalProfile profile, {required bool isDefault}) {
    final base =
        '${profile.shell} • ${terminalEmulationLabel(profile.terminalEmulation)} • ${profile.scrollbackLines} lines';
    return isDefault ? '$base • Default profile' : base;
  }
}
