import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../../features/ai/ai_api_client.dart';
import '../../features/ai/ai_models.dart';
import '../../features/ai/ai_settings.dart';
import '../../features/ai/terminal_ai_controller.dart';
import '../../features/ai/terminal_ai_workspace.dart';
import '../app_ui.dart';

/// Each preview uses the real component. Press/hold and Tab exercise Material's
/// pressed/focus states; the state selector changes facts, not rendered colours.
enum MobilePrdPreviewComponent {
  block,
  contextChip,
  taskHeader,
  taskStatus,
  composerShell,
  proposalCard,
  reviewPage,
  readerHeader,
  emptyError,
}

enum MobilePrdPreviewState {
  defaultState,
  focused,
  selected,
  disabled,
  loading,
  error,
  unknown,
  targetChanged,
}

const _names = <MobilePrdPreviewComponent, String>{
  MobilePrdPreviewComponent.block: 'Block',
  MobilePrdPreviewComponent.contextChip: 'ContextChip',
  MobilePrdPreviewComponent.taskHeader: 'TaskHeader',
  MobilePrdPreviewComponent.taskStatus: 'TaskStatus',
  MobilePrdPreviewComponent.composerShell: 'ComposerShell',
  MobilePrdPreviewComponent.proposalCard: 'ProposalCard',
  MobilePrdPreviewComponent.reviewPage: 'ReviewPage',
  MobilePrdPreviewComponent.readerHeader: 'ReaderHeader',
  MobilePrdPreviewComponent.emptyError: 'Empty/Error',
};

class MobilePrdComponentPreview extends StatefulWidget {
  const MobilePrdComponentPreview({
    required this.component,
    this.dark = false,
    this.initialState = MobilePrdPreviewState.defaultState,
    super.key,
  });
  final MobilePrdPreviewComponent component;
  final bool dark;
  final MobilePrdPreviewState initialState;

  @override
  State<MobilePrdComponentPreview> createState() =>
      _MobilePrdComponentPreviewState();
}

