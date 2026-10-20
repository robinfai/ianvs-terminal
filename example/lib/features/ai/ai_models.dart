import 'dart:convert';
import 'dart:typed_data';

import 'package:ianvs_terminal/input_intent.dart'
    show InputIntent, InputIntentContext, classifyInputIntent;

enum AiBackendKind { llm, acp }

enum AiApprovalMode { manual, smart }

enum AiApprovalSensitivity { cautious, balanced, relaxed }

/// Configuration is device-local; credentials never join profile/data sync.
class AiConfiguration {
  const AiConfiguration({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    this.approvalMode = AiApprovalMode.manual,
    this.approvalSensitivity = AiApprovalSensitivity.balanced,
  }) : backend = AiBackendKind.llm,
       agentCommand = '',
       agentArguments = const [];

  const AiConfiguration.acp({
    required this.agentCommand,
    this.agentArguments = const [],
    this.model = 'gpt-5.6-sol',
    this.approvalMode = AiApprovalMode.manual,
    this.approvalSensitivity = AiApprovalSensitivity.balanced,
  }) : backend = AiBackendKind.acp,
       endpoint = '',
       apiKey = '';

  const AiConfiguration.mock({
    this.approvalMode = AiApprovalMode.manual,
    this.approvalSensitivity = AiApprovalSensitivity.balanced,
  }) : endpoint = 'http://127.0.0.1:8787/v1',
       apiKey = 'trail-local-mock',
       model = 'trail-mock',
       backend = AiBackendKind.llm,
       agentCommand = '',
       agentArguments = const [];

  final AiBackendKind backend;
  final AiApprovalMode approvalMode;
  final AiApprovalSensitivity approvalSensitivity;
  final String agentCommand;
  final List<String> agentArguments;
  final String endpoint;
  final String apiKey;
  final String model;

  bool hasSameValues(
    AiConfiguration? other, {
    bool includeApprovalPolicy = true,
  }) =>
      other != null &&
      backend == other.backend &&
      (!includeApprovalPolicy ||
          (approvalMode == other.approvalMode &&
              approvalSensitivity == other.approvalSensitivity)) &&
      endpoint == other.endpoint &&
      apiKey == other.apiKey &&
      model == other.model &&
      agentCommand == other.agentCommand &&
      agentArguments.length == other.agentArguments.length &&
      Iterable<int>.generate(
        agentArguments.length,
      ).every((index) => agentArguments[index] == other.agentArguments[index]);

  void validate() {
    if (backend == AiBackendKind.llm) {
      completionsUri;
      return;
    }
    if (!agentCommand.startsWith('/') ||
        agentCommand.contains(RegExp(r'[\x00\r\n]')) ||
        agentArguments.length > 32 ||
        agentArguments.any((a) => a.length > 4096 || a.contains('\x00')) ||
        model.trim().isEmpty ||
        model.length > 200) {
      throw const AiFailure('configuration');
    }
  }

  Uri get completionsUri {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        model.trim().isEmpty ||
        model.length > 200 ||
        apiKey.trim().isEmpty ||
        apiKey.contains(RegExp(r'[\r\n]'))) {
      throw const AiFailure('configuration');
    }
    var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (!path.endsWith('/chat/completions')) {
      if (path.isEmpty) path = '/v1';
      path = '$path/chat/completions';
    }
    return uri.replace(path: path);
  }

  Map<String, Object?> toJson() => {
    'backend': backend.name,
    'approvalMode': approvalMode.name,
    'approvalSensitivity': approvalSensitivity.name,
    if (backend == AiBackendKind.acp) ...{
      'agentCommand': agentCommand,
      'agentArguments': agentArguments,
    },
    'endpoint': endpoint,
    'apiKey': apiKey,
    'model': model,
  };

  factory AiConfiguration.fromJson(Map<String, Object?> json) {
    final approvalMode = json['approvalMode'] == 'smart'
        ? AiApprovalMode.smart
        : AiApprovalMode.manual;
    // Existing installations retain their low-risk threshold until the user
    // selects a different sensitivity. Unknown values never widen approval.
    final approvalSensitivity = switch (json['approvalSensitivity']) {
      'cautious' => AiApprovalSensitivity.cautious,
      'relaxed' => AiApprovalSensitivity.relaxed,
      _ => AiApprovalSensitivity.balanced,
    };
    if (json['backend'] == 'acp') {
      final value = AiConfiguration.acp(
        agentCommand: json['agentCommand']! as String,
        agentArguments: (json['agentArguments']! as List).cast<String>(),
        model: json['model']! as String,
        approvalMode: approvalMode,
        approvalSensitivity: approvalSensitivity,
      );
      value.validate();
      return value;
    }
    final value = AiConfiguration(
      endpoint: json['endpoint']! as String,
      apiKey: json['apiKey']! as String,
      model: json['model']! as String,
      approvalMode: approvalMode,
      approvalSensitivity: approvalSensitivity,
    );
    value.completionsUri;
    return value;
  }
}

