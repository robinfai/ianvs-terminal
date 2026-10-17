part of 'terminal_ai_workspace.dart';

/// A presentation of the existing task, never another execution loop. The host
/// opts in when it already provides the phone's session navigation.
extension _TerminalAiMobilePresentation on _TerminalAiWorkspaceState {
  bool get _useCompactMobile => widget.compactMobile && _mobile;

  bool get _mobileCanSubmit {
    if (!_mobileActionAllowed ||
        c.followUpEnded ||
        (!_hasCommandCandidate && _input.text.trim().isEmpty) ||
        !_input.value.composing.isCollapsed) {
      return false;
    }
    if (_commandIntent) return c.canRunUserCommand;
    // Unknown outcomes retain the existing *local* deferred-requirement path.
    // A disconnected terminal alone does not enable offline model requests.
    if (c.hasUnresolvedSubmission) return true;
    return c.terminalError == null && !c.targetChanged && !_reconnecting;
  }

  bool get _mobileActionAllowed {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return mounted &&
        _paneInteractive &&
        !_mobileDetailsOpen &&
        ModalRoute.of(context)?.isCurrent != false &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
  }

  String get _mobileStatus {
    if (c.hasUnresolvedSubmission) {
      return c.followUpEnded
          ? t('Follow-up ended · outcome unknown', '已结束跟进 · 原结果未知')
          : t('Submission unknown · may have run', '提交结果未知 · 可能已执行');
    }
    if (_reconnecting) return t('Reconnecting and inspecting…', '正在重连并检查…');
    if (c.terminalError != null) return t('Terminal unavailable', '终端不可用');
    if (c.targetChanged) return t('Execution target changed', '执行目标已变化');
    if (_mobileRecoveryNotice != null) return _mobileRecoveryNotice!;
    if (c.followUpEnded) return t('Follow-up ended · read-only', '已结束跟进 · 只读');
    if (c.generationCancelled) {
      return t(
        'Generation cancelled · command is not interrupted',
        '已取消生成 · 命令未被中断',
      );
    }
    if (c.phase == AiPhase.idle && c.takenOver) {
      final running =
          c.context?.runningCommand?.isNotEmpty == true &&
          c.context?.canRunCommand == false;
      return running
          ? t('AI paused · command still running', 'AI 已暂停，命令仍在运行')
          : t('AI paused', 'AI 已暂停');
    }
    if (widget.unifiedWorkspace &&
        c.phase == AiPhase.idle &&
        c.transcript.isEmpty) {
      return c.context?.canRunCommand == true
          ? t('Shell ready', 'Shell 就绪')
          : t('Waiting for shell', '等待终端就绪');
    }
    return _status;
  }

  String get _mobileDraftHint {
    if (c.followUpEnded) return t('This task is read-only', '此任务已结束跟进，只读');
    if (c.hasUnresolvedSubmission && !_commandIntent) {
      return t('Add a requirement · saved only', '补充要求，仅暂存…');
    }
    if (c.terminalError != null) {
      return t('Offline · draft only', '终端不可用，可先写草稿…');
    }
    if (c.targetChanged) {
      return t('Target changed · draft only', '目标已变化，可先写草稿…');
    }
    return _commandIntent
        ? t('Enter a command…', '输入命令…')
        : t('Ask AI…', '向 AI 提问…');
  }

  ({String id, String label})? get _mobilePrimaryAction {
    if (c.hasUnresolvedSubmission) {
      return (id: 'check', label: t('Check receipt', '检查原提交'));
    }
    if (c.terminalError != null) {
      return widget.onReconnect != null
          ? (id: 'reconnect', label: t('Reconnect', '重新连接'))
          : (id: 'check', label: t('Check status', '检查状态'));
    }
    if (c.followUpEnded) return (id: 'new', label: t('New task', '新建任务'));
    if (c.targetChanged) {
      return (id: 'details', label: t('Review target', '确认目标'));
    }
    if (c.canApprove) return (id: 'review', label: t('Review', '审阅命令'));
    if (c.busy) return (id: 'pause', label: t('Pause AI', '暂停 AI'));
    if (c.canResume) return (id: 'resume', label: t('Continue', '继续任务'));
    if (c.error != null || _mobileRecoveryNotice != null) {
      return (id: 'details', label: t('Details', '查看详情'));
    }
    return null;
  }

