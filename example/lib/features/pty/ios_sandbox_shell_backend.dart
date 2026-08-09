import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ianvs_pty/ianvs_pty.dart';

/// A small, in-process shell for iOS that never launches a child process.
///
/// Every path is mapped into [rootDirectory]. Commands are deliberately
/// bounded to a useful file-manipulation subset so the terminal can remain
/// interactive without escaping the iOS application sandbox.
final class IosSandboxShellBackend
    implements PtySessionBackend, PtySessionConfigV1Backend {
  IosSandboxShellBackend({
    required Directory rootDirectory,
    required PtySessionBackend terminalBackend,
    DateTime Function()? clock,
  }) : rootDirectory = Directory(rootDirectory.absolute.path),
       _terminalBackend = terminalBackend,
       _terminalOutput = _requireReplayBackend(terminalBackend),
       _clock = clock ?? DateTime.now {
    this.rootDirectory.createSync(recursive: true);
    _rootPath = this.rootDirectory.resolveSymbolicLinksSync();
  }

  final Directory rootDirectory;
  final PtySessionBackend _terminalBackend;
  final PtyReplaySessionBackend _terminalOutput;
  final DateTime Function() _clock;
  late final String _rootPath;
  final Map<String, _SandboxSession> _sessions = <String, _SandboxSession>{};

  @override
  bool get supportsSessionConfigV1 {
    final output = _terminalBackend;
    final configOutput = output is PtyReplaySessionConfigV1Backend
        ? output as PtyReplaySessionConfigV1Backend
        : null;
    return configOutput?.supportsReplaySessionConfigV1 ?? false;
  }

  @override
  int ping() => _terminalBackend.ping();

  @override
  String createSession(String sessionConfigJson) {
    return _createSession(
      _terminalOutput.createReplaySession(sessionConfigJson),
    );
  }

  @override
  String createSessionV1(String sessionConfigV1Json) {
    final output = _terminalBackend;
    final configOutput = output is PtyReplaySessionConfigV1Backend
        ? output as PtyReplaySessionConfigV1Backend
        : null;
    if (configOutput == null || !configOutput.supportsReplaySessionConfigV1) {
      throw UnsupportedError('Replay SessionConfig v1 is not supported');
    }
    return _createSession(
      configOutput.createReplaySessionV1(sessionConfigV1Json),
    );
  }

  String _createSession(String sessionId) {
    final session = _SandboxSession(sessionId)
      ..lines.addAll(const <_ShellLine>[
        _ShellLine('Ianvs Sandbox Shell'),
        _ShellLine('On-device · offline · app-container only'),
        _ShellLine('Type "help" to see the available commands.'),
        _ShellLine(''),
      ]);
    _sessions[sessionId] = session;
    _redraw(session);
    return sessionId;
  }

  @override
  void closeSession(String sessionId) {
    _sessions.remove(sessionId);
    _terminalBackend.closeSession(sessionId);
  }

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  }) {
    final session = _sessions[sessionId];
    if (session == null) {
      return;
    }
    _terminalBackend.resizeSession(
      sessionId,
      cols: cols,
      rows: rows,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
    );
    _redraw(session);
  }

  @override
  void writeInput(String sessionId, List<int> bytes) {
    final session = _sessions[sessionId];
    if (session == null || bytes.isEmpty) {
      return;
    }
    var index = 0;
    while (index < bytes.length) {
      final byte = bytes[index] & 0xff;
      if (byte == 0x1b) {
        final consumed = _handleEscapeSequence(session, bytes, index);
        index += consumed;
        continue;
      }
      if (byte == 0x0d || byte == 0x0a) {
        if (byte == 0x0a && session.lastInputWasCarriageReturn) {
          session.lastInputWasCarriageReturn = false;
          index += 1;
          continue;
        }
        session.lastInputWasCarriageReturn = byte == 0x0d;
        _submit(session);
        index += 1;
        continue;
      }
      session.lastInputWasCarriageReturn = false;
      if (byte < 0x20 || byte == 0x7f) {
        _handleControlByte(session, byte);
        index += 1;
        continue;
      }

      final start = index;
      while (index < bytes.length) {
        final candidate = bytes[index] & 0xff;
        if (candidate < 0x20 || candidate == 0x7f) {
          break;
        }
        index += 1;
      }
      final text = utf8.decode(
        bytes.sublist(start, index),
        allowMalformed: true,
      );
      _insertText(session, text);
    }
    _redraw(session);
  }

  int _handleEscapeSequence(
    _SandboxSession session,
    List<int> bytes,
    int start,
  ) {
    if (start + 2 >= bytes.length || bytes[start + 1] != 0x5b) {
      return 1;
    }
    final code = bytes[start + 2];
    switch (code) {
      case 0x41: // Up
        _moveHistory(session, -1);
      case 0x42: // Down
        _moveHistory(session, 1);
      case 0x43: // Right
        session.cursor = math.min(session.input.length, session.cursor + 1);
      case 0x44: // Left
        session.cursor = math.max(0, session.cursor - 1);
      case 0x48: // Home
        session.cursor = 0;
      case 0x46: // End
        session.cursor = session.input.length;
      default:
        if (code == 0x33 &&
            start + 3 < bytes.length &&
            bytes[start + 3] == 0x7e) {
          _deleteForward(session);
          return 4;
        }
    }
    return 3;
  }

  void _handleControlByte(_SandboxSession session, int byte) {
    switch (byte) {
      case 0x03: // Ctrl-C
        session.lines.add(
          _ShellLine(
            '${_prompt(session)}${session.inputText}^C',
            promptLength: _prompt(session).length,
          ),
        );
        _replaceInput(session, '');
      case 0x04: // Ctrl-D
        if (session.input.isEmpty) {
          session.lines.add(
            const _ShellLine('logout is disabled in the iOS sandbox shell'),
          );
        } else {
          _deleteForward(session);
        }
      case 0x01: // Ctrl-A
        session.cursor = 0;
      case 0x05: // Ctrl-E
        session.cursor = session.input.length;
      case 0x0b: // Ctrl-K
        session.input.removeRange(session.cursor, session.input.length);
      case 0x0c: // Ctrl-L
        session.lines.clear();
      case 0x15: // Ctrl-U
        session.input.removeRange(0, session.cursor);
        session.cursor = 0;
      case 0x17: // Ctrl-W
        _deletePreviousWord(session);
      case 0x08:
      case 0x7f:
        _deleteBackward(session);
      case 0x09:
        _completeInput(session);
      default:
        // Other control bytes are intentionally inert.
        break;
    }
  }

  void _insertText(_SandboxSession session, String text) {
    if (text.isEmpty) {
      return;
    }
    final runes = text.runes.map(String.fromCharCode).toList(growable: false);
    session.input.insertAll(session.cursor, runes);
    session.cursor += runes.length;
  }

  void _deleteBackward(_SandboxSession session) {
    if (session.cursor == 0) {
      return;
    }
    session.input.removeAt(session.cursor - 1);
    session.cursor -= 1;
  }

  void _deleteForward(_SandboxSession session) {
    if (session.cursor >= session.input.length) {
      return;
    }
    session.input.removeAt(session.cursor);
  }

  void _deletePreviousWord(_SandboxSession session) {
    var start = session.cursor;
    while (start > 0 && session.input[start - 1].trim().isEmpty) {
      start -= 1;
    }
    while (start > 0 && session.input[start - 1].trim().isNotEmpty) {
      start -= 1;
    }
    session.input.removeRange(start, session.cursor);
    session.cursor = start;
  }

  void _moveHistory(_SandboxSession session, int delta) {
    if (session.history.isEmpty) {
      return;
    }
    final next = (session.historyIndex + delta).clamp(
      0,
      session.history.length,
    );
    session.historyIndex = next;
    _replaceInput(
      session,
      next == session.history.length ? '' : session.history[next],
    );
  }

  void _replaceInput(_SandboxSession session, String text) {
    session.input
      ..clear()
      ..addAll(text.runes.map(String.fromCharCode));
    session.cursor = session.input.length;
  }

  void _completeInput(_SandboxSession session) {
    final input = session.inputText;
    final prefixStart = input.lastIndexOf(RegExp(r'[\s|;]')) + 1;
    final prefix = input.substring(prefixStart);
    if (prefix.isEmpty) {
      return;
    }
    final candidates = prefixStart == 0
        ? _sandboxCommands
              .where((command) => command.startsWith(prefix))
              .toList()
        : _pathCompletions(session, prefix);
    if (candidates.length == 1) {
      final replacement = candidates.single;
      _replaceInput(session, '${input.substring(0, prefixStart)}$replacement');
      return;
    }
    if (candidates.isNotEmpty) {
      final prompt = _prompt(session);
      session.lines
        ..add(_ShellLine('$prompt$input', promptLength: prompt.length))
        ..add(_ShellLine(candidates.join('  ')));
    }
  }

  List<String> _pathCompletions(_SandboxSession session, String prefix) {
    final slash = prefix.lastIndexOf('/');
    final directoryPart = slash < 0 ? '.' : prefix.substring(0, slash + 1);
    final namePrefix = slash < 0 ? prefix : prefix.substring(slash + 1);
    try {
      final resolved = _resolvePath(session, directoryPart, mustExist: true);
      final directory = Directory(resolved.systemPath);
      if (!directory.existsSync()) {
        return const <String>[];
      }
      final leading = slash < 0 ? '' : prefix.substring(0, slash + 1);
      final candidates = <String>[];
      for (final entity in directory.listSync(followLinks: false)) {
        final name = _basename(entity.path);
        if (!name.startsWith(namePrefix)) {
          continue;
        }
        candidates.add('$leading$name${entity is Directory ? '/' : ''}');
      }
      candidates.sort();
      return candidates;
    } on Object {
      return const <String>[];
    }
  }

  void _submit(_SandboxSession session) {
    final commandLine = session.inputText;
    final prompt = _prompt(session);
    session.lines.add(
      _ShellLine('$prompt$commandLine', promptLength: prompt.length),
    );
    if (commandLine.trim().isNotEmpty) {
      if (session.history.isEmpty || session.history.last != commandLine) {
        session.history.add(commandLine);
        if (session.history.length > 200) {
          session.history.removeAt(0);
        }
      }
      final result = _runCommandLine(session, commandLine);
      if (result.clearScreen) {
        session.lines.clear();
      }
      _appendOutput(session, result.output);
      if (result.error.isNotEmpty) {
        _appendOutput(session, result.error);
      }
      session.lastExitCode = result.exitCode;
    }
    _replaceInput(session, '');
    session.historyIndex = session.history.length;
  }

  void _appendOutput(_SandboxSession session, String output) {
    if (output.isEmpty) {
      return;
    }
    final normalized = output.endsWith('\n')
        ? output.substring(0, output.length - 1)
        : output;
    for (final line in normalized.split('\n')) {
      session.lines.add(_ShellLine(line));
    }
    if (session.lines.length > 5000) {
      session.lines.removeRange(0, session.lines.length - 5000);
    }
  }

  _CommandResult _runCommandLine(_SandboxSession session, String commandLine) {
    final tokenResult = _ShellTokenizer.tokenize(commandLine);
    if (tokenResult.error != null) {
      return _CommandResult.failure('shell: ${tokenResult.error}');
    }
    final tokens = tokenResult.tokens;
    if (tokens.isEmpty) {
      return const _CommandResult();
    }

    final combinedOutput = StringBuffer();
    final combinedError = StringBuffer();
    var exitCode = 0;
    var sequenceStart = 0;
    for (var index = 0; index <= tokens.length; index += 1) {
      if (index != tokens.length && tokens[index] != ';') {
        continue;
      }
      final sequence = tokens.sublist(sequenceStart, index);
      sequenceStart = index + 1;
      if (sequence.isEmpty) {
        continue;
      }
      final result = _runPipeline(session, sequence);
      if (result.clearScreen) {
        return result;
      }
      combinedOutput.write(result.output);
      combinedError.write(result.error);
      exitCode = result.exitCode;
    }
    return _CommandResult(
      output: combinedOutput.toString(),
      error: combinedError.toString(),
      exitCode: exitCode,
    );
  }

  _CommandResult _runPipeline(_SandboxSession session, List<String> tokens) {
    final stages = <List<String>>[];
    var start = 0;
    for (var index = 0; index <= tokens.length; index += 1) {
      if (index != tokens.length && tokens[index] != '|') {
        continue;
      }
      if (index == start) {
        return _CommandResult.failure('shell: empty pipeline stage');
      }
      stages.add(tokens.sublist(start, index));
      start = index + 1;
    }

    String stdin = '';
    final errors = StringBuffer();
    var exitCode = 0;
    String? redirectPath;
    var appendRedirect = false;
    final last = stages.last;
    for (var index = 0; index < last.length; index += 1) {
      if (last[index] != '>' && last[index] != '>>') {
        continue;
      }
      if (index + 1 >= last.length || index + 2 != last.length) {
        return _CommandResult.failure('shell: invalid output redirection');
      }
      redirectPath = last[index + 1];
      appendRedirect = last[index] == '>>';
      stages[stages.length - 1] = last.sublist(0, index);
      break;
    }

    for (final stage in stages) {
      if (stage.isEmpty) {
        return _CommandResult.failure('shell: missing command');
      }
      final expanded = stage
          .map((token) => _expandVariables(session, token))
          .toList(growable: false);
      final result = _runCommand(session, expanded, stdin);
      if (result.clearScreen) {
        return result;
      }
      stdin = result.output;
      errors.write(result.error);
      exitCode = result.exitCode;
    }

    if (redirectPath != null) {
      try {
        final resolved = _resolvePath(session, redirectPath);
        final file = File(resolved.systemPath);
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(
          stdin,
          mode: appendRedirect ? FileMode.append : FileMode.write,
          flush: true,
        );
        stdin = '';
      } on Object catch (error) {
        return _CommandResult.failure(
          'shell: $redirectPath: ${_friendlyIoError(error)}',
        );
      }
    }

    return _CommandResult(
      output: stdin,
      error: errors.toString(),
      exitCode: exitCode,
    );
  }

  String _expandVariables(_SandboxSession session, String value) {
    final variables = <String, String>{
      'HOME': '/',
      'PWD': session.cwd,
      'USER': 'mobile',
      'SHELL': 'ianvs-sandbox',
      '?': '${session.lastExitCode}',
    };
    return value.replaceAllMapped(
      RegExp(r'\$\{([A-Za-z_?][A-Za-z0-9_?]*)\}|\$([A-Za-z_?][A-Za-z0-9_?]*)'),
      (match) => variables[match.group(1) ?? match.group(2)] ?? '',
    );
  }

  _CommandResult _runCommand(
    _SandboxSession session,
    List<String> args,
    String stdin,
  ) {
    final command = args.first;
    final rest = args.skip(1).toList(growable: false);
    try {
      return switch (command) {
        'help' => _help(),
        'pwd' => _CommandResult(output: '${session.cwd}\n'),
        'cd' => _cd(session, rest),
        'ls' => _ls(session, rest),
        'cat' => _cat(session, rest, stdin),
        'echo' => _CommandResult(output: '${rest.join(' ')}\n'),
        'mkdir' => _mkdir(session, rest),
        'touch' => _touch(session, rest),
        'rm' => _rm(session, rest),
        'cp' => _copy(session, rest),
        'mv' => _move(session, rest),
        'head' => _headTail(session, rest, stdin, head: true),
        'tail' => _headTail(session, rest, stdin, head: false),
        'grep' => _grep(session, rest, stdin),
        'wc' => _wc(session, rest, stdin),
        'history' => _history(session),
        'clear' => const _CommandResult(clearScreen: true),
        'date' => _CommandResult(output: '${_clock().toLocal()}\n'),
        'whoami' => const _CommandResult(output: 'mobile\n'),
        'uname' => const _CommandResult(output: 'iOS Ianvs sandbox shell\n'),
        'env' => _CommandResult(
          output:
              'HOME=/\nPWD=${session.cwd}\nUSER=mobile\nSHELL=ianvs-sandbox\n',
        ),
        'exit' => const _CommandResult(
          error:
              'exit: sessions are managed by the app; close the tab instead\n',
          exitCode: 1,
        ),
        _ => _CommandResult.failure('$command: command not found'),
      };
    } on _SandboxPathException catch (error) {
      return _CommandResult.failure('$command: ${error.message}');
    } on FileSystemException catch (error) {
      return _CommandResult.failure('$command: ${_friendlyIoError(error)}');
    } on Object catch (error) {
      return _CommandResult.failure('$command: ${_friendlyIoError(error)}');
    }
  }

  _CommandResult _help() {
    return const _CommandResult(
      output: '''
Ianvs iOS sandbox commands
  Files:   pwd cd ls cat mkdir touch rm cp mv
  Text:    echo grep head tail wc
  Shell:   history clear date whoami uname env help

Pipes (|), command separators (;), and output redirects (> and >>) are supported.
Paths are always confined to this app's IanvsShell folder.
''',
    );
  }

  _CommandResult _cd(_SandboxSession session, List<String> args) {
    if (args.length > 1) {
      return _CommandResult.failure('cd: too many arguments');
    }
    final target = args.isEmpty ? '/' : args.single;
    final resolved = _resolvePath(session, target, mustExist: true);
    if (!Directory(resolved.systemPath).existsSync()) {
      return _CommandResult.failure('cd: $target: not a directory');
    }
    session.cwd = resolved.virtualPath;
    return const _CommandResult();
  }

  _CommandResult _ls(_SandboxSession session, List<String> args) {
    var showHidden = false;
    var long = false;
    final targets = <String>[];
    for (final arg in args) {
      if (arg.startsWith('-') && arg.length > 1) {
        showHidden = showHidden || arg.contains('a');
        long = long || arg.contains('l');
      } else {
        targets.add(arg);
      }
    }
    if (targets.length > 1) {
      return _CommandResult.failure('ls: only one path is supported at a time');
    }
    final target = targets.isEmpty ? '.' : targets.single;
    final resolved = _resolvePath(session, target, mustExist: true);
    final type = FileSystemEntity.typeSync(resolved.systemPath);
    if (type == FileSystemEntityType.file) {
      final file = File(resolved.systemPath);
      final name = _basename(file.path);
      return _CommandResult(
        output: long
            ? '- ${file.lengthSync().toString().padLeft(8)} $name\n'
            : '$name\n',
      );
    }
    if (type != FileSystemEntityType.directory) {
      return _CommandResult.failure('ls: $target: not found');
    }
    final entries =
        Directory(resolved.systemPath)
            .listSync(followLinks: false)
            .where(
              (entry) => showHidden || !_basename(entry.path).startsWith('.'),
            )
            .toList(growable: false)
          ..sort(
            (left, right) =>
                _basename(left.path).compareTo(_basename(right.path)),
          );
    final buffer = StringBuffer();
    for (final entry in entries) {
      final name = '${_basename(entry.path)}${entry is Directory ? '/' : ''}';
      if (long) {
        final size = entry is File ? entry.lengthSync() : 0;
        buffer.writeln(
          '${entry is Directory ? 'd' : '-'} ${size.toString().padLeft(8)} $name',
        );
      } else {
        buffer.writeln(name);
      }
    }
    return _CommandResult(output: buffer.toString());
  }

  _CommandResult _cat(
    _SandboxSession session,
    List<String> args,
    String stdin,
  ) {
    if (args.isEmpty) {
      return _CommandResult(output: stdin);
    }
    final buffer = StringBuffer();
    for (final arg in args) {
      final resolved = _resolvePath(session, arg, mustExist: true);
      final file = File(resolved.systemPath);
      if (!file.existsSync()) {
        return _CommandResult.failure('cat: $arg: not a file');
      }
      buffer.write(file.readAsStringSync());
    }
    return _CommandResult(output: buffer.toString());
  }

  _CommandResult _mkdir(_SandboxSession session, List<String> args) {
    final recursive = args.contains('-p');
    final paths = args.where((arg) => arg != '-p').toList(growable: false);
    if (paths.isEmpty) {
      return _CommandResult.failure('mkdir: missing path');
    }
    for (final path in paths) {
      final resolved = _resolvePath(session, path);
      Directory(resolved.systemPath).createSync(recursive: recursive);
    }
    return const _CommandResult();
  }

  _CommandResult _touch(_SandboxSession session, List<String> args) {
    if (args.isEmpty) {
      return _CommandResult.failure('touch: missing path');
    }
    for (final path in args) {
      final resolved = _resolvePath(session, path);
      final file = File(resolved.systemPath);
      file.parent.createSync(recursive: true);
      if (file.existsSync()) {
        file.setLastModifiedSync(_clock());
      } else {
        file.createSync();
      }
    }
    return const _CommandResult();
  }

  _CommandResult _rm(_SandboxSession session, List<String> args) {
    final recursive = args.any(
      (arg) => arg == '-r' || arg == '-R' || arg == '-rf' || arg == '-fr',
    );
    final force = args.any(
      (arg) => arg == '-f' || arg == '-rf' || arg == '-fr',
    );
    final paths = args
        .where((arg) => !arg.startsWith('-'))
        .toList(growable: false);
    if (paths.isEmpty) {
      return _CommandResult.failure('rm: missing path');
    }
    for (final path in paths) {
      final resolved = _resolvePath(session, path);
      if (resolved.virtualPath == '/') {
        return _CommandResult.failure('rm: refusing to remove sandbox root');
      }
      final type = FileSystemEntity.typeSync(
        resolved.systemPath,
        followLinks: false,
      );
      if (type == FileSystemEntityType.notFound) {
        if (!force) {
          return _CommandResult.failure('rm: $path: not found');
        }
        continue;
      }
      if (type == FileSystemEntityType.directory && !recursive) {
        return _CommandResult.failure('rm: $path: is a directory (use -r)');
      }
      FileSystemEntity.isDirectorySync(resolved.systemPath)
          ? Directory(resolved.systemPath).deleteSync(recursive: recursive)
          : File(resolved.systemPath).deleteSync();
    }
    return const _CommandResult();
  }

  _CommandResult _copy(_SandboxSession session, List<String> args) {
    final recursive = args.contains('-r') || args.contains('-R');
    final paths = args
        .where((arg) => !arg.startsWith('-'))
        .toList(growable: false);
    if (paths.length != 2) {
      return _CommandResult.failure('cp: expected source and destination');
    }
    final source = _resolvePath(session, paths[0], mustExist: true);
    var destination = _resolvePath(session, paths[1]);
    if (Directory(destination.systemPath).existsSync()) {
      destination = _resolvePath(
        session,
        '${paths[1]}/${_basename(source.systemPath)}',
      );
    }
    if (Directory(source.systemPath).existsSync()) {
      if (!recursive) {
        return _CommandResult.failure(
          'cp: ${paths[0]}: is a directory (use -r)',
        );
      }
      _copyDirectory(
        Directory(source.systemPath),
        Directory(destination.systemPath),
      );
    } else {
      File(destination.systemPath).parent.createSync(recursive: true);
      File(source.systemPath).copySync(destination.systemPath);
    }
    return const _CommandResult();
  }

  void _copyDirectory(Directory source, Directory destination) {
    destination.createSync(recursive: true);
    for (final entity in source.listSync(followLinks: false)) {
      final target =
          '${destination.path}${Platform.pathSeparator}${_basename(entity.path)}';
      if (entity is Directory) {
        _copyDirectory(entity, Directory(target));
      } else if (entity is File) {
        entity.copySync(target);
      }
    }
  }

  _CommandResult _move(_SandboxSession session, List<String> args) {
    if (args.length != 2) {
      return _CommandResult.failure('mv: expected source and destination');
    }
    final source = _resolvePath(session, args[0], mustExist: true);
    var destination = _resolvePath(session, args[1]);
    if (Directory(destination.systemPath).existsSync()) {
      destination = _resolvePath(
        session,
        '${args[1]}/${_basename(source.systemPath)}',
      );
    }
    FileSystemEntity.isDirectorySync(source.systemPath)
        ? Directory(source.systemPath).renameSync(destination.systemPath)
        : File(source.systemPath).renameSync(destination.systemPath);
    return const _CommandResult();
  }

  _CommandResult _headTail(
    _SandboxSession session,
    List<String> args,
    String stdin, {
    required bool head,
  }) {
    var count = 10;
    final paths = <String>[];
    for (var index = 0; index < args.length; index += 1) {
      if (args[index] == '-n' && index + 1 < args.length) {
        count = int.tryParse(args[index + 1])?.clamp(0, 10000) ?? count;
        index += 1;
      } else {
        paths.add(args[index]);
      }
    }
    final textResult = _readTextInputs(session, paths, stdin);
    if (textResult.error.isNotEmpty) {
      return textResult;
    }
    final lines = textResult.output.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    final selected = head
        ? lines.take(count)
        : lines.skip(math.max(0, lines.length - count));
    return _CommandResult(
      output: selected.isEmpty ? '' : '${selected.join('\n')}\n',
    );
  }

  _CommandResult _grep(
    _SandboxSession session,
    List<String> args,
    String stdin,
  ) {
    var ignoreCase = false;
    var showNumbers = false;
    final positional = <String>[];
    for (final arg in args) {
      if (arg.startsWith('-') && arg.length > 1) {
        ignoreCase = ignoreCase || arg.contains('i');
        showNumbers = showNumbers || arg.contains('n');
      } else {
        positional.add(arg);
      }
    }
    if (positional.isEmpty) {
      return _CommandResult.failure('grep: missing pattern');
    }
    final pattern = positional.first;
    final textResult = _readTextInputs(
      session,
      positional.skip(1).toList(),
      stdin,
    );
    if (textResult.error.isNotEmpty) {
      return textResult;
    }
    final needle = ignoreCase ? pattern.toLowerCase() : pattern;
    final buffer = StringBuffer();
    var matched = false;
    final lines = textResult.output.split('\n');
    for (var index = 0; index < lines.length; index += 1) {
      final haystack = ignoreCase ? lines[index].toLowerCase() : lines[index];
      if (!haystack.contains(needle)) {
        continue;
      }
      matched = true;
      buffer.writeln(
        showNumbers ? '${index + 1}:${lines[index]}' : lines[index],
      );
    }
    return _CommandResult(output: buffer.toString(), exitCode: matched ? 0 : 1);
  }

  _CommandResult _wc(_SandboxSession session, List<String> args, String stdin) {
    final paths = args
        .where((arg) => !arg.startsWith('-'))
        .toList(growable: false);
    final textResult = _readTextInputs(session, paths, stdin);
    if (textResult.error.isNotEmpty) {
      return textResult;
    }
    final text = textResult.output;
    final lines = text.isEmpty
        ? 0
        : '\n'.allMatches(text).length + (text.endsWith('\n') ? 0 : 1);
    final words = RegExp(r'\S+').allMatches(text).length;
    return _CommandResult(
      output: '$lines $words ${utf8.encode(text).length}\n',
    );
  }

  _CommandResult _readTextInputs(
    _SandboxSession session,
    List<String> paths,
    String stdin,
  ) {
    if (paths.isEmpty) {
      return _CommandResult(output: stdin);
    }
    final buffer = StringBuffer();
    for (final path in paths) {
      final resolved = _resolvePath(session, path, mustExist: true);
      final file = File(resolved.systemPath);
      if (!file.existsSync()) {
        return _CommandResult.failure('$path: not a file');
      }
      buffer.write(file.readAsStringSync());
    }
    return _CommandResult(output: buffer.toString());
  }

  _CommandResult _history(_SandboxSession session) {
    final buffer = StringBuffer();
    for (var index = 0; index < session.history.length; index += 1) {
      buffer.writeln(
        '${(index + 1).toString().padLeft(4)}  ${session.history[index]}',
      );
    }
    return _CommandResult(output: buffer.toString());
  }

  _ResolvedPath _resolvePath(
    _SandboxSession session,
    String rawPath, {
    bool mustExist = false,
  }) {
    final trimmed = rawPath.trim();
    final expanded = trimmed == '~'
        ? '/'
        : trimmed.startsWith('~/')
        ? '/${trimmed.substring(2)}'
        : trimmed;
    final segments = <String>[];
    if (!expanded.startsWith('/')) {
      segments.addAll(session.cwd.split('/').where((part) => part.isNotEmpty));
    }
    for (final part in expanded.split('/')) {
      if (part.isEmpty || part == '.') {
        continue;
      }
      if (part == '..') {
        if (segments.isEmpty) {
          throw const _SandboxPathException(
            'path cannot escape the sandbox root',
          );
        }
        segments.removeLast();
        continue;
      }
      if (part.contains('\u0000')) {
        throw const _SandboxPathException('invalid path');
      }
      segments.add(part);
    }
    final virtual = segments.isEmpty ? '/' : '/${segments.join('/')}';
    final system = segments.fold<String>(
      _rootPath,
      (parent, segment) => '$parent${Platform.pathSeparator}$segment',
    );
    _assertContained(system);
    if (mustExist &&
        FileSystemEntity.typeSync(system) == FileSystemEntityType.notFound) {
      throw _SandboxPathException('$rawPath: not found');
    }
    return _ResolvedPath(virtualPath: virtual, systemPath: system);
  }

  void _assertContained(String systemPath) {
    var probe = systemPath;
    while (FileSystemEntity.typeSync(probe, followLinks: false) ==
        FileSystemEntityType.notFound) {
      final parent = File(probe).parent.path;
      if (parent == probe) {
        break;
      }
      probe = parent;
    }
    final canonical =
        FileSystemEntity.typeSync(probe, followLinks: false) ==
            FileSystemEntityType.notFound
        ? probe
        : File(probe).resolveSymbolicLinksSync();
    if (canonical != _rootPath &&
        !canonical.startsWith('$_rootPath${Platform.pathSeparator}')) {
      throw const _SandboxPathException('path cannot escape the sandbox root');
    }
  }

  @override
  void scrollViewport(String sessionId, int deltaLines) {
    if (!_sessions.containsKey(sessionId) || deltaLines == 0) {
      return;
    }
    _terminalBackend.scrollViewport(sessionId, deltaLines);
  }

  @override
  void scrollViewportTo(String sessionId, int offset) {
    if (!_sessions.containsKey(sessionId)) {
      return;
    }
    _terminalBackend.scrollViewportTo(sessionId, offset);
  }

  @override
  String? takeFrameDiffJson(String sessionId) {
    return _sessions.containsKey(sessionId)
        ? _terminalBackend.takeFrameDiffJson(sessionId)
        : null;
  }

  void _redraw(_SandboxSession session) {
    final output = StringBuffer(
      '\x1b[?25l\x1b[3J\x1b[2J\x1b[H\x1b]0;iOS Sandbox\x07',
    );
    for (final line in session.lines) {
      _writeStyledLine(output, line);
      output.write('\r\n');
    }

    _writePrompt(output, _prompt(session));
    output.write(session.input.take(session.cursor).join());
    output.write('\x1b7');
    output.write(session.input.skip(session.cursor).join());
    output.write('\x1b8\x1b[5 q\x1b[?25h');
    _terminalOutput.replayOutput(session.id, utf8.encode(output.toString()));
  }

  void _writeStyledLine(StringBuffer output, _ShellLine line) {
    final promptLength = line.promptLength.clamp(0, line.text.length);
    if (promptLength == 0) {
      output.write(line.text);
      return;
    }
    _writePrompt(output, line.text.substring(0, promptLength));
    output.write(line.text.substring(promptLength));
  }

  void _writePrompt(StringBuffer output, String prompt) {
    output
      ..write('\x1b[1;38;2;125;211;252m')
      ..write(prompt)
      ..write('\x1b[0m');
  }

  String _prompt(_SandboxSession session) {
    final location = session.cwd == '/' ? '~' : '~${session.cwd}';
    return 'ios:$location \$ ';
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    return _sessions.containsKey(sessionId)
        ? _terminalBackend.pollEvents(sessionId)
        : const <PtyEvent>[];
  }
}

