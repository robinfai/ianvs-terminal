import 'command_action_search_index.dart';

enum CommandActionSearchIntent {
  openSearch,
  closeSearch,
  movePrevious,
  moveNext,
  acceptSelection,
}

enum CommandActionSearchOutputKind { none, openAction, insertSavedCommand }

class CommandActionSearchOutput {
  const CommandActionSearchOutput._({required this.kind, this.item});

  static const none = CommandActionSearchOutput._(
    kind: CommandActionSearchOutputKind.none,
  );

  const CommandActionSearchOutput.openAction(CommandActionSearchItem item)
    : this._(kind: CommandActionSearchOutputKind.openAction, item: item);

  const CommandActionSearchOutput.insertSavedCommand(
    CommandActionSearchItem item,
  ) : this._(
        kind: CommandActionSearchOutputKind.insertSavedCommand,
        item: item,
      );

  final CommandActionSearchOutputKind kind;
  final CommandActionSearchItem? item;

  String? get actionId {
    final selected = item;
    if (kind != CommandActionSearchOutputKind.openAction || selected == null) {
      return null;
    }
    return selected.id;
  }

  String? get command {
    final selected = item;
    if (kind != CommandActionSearchOutputKind.insertSavedCommand ||
        selected == null) {
      return null;
    }
    return selected.command;
  }
}

class CommandActionSearchState {
  const CommandActionSearchState({
    required this.isOpen,
    required this.query,
    required this.results,
    required this.selectedIndex,
  });

  const CommandActionSearchState.closed()
    : isOpen = false,
      query = '',
      results = const <CommandActionSearchResult>[],
      selectedIndex = -1;

  final bool isOpen;
  final String query;
  final List<CommandActionSearchResult> results;
  final int selectedIndex;

  bool get empty => isOpen && results.isEmpty;

  CommandActionSearchResult? get selectedResult {
    if (selectedIndex < 0 || selectedIndex >= results.length) {
      return null;
    }
    return results[selectedIndex];
  }
}

class CommandActionSearchController {
  CommandActionSearchController({required CommandActionSearchIndex index})
    : _index = index;

  final CommandActionSearchIndex _index;

  CommandActionSearchState state = const CommandActionSearchState.closed();

  CommandActionSearchOutput handleIntent(CommandActionSearchIntent intent) {
    return switch (intent) {
      CommandActionSearchIntent.openSearch => _open(),
      CommandActionSearchIntent.closeSearch => _close(),
      CommandActionSearchIntent.movePrevious => _moveSelection(-1),
      CommandActionSearchIntent.moveNext => _moveSelection(1),
      CommandActionSearchIntent.acceptSelection => _accept(),
    };
  }

  void updateQuery(String query) {
    if (!state.isOpen) {
      return;
    }
    final results = _index.search(query);
    state = CommandActionSearchState(
      isOpen: true,
      query: query,
      results: results,
      selectedIndex: results.isEmpty ? -1 : 0,
    );
  }

  CommandActionSearchOutput _open() {
    final results = _index.search('');
    state = CommandActionSearchState(
      isOpen: true,
      query: '',
      results: results,
      selectedIndex: results.isEmpty ? -1 : 0,
    );
    return CommandActionSearchOutput.none;
  }

  CommandActionSearchOutput _close() {
    state = const CommandActionSearchState.closed();
    return CommandActionSearchOutput.none;
  }

  CommandActionSearchOutput _moveSelection(int delta) {
    if (!state.isOpen || state.results.isEmpty) {
      return CommandActionSearchOutput.none;
    }
    final nextIndex = (state.selectedIndex + delta)
        .clamp(0, state.results.length - 1)
        .toInt();
    state = CommandActionSearchState(
      isOpen: state.isOpen,
      query: state.query,
      results: state.results,
      selectedIndex: nextIndex,
    );
    return CommandActionSearchOutput.none;
  }

  CommandActionSearchOutput _accept() {
    final item = state.selectedResult?.item;
    if (item == null) {
      return CommandActionSearchOutput.none;
    }
    return switch (item.selection) {
      CommandActionSelection.openAction => CommandActionSearchOutput.openAction(
        item,
      ),
      CommandActionSelection.insertSavedCommand =>
        CommandActionSearchOutput.insertSavedCommand(item),
    };
  }
}