  bool _mobileActionEnabled(String action) {
    if (!_mobileActionAllowed) return false;
    if (action == 'details' || action == 'observe') return true;
    if (_reconnecting) return false;
    if (action == 'reconnect' || action == 'check') return !c.checkingTerminal;
    if (action == 'resume') return !_resuming && c.canResume;
    if (action == 'review') return c.canApprove;
    if (action == 'pause') return c.busy || c.canApprove;
    if (action == 'interrupt') return c.canInterrupt;
    if (action == 'end') return c.canEndFollowUp;
    if (action == 'new') return !c.hasUnresolvedSubmission || c.followUpEnded;
    return true;
  }

  Future<void> _runMobileAction(String action) async {
    if (!_mobileActionEnabled(action)) return;
    if (action == 'details') {
      await _showMobileDetails();
      return;
    }
    final owner = c;
    final taskId = c.taskId;
    final paneRevision = _paneRevision;
    bool current() =>
        mounted &&
        identical(c, owner) &&
        c.taskId == taskId &&
        _paneRevision == paneRevision;
    try {
      switch (action) {
        case 'check':
          _refreshMobile(() => _mobileRecoveryNotice = null);
          await owner.refreshContext();
        case 'reconnect':
          final reconnect = widget.onReconnect;
          if (reconnect == null || owner.terminalError == null) return;
          _refreshMobile(() {
            _reconnecting = true;
            _mobileRecoveryNotice = null;
          });
          // The host reconciles old receipts and transfers drafts; no ask,
          // approval, resume or command is sent by this presentation callback.
          await reconnect();
        case 'observe':
          _observeTerminal();
        case 'takeover':
          if (widget.onTakeOver == null) return;
          _focus.unfocus();
          widget.onTakeOver!();
        case 'pause':
          owner.takeOver(); // Revokes AI input, NOT Ctrl+C.
        case 'interrupt':
          await owner.interruptCommand();
        case 'resume':
          await _resume(); // Keeps target/revision/identity checks.
        case 'review':
          final entry = owner.transcript
              .where(
                (entry) =>
                    entry.action?.id == owner.pending?.id &&
                    entry.revision == owner.proposalRevision &&
                    entry.state == AiEntryState.proposed,
              )
              .firstOrNull;
          if (entry != null) await _review(entry);
        case 'ssh-settings':
          await widget.onConfigureTerminal?.call();
        case 'ai-settings':
          await _openSettings();
        case 'end':
          owner.endFollowUp();
        case 'new':
          _savePosition();
          owner.newTask();
        case 'latest':
          _showLatest();
        case 'return':
          _returnToReading();
      }
    } on Object catch (failure) {
      if (current()) {
        _refreshMobile(() {
          _mobileRecoveryNotice = failure is AiFailure
              ? aiErrorText(failure.code, zh)
              : t('Action incomplete · open details', '操作未完成，请查看详情');
        });
      }
    } finally {
      if (mounted && identical(c, owner) && action == 'reconnect') {
        _refreshMobile(() => _reconnecting = false);
      }
    }
  }

