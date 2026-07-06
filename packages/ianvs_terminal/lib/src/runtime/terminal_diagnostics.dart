import 'dart:convert';

import 'package:ianvs_pty/ianvs_pty.dart';

import 'terminal_backend_request_error.dart';

const int _maxDiagnosticsResourceSamples = 60;
const int _maxDiagnosticsEvents = 200;
const int _maxDiagnosticsSummaryEntries = 32;
const int _maxDiagnosticsSummaryNestedEntries = 32;
const int _maxDiagnosticsSummaryListEntries = 20;
const int _maxDiagnosticsSummaryStringLength = 4096;
const int _maxDiagnosticsSummaryListStringLength = 512;
const int _maxDecodedCollectionScanMultiplier = 4;

final class TerminalDiagnosticsClient {
  const TerminalDiagnosticsClient(
    this._requestBackend, {
    TerminalBackendRequestErrorHandler? onRequestError,
  }) : _onRequestError = onRequestError;

  factory TerminalDiagnosticsClient.fromBackend(
    PtySessionBackend backend, {
    TerminalBackendRequestErrorHandler? onRequestError,
  }) {
    return TerminalDiagnosticsClient(
      backend is PtySessionJsonRequestBackend
          ? backend as PtySessionJsonRequestBackend
          : null,
      onRequestError: onRequestError,
    );
  }

  final PtySessionJsonRequestBackend? _requestBackend;
  final TerminalBackendRequestErrorHandler? _onRequestError;

  TerminalDiagnosticsExport? exportSession(
    String sessionId, {
    TerminalDiagnosticsPolicy policy = const TerminalDiagnosticsPolicy(),
  }) {
    final backend = _requestBackend;
    if (backend == null) {
      return null;
    }

    final String? raw;
    try {
      raw = backend.requestSessionJson(
        sessionId,
        jsonEncode(policy.toRequestJson()),
      );
    } on Object catch (error, stackTrace) {
      _onRequestError?.call(
        sessionId,
        'terminal.export_diagnostics',
        error,
        stackTrace,
      );
      return null;
    }

    try {
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return TerminalDiagnosticsExport.fromJson(_stringKeyedJsonMap(decoded));
    } on Object {
      return null;
    }
  }
}

final class TerminalDiagnosticsPolicy {
  const TerminalDiagnosticsPolicy({
    this.maxSamples = 60,
    this.includeScrollback = false,
    this.includeRawCommand = false,
    this.includeRawCwd = false,
    this.includeEnv = false,
    this.redactionMode = 'basic',
  });

  final int maxSamples;
  final bool includeScrollback;
  final bool includeRawCommand;
  final bool includeRawCwd;
  final bool includeEnv;
  final String redactionMode;

  bool get includeContent =>
      includeScrollback || includeRawCommand || includeRawCwd || includeEnv;

  Map<String, Object?> toRequestJson() {
    final effectiveMaxSamples = maxSamples.clamp(1, 60).toInt();
    return <String, Object?>{
      'kind': 'terminal.export_diagnostics',
      'maxSamples': effectiveMaxSamples,
      'includeContent': includeContent,
      'redactionMode': redactionMode,
      'policy': <String, Object?>{
        'includeScrollback': includeScrollback,
        'includeRawCommand': includeRawCommand,
        'includeRawCwd': includeRawCwd,
        'includeEnv': includeEnv,
      },
    };
  }
}

final class TerminalDiagnosticsExport {
  const TerminalDiagnosticsExport({
    required this.manifest,
    required this.resourceSamples,
    required this.terminalStats,
    required this.events,
    required this.summary,
  });

  factory TerminalDiagnosticsExport.fromJson(Map<String, Object?> json) {
    return TerminalDiagnosticsExport(
      manifest: _mapValue(json['manifest']),
      resourceSamples: _mapList(
        json['resource_samples'] ?? json['resourceSamples'],
        maxEntries: _maxDiagnosticsResourceSamples,
      ),
      terminalStats: _mapValue(json['terminal_stats'] ?? json['terminalStats']),
      events: _mapList(json['events'], maxEntries: _maxDiagnosticsEvents),
      summary: _diagnosticsSummaryValue(json['summary']),
    );
  }

  final Map<String, Object?> manifest;
  final List<Map<String, Object?>> resourceSamples;
  final Map<String, Object?> terminalStats;
  final List<Map<String, Object?>> events;
  final Map<String, Object?> summary;

