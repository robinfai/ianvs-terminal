import 'package:flutter/foundation.dart';

import 'local_shell_session_controller.dart';
import 'saved_commands.dart';
import 'session_metadata.dart';
import 'terminal_blocks.dart';
import 'terminal_windows.dart';

enum CommandPaletteEntrySource { saved, history, session }

extension CommandPaletteEntrySourceLabel on CommandPaletteEntrySource {
  String get label {
    return switch (this) {
      CommandPaletteEntrySource.saved => 'Saved',
      CommandPaletteEntrySource.history => 'History',
      CommandPaletteEntrySource.session => 'Session',
    };
  }
}

enum CommandPaletteFilter { all, commands, saved, history, session, ssh }

extension CommandPaletteFilterLabel on CommandPaletteFilter {
  String get label {
    return switch (this) {
      CommandPaletteFilter.all => 'All',
      CommandPaletteFilter.commands => 'Commands',
      CommandPaletteFilter.saved => 'Saved',
      CommandPaletteFilter.history => 'History',
      CommandPaletteFilter.session => 'Session',
      CommandPaletteFilter.ssh => 'SSH',
    };
  }
}

class CommandPaletteEntry {
  const CommandPaletteEntry({
    required this.id,
    required this.source,
    required this.title,
    required this.searchFields,
    this.commandText = '',
    this.outputPreview = '',
    this.status = LocalShellStatus.running,
    this.exitCode,
    this.blockStatus,
    this.recordedAt = '',
    this.windowIndex = 0,
    this.windowId = 0,
    this.windowLabel = '',
    this.tabIndex = 0,
    this.tabId = 0,
    this.tabTitle = '',
    this.paneId = 0,
    this.paneOrdinal = 0,
    this.cwd = '',
    this.lastCommand = '',
    this.metadata = const TerminalSessionMetadata(),
    this.isActiveWindow = false,
    this.isActiveTab = false,
    this.isActivePane = false,
    this.savedEntry = const SavedCommandEntry(command: ''),
  });

  final String id;
  final CommandPaletteEntrySource source;
  final String title;
  final List<String> searchFields;
  final String commandText;
  final String outputPreview;
  final LocalShellStatus status;
  final int? exitCode;
  final TerminalBlockStatus? blockStatus;
  final String recordedAt;
  final int windowIndex;
  final int windowId;
  final String windowLabel;
  final int tabIndex;
  final int tabId;
  final String tabTitle;
  final int paneId;
  final int paneOrdinal;
  final String cwd;
  final String lastCommand;
  final TerminalSessionMetadata metadata;
  final bool isActiveWindow;
  final bool isActiveTab;
  final bool isActivePane;
  final SavedCommandEntry savedEntry;

  bool get isCommandEntry => source != CommandPaletteEntrySource.session;
  bool get isSessionEntry => source == CommandPaletteEntrySource.session;
  bool get isSshSession => isSessionEntry && metadata.isSsh;

  String get paneLabel => 'Pane ${paneOrdinal + 1} · #$paneId';

  String get statusLabel {
    return switch (status) {
      LocalShellStatus.starting => 'Starting',
      LocalShellStatus.running => 'Running',
      LocalShellStatus.exited =>
        exitCode == null ? 'Exited' : 'Exited $exitCode',
      LocalShellStatus.failed => 'Failed',
    };
  }
}

class CommandPaletteController extends ChangeNotifier {
  CommandPaletteController({
    required TerminalWindowsController windowsController,
    required SavedCommandsController savedCommandsController,
  }) : _windowsController = windowsController,
       _savedCommandsController = savedCommandsController {
    _windowsController.addListener(_handleDependencyChanged);
    _savedCommandsController.addListener(_handleDependencyChanged);
    _rebuildEntries(notify: false);
  }

  final TerminalWindowsController _windowsController;
  final SavedCommandsController _savedCommandsController;

  final List<CommandPaletteEntry> _entries = <CommandPaletteEntry>[];
  List<CommandPaletteEntry> _matches = <CommandPaletteEntry>[];
  String _query = '';
  int _activeIndex = -1;
  bool _isOpen = false;
  CommandPaletteFilter _baseFilter = CommandPaletteFilter.all;

