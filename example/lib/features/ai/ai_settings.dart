import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/services/data_api_runtime.dart';
import '../../platform/development_secret_file.dart';
import '../../startup/app_environment.dart';
import 'ai_models.dart';
import 'ai_usage.dart';

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
  AiSettingsController(this.store, {AiConfiguration? gatewayConfiguration}) {
    _gatewayConfiguration = gatewayConfiguration;
    loaded = _load();
  }
  final AiConfigurationStore store;
  late final Future<void> loaded;
  AiConfiguration? _gatewayConfiguration;
  AiConfiguration? get gatewayConfiguration {
    final base = _gatewayConfiguration;
    final preference = _customConfiguration;
    if (base == null || preference?.officialService != true) return base;
    return AiConfiguration(
      endpoint: base.endpoint,
      apiKey: base.apiKey,
      model: preference!.model,
      approvalMode: preference.approvalMode,
      approvalSensitivity: preference.approvalSensitivity,
    );
  }

  String get officialModel => _customConfiguration?.officialService == true
      ? _customConfiguration!.model
      : 'default';
  AiApprovalMode get officialApprovalMode =>
      _customConfiguration?.officialService == true
      ? _customConfiguration!.approvalMode
      : _gatewayConfiguration?.approvalMode ?? AiApprovalMode.manual;
  AiApprovalSensitivity get officialApprovalSensitivity =>
      _customConfiguration?.officialService == true
      ? _customConfiguration!.approvalSensitivity
      : _gatewayConfiguration?.approvalSensitivity ??
            AiApprovalSensitivity.balanced;

  AiUsageController? _usage;
  AiUsageController? get usage => _usage ??= gatewayConfiguration == null
      ? null
      : AiUsageController(AiUsageClient(gatewayConfiguration!));

  void updateGatewayConfiguration(AiConfiguration? value) {
    if (_disposed ||
        (_gatewayConfiguration?.hasSameValues(value) ?? value == null)) {
      return;
    }
    _usage?.dispose();
    _usage = null;
    _gatewayConfiguration = value;
    notifyListeners();
  }

  AiConfiguration? _customConfiguration;
  AiConfiguration? get customConfiguration =>
      _customConfiguration?.officialService == true
      ? null
      : _customConfiguration;
  AiConfiguration? get configuration =>
      customConfiguration ?? gatewayConfiguration;
  set configuration(AiConfiguration? value) => _customConfiguration = value;
  bool get usesGateway =>
      customConfiguration == null && gatewayConfiguration != null;
  bool loading = true;
  String? error;
  bool _disposed = false;

  /// A local, valid LLM configuration is enough; no network request is needed.
  bool get hasLlmConfiguration {
    final value = configuration;
    if (loading || error != null || value?.backend != AiBackendKind.llm) {
      return false;
    }
    try {
      value!.validate();
      return true;
    } on AiFailure {
      return false;
    }
  }

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
    _usage?.dispose();
    super.dispose();
  }
}

final aiConfigurationStoreProvider = Provider<AiConfigurationStore>(
  (ref) => createAiConfigurationStore(),
);

AiConfiguration? _gatewayConfiguration(DataApiRuntime? runtime) =>
    runtime?.canAccessResources == true
    ? AiConfiguration(
        endpoint: runtime!.baseUri.resolve('/v1/ai').toString(),
        apiKey: runtime.resourceAccessToken!,
        model: 'default',
      )
    : null;

final aiSettingsProvider = Provider<AiSettingsController>((ref) {
  // Existing SSH/AI sessions retain this controller. Runtime refreshes must
  // update it in place instead of leaving those sessions with a disposed copy.
  final source = ref.watch(dataApiRuntimeSourceProvider);
  final controller = AiSettingsController(
    ref.read(aiConfigurationStoreProvider),
    gatewayConfiguration: _gatewayConfiguration(
      source == null ? ref.read(dataApiRuntimeProvider) : source.value,
    ),
  );
  if (source != null) {
    // Settings and live AI sessions retain the controller via ref.read. Keep
    // credentials fresh even while Riverpod has no active UI subscribers.
    void refresh() => controller.updateGatewayConfiguration(
      _gatewayConfiguration(source.value),
    );
    source.addListener(refresh);
    ref.onDispose(() => source.removeListener(refresh));
  } else {
    ref.listen<DataApiRuntime?>(dataApiRuntimeProvider, (_, runtime) {
      controller.updateGatewayConfiguration(_gatewayConfiguration(runtime));
    });
  }
  ref.onDispose(controller.dispose);
  return controller;
});
