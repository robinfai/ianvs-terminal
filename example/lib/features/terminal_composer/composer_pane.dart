import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../preferences/app_preferences_models.dart';
import '../sessions/session_state.dart';
import 'terminal_mode.dart';

/// App lifecycle and runtime assembly. Drafts remain in memory per session.
final class ComposerPaneSession extends ChangeNotifier {
  ComposerPaneSession({
    required this.sessionId,
    required this.runtime,
    TerminalViewMode preferredMode = TerminalViewMode.normal,
  }) : mode = TerminalModeController(preferredMode: preferredMode) {
    controller = TerminalComposerController(
      targetId: sessionId,
      provider: (query, cancellation) async {
        if (cancellation.isCancelled) return CompletionBatch(query, const []);
        final json = runtime.composerRequest(
          sessionId,
          'completion.query',
          query.toJson(),
        );
        if (json == null) throw StateError('Completion unavailable');
        final staticBatch = CompletionBatch.fromJson(query, json);
        if (cancellation.isCancelled) return staticBatch;
        controller.publishCompletions(staticBatch, cancellation: cancellation);
        final lease = controller.readyLease;
        if (!controller.allowsLocalSuggestions(cancellation) || lease == null) {
          return staticBatch;
        }
        final start = runtime.composerRequest(
          sessionId,
          'completion.local_start',
          {
            'query': query.toJson(),
            'lease': lease,
            'policy': {'files': true, 'scripts': true},
          },
        );
        final job = start?['jobId'];
        if (start?['status'] != 'pending' || job is! String) return staticBatch;
        try {
          final deadline = DateTime.now().add(
            const Duration(milliseconds: 300),
          );
          while (!_disposed &&
              !cancellation.isCancelled &&
              DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            if (_disposed || cancellation.isCancelled) break;
            final poll = runtime.composerRequest(
              sessionId,
              'completion.local_poll',
              {'jobId': job},
            );
            if (poll?['status'] != 'pending') {
              final rawBatch = poll?['batch'];
              if (rawBatch is! Map || poll?['status'] != 'complete') break;
              final localBatch = CompletionBatch.fromJson(
                query,
                rawBatch.cast<String, Object?>(),
              );
              final edits = <String, CompletionEdit>{};
              // Preserve static order and selected item identity while adding IO.
              for (final item in [...staticBatch.items, ...localBatch.items]) {
                edits.putIfAbsent(
                  '${item.start}:${item.end}:${item.newText}',
                  () => item,
                );
              }
              return CompletionBatch(query, edits.values.take(100).toList());
            }
          }
        } finally {
          if (!_disposed) {
            runtime.composerRequest(sessionId, 'completion.local_cancel', {
              'jobId': job,
            });
          }
        }
        return staticBatch;
      },
      submit: _submit,
    );
    mode.addListener(_modeChanged);
  }

  final String sessionId;
  final TerminalRuntimeController runtime;
  late final TerminalComposerController controller;
  late final CommandBlockController blocks = CommandBlockController(
    request: (request) => runtime.commandBlocks(sessionId, request),
  );
  final TerminalModeController mode;
  TerminalPane? _pane;
  bool _readOnly = false;
  bool _visible = false;
  bool _fullScreen = false;
  bool _richOutput = false;
  bool _unattributedOutput = false;
  final editorFocus = FocusNode(debugLabel: 'Pane composer');
  bool get enabled => mode.state.mode == TerminalViewMode.blocks;
  bool get fullScreen => _fullScreen;
  bool Function(int delta)? navigateBlocks;
  Timer? _pollTimer;
  bool _disposed = false;
  bool _modeNotificationScheduled = false;
  int? _historyRevision;
  String? _composerContextId;
  String? _composerTransport;

  void setVisible(bool visible, {bool deferNotification = false}) {
    if (_disposed) return;
    _visible = visible;
    _pollTimer?.cancel();
    controller.setActive(
      visible && enabled,
      deferNotification: deferNotification || _duringBuild,
    );
    if (_pane?.isExited != true) {
      // Hiding can run while widgets are unmounting. Only the timer may poll
      // inactive sessions, so backend events never fire during that teardown.
      if (visible) _poll();
      _pollTimer = Timer.periodic(
        Duration(milliseconds: visible ? 150 : 500),
        (_) => _poll(),
      );
    }
  }

