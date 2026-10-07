import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../platform/development_secret_file.dart';
import '../../startup/app_environment.dart';
import 'ai_models.dart';

abstract interface class AiConfigurationStore {
  Future<AiConfiguration?> read();
  Future<void> write(AiConfiguration? configuration);
}

AiConfigurationStore createAiConfigurationStore({
  AppEnvironment? environment,
  Future<Directory> Function() appSupportDirectoryResolver =
      getApplicationSupportDirectory,
}) {
  final selectedEnvironment = environment ?? AppEnvironment.current;
  return selectedEnvironment == AppEnvironment.development
      ? DevelopmentAiConfigurationStore(
          directoryResolver: () async => selectedEnvironment.supportDirectory(
            await appSupportDirectoryResolver(),
          ),
        )
      : SecureAiConfigurationStore();
}

final class DevelopmentAiConfigurationStore implements AiConfigurationStore {
  DevelopmentAiConfigurationStore({
    required Future<Directory> Function() directoryResolver,
  }) : _file = DevelopmentSecretFile(
         directoryResolver: directoryResolver,
         name: 'ai-configuration.v1.json',
       );

  final DevelopmentSecretFile _file;

  @override
  Future<AiConfiguration?> read() async {
    final raw = await _file.read();
    return raw == null
        ? null
        : AiConfiguration.fromJson(
            (jsonDecode(raw) as Map).cast<String, Object?>(),
          );
  }

  @override
  Future<void> write(AiConfiguration? configuration) => _file.write(
    configuration == null ? null : jsonEncode(configuration.toJson()),
  );
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
    value?.validate();
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
  final controller = AiSettingsController(createAiConfigurationStore());
  ref.onDispose(controller.dispose);
  return controller;
});
