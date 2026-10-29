part of 'terminal_ai_workspace.dart';

/// The original Composer model owns local edits/candidates; AI remains the only
/// submission owner. Accepting a suggestion is always a separate edit.
extension _WorkspaceComposer on _TerminalAiWorkspaceState {
  bool get _humanCommandOwnsTerminal {
    final action = c.transcript
        .where((entry) => entry.action != null)
        .lastOrNull;
    return c.inputIntentChoice != InputIntentChoice.ai &&
        c.isUserCommand(action?.action) &&
        (action?.state == AiEntryState.accepted ||
            action?.state == AiEntryState.submitted) &&
        (_commandEditor?.ownership == ComposerOwnership.running ||
            _commandEditor?.ownership == ComposerOwnership.submitting);
  }

  bool get _canCommandEdit =>
      _paneInteractive &&
      !c.followUpEnded &&
      !c.busy &&
      !c.hasUnresolvedSubmission &&
      !widget.fullScreenTerminal &&
      c.pending == null &&
      c.attachments.isEmpty &&
      c.inputIntentChoice != InputIntentChoice.ai &&
      _commandEditor?.ownership == ComposerOwnership.ready;

  void _restoreCommandFocus() {
    final session = widget.commandSession;
    if (session == null ||
        !_paneInteractive ||
        _mobile ||
        !session.enabled ||
        c.busy ||
        c.pending != null ||
        _commandEditor?.ownership != ComposerOwnership.ready ||
        !session.runningFocus.hasFocus ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _focus.requestFocus();
  }

  void _commandSessionChanged() {
    final session = widget.commandSession;
    if (!mounted ||
        session == null ||
        session.enabled ||
        session.mode.state.notice != TerminalModeNotice.normalFallback ||
        session.mode.state.unavailableReason ==
            BlockUnavailableReason.checking ||
        !_paneInteractive ||
        c.busy ||
        c.pending != null ||
        c.hasUnresolvedSubmission) {
      return;
    }
    final action = c.transcript
        .where((entry) => entry.action != null)
        .lastOrNull;
    // A manually launched TUI/nested shell keeps the original Composer's
    // terminal handoff. Agent commands still require explicit takeover.
    if (!c.isUserCommand(action?.action) ||
        action?.state != AiEntryState.accepted ||
        action?.target?.sessionId != session.sessionId) {
      return;
    }
    final task = c.taskId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_paneInteractive ||
          c.taskId != task ||
          session.enabled ||
          c.busy ||
          c.pending != null ||
          c.hasUnresolvedSubmission ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      widget.onTakeOver?.call();
    });
  }

  bool get _hasCommandCandidate =>
      _canCommandEdit &&
      (_commandEditor?.historyOpen == true ||
          _commandEditor?.selectedIndex != -1 &&
              _commandEditor?.completionMenuOpen == true);

  void _chooseInputIntent(InputIntentChoice choice) {
    _commandEditor?.dismissHistory();
    _commandEditor?.dismissCompletions();
    c.chooseInputIntent(choice);
  }

  void _acceptedCommandEdit() {
    if (!mounted ||
        !_paneInteractive ||
        c.followUpEnded ||
        c.busy ||
        c.hasUnresolvedSubmission) {
      return;
    }
    c.chooseInputIntent(InputIntentChoice.command);
    _focus.requestFocus();
  }

  bool _acceptCommandCandidate() {
    final model = _commandEditor;
    if (model == null || !_hasCommandCandidate) return false;
    if (model.historyOpen) {
      model.acceptHistory();
    } else {
      model.accept();
    }
    _acceptedCommandEdit();
    return true;
  }

  void _syncCommandEditor() {
    // State/ownership can change during host layout. Revoke candidates before
    // the next key event, and update the overlay after the layout is complete.
    if (_commandHasDependencies) {
      _commandEditor?.setActive(
        _canCommandEdit && !_draftEditorOpen,
        deferNotification: true,
      );
    }
    _commandEditorChanged();
  }

  void _commandEditorChanged() {
    if (!mounted || _commandUpdateScheduled || _commandEditor == null) return;
    _commandUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _commandUpdateScheduled = false;
      if (!mounted) return;
      final model = _commandEditor!;
      if (model.ownership == ComposerOwnership.ready &&
          model.readyLease != _lastCommandLease) {
        _lastCommandLease = model.readyLease;
        if (model.readyLease != _submittedCommandLease) {
          _submittedCommandHeight = null;
        }
        if (!c.busy) unawaited(c.refreshContext());
      }
      _restoreCommandFocus();
      _commandSessionChanged();
      model.setActive(_canCommandEdit && !_draftEditorOpen);
      final show =
          _canCommandEdit &&
          _focus.hasFocus &&
          !_draftEditorOpen &&
          ModalRoute.of(context)?.isCurrent != false &&
          _input.value.composing.isCollapsed &&
          (model.historyOpen ||
              model.completionMenuOpen ||
              model.loading ||
              model.completionStatus.isNotEmpty);
      final opening = show && !_completionOverlay.isShowing;
      if (opening) _completionOverlay.show();
      if (!show && _completionOverlay.isShowing) _completionOverlay.hide();
      final navigation =
          _completionNavigation != model.selectionNavigationRevision;
      _completionNavigation = model.selectionNavigationRevision;
      _refreshMobile(() {});
      if (show && (opening || navigation)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_completionScroll.hasClients) return;
          final index = model.historyOpen
              ? model.historySelectedIndex
              : model.selectedIndex;
          if (index < 0) return;
          final extent = ComposerSuggestions.rowExtent(
            MediaQuery.textScalerOf(context),
            inlineDetail:
                !model.historyOpen &&
                _completionWidth < MediaQuery.textScalerOf(context).scale(600),
            tokens: ComposerTheme.of(context),
          );
          final position = _completionScroll.position;
          final top = 4 + index * extent;
          final bottom = top + extent + 4;
          final target = top < position.pixels
              ? top
              : bottom > position.pixels + position.viewportDimension
              ? bottom - position.viewportDimension
              : position.pixels;
          if (target != position.pixels) {
            _completionScroll.jumpTo(
              target.clamp(0.0, position.maxScrollExtent),
            );
          }
        });
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  KeyEventResult _commandKey(KeyEvent event) {
    final model = _commandEditor;
    if (model == null ||
        !_paneInteractive ||
        c.followUpEnded ||
        !_input.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final down = event is KeyDownEvent;
    final repeat = event is KeyRepeatEvent;
    if (!down && !repeat) return KeyEventResult.ignored;
    final command = Theme.of(context).platform == TargetPlatform.macOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    if (_canCommandEdit &&
        command &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      final blocks = widget.commandSession!.blocks;
      if (blocks.blocks.isNotEmpty) {
        model.dismissHistory();
        model.dismissCompletions();
        _follow = false;
        blocks.move(key == LogicalKeyboardKey.arrowUp ? -1 : 1);
        return KeyEventResult.handled;
      }
    }
    if (command && key == LogicalKeyboardKey.keyZ) {
      model.dismissHistory();
      keyboard.isShiftPressed ? model.redo() : model.undo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (keyboard.isShiftPressed ||
          keyboard.isAltPressed ||
          keyboard.isControlPressed) {
        if (down) model.insertNewline();
        return KeyEventResult.handled;
      }
      if (_hasCommandCandidate) {
        if (down) _acceptCommandCandidate();
        return KeyEventResult.handled;
      }
    }
    if (!_canCommandEdit) return KeyEventResult.ignored;
    model.setActive(true);
    if (keyboard.isControlPressed && key == LogicalKeyboardKey.keyR) {
      model.openHistory();
      return KeyEventResult.handled;
    }
    if (keyboard.isControlPressed &&
        key == LogicalKeyboardKey.keyC &&
        !keyboard.isMetaPressed) {
      // A selected range keeps the platform copy shortcut; an empty selection
      // clears only the local draft, never writes Ctrl+C to the shell.
      if (!_input.selection.isCollapsed) return KeyEventResult.ignored;
      model.clearDraft();
      return KeyEventResult.handled;
    }
    if (!keyboard.isShiftPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        (key == LogicalKeyboardKey.arrowRight ||
            keyboard.isControlPressed &&
                (key == LogicalKeyboardKey.keyF ||
                    key == LogicalKeyboardKey.keyE))) {
      if (model.acceptInline(
        partial:
            key == LogicalKeyboardKey.arrowRight && keyboard.isControlPressed,
      )) {
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.tab &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed) {
      if (down) {
        if (keyboard.isShiftPressed) {
          model.dismissCompletions();
          model.dismissHistory();
          FocusScope.of(context).previousFocus();
        } else {
          model.completeOnTab();
        }
      }
      return KeyEventResult.handled;
    }
    if (!keyboard.isShiftPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed &&
        (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      final delta = key == LogicalKeyboardKey.arrowUp ? -1 : 1;
      if (model.historyOpen) {
        model.selectHistory(delta);
      } else if (model.completionMenuOpen) {
        model.selectNext(delta);
      } else if (delta < 0 &&
          _commandField.currentState?.onFirstVisualLine == true) {
        model.openHistory();
      } else if (delta > 0 &&
          _commandField.currentState?.hasSingleVisualLine == true &&
          model.items.isNotEmpty) {
        model.selectNext(1);
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (model.historyOpen) {
        model.dismissHistory();
      } else if (model.completionMenuOpen ||
          model.loading ||
          model.completionStatus.isNotEmpty) {
        model.dismissCompletions();
        model.dismissInline();
      } else if (model.inlineSuggestion.isNotEmpty) {
        model.dismissInline();
      } else if (!_input.selection.isCollapsed) {
        _input.selection = TextSelection.collapsed(
          offset: _input.selection.extentOffset,
        );
      } else {
        widget.onTakeOver?.call();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _commandPrompt({
    required int maxLines,
    String? hintText,
    required bool dense,
  }) {
    final model = _commandEditor!;
    return LayoutBuilder(
      builder: (context, bounds) {
        _completionWidth = bounds.maxWidth;
        return TextFieldTapRegion(
          child: OverlayPortal.overlayChildLayoutBuilder(
            key: _completionPortalKey,
            controller: _completionOverlay,
            overlayChildBuilder: (context, info) {
              final origin = MatrixUtils.transformPoint(
                info.childPaintTransform,
                Offset.zero,
              );
              final available =
                  (origin.dy - MediaQuery.paddingOf(context).top - 8).clamp(
                    0.0,
                    320.0,
                  );
              final width = bounds.maxWidth.clamp(0.0, info.overlaySize.width);
              return Positioned(
                left: origin.dx.clamp(
                  0.0,
                  (info.overlaySize.width - width).clamp(0.0, double.infinity),
                ),
                bottom: (info.overlaySize.height - origin.dy + 6).clamp(
                  0.0,
                  double.infinity,
                ),
                width: width,
                child: TextFieldTapRegion(
                  child: !_canCommandEdit
                      ? const SizedBox.shrink()
                      : model.historyOpen || model.completionMenuOpen
                      ? ComposerSuggestions(
                          model: model,
                          canInteract: () =>
                              mounted && _canCommandEdit && !_draftEditorOpen,
                          scroll: _completionScroll,
                          chinese: zh,
                          maxHeight: available,
                          onAccepted: _acceptedCommandEdit,
                          onClosed: _focus.requestFocus,
                        )
                      : Material(
                          elevation: 4,
                          color: ComposerTheme.of(context).popover,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: available),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                model.loading
                                    ? t('Finding completions…', '正在查找补全…')
                                    : switch (model.completionStatus) {
                                        'completion_selection' => t(
                                          'Move the cursor to the completion position first.',
                                          '请先将光标移到要补全的位置。',
                                        ),
                                        'completion_unavailable' => t(
                                          'Completions unavailable. Continue editing.',
                                          '补全暂不可用，可继续编辑。',
                                        ),
                                        'unsupported_context' => t(
                                          'No completions for this shell expression.',
                                          '此 shell 表达式暂不提供补全。',
                                        ),
                                        _ => t(
                                          'No matching completions.',
                                          '没有匹配的补全项。',
                                        ),
                                      },
                                key: const Key('ai-completion-feedback'),
                              ),
                            ),
                          ),
                        ),
                ),
              );
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: _mobile ? 0 : _submittedCommandHeight ?? 0,
              ),
              child: ComposerEditor(
                key: _commandField,
                fieldKey: const Key('ai-prompt'),
                controller: _input,
                focusNode: _focus,
                autofocus: false,
                readOnly:
                    c.followUpEnded ||
                    !_paneInteractive ||
                    _humanCommandOwnsTerminal,
                suggestion: _canCommandEdit && _focus.hasFocus
                    ? model.inlineSuggestion
                    : '',
                suggestionColor: context.appTheme.textMuted,
                style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                  height: 1.5,
                  fontFamily: _commandIntent
                      ? ComposerTheme.of(context).commandStyle.fontFamily
                      : null,
                  fontFamilyFallback: _commandIntent
                      ? ComposerTheme.of(
                          context,
                        ).commandStyle.fontFamilyFallback
                      : null,
                ),
                hint: model.historyOpen
                    ? t('Filter command history…', '筛选历史命令…')
                    : hintText ??
                          (_commandIntent
                              ? t('Enter a command…', '输入命令…')
                              : t('Ask AI…', '向 AI 提问…')),
                maxLines: maxLines,
                centerVertically: dense,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _commandActions() {
    final model = _commandEditor!;
    return PopupMenuButton<String>(
      key: const Key('ai-command-actions'),
      requestFocus: !_mobile,
      onCanceled: () {
        if (mounted && _paneInteractive) _focus.requestFocus();
      },
      tooltip: t('Command editing actions', '命令编辑操作'),
      enabled: _paneInteractive && !c.followUpEnded,
      icon: Icon(
        Icons.more_horiz,
        size: 18,
        semanticLabel: t('Command editing actions', '命令编辑操作'),
      ),
      onSelected: (action) async {
        if (!_paneInteractive || c.followUpEnded) return;
        switch (action) {
          case 'history':
            if (_canCommandEdit) {
              model.setActive(true);
              model.openHistory();
            }
          case 'complete':
            if (_canCommandEdit) {
              model.setActive(true);
              model.completeOnTab();
            }
          case 'suggest':
            if (_canCommandEdit) model.toggleLocalSuggestions();
          case 'copy':
            try {
              await Clipboard.setData(ClipboardData(text: _input.text));
            } on PlatformException {
              if (mounted) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  SnackBar(
                    content: Text(t('Could not copy the draft.', '无法复制草稿。')),
                  ),
                );
              }
            }
          case 'undo':
            model.dismissHistory();
            model.undo();
          case 'redo':
            model.dismissHistory();
            model.redo();
          case 'clear':
            model.clearDraft();
          case 'help':
            await showDialog<void>(
              context: context,
              builder: (context) => const CommandShortcutsDialog(),
            );
        }
        if (mounted && _paneInteractive) _focus.requestFocus();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'complete',
          enabled: _canCommandEdit,
          child: Text(t('Complete · Tab', '补全 · Tab')),
        ),
        PopupMenuItem(
          value: 'history',
          enabled: _canCommandEdit,
          child: Text(t('Command history · Ctrl+R', '命令历史 · Ctrl+R')),
        ),
        CheckedPopupMenuItem(
          value: 'suggest',
          enabled: _canCommandEdit,
          checked: model.localSuggestions,
          child: Text(t('Automatic suggestions', '自动建议')),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'copy',
          enabled: _input.text.isNotEmpty,
          child: Text(t('Copy draft', '复制草稿')),
        ),
        PopupMenuItem(
          value: 'undo',
          enabled: model.canUndo,
          child: Text(t('Undo', '撤销')),
        ),
        PopupMenuItem(
          value: 'redo',
          enabled: model.canRedo,
          child: Text(t('Redo', '重做')),
        ),
        PopupMenuItem(
          value: 'clear',
          enabled: _input.text.isNotEmpty,
          child: Text(t('Clear draft', '清空草稿')),
        ),
        PopupMenuItem(
          value: 'help',
          child: Text(t('Keyboard shortcuts', '键盘快捷键')),
        ),
      ],
    );
  }
}