class AiFailure implements Exception {
  const AiFailure(this.code);
  final String code;
  @override
  String toString() => 'AI: $code';
}

/// A proposal rejected before any terminal input. Only this failure permits
/// asking the model to repair its arguments; execution failures never do.
class AiInvalidAction extends AiFailure {
  const AiInvalidAction(
    this.detail, {
    this.responseMessage,
    this.responseModel,
    this.requestId,
    this.usage,
  }) : super('invalid_action');

  // Locally authored diagnostic, never provider text or terminal output.
  final String detail;
  final Map<String, Object?>? responseMessage;
  final String? responseModel;
  final String? requestId;
  final Map<String, Object?>? usage;
}

abstract final class AiActionLimits {
  static const textLength = 4096;
  static const commandLength = 8192;
  static const reasonLength = 2000;
  static const keyCount = 64;
  static const inputBytes = 8192;
}

class AiCancellation {
  bool _cancelled = false;
  final _callbacks = <void Function()>[];
  bool get isCancelled => _cancelled;
  void check() {
    if (_cancelled) throw const AiFailure('cancelled');
  }

  void onCancel(void Function() callback) {
    if (_cancelled) {
      callback();
    } else {
      _callbacks.add(callback);
    }
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final callback in _callbacks) {
      callback();
    }
    _callbacks.clear();
  }
}

/// An explicit AI mode remains available for ambiguous or unsupported wording.
/// This local heuristic only changes the submit action; it never sends data.
bool looksLikeNaturalLanguage(
  String input, {
  Set<String> commandNames = const {},
}) {
  return classifyInputIntent(
        input,
        context: InputIntentContext(commandNames: commandNames),
      ).intent ==
      InputIntent.ai;
}

String boundedAiText(String text, [int limit = 16000]) {
  if (text.length <= limit) return text;
  // Keep the tail, where command failures and interactive prompts usually sit.
  var start = text.length - limit;
  if (start > 0 &&
      text.codeUnitAt(start) >= 0xdc00 &&
      text.codeUnitAt(start) <= 0xdfff) {
    start++;
  }
  return '[earlier content omitted]\n${text.substring(start)}';
}

class AiBlockOutputRange {
  const AiBlockOutputRange({
    required this.startLine,
    required this.endLine,
    required this.output,
    this.lineStartOffsets = const [],
  });
  final int startLine;
  final int endLine;
  final String output;

  /// UTF-16 offsets of physical terminal rows, including soft-wrapped rows.
  final List<int> lineStartOffsets;
}

Map<String, Object?> _blockOutputJson(
  String output,
  int startLine,
  int? endLine,
  List<int> rowOffsets,
  int limit,
) {
  if (output.length <= limit) {
    return {
      'output': output,
      'output_start_line': startLine,
      'output_end_line': ?endLine,
    };
  }
  var offsets = rowOffsets;
  if (offsets.isEmpty) {
    final logicalOffsets = [
      0,
      for (final match in RegExp('\n').allMatches(output)) match.end,
    ];
    // Legacy contexts can use logical lines only when they match the known
    // physical row count. Soft wraps otherwise make this mapping ambiguous.
    if (endLine != null && logicalOffsets.length == endLine - startLine) {
      offsets = logicalOffsets;
    }
  }
  var cut = output.length - limit;
  int? firstRow;
  var partial = false;
  if (offsets.isNotEmpty) {
    firstRow = offsets.indexWhere((offset) => offset >= cut);
    if (firstRow >= 0) {
      cut = offsets[firstRow];
    } else {
      firstRow = offsets.length - 1;
      partial = true;
    }
  }
  if (cut < output.length &&
      output.codeUnitAt(cut) >= 0xdc00 &&
      output.codeUnitAt(cut) <= 0xdfff) {
    cut++;
  }
  return {
    'output': output.substring(cut),
    if (firstRow != null) ...{
      'output_start_line': startLine + firstRow,
      'output_end_line': ?endLine,
      if (partial) 'first_line_truncated': true,
    } else
      'output_line_mapping_unavailable': true,
    'output_truncated': true,
  };
}