PtyReplaySessionBackend _requireReplayBackend(PtySessionBackend backend) {
  if (backend case final PtyReplaySessionBackend replayBackend) {
    return replayBackend;
  }
  throw ArgumentError.value(
    backend,
    'terminalBackend',
    'must support replay sessions for in-process terminal output',
  );
}

const Set<String> _sandboxCommands = <String>{
  'cat',
  'cd',
  'clear',
  'cp',
  'date',
  'echo',
  'env',
  'exit',
  'grep',
  'head',
  'help',
  'history',
  'ls',
  'mkdir',
  'mv',
  'pwd',
  'rm',
  'tail',
  'touch',
  'uname',
  'wc',
  'whoami',
};

final class _SandboxSession {
  _SandboxSession(this.id);

  final String id;
  final List<_ShellLine> lines = <_ShellLine>[];
  final List<String> input = <String>[];
  final List<String> history = <String>[];
  String cwd = '/';
  int cursor = 0;
  int historyIndex = 0;
  int lastExitCode = 0;
  bool lastInputWasCarriageReturn = false;

  String get inputText => input.join();
}

final class _ShellLine {
  const _ShellLine(this.text, {this.promptLength = 0});

  final String text;
  final int promptLength;
}

final class _CommandResult {
  const _CommandResult({
    this.output = '',
    this.error = '',
    this.exitCode = 0,
    this.clearScreen = false,
  });

