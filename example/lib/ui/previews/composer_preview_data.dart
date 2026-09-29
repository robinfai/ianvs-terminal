import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

enum ComposerPreviewScenario { completion, history, suggestion }

TerminalComposerController createComposerPreviewController(
  ComposerPreviewScenario scenario,
) =>
    TerminalComposerController(
        targetId: 'preview',
        text: scenario == ComposerPreviewScenario.completion
            ? 'git che'
            : 'git',
        provider: (query, _) async => CompletionBatch(
          query,
          query.value.text == 'git che'
              ? const [
                  CompletionEdit(
                    itemId: 'checkout',
                    label: 'checkout',
                    detail: 'Switch branches or restore working tree files',
                    kind: 'subcommand',
                    source: 'catalog',
                    start: 4,
                    end: 7,
                    newText: 'checkout',
                    cursor: 12,
                  ),
                  CompletionEdit(
                    itemId: 'cherry-pick',
                    label: 'cherry-pick',
                    detail: 'Apply changes from existing commits',
                    kind: 'subcommand',
                    source: 'catalog',
                    start: 4,
                    end: 7,
                    newText: 'cherry-pick',
                    cursor: 15,
                  ),
                ]
              : const [],
        ),
        submit: (_) async => ComposerSubmissionOutcome.accepted,
      )
      ..updateShell(
        contextKey: 'preview-ready',
        cwd: '~/code/ianvs-terminal',
        dialect: 'zsh',
        lease: 'preview-lease',
        ownership: ComposerOwnership.ready,
      )
      ..updateHistory([
        'git checkout composer',
        'git status --short',
        'git diff --stat',
        'git log --oneline -5',
        'git branch --show-current',
        'ls ./documents/',
      ]);

/// A separate matrix keeps the original three golden scenarios stable while
/// sharing richer, real-controller fixtures between previews and UI captures.
enum ComposerRedesignScenario {
  empty,
  completion,
  history,
  suggestion,
  multiline,
  draft,
  running,
  submitting,
  suspended,
  unknown,
  rejected,
  selection,
  noCompletions,
  unavailable,
  emptyHistory,
  loading,
  unknownLoading,
  longPath,
  longAlias,
  completionDetails,
  longHistory,
  historyNoMatch,
  unsupportedContext,
  automaticSuggestions,
  moreMenu,
  copyFeedback,
  shortcutHelp,
}

class ComposerRedesignFixture {
  ComposerRedesignFixture(this.scenario) {
    final legacy = switch (scenario) {
      ComposerRedesignScenario.completion => ComposerPreviewScenario.completion,
      ComposerRedesignScenario.history => ComposerPreviewScenario.history,
      ComposerRedesignScenario.suggestion => ComposerPreviewScenario.suggestion,
      _ => null,
    };
    if (legacy != null) {
      controller = createComposerPreviewController(legacy);
      return;
    }
    controller =
        TerminalComposerController(
          targetId: 'redesign-fixture',
          text: switch (scenario) {
            ComposerRedesignScenario.empty ||
            ComposerRedesignScenario.emptyHistory ||
            ComposerRedesignScenario.longHistory => '',
            ComposerRedesignScenario.multiline =>
              'for file in ./reports/*.json; do\n  jq . "\$file"\ndone',
            ComposerRedesignScenario.selection => 'cd ../../../',
            ComposerRedesignScenario.noCompletions => 'cd ./missing-',
            ComposerRedesignScenario.loading ||
            ComposerRedesignScenario.unavailable ||
            ComposerRedesignScenario.automaticSuggestions => 'git che',
            ComposerRedesignScenario.longPath => 'ls ./',
            ComposerRedesignScenario.longAlias ||
            ComposerRedesignScenario.completionDetails => 'deploy',
            ComposerRedesignScenario.historyNoMatch => 'does-not-match-history',
            ComposerRedesignScenario.unsupportedContext => r'echo $(git ',
            ComposerRedesignScenario.moreMenu ||
            ComposerRedesignScenario.copyFeedback ||
            ComposerRedesignScenario.shortcutHelp => 'git',
            _ => 'npm run build',
          },
          provider: (query, _) async {
            if (scenario == ComposerRedesignScenario.loading ||
                scenario == ComposerRedesignScenario.unknownLoading) {
              await _completion.future;
            }
            if (scenario == ComposerRedesignScenario.unavailable) {
              throw StateError('Fixture completion provider unavailable');
            }
            if (scenario == ComposerRedesignScenario.unsupportedContext) {
              return CompletionBatch(
                query,
                const [],
                status: 'unsupported_context',
              );
            }
            if (scenario == ComposerRedesignScenario.longAlias ||
                scenario == ComposerRedesignScenario.completionDetails) {
              return CompletionBatch(query, [
                for (final alias in const [
                  'deploy-production-from-preview-environment-with-full-verification',
                  'deploy-preview',
                  'deploy-rollback',
                ])
                  CompletionEdit(
                    itemId: alias,
                    label: alias,
                    detail:
                        '部署到生产预览环境，并保留完整发布记录；此处只补全命令，不执行部署。 '
                        'Long shell alias metadata remains readable without hiding the command.',
                    kind: 'alias',
                    source: 'shell',
                    start: 0,
                    end: query.value.text.length,
                    newText: alias,
                    cursor: alias.length,
                  ),
              ]);
            }
            if (scenario == ComposerRedesignScenario.automaticSuggestions) {
              return CompletionBatch(query, const [
                CompletionEdit(
                  itemId: 'checkout',
                  label: 'checkout',
                  detail: 'Switch branches or restore working tree files',
                  kind: 'subcommand',
                  source: 'catalog',
                  start: 4,
                  end: 7,
                  newText: 'checkout',
                  cursor: 12,
                ),
              ]);
            }
            return CompletionBatch(query, const []);
          },
          submit: (_) async => switch (scenario) {
            ComposerRedesignScenario.unknown ||
            ComposerRedesignScenario.unknownLoading =>
              ComposerSubmissionOutcome.unknown,
            ComposerRedesignScenario.rejected =>
              ComposerSubmissionOutcome.rejected,
            ComposerRedesignScenario.submitting => await _submission.future,
            _ => ComposerSubmissionOutcome.accepted,
          },
        )..updateShell(
          contextKey: 'redesign-ready',
          cwd: scenario == ComposerRedesignScenario.longPath
              ? longCjkPath
              : '~/workspace/ianvs-terminal',
          dialect: 'zsh',
          lease: 'redesign-lease',
          ownership: ComposerOwnership.ready,
        );
    if (scenario == ComposerRedesignScenario.longHistory) {
      controller.updateHistory([
        for (var index = 39; index >= 0; index--)
          'git log --oneline --grep="发布记录 $index · 客户端窗口与命令输入交互回归"',
      ]);
    } else if (scenario == ComposerRedesignScenario.historyNoMatch ||
        scenario == ComposerRedesignScenario.moreMenu ||
        scenario == ComposerRedesignScenario.copyFeedback) {
      controller.updateHistory(['git status --short', 'git diff --stat']);
    }
  }

