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
            targetLabel: 'Local Shell',
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

@Preview(
  name: 'Composer redesign · Reference light',
  group: 'Composer redesign',
  size: Size(856, 460),
)
Widget composerRedesignLightPreview() => const _ComposerRedesignPreview(
  scenario: ComposerRedesignScenario.completion,
);

@Preview(
  name: 'Composer redesign · Reference dark',
  group: 'Composer redesign',
  size: Size(856, 460),
)
Widget composerRedesignDarkPreview() => const _ComposerRedesignPreview(
  brightness: Brightness.dark,
  scenario: ComposerRedesignScenario.completion,
);

@Preview(
  name: 'Composer redesign · 360 px / 2×',
  group: 'Composer redesign',
  size: Size(360, 740),
)
Widget composerRedesignLargeTextPreview() => const _ComposerRedesignPreview(
  brightness: Brightness.dark,
  textScale: 2,
  scenario: ComposerRedesignScenario.unknown,
);

@Preview(
  name: 'Composer redesign · 320 px',
  group: 'Composer redesign',
  size: Size(320, 640),
)
Widget composerRedesignNarrowPreview() =>
    const _ComposerRedesignPreview(scenario: ComposerRedesignScenario.longPath);

@Preview(
  name: 'Composer redesign · Short window',
  group: 'Composer redesign',
  size: Size(640, 300),
)
Widget composerRedesignShortPreview() => const _ComposerRedesignPreview(
  brightness: Brightness.dark,
  scenario: ComposerRedesignScenario.longHistory,
);

@Preview(
  name: 'Composer redesign · High contrast',
  group: 'Composer redesign',
  size: Size(856, 460),
)
Widget composerRedesignContrastPreview() => const _ComposerRedesignPreview(
  highContrast: true,
  scenario: ComposerRedesignScenario.completion,
);

@Preview(
  name: 'Composer redesign · Long alias',
  group: 'Composer redesign',
  size: Size(856, 460),
)
Widget composerRedesignAliasPreview() => const _ComposerRedesignPreview(
  scenario: ComposerRedesignScenario.longAlias,
);

@Preview(
  name: 'Composer redesign · Draft',
  group: 'Composer ownership',
  size: Size(856, 460),
)
Widget composerRedesignDraftPreview() =>
    const _ComposerRedesignPreview(scenario: ComposerRedesignScenario.draft);

@Preview(
  name: 'Composer redesign · Sending',
  group: 'Composer ownership',
  size: Size(856, 460),
)
Widget composerRedesignSendingPreview() => const _ComposerRedesignPreview(
  scenario: ComposerRedesignScenario.submitting,
);

@Preview(
  name: 'Composer redesign · Running',
  group: 'Composer ownership',
  size: Size(856, 460),
)
Widget composerRedesignRunningPreview() =>
    const _ComposerRedesignPreview(scenario: ComposerRedesignScenario.running);

@Preview(
  name: 'Composer redesign · Terminal input',
  group: 'Composer ownership',
  size: Size(856, 460),
)
Widget composerRedesignSuspendedPreview() => const _ComposerRedesignPreview(
  scenario: ComposerRedesignScenario.suspended,
);

@Preview(
  name: 'Composer redesign · Unknown + loading',
  group: 'Composer ownership',
  size: Size(856, 460),
)
Widget composerRedesignUnknownPreview() => const _ComposerRedesignPreview(
  scenario: ComposerRedesignScenario.unknownLoading,
);

@Preview(
  name: 'Composer redesign · Rejected',
  group: 'Composer ownership',
  size: Size(856, 460),
)
Widget composerRedesignRejectedPreview() =>
    const _ComposerRedesignPreview(scenario: ComposerRedesignScenario.rejected);

@Preview(
  name: 'Composer redesign · No history yet',
  group: 'Composer empty states',
  size: Size(856, 460),
)
Widget composerRedesignEmptyHistoryPreview() => const _ComposerRedesignPreview(
  scenario: ComposerRedesignScenario.emptyHistory,
);

@Preview(
  name: 'Composer redesign · No matching history',
  group: 'Composer empty states',
  size: Size(856, 460),
)
Widget composerRedesignNoHistoryMatchPreview() =>
    const _ComposerRedesignPreview(
      scenario: ComposerRedesignScenario.historyNoMatch,
    );

class _ComposerRedesignPreview extends StatefulWidget {
  const _ComposerRedesignPreview({
    required this.scenario,
    this.brightness = Brightness.light,
    this.textScale = 1,
    this.highContrast = false,
  });

  final ComposerRedesignScenario scenario;
  final Brightness brightness;
  final double textScale;
  final bool highContrast;

  @override
  State<_ComposerRedesignPreview> createState() =>
      _ComposerRedesignPreviewState();
}

class _ComposerRedesignPreviewState extends State<_ComposerRedesignPreview> {
  late final fixture = ComposerRedesignFixture(widget.scenario);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      fixture.activate();
      await Future<void>.delayed(Duration.zero);
      if (mounted) fixture.revealSelection();
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildIanvsTerminalTheme(
      widget.brightness,
      platform: TargetPlatform.macOS,
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(widget.textScale),
        highContrast: widget.highContrast,
      ),
      child: child!,
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: TerminalComposerView(
            controller: fixture.controller,
            autofocus: true,
            targetLabel: fixture.targetLabel,
            chinese: true,
            onUseTerminal: () {},
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    fixture.dispose();
    super.dispose();
  }
}
