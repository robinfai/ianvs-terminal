import 'package:flutter/foundation.dart';

import 'saved_commands.dart';
import 'terminal_blocks.dart';

enum CommandHistoryEntrySource {
  saved,
  history;

  String get label {
    return switch (this) {
      CommandHistoryEntrySource.saved => 'Saved',
      CommandHistoryEntrySource.history => 'History',
    };
  }
}

class CommandHistoryEntry {
  const CommandHistoryEntry({
    required this.id,
    required this.blockId,
    required this.commandText,
    required this.source,
    required this.status,
    required this.outputPreview,
    required this.scrollbackOffset,
  });

  final String id;
  final String blockId;
  final String commandText;
  final CommandHistoryEntrySource source;
  final TerminalBlockStatus status;
  final String outputPreview;
  final int scrollbackOffset;
}

class CommandHistoryController extends ChangeNotifier {
  CommandHistoryController({
    required TerminalBlocksController blocksController,
    required Future<void> Function(String command) reinputCommand,
    SavedCommandsController? savedCommandsController,
  }) : _blocksController = blocksController,
       _reinputCommand = reinputCommand,
       _savedCommandsController = savedCommandsController {
    _blocksController.addListener(_handleBlocksChanged);
    _savedCommandsController?.addListener(_handleSavedCommandsChanged);
    _rebuildEntries();
  }

  final TerminalBlocksController _blocksController;
  final Future<void> Function(String command) _reinputCommand;
  final SavedCommandsController? _savedCommandsController;

  final List<CommandHistoryEntry> _entries = <CommandHistoryEntry>[];
  List<CommandHistoryEntry> _matches = <CommandHistoryEntry>[];
  String _query = '';
  int _activeIndex = -1;
  bool _isOpen = false;

  bool get isOpen => _isOpen;
  String get query => _query;
  List<CommandHistoryEntry> get entries => List.unmodifiable(_entries);
  List<CommandHistoryEntry> get matches => List.unmodifiable(_matches);
  int get activeIndex => _activeIndex;
  int get displayIndex => _matches.isEmpty ? 0 : _activeIndex + 1;
  bool get canSaveActiveEntry =>
      activeEntry?.source == CommandHistoryEntrySource.history &&
      _savedCommandsController != null;
  bool get canRemoveActiveEntry =>
      activeEntry?.source == CommandHistoryEntrySource.saved &&
      _savedCommandsController != null;

  CommandHistoryEntry? get activeEntry {
    if (_activeIndex < 0 || _activeIndex >= _matches.length) {
      return null;
    }
    return _matches[_activeIndex];
  }

  void open() {
    if (_isOpen) {
      return;
    }
    _isOpen = true;
    notifyListeners();
  }

  void close() {
    if (!_isOpen) {
      return;
    }
    _isOpen = false;
    notifyListeners();
  }

  void reset() {
    final changed = _isOpen || _query.isNotEmpty || _activeIndex != -1;
    _isOpen = false;
    _query = '';
    _rebuildEntries(notify: false);
    if (changed || _entries.isNotEmpty || _matches.isNotEmpty) {
      notifyListeners();
    }
  }

  void updateQuery(String value) {
    if (value == _query) {
      return;
    }
    _query = value;
    _applyFilter(resetActive: true);
    notifyListeners();
  }

  void goToNext() {
    if (_matches.isEmpty) {
      return;
    }
    _activeIndex = (_activeIndex + 1) % _matches.length;
    notifyListeners();
  }

  void goToPrevious() {
    if (_matches.isEmpty) {
      return;
    }
    _activeIndex = _activeIndex <= 0 ? _matches.length - 1 : _activeIndex - 1;
    notifyListeners();
  }

  void selectEntryAt(int index) {
    if (index < 0 || index >= _matches.length) {
      return;
    }
    _activeIndex = index;
    notifyListeners();
  }

  Future<void> chooseActiveEntry() async {
    final entry = activeEntry;
    if (entry == null) {
      return;
    }
    await _reinputCommand(entry.commandText);
    close();
  }

  Future<void> chooseEntryAt(int index) async {
    if (index < 0 || index >= _matches.length) {
      return;
    }
    selectEntryAt(index);
    await chooseActiveEntry();
  }

  bool saveCommand(String command) {
    return _savedCommandsController?.addCommand(command) ?? false;
  }

  bool saveActiveEntry() {
    final entry = activeEntry;
    if (entry == null || entry.source != CommandHistoryEntrySource.history) {
      return false;
    }
    return saveCommand(entry.commandText);
  }

