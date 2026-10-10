import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../ai_models.dart';
import 'acp_environment.dart';
import 'acp_installation.dart';
import 'acp_rpc.dart';
import 'agent_backend.dart';
import 'bridge_permissions.dart';
import 'terminal_mcp_server.dart';

/// Pinned Codex ACP profile. No host shell, filesystem write, plugins or apps.
/// Agent credentials are isolated from Trail's model API configuration.
class CodexAcpBackend implements AgentBackend {
  CodexAcpBackend(this.configuration, {this.reviewOnly = false});
  final AiConfiguration configuration;
  final bool reviewOnly;
  AcpRpc? _rpc;
  TerminalMcpServer? _bridge;
  Directory? _directory;
  String? _session;
  AgentToolHandler? _tools;
  AgentEventHandler? _events;
  _AcpPromptTurn? _activePrompt;
  bool get _running => _activePrompt != null;
  bool _acceptUpdates = false;
  final _bridgePermissions = BridgePermissions();
  bool _disposed = false;
  Future<void>? _closing;
  Future<void>? _disposing;

  /// Discovery only reads installation paths; it does not start the agent or
  /// read login credentials.
  static Future<AcpInstallation> discoverInstallation() =>
      AcpInstallationDiscovery(
        environment: readAcpDiscoveryEnvironment(),
      ).discover();

  static Map<String, Object?> profile(String model) => {
    'model': model,
    'model_reasoning_effort': 'high',
    'cli_auth_credentials_store': 'file',
    'sandbox_mode': 'read-only',
    'approval_policy': 'never',
    'web_search': 'disabled',
    'project_doc_max_bytes': 0,
    'skills': {'include_instructions': false},
    'features': {
      for (final name in [
        'shell_tool',
        'unified_exec',
        'apps',
        'plugins',
        'remote_plugin',
        'multi_agent',
        'multi_agent_v2',
        'browser_use',
        'computer_use',
        'image_generation',
        'view_image',
        'workspace_dependencies',
        'skill_search',
        'skill_mcp_dependency_install',
        'memories',
        'shell_snapshot',
        'goals',
        'worktrees',
      ])
        name: false,
      'skip_host_skill_discovery': true,
    },
  };

  Future<void> _connect(AiCancellation cancellation) async {
    void check() {
      cancellation.check();
      if (_disposed) throw const AiFailure('cancelled');
    }

    check();
    if (Platform.isIOS || Platform.isAndroid) {
      throw const AiFailure('acp_desktop_only');
    }
    configuration.validate();
    await _closing;
    check();
    if (_rpc != null && !_rpc!.closed) return;
    await _closeConnection();
    check();
    _directory ??= await Directory.systemTemp.createTemp('trail-acp-');
    check();
    final directory = _directory!;
    final home = await Directory('${directory.path}/agent').create();
    check();
    final cwd = await Directory('${directory.path}/workspace').create();
    check();
    final credentials = File(readCodexAuthenticationPath());
    final isolatedAuth = File('${home.path}/auth.json');
    final hasIsolatedAuth = await isolatedAuth.exists();
    check();
    if (!hasIsolatedAuth) {
      final hasCredentials = await credentials.exists();
      check();
      if (!hasCredentials) {
        throw const AiFailure('acp_authentication');
      }
      await credentials.copy(isolatedAuth.path);
      check();
      await Process.run('/bin/chmod', ['600', isolatedAuth.path]);
      check();
    }
    final bridge = reviewOnly
        ? null
        : TerminalMcpServer((name, args) async {
            if (!_running || _tools == null || _disposed) {
              throw const AiFailure('cancelled');
            }
            return _tools!(name, args);
          });
    _bridge = bridge;
    await bridge?.start();
    check();
    final process = await Process.start(
      configuration.agentCommand,
      configuration.agentArguments,
      workingDirectory: cwd.path,
      environment: {
        // Do not inherit provider overrides, plugin config, or logging secrets.
        ...readAcpProcessEnvironment(),
        'CODEX_HOME': home.path,
        'CODEX_CONFIG': jsonEncode(profile(configuration.model)),
        'INITIAL_AGENT_MODE': 'read-only',
        'NO_BROWSER': '1',
      },
      includeParentEnvironment: false,
      runInShell: false,
    );
    final rpc = _rpc = AcpRpc(
      process,
      (method, params) {
        if (method != 'session/update' || params['sessionId'] != _session) {
          return;
        }
        final update = (params['update'] as Map? ?? {}).cast<String, Object?>();
        if (_running && _acceptUpdates) _bridgePermissions.observe(update);
        if (_running && _acceptUpdates) _events?.call(update);
      },
      permissionOption: (params) => reviewOnly
          ? null
          : _bridgePermissions.option(
              params,
              session: _session ?? '',
              active: _running && _acceptUpdates,
            ),
    );
    // Adopt a process that finished starting after cancellation before checking
    // the token, so this turn's cleanup still owns and closes it.
    check();
    final initialized = await rpc.request('initialize', {
      'protocolVersion': 1,
      'clientInfo': {'name': 'trail', 'version': '1.0.0'},
      'clientCapabilities': {
        'fs': {'readTextFile': false, 'writeTextFile': false},
        'terminal': false,
      },
    });
    check();
    if (initialized['protocolVersion'] != 1 ||
        (initialized['agentInfo'] as Map?)?['name'] !=
            '@agentclientprotocol/codex-acp' ||
        ((initialized['agentCapabilities'] as Map?)?['mcpCapabilities']
                as Map?)?['http'] !=
            true) {
      throw const AiFailure('acp_capability');
    }
    final session = await rpc.request(
      _session == null ? 'session/new' : 'session/load',
      {
        if (_session != null) 'sessionId': _session,
        'cwd': cwd.path,
        'mcpServers': [
          if (bridge != null)
            {
              'name': 'trail_terminal',
              'type': 'http',
              'url': bridge.url,
              'headers': [
                {'name': 'Authorization', 'value': 'Bearer ${bridge.token}'},
              ],
            },
        ],
      },
    );
    check();
    _session ??= session['sessionId']! as String;
    final options = (session['configOptions'] as List? ?? [])
        .cast<Map<Object?, Object?>>();
    final model = options
        .where((o) => o['category'] == 'model' || o['id'] == 'model')
        .firstOrNull;
    if (model == null) throw const AiFailure('acp_model');
    final configured = await rpc.request('session/set_config_option', {
      'sessionId': _session,
      'configId': model['id'],
      'value': configuration.model,
    });
    check();
    final verified = (configured['configOptions'] as List? ?? [])
        .cast<Map<Object?, Object?>>()
        .where((o) => o['id'] == model['id'])
        .firstOrNull;
    if (verified?['currentValue'] != configuration.model) {
      throw const AiFailure('acp_model');
    }
    _events?.call({
      'sessionUpdate': 'trail_connection',
      'agent': initialized['agentInfo'],
      'session_id': _session,
      'model': verified!['currentValue'],
      'reasoning_effort': 'high',
      'reconnected': session['sessionId'] == null,
    });
  }

