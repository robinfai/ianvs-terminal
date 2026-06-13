import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:app/features/productivity/command_blocks_history_feature_flags.dart';
import 'package:app/features/productivity/shell_command_block_controller.dart';
import 'package:app/features/productivity/shell_productivity_models.dart';
import 'package:app/features/shell/shell_command_block_view_models.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

void main() {
  test(
    'real PTY readonly commands flow into command block output',
    () async {
      final libraryPath = _workspaceCoreLibraryPath!;
      final backend = NativePtyBackend.fromBindings(
        NativePtyBindings(ffi.DynamicLibrary.open(libraryPath)),
      );
      final home = Directory.systemTemp.createTempSync('ianvs-pty-home-');
      final cwd = Directory.systemTemp.createTempSync('ianvs-pty-cwd-');
      addTearDown(() {
        if (home.existsSync()) {
          home.deleteSync(recursive: true);
        }
        if (cwd.existsSync()) {
          cwd.deleteSync(recursive: true);
        }
      });
      File(
        '${home.path}/.zshrc',
      ).writeAsStringSync("PROMPT='%~ % '\nalias ll='ls -la'\n");
      File('${cwd.path}/alpha.txt').writeAsStringSync('alpha-one\nalpha-two\n');
      File('${cwd.path}/beta.txt').writeAsStringSync('beta-one\n');

      final sessionId = backend.createSession(
        jsonEncode(<String, Object?>{
          'id': 'real-pty-command-block',
          'name': 'Real PTY Command Block',
          ...terminal.TerminalSessionConfig(
            launch: terminal.TerminalLaunchConfig(
              program: '/bin/zsh',
              env: <String, String>{'HOME': home.path, 'ZDOTDIR': home.path},
              cwd: cwd.path,
            ),
            scrollbackLines: 1000,
          ).toJson(),
        }),
      );
      addTearDown(() => backend.closeSession(sessionId));
      backend.resizeSession(
        sessionId,
        cols: 120,
        rows: 48,
        pixelWidth: 1200,
        pixelHeight: 960,
      );

      final harness = _RealPtyCommandBlockHarness(
        backend: backend,
        sessionId: sessionId,
      );
      await harness.waitForStartup();

      await harness.runAndExpectOutput(
        command: 'pwd',
        expectedOutput: cwd.resolveSymbolicLinksSync(),
      );
      await harness.runAndExpectOutput(
        command: 'ls -1',
        expectedOutput: 'alpha.txt',
      );
      await harness.runAndExpectOutput(
        command: 'cat alpha.txt',
        expectedOutput: 'alpha-two',
      );
      await harness.runAndExpectOutput(
        command: 'll',
        expectedOutput: 'alpha.txt',
      );
    },
    skip: _workspaceCoreLibraryPath == null
        ? 'libianvs_core.dylib is unavailable for this test run.'
        : false,
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'real PTY long command output stays rendered in command block',
    () async {
      final libraryPath = _workspaceCoreLibraryPath!;
      final backend = NativePtyBackend.fromBindings(
        NativePtyBindings(ffi.DynamicLibrary.open(libraryPath)),
      );
      final home = Directory.systemTemp.createTempSync('ianvs-pty-home-');
      final cwd = Directory.systemTemp.createTempSync('ianvs-pty-cwd-');
      addTearDown(() {
        if (home.existsSync()) {
          home.deleteSync(recursive: true);
        }
        if (cwd.existsSync()) {
          cwd.deleteSync(recursive: true);
        }
      });
      File(
        '${home.path}/.zshrc',
      ).writeAsStringSync("PROMPT='%~ % '\nalias ll='ls -lhF'\n");
      for (var index = 0; index < 45; index += 1) {
        File(
          '${cwd.path}/file-${index.toString().padLeft(2, '0')}.txt',
        ).writeAsStringSync('row-$index\n');
      }

      final sessionId = backend.createSession(
        jsonEncode(<String, Object?>{
          'id': 'real-pty-command-block-long-output',
          'name': 'Real PTY Command Block Long Output',
          ...terminal.TerminalSessionConfig(
            launch: terminal.TerminalLaunchConfig(
              program: '/bin/zsh',
              env: <String, String>{'HOME': home.path, 'ZDOTDIR': home.path},
              cwd: cwd.path,
            ),
            scrollbackLines: 1000,
          ).toJson(),
        }),
      );
      addTearDown(() => backend.closeSession(sessionId));
      backend.resizeSession(
        sessionId,
        cols: 93,
        rows: 20,
        pixelWidth: 930,
        pixelHeight: 400,
      );

      final harness = _RealPtyCommandBlockHarness(
        backend: backend,
        sessionId: sessionId,
      );
      await harness.waitForStartup();

      await harness.runAndExpectOutput(
        command: 'll',
        expectedOutput: 'file-44.txt',
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      harness.pump();

      expect(harness.latestOutputFor('ll'), contains('file-44.txt'));
    },
    skip: _workspaceCoreLibraryPath == null
        ? 'libianvs_core.dylib is unavailable for this test run.'
        : false,
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'real PTY alias output stays rendered after later commands',
    () async {
      final libraryPath = _workspaceCoreLibraryPath!;
      final backend = NativePtyBackend.fromBindings(
        NativePtyBindings(ffi.DynamicLibrary.open(libraryPath)),
      );
      final home = Directory.systemTemp.createTempSync('ianvs-pty-home-');
      final cwd = Directory.systemTemp.createTempSync('ianvs-pty-cwd-');
      addTearDown(() {
        if (home.existsSync()) {
          home.deleteSync(recursive: true);
        }
        if (cwd.existsSync()) {
          cwd.deleteSync(recursive: true);
        }
      });
      File(
        '${home.path}/.zshrc',
      ).writeAsStringSync("PROMPT='~ > '\nalias ll='ls -la'\n");
      File('${cwd.path}/.hidden-file').writeAsStringSync('hidden\n');
      for (var index = 0; index < 55; index += 1) {
        File(
          '${cwd.path}/file-${index.toString().padLeft(2, '0')}.txt',
        ).writeAsStringSync('row-$index\n');
      }

      final sessionId = backend.createSession(
        jsonEncode(<String, Object?>{
          'id': 'real-pty-command-block-alias-sequence',
          'name': 'Real PTY Command Block Alias Sequence',
          ...terminal.TerminalSessionConfig(
            launch: terminal.TerminalLaunchConfig(
              program: '/bin/zsh',
              env: <String, String>{
                'HOME': home.path,
                'ZDOTDIR': home.path,
                'LC_ALL': 'C',
              },
              cwd: cwd.path,
            ),
            scrollbackLines: 1000,
          ).toJson(),
        }),
      );
      addTearDown(() => backend.closeSession(sessionId));
      backend.resizeSession(
        sessionId,
        cols: 112,
        rows: 40,
        pixelWidth: 1120,
        pixelHeight: 800,
      );

      final harness = _RealPtyCommandBlockHarness(
        backend: backend,
        sessionId: sessionId,
      );
      await harness.waitForStartup();

      await harness.runAndExpectOutput(
        command: 'ls',
        expectedOutput: 'file-54.txt',
      );
      await harness.runAndExpectOutput(
        command: 'll',
        expectedOutput: 'file-54.txt',
      );
      await harness.runAndExpectOutput(
        command: 'pwd',
        expectedOutput: cwd.resolveSymbolicLinksSync(),
      );
      await harness.runAndExpectOutput(
        command: 'echo 123',
        expectedOutput: '123',
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      harness.pump();

      printOnFailure(harness.describeBlocks());

      final llOutput = harness.latestOutputFor('ll');
      expect(llOutput, contains('-rw-r--r--'));
      expect(llOutput, contains('file-54.txt'));
      expect(llOutput, isNot(contains(cwd.resolveSymbolicLinksSync())));
      expect(llOutput, isNot(contains('123')));

      expect(
        harness.latestOutputFor('pwd'),
        contains(cwd.resolveSymbolicLinksSync()),
      );
      expect(harness.latestOutputFor('echo 123').trim(), '123');
    },
    skip: _workspaceCoreLibraryPath == null
        ? 'libianvs_core.dylib is unavailable for this test run.'
        : false,
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'real PTY command outputs stay attached to their own command blocks',
    () async {
      final libraryPath = _workspaceCoreLibraryPath!;
      final backend = NativePtyBackend.fromBindings(
        NativePtyBindings(ffi.DynamicLibrary.open(libraryPath)),
      );
      final home = Directory.systemTemp.createTempSync('ianvs-pty-home-');
      final cwd = Directory.systemTemp.createTempSync('ianvs-pty-cwd-');
      addTearDown(() {
        if (home.existsSync()) {
          home.deleteSync(recursive: true);
        }
        if (cwd.existsSync()) {
          cwd.deleteSync(recursive: true);
        }
      });
      File('${home.path}/.zshrc').writeAsStringSync("PROMPT='%~ % '\n");
      File('${cwd.path}/alpha.txt').writeAsStringSync('alpha\n');
      File('${cwd.path}/.hidden-file').writeAsStringSync('hidden\n');
      final downloads = Directory('${cwd.path}/Downloads')..createSync();
      for (var index = 0; index < 35; index += 1) {
        File(
          '${downloads.path}/download-${index.toString().padLeft(2, '0')}.txt',
        ).writeAsStringSync('download-$index\n');
      }

      final sessionId = backend.createSession(
        jsonEncode(<String, Object?>{
          'id': 'real-pty-command-block-sequence',
          'name': 'Real PTY Command Block Sequence',
          ...terminal.TerminalSessionConfig(
            launch: terminal.TerminalLaunchConfig(
              program: '/bin/zsh',
              env: <String, String>{
                'HOME': home.path,
                'ZDOTDIR': home.path,
                'LC_ALL': 'C',
              },
              cwd: cwd.path,
            ),
            scrollbackLines: 1000,
          ).toJson(),
        }),
      );
      addTearDown(() => backend.closeSession(sessionId));
      backend.resizeSession(
        sessionId,
        cols: 80,
        rows: 12,
        pixelWidth: 800,
        pixelHeight: 240,
      );

      final harness = _RealPtyCommandBlockHarness(
        backend: backend,
        sessionId: sessionId,
      );
      await harness.waitForStartup();

      await harness.runAndExpectOutput(
        command: 'ls',
        expectedOutput: 'alpha.txt',
      );
      await harness.runAndExpectOutput(
        command: 'ls MissingDir',
        expectedOutput: 'No such file',
      );
      await harness.runAndExpectOutput(
        command: 'ls Downloads',
        expectedOutput: 'download-34.txt',
      );
      await harness.runAndExpectOutput(
        command: 'ls -la',
        expectedOutput: '.hidden-file',
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      harness.pump();

      printOnFailure(harness.describeBlocks());

      final lsOutput = harness.latestOutputFor('ls');
      expect(lsOutput, contains('alpha.txt'));
      expect(lsOutput, isNot(contains('download-34.txt')));
      expect(lsOutput, isNot(contains('No such file')));

      final missingOutput = harness.latestOutputFor('ls MissingDir');
      expect(_nonEmptyLines(missingOutput).first, contains('No such file'));
      expect(missingOutput, contains('No such file'));
      expect(missingOutput, isNot(contains('download-34.txt')));

      final downloadsOutput = harness.latestOutputFor('ls Downloads');
      expect(
        _nonEmptyLines(downloadsOutput).first,
        contains('download-00.txt'),
      );
      expect(downloadsOutput, contains('download-34.txt'));
      expect(downloadsOutput, isNot(contains('.hidden-file')));

      final longOutput = harness.latestOutputFor('ls -la');
      expect(_nonEmptyLines(longOutput).first.trimLeft(), startsWith('total'));
      expect(longOutput, contains('.hidden-file'));
      expect(longOutput, contains('alpha.txt'));
    },
    skip: _workspaceCoreLibraryPath == null
        ? 'libianvs_core.dylib is unavailable for this test run.'
        : false,
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'real PTY short command output replaces stale submitted rows',
    () async {
      final libraryPath = _workspaceCoreLibraryPath!;
      final backend = NativePtyBackend.fromBindings(
        NativePtyBindings(ffi.DynamicLibrary.open(libraryPath)),
      );
      final home = Directory.systemTemp.createTempSync('ianvs-pty-home-');
      final cwd = Directory.systemTemp.createTempSync('ianvs-pty-cwd-');
      addTearDown(() {
        if (home.existsSync()) {
          home.deleteSync(recursive: true);
        }
        if (cwd.existsSync()) {
          cwd.deleteSync(recursive: true);
        }
      });
      File(
        '${home.path}/.zshrc',
      ).writeAsStringSync("PROMPT='~ > '\nll() { print LL-OUTPUT; }\n");
      File('${cwd.path}/alpha.txt').writeAsStringSync('alpha\n');
      File('${cwd.path}/beta.txt').writeAsStringSync('beta\n');

      final sessionId = backend.createSession(
        jsonEncode(<String, Object?>{
          'id': 'real-pty-command-block-stale-submitted',
          'name': 'Real PTY Command Block Stale Submitted',
          ...terminal.TerminalSessionConfig(
            launch: terminal.TerminalLaunchConfig(
              program: '/bin/zsh',
              env: <String, String>{'HOME': home.path, 'ZDOTDIR': home.path},
              cwd: cwd.path,
            ),
            scrollbackLines: 1000,
          ).toJson(),
        }),
      );
      addTearDown(() => backend.closeSession(sessionId));
      backend.resizeSession(
        sessionId,
        cols: 160,
        rows: 18,
        pixelWidth: 1600,
        pixelHeight: 360,
      );

      final harness = _RealPtyCommandBlockHarness(
        backend: backend,
        sessionId: sessionId,
      );
      await harness.waitForStartup();

      await harness.runAndExpectOutput(
        command: 'ls',
        expectedOutput: 'alpha.txt',
      );
      await harness.runAndExpectOutput(
        command: 'll',
        expectedOutput: 'LL-OUTPUT',
      );
      await harness.runAndExpectOutput(
        command: 'pwd',
        expectedOutput: cwd.resolveSymbolicLinksSync(),
      );
      await harness.runAndExpectOutput(
        command: 'echo 123',
        expectedOutput: '123',
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      harness.pump();

      printOnFailure(harness.describeBlocks());

      final lsOutput = harness.latestOutputFor('ls');
      expect(lsOutput, contains('alpha.txt'));
      expect(lsOutput, isNot(contains('LL-OUTPUT')));
      expect(lsOutput, isNot(contains(cwd.resolveSymbolicLinksSync())));

      final llOutput = harness.latestOutputFor('ll');
      expect(llOutput, contains('LL-OUTPUT'));
      expect(llOutput, isNot(contains('alpha.txt')));
      expect(llOutput, isNot(contains(cwd.resolveSymbolicLinksSync())));

      final pwdOutput = harness.latestOutputFor('pwd');
      expect(pwdOutput, contains(cwd.resolveSymbolicLinksSync()));
      expect(pwdOutput, isNot(contains('alpha.txt')));
      expect(pwdOutput, isNot(contains('LL-OUTPUT')));

      final echoOutput = harness.latestOutputFor('echo 123');
      expect(echoOutput.trim(), '123');
      expect(echoOutput, isNot(contains('alpha.txt')));
      expect(echoOutput, isNot(contains('LL-OUTPUT')));
    },
    skip: _workspaceCoreLibraryPath == null
        ? 'libianvs_core.dylib is unavailable for this test run.'
        : false,
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'real PTY bash readline interaction exposes a running command block',
    () async {
      final libraryPath = _workspaceCoreLibraryPath!;
      final bashPath = _bashPath!;
      final backend = NativePtyBackend.fromBindings(
        NativePtyBindings(ffi.DynamicLibrary.open(libraryPath)),
      );
      final home = Directory.systemTemp.createTempSync('ianvs-pty-bash-home-');
      final cwd = Directory.systemTemp.createTempSync('ianvs-pty-bash-cwd-');
      addTearDown(() {
        if (home.existsSync()) {
          home.deleteSync(recursive: true);
        }
        if (cwd.existsSync()) {
          cwd.deleteSync(recursive: true);
        }
      });
      File('${home.path}/.bashrc').writeAsStringSync('''
PS1='PROMPT-XYZ> '
ianvs_readline_probe() {
  local answer
  read -e -p 'Name: ' answer
  printf 'ANSWER=%s\\n' "\$answer"
}
''');

      final sessionId = backend.createSession(
        jsonEncode(<String, Object?>{
          'id': 'real-pty-command-block-bash-readline',
          'name': 'Real PTY Bash Readline Command Block',
          ...terminal.TerminalSessionConfig(
            launch: terminal.TerminalLaunchConfig(
              program: bashPath,
              env: <String, String>{
                'HOME': home.path,
                'INPUTRC': '/dev/null',
                'BASH_SILENCE_DEPRECATION_WARNING': '1',
              },
              cwd: cwd.path,
            ),
            scrollbackLines: 1000,
          ).toJson(),
        }),
      );
      addTearDown(() => backend.closeSession(sessionId));
      backend.resizeSession(
        sessionId,
        cols: 120,
        rows: 24,
        pixelWidth: 1200,
        pixelHeight: 480,
      );

      final harness = _RealPtyCommandBlockHarness(
        backend: backend,
        sessionId: sessionId,
      );
      await harness.waitForStartup();

      const command = 'ianvs_readline_probe';
      await harness.startAndExpectRunning(
        command: command,
        expectedFrameText: 'Name:',
      );

      final running = harness.latestBlockForCommand(command);
      expect(running, isNotNull);
      expect(running!.status, ShellCommandBlockStatus.running);
      expect(running.command, command);

      harness.writeInput('codex\n');
      await harness.waitForFinishedOutput(
        command: command,
        expectedOutput: 'ANSWER=codex',
      );

      final finished = harness.latestBlockForCommand(command);
      expect(finished, isNotNull);
      expect(finished!.id, running.id);
      expect(finished.status, ShellCommandBlockStatus.succeeded);
      expect(harness.latestOutputFor(command), contains('ANSWER=codex'));
    },
    skip: _workspaceCoreLibraryPath == null
        ? 'libianvs_core.dylib is unavailable for this test run.'
        : _bashPath == null
        ? '/bin/bash is unavailable for this test run.'
        : false,
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'real PTY vi after ls enters alternate screen instead of command block live output',
    () async {
      final libraryPath = _workspaceCoreLibraryPath!;
      final backend = NativePtyBackend.fromBindings(
        NativePtyBindings(ffi.DynamicLibrary.open(libraryPath)),
      );
      final home = Directory.systemTemp.createTempSync('ianvs-pty-vi-home-');
      final cwd = Directory.systemTemp.createTempSync('ianvs-pty-vi-cwd-');
      addTearDown(() {
        if (home.existsSync()) {
          home.deleteSync(recursive: true);
        }
        if (cwd.existsSync()) {
          cwd.deleteSync(recursive: true);
        }
      });
      File('${home.path}/.zshrc').writeAsStringSync("PROMPT='%~ % '\n");
      File('${cwd.path}/public.key').writeAsStringSync('ssh-rsa test-key\n');

      final sessionId = backend.createSession(
        jsonEncode(<String, Object?>{
          'id': 'real-pty-command-block-vi-after-ls',
          'name': 'Real PTY Command Block Vi After Ls',
          ...terminal.TerminalSessionConfig(
            launch: terminal.TerminalLaunchConfig(
              program: '/bin/zsh',
              env: <String, String>{
                'HOME': home.path,
                'ZDOTDIR': home.path,
                'VIMINIT': '',
                'EXINIT': '',
              },
              cwd: cwd.path,
            ),
            scrollbackLines: 1000,
          ).toJson(),
        }),
      );
      addTearDown(() => backend.closeSession(sessionId));
      backend.resizeSession(
        sessionId,
        cols: 120,
        rows: 24,
        pixelWidth: 1200,
        pixelHeight: 480,
      );

      final harness = _RealPtyCommandBlockHarness(
        backend: backend,
        sessionId: sessionId,
      );
      await harness.waitForStartup();

      await harness.runAndExpectOutput(
        command: 'ls -1',
        expectedOutput: 'public.key',
      );

      const command = 'vi public.key';
      await harness.startAndExpectRunning(
        command: command,
        expectedFrameText: 'test-key',
      );
      await harness.waitForAlternateScreen(
        failureMessage: 'vi after ls did not enter alternate screen',
      );

      final running = harness.latestBlockForCommand(command);
      expect(running, isNotNull);
      expect(running!.status, ShellCommandBlockStatus.running);
      expect(harness.frameModes.alternateScreen, isTrue);
      expect(
        shellCommandBlocksShouldUseNativeTerminal(
          modes: harness.frameModes,
          nativeTerminalBlockId: running.id,
        ),
        isTrue,
      );

      harness.writeInput(':q!\n');
      await harness.waitForFinishedCommand(command: command);
      await harness.waitForPrimaryScreen(
        failureMessage: 'vi after ls did not return to primary screen',
      );
      expect(harness.frameModes.alternateScreen, isFalse);

      await harness.runAndExpectOutput(
        command: 'ls -1',
        expectedOutput: 'public.key',
      );
      final commandsAfterVi = harness.commandsAfter(command);
      expect(
        commandsAfterVi,
        isNot(
          contains(
            predicate<String>(
              (command) =>
                  command.contains('rgb:') ||
                  command.contains(r'$y') ||
                  command.contains('2R1R82') ||
                  command.contains('10000'),
            ),
          ),
        ),
      );
      expect(harness.describeBlocks(), isNot(contains('command not found')));
    },
    skip: _workspaceCoreLibraryPath == null
        ? 'libianvs_core.dylib is unavailable for this test run.'
        : false,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

class _RealPtyCommandBlockHarness {
  _RealPtyCommandBlockHarness({required this.backend, required this.sessionId});

  static const _flags = CommandBlocksHistoryFeatureFlags(
    enabled: true,
    commandBlocks: true,
    historyPeek: true,
    failureSnapshots: true,
    reviewWorkspaceEntrypoints: true,
    outputDiff: true,
  );

  final PtySessionBackend backend;
  final String sessionId;

  final terminal.TerminalViewportController _viewportController =
      terminal.TerminalViewportController();
  terminal.TerminalFrameDiff? _frame;
  ShellCommandBlockSnapshot _snapshot = const ShellCommandBlockSnapshot();
  final Map<String, List<terminal.TerminalRow>> _capturedRowsByBlockId =
      <String, List<terminal.TerminalRow>>{};
  final Map<String, int> _finishedTargets = <String, int>{};
  final Map<String, _SubmittedCapture> _submittedCaptures =
      <String, _SubmittedCapture>{};

  Future<void> waitForStartup() async {
    await _waitUntil(() {
      pump();
      return _snapshot.currentCwd != null;
    });
  }

  Future<void> runAndExpectOutput({
    required String command,
    required String expectedOutput,
  }) async {
    _recordSubmittedCapture(command);
    backend.writeInput(sessionId, utf8.encode('$command\n'));
    await _waitUntil(() {
      pump();
      return latestOutputFor(command).contains(expectedOutput);
    }, failureMessage: 'command "$command" did not capture "$expectedOutput"');
  }

  Future<void> startAndExpectRunning({
    required String command,
    required String expectedFrameText,
  }) async {
    _recordSubmittedCapture(command);
    backend.writeInput(sessionId, utf8.encode('$command\n'));
    await _waitUntil(() {
      pump();
      final block = _latestBlockFor(command);
      if (block == null || block.status != ShellCommandBlockStatus.running) {
        return false;
      }
      final frameText = _frame?.rows.map((row) => row.text).join('\n') ?? '';
      return frameText.contains(expectedFrameText) ||
          latestOutputFor(command).contains(expectedFrameText);
    }, failureMessage: 'command "$command" did not reach running state');
  }

  void writeInput(String text) {
    backend.writeInput(sessionId, utf8.encode(text));
  }

  Future<void> waitForFinishedOutput({
    required String command,
    required String expectedOutput,
  }) async {
    await _waitUntil(
      () {
        pump();
        final block = _latestBlockFor(command);
        return block != null &&
            block.status != ShellCommandBlockStatus.running &&
            latestOutputFor(command).contains(expectedOutput);
      },
      failureMessage:
          'command "$command" did not finish with "$expectedOutput"',
    );
  }

  Future<void> waitForFinishedCommand({required String command}) async {
    await _waitUntil(() {
      pump();
      final block = _latestBlockFor(command);
      return block != null && block.status != ShellCommandBlockStatus.running;
    }, failureMessage: 'command "$command" did not finish');
  }

  ShellCommandBlock? latestBlockForCommand(String command) {
    return _latestBlockFor(command);
  }

  List<String> commandsAfter(String command) {
    var seen = false;
    final commands = <String>[];
    for (final block in _snapshot.blocks) {
      if (seen) {
        commands.add(block.command);
      }
      if (block.command == command) {
        seen = true;
      }
    }
    return commands;
  }

  terminal.TerminalFrameModes get frameModes =>
      _frame?.modes ?? terminal.TerminalFrameModes.empty;

  Future<void> waitForAlternateScreen({
    String failureMessage = 'alternate screen was not entered',
  }) async {
    await _waitUntil(() {
      pump();
      return frameModes.alternateScreen;
    }, failureMessage: failureMessage);
  }

  Future<void> waitForPrimaryScreen({
    String failureMessage = 'primary screen was not restored',
  }) async {
    await _waitUntil(() {
      pump();
      return !frameModes.alternateScreen;
    }, failureMessage: failureMessage);
  }

  void _recordSubmittedCapture(String command) {
    pump();
    final commandRow = _submittedCommandRowForFrame(_frame);
    if (commandRow == null) {
      return;
    }
    _finishedTargets.clear();
    _submittedCaptures[command] = _SubmittedCapture(
      commandRow: commandRow,
      submittedAt: DateTime.now(),
    );
  }

  void pump() {
    final rawFrame = backend.takeFrameDiffJson(sessionId);
    if (rawFrame != null && rawFrame.isNotEmpty) {
      final decoded = jsonDecode(rawFrame);
      if (decoded is Map<String, Object?>) {
        _viewportController.updateFrame(
          terminal.TerminalFrameDiff.fromJson(decoded),
        );
        _frame = _viewportController.frame;
        _captureSubmittedRows();
        _captureFinishedTargets();
        _captureVisibleRows();
      }
    }

    for (final event in backend.pollEvents(sessionId)) {
      if (event.kind != 'shell_hook') {
        continue;
      }
      final hook = terminal.TerminalSessionShellHookEvent(
        sessionId,
        rawPayload: event.payload,
      );
      _recordShellHook(hook);
      if (hook.hook == 'command_finished') {
        final block = _snapshot.blocks.isEmpty ? null : _snapshot.blocks.last;
        if (block != null && block.isValid) {
          _captureSubmittedRowsForBlock(block);
          _finishedTargets[block.id] = block.outputRange.commandRow;
        }
      }
      _captureFinishedTargets();
    }
  }

  String latestOutputFor(String command) {
    final block = _latestBlockFor(command);
    if (block == null) {
      return '';
    }
    final viewModel = _viewModel();
    for (final item in viewModel.blocks) {
      if (item.id != block.id) {
        continue;
      }
      return item.terminalRows.map((row) => row.text).join('\n');
    }
    return '';
  }

  String describeBlocks() {
    final buffer = StringBuffer();
    buffer.writeln('blocks:');
    for (final block in _snapshot.blocks) {
      final rows =
          _capturedRowsByBlockId[block.id] ?? const <terminal.TerminalRow>[];
      buffer.writeln(
        '${block.id} command=${block.command} '
        'status=${block.status.name} '
        'range=${block.outputRange.commandRow}:'
        '${block.outputRange.outputStartRow}-${block.outputRange.outputEndRow} '
        'rows=${rows.map((row) => row.text).join(' / ')}',
      );
    }
    final frame = _frame;
    if (frame != null) {
      buffer.writeln(
        'frame viewport=${frame.viewportStartRow}+${frame.viewportRows} '
        'rows=${frame.rows.map((row) => '${row.index}:${row.text}').join(' / ')}',
      );
    }
    return buffer.toString();
  }

  void _captureSubmittedRows() {
    final frame = _frame;
    if (frame == null || _submittedCaptures.isEmpty) {
      return;
    }
    for (final entry in _submittedCaptures.entries.toList(growable: false)) {
      final rows = shellCommandBlockSubmittedPreviewRowsForFrame(
        command: entry.key,
        commandRow: entry.value.commandRow,
        submittedAt: entry.value.submittedAt,
        frame: frame,
      );
      if (rows.isEmpty) {
        continue;
      }
      _submittedCaptures[entry.key] = entry.value.copyWith(rows: rows);
    }
  }

  void _captureSubmittedRowsForBlock(ShellCommandBlock block) {
    final submitted = _submittedCaptures.remove(block.command);
    if (submitted == null || submitted.rows.isEmpty) {
      return;
    }
    final rows = shellCommandBlockOutputRowsFrom(block, submitted.rows);
    if (rows.isNotEmpty) {
      _capturedRowsByBlockId[block.id] = rows;
    }
  }

  void _recordShellHook(terminal.TerminalSessionShellHookEvent event) {
    final frame = _frame ?? terminal.TerminalFrameDiff.empty;
    final commandText = event.command?.trim();
    final submitted = commandText == null || commandText.isEmpty
        ? null
        : _submittedCaptures[commandText];
    final normalizedHook = ShellCommandBlockShellHookReducer.normalizeHook(
      event.hook,
    );
    final preexecSubmittedCommandRow = normalizedHook == 'preexec'
        ? submitted?.commandRow
        : null;
    final shellHookPromptScrollbackOffset = normalizedHook == 'precmd'
        ? event.promptScrollbackOffset ??
              shellCommandBlockPromptRowForFrame(frame)
        : event.promptScrollbackOffset;
    _snapshot = ShellCommandBlockShellHookReducer.reduce(
      snapshot: _snapshot,
      flags: _flags,
      sessionId: sessionId,
      hook: event.hook,
      command: event.command,
      cwd: event.cwd,
      exitCode: event.exitCode,
      promptScrollbackOffset:
          preexecSubmittedCommandRow ?? shellHookPromptScrollbackOffset,
      commandStartRow:
          submitted?.commandRow ??
          shellCommandBlockCommandStartRowForFrame(
            frame,
            command: event.command,
          ),
      viewportEndRow: shellCommandBlockVisibleViewportEndRow(
        viewportStartRow: frame.viewportStartRow,
        viewportRows: frame.viewportRows,
      ),
    );
  }

  void _captureFinishedTargets() {
    final frame = _frame;
    if (frame == null || _finishedTargets.isEmpty || _snapshot.blocks.isEmpty) {
      return;
    }
    if (_submittedCaptures.isNotEmpty) {
      return;
    }
    final latestBlockId = _snapshot.blocks.last.id;
    final removeTargetIds = <String>[];
    for (final entry in _finishedTargets.entries) {
      final block = _blockById(entry.key);
      if (block == null) {
        removeTargetIds.add(entry.key);
        continue;
      }
      final endPromptRow = _finishedTargetEndPromptRow(entry.value);
      final rows = _rowsAfterCommandRow(
        frame,
        entry.value,
        endPromptRow: endPromptRow,
      );
      final capture = shellCommandBlockFinishedPreviewCaptureForRows(
        block: block,
        rows: rows,
        isLatestBlock: entry.key == latestBlockId,
      );
      if (capture.rows.isNotEmpty) {
        _mergeCapturedRows(entry.key, capture.rows);
      }
      if (capture.removeTarget ||
          shellCommandBlockFrameReachedPromptBoundary(
            frame: frame,
            endPromptRow: endPromptRow,
          )) {
        removeTargetIds.add(entry.key);
      }
    }
    for (final id in removeTargetIds) {
      _finishedTargets.remove(id);
    }
  }

  void _captureVisibleRows() {
    final frame = _frame;
    if (frame == null || _snapshot.blocks.isEmpty) {
      return;
    }
    if (_submittedCaptures.isNotEmpty) {
      return;
    }
    final capturedRows = shellCommandBlockPreviewRowsForFrame(
      snapshot: _snapshot,
      frame: frame,
    );
    for (final entry in capturedRows.entries) {
      _mergeCapturedRows(entry.key, entry.value);
    }
  }

  void _mergeCapturedRows(String blockId, List<terminal.TerminalRow> rows) {
    if (shellCommandBlockPreviewRowsWouldChange(
      existingRows: _capturedRowsByBlockId[blockId],
      nextRows: rows,
    )) {
      _capturedRowsByBlockId[blockId] = shellCommandBlockMergedPreviewRows(
        existingRows: _capturedRowsByBlockId[blockId],
        nextRows: rows,
      );
    }
  }

  ShellCommandBlock? _blockById(String blockId) {
    for (final block in _snapshot.blocks) {
      if (block.id == blockId) {
        return block;
      }
    }
    return null;
  }

  ShellCommandBlock? _latestBlockFor(String command) {
    for (final block in _snapshot.blocks.reversed) {
      if (block.command == command) {
        return block;
      }
    }
    return null;
  }

  ShellCommandBlocksOverlayViewModel _viewModel() {
    final frame = _frame ?? terminal.TerminalFrameDiff.empty;
    return ShellCommandBlockViewModelBuilder.build(
      blocks: _snapshot.blocks,
      viewportStartRow: frame.viewportStartRow,
      viewportEndRow: frame.viewportStartRow + frame.viewportRows - 1,
      visibleRows: frame.rows,
      capturedRowsByBlockId: _capturedRowsByBlockId,
      viewportCols: frame.viewportCols,
      flags: _flags,
    );
  }

  int? _finishedTargetEndPromptRow(int commandRow) {
    final promptRow = _snapshot.lastPrompt?.row;
    if (promptRow == null || promptRow <= commandRow) {
      return null;
    }
    return promptRow;
  }

  List<terminal.TerminalRow> _rowsAfterCommandRow(
    terminal.TerminalFrameDiff frame,
    int commandRow, {
    int? endPromptRow,
  }) {
    final rows = <terminal.TerminalRow>[];
    for (final row in frame.rows) {
      final absoluteRow = frame.viewportStartRow + row.index;
      if (absoluteRow <= commandRow) {
        continue;
      }
      if (endPromptRow != null && absoluteRow >= endPromptRow) {
        continue;
      }
      rows.add(
        terminal.TerminalRow(
          index: rows.length,
          text: row.text,
          wrapped: row.wrapped,
          modifiedAt: row.modifiedAt,
          styleRuns: row.styleRuns,
        ),
      );
    }
    return rows;
  }

  Future<void> _waitUntil(
    bool Function() predicate, {
    String failureMessage = 'condition was not met',
  }) async {
    for (var attempt = 0; attempt < 120; attempt += 1) {
      if (predicate()) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final blocks = _snapshot.blocks
        .map(
          (block) =>
              '${block.command} ${block.outputRange.outputStartRow}-${block.outputRange.outputEndRow}',
        )
        .join(', ');
    final rows = (_frame?.rows ?? const <terminal.TerminalRow>[])
        .map((row) => row.text)
        .join('\n');
    fail('$failureMessage\nblocks: $blocks\nrows:\n$rows');
  }
}

class _SubmittedCapture {
  const _SubmittedCapture({
    required this.commandRow,
    required this.submittedAt,
    this.rows = const <terminal.TerminalRow>[],
  });

  final int commandRow;
  final DateTime submittedAt;
  final List<terminal.TerminalRow> rows;

  _SubmittedCapture copyWith({List<terminal.TerminalRow>? rows}) {
    return _SubmittedCapture(
      commandRow: commandRow,
      submittedAt: submittedAt,
      rows: rows ?? this.rows,
    );
  }
}

int? _submittedCommandRowForFrame(terminal.TerminalFrameDiff? frame) {
  if (frame == null || frame.viewportStartRow < 0 || frame.cursor.row < 0) {
    return null;
  }
  return frame.viewportStartRow + frame.cursor.row;
}

List<String> _nonEmptyLines(String text) {
  return [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty) line,
  ];
}

String? _resolveWorkspaceCoreLibraryPath() {
  if (!Platform.isMacOS) {
    return null;
  }
  const relativeCandidates = <String>[
    '../native/core/target/debug/libianvs_core.dylib',
    '../../native/core/target/debug/libianvs_core.dylib',
    'native/core/target/debug/libianvs_core.dylib',
  ];
  for (final relativePath in relativeCandidates) {
    final candidate = File.fromUri(Directory.current.uri.resolve(relativePath));
    if (candidate.existsSync()) {
      return candidate.absolute.path;
    }
  }
  return null;
}

final String? _workspaceCoreLibraryPath = _resolveWorkspaceCoreLibraryPath();

String? _resolveShellPath(String shellName) {
  final directCandidates = <String>[
    '/bin/$shellName',
    '/usr/bin/$shellName',
    '/opt/homebrew/bin/$shellName',
    '/usr/local/bin/$shellName',
  ];
  for (final candidate in directCandidates) {
    final file = File(candidate);
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }
  final path = Platform.environment['PATH'];
  if (path == null || path.trim().isEmpty) {
    return null;
  }
  for (final directory in path.split(':')) {
    if (directory.trim().isEmpty) {
      continue;
    }
    final file = File('$directory/$shellName');
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }
  return null;
}

final String? _bashPath = _resolveShellPath('bash');