  bool saveEntry(CommandHistoryEntry entry) {
    if (entry.source != CommandHistoryEntrySource.history) {
      return false;
    }
    return saveCommand(entry.commandText);
  }

  bool removeActiveEntry() {
    final entry = activeEntry;
    if (entry == null || entry.source != CommandHistoryEntrySource.saved) {
      return false;
    }
    return removeEntry(entry);
  }

  bool removeEntry(CommandHistoryEntry entry) {
    if (entry.source != CommandHistoryEntrySource.saved) {
      return false;
    }
    return _savedCommandsController?.removeCommand(entry.commandText) ?? false;
  }

  void _handleBlocksChanged() {
    _rebuildEntries(notify: false);
    _applyFilter(resetActive: true);
    notifyListeners();
  }

  void _handleSavedCommandsChanged() {
    _rebuildEntries(notify: false);
    _applyFilter(resetActive: true);
    notifyListeners();
  }

  void _rebuildEntries({bool notify = true}) {
    final savedEntries = _entriesFromSavedCommands(
      _savedCommandsController?.commands ?? const <String>[],
    );
    final savedCommandSet = savedEntries
        .map((entry) => entry.commandText)
        .toSet();
    _entries
      ..clear()
      ..addAll(savedEntries)
      ..addAll(
        _entriesFromBlocks(
          _blocksController.blocks,
          excludedCommands: savedCommandSet,
        ),
      );
    _applyFilter(resetActive: true);
    if (notify) {
      notifyListeners();
    }
  }

  void _applyFilter({String? preferredBlockId, bool resetActive = false}) {
    final normalizedQuery = _query.trim().toLowerCase();
    _matches = _entries
        .where(
          (entry) =>
              normalizedQuery.isEmpty ||
              entry.commandText.toLowerCase().contains(normalizedQuery),
        )
        .toList(growable: false);

    if (_matches.isEmpty) {
      _activeIndex = -1;
      return;
    }

    if (!resetActive && preferredBlockId != null) {
      final preferredIndex = _matches.indexWhere(
        (entry) => entry.blockId == preferredBlockId,
      );
      if (preferredIndex >= 0) {
        _activeIndex = preferredIndex;
        return;
      }
    }

    if (_activeIndex < 0 || _activeIndex >= _matches.length) {
      _activeIndex = 0;
    }
  }

  @override
  void dispose() {
    _blocksController.removeListener(_handleBlocksChanged);
    _savedCommandsController?.removeListener(_handleSavedCommandsChanged);
    super.dispose();
  }
}

List<CommandHistoryEntry> _entriesFromSavedCommands(List<String> commands) {
  final entries = <CommandHistoryEntry>[];
  for (var index = 0; index < commands.length; index += 1) {
    final command = commands[index].trim();
    if (command.isEmpty) {
      continue;
    }
    entries.add(
      CommandHistoryEntry(
        id: 'saved-$index',
        blockId: 'saved-$index',
        commandText: command,
        source: CommandHistoryEntrySource.saved,
        status: TerminalBlockStatus.unknown,
        outputPreview: '',
        scrollbackOffset: 0,
      ),
    );
  }
  return entries;
}

List<CommandHistoryEntry> _entriesFromBlocks(
  List<TerminalBlock> blocks, {
  Set<String> excludedCommands = const <String>{},
}) {
  final seenCommands = <String>{};
  final entries = <CommandHistoryEntry>[];
  for (final block in blocks.reversed) {
    final command = block.commandText.trimRight();
    if (block.status == TerminalBlockStatus.running || command.trim().isEmpty) {
      continue;
    }
    if (excludedCommands.contains(command)) {
      continue;
    }
    if (!seenCommands.add(command)) {
      continue;
    }
    entries.add(
      CommandHistoryEntry(
        id: block.id,
        blockId: block.id,
        commandText: command,
        source: CommandHistoryEntrySource.history,
        status: block.status,
        outputPreview: _firstOutputLine(block.outputText),
        scrollbackOffset: block.scrollbackOffset,
      ),
    );
  }
  return entries;
}

String _firstOutputLine(String text) {
  final trimmed = text.trimRight();
  if (trimmed.isEmpty) {
    return '';
  }
  return _singleLinePreview(trimmed.split('\n').first);
}

String _singleLinePreview(String text) {
  final preview = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (preview.length <= 120) {
    return preview;
  }
  return '${preview.substring(0, 119)}...';
}
