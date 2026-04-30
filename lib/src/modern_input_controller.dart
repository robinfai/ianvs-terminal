import 'package:flutter/foundation.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;

enum ModernInputEffectiveMode { modern, raw }

class ModernInputState {
  const ModernInputState({
    this.draft = '',
    this.manualRaw = false,
    this.autoRawHint = false,
  });

  final String draft;
  final bool manualRaw;
  final bool autoRawHint;

  ModernInputEffectiveMode get effectiveMode => manualRaw || autoRawHint
      ? ModernInputEffectiveMode.raw
      : ModernInputEffectiveMode.modern;

  ModernInputState copyWith({
    String? draft,
    bool? manualRaw,
    bool? autoRawHint,
  }) {
    return ModernInputState(
      draft: draft ?? this.draft,
      manualRaw: manualRaw ?? this.manualRaw,
      autoRawHint: autoRawHint ?? this.autoRawHint,
    );
  }
}

class ModernInputController extends ChangeNotifier {
  ModernInputController({required this.submitCommand});

  final Future<void> Function(String command) submitCommand;

  ModernInputState _state = const ModernInputState();

  ModernInputState get state => _state;
  bool get canSubmit => _state.draft.isNotEmpty;

  void updateDraft(String value) {
    _setState(_state.copyWith(draft: value));
  }

  void insertText(String value) {
    if (value.isEmpty) {
      return;
    }
    _setState(_state.copyWith(draft: '${_state.draft}$value'));
  }

  void insertNewline() {
    insertText('\n');
  }

  Future<bool> submit() async {
    final command = _state.draft;
    if (command.isEmpty) {
      return false;
    }
    await submitCommand(command);
    _setState(_state.copyWith(draft: ''));
    return true;
  }

  void enableManualRaw() {
    _setState(_state.copyWith(manualRaw: true));
  }

  void toggleManualRaw() {
    _setState(_state.copyWith(manualRaw: !_state.manualRaw));
  }

  void useModernInput() {
    _setState(_state.copyWith(manualRaw: false));
  }

  void updateAutoRawHintFromModes(terminal.TerminalFrameModes modes) {
    final nextHint =
        modes.mouseMode != 'off' ||
        modes.applicationCursor ||
        modes.applicationKeypad ||
        modes.focusTracking;
    if (nextHint == _state.autoRawHint) {
      return;
    }
    _setState(_state.copyWith(autoRawHint: nextHint));
  }

  void reset() {
    _setState(const ModernInputState());
  }

  void _setState(ModernInputState next) {
    if (next.draft == _state.draft &&
        next.manualRaw == _state.manualRaw &&
        next.autoRawHint == _state.autoRawHint) {
      return;
    }
    _state = next;
    notifyListeners();
  }
}
