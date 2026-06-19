import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'universal_input.dart';

class CommandIntelligenceService {
  CommandIntelligenceService({
    String? apiKey,
    this.model = defaultCommandIntelligenceModel,
    this.baseUrl = defaultCommandIntelligenceBaseUrl,
    this.timeout = const Duration(seconds: 5),
    HttpClient? httpClient,
  }) : _apiKey = _nonEmpty(apiKey),
       _httpClient = httpClient ?? HttpClient(),
       _ownsHttpClient = httpClient == null;

  factory CommandIntelligenceService.fromEnvironment({
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    return CommandIntelligenceService(apiKey: env['DEEPSEEK_API_KEY']);
  }

  final String? _apiKey;
  final HttpClient _httpClient;
  final bool _ownsHttpClient;
  final String model;
  final String baseUrl;
  final Duration timeout;

  bool get remoteAvailable => _apiKey != null;

  static const String defaultCommandIntelligenceModel = 'deepseek-v4-flash';
  static const String defaultCommandIntelligenceBaseUrl =
      'https://api.deepseek.com';

  bool remoteAvailableFor({String? apiKey}) {
    return _apiKeyFor(apiKey) != null;
  }

  void close() {
    if (_ownsHttpClient) {
      _httpClient.close(force: true);
    }
  }

  Future<List<CommandDraft>> draftCommands(CommandDraftRequest request) async {
    final apiKey = _apiKeyFor(request.apiKey);
    if (!request.allowRemote || apiKey == null) {
      return const <CommandDraft>[];
    }
    try {
      return await _requestDraftCommands(
        request,
        apiKey: apiKey,
        baseUrl: _baseUrlFor(request.apiBaseUrl),
        model: _modelFor(request.apiModel),
      );
    } on Object {
      return const <CommandDraft>[];
    }
  }

  Future<CommandCorrection?> correctCommand(
    CommandCorrectionRequest request,
  ) async {
    final safeRequest = CommandCorrectionRequest(
      command: request.command,
      cwd: request.cwd,
      exitCode: request.exitCode,
      outputTail: redactUniversalInputCommandContext(request.outputTail),
      recentCommands: request.recentCommands,
      recentDirectories: request.recentDirectories,
      apiBaseUrl: request.apiBaseUrl,
      apiKey: request.apiKey,
      apiModel: request.apiModel,
      allowRemote: request.allowRemote,
      preferRemote: request.preferRemote,
    );
    final localCorrection = universalInputLocalCorrectionFor(safeRequest);
    final apiKey = _apiKeyFor(safeRequest.apiKey);
    final shouldUseRemote =
        safeRequest.allowRemote &&
        apiKey != null &&
        (safeRequest.preferRemote || localCorrection == null);
    if (!shouldUseRemote) {
      return localCorrection;
    }
    try {
      return await _requestCommandCorrection(
            safeRequest,
            apiKey: apiKey,
            baseUrl: _baseUrlFor(safeRequest.apiBaseUrl),
            model: _modelFor(safeRequest.apiModel),
          ) ??
          localCorrection;
    } on Object {
      return localCorrection;
    }
  }

  Future<List<CommandDraft>> _requestDraftCommands(
    CommandDraftRequest request, {
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    final content = await _chatCompletion(
      [
        {
          'role': 'system',
          'content':
              'Return only JSON. Generate at most 3 concise shell commands for the user intent. '
              'Use this shape: {"commands":[{"command":"...","reason":"...","confidence":0.0-1.0}]}. '
              'Never include markdown. Never execute commands. Do not include reasoning.',
        },
        {
          'role': 'user',
          'content': jsonEncode({
            'intent': request.input,
            'cwd': request.cwd,
            'recentCommands': request.recentCommands.take(12).toList(),
            'contextChips': request.contextChips.take(8).toList(),
            'modelLabel': request.modelLabel,
          }),
        },
      ],
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
    );
    final decoded = _decodeJsonPayload(content);
    final commandObjects = _commandObjectsFromJson(decoded);
    return [
      for (final object in commandObjects.take(3))
        if (_stringValue(object['command']) case final command?
            when command.trim().isNotEmpty)
          CommandDraft(
            command: command.trim(),
            reason:
                _stringValue(object['reason']) ??
                'Generated from natural language.',
            source: CommandSuggestionSource.deepSeek,
            confidence: _confidenceValue(object['confidence']),
            riskLevel: universalInputRiskLevelForCommand(command),
          ),
    ];
  }

  Future<CommandCorrection?> _requestCommandCorrection(
    CommandCorrectionRequest request, {
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    final content = await _chatCompletion(
      [
        {
          'role': 'system',
          'content':
              'Return only JSON. Suggest one corrected shell command for a failed command. '
              'Use this shape: {"command":"...","reason":"...","confidence":0.0-1.0}. '
              'If no useful correction exists, return {"command":null}. Never include markdown. Do not include reasoning.',
        },
        {
          'role': 'user',
          'content': jsonEncode({
            'command': request.command,
            'cwd': request.cwd,
            'exitCode': request.exitCode,
            'outputTail': request.outputTail,
            'recentCommands': request.recentCommands.take(12).toList(),
            'recentDirectories': request.recentDirectories.take(12).toList(),
          }),
        },
      ],
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
    );
    final decoded = _decodeJsonPayload(content);
    final object = switch (decoded) {
      final Map<String, Object?> map => map,
      final List<Object?> list when list.isNotEmpty && list.first is Map =>
        (list.first as Map).cast<String, Object?>(),
      _ => null,
    };
    if (object == null) {
      return null;
    }
    final command = _stringValue(object['command'])?.trim();
    if (command == null || command.isEmpty) {
      return null;
    }
    return CommandCorrection(
      command: command,
      reason:
          _stringValue(object['reason']) ?? 'Generated from failure output.',
      ruleId: 'deepseek-correction',
      source: CommandSuggestionSource.deepSeek,
      confidence: _confidenceValue(object['confidence']),
      riskLevel: universalInputRiskLevelForCommand(command),
    );
  }

  Future<String> _chatCompletion(
    List<Map<String, Object?>> messages, {
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    final uri = Uri.parse('${_normalizedBaseUrl(baseUrl)}/chat/completions');
    final request = await _httpClient.postUrl(uri).timeout(timeout);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    request.write(jsonEncode(_requestBodyFor(messages, baseUrl, model)));
    final response = await request.close().timeout(timeout);
    final body = await utf8.decoder.bind(response).join().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'DeepSeek request failed with ${response.statusCode}.',
        uri: uri,
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('DeepSeek response must be an object.');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('DeepSeek response has no choices.');
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map) {
      throw const FormatException('DeepSeek choice must be an object.');
    }
    final message = firstChoice['message'];
    if (message is! Map) {
      throw const FormatException('DeepSeek message must be an object.');
    }
    final content = message['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('DeepSeek content is empty.');
    }
    return content;
  }

  Object? _decodeJsonPayload(String content) {
    var trimmed = content.trim();
    if (trimmed.startsWith('```')) {
      trimmed = trimmed
          .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }
    final firstObject = trimmed.indexOf('{');
    final firstArray = trimmed.indexOf('[');
    final startCandidates = [
      if (firstObject != -1) firstObject,
      if (firstArray != -1) firstArray,
    ];
    if (startCandidates.isNotEmpty) {
      final start = startCandidates.reduce((a, b) => a < b ? a : b);
      final end = trimmed.lastIndexOf(trimmed[start] == '{' ? '}' : ']');
      if (end > start) {
        trimmed = trimmed.substring(start, end + 1);
      }
    }
    return jsonDecode(trimmed);
  }

  List<Map<String, Object?>> _commandObjectsFromJson(Object? decoded) {
    final objects = switch (decoded) {
      final Map<String, Object?> map when map['commands'] is List =>
        map['commands'] as List,
      final Map<String, Object?> map when map['command'] != null => [map],
      final List<Object?> list => list,
      _ => const <Object?>[],
    };
    return [
      for (final object in objects)
        if (object is Map) object.cast<String, Object?>(),
    ];
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String? _apiKeyFor(String? override) {
    return _nonEmpty(override) ?? _apiKey;
  }

  String _baseUrlFor(String? override) {
    return _nonEmpty(override) ?? baseUrl;
  }

  String _modelFor(String? override) {
    return _nonEmpty(override) ?? model;
  }

  static String _normalizedBaseUrl(String value) {
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  Map<String, Object?> _requestBodyFor(
    List<Map<String, Object?>> messages,
    String baseUrl,
    String model,
  ) {
    return {
      'model': model,
      'messages': messages,
      'temperature': 0.2,
      if (_shouldDisableThinking(baseUrl: baseUrl, model: model))
        'thinking': {'type': 'disabled'},
    };
  }

  static bool _shouldDisableThinking({
    required String baseUrl,
    required String model,
  }) {
    final normalizedBaseUrl = baseUrl.toLowerCase();
    final normalizedModel = model.toLowerCase();
    return normalizedBaseUrl.contains('deepseek') ||
        normalizedModel.startsWith('deepseek-');
  }

  static String? _stringValue(Object? value) {
    return value is String ? value : null;
  }

  static double _confidenceValue(Object? value) {
    final confidence = switch (value) {
      final num number => number.toDouble(),
      final String text => double.tryParse(text),
      _ => null,
    };
    return (confidence ?? 0.72).clamp(0, 1).toDouble();
  }
}
