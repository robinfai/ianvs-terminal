import 'package:ianvs_design/ianvs_design.dart';
import 'app_grouped_section.dart';
import 'app_text_form_field.dart';

/// Trail's configuration label width; reflow and semantics are shared by Ianvs.
class AppConfigurationField extends StatelessWidget {
  const AppConfigurationField({
    super.key,
    required this.label,
    required this.child,
    this.helper,
    this.stackedOnPhone = false,
    this.subtleLabel = false,
    this.showLabel = true,
    this.labelWidth = 110,
    this.breakpoint = 520,
  });

  final String label;
  final Widget child;
  final String? helper;
  final bool stackedOnPhone;
  final bool subtleLabel;
  final bool showLabel;
  final double labelWidth;
  final double breakpoint;

  Widget get _labeledChild =>
      child is TextField || child is TextFormField || child is AppTextFormField
      ? Semantics(
          container: true,
          explicitChildNodes: true,
          label: label,
          child: child,
        )
      : child;

  @override
  Widget build(BuildContext context) {
    if (showLabel && AppGroupedFormScope.of(context)) {
      final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w400,
      );
      return LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              stackedOnPhone ||
              constraints.maxWidth < 320 ||
              label.length > 12 ||
              RegExp(r'[\u4e00-\u9fff]').allMatches(label).length > 5;
          return Container(
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: .45),
                  width: .5,
                ),
              ),
            ),
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (stacked) ...[
                  Text(label, style: style),
                  _labeledChild,
                ] else
                  Row(
                    children: [
                      SizedBox(width: 92, child: Text(label, style: style)),
                      const SizedBox(width: 8),
                      Expanded(child: _labeledChild),
                    ],
                  ),
                if (helper != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: helper!.length > 90
                        ? ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: const EdgeInsets.only(bottom: 8),
                            title: Text(
                              Localizations.localeOf(context).languageCode ==
                                      'zh'
                                  ? '了解此设置'
                                  : 'About this setting',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            children: [
                              Text(
                                helper!,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          )
                        : Text(
                            helper!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 13,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                  ),
              ],
            ),
          );
        },
      );
    }
    return !showLabel
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _labeledChild,
              if (helper != null) ...[
                const SizedBox(height: 6),
                Text(
                  helper!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          )
        : DefaultTextStyle.merge(
            style: subtleLabel
                ? TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  )
                : const TextStyle(),
            child: IanvsFieldRow(
              label: label,
              helper: helper,
              labelWidth: labelWidth,
              breakpoint: breakpoint,
              child: DefaultTextStyle(
                style: DefaultTextStyle.of(context).style,
                child: _labeledChild,
              ),
            ),
          );
  }
}

/// Scoped styling for connection and synchronization forms; validation and
/// focus/error outlines continue to use the inherited component contract.
ThemeData appConfigurationFormTheme(BuildContext context) {
  final theme = Theme.of(context);
  final mobile =
      theme.platform == TargetPlatform.iOS ||
      theme.platform == TargetPlatform.android;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(mobile ? 8 : 6),
    borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
  );
  return theme.copyWith(
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerLow,
      border: border,
      enabledBorder: border,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: mobile ? 12 : 6,
      ),
      helperStyle: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
