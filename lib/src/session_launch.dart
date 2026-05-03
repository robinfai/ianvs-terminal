import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart' as terminal;

enum TerminalSessionLaunchKind { localShell, sshCommand }

@immutable
class TerminalSessionLaunchProfile {
  const TerminalSessionLaunchProfile.localShell()
    : kind = TerminalSessionLaunchKind.localShell,
      host = '',
      account = '';

  const TerminalSessionLaunchProfile.sshCommand({
    required this.host,
    this.account = '',
  }) : kind = TerminalSessionLaunchKind.sshCommand;

  factory TerminalSessionLaunchProfile.fromJson(Object? json) {
    final map = _objectMap(json);
    if (map == null) {
      return const TerminalSessionLaunchProfile.localShell();
    }
    return switch (_kindFromJson(map['kind'])) {
      TerminalSessionLaunchKind.sshCommand =>
        _sshProfileFromJson(map) ??
            const TerminalSessionLaunchProfile.localShell(),
      TerminalSessionLaunchKind.localShell =>
        const TerminalSessionLaunchProfile.localShell(),
    };
  }

  final TerminalSessionLaunchKind kind;
  final String host;
  final String account;

  bool get isLocalShell => kind == TerminalSessionLaunchKind.localShell;
  bool get isSshCommand =>
      kind == TerminalSessionLaunchKind.sshCommand && isValidSshHost(host);
  bool get isDefaultLocal =>
      isLocalShell && host.trim().isEmpty && account.trim().isEmpty;

  String get authority {
    final trimmedHost = host.trim();
    final trimmedAccount = account.trim();
    if (trimmedAccount.isEmpty) {
      return trimmedHost;
    }
    return '$trimmedAccount@$trimmedHost';
  }

  String get transportLabel {
    if (isSshCommand) {
      return 'SSH command';
    }
    return 'Local shell';
  }

  TerminalSessionLaunchProfile copyWith({String? host, String? account}) {
    if (!isSshCommand) {
      return this;
    }
    return TerminalSessionLaunchProfile.sshCommand(
      host: host ?? this.host,
      account: account ?? this.account,
    );
  }

  terminal.TerminalSessionConfig applyTo(
    terminal.TerminalSessionConfig config,
  ) {
    if (!isSshCommand) {
      return config;
    }
    return config.copyWith(
      launch: config.launch.copyWith(
        program: _defaultSshProgram(),
        args: <String>[authority],
      ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      if (isSshCommand) 'host': host.trim(),
      if (isSshCommand && account.trim().isNotEmpty) 'account': account.trim(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalSessionLaunchProfile &&
        other.kind == kind &&
        other.host == host &&
        other.account == account;
  }

  @override
  int get hashCode => Object.hash(kind, host, account);
}

TerminalSessionLaunchProfile? _sshProfileFromJson(Map<String, Object?> map) {
  final host = _stringOrEmpty(map['host']);
  if (!isValidSshHost(host)) {
    return null;
  }
  return TerminalSessionLaunchProfile.sshCommand(
    host: host,
    account: _stringOrEmpty(map['account']),
  );
}

TerminalSessionLaunchKind _kindFromJson(Object? value) {
  return switch (value) {
    'sshCommand' => TerminalSessionLaunchKind.sshCommand,
    _ => TerminalSessionLaunchKind.localShell,
  };
}

String _defaultSshProgram() {
  for (final candidate in const <String>['/usr/bin/ssh', '/bin/ssh']) {
    if (File(candidate).existsSync()) {
      return candidate;
    }
  }
  return 'ssh';
}

Map<String, Object?>? _objectMap(Object? value) {
  if (value is Map) {
    return value.map(
      (key, entry) => MapEntry(key.toString(), entry as Object?),
    );
  }
  return null;
}

String _stringOrEmpty(Object? value) {
  if (value is String) {
    return value.trim();
  }
  return '';
}

String? sshHostValidationError(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return 'Host is required.';
  }
  if (!isValidSshHost(normalized)) {
    return 'Host must be a hostname or address, not ssh options.';
  }
  return null;
}

bool isValidSshHost(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.startsWith('-')) {
    return false;
  }
  return !RegExp(r'\s').hasMatch(normalized);
}
