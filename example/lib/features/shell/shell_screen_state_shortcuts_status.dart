part of 'shell_screen.dart';

extension _ShellScreenStateShortcutsStatus on _ShellScreenState {
  void _closeToolbelt() {
    if (!_isToolbeltOpen) {
      return;
    }
    _mutateState(() {
      _isToolbeltOpen = false;
    });
  }

  void _openToolbeltChild(Future<void> Function() open) {
    _closeToolbelt();
    unawaited(open());
  }

  Future<void> _dispatchShellNotification({
    required String title,
    String? body,
    required String identifier,
    int? expiresAfterMs,
  }) async {
    try {
      await ref.read(shellNotificationSenderProvider)(
        title: title,
        body: body,
        identifier: identifier,
        expiresAfterMs: expiresAfterMs,
      );
      if (mounted && _notificationsBlockedBySystem) {
        _mutateState(() {
          _notificationsBlockedBySystem = false;
          _lastNotificationFailureLabel = null;
          _lastNotificationFailureTooltip = null;
        });
      }
    } on PlatformException catch (error) {
      if (mounted &&
          error.code == 'notification_authorization_failed' &&
          !_notificationsBlockedBySystem) {
        _mutateState(() {
          _notificationsBlockedBySystem = true;
        });
      }
      if (!mounted || !_notificationFailureCodesShown.add(error.code)) {
        return;
      }
      final message = switch (error.code) {
        'notification_authorization_failed' =>
          'macOS notifications are blocked for Ianvs Terminal. Enable them in System Settings > Notifications.',
        'notification_delivery_failed' =>
          'Ianvs Terminal could not deliver a macOS notification right now.',
        _ => null,
      };
      if (message == null) {
        return;
      }
      _showNotificationFailureStatus(message);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _showNotificationFailureStatus(String message) {
    _notificationFailureStatusClearTimer?.cancel();
    if (!mounted) {
      return;
    }
    _mutateState(() {
      _lastNotificationFailureLabel = 'NOTIFY BLOCKED';
      _lastNotificationFailureTooltip = message;
    });
    _notificationFailureStatusClearTimer = Timer(
      const Duration(seconds: 8),
      () {
        if (!mounted) {
          return;
        }
        _mutateState(() {
          _lastNotificationFailureLabel = null;
          _lastNotificationFailureTooltip = null;
        });
      },
    );
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
    if (_isToolbeltOpen) {
      return 'toolbelt';
    }
    if (_instantReplayWorkspaceSession != null) {
      return 'instantReplay';
    }
    return 'none';
  }

  void _publishAcceptanceSnapshot([SessionState? state]) {
    final SessionState snapshotState =
        state ?? ref.read(sessionControllerProvider);
    final activeSessionId = snapshotState.activeSessionId;
    TerminalTab? activeTab;
    if (activeSessionId != null) {
      for (final tab in snapshotState.tabs) {
        if (tab.containsSession(activeSessionId)) {
          activeTab = tab;
          break;
        }
      }
    }
    final sessionController = ref.read(sessionControllerProvider.notifier);
    final terminalFrame = activeSessionId == null
        ? null
        : sessionController.viewportFor(activeSessionId).frame;
    final terminalPreview = activeTab == null
        ? null
        : _acceptancePreviewForActiveTabPanes(
            activeTab,
            frameForSession: (sessionId) =>
                sessionController.viewportFor(sessionId).frame,
          );
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

  String? _acceptancePreviewForActiveTabPanes(
    TerminalTab activeTab, {
    required terminal.TerminalFrameDiff? Function(String sessionId)
    frameForSession,
  }) {
    final activePane = activeTab.activePane;
    final panes = <TerminalPane>[
      activePane,
      for (final pane in activeTab.effectivePanes)
        if (pane.sessionId != activePane.sessionId) pane,
    ];
    for (final pane in panes) {
      final frame = frameForSession(pane.sessionId);
      if (frame == null) {
        continue;
      }
      for (final row in frame.rows) {
        final text = row.text.trim();
        if (text.isNotEmpty) {
          return text;
        }
      }
    }
    return null;
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

  String _sessionPasteShortcutLabel() {
    return _usesMetaShortcuts ? '⌘V' : 'Ctrl+V';
  }

  String _instantReplayShortcutLabel() {
    return _usesMetaShortcuts ? '⌥⌘B' : 'Alt+Ctrl+B';
  }

  String _searchShortcutLabel() {
    return _usesMetaShortcuts ? '⌘F' : 'Ctrl+F';
  }

  _ShellShortcut? _shortcutActionFor(KeyEvent event) {
    final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
    final isControlPressed = HardwareKeyboard.instance.isControlPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final isAltPressed = HardwareKeyboard.instance.isAltPressed;
    final usesMetaShortcuts =
        _usesMetaShortcuts || ref.read(referenceDemoModeProvider);
    final usesAppModifier = usesMetaShortcuts
        ? isMetaPressed && !isControlPressed
        : isControlPressed && !isMetaPressed;

    for (final scope in const <TerminalKeyBindingScope>[
      TerminalKeyBindingScope.terminalFocused,
      TerminalKeyBindingScope.focusedApp,
      TerminalKeyBindingScope.global,
    ]) {
      final actionId = ShellShortcutBridge.resolve(
        key: event.logicalKey,
        usesMetaShortcuts: usesMetaShortcuts,
        isMetaPressed: isMetaPressed,
        isControlPressed: isControlPressed,
        isShiftPressed: isShiftPressed,
        isAltPressed: isAltPressed,
        scope: scope,
        config: _keybindingsConfig,
      );
      if (actionId != null) {
        return _ShellShortcut(actionId);
      }
    }

    if (usesAppModifier && !isShiftPressed && !isAltPressed) {
      final tabIndex = _tabShortcutIndexFor(event.logicalKey);
      if (tabIndex != null) {
        return _ShellShortcut(TerminalActionId.activateTab, tabIndex: tabIndex);
      }
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

  EdgeInsets _terminalViewportPaddingFor(SessionState sessionState) {
    return EdgeInsets.all(sessionState.terminalViewportPadding);
  }

  Size _terminalContentSizeFor(
    BoxConstraints constraints,
    EdgeInsets terminalViewportPadding,
  ) {
    return Size(
      (constraints.maxWidth - terminalViewportPadding.horizontal)
          .clamp(1.0, double.infinity)
          .toDouble(),
      (constraints.maxHeight - terminalViewportPadding.vertical)
          .clamp(1.0, double.infinity)
          .toDouble(),
    );
  }

  String? _viewportStatusLabelFor(String? sessionId) {
    if (sessionId == null) {
      return null;
    }
    final viewportSize =
        _scheduledViewportSizes[sessionId] ??
        _committedViewportSizes[sessionId];
    final cellSize =
        _measuredTerminalCellSizes[sessionId] ??
        terminal.terminalFallbackCellSize;
    if (viewportSize == null || cellSize.width <= 0 || cellSize.height <= 0) {
      return null;
    }
    final cols = (viewportSize.width / cellSize.width).floor();
    final rows = (viewportSize.height / cellSize.height).floor();
    if (cols <= 0 || rows <= 0) {
      return null;
    }
    return '$cols×$rows';
  }

  String _shortStatusValue(String value, {int max = 18}) {
    final trimmed = value.trim();
    if (trimmed.length <= max) {
      return trimmed;
    }
    if (max <= 1) {
      return trimmed.substring(0, max);
    }
    return '${trimmed.substring(0, max - 1)}…';
  }

  String _progressStatusTooltip(TerminalPaneProgressState progress) {
    return [
      'Terminal progress reported by ${progress.source}.',
      if (progress.label?.trim().isNotEmpty == true)
        'Label: ${progress.label!.trim()}',
      if (progress.percent != null) 'Percent: ${progress.percent}%',
      if (progress.state?.trim().isNotEmpty == true)
        'State: ${progress.state!.trim()}',
      if (progress.id?.trim().isNotEmpty == true) 'ID: ${progress.id!.trim()}',
    ].join('\n');
  }

  String _notificationStatusLabel(TerminalPaneNotificationState notification) {
    final suffix = notification.count > 1 ? ' x${notification.count}' : '';
    return 'NOTIFY ${_shortStatusValue(notification.title, max: 14)}$suffix';
  }

  String _notificationStatusTooltip(
    TerminalPaneNotificationState notification,
  ) {
    return [
      'Terminal notification reported by ${notification.source}.',
      'Title: ${notification.title}',
      if (notification.message.trim().isNotEmpty)
        'Message: ${notification.message.trim()}',
      if (notification.remoteHost?.trim().isNotEmpty == true)
        'Remote host: ${notification.remoteHost!.trim()}',
      if (notification.remoteUser?.trim().isNotEmpty == true)
        'Remote user: ${notification.remoteUser!.trim()}',
      if (notification.count > 1) 'Count: ${notification.count}',
      'Click to inspect recent notifications for this pane.',
    ].join('\n');
  }

  String _statusDirectoryTooltip({
    required String path,
    required bool fromShellIntegration,
    String? hostname,
    String? username,
  }) {
    final remote = _shellHostIsRemote(hostname);
    return [
      if (!fromShellIntegration)
        'Profile default working directory.'
      else if (remote)
        'Remote-reported shell integration path.'
      else
        'Local shell integration path.',
      'Path: $path',
      if (hostname?.trim().isNotEmpty == true) 'Host: ${hostname!.trim()}',
      if (username?.trim().isNotEmpty == true) 'User: ${username!.trim()}',
      if (remote) 'Local file actions stay disabled for remote paths.',
    ].join('\n');
  }

  String? _statusTooltipForPane({
    required String? sessionId,
    required String? tooltip,
    bool includeFocusHint = false,
  }) {
    if (tooltip == null || tooltip.trim().isEmpty) {
      return tooltip;
    }
    if (sessionId == null || !_sessionIsInMultiPaneTab(sessionId)) {
      return tooltip;
    }
    return [
      _terminalPaneContextLine(sessionId),
      tooltip,
      if (includeFocusHint && _sessionNeedsFocus(sessionId))
        'Click to focus this pane.',
    ].join('\n');
  }

  bool _sessionNeedsFocus(String sessionId) {
    return ref.read(sessionControllerProvider).activeSessionId != sessionId;
  }

  bool _shellHostIsRemote(String? hostname) {
    final normalized = hostname?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return false;
    }
    final localHostname = Platform.localHostname.toLowerCase();
    return normalized != 'localhost' &&
        normalized != '127.0.0.1' &&
        normalized != '::1' &&
        normalized != localHostname &&
        normalized != '$localHostname.local';
  }

  List<_ShellStatusModeItem> _statusModeItemsFor(
    String sessionId,
    terminal.TerminalFrameModes modes,
  ) {
    final items = <_ShellStatusModeItem>[];
    if (modes.alternateScreen) {
      items.add(
        _ShellStatusModeItem(
          key: const Key('shell-status-mode-alt'),
          label: 'ALT',
          tooltip: _statusTooltipForPane(
            sessionId: sessionId,
            tooltip: 'Alternate screen buffer is active.',
          )!,
          semanticsLabel: 'Terminal mode: alternate screen buffer active',
        ),
      );
    }
    if (modes.mouseMode != 'off') {
      final mouseMode = _mouseModeStatusLabel(modes.mouseMode);
      final mouseEncoding = _mouseEncodingStatusLabel(modes.mouseEncoding);
      items.add(
        _ShellStatusModeItem(
          key: const Key('shell-status-mode-mouse'),
          label: 'MOUSE',
          tooltip: _statusTooltipForPane(
            sessionId: sessionId,
            tooltip: 'Mouse reporting is active: $mouseMode, $mouseEncoding.',
          )!,
          semanticsLabel: 'Terminal mode: mouse reporting active',
        ),
      );
    }
    if (modes.bracketedPaste) {
      items.add(
        _ShellStatusModeItem(
          key: const Key('shell-status-mode-paste'),
          label: 'PASTE',
          tooltip: _statusTooltipForPane(
            sessionId: sessionId,
            tooltip: 'Bracketed paste mode is active.',
          )!,
          semanticsLabel: 'Terminal mode: bracketed paste active',
        ),
      );
    }
    if (modes.focusTracking) {
      items.add(
        _ShellStatusModeItem(
          key: const Key('shell-status-mode-focus'),
          label: 'FOCUS',
          tooltip: _statusTooltipForPane(
            sessionId: sessionId,
            tooltip:
                'Focus reporting is active. The application receives focus-in and focus-out events.',
          )!,
          semanticsLabel: 'Terminal mode: focus reporting active',
        ),
      );
    }
    if (modes.kittyKeyboardFlags != 0) {
      items.add(
        _ShellStatusModeItem(
          key: const Key('shell-status-mode-kitty-keyboard'),
          label: 'KEYS',
          tooltip: _statusTooltipForPane(
            sessionId: sessionId,
            tooltip: _kittyKeyboardStatusTooltip(modes.kittyKeyboardFlags),
          )!,
          semanticsLabel: 'Terminal mode: Kitty keyboard protocol active',
        ),
      );
    }
    if (modes.synchronizedOutput) {
      items.add(
        _ShellStatusModeItem(
          key: const Key('shell-status-mode-sync'),
          label: 'SYNC',
          tooltip: _statusTooltipForPane(
            sessionId: sessionId,
            tooltip:
                'Synchronized output mode is active. Intermediate updates are held until the application flushes.',
          )!,
          semanticsLabel: 'Terminal mode: synchronized output active',
        ),
      );
    }
    if (_isSessionReadOnly(sessionId)) {
      items.add(
        _ShellStatusModeItem(
          key: const Key('shell-status-mode-read-only'),
          label: 'READ ONLY',
          tooltip: _statusTooltipForPane(
            sessionId: sessionId,
            tooltip:
                'Read-only mode is enabled for this pane. Input and paste sends are blocked.',
          )!,
          semanticsLabel: 'Terminal pane is read-only',
        ),
      );
    }
    return items;
  }

  String _mouseModeStatusLabel(String mode) {
    return switch (mode) {
      'x10' => 'X10 tracking',
      'normal' => 'normal tracking',
      'button_event' => 'button-event tracking',
      'any_event' => 'any-event tracking',
      _ => mode.replaceAll('_', ' '),
    };
  }

  String _mouseEncodingStatusLabel(String encoding) {
    return switch (encoding) {
      'sgr' => 'SGR encoding',
      'sgr_pixels' => 'SGR pixels encoding',
      'utf8' => 'UTF-8 encoding',
      'urxvt' => 'URXVT encoding',
      'default' => 'default encoding',
      _ => '${encoding.replaceAll('_', ' ')} encoding',
    };
  }

  String _kittyKeyboardStatusTooltip(int flags) {
    final enabled = <String>[
      if ((flags & 1) != 0) 'disambiguated keys',
      if ((flags & 2) != 0) 'repeat and release events',
      if ((flags & 4) != 0) 'alternate key forms',
      if ((flags & 8) != 0) 'all keys',
      if ((flags & 16) != 0) 'associated text',
    ];
    return [
      'Kitty keyboard protocol is active.',
      if (enabled.isNotEmpty) 'Enabled: ${enabled.join(', ')}.',
      'Some key combinations are sent as Kitty CSI-u sequences.',
    ].join('\n');
  }
}
