import 'package:ianvs_pty/ianvs_pty.dart';

import '../config/terminal_defaults.dart';
import '../terminal/terminal_models.dart';
import 'terminal_backend_request_error.dart';
import 'terminal_session_request_transport.dart';
import 'terminal_zmodem_recovery.dart';

const int _maxSearchMatchesPerResponse = 1000;
const int _maxDecodedCollectionScanMultiplier = 4;

enum TerminalZmodemCancelActiveOutcome { cancelled, draining, idle }

final class TerminalJsonRequestClient {
  TerminalJsonRequestClient(
    PtySessionJsonRequestBackend? backend, {
    TerminalBackendRequestErrorHandler? onRequestError,
  }) : _transport = TerminalSessionRequestTransport(backend),
       _onRequestError = onRequestError;

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

  final TerminalSessionRequestTransport _transport;
  final TerminalBackendRequestErrorHandler? _onRequestError;

  bool respondSshAuthentication(
    String sessionId, {
    required int challengeId,
    required List<String> responses,
    bool cancel = false,
  }) {
    const operation = 'ssh.auth_response';
    final decoded = _requestJsonObject(sessionId, operation, <String, Object?>{
      'kind': operation,
      'challengeId': challengeId,
      'responses': responses,
      'cancel': cancel,
    });
    return decoded?['accepted'] == true;
  }

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

  bool clearBuffer(String sessionId) {
    const operation = 'terminal.clear_buffer';
    final decoded = _requestJsonObject(sessionId, operation, <String, Object?>{
      'kind': operation,
    });
    return decoded?['cleared'] == true;
  }

  bool acceptZmodemReceive(
    String sessionId, {
    required String transferId,
    required String destination,
  }) {
    const operation = 'terminal.zmodem.accept_receive';
    final decoded = _requestJsonObject(sessionId, operation, <String, Object?>{
      'kind': operation,
      'transferId': transferId,
      'destination': destination,
    });
    return decoded?['accepted'] == true;
  }

  bool acceptZmodemSend(
    String sessionId, {
    required String transferId,
    required List<String> files,
  }) {
    const operation = 'terminal.zmodem.accept_send';
    final decoded = _requestJsonObject(sessionId, operation, <String, Object?>{
      'kind': operation,
      'transferId': transferId,
      'files': files,
    });
    return decoded?['accepted'] == true;
  }

  bool cancelZmodem(String sessionId, {required String transferId}) {
    const operation = 'terminal.zmodem.cancel';
    final decoded = _requestJsonObject(sessionId, operation, <String, Object?>{
      'kind': operation,
      'transferId': transferId,
    });
    return decoded?['cancelled'] == true;
  }

  TerminalZmodemCancelActiveOutcome? cancelActiveZmodem(String sessionId) {
    const operation = 'terminal.zmodem.cancel_active';
    final decoded = _requestJsonObject(sessionId, operation, <String, Object?>{
      'kind': operation,
    });
    if (decoded?['reconciled'] != true) {
      return null;
    }
    return switch (decoded?['outcome']) {
      'cancelled' => TerminalZmodemCancelActiveOutcome.cancelled,
      'draining' => TerminalZmodemCancelActiveOutcome.draining,
      'idle' => TerminalZmodemCancelActiveOutcome.idle,
      _ => null,
    };
  }

  bool? sessionCloseReady(String sessionId) {
    const operation = 'terminal.session.close_readiness';
    final decoded = _requestJsonObject(sessionId, operation, <String, Object?>{
      'kind': operation,
    });
    return switch (decoded?['ready']) {
      true => true,
      false => false,
      _ => null,
    };
  }

  TerminalZmodemRecoveryResolution resolveZmodemRecovery(
    String sessionId, {
    required String recoveryToken,
  }) {
    if (!_isZmodemRecoveryToken(recoveryToken)) {
      return const TerminalZmodemRecoveryResolution.requestFailed();
    }
    const operation = 'terminal.zmodem.resolve_recovery';
    final decoded = _requestJsonObject(sessionId, operation, <String, Object?>{
      'kind': operation,
      'recoveryToken': recoveryToken,
    });
    if (decoded == null) {
      return const TerminalZmodemRecoveryResolution.requestFailed();
    }
    if (decoded['available'] == false) {
      return const TerminalZmodemRecoveryResolution.unavailable();
    }
    if (decoded['available'] != true) {
      return const TerminalZmodemRecoveryResolution.requestFailed();
    }
    final path = _stringFromJsonValue(decoded['path']);
    return path != null &&
            path.startsWith('/') &&
            path.length <= 4096 &&
            !path.contains('\u0000')
        ? TerminalZmodemRecoveryResolution.available(path)
        : const TerminalZmodemRecoveryResolution.requestFailed();
  }

  TerminalZmodemRecoveryDisposition consumeZmodemRecovery(
    String sessionId, {
    required String recoveryToken,
  }) {
    if (!_isZmodemRecoveryToken(recoveryToken)) {
      return TerminalZmodemRecoveryDisposition.requestFailed;
    }
    const operation = 'terminal.zmodem.consume_recovery';
    final decoded = _requestJsonObject(sessionId, operation, <String, Object?>{
      'kind': operation,
      'recoveryToken': recoveryToken,
    });
    if (decoded == null || decoded['consumed'] is! bool) {
      return TerminalZmodemRecoveryDisposition.requestFailed;
    }
    return decoded['consumed'] == true
        ? TerminalZmodemRecoveryDisposition.success
        : TerminalZmodemRecoveryDisposition.unavailable;
  }

  TerminalZmodemRecoveryDisposition dismissZmodemRecovery(
    String sessionId, {
    required String recoveryToken,
  }) {
    if (!_isZmodemRecoveryToken(recoveryToken)) {
      return TerminalZmodemRecoveryDisposition.requestFailed;
    }
    const operation = 'terminal.zmodem.dismiss_recovery';
    final decoded = _requestJsonObject(sessionId, operation, <String, Object?>{
      'kind': operation,
      'recoveryToken': recoveryToken,
    });
    if (decoded == null || decoded['dismissed'] is! bool) {
      return TerminalZmodemRecoveryDisposition.requestFailed;
    }
    return decoded['dismissed'] == true
        ? TerminalZmodemRecoveryDisposition.success
        : TerminalZmodemRecoveryDisposition.unavailable;
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
    if (!_transport.isSupported) {
      return null;
    }
    try {
      return _transport.requestObject(sessionId, request);
    } on Object catch (error, stackTrace) {
      _onRequestError?.call(sessionId, operation, error, stackTrace);
      return null;
    }
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

bool _isZmodemRecoveryToken(String value) =>
    value.length == 32 && RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(value);
