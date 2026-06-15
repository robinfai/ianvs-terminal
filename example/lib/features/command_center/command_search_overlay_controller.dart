import 'command_search_index.dart';
import 'command_search_query_parser.dart';

enum CommandSearchOverlayKeyIntent {
  openSearch,
  closeSearch,
  movePrevious,
  moveNext,
  insertSelection,
  executeSelection,
}

enum CommandSearchOverlayOutputKind { none, insert, explicitExecute }

class CommandSearchOverlayOutput {
  const CommandSearchOverlayOutput._({required this.kind, this.command});

  static const none = CommandSearchOverlayOutput._(
    kind: CommandSearchOverlayOutputKind.none,
  );

  const CommandSearchOverlayOutput.insert(String command)
    : this._(kind: CommandSearchOverlayOutputKind.insert, command: command);

  const CommandSearchOverlayOutput.explicitExecute(String command)
    : this._(
        kind: CommandSearchOverlayOutputKind.explicitExecute,
        command: command,
      );

  final CommandSearchOverlayOutputKind kind;
  final String? command;
}

class CommandSearchOverlayState {
  const CommandSearchOverlayState({
    required this.isOpen,
    required this.query,
    required this.results,
    required this.selectedIndex,
  });

  const CommandSearchOverlayState.closed()
    : isOpen = false,
      query = '',
      results = const <CommandSearchResult>[],
      selectedIndex = -1;

  final bool isOpen;
  final String query;
  final List<CommandSearchResult> results;
  final int selectedIndex;

  bool get empty => isOpen && results.isEmpty;

  CommandSearchResult? get selectedResult {
    if (selectedIndex < 0 || selectedIndex >= results.length) {
      return null;
    }
    return results[selectedIndex];
  }
}

class CommandSearchOverlayController {
  CommandSearchOverlayController({
    required CommandSearchIndex index,
    String? currentCwd,
    CommandSearchQueryParser parser = const CommandSearchQueryParser(),
  }) : _index = index,
       _currentCwd = currentCwd,
       _parser = parser;

  final CommandSearchIndex _index;
  final String? _currentCwd;
  final CommandSearchQueryParser _parser;

  CommandSearchOverlayState state = const CommandSearchOverlayState.closed();

  CommandSearchOverlayOutput handleIntent(
    CommandSearchOverlayKeyIntent intent,
  ) {
    return switch (intent) {
      CommandSearchOverlayKeyIntent.openSearch => _open(),
      CommandSearchOverlayKeyIntent.closeSearch => _close(),
      CommandSearchOverlayKeyIntent.movePrevious => _moveSelection(-1),
      CommandSearchOverlayKeyIntent.moveNext => _moveSelection(1),
      CommandSearchOverlayKeyIntent.insertSelection => _accept(
        CommandSearchOverlayOutputKind.insert,
      ),
      CommandSearchOverlayKeyIntent.executeSelection => _accept(
        CommandSearchOverlayOutputKind.explicitExecute,
      ),
    };
  }

  void updateQuery(String query) {
    if (!state.isOpen) {
      return;
    }
    final results = _index.search(
      _parser.parse(query),
      currentCwd: _currentCwd,
    );
    state = CommandSearchOverlayState(
      isOpen: true,
      query: query,
      results: results,
      selectedIndex: results.isEmpty ? -1 : 0,
    );
  }

  CommandSearchOverlayOutput _open() {
    final results = _index.search(_parser.parse(''), currentCwd: _currentCwd);
    state = CommandSearchOverlayState(
      isOpen: true,
      query: '',
      results: results,
      selectedIndex: results.isEmpty ? -1 : 0,
    );
    return CommandSearchOverlayOutput.none;
  }

  CommandSearchOverlayOutput _close() {
    state = const CommandSearchOverlayState.closed();
    return CommandSearchOverlayOutput.none;
  }

  CommandSearchOverlayOutput _moveSelection(int delta) {
    if (!state.isOpen || state.results.isEmpty) {
      return CommandSearchOverlayOutput.none;
    }
    final nextIndex = (state.selectedIndex + delta)
        .clamp(0, state.results.length - 1)
        .toInt();
    state = CommandSearchOverlayState(
      isOpen: state.isOpen,
      query: state.query,
      results: state.results,
      selectedIndex: nextIndex,
    );
    return CommandSearchOverlayOutput.none;
  }

  CommandSearchOverlayOutput _accept(CommandSearchOverlayOutputKind kind) {
    final command = state.selectedResult?.entry.command;
    if (command == null) {
      return CommandSearchOverlayOutput.none;
    }
    return switch (kind) {
      CommandSearchOverlayOutputKind.insert =>
        CommandSearchOverlayOutput.insert(command),
      CommandSearchOverlayOutputKind.explicitExecute =>
        CommandSearchOverlayOutput.explicitExecute(command),
      CommandSearchOverlayOutputKind.none => CommandSearchOverlayOutput.none,
    };
  }
}
