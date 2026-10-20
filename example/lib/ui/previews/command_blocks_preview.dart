import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../app_ui.dart';

@Preview(
  name: 'Command blocks · Light',
  group: 'Terminal',
  size: Size(900, 800),
)
Widget commandBlocksLightPreview() => const CommandBlocksPreview();

@Preview(name: 'Command blocks · Dark', group: 'Terminal', size: Size(900, 800))
Widget commandBlocksDarkPreview() =>
    const CommandBlocksPreview(brightness: Brightness.dark);

@Preview(
  name: 'Command blocks · Large text',
  group: 'Terminal',
  size: Size(360, 800),
  textScaleFactor: 2,
)
Widget commandBlocksNarrowPreview() =>
    const CommandBlocksPreview(brightness: Brightness.dark);

@Preview(
  name: 'Command blocks · Phone',
  group: 'Terminal',
  size: Size(390, 844),
)
Widget commandBlocksPhonePreview() => CommandBlocksPreview(
  theme: buildIanvsTerminalTheme(
    Brightness.light,
    platform: TargetPlatform.iOS,
  ),
  longOutput: true,
);

@Preview(
  name: 'Command blocks · Phone dark',
  group: 'Terminal',
  size: Size(390, 844),
)
Widget commandBlocksPhoneDarkPreview() => CommandBlocksPreview(
  brightness: Brightness.dark,
  theme: buildIanvsTerminalTheme(Brightness.dark, platform: TargetPlatform.iOS),
  longOutput: true,
);

/// Production components with deterministic native-cell fixtures for review.
class CommandBlocksPreview extends StatefulWidget {
  const CommandBlocksPreview({
    super.key,
    this.brightness = Brightness.light,
    this.theme,
    this.textScale = 1,
    this.highContrast = false,
    this.running = false,
    this.longOutput = false,
  });
  final Brightness brightness;
  final ThemeData? theme;
  final double textScale;
  final bool highContrast;
  final bool running;
  final bool longOutput;
  @override
  State<CommandBlocksPreview> createState() => _CommandBlocksPreviewState();
}

class _CommandBlocksPreviewState extends State<CommandBlocksPreview> {
  late final CommandBlockController blocks;
  late final TerminalComposerController composer;
  final focus = FocusNode();
  @override
  void initState() {
    super.initState();
    final source = <Map<String, Object?>>[
      _block(
        '1',
        'git status --short',
        [
          ' M lib/features/terminal/command_blocks.dart',
          ' M test/terminal/command_blocks_test.dart',
        ],
        0,
        145,
      ),
      _block(
        '2',
        'flutter test',
        [
          '00:01 +4: command output retains ANSI styles',
          '00:02 +8: running terminal receives input',
          '00:02 +12: All tests passed!',
        ],
        0,
        2480,
      ),
      _block(
        '3',
        widget.running
            ? 'read "answer?Continue? "'
            : widget.longOutput
            ? 'seq 1 240'
            : 'npm run build',
        widget.running
            ? ['Continue? ']
            : widget.longOutput
            ? [for (var i = 1; i <= 240; i++) 'Output line $i']
            : [
                '> build',
                'src/app.ts:42:7 - error TS2322',
                "Type 'string' is not assignable to type 'number'.",
              ],
        widget.running
            ? null
            : widget.longOutput
            ? 0
            : 1,
        820,
      ),
    ];
    blocks = CommandBlockController(
      request: (request) {
        if (request['id'] == null) return {'blocks': source};
        final block = source.firstWhere((b) => b['id'] == request['id']);
        return {'block': block};
      },
    )..refresh();
    composer =
        TerminalComposerController(
          targetId: 'preview',
          provider: (query, _) async => CompletionBatch(query, const []),
          submit: (_) async => ComposerSubmissionOutcome.accepted,
        )..updateShell(
          contextKey: 'preview',
          cwd: '~/code/ianvs-terminal',
          dialect: 'zsh',
          lease: 'preview',
          ownership: widget.running
              ? ComposerOwnership.running
              : ComposerOwnership.ready,
        );
  }

  Map<String, Object?> _block(
    String id,
    String command,
    List<String> lines,
    int? exit,
    int duration,
  ) => {
    'id': id,
    'command': command,
    'cwd': '~/code/ianvs-terminal',
    'exitCode': exit,
    'running': exit == null,
    'columns': 80,
    'startedAt': 1000,
    'finishedAt': exit == null ? null : 1000 + duration,
    'cursorLine': lines.length - 1,
    'cursorColumn': lines.last.length,
    'totalLines': lines.length,
    'matchingLines': lines.length,
    'lines': [
      for (var i = 0; i < lines.length; i++)
        {'index': i, 'text': lines[i], 'wrapped': false},
    ],
  };
  @override
  void dispose() {
    blocks.dispose();
    composer.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme:
        widget.theme ??
        buildIanvsTerminalTheme(
          widget.brightness,
          highContrast: widget.highContrast,
        ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(widget.textScale),
        highContrast: widget.highContrast,
      ),
      child: child!,
    ),
    home: Scaffold(
      body: Column(
        children: [
          Expanded(
            child: TerminalCommandBlocksView(
              controller: blocks,
              chinese: true,
              font: const TerminalFontConfig(family: 'monospace'),
              onReinput: (text) {
                composer.editor.text = text;
                focus.requestFocus();
              },
              onReturnToInput: focus.requestFocus,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: TerminalComposerView(
              controller: composer,
              focusNode: focus,
              chinese: true,
              targetLabel: '本地',
              onUseTerminal: () {},
            ),
          ),
        ],
      ),
    ),
  );
}
