import '../shell/shell_action_registry.dart';
import 'shell_productivity_models.dart';

sealed class ShellProductivityActionResult {
  const ShellProductivityActionResult();
}

class ShellProductivityStateResult extends ShellProductivityActionResult {
  const ShellProductivityStateResult(this.state);

  final ShellProductivityState state;
}

class ShellProductivityPromptResult extends ShellProductivityActionResult {
  const ShellProductivityPromptResult(this.prompt);

  final ShellPromptMark? prompt;
}

class ShellProductivityCommandOutputResult
    extends ShellProductivityActionResult {
  const ShellProductivityCommandOutputResult(this.range);

  final ShellCommandOutputRange? range;
}

class ShellProductivityRecentDirectoryResult
    extends ShellProductivityActionResult {
  const ShellProductivityRecentDirectoryResult(this.directory);

  final String? directory;
}

class ShellProductivitySearchResult extends ShellProductivityActionResult {
  const ShellProductivitySearchResult(this.search);

  final ShellSearchState search;
}

class ShellProductivityNoopResult extends ShellProductivityActionResult {
  const ShellProductivityNoopResult();
}

class ShellProductivityActionContext {
  const ShellProductivityActionContext({
    this.currentRow = 0,
    this.search = const ShellSearchState(),
  });

  final int currentRow;
  final ShellSearchState search;
}

class ShellProductivityActionReducer {
  const ShellProductivityActionReducer._();

  static ShellProductivityActionResult reduce({
    required ShellProductivityState state,
    required TerminalActionId actionId,
    required ShellProductivityActionContext context,
  }) {
    return switch (actionId) {
      TerminalActionId.toggleReadOnly => ShellProductivityStateResult(
        state.toggleReadOnly(),
      ),
      TerminalActionId.previousPrompt => ShellProductivityPromptResult(
        state.previousPrompt(context.currentRow),
      ),
      TerminalActionId.nextPrompt => ShellProductivityPromptResult(
        state.nextPrompt(context.currentRow),
      ),
      TerminalActionId.selectCommandOutput ||
      TerminalActionId.copyCommandOutput =>
        ShellProductivityCommandOutputResult(state.lastCommandOutputRange()),
      TerminalActionId.openRecentDirectory =>
        ShellProductivityRecentDirectoryResult(state.firstRecentDirectory),
      TerminalActionId.clearScrollback => const ShellProductivityNoopResult(),
      TerminalActionId.search => ShellProductivitySearchResult(context.search),
      TerminalActionId.globalSearch => ShellProductivitySearchResult(
        context.search.clear(),
      ),
      _ => const ShellProductivityNoopResult(),
    };
  }
}
