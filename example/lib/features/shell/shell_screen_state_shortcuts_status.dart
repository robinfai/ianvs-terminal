part of 'shell_screen.dart';

extension _ShellScreenStateShortcutsStatus on _ShellScreenState {
  void _openToolbelt() {
    if (_isToolbeltOpen) {
      return;
    }
    _mutateState(() {
      _isToolbeltOpen = true;
    });
  }

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
  }) async {
    try {
      await ref.read(shellNotificationSenderProvider)(
        title: title,
        body: body,
        identifier: identifier,
      );
      if (mounted && _notificationsBlockedBySystem) {
        _mutateState(() {
          _notificationsBlockedBySystem = false;
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
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
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

  bool get _shellOverlayOpenForQuitShortcutGuard {
    return _isCommandMenuOpen ||
        _isDefaultsOpen ||
        _isProfilesOpen ||
        _isCommandSearchOpen ||
        _isCommandActionSearchOpen ||
        _isAutocompleteOpen ||
        _isAutoComposerOpen;
  }

  Future<bool> _handleNativeWindowCloseRequest() async {
    if (!mounted) {
      return false;
    }
    if (_isCommandMenuOpen || _isDefaultsOpen || _isProfilesOpen) {
      final didPop = await Navigator.of(
        context,
        rootNavigator: true,
      ).maybePop();
      if (didPop) {
        return true;
      }
    }
    if (_isCommandSearchOpen) {
      _closeCommandSearch(preferCommandInput: true);
      return true;
    }
    if (_isCommandActionSearchOpen) {
      _closeCommandActionSearch();
      return true;
    }
    if (_isSearchOpen) {
      _closeSearch();
      return true;
    }
    if (_isAutocompleteOpen) {
      _closeAutocomplete();
      return true;
    }
    if (_isAutoComposerOpen) {
      _closeAutoComposer();
      return true;
    }
    if (_isToolbeltOpen) {
      _closeToolbelt();
      return true;
    }
    if (_instantReplayWorkspaceSession != null) {
      _closeInstantReplayWorkspace();
      return true;
    }
    return false;
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

  String _hotkeyWindowShortcutLabel() {
    return _usesMetaShortcuts ? '⌥⌘Space' : 'Alt+Ctrl+Space';
  }

  String _autocompleteShortcutLabel() {
    return _usesMetaShortcuts ? '⌘;' : 'Ctrl+;';
  }

  String _sessionCopyShortcutLabel() {
    return _usesMetaShortcuts ? '⌘C' : 'Ctrl+C';
  }

  String _copyModeShortcutLabel() {
    return _usesMetaShortcuts ? '⌘⇧C' : 'Ctrl+Shift+C';
  }

  String _sessionPasteShortcutLabel() {
    return _usesMetaShortcuts ? '⌘V' : 'Ctrl+V';
  }

  String _pasteHistoryShortcutLabel() {
    return _usesMetaShortcuts ? '⌘⇧H' : 'Ctrl+Shift+H';
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

  List<ShellStatusModeItem> _statusModeItemsFor(
    String sessionId,
    terminal.TerminalFrameModes modes,
  ) {
    final items = <ShellStatusModeItem>[];
    if (modes.alternateScreen) {
      items.add(
        const ShellStatusModeItem(
          key: Key('shell-status-mode-alt'),
          label: 'ALT',
          tooltip: 'Alternate screen buffer is active.',
          semanticsLabel: 'Terminal mode: alternate screen buffer active',
        ),
      );
    }
    if (modes.mouseMode != 'off') {
      final mouseMode = _mouseModeStatusLabel(modes.mouseMode);
      final mouseEncoding = _mouseEncodingStatusLabel(modes.mouseEncoding);
      items.add(
        ShellStatusModeItem(
          key: const Key('shell-status-mode-mouse'),
          label: 'MOUSE',
          tooltip: 'Mouse reporting is active: $mouseMode, $mouseEncoding.',
          semanticsLabel: 'Terminal mode: mouse reporting active',
        ),
      );
    }
    if (modes.bracketedPaste) {
      items.add(
        const ShellStatusModeItem(
          key: Key('shell-status-mode-paste'),
          label: 'PASTE',
          tooltip: 'Bracketed paste mode is active.',
          semanticsLabel: 'Terminal mode: bracketed paste active',
        ),
      );
    }
    if (_isSessionReadOnly(sessionId)) {
      items.add(
        const ShellStatusModeItem(
          key: Key('shell-status-mode-read-only'),
          label: 'READ ONLY',
          tooltip:
              'Read-only mode is enabled for this pane. Input and paste sends are blocked.',
          semanticsLabel: 'Terminal pane is read-only',
        ),
      );
    }
    return items;
  }

  String _mouseModeStatusLabel(String mode) {
    return switch (mode) {
      'normal' => 'normal tracking',
      'button_event' => 'button-event tracking',
      'any_event' => 'any-event tracking',
      _ => mode.replaceAll('_', ' '),
    };
  }

  String _mouseEncodingStatusLabel(String encoding) {
    return switch (encoding) {
      'sgr' => 'SGR encoding',
      'utf8' => 'UTF-8 encoding',
      'urxvt' => 'URXVT encoding',
      'default' => 'default encoding',
      _ => '${encoding.replaceAll('_', ' ')} encoding',
    };
  }
}
