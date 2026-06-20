import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String defaultFigCompletionSidecarUrl = 'http://127.0.0.1:17382';

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
    Uri? endpoint,
    this.timeout = const Duration(milliseconds: 220),
    this.failureBackoff = const Duration(seconds: 5),
    HttpClient? httpClient,
  }) : endpoint = endpoint ?? Uri.parse(defaultFigCompletionSidecarUrl),
       _httpClient = httpClient ?? HttpClient(),
       _ownsHttpClient = httpClient == null;

  factory FigCompletionService.fromEnvironment({
    Map<String, String>? environment,
    HttpClient? httpClient,
  }) {
    final env = environment ?? Platform.environment;
    final configured = _nonEmpty(env['IANVS_FIG_COMPLETION_URL']);
    return FigCompletionService(
      endpoint: Uri.parse(configured ?? defaultFigCompletionSidecarUrl),
      httpClient: httpClient,
    );
  }

  final Uri endpoint;
  final Duration timeout;
  final Duration failureBackoff;
  final HttpClient _httpClient;
  final bool _ownsHttpClient;
  DateTime? _disabledUntil;

  Future<FigCompletionResponse?> complete(FigCompletionRequest input) async {
    final disabledUntil = _disabledUntil;
    if (disabledUntil != null && DateTime.now().isBefore(disabledUntil)) {
      return null;
    }
    try {
      final request = await _httpClient.postUrl(_completeUri).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(input.toJson()));
      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _markTemporarilyUnavailable();
        return null;
      }
      _disabledUntil = null;
      return FigCompletionResponse.fromJson(jsonDecode(body));
    } on Object {
      _markTemporarilyUnavailable();
      return null;
    }
  }

  void close() {
    if (_ownsHttpClient) {
      _httpClient.close(force: true);
    }
  }

  Uri get _completeUri {
    if (endpoint.path.endsWith('/complete')) {
      return endpoint;
    }
    final path = endpoint.path.replaceFirst(RegExp(r'/+$'), '');
    return endpoint.replace(
      path: path.isEmpty ? '/complete' : '$path/complete',
    );
  }

  void _markTemporarilyUnavailable() {
    _disabledUntil = DateTime.now().add(failureBackoff);
  }
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
