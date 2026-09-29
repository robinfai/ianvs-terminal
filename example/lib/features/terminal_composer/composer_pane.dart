import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

/// App lifecycle and runtime assembly. Drafts remain in memory per session.
final class ComposerPaneSession {
  ComposerPaneSession({required this.sessionId, required this.runtime}) {
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
        if (!controller.localSuggestions || lease == null) return staticBatch;
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
  }

  final String sessionId;
  final TerminalRuntimeController runtime;
  late final TerminalComposerController controller;
  bool enabled = false;
  Timer? _pollTimer;
  bool _disposed = false;

  void setVisible(bool visible) {
    if (_disposed) return;
    _pollTimer?.cancel();
    controller.setActive(visible && enabled);
    if (visible && enabled) {
      _poll();
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 150),
        (_) => _poll(),
      );
    }
  }

  void _poll() {
    if (_disposed) return;
    final json = runtime.composerRequest(sessionId, 'composer.state', const {});
    final state = json?['state'];
    final ownership = switch (state) {
      'ready' => ComposerOwnership.ready,
      'running' => ComposerOwnership.running,
      'suspended' => ComposerOwnership.suspended,
      _ => ComposerOwnership.draft,
    };
    controller.updateShell(
      contextKey: '${json?['lease'] ?? state ?? 'unavailable'}',
      cwd: json?['cwd'] as String? ?? '',
      lease: json?['lease'] as String?,
      dialect: json?['dialect'] as String? ?? 'generic',
      ownership: ownership,
    );
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
    final deadline = DateTime.now().add(const Duration(seconds: 2));
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

  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    controller.dispose();
  }
}

class ComposerPane extends StatefulWidget {
  const ComposerPane({
    required this.session,
    required this.targetLabel,
    required this.onTerminalFocus,
    required this.active,
    required this.available,
    super.key,
  });
  final ComposerPaneSession session;
  final String targetLabel;
  final VoidCallback onTerminalFocus;
  final bool active;
  final bool available;
  @override
  State<ComposerPane> createState() => _ComposerPaneState();
}

class _ComposerPaneState extends State<ComposerPane> {
  final _focus = FocusNode(debugLabel: 'Pane composer');
  ComposerOwnership? _lastOwnership;
  ComposerPaneSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    session.controller.addListener(_changed);
    // Defer notification until after the first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) session.setVisible(widget.available && widget.active);
    });
  }

  @override
  void didUpdateWidget(ComposerPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.available != widget.available) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) session.setVisible(widget.available && widget.active);
      });
    }
  }

  void _changed() {
    if (!mounted) return;
    final owner = session.controller.ownership;
    if (_lastOwnership != owner && session.enabled && widget.active) {
      if (owner == ComposerOwnership.running ||
          owner == ComposerOwnership.suspended) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onTerminalFocus();
        });
      } else if (owner == ComposerOwnership.ready &&
          (_lastOwnership == ComposerOwnership.running ||
              _lastOwnership == ComposerOwnership.suspended)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focus.requestFocus();
        });
      }
    }
    _lastOwnership = owner;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final controller = session.controller;
    final running =
        controller.ownership == ComposerOwnership.running ||
        controller.ownership == ComposerOwnership.suspended;
    if (!session.enabled || !widget.available || running) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: Key('composer-toggle-${session.sessionId}'),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: !widget.available
              ? null
              : () {
                  session.enabled = !session.enabled;
                  session.setVisible(widget.active);
                  setState(() {});
                  if (session.enabled) _focus.requestFocus();
                },
          icon: const Icon(Icons.edit_note_rounded, size: 16),
          label: Text(
            running
                ? (zh ? '运行中 · 传统输入' : 'Running · terminal input')
                : (zh ? 'Composer · 命令编辑器' : 'Composer · command editor'),
            style: const TextStyle(fontSize: 11),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: TerminalComposerView(
        controller: controller,
        targetLabel: widget.targetLabel,
        focusNode: _focus,
        chinese: zh,
        autofocus: widget.active,
        onUseTerminal: () {
          session.enabled = false;
          session.setVisible(false);
          setState(() {});
          widget.onTerminalFocus();
        },
      ),
    );
  }

  @override
  void dispose() {
    session.controller.removeListener(_changed);
    session.setVisible(false);
    _focus.dispose();
    super.dispose();
  }
}
