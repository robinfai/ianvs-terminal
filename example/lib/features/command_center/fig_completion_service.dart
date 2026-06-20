import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:ianvs_pty/ianvs_pty.dart';

class FigCompletionRequest {
  const FigCompletionRequest({
    required this.text,
    required this.cursorOffset,
    this.cwd,
    this.shell,
    this.sessionId,
    this.environmentVariables = const <String, String>{},
    this.recentCommands = const <String>[],
  });

  final String text;
  final int cursorOffset;
  final String? cwd;
  final String? shell;
  final String? sessionId;
  final Map<String, String> environmentVariables;
  final List<String> recentCommands;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'text': text,
      'cursorOffset': cursorOffset,
      if (environmentVariables.isNotEmpty)
        'environmentVariables': environmentVariables,
      if (recentCommands.isNotEmpty)
        'recentCommands': recentCommands.take(40).toList(growable: false),
    };
    final normalizedCwd = _nonEmpty(cwd);
    if (normalizedCwd != null) {
      json['cwd'] = normalizedCwd;
    }
    final normalizedShell = _nonEmpty(shell);
    if (normalizedShell != null) {
      json['shell'] = normalizedShell;
    }
    final normalizedSessionId = _nonEmpty(sessionId);
    if (normalizedSessionId != null) {
      json['sessionId'] = normalizedSessionId;
    }
    return json;
  }
}

class FigCompletionResponse {
  const FigCompletionResponse({required this.items});

  factory FigCompletionResponse.fromJson(Object? json) {
    if (json is! Map) {
      throw const FormatException('Fig completion response must be an object.');
    }
    final rawItems = json['items'];
    if (rawItems is! List) {
      return const FigCompletionResponse(items: <FigCompletionSuggestion>[]);
    }
    return FigCompletionResponse(
      items: [
        for (final item in rawItems)
          if (item is Map)
            FigCompletionSuggestion.fromJson(item.cast<String, Object?>()),
      ],
    );
  }

  final List<FigCompletionSuggestion> items;
}

class FigCompletionSuggestion {
  const FigCompletionSuggestion({
    required this.name,
    required this.replacementText,
    this.displayName,
    this.description,
    this.type,
    this.source,
    this.replaceStart,
    this.replaceEnd,
    this.cursorOffset,
    this.priority = 50,
    this.isDangerous = false,
  });

  factory FigCompletionSuggestion.fromJson(Map<String, Object?> json) {
    final name = _firstString(json['name']);
    final replacementText =
        _stringValue(json['insertText']) ??
        _stringValue(json['replacementText']) ??
        name;
    if (name == null || replacementText == null) {
      throw const FormatException('Fig completion suggestion needs text.');
    }
    return FigCompletionSuggestion(
      name: name,
      replacementText: replacementText,
      displayName: _stringValue(json['displayName']),
      description: _stringValue(json['description']),
      type: _stringValue(json['type']),
      source: _stringValue(json['source']),
      replaceStart: _intValue(json['replaceStart']),
      replaceEnd: _intValue(json['replaceEnd']),
      cursorOffset: _intValue(json['cursorOffset']),
      priority: _intValue(json['priority']) ?? 50,
      isDangerous: json['isDangerous'] == true,
    );
  }

  final String name;
  final String replacementText;
  final String? displayName;
  final String? description;
  final String? type;
  final String? source;
  final int? replaceStart;
  final int? replaceEnd;
  final int? cursorOffset;
  final int priority;
  final bool isDangerous;
}

class FigCompletionService {
  FigCompletionService({
    FigCompletionBindings? bindings,
    bool? runNativeInBackground,
  }) : _bindings = bindings,
       _runNativeInBackground = runNativeInBackground ?? bindings == null;

  factory FigCompletionService.load() {
    return FigCompletionService();
  }

  final FigCompletionBindings? _bindings;
  final bool _runNativeInBackground;
  _FigCompletionWorker? _worker;

  Future<FigCompletionResponse?> complete(FigCompletionRequest input) async {
    try {
      final body = await _completeJson(jsonEncode(input.toJson()));
      if (body == null || body.trim().isEmpty) {
        return null;
      }
      return FigCompletionResponse.fromJson(jsonDecode(body));
    } on Object {
      return null;
    }
  }