  Future<void> _showMobileDetails() async {
    if (!_mobileActionAllowed) return;
    final owner = c;
    final taskId = c.taskId;
    final paneRevision = _paneRevision;
    bool current() =>
        mounted &&
        identical(c, owner) &&
        c.taskId == taskId &&
        _paneRevision == paneRevision &&
        _paneInteractive;
    _focus.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    _replyFocusAllowed = false;
    _refreshMobile(() => _mobileDetailsOpen = true);
    String? action;
    try {
      action = await showModalBottomSheet<String>(
        context: context,
        sheetAnimationStyle: appDialogAnimation(context),
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => ListenableBuilder(
          listenable: owner,
          builder: (context, _) {
            Widget choice(
              String id,
              String label,
              IconData icon, {
              bool enabled = true,
              String? description,
            }) => ListTile(
              key: ValueKey('ai-mobile-detail-$id'),
              leading: Icon(icon),
              title: Text(label),
              subtitle: description == null ? null : Text(description),
              enabled: current() && enabled,
              onTap: current() && enabled
                  ? () => Navigator.pop(sheetContext, id)
                  : null,
            );
            return SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .8,
                ),
                child: ListView(
                  key: const Key('ai-mobile-details'),
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            t('Task details', '任务详情'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: t('Close', '关闭'),
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    if (!current())
                      Text(
                        t(
                          'Task changed. Close and review the current task.',
                          '任务已变化，请关闭后查看当前任务。',
                        ),
                      )
                    else ...[
                      Text(_mobileStatus),
                      const SizedBox(height: 8),
                      SelectableText(
                        '${owner.terminalError == null ? t('Target', '执行目标') : t('Last known target', '上次目标')}：'
                        '${widget.targetLabel}\n${owner.context?.cwd ?? ''}',
                      ),
                      if (owner.hasUnresolvedSubmission)
                        Text(
                          t(
                            'The command may have run. Inspect its original receipt; it will not be resent.',
                            '命令可能已经执行。请检查原提交，不会重发原命令。',
                          ),
                        ),
                      if (owner.terminalError != null)
                        Text(
                          aiErrorText(owner.terminalError!, zh),
                          key: const Key('ai-terminal-error'),
                        ),
                      if (owner.error != null &&
                          owner.error != owner.terminalError)
                        Text(
                          aiErrorText(owner.error!, zh),
                          key: const Key('ai-error'),
                        ),
                      if (_mobileRecoveryNotice != null)
                        Text(_mobileRecoveryNotice!),
                      if (owner.targetChanged &&
                          owner.originalTarget != null &&
                          owner.context != null)
                        AiTargetComparison(
                          original: owner.originalTarget!,
                          current: owner.context!,
                          zh: zh,
                        ),
                      const Divider(),
                      if (owner.hasUnresolvedSubmission ||
                          owner.terminalError != null)
                        choice(
                          'check',
                          owner.hasUnresolvedSubmission
                              ? t('Check original submission', '检查原提交')
                              : t('Check terminal status', '检查终端状态'),
                          Icons.refresh,
                          enabled: !owner.checkingTerminal && !_reconnecting,
                        ),
                      if (owner.terminalError != null &&
                          widget.onReconnect != null)
                        choice(
                          'reconnect',
                          t('Reconnect and inspect', '重新连接并检查'),
                          Icons.sync,
                          enabled: !owner.checkingTerminal && !_reconnecting,
                          description: t(
                            'No automatic draft submission or command replay.',
                            '不会自动发送草稿，也不会重放原命令。',
                          ),
                        ),
                      choice(
                        'observe',
                        t('View terminal (read-only)', '只读查看终端'),
                        Icons.visibility_outlined,
                      ),
                      if (owner.busy || owner.canApprove)
                        choice(
                          'pause',
                          t('Pause AI', '暂停 AI'),
                          Icons.pause_circle_outline,
                          description: t(
                            'Does not interrupt a running command.',
                            '不会中断正在运行的命令。',
                          ),
                        ),
                      if (owner.canResume)
                        choice(
                          'resume',
                          _resumeLabel,
                          Icons.play_arrow_outlined,
                          enabled: !_resuming,
                        ),
                      if (widget.onTakeOver != null)
                        choice(
                          'takeover',
                          t('Take over terminal input', '接管终端输入'),
                          Icons.keyboard_outlined,
                          description: t(
                            'Pauses AI before restoring manual input.',
                            '先暂停 AI，再交还人工输入权。',
                          ),
                        ),
                      if (owner.canInterrupt)
                        choice(
                          'interrupt',
                          t(
                            'Interrupt ${owner.context?.runningCommand}',
                            '中断 ${owner.context?.runningCommand}',
                          ),
                          Icons.stop_circle_outlined,
                          description: t(
                            'Sends Ctrl+C to the current command.',
                            '向当前命令发送 Ctrl+C。',
                          ),
                        ),
                      if (widget.onConfigureTerminal != null &&
                          owner.terminalError != null)
                        choice(
                          'ssh-settings',
                          t('SSH connection settings', 'SSH 连接设置'),
                          Icons.settings_outlined,
                        ),
                      choice(
                        'ai-settings',
                        t('AI connection', 'AI 连接'),
                        Icons.tune,
                      ),
                      if (_returnOffset != null)
                        choice(
                          'return',
                          t('Return to reading position', '返回阅读位置'),
                          Icons.undo,
                        ),
                      if (owner.canEndFollowUp)
                        choice(
                          'end',
                          t('End follow-up', '结束跟进'),
                          Icons.stop_outlined,
                          description: t(
                            'Retains the unknown outcome. Does not stop or resend the command.',
                            '保留结果未知的记录，不中断或重发命令。',
                          ),
                        ),
                      if (owner.followUpEnded)
                        choice(
                          'new',
                          t('Start an independent task', '新建独立任务'),
                          Icons.add,
                        ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      );
    } finally {
      if (mounted) _refreshMobile(() => _mobileDetailsOpen = false);
    }
    // Dialog choices are intents only. Never apply a stale choice to a new
    // task/pane or fire an action from underneath a still-open modal route.
    if (action != null && current()) await _runMobileAction(action);
  }

  Widget _mobileHeader({bool short = false}) {
    final primary = _mobilePrimaryAction;
    final taskId = c.taskId;
    final paneRevision = _paneRevision;
    return Padding(
      key: const Key('ai-mobile-task-strip'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          AiRequestIndicator(controller: c),
          const SizedBox(width: 8),
          Expanded(
            child: PopupMenuButton<String>(
              key: const Key('ai-mobile-task-menu'),
              enabled: _mobileActionAllowed,
              tooltip: t('Session tasks and controls', '会话任务与操作'),
              popUpAnimationStyle: appDialogAnimation(context),
              onSelected: (id) {
                if (!_mobileActionAllowed ||
                    c.taskId != taskId ||
                    _paneRevision != paneRevision) {
                  return;
                }
                if (id == 'mobile:new') {
                  unawaited(_runMobileAction('new'));
                } else if (id == 'mobile:details') {
                  unawaited(_showMobileDetails());
                } else if (id == 'mobile:observe') {
                  _observeTerminal();
                } else if (c.tasks.any((task) => task.id == id)) {
                  _savePosition();
                  c.selectTask(id);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'mobile:new',
                  key: const Key('ai-new-task'),
                  enabled: !c.hasUnresolvedSubmission || c.followUpEnded,
                  child: Text(t('New task', '新任务')),
                ),
                PopupMenuItem(
                  value: 'mobile:details',
                  child: Text(t('Details and controls', '详情与控制')),
                ),
                PopupMenuItem(
                  value: 'mobile:observe',
                  key: const Key('ai-observe-terminal'),
                  child: Text(t('View terminal (read-only)', '只读查看终端')),
                ),
                const PopupMenuDivider(),
                for (final task in c.tasks)
                  CheckedPopupMenuItem(
                    value: task.id,
                    checked: task.id == c.taskId,
                    child: Text(
                      task.title.isEmpty ? t('New task', '新任务') : task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, bounds) {
                          final title = Text(
                            c.taskTitle.isEmpty
                                ? (widget.unifiedWorkspace
                                      ? 'Block + AI'
                                      : t('New task', '新任务'))
                                : c.taskTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                          );
                          final status = Semantics(
                            liveRegion: true,
                            label:
                                c.phase == AiPhase.observing &&
                                    c.terminalError == null &&
                                    !c.hasUnresolvedSubmission &&
                                    !c.targetChanged
                                ? t('AI is observing the terminal', 'AI 正在观察终端')
                                : _mobileStatus,
                            excludeSemantics: true,
                            child: Text(
                              _mobileStatus,
                              key: const Key('ai-task-status'),
                              maxLines: short ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: context.appTheme.textMuted),
                            ),
                          );
                          // Keep recovery copy readable when actions share the strip.
                          if (!short &&
                              primary == null &&
                              bounds.maxWidth >= 260) {
                            return Row(
                              children: [
                                Expanded(child: title),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: status,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                            );
                          }
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [if (!short) title, status],
                          );
                        },
                      ),
                    ),
                    const Icon(Icons.expand_more, size: 18),
                  ],
                ),
              ),
            ),
          ),
          if (primary != null) ...[
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 128),
              child: TextButton(
                key: ValueKey('ai-mobile-primary-${primary.id}'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: _mobileActionEnabled(primary.id)
                    ? () {
                        if (!mounted ||
                            c.taskId != taskId ||
                            _paneRevision != paneRevision) {
                          return;
                        }
                        unawaited(_runMobileAction(primary.id));
                      }
                    : null,
                child: Text(
                  _reconnecting && primary.id == 'reconnect'
                      ? t('Reconnecting…', '重连中…')
                      : c.checkingTerminal && primary.id == 'check'
                      ? t('Checking…', '检查中…')
                      : primary.label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
          if (c.terminalError != null || c.hasUnresolvedSubmission)
            IconButton(
              key: const Key('ai-mobile-recovery-details'),
              tooltip: t('Details', '查看详情'),
              onPressed: _mobileActionAllowed ? _showMobileDetails : null,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              icon: const Icon(Icons.info_outline, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _mobileComposer({bool short = false}) => ListenableBuilder(
    listenable: Listenable.merge([_input, _focus]),
    builder: (context, _) {
      final editing =
          _focus.hasFocus ||
          !_input.value.composing.isCollapsed ||
          _draftEditorOpen;
      // Draft contents survive reading mode; only active editing expands it.
      final hasDraft = _input.text.isNotEmpty || c.attachments.isNotEmpty;
      final keyboard = View.of(context).viewInsets.bottom > 0;
      final blocked =
          !c.hasUnresolvedSubmission &&
          (c.terminalError != null || c.targetChanged);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Container(
          key: const Key('ai-mobile-composer'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: context.appTheme.panel,
            border: Border.all(color: context.appTheme.borderStrong),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Keep the editor at the same element position when chrome grows.
                  // No AnimatedSwitcher, replacement controller or draft copy.
                  SizedBox(
                    child:
                        editing &&
                            (blocked || c.hasUnresolvedSubmission) &&
                            !short
                        ? Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 4),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                c.hasUnresolvedSubmission
                                    ? t(
                                        'Saved only · not sent or executed',
                                        '仅暂存要求，不会发送或执行',
                                      )
                                    : t(
                                        'Draft only · reconnect/confirm target before sending',
                                        '仅编辑草稿，连接或确认目标后再发送',
                                      ),
                                key: const Key('ai-mobile-draft-only'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          )
                        : null,
                  ),
                  SizedBox(
                    child: editing && _commandIntent && !short
                        ? Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton(
                              onPressed: _mobileActionAllowed
                                  ? _showMobileDetails
                                  : null,
                              child: Text(
                                '${widget.targetLabel} · ${c.context?.cwd ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                        : null,
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      children: [
                        SizedBox(
                          width: editing && !short
                              ? 0
                              : ComposerIntentMenu.slotWidth,
                        ),
                        Expanded(
                          child: _prompt(
                            maxLines: short || !editing ? 1 : 4,
                            hintText: _mobileDraftHint,
                            dense: true,
                          ),
                        ),
                        if ((short || !editing) && (editing || hasDraft))
                          _expandDraftButton(),
                        if (short && (keyboard || _focus.hasFocus))
                          _hideKeyboardButton(),
                        const SizedBox(width: 4),
                        SizedBox(width: 44, child: _sendButton(iconOnly: true)),
                      ],
                    ),
                  ),
                  SizedBox(
                    child: editing && !short
                        ? Row(
                            children: [
                              const Expanded(child: SizedBox(height: 44)),
                              if (c.attachments.isNotEmpty)
                                Flexible(
                                  child: _pendingContexts(compact: true),
                                ),
                              if (_commandEditor != null) _commandActions(),
                              _expandDraftButton(),
                              if (keyboard || _focus.hasFocus)
                                _hideKeyboardButton(),
                            ],
                          )
                        : null,
                  ),
                ],
              ),
              PositionedDirectional(
                start: 0,
                bottom: 0,
                width: ComposerIntentMenu.slotWidth - 8,
                child: _inputIntentMenu(condensed: true),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _mobilePage(Widget timeline, BoxConstraints bounds) {
    final short = bounds.maxHeight < 320;
    // The same scroll/controller/editor subtrees survive rotation and keyboard
    // changes. Very short viewports scroll the chrome rather than shrink taps.
    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: bounds.maxHeight < 160 ? bounds.maxHeight * .35 : 96,
          ),
          child: SingleChildScrollView(child: _mobileHeader(short: short)),
        ),
        Divider(height: 1, color: context.appTheme.border),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.depth == 0 &&
                      (notification is ScrollStartNotification &&
                              notification.dragDetails != null ||
                          notification is UserScrollNotification &&
                              notification.direction != ScrollDirection.idle)) {
                    _follow = false;
                    _replyFocusAllowed = false;
                    _positionRevision++;
                    _restoringPosition = false;
                  }
                  return false;
                },
                child: Listener(
                  onPointerDown: (_) => _replyFocusAllowed = false,
                  child: KeyedSubtree(key: ValueKey(_taskId), child: timeline),
                ),
              ),
              AnimatedBuilder(
                animation: Listenable.merge([_scroll, _following]),
                builder: (context, _) {
                  if (_follow ||
                      !_scroll.hasClients ||
                      _scroll.position.extentAfter <= 48) {
                    return const SizedBox.shrink();
                  }
                  return PositionedDirectional(
                    end: 12,
                    bottom: 8,
                    child: Material(
                      color: context.appTheme.panel,
                      elevation: 2,
                      borderRadius: BorderRadius.circular(20),
                      child: TextButton.icon(
                        key: const Key('ai-show-latest'),
                        onPressed: _mobileActionAllowed ? _showLatest : null,
                        icon: const Icon(
                          Icons.arrow_downward_outlined,
                          size: 18,
                        ),
                        label: Text(t('Latest', '回到最新')),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: short ? bounds.maxHeight * .55 : bounds.maxHeight * .45,
          ),
          child: SingleChildScrollView(child: _mobileComposer(short: short)),
        ),
      ],
    );
  }
}
