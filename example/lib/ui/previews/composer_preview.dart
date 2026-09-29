import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../app_ui.dart';
import 'composer_preview_data.dart';

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

@Preview(name: 'Composer · History', group: 'Terminal', size: Size(820, 480))
Widget composerHistoryPreview() => const _ComposerPreview(
  brightness: Brightness.dark,
  scenario: ComposerPreviewScenario.history,
);

@Preview(
  name: 'Composer · Inline suggestion',
  group: 'Terminal',
  size: Size(820, 380),
)
Widget composerSuggestionPreview() => const _ComposerPreview(
  brightness: Brightness.light,
  scenario: ComposerPreviewScenario.suggestion,
);

class _ComposerPreview extends StatefulWidget {
  const _ComposerPreview({
    required this.brightness,
    this.scenario = ComposerPreviewScenario.completion,
  });
  final Brightness brightness;
  final ComposerPreviewScenario scenario;
  @override
  State<_ComposerPreview> createState() => _ComposerPreviewState();
}

class _ComposerPreviewState extends State<_ComposerPreview> {
  late final TerminalComposerController controller =
      createComposerPreviewController(widget.scenario);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (widget.scenario == ComposerPreviewScenario.history) {
        controller.openHistory();
      } else if (widget.scenario == ComposerPreviewScenario.completion) {
        controller.requestCompletions();
        await Future<void>.delayed(Duration.zero);
        if (mounted) controller.selectNext(1);
      }
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildIanvsTerminalTheme(widget.brightness),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: TerminalComposerView(
            controller: controller,
            autofocus: true,
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
