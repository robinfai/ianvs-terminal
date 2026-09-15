import 'package:ianvs_design/ianvs_design.dart';

/// Trail's configuration label width; reflow and semantics are shared by Ianvs.
class AppConfigurationField extends StatelessWidget {
  const AppConfigurationField({
    super.key,
    required this.label,
    required this.child,
    this.helper,
    this.showLabel = true,
    this.labelWidth = 120,
    this.breakpoint = 520,
  });

  final String label;
  final Widget child;
  final String? helper;
  final bool showLabel;
  final double labelWidth;
  final double breakpoint;

  @override
  Widget build(BuildContext context) => !showLabel
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            child,
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
      : IanvsFieldRow(
          label: label,
          helper: helper,
          labelWidth: labelWidth,
          breakpoint: breakpoint,
          child: child,
        );
}
