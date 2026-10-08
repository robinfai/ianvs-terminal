import 'package:flutter/material.dart';

import '../../../ui/app_ui.dart';

/// A persistent explanation above retained, read-only terminal output.
class MobileDisconnectedSessionNotice extends StatelessWidget {
  const MobileDisconnectedSessionNotice({
    super.key,
    required this.sessionId,
    required this.reconnected,
    this.compact = false,
    this.exitCode,
    this.onReconnect,
  });

  final String sessionId;
  final bool reconnected;
  final bool compact;
  final int? exitCode;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.appTheme;
    final detail = reconnected
        ? context.l10n.mobileSessionReconnectedDetail
        : context.l10n.mobileSessionDisconnectedDetail;
    final action = onReconnect == null
        ? null
        : FilledButton.tonalIcon(
            key: Key('mobile-disconnected-reconnect-$sessionId'),
            onPressed: onReconnect,
            icon: Icon(
              reconnected ? Icons.arrow_forward_rounded : Icons.refresh_rounded,
            ),
            label: Text(
              reconnected
                  ? context.l10n.mobileSessionOpenCurrent
                  : context.l10n.mobileSessionReconnect,
            ),
          );
    if (compact) {
      return Material(
        color: tokens.panel,
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.sm),
          child: Row(
            children: [
              Icon(Icons.link_off_rounded, color: tokens.textSubtle),
              SizedBox(width: tokens.spacing.sm),
              Expanded(
                child: Tooltip(
                  message: detail,
                  child: Semantics(
                    liveRegion: true,
                    label: detail,
                    child: Text(
                      context.l10n.mobileSessionDisconnectedTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ),
              ),
              if (action != null) ...[
                SizedBox(width: tokens.spacing.sm),
                Flexible(child: action),
              ],
            ],
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        color: tokens.panel,
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.link_off_rounded, color: tokens.textSubtle),
                  SizedBox(width: tokens.spacing.sm),
                  Expanded(
                    child: Text(
                      context.l10n.mobileSessionDisconnectedTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (exitCode != null)
                    Text(
                      context.l10n.mobileSessionExitCode(exitCode!),
                      style: theme.textTheme.labelMedium,
                    ),
                ],
              ),
              SizedBox(height: tokens.spacing.sm),
              Text(detail, style: theme.textTheme.bodySmall),
              if (action != null) ...[
                SizedBox(height: tokens.spacing.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: action,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