class AiBlockContext {
  const AiBlockContext({
    required this.command,
    required this.output,
    required this.exitCode,
    required this.cwd,
    this.id,
    this.running,
    this.totalLines,
    this.outputStartLine = 0,
    this.outputEndLine,
    this.evicted = false,
    this.sourceSessionId,
    this.sourceContextId,
    this.sourceLineBase,
    this.outputRanges = const [],
    this.lineStartOffsets = const [],
  });
  final String command;
  final String output;
  final int? exitCode;
  final String cwd;
  final String? id;
  final bool? running;
  final int? totalLines;
  final int outputStartLine;
  final int? outputEndLine;
  final bool evicted;
  final String? sourceSessionId;
  final String? sourceContextId;
  final int? sourceLineBase;

  /// Explicit disjoint source ranges. Empty means the ordinary contiguous
  /// outputStartLine/outputEndLine snapshot; bounds are zero-based, end-exclusive.
  final List<AiBlockOutputRange> outputRanges;
  final List<int> lineStartOffsets;

  /// Legacy snapshots without an explicit source must be bound while their
  /// original terminal is known, before a reconnect or target change.
  AiBlockContext withFallbackSource(AiTerminalContext origin) {
    if (sourceSessionId != null) return this;
    return AiBlockContext(
      command: command,
      output: output,
      exitCode: exitCode,
      cwd: cwd,
      id: id,
      running: running,
      totalLines: totalLines,
      outputStartLine: outputStartLine,
      outputEndLine: outputEndLine,
      evicted: evicted,
      sourceSessionId: origin.sessionId,
      sourceContextId: sourceContextId ?? origin.contextId,
      sourceLineBase: sourceLineBase,
      outputRanges: List.unmodifiable(outputRanges),
      lineStartOffsets: List.unmodifiable(lineStartOffsets),
    );
  }

  int get includedLineCount => outputRanges.isEmpty
      ? (outputEndLine ?? outputStartLine) - outputStartLine
      : outputRanges.fold(
          0,
          (count, range) => count + range.endLine - range.startLine,
        );
  String get selectionKey =>
      '$outputStartLine:$outputEndLine:${outputRanges.map((r) => '${r.startLine}:${r.endLine}').join(',')}';

  List<Map<String, Object?>> _rangesJson() {
    var remaining = 16000;
    final result = <Map<String, Object?>>[];
    for (final range in outputRanges) {
      if (remaining == 0) break;
      final data = _blockOutputJson(
        range.output,
        range.startLine,
        range.endLine,
        range.lineStartOffsets,
        remaining,
      );
      if (id != null) data['citation'] = _citation(data);
      remaining -= (data['output']! as String).length;
      result.add({
        if (data.containsKey('output_start_line'))
          'start_line': data.remove('output_start_line'),
        if (data.containsKey('output_end_line'))
          'end_line': data.remove('output_end_line'),
        ...data,
      });
    }
    return result;
  }

  String? _citation(Map<String, Object?> data) {
    final start = data['output_start_line'] as int?;
    final end = data['output_end_line'] as int?;
    return id != null && start != null && end != null && end > start
        ? '[block:$id:${start + 1}-$end]'
        : null;
  }

  Map<String, Object?> toJson() {
    final ranges = _rangesJson();
    final contiguous = _blockOutputJson(
      output,
      outputStartLine,
      outputEndLine,
      lineStartOffsets,
      16000,
    );
    if (id != null) contiguous['citation'] = _citation(contiguous);
    return {
      if (id != null) 'id': id,
      if (sourceSessionId != null) 'source_session_id': sourceSessionId,
      if (sourceContextId != null) 'source_context_id': sourceContextId,
      if (sourceLineBase != null) 'source_line_base': sourceLineBase,
      'command': boundedAiText(command, 4000),
      if (outputRanges.isEmpty) ...contiguous,
      if (outputRanges.isNotEmpty) ...{
        'output_is_contiguous': false,
        if (ranges.every(
          (r) => r.containsKey('start_line') && r.containsKey('end_line'),
        ))
          'included_line_count': ranges.fold<int>(
            0,
            (sum, r) =>
                sum + (r['end_line']! as int) - (r['start_line']! as int),
          ),
        'output_ranges': ranges,
        'output_start_line': outputStartLine,
        if (outputEndLine != null) 'output_end_line': outputEndLine,
      },
      'exit_code': exitCode,
      'cwd': cwd,
      if (running != null) 'running': running,
      if (totalLines != null) 'total_lines': totalLines,
      if (evicted) 'evicted': true,
      'output_truncated':
          outputRanges.isNotEmpty ||
          evicted ||
          outputStartLine > 0 ||
          output.length > 16000 ||
          (outputEndLine != null &&
              totalLines != null &&
              outputEndLine! < totalLines!),
    };
  }
}

