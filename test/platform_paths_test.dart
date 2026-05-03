import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/src/platform_paths.dart';

void main() {
  test('state directory follows platform-specific boundaries', () {
    expect(
      defaultTerminalStateDirectoryPath(
        environment: const <String, String>{'HOME': '/Users/robin'},
        operatingSystem: 'macos',
        currentPath: '/workspace',
      ),
      '/Users/robin/Library/Application Support/Ianvs/ianvs-terminal',
    );
    expect(
      defaultTerminalStateDirectoryPath(
        environment: const <String, String>{
          'APPDATA': r'C:\Users\Robin\AppData\Roaming',
        },
        operatingSystem: 'windows',
        currentPath: r'C:\workspace',
      ),
      r'C:\Users\Robin\AppData\Roaming\Ianvs\ianvs-terminal',
    );
    expect(
      defaultTerminalStateDirectoryPath(
        environment: const <String, String>{'HOME': '/home/robin'},
        operatingSystem: 'linux',
        currentPath: '/workspace',
      ),
      '/home/robin/.local/state/ianvs-terminal',
    );
    expect(
      defaultTerminalStateDirectoryPath(
        environment: const <String, String>{'HOME': '/tmp/robin'},
        operatingSystem: 'fuchsia',
        currentPath: '/workspace',
      ),
      '/tmp/robin/.ianvs-terminal',
    );
  });

  test('default file paths stay inside the shared state directory', () {
    expect(
      defaultTerminalSettingsFilePath(
        environment: const <String, String>{'HOME': '/Users/robin'},
        operatingSystem: 'macos',
        currentPath: '/workspace',
      ),
      '/Users/robin/Library/Application Support/Ianvs/ianvs-terminal/settings.json',
    );
    expect(
      defaultSavedCommandsFilePath(
        environment: const <String, String>{'HOME': '/Users/robin'},
        operatingSystem: 'macos',
        currentPath: '/workspace',
      ),
      '/Users/robin/Library/Application Support/Ianvs/ianvs-terminal/saved_commands.json',
    );
    expect(
      defaultTerminalSessionRestoreFilePath(
        environment: const <String, String>{'HOME': '/Users/robin'},
        operatingSystem: 'macos',
        currentPath: '/workspace',
      ),
      '/Users/robin/Library/Application Support/Ianvs/ianvs-terminal/session_restore.json',
    );
    expect(
      defaultShellIntegrationZdotdirPath(
        environment: const <String, String>{'HOME': '/Users/robin'},
        operatingSystem: 'macos',
        currentPath: '/workspace',
      ),
      '/Users/robin/Library/Application Support/Ianvs/ianvs-terminal/shell-integration/zsh',
    );
  });

  test('default home lookup respects non-macOS user directories', () {
    expect(
      defaultUserHomePath(
        environment: const <String, String>{'USERPROFILE': r'C:\Users\Robin'},
        operatingSystem: 'windows',
        currentPath: r'C:\workspace',
      ),
      r'C:\Users\Robin',
    );
    expect(
      defaultUserHomePath(
        environment: const <String, String>{},
        operatingSystem: 'linux',
        currentPath: '/workspace',
      ),
      '/workspace',
    );
  });
}
