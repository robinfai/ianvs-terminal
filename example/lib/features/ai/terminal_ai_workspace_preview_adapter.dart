part of 'terminal_ai_workspace.dart';

/// Development-only entry points into the production presentation builders.
/// This adapter owns no fixture data, network configuration or execution logic.
/// Normal application routes instantiate [TerminalAiWorkspace] directly.
enum TerminalAiPreviewComponent {
  contextChip,
  taskHeader,
  taskStatus,
  composerShell,
  proposalCard,
  reviewPage,
  emptyError,
}

class TerminalAiComponentPreview extends TerminalAiWorkspace {
  const TerminalAiComponentPreview({
    required super.controller,
    required super.onClose,
    required this.component,
    this.removableContext = true,
    this.focusDraft = false,
    this.selectDraft = false,
    super.targetLabel,
    super.onObserveTerminal,
    super.key,
  });

  final TerminalAiPreviewComponent component;
  final bool removableContext;
  final bool focusDraft;
  final bool selectDraft;

  @override
  State<TerminalAiWorkspace> createState() =>
      _TerminalAiComponentPreviewState();
}

class _TerminalAiComponentPreviewState extends _TerminalAiWorkspaceState {
  bool _reviewOpened = false;
  bool _draftFocused = false;
  TerminalAiComponentPreview get preview =>
      widget as TerminalAiComponentPreview;

  @override
  Widget build(BuildContext context) {
    final proposal = c.transcript
        .where((entry) => entry.action != null)
        .lastOrNull;
    final block =
        c.attachments.firstOrNull ??
        c.transcript.expand((entry) => entry.contexts).firstOrNull;
    if (!_draftFocused && (preview.focusDraft || preview.selectDraft)) {
      _draftFocused = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (preview.selectDraft) {
          _input.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _input.text.length,
          );
        }
        _focus.requestFocus();
      });
    }
    if (preview.component == TerminalAiPreviewComponent.reviewPage &&
        proposal != null &&
        !_reviewOpened) {
      _reviewOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_review(proposal));
      });
    }
    return Material(
      color: context.appTheme.panel,
      child: switch (preview.component) {
        TerminalAiPreviewComponent.contextChip =>
          block == null
              ? _emptyState()
              : Align(
                  alignment: Alignment.topLeft,
                  child: _contextChip(
                    block,
                    removable: preview.removableContext,
                  ),
                ),
        TerminalAiPreviewComponent.taskHeader => Align(
          alignment: Alignment.topCenter,
          child: _header(true),
        ),
        TerminalAiPreviewComponent.taskStatus => Align(
          alignment: Alignment.topCenter,
          child: _statusBar(false),
        ),
        TerminalAiPreviewComponent.composerShell => Align(
          alignment: Alignment.topCenter,
          child: _composer(true),
        ),
        TerminalAiPreviewComponent.proposalCard =>
          proposal == null
              ? _emptyState()
              : SingleChildScrollView(child: _proposal(proposal, true)),
        TerminalAiPreviewComponent.reviewPage => _reviewPresentation(
          proposal == null
              ? _emptyState()
              : SingleChildScrollView(child: _proposal(proposal, true)),
        ),
        TerminalAiPreviewComponent.emptyError =>
          c.error != null ||
                  c.terminalError != null ||
                  c.hasUnresolvedSubmission
              ? _recovery()
              : _emptyState(),
      },
    );
  }
}
