import 'package:flutter/foundation.dart';

import '../preferences/app_preferences_models.dart';

enum BlockUnavailableReason {
  checking,
  llmRequired,
  unsupportedShell,
  remoteShell,
  nestedShell,
  terminalInput,
  fullScreen,
  richOutput,
  unattributedOutput,
  exited,
  readOnly,
}

enum TerminalModeNotice {
  blocksAvailable,
  normalFallback,
  blocksRestored,
  supportChecked,
}

@immutable
class TerminalModeState {
  const TerminalModeState({
    this.mode = TerminalViewMode.normal,
    this.unavailableReason = BlockUnavailableReason.checking,
    this.notice,
  });

  final TerminalViewMode mode;
  final BlockUnavailableReason? unavailableReason;
  final TerminalModeNotice? notice;
  bool get canUseBlocks => unavailableReason == null;

  @override
  bool operator ==(Object other) =>
      other is TerminalModeState &&
      other.mode == mode &&
      other.unavailableReason == unavailableReason &&
      other.notice == notice;

  @override
  int get hashCode => Object.hash(mode, unavailableReason, notice);
}

/// Per-session choice. A capability loss always returns input to the terminal;
/// authenticated shell transitions can restore Blocks after a fresh ready lease.
/// Other capability losses still require a manual choice.
class TerminalModeController extends ChangeNotifier {
  TerminalModeController({this.preferredMode = TerminalViewMode.normal});

  final TerminalViewMode preferredMode;
  TerminalModeState _state = const TerminalModeState();
  TerminalModeState get state => _state;
  bool _initialChoiceApplied = false;
  bool _manualChoice = false;
  TerminalViewMode? _selectedMode;

  /// Reconnect preserves the user's mode, not a temporary capability fallback.
  TerminalViewMode get chosenMode => _selectedMode ?? preferredMode;
  bool _offerRestore = false;
  bool _restoreAfterShellTransition = false;
  bool get awaitingShellResume => _restoreAfterShellTransition;
  bool _llmRequired = false;
  BlockUnavailableReason? _shellReason = BlockUnavailableReason.checking;

  /// Keep the product restriction separate from shell capability so polling or
  /// an explicit support check cannot accidentally re-enable Blocks.
  void setLlmRequired(bool required) {
    if (_llmRequired == required) return;
    _llmRequired = required;
    updateAvailability(_shellReason);
  }

  void updateAvailability(
    BlockUnavailableReason? shellReason, {
    bool rechecked = false,
    bool shellTransition = false,
  }) {
    _shellReason = shellReason;
    final reason = _llmRequired
        ? BlockUnavailableReason.llmRequired
        : shellReason;
    // An explicit check reports capability; it does not choose a display mode.
    if (rechecked) _initialChoiceApplied = true;
    var mode = _state.mode;
    var notice = _state.notice;
    if (reason != null) {
      if (!shellTransition || rechecked) {
        _restoreAfterShellTransition = false;
      } else if (mode == TerminalViewMode.blocks) {
        _restoreAfterShellTransition = true;
      }
      if (mode == TerminalViewMode.blocks) {
        mode = TerminalViewMode.normal;
        _offerRestore = true;
      }
      notice = _offerRestore ? TerminalModeNotice.normalFallback : null;
    } else {
      // Only the host can certify a matching context and a fresh ready lease.
      // A capability poll alone (including running/unknown) cannot restore input.
      if (shellTransition && _restoreAfterShellTransition && !rechecked) {
        mode = TerminalViewMode.blocks;
        _restoreAfterShellTransition = false;
        _offerRestore = false;
      }
      if (!_initialChoiceApplied) {
        mode = preferredMode;
        _initialChoiceApplied = true;
      }
      if (mode == TerminalViewMode.normal) {
        notice = _offerRestore
            ? TerminalModeNotice.blocksRestored
            : !_manualChoice
            ? TerminalModeNotice.blocksAvailable
            : null;
      } else {
        notice = null;
      }
    }
    if (rechecked) _restoreAfterShellTransition = false;
    if (rechecked ||
        (_state.notice == TerminalModeNotice.supportChecked &&
            _state.unavailableReason == reason)) {
      notice = TerminalModeNotice.supportChecked;
    }
    _publish(
      TerminalModeState(mode: mode, unavailableReason: reason, notice: notice),
    );
  }

  bool select(TerminalViewMode mode) {
    if (mode == TerminalViewMode.blocks && !_state.canUseBlocks) return false;
    _initialChoiceApplied = true;
    _manualChoice = true;
    _selectedMode = mode;
    _restoreAfterShellTransition = false;
    _offerRestore = false;
    _publish(
      TerminalModeState(
        mode: mode,
        unavailableReason: _state.unavailableReason,
      ),
    );
    return true;
  }

  void _publish(TerminalModeState next) {
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }
}
