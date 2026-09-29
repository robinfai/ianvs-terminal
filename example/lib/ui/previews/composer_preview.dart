import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../app_ui.dart';

@Preview(name: 'Composer · Dark', group: 'Terminal', size: Size(820, 380))
Widget composerDarkPreview() =>
    const _ComposerPreview(brightness: Brightness.dark);

@Preview(name: 'Composer · Light', group: 'Terminal', size: Size(820, 380))
Widget composerLightPreview() =>
    const _ComposerPreview(brightness: Brightness.light);

@Preview(
  name: 'Composer · Compact',
  group: 'Terminal',
  size: Size(360, 400),
  textScaleFactor: 2,
)
Widget composerCompactPreview() =>
    const _ComposerPreview(brightness: Brightness.dark);

class _ComposerPreview extends StatefulWidget {
  const _ComposerPreview({required this.brightness});
  final Brightness brightness;
  @override
  State<_ComposerPreview> createState() => _ComposerPreviewState();
}

class _ComposerPreviewState extends State<_ComposerPreview> {
  late final controller =
      TerminalComposerController(
        targetId: 'preview',
        text: 'git checkout composer',
        provider: (q, _) async => CompletionBatch(q, const []),
      )..updateShell(
        contextKey: 'preview',
        cwd: '~/code/ianvs-terminal',
        ownership: ComposerOwnership.draft,
      );
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildIanvsTerminalTheme(widget.brightness),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: TerminalComposerView(
            controller: controller,
            targetLabel: 'Local · zsh',
            onUseTerminal: () {},
          ),
        ),
      ),
    ),
  );
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
