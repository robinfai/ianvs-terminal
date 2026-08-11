import 'data_api_runtime.dart';

typedef DataApiFreshRuntimeBootstrap = Future<DataApiRuntime?> Function();

final class DataApiStartupRecoveryBusyException implements Exception {
  const DataApiStartupRecoveryBusyException();

  @override
  String toString() => 'Data API startup recovery is already running.';
}

/// Runs recovery work against a newly bootstrapped runtime and never exposes
/// that temporary runtime to the locked composition.
final class DataApiFreshRuntimeRunner {
  DataApiFreshRuntimeRunner({
    required DataApiRuntime? initialRuntime,
    required DataApiFreshRuntimeBootstrap bootstrap,
    this.closeTimeout = const Duration(seconds: 5),
  }) : _initialRuntime = initialRuntime,
       _bootstrap = bootstrap;

  final DataApiRuntime? _initialRuntime;
  final DataApiFreshRuntimeBootstrap _bootstrap;
  final Duration closeTimeout;
  var _running = false;

  Future<T> run<T>(
    Future<T> Function(DataApiRuntime? runtime) operation,
  ) async {
    if (_running) {
      throw const DataApiStartupRecoveryBusyException();
    }
    _running = true;
    try {
      final initialRuntime = _initialRuntime;
      if (initialRuntime?.isLocal == true) {
        await initialRuntime!.close().timeout(closeTimeout);
      }
      final runtime = await _bootstrap();
      try {
        return await operation(runtime);
      } finally {
        await runtime?.close().timeout(closeTimeout);
      }
    } finally {
      _running = false;
    }
  }
}
