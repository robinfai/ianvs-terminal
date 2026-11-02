import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Semantic Apple grouped surfaces. Keep platform color values out of pages.
extension AppGroupedSurfaces on BuildContext {
  Color get groupedPendingColor =>
      CupertinoDynamicColor.resolve(CupertinoColors.systemOrange, this);
  bool get usesAppleGroups => Theme.of(this).platform == TargetPlatform.iOS;
  Color get groupedBackground => usesAppleGroups
      ? (Theme.of(this).brightness == Brightness.dark
            ? CupertinoColors.systemGroupedBackground.darkColor
            : CupertinoColors.systemGroupedBackground.color)
      : Theme.of(this).colorScheme.surface;
  Color get groupedSurface => usesAppleGroups
      ? (Theme.of(this).brightness == Brightness.dark
            ? CupertinoColors.secondarySystemGroupedBackground.darkColor
            : CupertinoColors.secondarySystemGroupedBackground.color)
      : Theme.of(this).colorScheme.surfaceContainerLowest;
}

class AppGroupedSection extends StatelessWidget {
  const AppGroupedSection({
    super.key,
    required this.children,
    this.title,
    this.padding = EdgeInsets.zero,
    this.separated = false,
    this.flat = false,
  });
  final List<Widget> children;
  final String? title;
  final EdgeInsetsGeometry padding;
  final bool separated;

  /// Form/list rows sit directly on the page instead of inside a card.
  final bool flat;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (title != null)
        Padding(
          padding: EdgeInsets.fromLTRB(flat ? 0 : 8, 0, flat ? 0 : 8, 16),
          child: Text(
            title!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      Material(
        color: flat ? Colors.transparent : context.groupedSurface,
        borderRadius: flat
            ? BorderRadius.zero
            : BorderRadius.circular(context.usesAppleGroups ? 16 : 10),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: flat ? const EdgeInsets.symmetric(vertical: 8) : padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (separated && i > 0)
                  Divider(height: 1, indent: flat ? 0 : 16),
                children[i],
              ],
            ],
          ),
        ),
      ),
    ],
  );
}

class AppGroupedFormScope extends InheritedWidget {
  const AppGroupedFormScope({super.key, required super.child});
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppGroupedFormScope>() != null;
  @override
  bool updateShouldNotify(AppGroupedFormScope oldWidget) => false;
}

/// Desktop keeps aligned labels; iPhone gets a shared, editable grouped surface.
class AppFormGroup extends StatelessWidget {
  const AppFormGroup({super.key, required this.children, this.title});
  final List<Widget> children;
  final String? title;
  @override
  Widget build(BuildContext context) {
    if (!context.usesAppleGroups) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    final theme = Theme.of(context);
    return AppGroupedFormScope(
      child: Theme(
        data: theme.copyWith(
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: theme.colorScheme.primary),
            ),
          ),
        ),
        child: AppGroupedSection(
          flat: true,
          title: title,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          // Desktop callers supply inter-field gaps. In an Apple inset group,
          // the 48-point rows own vertical rhythm; retain wrapped content.
          children: [
            for (final child in children)
              if (child is! SizedBox || child.child != null) child,
          ],
        ),
      ),
    );
  }
}

/// Shared settings surface: inset rows on iPhone and bounded groups on Mac.
class AppSettingsSection extends StatelessWidget {
  const AppSettingsSection({super.key, this.title, required this.children});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (context.usesAppleGroups) {
      return AppFormGroup(title: title, children: children);
    }
    return AppGroupedSection(
      flat: true,
      title: title,
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }
}
