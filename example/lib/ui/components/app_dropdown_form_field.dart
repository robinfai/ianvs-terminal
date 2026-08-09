import 'package:flutter/material.dart';

/// A themed form dropdown that shares text metrics with single-line inputs.
///
/// Material's [DropdownButtonFormField] defaults to `titleMedium`, while
/// [TextField] defaults to `bodyLarge`. Using the same text style prevents
/// adjacent controls from drifting to different heights at larger text scales.
class AppDropdownFormField<T> extends StatelessWidget {
  const AppDropdownFormField({
    super.key,
    required this.items,
    required this.onChanged,
    this.initialValue,
    this.decoration = const InputDecoration(),
    this.isExpanded = false,
    this.iconSize = 24,
    this.itemHeight,
    this.menuMaxHeight,
    this.borderRadius,
  });

  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final T? initialValue;
  final InputDecoration decoration;
  final bool isExpanded;
  final double iconSize;
  final double? itemHeight;
  final double? menuMaxHeight;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: initialValue,
      items: items,
      onChanged: onChanged,
      decoration: decoration,
      isExpanded: isExpanded,
      style: Theme.of(context).textTheme.bodyLarge,
      iconSize: iconSize,
      itemHeight: itemHeight,
      menuMaxHeight: menuMaxHeight,
      borderRadius: borderRadius,
    );
  }
}