  void updateEnvironment(TerminalPane pane, {required bool readOnly}) {
    _pane = pane;
    _readOnly = readOnly;
    if (pane.isExited) _pollTimer?.cancel();
    _updateMode();
  }

  /// Output can arrive before the periodic poll when another UI surface (for
  /// example terminal AI) submits directly to the same negotiated shell.
  void refreshShellState({bool recheckSupport = false}) {
    if (!_disposed && _pane?.isExited != true) {
      _poll(recheckSupport: recheckSupport);
    }
  }

  void updateOutput({
    required bool fullScreen,
    required bool richOutput,
    bool unattributedOutput = false,
  }) {
    _fullScreen = fullScreen;
    _richOutput |= richOutput;
    _unattributedOutput |= unattributedOutput;
    _updateMode();
  }

  bool selectMode(TerminalViewMode value) => mode.select(value);

  bool get _duringBuild =>
      SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks;

  void _modeChanged() {
    final deferNotification = _duringBuild;
    controller.setActive(
      _visible && enabled,
      deferNotification: deferNotification,
    );
    if (!deferNotification) {
      notifyListeners();
    } else if (!_modeNotificationScheduled) {
      // Environment updates also run from the host's LayoutBuilder. Revoke
      // input now, then publish the latest mode once outside its build scope.
      _modeNotificationScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _modeNotificationScheduled = false;
        if (!_disposed) notifyListeners();
      });
    }
  }

  void _updateMode({bool recheckSupport = false}) {
    final pane = _pane;
    final shell = pane?.shellIntegration;
    final remoteCommand = _startsRemoteCommand(shell?.runningCommand);
    final remote =
        shell?.contextKind == 'ssh' ||
        (pane?.shellConnectionChain.any(
              (hop) => hop.kind == ShellConnectionHopKind.sshShell,
            ) ??
            false) ||
        remoteCommand;
    final negotiated =
        _composerTransport == 'shell' &&
        _composerContextId == (shell?.contextId ?? 'root') &&
        (!remoteCommand || controller.ownership == ComposerOwnership.ready);
    final reason = pane?.isExited == true
        ? BlockUnavailableReason.exited
        : _readOnly
        ? BlockUnavailableReason.readOnly
        : _composerContextId != null &&
              shell?.contextId != null &&
              _composerContextId != shell!.contextId
        ? BlockUnavailableReason.checking
        : remote && !negotiated
        ? BlockUnavailableReason.remoteShell
        : shell?.contextId != null && shell!.contextId != 'root' && !negotiated
        ? BlockUnavailableReason.nestedShell
        : _fullScreen
        ? BlockUnavailableReason.fullScreen
        : _richOutput
        ? BlockUnavailableReason.richOutput
        : _unattributedOutput
        ? BlockUnavailableReason.unattributedOutput
        : switch (controller.ownership) {
            ComposerOwnership.ready when controller.readyLease != null => null,
            // An unresolved submission still needs the explicit draft recovery
            // control. Its receipt lock is not a loss of shell capability.
            ComposerOwnership.running ||
            ComposerOwnership.submitting ||
            ComposerOwnership.unknown => null,
            ComposerOwnership.suspended => BlockUnavailableReason.terminalInput,
            _ => BlockUnavailableReason.unsupportedShell,
          };
    mode.updateAvailability(reason, rechecked: recheckSupport);
  }

  // The bootstrap context is authoritative once available. Also cover a plain
  // ssh invocation while its wrapper is disabled or still connecting.
  static bool _startsRemoteCommand(String? command) => RegExp(
    r'^(?:(?:command|exec|sudo)\s+)*(?:/\S*/)?(?:ssh|mosh|telnet)(?:\s|$)',
  ).hasMatch(command?.trim() ?? '');

  void _poll({bool recheckSupport = false}) {
    if (_disposed) return;
    final json = runtime.composerRequest(sessionId, 'composer.state', const {});
    final contextId = json?['contextId'] as String?;
    final transport = json?['transport'] as String?;
    if (_composerContextId != contextId || _composerTransport != transport) {
      if (_composerContextId != null) {
        mode.updateAvailability(BlockUnavailableReason.checking);
      }
      _historyRevision = null;
      controller.updateHistory(const []);
    }
    _composerContextId = contextId;
    _composerTransport = transport;
    controller.updateIntentContext(
      InputIntentContext(
        scope: json == null ? '' : '$sessionId:$transport:$contextId',
        commandNames: {
          if (json?['commandNames'] case final List<Object?> names)
            ...names.whereType<String>(),
        },
        aliases: {
          if (json?['aliases'] case final Map<Object?, Object?> aliases)
            for (final entry in aliases.entries)
              if (entry case MapEntry(
                key: final String name,
                value: final String expansion,
              ))
                name: expansion,
        },
      ),
    );
    final state = json?['state'];
    final ownership = switch (state) {
      'ready' => ComposerOwnership.ready,
      'running' => ComposerOwnership.running,
      'submitting' => ComposerOwnership.submitting,
      'suspended' => ComposerOwnership.suspended,
      _ => ComposerOwnership.draft,
    };
    controller.updateShell(
      contextKey:
          '$transport:$contextId:${json?['lease'] ?? state ?? 'unavailable'}',
      cwd: json?['cwd'] as String? ?? '',
      lease: json?['lease'] as String?,
      dialect: json?['dialect'] as String? ?? 'generic',
      ownership: ownership,
    );
    _updateMode(recheckSupport: recheckSupport);
    final historyRevision = json?['historyRevision'];
    final history = json?['history'];
    if (historyRevision is int &&
        historyRevision != _historyRevision &&
        history is List &&
        history.every((entry) => entry is String)) {
      _historyRevision = historyRevision;
      controller.updateHistory(history.cast<String>());
    }
  }

  Future<ComposerSubmissionOutcome> _submit(
    ComposerSubmission submission,
  ) async {
    final response = runtime.composerRequest(sessionId, 'composer.submit', {
      'lease': submission.lease,
      'submissionId': submission.id,
      'text': submission.query.value.text,
    });
    if (response?['outcome'] == 'rejected') {
      return ComposerSubmissionOutcome.rejected;
    }
    if (response?['outcome'] == 'accepted') {
      return ComposerSubmissionOutcome.accepted;
    }
    if (response?['outcome'] != 'pending') {
      return ComposerSubmissionOutcome.unknown;
    }
    final deadline = DateTime.now().add(
      Duration(seconds: _composerTransport == 'shell' ? 6 : 2),
    );
    while (!_disposed && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (_disposed) break;
      final state = runtime.composerRequest(
        sessionId,
        'composer.state',
        const {},
      );
      if (state?['submissionId'] != submission.id) continue;
      switch (state?['outcome']) {
        case 'accepted':
          return ComposerSubmissionOutcome.accepted;
        case 'rejected':
          return ComposerSubmissionOutcome.rejected;
        case 'unknown':
          return ComposerSubmissionOutcome.unknown;
      }
    }
    return ComposerSubmissionOutcome.unknown;
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    mode.removeListener(_modeChanged);
    mode.dispose();
    controller.dispose();
    blocks.dispose();
    editorFocus.dispose();
    super.dispose();
  }
}

