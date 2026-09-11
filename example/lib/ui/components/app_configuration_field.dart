import 'package:ianvs_design/ianvs_design.dart';

/// Trail's configuration label width; reflow and semantics are shared by Ianvs.
class AppConfigurationField extends StatelessWidget {
  const AppConfigurationField({
    super.key,
    required this.label,
    required this.child,
    this.helper,
    this.labelWidth = 120,
    this.breakpoint = 520,
  });

  final String label;
  final Widget child;
  final String? helper;
  final double labelWidth;
  final double breakpoint;

  @override
  Widget build(BuildContext context) => IanvsFieldRow(
    label: label,
    helper: helper,
    labelWidth: labelWidth,
    breakpoint: breakpoint,
    child: child,
  );
}