class _MobilePrdComponentPreviewState extends State<MobilePrdComponentPreview> {
  late MobilePrdPreviewState state = widget.initialState;
  late bool dark = widget.dark;
  List<MobilePrdPreviewState> get states => switch (widget.component) {
    MobilePrdPreviewComponent.block => const [
      MobilePrdPreviewState.defaultState,
      MobilePrdPreviewState.selected,
      MobilePrdPreviewState.loading,
      MobilePrdPreviewState.error,
      MobilePrdPreviewState.unknown,
    ],
    MobilePrdPreviewComponent.contextChip => const [
      MobilePrdPreviewState.defaultState,
      MobilePrdPreviewState.disabled,
    ],
    MobilePrdPreviewComponent.composerShell => const [
      MobilePrdPreviewState.defaultState,
      MobilePrdPreviewState.focused,
      MobilePrdPreviewState.selected,
      MobilePrdPreviewState.disabled,
      MobilePrdPreviewState.loading,
      MobilePrdPreviewState.error,
      MobilePrdPreviewState.unknown,
    ],
    MobilePrdPreviewComponent.proposalCard ||
    MobilePrdPreviewComponent.reviewPage => const [
      MobilePrdPreviewState.defaultState,
      MobilePrdPreviewState.disabled,
      MobilePrdPreviewState.error,
      MobilePrdPreviewState.unknown,
      MobilePrdPreviewState.targetChanged,
    ],
    MobilePrdPreviewComponent.readerHeader => const [
      MobilePrdPreviewState.defaultState,
      MobilePrdPreviewState.loading,
      MobilePrdPreviewState.error,
    ],
    MobilePrdPreviewComponent.emptyError => const [
      MobilePrdPreviewState.defaultState,
      MobilePrdPreviewState.error,
      MobilePrdPreviewState.unknown,
    ],
    _ => const [
      MobilePrdPreviewState.defaultState,
      MobilePrdPreviewState.loading,
      MobilePrdPreviewState.error,
      MobilePrdPreviewState.unknown,
      MobilePrdPreviewState.targetChanged,
    ],
  };
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildIanvsTerminalTheme(
      dark ? Brightness.dark : Brightness.light,
      platform: TargetPlatform.iOS,
    ),
    home: Scaffold(
      appBar: AppBar(
        title: Text(_names[widget.component]!),
        actions: [
          IconButton(
            tooltip: 'Toggle theme',
            onPressed: () => setState(() => dark = !dark),
            icon: const Icon(Icons.brightness_6_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Expanded(child: Text('Hold for pressed · Tab for focus')),
                DropdownButton<MobilePrdPreviewState>(
                  key: const Key('mobile-prd-preview-state'),
                  value: state,
                  items: [
                    for (final value in states)
                      DropdownMenuItem(value: value, child: Text(value.name)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => state = value);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _Fixture(
              key: ValueKey((widget.component, state)),
              component: widget.component,
              state: state,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Fixture extends StatefulWidget {
  const _Fixture({required this.component, required this.state, super.key});
  final MobilePrdPreviewComponent component;
  final MobilePrdPreviewState state;
  @override
  State<_Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<_Fixture> {
  late final AiSettingsController settings;
  late final _Terminal terminal;
  late final _Api api;
  late final TerminalAiController task;
  late final CommandBlockController blocks;
  bool ready = false;
  bool readerOpened = false;

  static const source = AiBlockContext(
    id: 'prd-source',
    command: 'cat /srv/应用/config.yaml',
    output: 'Permission denied\nInspect file permissions before changing them.',
    cwd: '/srv/应用',
    exitCode: 1,
    sourceSessionId: 'preview',
    sourceContextId: 'root',
    sourceLineBase: 100,
    outputStartLine: 0,
    outputEndLine: 2,
    totalLines: 2,
  );

  @override
  void initState() {
    super.initState();
    settings = AiSettingsController(_Store());
    terminal = _Terminal();
    api = _Api();
    task = TerminalAiController(
      settings: settings,
      terminal: terminal,
      api: api,
    );
    blocks = CommandBlockController(request: _readBlock)..refresh();
    if (widget.state == MobilePrdPreviewState.selected) {
      blocks.select('prd-source');
    }
    unawaited(_prepare());
  }

  Map<String, Object?> _readBlock(Map<String, Object?> args) {
    final lines = <String>[
      if (widget.state == MobilePrdPreviewState.error)
        'Permission denied: /srv/应用/config.yaml'
      else if (widget.state == MobilePrdPreviewState.loading)
        'Inspecting configuration…'
      else
        'Configuration inspected without modification.',
      for (var line = 2; line <= 12; line++)
        'Retained output line $line · 原始日志',
    ];
    final limit = args['limit'] as int? ?? lines.length;
    final offset =
        (args['sourceLine'] ??
                args['offset'] ??
                (args['tail'] == true
                    ? (lines.length - limit).clamp(0, lines.length)
                    : 0))
            as int;
    final end = (offset + limit).clamp(0, lines.length);
    final block = <String, Object?>{
      'id': 'prd-source',
      'command': source.command,
      'cwd': source.cwd,
      'contextId': 'root',
      'columns': 80,
      'running': widget.state == MobilePrdPreviewState.loading,
      'exitCode': switch (widget.state) {
        MobilePrdPreviewState.loading || MobilePrdPreviewState.unknown => null,
        MobilePrdPreviewState.error => 1,
        _ => 0,
      },
      'startedAt': 1000,
      'finishedAt': 1240,
      'totalLines': lines.length,
      'matchingLines': lines.length,
      'offset': offset,
      'nextOffset': end < lines.length ? end : null,
      'hasMore': end < lines.length,
      'lines': [
        for (var i = offset; i < end; i++)
          {'index': i, 'source_row': 100 + i, 'text': lines[i]},
      ],
    };
    return args['id'] == null
        ? {
            'blocks': [block],
          }
        : {'block': block};
  }

  Future<void> _prepare() async {
    await settings.loaded;
    if (!mounted) return;
    await task.refreshContext();
    if (!mounted) return;
    final proposal =
        widget.component == MobilePrdPreviewComponent.proposalCard ||
        widget.component == MobilePrdPreviewComponent.reviewPage;
    if (proposal ||
        widget.state == MobilePrdPreviewState.unknown ||
        widget.state == MobilePrdPreviewState.targetChanged) {
      await task.ask(
        'Inspect the configuration, preserving the original files.',
      );
      if (!mounted) return;
      if (widget.state == MobilePrdPreviewState.unknown) {
        terminal.unknown = true;
        await task.approve();
      } else if (widget.state == MobilePrdPreviewState.targetChanged) {
        terminal.changed = true;
        await task.refreshContext();
      } else if (widget.state == MobilePrdPreviewState.disabled) {
        task.reject();
      }
    } else if (widget.state == MobilePrdPreviewState.loading) {
      api.waiting = Completer<AiReply>();
      unawaited(task.ask('Inspecting the current state…'));
      await Future<void>.delayed(Duration.zero);
    }
    if (!mounted) return;
    if (widget.state == MobilePrdPreviewState.error) {
      terminal.unavailable = true;
      await task.refreshContext();
    }
    if (!mounted) return;
    if (widget.component == MobilePrdPreviewComponent.contextChip ||
        widget.component == MobilePrdPreviewComponent.composerShell) {
      task.attachContext(source);
      task.setDraft(
        widget.state == MobilePrdPreviewState.disabled
            ? ''
            : 'Explain this failure\n保留原始路径 /srv/应用/config.yaml',
      );
    }
    setState(() => ready = true);
  }

  @override
  void dispose() {
    if (api.waiting case final gate? when !gate.isCompleted) {
      gate.complete(const AiReply(text: 'Preview cancelled.'));
    }
    task.dispose();
    settings.dispose();
    blocks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Center(child: CircularProgressIndicator());
    if (widget.component == MobilePrdPreviewComponent.block ||
        widget.component == MobilePrdPreviewComponent.readerHeader) {
      if (widget.component == MobilePrdPreviewComponent.readerHeader &&
          !readerOpened) {
        readerOpened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(
              showCommandBlockReader(
                context,
                controller: blocks,
                id: 'prd-source',
                onAttachRange: (_) {},
              ),
            );
          }
        });
      }
      return TerminalCommandBlocksView(
        controller: blocks,
        onReinput: (_) {},
        onReturnToInput: () {},
        onAskAi: (_) {},
      );
    }
    final component = switch (widget.component) {
      MobilePrdPreviewComponent.contextChip =>
        TerminalAiPreviewComponent.contextChip,
      MobilePrdPreviewComponent.taskHeader =>
        TerminalAiPreviewComponent.taskHeader,
      MobilePrdPreviewComponent.taskStatus =>
        TerminalAiPreviewComponent.taskStatus,
      MobilePrdPreviewComponent.composerShell =>
        TerminalAiPreviewComponent.composerShell,
      MobilePrdPreviewComponent.proposalCard =>
        TerminalAiPreviewComponent.proposalCard,
      MobilePrdPreviewComponent.reviewPage =>
        TerminalAiPreviewComponent.reviewPage,
      _ => TerminalAiPreviewComponent.emptyError,
    };
    return TerminalAiComponentPreview(
      controller: task,
      component: component,
      targetLabel: 'ops@staging.example.test',
      onClose: task.takeOver,
      onObserveTerminal: () {},
      removableContext: widget.state != MobilePrdPreviewState.disabled,
      focusDraft: widget.state == MobilePrdPreviewState.focused,
      selectDraft: widget.state == MobilePrdPreviewState.selected,
    );
  }
}

class _Store implements AiConfigurationStore {
  @override
  Future<AiConfiguration?> read() async => const AiConfiguration.mock();
  @override
  Future<void> write(AiConfiguration? configuration) async {}
}

class _Api implements AiApi {
  Completer<AiReply>? waiting;
  @override
  Future<AiReply> complete(
    AiConfiguration configuration,
    List<Map<String, Object?>> messages,
    AiCancellation cancellation,
  ) async {
    cancellation.check();
    if (waiting case final gate?) return gate.future;
    if (messages.last['role'] == 'tool') {
      return const AiReply(text: 'Inspection complete.');
    }
    return AiReply(
      text: 'Read the file metadata before suggesting a change.',
      action: AiAction.fromToolCall({
        'id': 'preview-inspect',
        'type': 'function',
        'function': {
          'name': 'run_command',
          'arguments': jsonEncode({
            'command': 'ls -l /srv/应用/config.yaml',
            'reason': 'Inspect file permissions',
          }),
        },
      }),
    );
  }
}

class _Terminal implements AiTerminalPort, AiSubmissionInspector {
  final inputs = StreamController<void>.broadcast();
  bool unknown = false;
  bool unavailable = false;
  bool changed = false;
  @override
  Stream<void> get userInput => inputs.stream;
  @override
  Future<AiTerminalContext> readContext() async {
    if (unavailable) throw const AiFailure('session_unavailable');
    return AiTerminalContext(
      sessionId: changed ? 'replacement' : 'preview',
      contextId: 'root',
      guard: changed ? 'replacement:root' : 'preview:root',
      screen: 'ops@staging> ',
      cwd: '/srv/应用',
      canRunCommand: true,
      targetLabel: 'ops@staging.example.test',
      readyLease: 'ready-preview',
      commandNames: const {'ls', 'cat'},
    );
  }

  @override
  Future<Map<String, Object?>> execute(
    AiAction action,
    AiTerminalContext expected,
    AiCancellation cancellation,
  ) async {
    cancellation.check();
    if (unknown) throw const AiFailure('submission_unknown');
    return {
      'status': 'input_sent',
      'submission_id': 'preview-receipt',
      'block_id': 'prd-source',
    };
  }

  @override
  String? submissionFor(String actionId) => 'preview-receipt';
  @override
  Future<Map<String, Object?>> inspectSubmission(String id) async => {
    'status': unknown ? 'unknown' : 'input_sent',
    'submission_id': id,
  };
  @override
  void dispose() => unawaited(inputs.close());
}

@Preview(
  name: 'Block · light',
  group: 'Mobile PRD component states',
  size: Size(390, 640),
)
Widget blockLightStatePreview() => const MobilePrdComponentPreview(
  component: MobilePrdPreviewComponent.block,
  dark: false,
);

@Preview(
  name: 'Block · dark',
  group: 'Mobile PRD component states',
  size: Size(390, 640),
)
Widget blockDarkStatePreview() => const MobilePrdComponentPreview(
  component: MobilePrdPreviewComponent.block,
  dark: true,
);

@Preview(
  name: 'ContextChip · light',
  group: 'Mobile PRD component states',
  size: Size(390, 640),
)
Widget contextChipLightStatePreview() => const MobilePrdComponentPreview(
  component: MobilePrdPreviewComponent.contextChip,
  dark: false,
);

@Preview(
  name: 'ContextChip · dark',
  group: 'Mobile PRD component states',
  size: Size(390, 640),
)
Widget contextChipDarkStatePreview() => const MobilePrdComponentPreview(
  component: MobilePrdPreviewComponent.contextChip,
  dark: true,
);

@Preview(
  name: 'TaskHeader · light',
  group: 'Mobile PRD component states',
  size: Size(390, 640),
)
Widget taskHeaderLightStatePreview() => const MobilePrdComponentPreview(
  component: MobilePrdPreviewComponent.taskHeader,
  dark: false,
);

@Preview(
  name: 'TaskHeader · dark',
  group: 'Mobile PRD component states',
  size: Size(390, 640),
)
Widget taskHeaderDarkStatePreview() => const MobilePrdComponentPreview(
  component: MobilePrdPreviewComponent.taskHeader,
  dark: true,
);

@Preview(
  name: 'TaskStatus · light',
  group: 'Mobile PRD component states',
  size: Size(390, 640),
)
Widget taskStatusLightStatePreview() => const MobilePrdComponentPreview(
  component: MobilePrdPreviewComponent.taskStatus,
  dark: false,
);

@Preview(
  name: 'TaskStatus · dark',
  group: 'Mobile PRD component states',
  size: Size(390, 640),
)
Widget taskStatusDarkStatePreview() => const MobilePrdComponentPreview(
  component: MobilePrdPreviewComponent.taskStatus,
  dark: true,
);

@Preview(
  name: 'ComposerShell · light',
  group: 'Mobile PRD component states',
  size: Size(390, 640),
)
Widget composerShellLightStatePreview() => const MobilePrdComponentPreview(
  component: MobilePrdPreviewComponent.composerShell,
  dark: false,
);

@Preview(
  name: 'ComposerShell · dark',
  group: 'Mobile PRD component states',
  size: Size(390, 640),
)
Widget composerShellDarkStatePreview() => const MobilePrdComponentPreview(
  component: MobilePrdPreviewComponent.composerShell,
  dark: true,
);

@Preview(
  name: 'ProposalCard · light',
  group: 'Mobile PRD component states',
  size: Size(390, 640),
)
Widget proposalCardLightStatePreview() => const MobilePrdComponentPreview(
  component: MobilePrdPreviewComponent.proposalCard,
  dark: false,
);

@Preview(
  name: 'ProposalCard · dark',
  group: 'Mobile PRD component states',
  size: Size(390, 640),
)
Widget proposalCardDarkStatePreview() => const MobilePrdComponentPreview(
  component: MobilePrdPreviewComponent.proposalCard,
  dark: true,
);

@Preview(
  name: 'ReviewPage · light',
  group: 'Mobile PRD component states',
  size: Size(390, 640),
)
Widget reviewPageLightStatePreview() => const MobilePrdComponentPreview(
  component: MobilePrdPreviewComponent.reviewPage,
  dark: false,
);

@Preview(
  name: 'ReviewPage · dark',
  group: 'Mobile PRD component states',
  size: Size(390, 640),
)
Widget reviewPageDarkStatePreview() => const MobilePrdComponentPreview(
  component: MobilePrdPreviewComponent.reviewPage,
  dark: true,
);

@Preview(
  name: 'ReaderHeader · light',
  group: 'Mobile PRD component states',
  size: Size(390, 640),
)
Widget readerHeaderLightStatePreview() => const MobilePrdComponentPreview(
  component: MobilePrdPreviewComponent.readerHeader,
  dark: false,
);

@Preview(
  name: 'ReaderHeader · dark',
  group: 'Mobile PRD component states',
  size: Size(390, 640),
)
Widget readerHeaderDarkStatePreview() => const MobilePrdComponentPreview(
  component: MobilePrdPreviewComponent.readerHeader,
  dark: true,
);

@Preview(
  name: 'Empty / Error · light',
  group: 'Mobile PRD component states',
  size: Size(390, 640),
)
Widget emptyErrorLightStatePreview() => const MobilePrdComponentPreview(
  component: MobilePrdPreviewComponent.emptyError,
  dark: false,
);

@Preview(
  name: 'Empty / Error · dark',
  group: 'Mobile PRD component states',
  size: Size(390, 640),
)
Widget emptyErrorDarkStatePreview() => const MobilePrdComponentPreview(
  component: MobilePrdPreviewComponent.emptyError,
  dark: true,
);