class ComposerPane extends StatefulWidget {
  const ComposerPane({
    required this.session,
    required this.targetLabel,
    required this.onTerminalFocus,
    required this.active,
    required this.available,
    this.terminalFocus,
    this.onAskAi,
    this.onOpenAi,
    super.key,
  });
  final ComposerPaneSession session;
  final String targetLabel;
  final VoidCallback onTerminalFocus;

  /// The same pane's live terminal owner, used only for guarded focus return.
  final FocusNode? terminalFocus;
  final bool active;
  final bool available;
  final ValueChanged<String>? onAskAi;
  final VoidCallback? onOpenAi;
  @override
  State<ComposerPane> createState() => _ComposerPaneState();
}

class _ComposerPaneState extends State<ComposerPane>
    with WidgetsBindingObserver {
  FocusNode get _focus => session.editorFocus;
  final _paneFocus = FocusNode(
    debugLabel: 'Composer pane controls',
    canRequestFocus: false,
  );
  int _focusRevision = 0;
  FocusScopeNode? _pendingTerminalReturnScope;
  ComposerOwnership? _lastOwnership;
  bool _lastEnabled = false;
  ComposerPaneSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_focusChanged);
    session.controller.addListener(_changed);
    session.addListener(_changed);
    // Defer notification until after the first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) session.setVisible(widget.available && widget.active);
    });
  }

  @override
  void didUpdateWidget(ComposerPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ownershipChanged =
        oldWidget.active != widget.active ||
        oldWidget.available != widget.available;
    if (ownershipChanged) {
      ++_focusRevision;
      _pendingTerminalReturnScope = null;
    }
    final visible = widget.available && widget.active;
    if (ownershipChanged || visible != session._visible) {
      if (!visible) {
        // Revoke while layout applies the new owner, before old Run callbacks
        // can submit. Only the listener notification waits for layout to end.
        session.setVisible(false, deferNotification: true);
      } else {
        // A read-only layer can open and close before this widget observes an
        // inactive prop. Reconcile that revoke using the latest layout owner.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) session.setVisible(widget.available && widget.active);
        });
      }
    }
  }

  void _focusChanged() {
    ++_focusRevision;
    final owner = FocusManager.instance.primaryFocus;
    if (owner != _focus && owner != _pendingTerminalReturnScope) {
      _pendingTerminalReturnScope = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ++_focusRevision;
    _pendingTerminalReturnScope = null;
  }

  bool get _canTransferFocus {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return mounted &&
        widget.active &&
        widget.available &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        ModalRoute.of(context)?.isCurrent != false;
  }

  void _transferFocus({
    required bool toTerminal,
    required bool Function() stillCurrent,
  }) {
    if (!_canTransferFocus ||
        !(widget.terminalFocus?.hasFocus == true ||
            !toTerminal &&
                _pendingTerminalReturnScope != null &&
                FocusManager.instance.primaryFocus ==
                    _pendingTerminalReturnScope ||
            toTerminal && _paneFocus.hasFocus)) {
      return;
    }
    final revision = _focusRevision;
    final owner = FocusManager.instance.primaryFocus;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canTransferFocus ||
          revision != _focusRevision ||
          FocusManager.instance.primaryFocus != owner ||
          !stillCurrent()) {
        return;
      }
      if (toTerminal) {
        if (widget.terminalFocus?.canRequestFocus != false) {
          // A fast command may finish before its accepted block is mounted
          // (for example while the user reads earlier output). Retain only
          // this editor's explicit hand-off, and only while its route scope
          // has no replacement input owner. Background output cannot create
          // this permission, and focus/lifecycle changes revoke it.
          if (widget.terminalFocus?.context == null) {
            _pendingTerminalReturnScope = _paneFocus.enclosingScope;
          }
          widget.onTerminalFocus();
        }
      } else if (_focus.canRequestFocus) {
        _pendingTerminalReturnScope = null;
        _focus.requestFocus();
      }
    });
  }

  void _changed() {
    if (!mounted) return;
    if (_lastEnabled && !session.enabled && widget.active) {
      _transferFocus(toTerminal: true, stillCurrent: () => !session.enabled);
    }
    _lastEnabled = session.enabled;
    final owner = session.controller.ownership;
    if (_lastOwnership != owner && session.enabled && widget.active) {
      if (owner == ComposerOwnership.running ||
          owner == ComposerOwnership.suspended) {
        _transferFocus(
          toTerminal: true,
          stillCurrent: () =>
              session.enabled && session.controller.ownership == owner,
        );
      } else if (owner == ComposerOwnership.ready &&
          (_lastOwnership == ComposerOwnership.running ||
              _lastOwnership == ComposerOwnership.suspended)) {
        _transferFocus(
          toTerminal: false,
          stillCurrent: () =>
              session.enabled &&
              session.controller.ownership == ComposerOwnership.ready,
        );
      }
    }
    _lastOwnership = owner;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final controller = session.controller;
    if (!session.enabled || !widget.available) {
      return const SizedBox.shrink();
    }
    return Focus(
      focusNode: _paneFocus,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: MediaQuery.sizeOf(context).height < 400 ? 4 : 8,
        ),
        child: TerminalComposerView(
          controller: controller,
          targetLabel: widget.targetLabel,
          focusNode: _focus,
          onNavigateBlocks: (delta) =>
              session.navigateBlocks?.call(delta) ?? false,
          chinese: zh,
          autofocus: widget.active,
          onAskAi: widget.onAskAi,
          onOpenAi: widget.onOpenAi,
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_focusChanged);
    session.controller.removeListener(_changed);
    session.removeListener(_changed);
    session.setVisible(false);
    _paneFocus.dispose();
    super.dispose();
  }
}
