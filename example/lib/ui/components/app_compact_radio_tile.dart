import 'package:ianvs_design/ianvs_design.dart';

/// Trail adapter for the shared, keyboard-accessible choice row.
class AppCompactRadioTile<T> extends StatelessWidget {
  const AppCompactRadioTile({
    super.key,
    required this.value,
    required this.title,
    this.subtitle,
    this.tileKey,
    this.grouped = false,
  });

  final T value;
  final Widget title;
  final Widget? subtitle;
  final Key? tileKey;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final tile = IanvsChoiceTile<T>(
      key: tileKey,
      value: value,
      title: title,
      subtitle: subtitle,
    );
    if (!grouped) return tile;

    // The enclosing panel owns the corners; adjacent row states meet their
    // separators without rounded gaps. Keep the shared radio's keyboard logic.
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        extensions: [
          ...theme.extensions.values.where((value) => value is! IanvsTokens),
          context.ianvs.copyWith(controlRadius: 0),
        ],
      ),
      child: tile,
    );
  }
}
