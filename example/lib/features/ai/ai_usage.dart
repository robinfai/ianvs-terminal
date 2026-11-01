import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'ai_models.dart';

int _amount(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) throw const FormatException('Invalid usage');
  return value;
}

Map<String, Object?> _object(Object? value) =>
    (value! as Map).cast<String, Object?>();

class AiUsageSnapshot {
  AiUsageSnapshot.fromJson(Map<String, Object?> json)
    : purchasedRemaining = (json['purchased_remaining_nano_usd'] as int?) ?? 0,
      dailyRemaining =
          (json['daily_remaining_nano_usd'] as int?) ??
          _amount(json, 'remaining_nano_usd'),
      budget = _amount(json, 'daily_budget_nano_usd'),
      remaining = _amount(json, 'remaining_nano_usd'),
      spent = _amount(_object(json['usage']), 'spent_nano_usd'),
      reserved = _amount(_object(json['usage']), 'reserved_nano_usd'),
      input = _amount(_object(json['usage']), 'input_tokens'),
      cached = _amount(_object(json['usage']), 'cached_input_tokens'),
      output = _amount(_object(json['usage']), 'output_tokens'),
      pending = _amount(_object(json['usage']), 'pending_requests'),
      resetAt = DateTime.parse(json['reset_at']! as String);
  final int purchasedRemaining;
  final int dailyRemaining;
  final int budget;
  final int remaining;
  final int spent;
  final int reserved;
  final int input;
  final int cached;
  final int output;
  final int pending;
  final DateTime resetAt;
}

class AiUsageRecord {
  AiUsageRecord.fromJson(Map<String, Object?> json)
    : id = json['id']! as String,
      model = json['model']! as String,
      provider = json['provider']! as String,
      status = json['status']! as String,
      createdAt = DateTime.parse(json['created_at']! as String),
      spent = _amount(_object(json['usage']), 'spent_nano_usd'),
      reserved = _amount(json, 'reserved_nano_usd'),
      input = _amount(_object(json['usage']), 'input_tokens'),
      cached = _amount(_object(json['usage']), 'cached_input_tokens'),
      output = _amount(_object(json['usage']), 'output_tokens'),
      priceVersion =
          (_object(json['pricing_snapshot'])['version'] as String?) ?? '';
  final String id;
  final String model;
  final String provider;
  final String status;
  final String priceVersion;
  final DateTime createdAt;
  final int spent;
  final int reserved;
  final int input;
  final int cached;
  final int output;
}

class AiUsagePageData {
  const AiUsagePageData(this.records, this.nextCursor);
  factory AiUsagePageData.fromJson(Map<String, Object?> json) =>
      AiUsagePageData(
        (json['data']! as List)
            .map((value) => AiUsageRecord.fromJson(_object(value)))
            .toList(),
        json['next_cursor']! as String,
      );
  final List<AiUsageRecord> records;
  final String nextCursor;
}

abstract interface class AiUsageApi {
  Future<AiUsageSnapshot> usage();
  Future<AiUsagePageData> requests({String? before});
}

class AiUsageClient implements AiUsageApi {
  const AiUsageClient(this.configuration);
  final AiConfiguration configuration;
  Future<Map<String, Object?>> _get(String resource, {String? before}) async {
    final completions = configuration.completionsUri;
    final path = completions.path.replaceFirst(
      RegExp(r'/chat/completions$'),
      '/$resource',
    );
    final uri = completions.replace(
      path: path,
      queryParameters: before == null ? null : {'before': before},
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      return await (() async {
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${configuration.apiKey.trim()}',
        );
        final response = await request.close();
        if (response.statusCode != 200) {
          throw AiFailure(switch (response.statusCode) {
            401 || 403 => 'usage_authentication',
            404 || 503 => 'usage_unavailable',
            _ => 'usage_connection',
          });
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 1024 * 1024) {
            throw const AiFailure('usage_connection');
          }
          bytes.addAll(chunk);
        }
        return _object(jsonDecode(utf8.decode(bytes)));
      })().timeout(const Duration(seconds: 20));
    } on AiFailure {
      rethrow;
    } on Object {
      throw const AiFailure('usage_connection');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<AiUsageSnapshot> usage() async =>
      AiUsageSnapshot.fromJson(await _get('usage'));
  @override
  Future<AiUsagePageData> requests({String? before}) async =>
      AiUsagePageData.fromJson(await _get('requests', before: before));
}

/// One cache per signed-in backend identity; never persisted or reused across accounts.
class AiUsageController extends ChangeNotifier {
  AiUsageController(this.api);
  final AiUsageApi api;
  AiUsageSnapshot? snapshot;
  List<AiUsageRecord> records = [];
  String nextCursor = '';
  String? error;
  String? recordsError;
  bool loading = false;
  bool loadingRecords = false;
  bool _disposed = false;
  int _recordsEpoch = 0;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    if (_disposed || loading) return;
    loading = true;
    error = null;
    _notify();
    try {
      final result = await api.usage();
      if (!_disposed) snapshot = result;
    } on Object catch (failure) {
      if (!_disposed) {
        error = failure is AiFailure ? failure.code : 'usage_connection';
        if (error == 'usage_authentication') {
          snapshot = null;
          records = [];
          nextCursor = '';
          recordsError = error;
        }
      }
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> loadRecords({bool more = false}) async {
    if (_disposed || (more && (loadingRecords || nextCursor.isEmpty))) return;
    final epoch = ++_recordsEpoch;
    final cursor = more ? nextCursor : null;
    loadingRecords = true;
    recordsError = null;
    _notify();
    try {
      final page = await api.requests(before: cursor);
      if (_disposed || epoch != _recordsEpoch) return;
      records = more
          ? [
              ...records,
              ...page.records.where(
                (entry) => !records.any((existing) => existing.id == entry.id),
              ),
            ]
          : page.records;
      nextCursor = page.nextCursor;
    } on Object catch (failure) {
      if (!_disposed && epoch == _recordsEpoch) {
        recordsError = failure is AiFailure ? failure.code : 'usage_connection';
      }
    } finally {
      if (epoch == _recordsEpoch) {
        loadingRecords = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _recordsEpoch++;
    super.dispose();
  }
}

String aiQuotaPoints(int nanoUsd) {
  final whole = nanoUsd ~/ 2000;
  final fraction = ((nanoUsd % 2000) * 5)
      .toString()
      .padLeft(4, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole' : '$whole.$fraction';
}
