import 'package:ianvs_design/ianvs_design.dart';

/// Trail adapter for the shared, keyboard-accessible choice row.
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
  Widget build(BuildContext context) => IanvsChoiceTile<T>(
    key: tileKey,
    value: value,
    title: title,
    subtitle: subtitle,
  );
}
