import 'dart:convert';

import 'package:ianvs_pty/ianvs_pty.dart';

import '../config/terminal_defaults.dart';
import '../terminal/terminal_models.dart';
import 'terminal_backend_request_error.dart';

const int _maxSearchMatchesPerResponse = 1000;
const int _maxDecodedCollectionScanMultiplier = 4;

final class TerminalJsonRequestClient {
  const TerminalJsonRequestClient(
    this._backend, {
    TerminalBackendRequestErrorHandler? onRequestError,
  }) : _onRequestError = onRequestError;

  factory TerminalJsonRequestClient.fromBackend(
    PtySessionBackend backend, {
    TerminalBackendRequestErrorHandler? onRequestError,
  }) {
    return TerminalJsonRequestClient(
      backend is PtySessionJsonRequestBackend
          ? backend as PtySessionJsonRequestBackend
          : null,
      onRequestError: onRequestError,
    );
  }

  final PtySessionJsonRequestBackend? _backend;
  final TerminalBackendRequestErrorHandler? _onRequestError;

  String? selectionText(
    String sessionId,
    TerminalSelection selection, {
    required bool block,
  }) {
    const operation = 'terminal.selection_text';
    final decoded = _requestJsonObject(sessionId, operation, <String, Object?>{
      'kind': 'terminal.selection_text',
      'selection': selection.toJson(),
      'block': block,
    });
    if (decoded == null) {
      return null;
    }
    return _stringFromJsonValue(decoded['text']);
  }

  TerminalSearchResult searchTextResult(
    String sessionId,
    String query, {
    TerminalSearchMode mode = TerminalSearchMode.smartCaseSubstring,
  }) {
    if (query.isEmpty) {
      return TerminalSearchResult.empty;
    }
    const operation = 'terminal.search_text';
    final decoded = _requestJsonObject(sessionId, operation, <String, Object?>{
      'kind': operation,
      'query': query,
      'mode': mode.wireName,
    });
    if (decoded == null) {
      return TerminalSearchResult.empty;
    }
    return _decodeSearchResult(decoded);
  }

  bool clearScrollback(String sessionId) {
    const operation = 'terminal.clear_scrollback';
    final decoded = _requestJsonObject(sessionId, operation, <String, Object?>{
      'kind': operation,
    });
    return decoded?['cleared'] == true;
  }

  bool dismissOsc99Notification(String sessionId, String identifier) {
    const operation = 'terminal.dismiss_osc99_notification';
    final decoded = _requestJsonObject(sessionId, operation, <String, Object?>{
      'kind': operation,
      'id': identifier,
    });
    return decoded?['dismissed'] == true;
  }

  bool setBlockFolded(String sessionId, String id, {required bool folded}) {
    const operation = 'terminal.set_block_folded';
    final decoded = _requestJsonObject(sessionId, operation, <String, Object?>{
      'kind': operation,
      'id': id,
      'folded': folded,
    });
    return decoded?['updated'] == true;
  }

  bool setBlockRendered(String sessionId, String id, {required bool rendered}) {
    const operation = 'terminal.set_block_rendered';
    final decoded = _requestJsonObject(sessionId, operation, <String, Object?>{
      'kind': operation,
      'id': id,
      'rendered': rendered,
    });
    return decoded?['updated'] == true;
  }

  TerminalInlineButtonActivation activateItermButton(String sessionId, int id) {
    const operation = 'terminal.activate_iterm_button';
    final decoded = _requestJsonObject(sessionId, operation, <String, Object?>{
      'kind': operation,
      'id': id,
    });
    return decoded == null
        ? const TerminalInlineButtonActivation.rejected()
        : TerminalInlineButtonActivation.fromJson(decoded);
  }

  String? exportScrollbackText(String sessionId, {int? maxLines}) {
    const operation = 'terminal.export_scrollback';
    final decoded = _requestJsonObject(sessionId, operation, <String, Object?>{
      'kind': operation,
      'maxLines': ?_boundedScrollbackExportMaxLines(maxLines),
    });
    if (decoded == null) {
      return null;
    }
    return _stringFromJsonValue(decoded['content']);
  }

  Map<String, Object?>? _requestJsonObject(
    String sessionId,
    String operation,
    Map<String, Object?> request,
  ) {
    final backend = _backend;
    if (backend == null) {
      return null;
    }
    final String? raw;
    try {
      raw = backend.requestSessionJson(sessionId, jsonEncode(request));
    } on Object catch (error, stackTrace) {
      _onRequestError?.call(sessionId, operation, error, stackTrace);
      return null;
    }
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return _tryDecodeJsonObject(raw);
  }

  TerminalSearchResult _decodeSearchResult(Map<String, Object?> json) {
    final rawMatches = json['matches'];
    return TerminalSearchResult(
      matches: rawMatches is List
          ? _decodeSearchMatches(rawMatches)
          : const <TerminalSearchMatch>[],
      errorText: _nonEmptyTrimmedStringFromJsonValue(
        json['error_text'] ?? json['errorText'],
      ),
    );
  }

  List<TerminalSearchMatch> _decodeSearchMatches(List<dynamic> entries) {
    final matches = <TerminalSearchMatch>[];
    for (final entry in entries.take(
      _maxDecodedCollectionEntriesToScan(_maxSearchMatchesPerResponse),
    )) {
      if (entry is! Map) {
        continue;
      }
      try {
        matches.add(TerminalSearchMatch.fromJson(_stringKeyedJsonMap(entry)));
        if (matches.length >= _maxSearchMatchesPerResponse) {
          break;
        }
      } on Object {
        continue;
      }
    }
    return matches;
  }
}

int _maxDecodedCollectionEntriesToScan(int maxEntries) {
  return maxEntries * _maxDecodedCollectionScanMultiplier;
}

int? _boundedScrollbackExportMaxLines(int? value) {
  if (value == null) {
    return null;
  }
  if (value <= 0) {
    return 0;
  }
  if (value > maxTerminalScrollbackLines) {
    return maxTerminalScrollbackLines;
  }
  return value;
}

Map<String, Object?>? _tryDecodeJsonObject(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    return _stringKeyedJsonMap(decoded);
  } on Object {
    return null;
  }
}

Map<String, Object?> _stringKeyedJsonMap(Map<dynamic, dynamic> decoded) {
  final json = <String, Object?>{};
  for (final entry in decoded.entries) {
    final key = entry.key;
    if (key is String) {
      json[key] = entry.value;
    }
  }
  return json;
}

String? _stringFromJsonValue(Object? value) {
  if (value is String) {
    return value;
  }
  return null;
}

String? _nonEmptyTrimmedStringFromJsonValue(Object? value) {
  final text = _stringFromJsonValue(value)?.trim();
  return text == null || text.isEmpty ? null : text;
}