  static const longCjkPath =
      '/Users/developer/工作项目/客户交付与回归测试/2026 年度发布/命令输入与终端交互/财务报表';

  final ComposerRedesignScenario scenario;
  late final TerminalComposerController controller;
  final _submission = Completer<ComposerSubmissionOutcome>();
  final _completion = Completer<void>();

  String get targetLabel => scenario == ComposerRedesignScenario.longPath
      ? 'Local Shell · 开发环境'
      : 'Local Shell';

  bool get hasCompletionMenu => switch (scenario) {
    ComposerRedesignScenario.completion ||
    ComposerRedesignScenario.longAlias ||
    ComposerRedesignScenario.completionDetails ||
    ComposerRedesignScenario.automaticSuggestions => true,
    _ => false,
  };

  bool get hasHistoryMenu => switch (scenario) {
    ComposerRedesignScenario.history ||
    ComposerRedesignScenario.emptyHistory ||
    ComposerRedesignScenario.longHistory ||
    ComposerRedesignScenario.historyNoMatch => true,
    _ => false,
  };

  /// Call after the view has mounted, so focus and overlays use real geometry.
  void activate() {
    switch (scenario) {
      case ComposerRedesignScenario.completion:
      case ComposerRedesignScenario.longAlias:
      case ComposerRedesignScenario.completionDetails:
      case ComposerRedesignScenario.loading:
        controller.requestCompletions();
      case ComposerRedesignScenario.automaticSuggestions:
        controller.toggleLocalSuggestions();
      case ComposerRedesignScenario.history:
      case ComposerRedesignScenario.emptyHistory:
      case ComposerRedesignScenario.longHistory:
      case ComposerRedesignScenario.historyNoMatch:
        controller.openHistory();
      case ComposerRedesignScenario.selection:
        controller.editor.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.editor.text.length,
        );
        controller.completeOnTab();
      case ComposerRedesignScenario.noCompletions:
      case ComposerRedesignScenario.unavailable:
      case ComposerRedesignScenario.unsupportedContext:
        controller.completeOnTab();
      case ComposerRedesignScenario.unknown:
      case ComposerRedesignScenario.unknownLoading:
      case ComposerRedesignScenario.rejected:
      case ComposerRedesignScenario.submitting:
        unawaited(controller.run());
      case ComposerRedesignScenario.draft:
      case ComposerRedesignScenario.running:
      case ComposerRedesignScenario.suspended:
        controller.updateShell(
          contextKey: 'redesign-${scenario.name}',
          cwd: controller.cwd,
          dialect: 'zsh',
          lease: null,
          ownership: switch (scenario) {
            ComposerRedesignScenario.draft => ComposerOwnership.draft,
            ComposerRedesignScenario.running => ComposerOwnership.running,
            _ => ComposerOwnership.suspended,
          },
        );
      case ComposerRedesignScenario.empty:
      case ComposerRedesignScenario.suggestion:
      case ComposerRedesignScenario.multiline:
      case ComposerRedesignScenario.longPath:
      case ComposerRedesignScenario.moreMenu:
      case ComposerRedesignScenario.copyFeedback:
      case ComposerRedesignScenario.shortcutHelp:
        break;
    }
  }

  /// Call after the first provider/submission microtasks have completed.
  void revealSelection() {
    if (hasCompletionMenu && controller.items.isNotEmpty) {
      controller.selectNext(1);
    }
    if (scenario == ComposerRedesignScenario.unknownLoading) {
      controller.requestCompletions();
    }
  }

  void finish() {
    if (!_submission.isCompleted) {
      _submission.complete(ComposerSubmissionOutcome.accepted);
    }
    if (!_completion.isCompleted) _completion.complete();
  }

  void dispose() {
    finish();
    controller.dispose();
  }
}
