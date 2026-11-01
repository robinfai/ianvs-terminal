import 'package:flutter/material.dart';
import '../foundation/app_theme_tokens.dart';

/// Inline status with a readable label even when motion is reduced.
class AppStatus extends StatelessWidget {
  const AppStatus({
    super.key,
    required this.message,
    this.loading = false,
    this.error = false,
    this.action,
  });
  final String message;
  final bool loading;
  final bool error;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: error
            ? context.appTheme.dangerContainer
            : context.appTheme.chrome,
        borderRadius: BorderRadius.circular(context.appTheme.radius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (loading)
              SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: MediaQuery.disableAnimationsOf(context) ? .75 : null,
                ),
              )
            else
              Icon(
                error ? Icons.error_outline : Icons.check_circle_outline,
                color: error
                    ? context.appTheme.danger
                    : context.appTheme.success,
              ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
            ?action,
          ],
        ),
      ),
    ),
  );
}