  bool get isOpen => _isOpen;
  String get query => _query;
  CommandPaletteFilter get baseFilter => _baseFilter;
  List<CommandPaletteEntry> get entries => List.unmodifiable(_entries);
  List<CommandPaletteEntry> get matches => List.unmodifiable(_matches);
  int get activeIndex => _activeIndex;
  int get displayIndex => _matches.isEmpty ? 0 : _activeIndex + 1;
  bool get canSaveActiveEntry =>
      activeEntry?.source == CommandPaletteEntrySource.history;
  bool get canRemoveActiveEntry =>
      activeEntry?.source == CommandPaletteEntrySource.saved;

  CommandPaletteEntry? get activeEntry {
    if (_activeIndex < 0 || _activeIndex >= _matches.length) {
      return null;
    }
    return _matches[_activeIndex];
  }

  CommandPaletteFilter get effectiveFilter {
    final override = _prefixedFilter(_query);
    return override ?? _baseFilter;
  }

  void open({CommandPaletteFilter filter = CommandPaletteFilter.all}) {
    _baseFilter = filter;
    if (_isOpen) {
      _applyFilter(resetActive: true);
      notifyListeners();
      return;
    }
    _isOpen = true;
    _applyFilter(resetActive: true);
    notifyListeners();
  }

  void close() {
    final changed = _isOpen || _query.isNotEmpty || _activeIndex != -1;
    _isOpen = false;
    _query = '';
    _baseFilter = CommandPaletteFilter.all;
    _applyFilter(resetActive: true);
    if (changed) {
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

  bool saveActiveEntry() {
    final entry = activeEntry;
    if (entry == null || entry.source != CommandPaletteEntrySource.history) {
      return false;
    }
    return saveEntry(entry);
  }

  bool saveEntry(CommandPaletteEntry entry) {
    if (entry.source != CommandPaletteEntrySource.history) {
      return false;
    }
    return _savedCommandsController.addCommand(entry.commandText);
  }

  bool removeActiveEntry() {
    final entry = activeEntry;
    if (entry == null || entry.source != CommandPaletteEntrySource.saved) {
      return false;
    }
    return removeEntry(entry);
  }

  bool removeEntry(CommandPaletteEntry entry) {
    if (entry.source != CommandPaletteEntrySource.saved) {
      return false;
    }
    return _savedCommandsController.removeCommand(entry.commandText);
  }

  void _handleDependencyChanged() {
    final preferredId = activeEntry?.id;
    _rebuildEntries(notify: false);
    _applyFilter(preferredId: preferredId, resetActive: false);
    notifyListeners();
  }

  void _rebuildEntries({bool notify = true}) {
    _entries
      ..clear()
      ..addAll(
        buildCommandPaletteEntries(
          windowsController: _windowsController,
          savedCommandsController: _savedCommandsController,
        ),
      );
    _applyFilter(resetActive: true);
    if (notify) {
      notifyListeners();
    }
  }

  void _applyFilter({String? preferredId, bool resetActive = false}) {
    final filter = effectiveFilter;
    final normalizedQuery = _normalizedSearchQuery(_query);
    final scored = <_ScoredPaletteEntry>[];

    for (final entry in _entries) {
      if (!_matchesFilter(entry, filter)) {
        continue;
      }
      final rank = normalizedQuery.isEmpty
          ? _PaletteMatchRank.unfiltered
          : _bestMatchRank(entry, normalizedQuery);
      if (rank == null) {
        continue;
      }
      scored.add(_ScoredPaletteEntry(entry: entry, rank: rank));
    }

    scored.sort((left, right) {
      final rankComparison = left.rank.index.compareTo(right.rank.index);
      if (rankComparison != 0) {
        return rankComparison;
      }
      final sourceComparison = _sourceWeight(
        left.entry,
        filter,
      ).compareTo(_sourceWeight(right.entry, filter));
      if (sourceComparison != 0) {
        return sourceComparison;
      }
      final activeComparison = _activeWeight(
        left.entry,
      ).compareTo(_activeWeight(right.entry));
      if (activeComparison != 0) {
        return activeComparison;
      }
      final recordedComparison = _recordedWeight(
        right.entry,
      ).compareTo(_recordedWeight(left.entry));
      if (recordedComparison != 0) {
        return recordedComparison;
      }
      final windowComparison = left.entry.windowIndex.compareTo(
        right.entry.windowIndex,
      );
      if (windowComparison != 0) {
        return windowComparison;
      }
      final tabComparison = left.entry.tabIndex.compareTo(right.entry.tabIndex);
      if (tabComparison != 0) {
        return tabComparison;
      }
      return left.entry.paneOrdinal.compareTo(right.entry.paneOrdinal);
    });

    _matches = scored.map((entry) => entry.entry).toList(growable: false);

    if (_matches.isEmpty) {
      _activeIndex = -1;
      return;
    }
    if (resetActive) {
      _activeIndex = 0;
      return;
    }
    if (!resetActive && preferredId != null) {
      final preferredIndex = _matches.indexWhere(
        (entry) => entry.id == preferredId,
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
    _windowsController.removeListener(_handleDependencyChanged);
    _savedCommandsController.removeListener(_handleDependencyChanged);
    super.dispose();
  }
}

List<CommandPaletteEntry> buildCommandPaletteEntries({
  required TerminalWindowsController windowsController,
  required SavedCommandsController savedCommandsController,
}) {
  final entries = <CommandPaletteEntry>[];
  final savedCommands = savedCommandsController.entries;
  final savedCommandSet = savedCommands.map((entry) => entry.command).toSet();

  for (var savedIndex = 0; savedIndex < savedCommands.length; savedIndex += 1) {
    final saved = savedCommands[savedIndex];
    entries.add(
      CommandPaletteEntry(
        id: 'saved-$savedIndex-${saved.command}',
        source: CommandPaletteEntrySource.saved,
        title: saved.title.isEmpty ? saved.command : saved.title,
        commandText: saved.command,
        recordedAt: saved.createdAt,
        savedEntry: saved,
        searchFields: <String>[
          saved.command,
          saved.title,
          saved.cwdHint,
          saved.targetKind,
          ...saved.tags,
        ],
      ),
    );
  }

  final historyBlocks = <_PaletteBlockContext>[];
  for (
    var windowIndex = 0;
    windowIndex < windowsController.windows.length;
    windowIndex += 1
  ) {
    final window = windowsController.windows[windowIndex];
    final tabsController = window.tabsController;
    for (
      var tabIndex = 0;
      tabIndex < tabsController.tabs.length;
      tabIndex += 1
    ) {
      final tab = tabsController.tabs[tabIndex];
      for (var paneIndex = 0; paneIndex < tab.panes.length; paneIndex += 1) {
        final pane = tab.panes[paneIndex];
        for (final block in pane.shellController.blocksController.blocks) {
          historyBlocks.add(
            _PaletteBlockContext(
              windowIndex: windowIndex,
              windowId: window.id,
              windowLabel: window.title,
              tabIndex: tabIndex,
              tabId: tab.id,
              tabTitle: tab.title,
              paneId: pane.id,
              paneOrdinal: paneIndex,
              metadata: pane.shellController.sessionMetadata,
              cwd: pane.shellController.completionController.cwd,
              isActiveWindow:
                  windowIndex == windowsController.activeWindowIndex,
              isActiveTab:
                  windowIndex == windowsController.activeWindowIndex &&
                  tabIndex == tabsController.activeIndex,
              isActivePane:
                  windowIndex == windowsController.activeWindowIndex &&
                  pane.id == tabsController.activePane.id,
              block: block,
            ),
          );
        }
      }
    }
  }
  historyBlocks.sort(
    (left, right) =>
        _blockContextWeight(right).compareTo(_blockContextWeight(left)),
  );
  final seenHistoryCommands = <String>{};
  for (final context in historyBlocks) {
    final command = context.block.commandText.trim();
    if (context.block.status == TerminalBlockStatus.running ||
        command.isEmpty ||
        savedCommandSet.contains(command) ||
        !seenHistoryCommands.add(command)) {
      continue;
    }
    entries.add(
      CommandPaletteEntry(
        id: 'history-${context.block.id}',
        source: CommandPaletteEntrySource.history,
        title: command,
        commandText: command,
        outputPreview: _firstOutputLine(context.block.outputText),
        blockStatus: context.block.status,
        recordedAt: context.block.recordedAt ?? '',
        windowIndex: context.windowIndex,
        windowId: context.windowId,
        windowLabel: context.windowLabel,
        tabIndex: context.tabIndex,
        tabId: context.tabId,
        tabTitle: context.tabTitle,
        paneId: context.paneId,
        paneOrdinal: context.paneOrdinal,
        cwd: context.cwd,
        metadata: context.metadata,
        isActiveWindow: context.isActiveWindow,
        isActiveTab: context.isActiveTab,
        isActivePane: context.isActivePane,
        searchFields: <String>[
          command,
          context.windowLabel,
          context.tabTitle,
          context.cwd,
          context.metadata.host,
          context.metadata.account,
          context.metadata.environment,
          context.metadata.project,
          _firstOutputLine(context.block.outputText),
        ],
      ),
    );
  }

  for (
    var windowIndex = 0;
    windowIndex < windowsController.windows.length;
    windowIndex += 1
  ) {
    final window = windowsController.windows[windowIndex];
    final tabsController = window.tabsController;
    for (
      var tabIndex = 0;
      tabIndex < tabsController.tabs.length;
      tabIndex += 1
    ) {
      final tab = tabsController.tabs[tabIndex];
      for (var paneIndex = 0; paneIndex < tab.panes.length; paneIndex += 1) {
        final pane = tab.panes[paneIndex];
        final shell = pane.shellController;
        final latestCommand = _latestCommand(shell.blocksController.blocks);
        final latestBlock = _latestCompletedBlock(
          shell.blocksController.blocks,
        );
        entries.add(
          CommandPaletteEntry(
            id: 'session-window-${window.id}-pane-${pane.id}',
            source: CommandPaletteEntrySource.session,
            title: tab.title,
            status: shell.status,
            exitCode: shell.exitCode,
            blockStatus: latestBlock?.status,
            recordedAt: latestBlock?.recordedAt ?? '',
            windowIndex: windowIndex,
            windowId: window.id,
            windowLabel: window.title,
            tabIndex: tabIndex,
            tabId: tab.id,
            tabTitle: tab.title,
            paneId: pane.id,
            paneOrdinal: paneIndex,
            cwd: shell.completionController.cwd,
            lastCommand: latestCommand,
            metadata: shell.sessionMetadata,
            isActiveWindow: windowIndex == windowsController.activeWindowIndex,
            isActiveTab:
                windowIndex == windowsController.activeWindowIndex &&
                tabIndex == tabsController.activeIndex,
            isActivePane:
                windowIndex == windowsController.activeWindowIndex &&
                pane.id == tabsController.activePane.id,
            searchFields: <String>[
              window.title,
              tab.title,
              'pane ${pane.id}',
              'pane ${paneIndex + 1}',
              shell.completionController.cwd,
              latestCommand,
              shell.sessionMetadata.host,
              shell.sessionMetadata.account,
              shell.sessionMetadata.environment,
              shell.sessionMetadata.project,
              shell.sessionMetadata.kind.label,
            ],
          ),
        );
      }
    }
  }

  return entries;
}

bool _matchesFilter(CommandPaletteEntry entry, CommandPaletteFilter filter) {
  return switch (filter) {
    CommandPaletteFilter.all => true,
    CommandPaletteFilter.commands => entry.isCommandEntry,
    CommandPaletteFilter.saved =>
      entry.source == CommandPaletteEntrySource.saved,
    CommandPaletteFilter.history =>
      entry.source == CommandPaletteEntrySource.history,
    CommandPaletteFilter.session => entry.isSessionEntry,
    CommandPaletteFilter.ssh => entry.isSshSession,
  };
}

String _normalizedSearchQuery(String query) {
  final trimmed = query.trim();
  final separatorIndex = trimmed.indexOf(':');
  if (separatorIndex <= 0) {
    return trimmed.toLowerCase();
  }
  final prefix = trimmed.substring(0, separatorIndex).toLowerCase();
  if (_filterFromPrefix(prefix) == null) {
    return trimmed.toLowerCase();
  }
  return trimmed.substring(separatorIndex + 1).trim().toLowerCase();
}

CommandPaletteFilter? _prefixedFilter(String query) {
  final trimmed = query.trimLeft();
  final separatorIndex = trimmed.indexOf(':');
  if (separatorIndex <= 0) {
    return null;
  }
  return _filterFromPrefix(trimmed.substring(0, separatorIndex).toLowerCase());
}

CommandPaletteFilter? _filterFromPrefix(String prefix) {
  return switch (prefix) {
    'saved' => CommandPaletteFilter.saved,
    'history' => CommandPaletteFilter.history,
    'session' => CommandPaletteFilter.session,
    'ssh' => CommandPaletteFilter.ssh,
    _ => null,
  };
}

_PaletteMatchRank? _bestMatchRank(
  CommandPaletteEntry entry,
  String normalizedQuery,
) {
  _PaletteMatchRank? bestRank;
  for (final field in entry.searchFields) {
    final normalizedField = field.toLowerCase();
    final rank = normalizedField == normalizedQuery
        ? _PaletteMatchRank.exact
        : normalizedField.startsWith(normalizedQuery)
        ? _PaletteMatchRank.prefix
        : normalizedField.contains(normalizedQuery)
        ? _PaletteMatchRank.substring
        : null;
    if (rank == null) {
      continue;
    }
    if (bestRank == null || rank.index < bestRank.index) {
      bestRank = rank;
    }
  }
  return bestRank;
}

int _sourceWeight(CommandPaletteEntry entry, CommandPaletteFilter filter) {
  if (filter == CommandPaletteFilter.session ||
      filter == CommandPaletteFilter.ssh) {
    return 0;
  }
  return switch (entry.source) {
    CommandPaletteEntrySource.saved => 0,
    CommandPaletteEntrySource.history => 1,
    CommandPaletteEntrySource.session => 2,
  };
}

int _activeWeight(CommandPaletteEntry entry) {
  if (entry.isActivePane) {
    return 0;
  }
  if (entry.isActiveTab) {
    return 1;
  }
  if (entry.isActiveWindow) {
    return 2;
  }
  return 3;
}

int _recordedWeight(CommandPaletteEntry entry) {
  if (entry.recordedAt.isEmpty) {
    return 0;
  }
  return DateTime.tryParse(entry.recordedAt)?.millisecondsSinceEpoch ?? 0;
}

int _blockContextWeight(_PaletteBlockContext context) {
  final recorded = context.block.recordedAt;
  if (recorded?.isNotEmpty ?? false) {
    return DateTime.tryParse(recorded!)?.millisecondsSinceEpoch ?? 0;
  }
  var weight = 0;
  if (context.isActivePane) {
    weight += 1 << 28;
  } else if (context.isActiveTab) {
    weight += 1 << 27;
  } else if (context.isActiveWindow) {
    weight += 1 << 26;
  }
  weight += context.block.scrollbackOffset;
  return weight;
}

TerminalBlock? _latestCompletedBlock(List<TerminalBlock> blocks) {
  for (var index = blocks.length - 1; index >= 0; index -= 1) {
    final block = blocks[index];
    if (block.status == TerminalBlockStatus.running) {
      continue;
    }
    if (block.commandText.trim().isEmpty) {
      continue;
    }
    return block;
  }
  return null;
}

String _latestCommand(List<TerminalBlock> blocks) {
  for (var index = blocks.length - 1; index >= 0; index -= 1) {
    final command = blocks[index].commandText.trim();
    if (command.isNotEmpty) {
      return command;
    }
  }
  return '';
}

String _firstOutputLine(String output) {
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}

enum _PaletteMatchRank { exact, prefix, substring, unfiltered }

class _ScoredPaletteEntry {
  const _ScoredPaletteEntry({required this.entry, required this.rank});

  final CommandPaletteEntry entry;
  final _PaletteMatchRank rank;
}

class _PaletteBlockContext {
  const _PaletteBlockContext({
    required this.windowIndex,
    required this.windowId,
    required this.windowLabel,
    required this.tabIndex,
    required this.tabId,
    required this.tabTitle,
    required this.paneId,
    required this.paneOrdinal,
    required this.metadata,
    required this.cwd,
    required this.isActiveWindow,
    required this.isActiveTab,
    required this.isActivePane,
    required this.block,
  });

  final int windowIndex;
  final int windowId;
  final String windowLabel;
  final int tabIndex;
  final int tabId;
  final String tabTitle;
  final int paneId;
  final int paneOrdinal;
  final TerminalSessionMetadata metadata;
  final String cwd;
  final bool isActiveWindow;
  final bool isActiveTab;
  final bool isActivePane;
  final TerminalBlock block;
}
