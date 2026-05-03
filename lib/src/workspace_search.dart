import 'package:flutter/foundation.dart';

import 'local_shell_session_controller.dart';
import 'terminal_tabs_controller.dart';

class WorkspaceSearchResult {
  const WorkspaceSearchResult({
    required this.id,
    required this.tabIndex,
    required this.tabId,
    required this.tabTitle,
    required this.paneId,
    required this.paneOrdinal,
    required this.cwd,
    required this.status,
    required this.exitCode,
    required this.isActiveTab,
    required this.isActivePane,
  });

  final String id;
  final int tabIndex;
  final int tabId;
  final String tabTitle;
  final int paneId;
  final int paneOrdinal;
  final String cwd;
  final LocalShellStatus status;
  final int? exitCode;
  final bool isActiveTab;
  final bool isActivePane;

  String get paneLabel => 'Pane ${paneOrdinal + 1} · #$paneId';

  String get statusLabel => workspaceSearchStatusLabel(status, exitCode);

  List<String> get searchFields => <String>[
    tabTitle,
    cwd,
    paneLabel,
    'pane $paneId',
    statusLabel,
  ];
}

class WorkspaceSearchController extends ChangeNotifier {
  WorkspaceSearchController({
    required List<WorkspaceSearchResult> Function() entriesBuilder,
    required void Function(WorkspaceSearchResult result) jumpToResult,
    Listenable? dependency,
  }) : _entriesBuilder = entriesBuilder,
       _jumpToResult = jumpToResult,
       _dependency = dependency {
    _dependency?.addListener(_handleDependencyChanged);
    _rebuildEntries(notify: false);
  }

  final List<WorkspaceSearchResult> Function() _entriesBuilder;
  final void Function(WorkspaceSearchResult result) _jumpToResult;
  final Listenable? _dependency;

  final List<WorkspaceSearchResult> _entries = <WorkspaceSearchResult>[];
  List<WorkspaceSearchResult> _matches = <WorkspaceSearchResult>[];
  String _query = '';
  int _activeIndex = -1;
  bool _isOpen = false;

  bool get isOpen => _isOpen;
  String get query => _query;
  List<WorkspaceSearchResult> get entries => List.unmodifiable(_entries);
  List<WorkspaceSearchResult> get matches => List.unmodifiable(_matches);
  int get activeIndex => _activeIndex;
  int get displayIndex => _matches.isEmpty ? 0 : _activeIndex + 1;

  WorkspaceSearchResult? get activeResult {
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
    _applyFilter(resetActive: true);
    notifyListeners();
  }

