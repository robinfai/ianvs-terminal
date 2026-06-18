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

enum CommandSearchOverlayOutputKind { none, insert, explicitExecute, viewBlock }

class CommandSearchOverlayOutput {
  const CommandSearchOverlayOutput._({
    required this.kind,
    this.command,
    this.invocationId,
  });

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

  const CommandSearchOverlayOutput.viewBlock(String invocationId)
    : this._(
        kind: CommandSearchOverlayOutputKind.viewBlock,
        invocationId: invocationId,
      );

  final CommandSearchOverlayOutputKind kind;
  final String? command;
  final String? invocationId;
}

class CommandSearchOverlayState {
  const CommandSearchOverlayState({
    required this.isOpen,
    required this.query,
    required this.results,
    required this.selectedIndex,
    required this.scope,
  });

  const CommandSearchOverlayState.closed()
    : isOpen = false,
      query = '',
      results = const <CommandSearchResult>[],
      selectedIndex = -1,
      scope = CommandSearchHistoryScope.currentSession;

  final bool isOpen;
  final String query;
  final List<CommandSearchResult> results;
  final int selectedIndex;
  final CommandSearchHistoryScope scope;

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
    String? currentSessionId,
    CommandSearchHistoryScope initialScope =
        CommandSearchHistoryScope.currentSession,
    CommandSearchQueryParser parser = const CommandSearchQueryParser(),
  }) : _index = index,
       _currentCwd = currentCwd,
       _currentSessionId = currentSessionId,
       _parser = parser {
    state = CommandSearchOverlayState.closed().copyWith(scope: initialScope);
  }

  final CommandSearchIndex _index;
  final String? _currentCwd;
  final String? _currentSessionId;
  final CommandSearchQueryParser _parser;

  late CommandSearchOverlayState state;

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
    final results = _resultsForQuery(query, scope: state.scope);
    state = CommandSearchOverlayState(
      isOpen: true,
      query: query,
      results: results,
      selectedIndex: results.isEmpty ? -1 : 0,
      scope: state.scope,
    );
  }

  void updateScope(CommandSearchHistoryScope scope) {
    final query = state.query;
    if (!state.isOpen) {
      state = CommandSearchOverlayState.closed().copyWith(scope: scope);
      return;
    }
    final results = _resultsForQuery(query, scope: scope);
    state = CommandSearchOverlayState(
      isOpen: true,
      query: query,
      results: results,
      selectedIndex: results.isEmpty ? -1 : 0,
      scope: scope,
    );
  }

  CommandSearchOverlayOutput viewSelectedBlock() {
    final invocationId = state.selectedResult?.entry.invocationId;
    if (invocationId == null) {
      return CommandSearchOverlayOutput.none;
    }
    return CommandSearchOverlayOutput.viewBlock(invocationId);
  }

  CommandSearchOverlayOutput _open() {
    final scope = state.scope;
    final results = _resultsForQuery('', scope: scope);
    state = CommandSearchOverlayState(
      isOpen: true,
      query: '',
      results: results,
      selectedIndex: results.isEmpty ? -1 : 0,
      scope: scope,
    );
    return CommandSearchOverlayOutput.none;
  }

  CommandSearchOverlayOutput _close() {
    state = CommandSearchOverlayState.closed().copyWith(scope: state.scope);
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
      scope: state.scope,
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
      CommandSearchOverlayOutputKind.viewBlock => CommandSearchOverlayOutput.none,
      CommandSearchOverlayOutputKind.none => CommandSearchOverlayOutput.none,
    };
  }

  List<CommandSearchResult> _resultsForQuery(
    String query, {
    required CommandSearchHistoryScope scope,
  }) {
    return _index.search(
      _parser.parse(query),
      currentCwd: _currentCwd,
      scope: scope,
      sessionId: _currentSessionId,
    );
  }
}

extension on CommandSearchOverlayState {
  CommandSearchOverlayState copyWith({
    bool? isOpen,
    String? query,
    List<CommandSearchResult>? results,
    int? selectedIndex,
    CommandSearchHistoryScope? scope,
  }) {
    return CommandSearchOverlayState(
      isOpen: isOpen ?? this.isOpen,
      query: query ?? this.query,
      results: results ?? this.results,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      scope: scope ?? this.scope,
    );
  }
}
