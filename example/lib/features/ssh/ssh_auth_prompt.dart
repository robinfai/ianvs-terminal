import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/app_ui.dart';
import '../terminal/terminal.dart' as terminal;

typedef SshAuthenticationResponder =
    FutureOr<bool> Function({
      required terminal.TerminalSessionSshAuthPromptEvent event,
      required List<String> responses,
      required bool cancel,
    });

/// Serializes keyboard-interactive rounds so a server can issue a password,
/// OTP, approval, or any later challenge without overlapping modal dialogs.
final class SshAuthenticationPromptPresenter {
  Future<void> _tail = Future<void>.value();
  final Set<String> _cancelledSessionIds = <String>{};
  final Map<String, int> _pendingBySessionId = <String, int>{};
  ({String sessionId, ValueNotifier<bool> cancellation})? _active;

  void cancelSession(String sessionId) {
    if (!_pendingBySessionId.containsKey(sessionId)) {
      return;
    }
    _cancelledSessionIds.add(sessionId);
    final active = _active;
    if (active?.sessionId == sessionId) {
      active!.cancellation.value = true;
    }
  }

  Future<void> enqueue(
    BuildContext context,
    terminal.TerminalSessionSshAuthPromptEvent event,
    SshAuthenticationResponder responder,
  ) {
    _pendingBySessionId.update(
      event.sessionId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    // Keep later server rounds usable even if a previous dialog was disposed
    // or its responder failed while the session was closing.
    return _tail = _tail
        .catchError((_) {})
        .then((_) async {
          if (!context.mounted ||
              !event.isValid ||
              _cancelledSessionIds.contains(event.sessionId)) {
            return;
          }
          final cancellation = ValueNotifier<bool>(false);
          _active = (sessionId: event.sessionId, cancellation: cancellation);
          final responses = await showDialog<List<String>>(
            context: context,
            barrierDismissible: false,
            builder: (_) => SshAuthenticationPromptDialog(
              event: event,
              cancellation: cancellation,
            ),
          );
          if (_active?.cancellation == cancellation) {
            _active = null;
          }
          cancellation.dispose();
          if (_cancelledSessionIds.contains(event.sessionId)) {
            return;
          }
          final accepted = await responder(
            event: event,
            responses: responses ?? const <String>[],
            cancel: responses == null,
          );
          if (!accepted && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'The SSH authentication challenge is no longer active.',
                ),
              ),
            );
          }
        })
        .catchError((_) {})
        .whenComplete(() {
          final remaining = (_pendingBySessionId[event.sessionId] ?? 1) - 1;
          if (remaining <= 0) {
            _pendingBySessionId.remove(event.sessionId);
            _cancelledSessionIds.remove(event.sessionId);
          } else {
            _pendingBySessionId[event.sessionId] = remaining;
          }
        });
  }
}

class SshAuthenticationPromptDialog extends StatefulWidget {
  const SshAuthenticationPromptDialog({
    super.key,
    required this.event,
    this.cancellation,
  });

  final terminal.TerminalSessionSshAuthPromptEvent event;
  final ValueNotifier<bool>? cancellation;

  @override
  State<SshAuthenticationPromptDialog> createState() =>
      _SshAuthenticationPromptDialogState();
}

class _SshAuthenticationPromptDialogState
    extends State<SshAuthenticationPromptDialog> {
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.event.prompts.length,
      (_) => TextEditingController(),
    );
    widget.cancellation?.addListener(_handleCancellation);
    if (widget.cancellation?.value == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _dismissIfMounted());
    }
  }

  @override
  void dispose() {
    widget.cancellation?.removeListener(_handleCancellation);
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final palette = context.appTheme;
    final challengeName = event.name.trim().isEmpty
        ? 'SSH authentication'
        : event.name.trim();
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final horizontalInset = viewportWidth < 600 ? 16.0 : 40.0;
    final contentWidth = (viewportWidth - horizontalInset * 2 - 48).clamp(
      0.0,
      420.0,
    );
    return AlertDialog(
      key: const Key('ssh-auth-prompt-dialog'),
      scrollable: true,
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: 24,
      ),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: palette.accent),
          SizedBox(width: palette.spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(challengeName),
                SizedBox(height: palette.spacing.xs),
                Text(
                  '${event.user}@${event.host}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.textSubtle,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        key: const Key('ssh-auth-dialog-content'),
        width: contentWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (event.instructions.isNotEmpty) ...[
                Text(event.instructions),
                SizedBox(height: palette.spacing.lg),
              ],
              for (var index = 0; index < event.prompts.length; index++) ...[
                AppFieldRow(
                  label: event.prompts[index].prompt.trim().isEmpty
                      ? 'Response ${index + 1}'
                      : event.prompts[index].prompt.trim(),
                  hint: event.prompts[index].echo
                      ? null
                      : 'Your response is hidden.',
                  control: Semantics(
                    label: event.prompts[index].prompt.trim().isEmpty
                        ? 'Response ${index + 1}'
                        : event.prompts[index].prompt.trim(),
                    textField: true,
                    obscured: !event.prompts[index].echo,
                    child: TextField(
                      key: Key('ssh-auth-response-$index'),
                      controller: _controllers[index],
                      autofocus: index == 0,
                      obscureText: !event.prompts[index].echo,
                      enableSuggestions: event.prompts[index].echo,
                      autocorrect: false,
                      textInputAction: index + 1 == event.prompts.length
                          ? TextInputAction.done
                          : TextInputAction.next,
                      decoration: const InputDecoration(),
                      onSubmitted: index + 1 == event.prompts.length
                          ? (_) => _submit()
                          : null,
                    ),
                  ),
                ),
                if (index + 1 < event.prompts.length)
                  SizedBox(height: palette.spacing.lg),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('ssh-auth-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('ssh-auth-submit'),
          onPressed: _submit,
          child: const Text('Continue'),
        ),
      ],
    );
  }

  void _submit() {
    Navigator.of(context).pop(
      _controllers.map((controller) => controller.text).toList(growable: false),
    );
  }

  void _handleCancellation() {
    if (widget.cancellation?.value == true) {
      _dismissIfMounted();
    }
  }

  void _dismissIfMounted() {
    if (mounted) {
      unawaited(Navigator.of(context).maybePop());
    }
  }
}