class AiTerminalContext {
  const AiTerminalContext({
    required this.sessionId,
    required this.contextId,
    required this.guard,
    required this.screen,
    this.cwd = '',
    this.shell = '',
    this.runningCommand,
    this.lastBlock,
    this.alternateScreen = false,
    this.canRunCommand = false,
    this.readOnly = false,
    this.rows = 24,
    this.columns = 80,
    this.cursorRow = 0,
    this.cursorColumn = 0,
    this.readyLease,
    this.targetLabel = '',
    this.commandNames = const {},
    this.aliases = const {},
  });

  final String sessionId;
  final String contextId;
  // Local capability token, intentionally excluded from model context.
  final String guard;
  final String? readyLease;
  final String targetLabel;
  // Classification metadata stays on device and is excluded from toJson().
  final Set<String> commandNames;
  final Map<String, String> aliases;
  final String screen;
  final String cwd;
  final String shell;
  final String? runningCommand;
  final AiBlockContext? lastBlock;
  final bool alternateScreen;
  final bool canRunCommand;
  final bool readOnly;
  final int rows;
  final int columns;
  final int cursorRow;
  final int cursorColumn;

  Map<String, Object?> toJson() => {
    'session_id': sessionId,
    'context_id': contextId,
    if (targetLabel.isNotEmpty) 'target_label': targetLabel,
    'cwd': cwd,
    'shell': shell,
    'running_command': runningCommand,
    'screen': boundedAiText(screen),
    'alternate_screen': alternateScreen,
    'can_run_command': canRunCommand,
    'read_only': readOnly,
    'rows': rows,
    'columns': columns,
    'cursor': {'row': cursorRow, 'column': cursorColumn},
    if (lastBlock != null) 'last_command': lastBlock!.toJson(),
  };
}

typedef AiEvidenceRange = ({
  String id,
  String sessionId,
  int first,
  int last,
  int? sourceLineBase,
});

/// A displayed citation and the actual output snapshots supplied to its reply.
/// Multiple distinct origins must never be silently resolved to today's block.
typedef AiEvidenceReference = ({
  String id,
  int startLine,
  int endLine,
  List<AiEvidenceRange> origins,
});

/// Captures only line ranges actually included in this model request. Read
/// tools and attachments use the same serialized evidence format. User prose
/// and assistant/tool-call strings are never parsed as terminal evidence.
List<AiEvidenceRange> suppliedAiEvidence(
  List<Map<String, Object?>> messages, {
  required String sessionId,
}) {
  final result = <AiEvidenceRange>{};
  void visit(Object? value, String source) {
    if (value is List) {
      for (final child in value) {
        visit(child, source);
      }
    } else if (value is Map) {
      final current =
          value['source_session_id'] as String? ??
          value['session_id'] as String? ??
          source;
      if (value['id'] case final String id) {
        final ranges = value['output_ranges'] as List?;
        void include(Object? start, Object? end) {
          if (start is int && end is int && start >= 0 && end > start) {
            result.add((
              id: id,
              sessionId: current,
              first: start + 1,
              last: end,
              sourceLineBase: value['source_line_base'] as int?,
            ));
          }
        }

        if (ranges != null) {
          for (final range in ranges.whereType<Map<Object?, Object?>>()) {
            include(range['start_line'], range['end_line']);
          }
        } else if (value['output'] is String) {
          include(value['output_start_line'], value['output_end_line']);
        }
      }
      for (final child in value.values) {
        visit(child, current);
      }
    }
  }

  for (final message in messages) {
    if (message['role'] != 'user' && message['role'] != 'tool') continue;
    final content = message['content'];
    if (content is! String) continue;
    Object? data;
    try {
      data = jsonDecode(content);
    } on FormatException {
      continue;
    }
    visit(data, sessionId);
  }
  return List.unmodifiable(result);
}

enum AiActionKind { runCommand, sendKeys, readScreen, readBlock }