  void close() {
    _worker?.close();
    _worker = null;
  }

  Future<String?> _completeJson(String requestJson) {
    if (_runNativeInBackground) {
      return (_worker ??= _FigCompletionWorker()).complete(requestJson);
    }
    final bindings = _bindings ?? NativeFigCompletionBindings.load();
    return Future.value(bindings.completeJson(requestJson));
  }
}

class _FigCompletionWorker {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  StreamSubscription<Object?>? _subscription;
  Completer<SendPort>? _ready;
  SendPort? _sendPort;
  int _nextRequestId = 0;
  final Map<int, Completer<String?>> _pending = <int, Completer<String?>>{};

  Future<String?> complete(String requestJson) async {
    final sendPort = await _ensureStarted();
    final requestId = _nextRequestId++;
    final completer = Completer<String?>();
    _pending[requestId] = completer;
    sendPort.send(<Object?>[requestId, requestJson]);
    return completer.future;
  }

  Future<SendPort> _ensureStarted() {
    final sendPort = _sendPort;
    if (sendPort != null) {
      return Future<SendPort>.value(sendPort);
    }
    final ready = _ready;
    if (ready != null) {
      return ready.future;
    }

    final nextReady = Completer<SendPort>();
    final receivePort = ReceivePort();
    _ready = nextReady;
    _receivePort = receivePort;
    _subscription = receivePort.listen(_handleMessage);
    Isolate.spawn(
      _figCompletionWorkerMain,
      receivePort.sendPort,
      debugName: 'Fig completion worker',
      errorsAreFatal: true,
      onError: receivePort.sendPort,
      onExit: receivePort.sendPort,
    ).then((isolate) {
      _isolate = isolate;
    }, onError: _completeWorkerFailure);
    return nextReady.future;
  }

  void _handleMessage(Object? message) {
    if (message == null) {
      _completeWorkerFailure(StateError('Fig completion worker exited.'));
      return;
    }
    if (message is SendPort) {
      _sendPort = message;
      final ready = _ready;
      if (ready != null && !ready.isCompleted) {
        ready.complete(message);
      }
      return;
    }
    if (message is! List<Object?> || message.length != 2) {
      return;
    }
    final requestId = message[0];
    if (requestId is! int) {
      _completeWorkerFailure(StateError(message.first.toString()));
      return;
    }
    _pending.remove(requestId)?.complete(_stringValue(message[1]));
  }

  void _completeWorkerFailure(Object error) {
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(error);
    }
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
    _pending.clear();
    _subscription?.cancel();
    _receivePort?.close();
    _isolate = null;
    _receivePort = null;
    _subscription = null;
    _ready = null;
    _sendPort = null;
  }

  void close() {
    _sendPort?.send(const <Object?>['close']);
    _isolate?.kill(priority: Isolate.immediate);
    _subscription?.cancel();
    _receivePort?.close();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
    _pending.clear();
    _isolate = null;
    _receivePort = null;
    _subscription = null;
    _ready = null;
    _sendPort = null;
  }
}

void _figCompletionWorkerMain(SendPort hostPort) {
  final receivePort = ReceivePort();
  final bindings = NativeFigCompletionBindings.load();
  hostPort.send(receivePort.sendPort);
  receivePort.listen((message) {
    if (message is List<Object?> &&
        message.length == 1 &&
        message.single == 'close') {
      receivePort.close();
      return;
    }
    if (message is! List<Object?> || message.length != 2) {
      return;
    }
    final requestId = message[0];
    final requestJson = message[1];
    if (requestId is! int || requestJson is! String) {
      return;
    }
    String? responseJson;
    try {
      responseJson = bindings.completeJson(requestJson);
    } on Object {
      responseJson = null;
    }
    hostPort.send(<Object?>[requestId, responseJson]);
  });
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _stringValue(Object? value) {
  return value is String && value.isNotEmpty ? value : null;
}

String? _firstString(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  if (value is List) {
    for (final item in value) {
      if (item is String && item.isNotEmpty) {
        return item;
      }
    }
  }
  return null;
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}
