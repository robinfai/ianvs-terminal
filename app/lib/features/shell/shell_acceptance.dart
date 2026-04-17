import 'dart:convert';

class ShellAcceptanceSnapshot {
  const ShellAcceptanceSnapshot({
    required this.commandMenuOpen,
    required this.defaultsOpen,
    required this.profilesOpen,
    required this.visibleOverlay,
    required this.terminalHasVisibleContent,
    required this.terminalPreview,
    required this.activeTabCount,
    required this.activeSessionId,
    required this.themeMode,
    required this.snapshotVersion,
  });

  static const empty = ShellAcceptanceSnapshot(
    commandMenuOpen: false,
    defaultsOpen: false,
    profilesOpen: false,
    visibleOverlay: 'none',
    terminalHasVisibleContent: false,
    terminalPreview: null,
    activeTabCount: 0,
    activeSessionId: null,
    themeMode: 'system',
    snapshotVersion: 0,
  );

  final bool commandMenuOpen;
  final bool defaultsOpen;
  final bool profilesOpen;
  final String visibleOverlay;
  final bool terminalHasVisibleContent;
  final String? terminalPreview;
  final int activeTabCount;
  final String? activeSessionId;
  final String themeMode;
  final int snapshotVersion;

  ShellAcceptanceSnapshot copyWith({
    bool? commandMenuOpen,
    bool? defaultsOpen,
    bool? profilesOpen,
    String? visibleOverlay,
    bool? terminalHasVisibleContent,
    Object? terminalPreview = _noChange,
    int? activeTabCount,
    Object? activeSessionId = _noChange,
    String? themeMode,
    int? snapshotVersion,
  }) {
    return ShellAcceptanceSnapshot(
      commandMenuOpen: commandMenuOpen ?? this.commandMenuOpen,
      defaultsOpen: defaultsOpen ?? this.defaultsOpen,
      profilesOpen: profilesOpen ?? this.profilesOpen,
      visibleOverlay: visibleOverlay ?? this.visibleOverlay,
      terminalHasVisibleContent:
          terminalHasVisibleContent ?? this.terminalHasVisibleContent,
      terminalPreview: identical(terminalPreview, _noChange)
          ? this.terminalPreview
          : terminalPreview as String?,
      activeTabCount: activeTabCount ?? this.activeTabCount,
      activeSessionId: identical(activeSessionId, _noChange)
          ? this.activeSessionId
          : activeSessionId as String?,
      themeMode: themeMode ?? this.themeMode,
      snapshotVersion: snapshotVersion ?? this.snapshotVersion,
    );
  }

  bool samePayloadAs(ShellAcceptanceSnapshot other) {
    return commandMenuOpen == other.commandMenuOpen &&
        defaultsOpen == other.defaultsOpen &&
        profilesOpen == other.profilesOpen &&
        visibleOverlay == other.visibleOverlay &&
        terminalHasVisibleContent == other.terminalHasVisibleContent &&
        terminalPreview == other.terminalPreview &&
        activeTabCount == other.activeTabCount &&
        activeSessionId == other.activeSessionId &&
        themeMode == other.themeMode;
  }

  Map<String, Object?> toJson() {
    return {
      'commandMenuOpen': commandMenuOpen,
      'defaultsOpen': defaultsOpen,
      'profilesOpen': profilesOpen,
      'visibleOverlay': visibleOverlay,
      'terminalHasVisibleContent': terminalHasVisibleContent,
      'terminalPreview': terminalPreview,
      'activeTabCount': activeTabCount,
      'activeSessionId': activeSessionId,
      'themeMode': themeMode,
      'snapshotVersion': snapshotVersion,
    };
  }

  String encode() => jsonEncode(toJson());
}

class ShellAcceptanceProbe {
  ShellAcceptanceSnapshot _current = ShellAcceptanceSnapshot.empty;

  ShellAcceptanceSnapshot get current => _current;

  void update(ShellAcceptanceSnapshot snapshot) {
    if (_current.samePayloadAs(snapshot)) {
      return;
    }
    _current = snapshot.copyWith(snapshotVersion: _current.snapshotVersion + 1);
  }

  void mergeTerminalContent({
    required bool terminalHasVisibleContent,
    required String? terminalPreview,
  }) {
    update(
      _current.copyWith(
        terminalHasVisibleContent: terminalHasVisibleContent,
        terminalPreview: terminalPreview,
      ),
    );
  }

  Future<String> handleDriverRequest(String? message) async {
    switch (message) {
      case null:
      case '':
      case 'shell.acceptance':
        return _current.encode();
      default:
        return jsonEncode({
          'error': 'unknown_request',
          'message': message,
          'snapshot': _current.toJson(),
        });
    }
  }
}

final shellAcceptanceProbe = ShellAcceptanceProbe();

const Object _noChange = Object();