/// Input accepted by the existing PTY writer, not proof of application effects.
/// A failed/in-flight write remains uncertain even if its prefix was accepted.
class AiKeyInputProgress {
  const AiKeyInputProgress({
    required this.sent,
    required this.total,
    this.writeUncertain = false,
  }) : assert(
         sent >= 0 && sent <= total,
         'Accepted input count must be between zero and total.',
       );

  final int sent;
  final int total;
  final bool writeUncertain;

  Map<String, Object?> toJson(AiAction action) => {
    'sent_count': sent,
    'total_count': total,
    'write_uncertain': writeUncertain,
    'sent_keys': [
      for (final stroke in action.keys.take(sent))
        if (stroke.key != null) {'key': stroke.key} else {'text': stroke.text},
    ],
  };
}

class AiKeyStroke {
  const AiKeyStroke.text(this.text) : key = null;
  const AiKeyStroke.key(this.key) : text = null;
  final String? text;
  final String? key;

  static const namedKeys = {
    'ENTER',
    'ESC',
    'TAB',
    'BACKSPACE',
    'DELETE',
    'UP',
    'DOWN',
    'LEFT',
    'RIGHT',
    'HOME',
    'END',
    'PAGE_UP',
    'PAGE_DOWN',
    'CTRL_A',
    'CTRL_B',
    'CTRL_C',
    'CTRL_D',
    'CTRL_E',
    'CTRL_F',
    'CTRL_G',
    'CTRL_H',
    'CTRL_I',
    'CTRL_J',
    'CTRL_K',
    'CTRL_L',
    'CTRL_M',
    'CTRL_N',
    'CTRL_O',
    'CTRL_P',
    'CTRL_Q',
    'CTRL_R',
    'CTRL_S',
    'CTRL_T',
    'CTRL_U',
    'CTRL_V',
    'CTRL_W',
    'CTRL_X',
    'CTRL_Y',
    'CTRL_Z',
  };

  factory AiKeyStroke.fromJson(Object? value) {
    if (value is! Map || value.length != 1) {
      throw const AiInvalidAction(
        'Each keys item must contain only text or key.',
      );
    }
    if (value['text'] case final String text) {
      if (text.isEmpty || text.length > AiActionLimits.textLength) {
        throw const AiInvalidAction(
          'Each text item must contain 1..4096 UTF-16 code units. Split long text into smaller proposals.',
        );
      }
      if (text.contains(RegExp(r'[\x00-\x08\x0b-\x1f\x7f]'))) {
        throw const AiInvalidAction(
          'Text may contain tab and newline, but no other control characters. Use named keys for ENTER, ESC and control keys.',
        );
      }
      return AiKeyStroke.text(text);
    }
    if (value['key'] case final String key when namedKeys.contains(key)) {
      return AiKeyStroke.key(key);
    }
    throw const AiInvalidAction('Use a text string or a supported named key.');
  }

  String encode({bool applicationCursor = false}) {
    if (text != null) return text!;
    final prefix = applicationCursor ? '\x1bO' : '\x1b[';
    return switch (key!) {
      'ENTER' => '\r',
      'ESC' => '\x1b',
      'TAB' => '\t',
      'BACKSPACE' => '\x7f',
      'DELETE' => '\x1b[3~',
      'UP' => '${prefix}A',
      'DOWN' => '${prefix}B',
      'RIGHT' => '${prefix}C',
      'LEFT' => '${prefix}D',
      'HOME' => '${prefix}H',
      'END' => '${prefix}F',
      'PAGE_UP' => '\x1b[5~',
      'PAGE_DOWN' => '\x1b[6~',
      _ => String.fromCharCode(key!.codeUnitAt(5) - 64),
    };
  }

  String get preview => text ?? '<$key>';
}

class AiAction {
  const AiAction({
    required this.id,
    required this.kind,
    required this.reason,
    required this.rawCall,
    this.command,
    this.keys = const [],
    this.waitMs = 0,
    this.blockId,
    this.startLine = 0,
    this.lineCount = 160,
  });
  final String id;
  final AiActionKind kind;
  final String reason;
  final String? command;
  final List<AiKeyStroke> keys;
  final int waitMs;
  final String? blockId;
  final int startLine;
  final int lineCount;
  bool get writesInput =>
      kind == AiActionKind.runCommand || kind == AiActionKind.sendKeys;
  final Map<String, Object?> rawCall;

