import 'dart:convert';
import 'dart:typed_data';

/// Configuration is device-local; credentials never join profile/data sync.
class AiConfiguration {
  const AiConfiguration({
    required this.endpoint,
    required this.apiKey,
    required this.model,
  });

  const AiConfiguration.mock()
    : endpoint = 'http://127.0.0.1:8787/v1',
      apiKey = 'trail-local-mock',
      model = 'trail-mock';

  final String endpoint;
  final String apiKey;
  final String model;

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
    'endpoint': endpoint,
    'apiKey': apiKey,
    'model': model,
  };

  factory AiConfiguration.fromJson(Map<String, Object?> json) {
    final value = AiConfiguration(
      endpoint: json['endpoint']! as String,
      apiKey: json['apiKey']! as String,
      model: json['model']! as String,
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
bool looksLikeNaturalLanguage(String input) {
  final text = input.trimLeft();
  return text.startsWith('? ') ||
      RegExp('^(请|帮我|如何|怎么|解释|查找|列出|显示|修复|纠正|把|将|查看|打开|在当前)').hasMatch(text) ||
      RegExp(
        r'^(please\b|can you\b|could you\b|how (do|can|to)\b|why\b|explain\b|help me\b|show me\b|list (all|the)\b|find (all|the)\b|fix (this|the|my)\b|in (vim|vi|k9s)\b)',
        caseSensitive: false,
      ).hasMatch(text);
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

class AiBlockContext {
  const AiBlockContext({
    required this.command,
    required this.output,
    required this.exitCode,
    required this.cwd,
  });
  final String command;
  final String output;
  final int? exitCode;
  final String cwd;
  Map<String, Object?> toJson() => {
    'command': boundedAiText(command, 4000),
    'output': boundedAiText(output),
    'exit_code': exitCode,
    'cwd': cwd,
  };
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
  });

  final String sessionId;
  final String contextId;
  // Local capability token, intentionally excluded from model context.
  final String guard;
  final String? readyLease;
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

enum AiActionKind { runCommand, sendKeys, readScreen }

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
      throw const AiFailure('invalid_action');
    }
    if (value['text'] case final String text
        when text.isNotEmpty && text.length <= 4096) {
      if (text.contains(RegExp(r'[\x00-\x08\x0b-\x1f\x7f]'))) {
        throw const AiFailure('invalid_action');
      }
      return AiKeyStroke.text(text);
    }
    if (value['key'] case final String key when namedKeys.contains(key)) {
      return AiKeyStroke.key(key);
    }
    throw const AiFailure('invalid_action');
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
  });
  final String id;
  final AiActionKind kind;
  final String reason;
  final String? command;
  final List<AiKeyStroke> keys;
  final Map<String, Object?> rawCall;

  factory AiAction.fromToolCall(Map<String, Object?> call) {
    final function = call['function'];
    final id = call['id'];
    if (id is! String || id.isEmpty || id.length > 200 || function is! Map) {
      throw const AiFailure('invalid_action');
    }
    final args = jsonDecode(function['arguments'] as String);
    if (args is! Map) throw const AiFailure('invalid_action');
    final kind = switch (function['name']) {
      'run_command' => AiActionKind.runCommand,
      'send_keys' => AiActionKind.sendKeys,
      'read_screen' => AiActionKind.readScreen,
      _ => throw const AiFailure('invalid_action'),
    };
    final reason = args['reason'];
    if (reason is! String || reason.trim().isEmpty || reason.length > 2000) {
      throw const AiFailure('invalid_action');
    }
    final command = args['command'];
    if (kind == AiActionKind.runCommand &&
        (command is! String ||
            command.trim().isEmpty ||
            command.length > 8192 ||
            command.contains(RegExp(r'[\x00-\x08\x0b-\x1f\x7f]')))) {
      throw const AiFailure('invalid_action');
    }
    final rawKeys = args['keys'];
    if (kind == AiActionKind.sendKeys &&
        (rawKeys is! List || rawKeys.isEmpty || rawKeys.length > 64)) {
      throw const AiFailure('invalid_action');
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
      rawCall: Map.unmodifiable(call),
    );
    if (action.inputBytes().length > 8192) {
      throw const AiFailure('invalid_action');
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
  const AiReply({required this.text, this.action});
  final String text;
  final AiAction? action;
  Map<String, Object?> toMessage() => {
    'role': 'assistant',
    'content': text,
    if (action != null) 'tool_calls': [action!.rawCall],
  };
}
