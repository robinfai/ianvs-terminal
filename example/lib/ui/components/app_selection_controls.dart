import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../foundation/app_theme_tokens.dart';

/// Cupertino switch geometry with the same Ianvs tint and keyboard focus.
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged,
    this.label, this.focusNode});
  final bool value;
  final ValueChanged<bool>? onChanged;
  /// Omit only when a surrounding MergeSemantics row supplies visible text.
  final String? label;
  final FocusNode? focusNode;
  @override
  Widget build(BuildContext context) => Semantics(label: label,
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: context.usesTouchControlDensity ? 48 : 32),
      child: CupertinoSwitch(
        value: value,
        onChanged: onChanged,
        focusNode: focusNode,
        activeTrackColor: context.appTheme.accent,
        inactiveTrackColor: context.appTheme.border,
        focusColor: context.appTheme.focus,
        trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.focused) ? context.appTheme.focus :
          MediaQuery.highContrastOf(context) ? context.appTheme.textPrimary : null),
        trackOutlineWidth: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.focused) || MediaQuery.highContrastOf(context) ? 2 : 0),
      ),
    ),
  );
}

/// Material segmented selection retains arrow-key navigation and semantics.
/// A neutral track and selected surface follow Cupertino's visual hierarchy.
class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({super.key, required this.segments,
    required this.value, required this.onChanged});
  final List<ButtonSegment<T>> segments;
  final T value;
  final ValueChanged<T>? onChanged;
  @override
  Widget build(BuildContext context) {
    final tokens = context.appTheme;
    return SegmentedButton<T>(
      segments: segments,
      selected: {value},
      onSelectionChanged: onChanged == null ? null : (values) => onChanged!(values.single),
      showSelectedIcon: false,
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(0, context.usesTouchControlDensity ? 48 : 32)),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? tokens.panelElevated : tokens.chrome),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled) ? tokens.textSubtle : tokens.textPrimary),
        side: WidgetStateProperty.resolveWith((states) => BorderSide(
          color: states.contains(WidgetState.focused) ? tokens.focus : tokens.border,
          width: states.contains(WidgetState.focused) ? 2 : 1)),
        textStyle: WidgetStateProperty.resolveWith((states) =>
          Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400)),
        animationDuration: Duration.zero,
      ),
    );
  }
}
