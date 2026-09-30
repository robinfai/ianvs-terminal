import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai_models.dart';

abstract interface class AiConfigurationStore {
  Future<AiConfiguration?> read();
  Future<void> write(AiConfiguration? configuration);
}

class SecureAiConfigurationStore implements AiConfigurationStore {
  SecureAiConfigurationStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );
  final FlutterSecureStorage _storage;
  static const storageKey = 'trail.ai.configuration.v1';

  @override
  Future<AiConfiguration?> read() async {
    final raw = await _storage.read(key: storageKey);
    return raw == null
        ? null
        : AiConfiguration.fromJson(
            (jsonDecode(raw) as Map).cast<String, Object?>(),
          );
  }

  @override
  Future<void> write(AiConfiguration? configuration) => configuration == null
      ? _storage.delete(key: storageKey)
      : _storage.write(
          key: storageKey,
          value: jsonEncode(configuration.toJson()),
        );
}

class AiSettingsController extends ChangeNotifier {
  AiSettingsController(this.store) {
    loaded = _load();
  }
  final AiConfigurationStore store;
  late final Future<void> loaded;
  AiConfiguration? configuration;
  bool loading = true;
  String? error;
  bool _disposed = false;

  Future<void> _load() async {
    try {
      configuration = await store.read();
    } on Object catch (_) {
      error = 'storage';
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> save(AiConfiguration? value) async {
    await loaded;
    value?.completionsUri;
    try {
      await store.write(value);
    } on Object catch (_) {
      throw const AiFailure('storage');
    }
    if (_disposed) return;
    configuration = value;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final aiSettingsProvider = Provider<AiSettingsController>((ref) {
  final controller = AiSettingsController(SecureAiConfigurationStore());
  ref.onDispose(controller.dispose);
  return controller;
});
