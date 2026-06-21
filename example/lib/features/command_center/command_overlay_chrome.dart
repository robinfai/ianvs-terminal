import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/app_ui.dart';

class CommandOverlayFrame extends StatelessWidget {
  const CommandOverlayFrame({
    required this.child,
    this.frameKey,
    this.maxWidth = 560,
    this.maxHeight = 420,
    super.key,
  });

  final Key? frameKey;
  final Widget child;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeTokens.of(context);
    final viewportSize = MediaQuery.sizeOf(context);
    final effectiveMaxWidth = math.min(
      maxWidth,
      math.max(0.0, viewportSize.width - 28),
    );
    final effectiveMaxHeight = math.min(
      maxHeight,
      math.max(0.0, viewportSize.height - 24),
    );
    return Material(
      key: frameKey,
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.overlay.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(palette.radius.xl),
          border: Border.all(color: palette.borderStrong),
          boxShadow: palette.elevation.dialog,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: effectiveMaxWidth,
            maxHeight: effectiveMaxHeight,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(palette.radius.xl),
            child: child,
          ),
        ),
      ),
    );
  }
}

InputDecoration commandOverlaySearchDecoration(
  BuildContext context, {
  required IconData icon,
  required String hintText,
}) {
  final palette = AppThemeTokens.of(context);
  return InputDecoration(
    prefixIcon: Icon(icon, size: 20, color: palette.textMuted),
    hintText: hintText,
    hintStyle: Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: palette.textSubtle),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    filled: true,
    fillColor: palette.chrome.withValues(alpha: 0.48),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(palette.radius.lg),
      borderSide: BorderSide(color: palette.borderStrong),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(palette.radius.lg),
      borderSide: BorderSide(color: palette.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(palette.radius.lg),
      borderSide: BorderSide(color: palette.accent, width: 1.4),
    ),
  );
}

Color commandOverlaySelectedColor(BuildContext context) {
  return AppThemeTokens.of(context).selected.withValues(alpha: 0.9);
}
