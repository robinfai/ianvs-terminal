import 'package:flutter/material.dart';

import 'local_terminal_shell_ui_wiring_exports.dart';

class LocalTerminalCompletionDiagnosticsPanel extends StatelessWidget {
  const LocalTerminalCompletionDiagnosticsPanel({
    required this.snapshot,
    this.maxItemsPerSection = 3,
    super.key,
  });

  final LocalTerminalShellUiWiringSnapshot snapshot;
  final int maxItemsPerSection;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
