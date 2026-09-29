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
