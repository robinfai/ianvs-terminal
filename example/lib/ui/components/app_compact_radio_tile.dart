import 'package:flutter/material.dart';

class AppCompactRadioTile<T> extends StatelessWidget {
  const AppCompactRadioTile({
    super.key,
    required this.value,
    required this.title,
    this.subtitle,
    this.tileKey,
  });

  final T value;
  final Widget title;
  final Widget? subtitle;
  final Key? tileKey;

  @override
  Widget build(BuildContext context) {
    final usesTouchDensity =
        Theme.of(context).materialTapTargetSize == MaterialTapTargetSize.padded;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: usesTouchDensity ? 48 : 0),
      child: RadioListTile<T>(
        key: tileKey ?? key,
        value: value,
        dense: !usesTouchDensity,
        visualDensity: usesTouchDensity
            ? VisualDensity.standard
            : VisualDensity.compact,
        contentPadding: EdgeInsets.zero,
        title: title,
        subtitle: subtitle,
      ),
    );
  }
}