  String? get conclusion =>
      _nonEmptyTrimmedStringFromJsonValue(summary['conclusion']);
  String? get summaryMarkdown =>
      _nonEmptyTrimmedStringFromJsonValue(summary['markdown']);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'manifest': manifest,
      'resource_samples': resourceSamples,
      'terminal_stats': terminalStats,
      'events': events,
      'summary': summary,
    };
  }
}

Map<String, Object?> _mapValue(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(_stringKeyedJsonMap(value));
  }
  return const <String, Object?>{};
}

Map<String, Object?> _diagnosticsSummaryValue(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  final result = <String, Object?>{};
  for (final entry in value.entries.take(
    _maxDecodedCollectionEntriesToScan(_maxDiagnosticsSummaryEntries),
  )) {
    if (result.length >= _maxDiagnosticsSummaryEntries) {
      break;
    }
    final key = entry.key;
    if (key is! String) {
      continue;
    }
    final boundedValue = _boundedDiagnosticsSummaryEntry(key, entry.value);
    if (boundedValue != null) {
      result[key] = boundedValue;
    }
  }
  return Map<String, Object?>.unmodifiable(result);
}

Object? _boundedDiagnosticsSummaryEntry(String key, Object? value) {
  return switch (key) {
    'evidence' || 'next_steps' => _diagnosticsSummaryStringList(value),
    _ => _boundedDiagnosticsSummaryJson(value, depth: 2),
  };
}

List<String> _diagnosticsSummaryStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  final strings = <String>[];
  for (final entry in value.take(
    _maxDecodedCollectionEntriesToScan(_maxDiagnosticsSummaryListEntries),
  )) {
    if (strings.length >= _maxDiagnosticsSummaryListEntries) {
      break;
    }
    final text = _boundedNonEmptyTrimmedString(
      entry,
      maxLength: _maxDiagnosticsSummaryListStringLength,
    );
    if (text != null) {
      strings.add(text);
    }
  }
  return List<String>.unmodifiable(strings);
}

Object? _boundedDiagnosticsSummaryJson(Object? value, {required int depth}) {
  if (value == null || value is bool) {
    return value;
  }
  if (value is num) {
    return value.isFinite ? value : null;
  }
  final text = _boundedNonEmptyTrimmedString(
    value,
    maxLength: _maxDiagnosticsSummaryStringLength,
  );
  if (text != null) {
    return text;
  }
  if (depth <= 0) {
    return null;
  }
  if (value is List) {
    final result = <Object?>[];
    for (final entry in value.take(
      _maxDecodedCollectionEntriesToScan(_maxDiagnosticsSummaryListEntries),
    )) {
      if (result.length >= _maxDiagnosticsSummaryListEntries) {
        break;
      }
      final boundedValue = _boundedDiagnosticsSummaryJson(
        entry,
        depth: depth - 1,
      );
      if (boundedValue != null) {
        result.add(boundedValue);
      }
    }
    return List<Object?>.unmodifiable(result);
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries.take(
      _maxDecodedCollectionEntriesToScan(_maxDiagnosticsSummaryNestedEntries),
    )) {
      if (result.length >= _maxDiagnosticsSummaryNestedEntries) {
        break;
      }
      final key = _boundedNonEmptyTrimmedString(
        entry.key,
        maxLength: _maxDiagnosticsSummaryListStringLength,
      );
      if (key == null) {
        continue;
      }
      final boundedValue = _boundedDiagnosticsSummaryJson(
        entry.value,
        depth: depth - 1,
      );
      if (boundedValue != null) {
        result[key] = boundedValue;
      }
    }
    return Map<String, Object?>.unmodifiable(result);
  }
  return null;
}

String? _boundedNonEmptyTrimmedString(Object? value, {required int maxLength}) {
  final text = _stringFromJsonValue(value)?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  if (text.length <= maxLength) {
    return text;
  }
  return text.substring(0, maxLength);
}

List<Map<String, Object?>> _mapList(Object? value, {int? maxEntries}) {
  if (value is! List) {
    return const <Map<String, Object?>>[];
  }
  final maps = <Map<String, Object?>>[];
  final entries = maxEntries == null
      ? value
      : value.take(_maxDecodedCollectionEntriesToScan(maxEntries));
  for (final entry in entries) {
    if (entry is! Map) {
      continue;
    }
    maps.add(Map<String, Object?>.unmodifiable(_stringKeyedJsonMap(entry)));
    if (maxEntries != null && maps.length >= maxEntries) {
      break;
    }
  }
  return List<Map<String, Object?>>.unmodifiable(maps);
}

int _maxDecodedCollectionEntriesToScan(int maxEntries) {
  return maxEntries * _maxDecodedCollectionScanMultiplier;
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
