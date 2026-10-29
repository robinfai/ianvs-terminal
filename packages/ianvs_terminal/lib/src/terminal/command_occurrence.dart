import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'command_block.dart';

/// The transport actually created by the runtime. Shell-reported host names
/// are separate evidence and never change this connection identity.
enum CommandTransportKind { local, ssh, replay }

@immutable
class CommandTransportIdentity {
  const CommandTransportIdentity({
    required this.kind,
    this.host,
    this.user,
    this.port,
  });

  final CommandTransportKind kind;
  final String? host;
  final String? user;
  final int? port;
}

@immutable
class CommandOccurrenceScope {
  const CommandOccurrenceScope({
    required this.sessionId,
    required this.sessionEpoch,
    required this.transport,
  });

  final String sessionId;
  final int sessionEpoch;
  final CommandTransportIdentity transport;
}

enum CommandOccurrenceLifecycle { running, suspended, finished, unknown }

enum CommandOutputRetention { retained, partial, unavailable, unknown }

/// Metadata projected from a native command block, not another execution log.
/// Missing bounded-list entries retain metadata but cannot claim their output
/// was evicted: it may simply be outside the current list window.
@immutable
class CommandOccurrence {
  const CommandOccurrence({
    required this.scope,
    required this.blockId,
    required this.presentationBlockId,
    required this.command,
    required this.cwd,
    required this.lifecycle,
    required this.outputRetention,
    this.contextId,
    this.sftpContextId,
    this.submissionId,
    this.shellHostname,
    this.shellUsername,
    this.startedAt,
    this.finishedAt,
    this.exitCode,
  });

  factory CommandOccurrence.fromBlock(
    CommandBlock block,
    CommandOccurrenceScope scope,
  ) => CommandOccurrence(
    scope: scope,
    blockId: block.sourceBlockId ?? block.id,
    presentationBlockId: block.id,
    command: block.command,
    cwd: block.cwd,
    contextId: block.contextId,
    sftpContextId: block.sftpContextId,
    submissionId: block.submissionId,
    shellHostname: block.shellHostname,
    shellUsername: block.shellUsername,
    startedAt: block.startedAt,
    finishedAt: block.finishedAt,
    exitCode: block.exitCode,
    lifecycle: block.running
        ? (block.suspended
              ? CommandOccurrenceLifecycle.suspended
              : CommandOccurrenceLifecycle.running)
        : CommandOccurrenceLifecycle.finished,
    outputRetention: block.evicted
        ? (block.totalLines > 0
              ? CommandOutputRetention.partial
              : CommandOutputRetention.unavailable)
        : CommandOutputRetention.retained,
  );

  final CommandOccurrenceScope scope;
  final String blockId;
  final String presentationBlockId;
  final String command;
  final String cwd;
  final String? contextId;
  final String? sftpContextId;
  final String? submissionId;
  final String? shellHostname;
  final String? shellUsername;
  final int? startedAt;
  final int? finishedAt;
  final int? exitCode;
  final CommandOccurrenceLifecycle lifecycle;
  final CommandOutputRetention outputRetention;

  /// Native block IDs are unique only within one session generation.
  String get id => jsonEncode([scope.sessionId, scope.sessionEpoch, blockId]);

  /// Unknown is distinct from success, including a lost completion event.
  bool? get succeeded =>
      lifecycle != CommandOccurrenceLifecycle.finished || exitCode == null
      ? null
      : exitCode == 0;

  bool? get outputRetained => switch (outputRetention) {
    CommandOutputRetention.retained || CommandOutputRetention.partial => true,
    CommandOutputRetention.unavailable => false,
    CommandOutputRetention.unknown => null,
  };

  CommandOccurrence withoutCurrentOutput({bool unavailable = false}) =>
      CommandOccurrence(
        scope: scope,
        blockId: blockId,
        presentationBlockId: presentationBlockId,
        command: command,
        cwd: cwd,
        contextId: contextId,
        sftpContextId: sftpContextId,
        submissionId: submissionId,
        shellHostname: shellHostname,
        shellUsername: shellUsername,
        startedAt: startedAt,
        finishedAt: finishedAt,
        exitCode: exitCode,
        lifecycle: lifecycle == CommandOccurrenceLifecycle.finished
            ? lifecycle
            : CommandOccurrenceLifecycle.unknown,
        outputRetention:
            unavailable || outputRetention == CommandOutputRetention.unavailable
            ? CommandOutputRetention.unavailable
            : CommandOutputRetention.unknown,
      );
}
