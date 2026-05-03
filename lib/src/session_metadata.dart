import 'package:flutter/foundation.dart';

import 'terminal_blocks.dart';

enum TerminalSessionKind { local, ssh }

extension TerminalSessionKindLabel on TerminalSessionKind {
  String get label {
    return switch (this) {
      TerminalSessionKind.local => 'Local shell',
      TerminalSessionKind.ssh => 'SSH session',
    };
  }
}

@immutable
class TerminalSafetyContext {
  const TerminalSafetyContext({
    this.identity = '',
    this.authorizationSource = '',
    this.validUntil = '',
  });

  factory TerminalSafetyContext.fromJson(Object? json) {
    final map = _objectMap(json);
    if (map == null) {
      return const TerminalSafetyContext();
    }
    return TerminalSafetyContext(
      identity: _stringOrEmpty(map['identity']),
      authorizationSource: _stringOrEmpty(map['authorizationSource']),
      validUntil: _stringOrEmpty(map['validUntil']),
    );
  }

  final String identity;
  final String authorizationSource;
  final String validUntil;

  bool get isEmpty =>
      identity.trim().isEmpty &&
      authorizationSource.trim().isEmpty &&
      validUntil.trim().isEmpty;

  List<String> get badges => <String>[
    if (identity.trim().isNotEmpty) 'Identity ${identity.trim()}',
    if (authorizationSource.trim().isNotEmpty)
      'Source ${authorizationSource.trim()}',
    if (validUntil.trim().isNotEmpty) 'Valid until ${validUntil.trim()}',
  ];

  TerminalSafetyContext copyWith({
    String? identity,
    String? authorizationSource,
    String? validUntil,
  }) {
    return TerminalSafetyContext(
      identity: identity ?? this.identity,
      authorizationSource: authorizationSource ?? this.authorizationSource,
      validUntil: validUntil ?? this.validUntil,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'identity': identity.trim(),
      'authorizationSource': authorizationSource.trim(),
      'validUntil': validUntil.trim(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalSafetyContext &&
        other.identity == identity &&
        other.authorizationSource == authorizationSource &&
        other.validUntil == validUntil;
  }

  @override
  int get hashCode => Object.hash(identity, authorizationSource, validUntil);
}

@immutable
class TerminalSessionMetadata {
  const TerminalSessionMetadata({
    this.kind = TerminalSessionKind.local,
    this.host = '',
    this.account = '',
    this.environment = '',
    this.project = '',
    this.safetyContext = const TerminalSafetyContext(),
  });

  factory TerminalSessionMetadata.fromJson(Object? json) {
    final map = _objectMap(json);
    if (map == null) {
      return const TerminalSessionMetadata();
    }
    return TerminalSessionMetadata(
      kind: _sessionKindFromJson(map['kind']),
      host: _stringOrEmpty(map['host']),
      account: _stringOrEmpty(map['account']),
      environment: _stringOrEmpty(map['environment']),
      project: _stringOrEmpty(map['project']),
      safetyContext: TerminalSafetyContext.fromJson(map['safetyContext']),
    );
  }

  final TerminalSessionKind kind;
  final String host;
  final String account;
  final String environment;
  final String project;
  final TerminalSafetyContext safetyContext;

  bool get isSsh => kind == TerminalSessionKind.ssh;

  bool get isDefaultLocal =>
      kind == TerminalSessionKind.local &&
      host.trim().isEmpty &&
      account.trim().isEmpty &&
      environment.trim().isEmpty &&
      project.trim().isEmpty &&
      safetyContext.isEmpty;

  List<String> get targetBadges => <String>[
    if (host.trim().isNotEmpty) 'Host ${host.trim()}',
    if (account.trim().isNotEmpty) 'Account ${account.trim()}',
    if (environment.trim().isNotEmpty) 'Env ${environment.trim()}',
    if (project.trim().isNotEmpty) 'Project ${project.trim()}',
  ];

  String? get compactContextLabel {
    return _firstNonEmpty(<String>[project, host, environment]);
  }

  String? get preferredTabTitle {
    if (!isSsh) {
      return null;
    }
    final accountAtHost = account.trim().isNotEmpty && host.trim().isNotEmpty
        ? '${account.trim()}@${host.trim()}'
        : '';
    return _firstNonEmpty(<String>[project, accountAtHost, host, environment]);
  }

  String get auditTargetEnvironment =>
      _firstNonEmpty(<String>[environment, project, host]) ?? kind.label;

  TerminalSessionMetadata copyWith({
    TerminalSessionKind? kind,
    String? host,
    String? account,
    String? environment,
    String? project,
    TerminalSafetyContext? safetyContext,
  }) {
    return TerminalSessionMetadata(
      kind: kind ?? this.kind,
      host: host ?? this.host,
      account: account ?? this.account,
      environment: environment ?? this.environment,
      project: project ?? this.project,
      safetyContext: safetyContext ?? this.safetyContext,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'host': host.trim(),
      'account': account.trim(),
      'environment': environment.trim(),
      'project': project.trim(),
      'safetyContext': safetyContext.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalSessionMetadata &&
        other.kind == kind &&
        other.host == host &&
        other.account == account &&
        other.environment == environment &&
        other.project == project &&
        other.safetyContext == safetyContext;
  }

  @override
  int get hashCode =>
      Object.hash(kind, host, account, environment, project, safetyContext);
}

@immutable
class TerminalSessionAuditEntry {
  const TerminalSessionAuditEntry({
    required this.commandText,
    required this.outputSummary,
    required this.recordedAt,
    required this.targetEnvironment,
  });

  final String commandText;
  final String outputSummary;
  final String recordedAt;
  final String targetEnvironment;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'commandText': commandText,
      'outputSummary': outputSummary,
      'recordedAt': recordedAt,
      'targetEnvironment': targetEnvironment,
    };
  }
}

@immutable
class TerminalSessionAuditSnapshot {
  const TerminalSessionAuditSnapshot({
    required this.exportedAt,
    required this.metadata,
    required this.entries,
  });