  factory AiAction.fromToolCall(Map<String, Object?> call) {
    final function = call['function'];
    final id = call['id'];
    if (id is! String || id.isEmpty || id.length > 200 || function is! Map) {
      throw const AiInvalidAction('A tool call requires an id and function.');
    }
    final rawArguments = function['arguments'];
    if (rawArguments is! String) {
      throw const AiInvalidAction(
        'Tool arguments must be a JSON object encoded as a string.',
      );
    }
    final Object? args;
    try {
      args = jsonDecode(rawArguments);
    } on FormatException {
      throw const AiInvalidAction('Tool arguments must contain valid JSON.');
    }
    if (args is! Map) {
      throw const AiInvalidAction('Tool arguments must be a JSON object.');
    }
    final kind = switch (function['name']) {
      'run_command' => AiActionKind.runCommand,
      'send_keys' => AiActionKind.sendKeys,
      'read_screen' => AiActionKind.readScreen,
      'read_block' => AiActionKind.readBlock,
      _ => throw const AiInvalidAction(
        'Use run_command, send_keys, read_screen or read_block.',
      ),
    };
    final reason = args['reason'];
    if (reason is! String ||
        reason.trim().isEmpty ||
        reason.length > AiActionLimits.reasonLength) {
      throw const AiInvalidAction(
        'reason must be a nonblank string of at most 2000 UTF-16 code units.',
      );
    }
    final command = args['command'];
    if (kind == AiActionKind.runCommand &&
        (command is! String ||
            command.trim().isEmpty ||
            command.length > AiActionLimits.commandLength ||
            command.contains(RegExp(r'[\x00-\x08\x0b-\x1f\x7f]')))) {
      throw const AiInvalidAction(
        'command must be a nonblank string of at most 8192 UTF-16 code units with no control characters except tab and newline.',
      );
    }
    final rawKeys = args['keys'];
    final blockId = args['block_id'];
    final startLine = args['start_line'] ?? 0;
    final lineCount = args['line_count'] ?? 160;
    if (kind == AiActionKind.readBlock &&
        (blockId is! String ||
            blockId.isEmpty ||
            blockId.length > 128 ||
            startLine is! int ||
            startLine < 0 ||
            startLine > 1 << 30 ||
            lineCount is! int ||
            lineCount < 1 ||
            lineCount > 500)) {
      throw const AiInvalidAction(
        'read_block requires a known block_id, zero-based start_line >= 0 and line_count from 1 to 500.',
      );
    }
    final waitMs = args['wait_ms'] ?? 0;
    if (kind == AiActionKind.readScreen &&
        (waitMs is! int || waitMs < 0 || waitMs > 30000)) {
      throw const AiInvalidAction(
        'wait_ms must be an integer from 0 to 30000.',
      );
    }
    if (kind == AiActionKind.sendKeys &&
        (rawKeys is! List ||
            rawKeys.isEmpty ||
            rawKeys.length > AiActionLimits.keyCount)) {
      throw const AiInvalidAction(
        'keys must contain 1..64 text or named-key items.',
      );
    }
    final keys = kind == AiActionKind.sendKeys
        ? (rawKeys as List).map(AiKeyStroke.fromJson).toList(growable: false)
        : const <AiKeyStroke>[];
    final action = AiAction(
      id: id,
      kind: kind,
      reason: reason,
      command: command is String ? command : null,
      keys: keys,
      waitMs: kind == AiActionKind.readScreen ? waitMs as int : 0,
      blockId: kind == AiActionKind.readBlock ? blockId as String : null,
      startLine: kind == AiActionKind.readBlock ? startLine as int : 0,
      lineCount: kind == AiActionKind.readBlock ? lineCount as int : 160,
      rawCall: Map.unmodifiable(call),
    );
    if (action.inputBytes().length > AiActionLimits.inputBytes) {
      throw const AiInvalidAction(
        'All keys together must encode to at most 8192 UTF-8 bytes. Split the input into smaller proposals.',
      );
    }
    return action;
  }

  Uint8List inputBytes({bool applicationCursor = false}) => Uint8List.fromList(
    utf8.encode(
      keys
          .map((key) => key.encode(applicationCursor: applicationCursor))
          .join(),
    ),
  );
  String get preview => command ?? keys.map((key) => key.preview).join();
}

class AiReply {
  const AiReply({
    required this.text,
    this.action,
    this.responseModel,
    this.requestId,
    this.usage,
  });
  final String text;
  final AiAction? action;
  final String? responseModel;
  final String? requestId;
  final Map<String, Object?>? usage;
  Map<String, Object?> toMessage() => {
    'role': 'assistant',
    'content': text,
    if (action != null) 'tool_calls': [action!.rawCall],
  };
}
