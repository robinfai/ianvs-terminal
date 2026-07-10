import 'package:flutter/widgets.dart';

enum TerminalCursorExperimentMode { surface, overlay }

class TerminalCursorExperimentScope extends InheritedWidget {
  const TerminalCursorExperimentScope({
    super.key,
    required this.mode,
    required super.child,
  });

  final TerminalCursorExperimentMode mode;

  static TerminalCursorExperimentMode modeOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<TerminalCursorExperimentScope>()
            ?.mode ??
        TerminalCursorExperimentMode.overlay;
  }

  @override
  bool updateShouldNotify(TerminalCursorExperimentScope oldWidget) {
    return mode != oldWidget.mode;
  }
}