  @override
  Future<void> prompt(
    String prompt, {
    required AgentToolHandler tools,
    required AgentEventHandler events,
    required AiCancellation cancellation,
  }) async {
    cancellation.check();
    while (_activePrompt != null) {
      final previous = _activePrompt!;
      if (!previous.cancellation.isCancelled) {
        throw const AiFailure('acp_busy');
      }
      // A supplement can arrive synchronously after cancellation. The old
      // connect and its cleanup must quiesce before replacing shared handlers.
      await previous.finished.future;
      cancellation.check();
    }
    if (_disposed) throw const AiFailure('cancelled');
    final turn = _activePrompt = _AcpPromptTurn();
    _tools = tools;
    _events = events;
    cancellation.onCancel(turn.cancellation.cancel);
    turn.cancellation.onCancel(() {
      if (turn.finished.isCompleted) return;
      if (!turn.cancelled.isCompleted) turn.cancelled.complete();
      _acceptUpdates = false;
      _tools = null;
      _events = null;
      final rpc = _rpc;
      if (rpc != null && !rpc.closed && _session != null) {
        try {
          rpc.notify('session/cancel', {'sessionId': _session});
        } on Object {
          // Closing the transport also cancels a prompt if notification fails.
        }
      }
      if (rpc != null) {
        _rpc = null;
        final closing = _closing = rpc.dispose();
        // Closing the RPC rejects even session-less initialize/new requests.
        // Keep the bridge until _connect has drained: start() may still own an
        // in-flight bind that needs to finish before it can be closed.
        unawaited(closing.then<void>((_) {}, onError: (Object _) {}));
      }
    });
    try {
      await _connect(turn.cancellation);
      turn.cancellation.check();
      _acceptUpdates = true;
      final rpc = _rpc!;
      final result = await Future.any<Map<String, Object?>>([
        rpc.request('session/prompt', {
          'sessionId': _session,
          'prompt': [
            {'type': 'text', 'text': prompt},
          ],
        }, timeout: const Duration(hours: 2)),
        turn.cancelled.future.then((_) => throw const AiFailure('cancelled')),
      ]);
      turn.cancellation.check();
      final quota = (result['_meta'] as Map?)?['quota'] as Map?;
      final models = quota?['model_usage'] as List?;
      if (models == null ||
          models.isEmpty ||
          models.any((m) => (m as Map)['model'] != configuration.model)) {
        throw const AiFailure('acp_model');
      }
      events({'sessionUpdate': 'trail_complete', ...result});
    } on Object {
      try {
        await _closeConnection();
      } on Object {
        // Preserve the original protocol failure; a canceled turn is normalized
        // below regardless of which transport request first noticed shutdown.
      }
      turn.cancellation.check();
      rethrow;
    } finally {
      _acceptUpdates = false;
      _bridgePermissions.clear();
      _tools = null;
      _events = null;
      _activePrompt = null;
      turn.finished.complete();
    }
  }

  Future<void> _closeConnection() {
    final rpc = _rpc;
    final bridge = _bridge;
    _rpc = null;
    _bridge = null;
    return _closing = Future.wait<void>([
      ?_closing,
      if (rpc != null) rpc.dispose(),
      if (bridge != null) bridge.dispose(),
    ]).then((_) {});
  }

  @override
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    final turn = _activePrompt;
    turn?.cancellation.cancel();
    await turn?.finished.future;
    _tools = null;
    _events = null;
    await _closeConnection();
    if (_directory != null && await _directory!.exists()) {
      await _directory!.delete(recursive: true);
    }
  }
}

class _AcpPromptTurn {
  final cancellation = AiCancellation();
  final cancelled = Completer<void>();
  final finished = Completer<void>();
}