  final String exportedAt;
  final TerminalSessionMetadata metadata;
  final List<TerminalSessionAuditEntry> entries;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'exportedAt': exportedAt,
      'session': metadata.toJson(),
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }
}

TerminalSessionAuditSnapshot buildTerminalSessionAuditSnapshot({
  required TerminalSessionMetadata metadata,
  required Iterable<TerminalBlock> blocks,
  DateTime? exportedAt,
}) {
  final timestamp = (exportedAt ?? DateTime.now().toUtc()).toIso8601String();
  final targetEnvironment = metadata.auditTargetEnvironment;
  final entries = blocks
      .where((block) => block.status != TerminalBlockStatus.running)
      .where((block) => block.commandText.trim().isNotEmpty)
      .map(
        (block) => TerminalSessionAuditEntry(
          commandText: block.commandText.trim(),
          outputSummary: _summarizeOutput(block.outputText),
          recordedAt: block.recordedAt ?? timestamp,
          targetEnvironment:
              _firstNonEmpty(<String>[
                block.targetEnvironment ?? '',
                targetEnvironment,
              ]) ??
              metadata.kind.label,
        ),
      )
      .toList(growable: false);
  return TerminalSessionAuditSnapshot(
    exportedAt: timestamp,
    metadata: metadata,
    entries: entries,
  );
}

TerminalSessionKind _sessionKindFromJson(Object? value) {
  return switch (value) {
    'ssh' => TerminalSessionKind.ssh,
    _ => TerminalSessionKind.local,
  };
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

String? _firstNonEmpty(Iterable<String> values) {
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

String _summarizeOutput(String output) {
  final oneLine = output.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (oneLine.isEmpty) {
    return '';
  }
  if (oneLine.length <= 120) {
    return oneLine;
  }
  return '${oneLine.substring(0, 117)}...';
}
