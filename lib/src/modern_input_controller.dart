import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  TextEditingValue _editingValue = const TextEditingValue();

  ModernInputState get state => _state;
  TextEditingValue get editingValue => _editingValue;
  bool get canSubmit => _state.draft.isNotEmpty;

  void updateDraft(String value) {
    updateEditingValue(
      TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      ),
    );
  }

  void updateEditingValue(TextEditingValue value) {
    final nextValue = _normalizedEditingValue(value);
    final nextState = _state.copyWith(draft: nextValue.text);
    if (nextState.draft == _state.draft) {
      _editingValue = nextValue;
      return;
    }
    _editingValue = nextValue;
    _setState(nextState);
  }

  void insertText(String value) {
    if (value.isEmpty) {
      return;
    }
    updateEditingValue(_editingValueWithInsertedText(value));
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
    _editingValue = const TextEditingValue();
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
    _editingValue = const TextEditingValue();
    _setState(const ModernInputState());
  }

  TextEditingValue _editingValueWithInsertedText(String value) {
    final baseValue = _editingValue.text == _state.draft
        ? _editingValue
        : TextEditingValue(
            text: _state.draft,
            selection: TextSelection.collapsed(offset: _state.draft.length),
          );
    final normalizedValue = _normalizedEditingValue(baseValue);
    final selection = normalizedValue.selection;
    final start = selection.start;
    final end = selection.end;
    final nextText = normalizedValue.text.replaceRange(start, end, value);
    return normalizedValue.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + value.length),
      composing: TextRange.empty,
    );
  }

  TextEditingValue _normalizedEditingValue(TextEditingValue value) {
    final text = value.text;
    if (!value.selection.isValid) {
      return value.copyWith(
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    final start = value.selection.start.clamp(0, text.length);
    final end = value.selection.end.clamp(0, text.length);
    return value.copyWith(
      selection: TextSelection(baseOffset: start, extentOffset: end),
    );
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
