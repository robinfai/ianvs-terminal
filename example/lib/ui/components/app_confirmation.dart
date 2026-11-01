import 'package:flutter/material.dart';
import '../foundation/app_motion.dart';
import 'app_action_button.dart';

/// Explicit cancel remains the default for destructive actions. DialogRoute
/// owns focus trapping/restoration and Back/Escape cancellation.
Future<bool> showAppConfirmation(BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = false,
}) async => await showDialog<bool>(
  context: context,
  animationStyle: appDialogAnimation(context),
  builder: (context) => AlertDialog(
    title: Text(title),
    content: Text(message),
    scrollable: true,
    actionsOverflowDirection: VerticalDirection.down,
    actions: [
      AppActionButton(label: cancelLabel, tone: AppActionTone.secondary,
        autofocus: destructive, onPressed: () => Navigator.of(context).pop(false)),
      AppActionButton(label: confirmLabel,
        tone: destructive ? AppActionTone.danger : AppActionTone.primary,
        autofocus: !destructive, onPressed: () => Navigator.of(context).pop(true)),
    ],
  ),
) ?? false;
