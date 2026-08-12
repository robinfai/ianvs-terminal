import 'local_terminal_config_models.dart';

class LocalTerminalConfigBootstrapResult {
  const LocalTerminalConfigBootstrapResult({
    required this.config,
    required this.source,
    this.localConfigRevision,
  });

  final LocalTerminalConfigDocument config;
  final LocalTerminalConfigBootstrapSource source;
  final int? localConfigRevision;
}

enum LocalTerminalConfigBootstrapSource { localConfig, defaults }

class LocalTerminalConfigBootstrap {
  const LocalTerminalConfigBootstrap._();

  static LocalTerminalConfigBootstrapResult resolve({
    required LocalTerminalConfigDocument? localConfig,
    int? localConfigRevision,
  }) {
    if (localConfig != null) {
      return LocalTerminalConfigBootstrapResult(
        config: localConfig,
        source: LocalTerminalConfigBootstrapSource.localConfig,
        localConfigRevision: localConfigRevision,
      );
    }

    return LocalTerminalConfigBootstrapResult(
      config: const LocalTerminalConfigDocument(
        layout: LocalTerminalLayoutConfig(restoreLayout: true),
      ),
      source: LocalTerminalConfigBootstrapSource.defaults,
      localConfigRevision: localConfigRevision,
    );
  }
}
