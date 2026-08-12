import 'local_terminal_config_bootstrap.dart';
import 'local_terminal_config_repository.dart';

class LocalTerminalConfigLoader {
  const LocalTerminalConfigLoader({required this.localConfigRepository});

  final TerminalConfigRepository localConfigRepository;

  Future<LocalTerminalConfigBootstrapResult> load() async {
    final localConfig = await localConfigRepository.loadVersioned();
    return LocalTerminalConfigBootstrap.resolve(
      localConfig: localConfig.value,
      localConfigRevision: localConfig.revision,
    );
  }
}
