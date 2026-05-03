import 'package:flutter/foundation.dart';

import 'clipboard_client.dart';

typedef TerminalBlockSeedFactory =
    List<TerminalBlock> Function(String sessionId);

enum TerminalBlockStatus { running, succeeded, failed, interrupted, unknown }

extension TerminalBlockStatusLabel on TerminalBlockStatus {
  String get label {
    return switch (this) {
      TerminalBlockStatus.running => 'Running',
      TerminalBlockStatus.succeeded => 'Succeeded',
      TerminalBlockStatus.failed => 'Failed',
      TerminalBlockStatus.interrupted => 'Interrupted',
      TerminalBlockStatus.unknown => 'Unknown',
    };
  }
}

class TerminalBlock {
  const TerminalBlock({
    required this.id,
    required this.sessionId,
    required this.commandText,
    required this.outputText,
    required this.status,
    required this.scrollbackOffset,
    this.recordedAt,
    this.targetEnvironment,
  });

  final String id;
  final String sessionId;
  final String commandText;
  final String outputText;
  final TerminalBlockStatus status;
  final int scrollbackOffset;
  final String? recordedAt;
  final String? targetEnvironment;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TerminalBlock &&
            other.id == id &&
            other.sessionId == sessionId &&
            other.commandText == commandText &&
            other.outputText == outputText &&
            other.status == status &&
            other.scrollbackOffset == scrollbackOffset &&
            other.recordedAt == recordedAt &&
            other.targetEnvironment == targetEnvironment;
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    commandText,
    outputText,
    status,
    scrollbackOffset,
    recordedAt,
    targetEnvironment,
  );

  TerminalBlock copyWith({
    String? id,
    String? sessionId,
    String? commandText,
    String? outputText,
    TerminalBlockStatus? status,
    int? scrollbackOffset,
    String? recordedAt,
    String? targetEnvironment,
  }) {
    return TerminalBlock(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      commandText: commandText ?? this.commandText,
      outputText: outputText ?? this.outputText,
      status: status ?? this.status,
      scrollbackOffset: scrollbackOffset ?? this.scrollbackOffset,
      recordedAt: recordedAt ?? this.recordedAt,
      targetEnvironment: targetEnvironment ?? this.targetEnvironment,
    );
  }
}

class TerminalBlocksController extends ChangeNotifier {
  TerminalBlocksController({
    required this.clipboardClient,
    required this.jumpToOffset,
    required this.reinputCommand,
  });

  final ClipboardClient clipboardClient;
  final void Function(int offset) jumpToOffset;
  final Future<void> Function(String command) reinputCommand;

  final List<TerminalBlock> _blocks = <TerminalBlock>[];
  int _activeIndex = -1;

  List<TerminalBlock> get blocks => List.unmodifiable(_blocks);
  bool get hasBlocks => _blocks.isNotEmpty;
  int get activeIndex => _activeIndex;
  int get displayIndex => hasBlocks ? _activeIndex + 1 : 0;
  TerminalBlock? get activeBlock {
    if (_activeIndex < 0 || _activeIndex >= _blocks.length) {
      return null;
    }
    return _blocks[_activeIndex];
  }

  bool get canGoToPreviousBlock => _blocks.length > 1;
  bool get canGoToNextBlock => _blocks.length > 1;
  bool get canCopyActiveCommand =>
      activeBlock?.commandText.trim().isNotEmpty ?? false;
  bool get canCopyActiveOutput => activeBlock?.outputText.isNotEmpty ?? false;
  bool get canCopyActiveCommandAndOutput =>
      canCopyActiveCommand || canCopyActiveOutput;
  bool get canReinputActiveCommand => canCopyActiveCommand;

  TerminalBlock startBlock({
    required String id,
    required String sessionId,
    required String commandText,
    int scrollbackOffset = 0,
  }) {
    final block = TerminalBlock(
      id: id,
      sessionId: sessionId,
      commandText: commandText,
      outputText: '',
      status: TerminalBlockStatus.running,
      scrollbackOffset: scrollbackOffset,
    );
    addBlock(block);
    return block;
  }

  void addBlock(TerminalBlock block) {
    final existingIndex = _indexOfBlock(block.id);
    if (existingIndex >= 0) {
      _blocks[existingIndex] = block;
      _activeIndex = existingIndex;
    } else {
      _blocks.add(block);
      _activeIndex = _blocks.length - 1;
    }
    notifyListeners();
  }

  void updateBlockOutput(String id, String outputText) {
    _updateBlock(id, (block) => block.copyWith(outputText: outputText));
  }

  void finishBlock(
    String id, {
    required TerminalBlockStatus status,
    String? recordedAt,
    String? targetEnvironment,
  }) {
    _updateBlock(
      id,
      (block) => block.copyWith(
        status: status,
        recordedAt: recordedAt,
        targetEnvironment: targetEnvironment,
      ),
    );
  }

  void goToPreviousBlock() {
    if (_blocks.isEmpty) {
      return;
    }
    _activeIndex = _activeIndex <= 0 ? _blocks.length - 1 : _activeIndex - 1;
    _jumpToActiveBlock();
    notifyListeners();
  }

  void goToNextBlock() {
    if (_blocks.isEmpty) {
      return;
    }
    _activeIndex = (_activeIndex + 1) % _blocks.length;
    _jumpToActiveBlock();
    notifyListeners();
  }

  void selectBlockById(String id) {
    final index = _indexOfBlock(id);
    if (index < 0) {
      return;
    }
    selectBlockAt(index);
  }

  void selectBlockAt(int index) {
    if (index < 0 || index >= _blocks.length) {
      return;
    }
    _activeIndex = index;
    _jumpToActiveBlock();
    notifyListeners();
  }

  Future<void> copyActiveCommand() async {
    final text = activeBlock?.commandText ?? '';
    if (text.isEmpty) {
      return;
    }
    await clipboardClient.writeText(text);
  }

  Future<void> copyActiveOutput() async {
    final text = activeBlock?.outputText ?? '';
    if (text.isEmpty) {
      return;
    }
    await clipboardClient.writeText(text);
  }

  Future<void> copyActiveCommandAndOutput() async {
    final block = activeBlock;
    if (block == null) {
      return;
    }
    final parts = <String>[
      if (block.commandText.isNotEmpty) block.commandText,
      if (block.outputText.isNotEmpty) block.outputText,
    ];
    if (parts.isEmpty) {
      return;
    }
    await clipboardClient.writeText(parts.join('\n'));
  }

  Future<void> reinputActiveCommand() async {
    final text = activeBlock?.commandText ?? '';
    if (text.isEmpty) {
      return;
    }
    await reinputCommand(text);
  }

  void clear() {
    if (_blocks.isEmpty && _activeIndex == -1) {
      return;
    }
    _blocks.clear();
    _activeIndex = -1;
    notifyListeners();
  }

  int _indexOfBlock(String id) {
    return _blocks.indexWhere((block) => block.id == id);
  }

  void _updateBlock(String id, TerminalBlock Function(TerminalBlock) update) {
    final index = _indexOfBlock(id);
    if (index < 0) {
      return;
    }
    _blocks[index] = update(_blocks[index]);
    _activeIndex = index;
    notifyListeners();
  }

  void _jumpToActiveBlock() {
    final block = activeBlock;
    if (block == null) {
      return;
    }
    jumpToOffset(block.scrollbackOffset);
  }
}