  void close() {
    final changed = _isOpen || _query.isNotEmpty || _activeIndex != -1;
    _isOpen = false;
    _query = '';
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

  void selectResultAt(int index) {
    if (index < 0 || index >= _matches.length) {
      return;
    }
    _activeIndex = index;
    notifyListeners();
  }

  void chooseActiveResult() {
    final result = activeResult;
    if (result == null) {
      return;
    }
    _jumpToResult(result);
    close();
  }

  void _handleDependencyChanged() {
    final preferredId = activeResult?.id;
    _rebuildEntries(notify: false);
    _applyFilter(preferredId: preferredId, resetActive: false);
    notifyListeners();
  }

  void _rebuildEntries({bool notify = true}) {
    _entries
      ..clear()
      ..addAll(_entriesBuilder());
    _applyFilter(resetActive: true);
    if (notify) {
      notifyListeners();
    }
  }

  void _applyFilter({String? preferredId, bool resetActive = false}) {
    _matches = filterWorkspaceSearchResults(_entries, _query);

    if (_matches.isEmpty) {
      _activeIndex = -1;
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
    _dependency?.removeListener(_handleDependencyChanged);
    super.dispose();
  }
}

List<WorkspaceSearchResult> buildWorkspaceSearchResults(
  TerminalTabsController tabsController,
) {
  final results = <WorkspaceSearchResult>[];
  for (var tabIndex = 0; tabIndex < tabsController.tabs.length; tabIndex += 1) {
    final tab = tabsController.tabs[tabIndex];
    for (var paneIndex = 0; paneIndex < tab.panes.length; paneIndex += 1) {
      final pane = tab.panes[paneIndex];
      final shellController = pane.shellController;
      results.add(
        WorkspaceSearchResult(
          id: 'tab-${tab.id}-pane-${pane.id}',
          tabIndex: tabIndex,
          tabId: tab.id,
          tabTitle: tab.title,
          paneId: pane.id,
          paneOrdinal: paneIndex,
          cwd: shellController.completionController.cwd,
          status: shellController.status,
          exitCode: shellController.exitCode,
          isActiveTab: tabIndex == tabsController.activeIndex,
          isActivePane: pane.id == tabsController.activePane.id,
        ),
      );
    }
  }
  return results;
}

List<WorkspaceSearchResult> filterWorkspaceSearchResults(
  List<WorkspaceSearchResult> results,
  String query,
) {
  final normalizedQuery = query.trim().toLowerCase();
  final scored = <_WorkspaceSearchScoredResult>[];

  for (final result in results) {
    final rank = normalizedQuery.isEmpty
        ? _WorkspaceSearchMatchRank.unfiltered
        : _bestMatchRank(result, normalizedQuery);
    if (rank == null) {
      continue;
    }
    scored.add(_WorkspaceSearchScoredResult(result: result, rank: rank));
  }

  scored.sort((left, right) {
    final rankComparison = left.rank.index.compareTo(right.rank.index);
    if (rankComparison != 0) {
      return rankComparison;
    }
    final activeComparison = _activeWeight(
      left.result,
    ).compareTo(_activeWeight(right.result));
    if (activeComparison != 0) {
      return activeComparison;
    }
    final tabComparison = left.result.tabIndex.compareTo(right.result.tabIndex);
    if (tabComparison != 0) {
      return tabComparison;
    }
    return left.result.paneOrdinal.compareTo(right.result.paneOrdinal);
  });

  return scored.map((entry) => entry.result).toList(growable: false);
}

String workspaceSearchStatusLabel(LocalShellStatus status, int? exitCode) {
  return switch (status) {
    LocalShellStatus.starting => 'Starting',
    LocalShellStatus.running => 'Running',
    LocalShellStatus.failed => 'Failed',
    LocalShellStatus.exited => exitCode == null ? 'Exited' : 'Exited $exitCode',
  };
}

_WorkspaceSearchMatchRank? _bestMatchRank(
  WorkspaceSearchResult result,
  String normalizedQuery,
) {
  _WorkspaceSearchMatchRank? bestRank;
  for (final field in result.searchFields) {
    final normalizedField = field.trim().toLowerCase();
    if (normalizedField.isEmpty) {
      continue;
    }
    final rank = switch (normalizedField) {
      final value when value == normalizedQuery =>
        _WorkspaceSearchMatchRank.exact,
      final value when value.startsWith(normalizedQuery) =>
        _WorkspaceSearchMatchRank.prefix,
      final value when value.contains(normalizedQuery) =>
        _WorkspaceSearchMatchRank.substring,
      _ => null,
    };
    if (rank == null) {
      continue;
    }
    if (bestRank == null || rank.index < bestRank.index) {
      bestRank = rank;
    }
  }
  return bestRank;
}

int _activeWeight(WorkspaceSearchResult result) {
  if (result.isActivePane) {
    return 0;
  }
  if (result.isActiveTab) {
    return 1;
  }
  return 2;
}

enum _WorkspaceSearchMatchRank { exact, prefix, substring, unfiltered }

class _WorkspaceSearchScoredResult {
  const _WorkspaceSearchScoredResult({
    required this.result,
    required this.rank,
  });

  final WorkspaceSearchResult result;
  final _WorkspaceSearchMatchRank rank;
}