  factory _CommandResult.failure(String message) => _CommandResult(
    error: message.endsWith('\n') ? message : '$message\n',
    exitCode: 1,
  );

  final String output;
  final String error;
  final int exitCode;
  final bool clearScreen;
}

final class _ResolvedPath {
  const _ResolvedPath({required this.virtualPath, required this.systemPath});

  final String virtualPath;
  final String systemPath;
}

final class _SandboxPathException implements Exception {
  const _SandboxPathException(this.message);

  final String message;
}

final class _TokenizeResult {
  const _TokenizeResult(this.tokens, {this.error});

  final List<String> tokens;
  final String? error;
}

abstract final class _ShellTokenizer {
  static _TokenizeResult tokenize(String input) {
    final tokens = <String>[];
    final current = StringBuffer();
    String? quote;
    var escaping = false;

    void flush() {
      if (current.isEmpty) {
        return;
      }
      tokens.add(current.toString());
      current.clear();
    }

    for (var index = 0; index < input.length; index += 1) {
      final char = input[index];
      if (escaping) {
        current.write(char);
        escaping = false;
        continue;
      }
      if (char == r'\' && quote != "'") {
        escaping = true;
        continue;
      }
      if (quote != null) {
        if (char == quote) {
          quote = null;
        } else {
          current.write(char);
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char.trim().isEmpty) {
        flush();
        continue;
      }
      if (char == '#' && current.isEmpty) {
        break;
      }
      if (char == '|' || char == ';' || char == '>') {
        flush();
        if (char == '>' &&
            index + 1 < input.length &&
            input[index + 1] == '>') {
          tokens.add('>>');
          index += 1;
        } else {
          tokens.add(char);
        }
        continue;
      }
      current.write(char);
    }
    if (escaping) {
      return const _TokenizeResult(<String>[], error: 'trailing escape');
    }
    if (quote != null) {
      return const _TokenizeResult(<String>[], error: 'unterminated quote');
    }
    flush();
    return _TokenizeResult(tokens);
  }
}

String _basename(String path) {
  final normalized = path.endsWith(Platform.pathSeparator)
      ? path.substring(0, path.length - 1)
      : path;
  final index = normalized.lastIndexOf(Platform.pathSeparator);
  return index < 0 ? normalized : normalized.substring(index + 1);
}

String _friendlyIoError(Object error) {
  if (error is FileSystemException) {
    final message = error.osError?.message ?? error.message;
    return message.isEmpty ? 'file operation failed' : message;
  }
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}
