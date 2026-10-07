import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../../features/ai/ai_api_client.dart';
import '../../features/ai/ai_models.dart';
import '../../features/ai/ai_settings.dart';
import '../../features/ai/terminal_ai_controller.dart';
import '../../features/ai/terminal_ai_retained_timeline.dart';
import '../../features/ai/terminal_ai_workspace.dart';
import '../app_ui.dart';

@Preview(
  name: 'AI workspace · Review',
  group: 'Terminal',
  size: Size(1000, 760),
)
Widget aiWorkspaceReviewPreview() => const AiWorkspacePreview();

@Preview(
  name: 'AI workspace · Dark evidence',
  group: 'Terminal',
  size: Size(1000, 760),
)
Widget aiWorkspaceEvidencePreview() =>
    const AiWorkspacePreview(dark: true, completed: true);

@Preview(
  name: 'AI workspace · Phone fixed text',
  group: 'Terminal',
  size: Size(390, 844),
)
Widget aiWorkspacePhonePreview() =>
    const AiWorkspacePreview(phone: true, draftOnly: true);

@Preview(
  name: 'AI workspace · Short phone',
  group: 'Terminal',
  size: Size(390, 320),
)
Widget aiWorkspaceShortPreview() =>
    const AiWorkspacePreview(phone: true, dark: true);

/// All interactions use in-memory fixtures. No network, credentials or PTY.
class AiWorkspacePreview extends StatefulWidget {
  const AiWorkspacePreview({
    super.key,
    this.phone = false,
    this.dark = false,
    this.completed = false,
    this.draftOnly = false,
  });
  final bool phone;
  final bool dark;
  final bool completed;
  final bool draftOnly;
  @override
  State<AiWorkspacePreview> createState() => _AiWorkspacePreviewState();
}

class _AiWorkspacePreviewState extends State<AiWorkspacePreview> {
  late final AiSettingsController settings;
  late final TerminalAiController task;
  late final CommandBlockController blocks;
  @override
  void initState() {
    super.initState();
    settings = AiSettingsController(_PreviewStore());
    task = TerminalAiController(
      settings: settings,
      terminal: _PreviewTerminal(),
      api: _PreviewApi(),
    );
    blocks = CommandBlockController(
      request: (args) {
        final block = <String, Object?>{
          'id': 'preview-result',
          'command': 'git status --short',
          'cwd': '~/project',
          'contextId': 'root',
          'running': false,
          'exitCode': 0,
          'columns': 80,
          'totalLines': 2,
          'matchingLines': 2,
          'lines': [
            {
              'index': 0,
              'text': ' M lib/features/terminal/command_blocks.dart',
              'source_row': 100,
            },
            {
              'index': 1,
              'text': ' M test/terminal/command_blocks_test.dart',
              'source_row': 101,
            },
          ],
        };
        final failed = <String, Object?>{
          ...block,
          'id': 'preview-failure',
          'command': 'ls --bad',
          'exitCode': 2,
          'lines': [
            {
              'index': 0,
              'text': "ls: unrecognized option '--bad'",
              'source_row': 20,
            },
            {
              'index': 1,
              'text': "Try 'ls --help' for more information.",
              'source_row': 21,
            },
          ],
        };
        return args['id'] == null
            ? {
                'blocks': [failed, block],
              }
            : {'block': args['id'] == 'preview-failure' ? failed : block};
      },
    )..refresh();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    await settings.loaded;
    if (!mounted) return;
    if (widget.draftOnly) {
      await task.refreshContext();
      if (!mounted) return;
      task.attachContext(
        const AiBlockContext(
          id: 'preview-failure',
          command: 'ls --bad',
          output:
              "ls: unrecognized option '--bad'\nTry 'ls --help' for more information.",
          exitCode: 2,
          cwd: '~/project',
          sourceSessionId: 'preview',
          sourceContextId: 'root',
          sourceLineBase: 20,
          outputStartLine: 0,
          outputEndLine: 2,
          totalLines: 2,
        ),
      );
      task.setDraft('解释这个错误');
      setState(() {});
      return;
    }
    await task.ask('检查当前工作区有哪些改动，只读取状态。');
    if (!mounted) return;
    if (widget.completed) await task.approve();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    task.dispose();
    settings.dispose();
    blocks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildIanvsTerminalTheme(
      widget.dark ? Brightness.dark : Brightness.light,
      platform: widget.phone ? TargetPlatform.iOS : TargetPlatform.macOS,
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => TerminalAiWorkspace(
          controller: task,
          targetLabel: 'Local Shell',
          onClose: task.takeOver,
          onShowEvidence: (reference) => unawaited(
            showAiEvidenceReader(
              context,
              controller: blocks,
              reference: reference,
              sourceSessionId: reference.origins.first.sessionId,
            ),
          ),
          timelineBuilder: (items, scroll, follow) => TerminalCommandBlocksView(
            controller: blocks,
            onReinput: task.setDraft,
            timeline: items,
            scrollController: scroll,
            followTail: follow,
            showToolbar: false,
            chinese: true,
          ),
        ),
      ),
    ),
  );
}

class _PreviewStore implements AiConfigurationStore {
  @override
  Future<AiConfiguration?> read() async => const AiConfiguration.mock();
  @override
  Future<void> write(AiConfiguration? _) async {}
}

class _PreviewTerminal implements AiTerminalPort {
  final inputs = StreamController<void>.broadcast();
  @override
  Stream<void> get userInput => inputs.stream;
  @override
  Future<AiTerminalContext> readContext() async => const AiTerminalContext(
    sessionId: 'preview',
    contextId: 'root',
    targetLabel: 'Local Shell',
    guard: 'preview',
    screen: '',
    cwd: '~/project',
    canRunCommand: true,
    readyLease: 'preview',
  );
  @override
  Future<Map<String, Object?>> execute(
    AiAction action,
    AiTerminalContext expected,
    AiCancellation cancellation,
  ) async {
    cancellation.check();
    return {
      'status': 'input_sent',
      'submission_id': 'preview-submit',
      'block_id': 'preview-result',
    };
  }

  @override
  void dispose() => unawaited(inputs.close());
}

class _PreviewApi implements AiApi {
  int sequence = 0;
  @override
  Future<AiReply> complete(
    AiConfiguration configuration,
    List<Map<String, Object?>> messages,
    AiCancellation cancellation,
  ) async {
    cancellation.check();
    if (messages.last['role'] == 'tool') {
      return const AiReply(
        text: '当前状态列出了两处修改；这只验证了工作区状态。 [block:preview-result:1-2]',
      );
    }
    return AiReply(
      text: '先读取当前工作区状态，不修改文件。',
      action: AiAction.fromToolCall({
        'id': 'preview-${sequence++}',
        'type': 'function',
        'function': {
          'name': 'run_command',
          'arguments': jsonEncode({
            'command': 'git status --short',
            'reason': '读取工作区改动',
          }),
        },
      }),
    );
  }
}
