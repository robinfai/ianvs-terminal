import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../ai_models.dart';
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
  bool _running = false;
  bool _acceptUpdates = false;
  final _bridgePermissions = BridgePermissions();
  bool _disposed = false;
  Future<void>? _closing;

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

  Future<void> _connect() async {
    if (_disposed) throw const AiFailure('cancelled');
    if (Platform.isIOS || Platform.isAndroid) {
      throw const AiFailure('acp_desktop_only');
    }
    configuration.validate();
    await _closing;
    if (_rpc != null && !_rpc!.closed) return;
    await _rpc?.dispose();
    await _bridge?.dispose();
    _directory ??= await Directory.systemTemp.createTemp('trail-acp-');
    final directory = _directory!;
    final home = await Directory('${directory.path}/agent').create();
    final cwd = await Directory('${directory.path}/workspace').create();
    final credentials = File(
      '${Platform.environment['CODEX_HOME'] ?? '${Platform.environment['HOME'] ?? ''}/.codex'}/auth.json',
    );
    final isolatedAuth = File('${home.path}/auth.json');
    if (!await isolatedAuth.exists()) {
      if (!await credentials.exists()) {
        throw const AiFailure('acp_authentication');
      }
      await credentials.copy(isolatedAuth.path);
      await Process.run('/bin/chmod', ['600', isolatedAuth.path]);
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
    final inherited = <String, String?>{
      'PATH': Platform.environment['PATH'],
      'HOME': Platform.environment['HOME'],
      'USER': Platform.environment['USER'],
      'TMPDIR': Platform.environment['TMPDIR'],
      'LANG': Platform.environment['LANG'],
      'LC_ALL': Platform.environment['LC_ALL'],
    };
    final process = await Process.start(
      configuration.agentCommand,
      configuration.agentArguments,
      workingDirectory: cwd.path,
      environment: {
        // Do not inherit provider overrides, plugin config, or logging secrets.
        for (final entry in inherited.entries)
          if (entry.value != null) entry.key: entry.value!,
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
    final initialized = await rpc.request('initialize', {
      'protocolVersion': 1,
      'clientInfo': {'name': 'trail', 'version': '1.0.0'},
      'clientCapabilities': {
        'fs': {'readTextFile': false, 'writeTextFile': false},
        'terminal': false,
      },
    });
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
    if (_running) throw const AiFailure('acp_busy');
    _running = true;
    _tools = tools;
    _events = events;
    final cancelled = Completer<void>();
    var finished = false;
    cancellation.onCancel(() {
      if (finished) return;
      if (!cancelled.isCompleted) cancelled.complete();
      final rpc = _rpc;
      if (rpc != null && !rpc.closed && _session != null) {
        rpc.notify('session/cancel', {'sessionId': _session});
      }
    });
    try {
      await _connect();
      cancellation.check();
      _acceptUpdates = true;
      final rpc = _rpc!;
      final result = await Future.any<Map<String, Object?>>([
        rpc.request('session/prompt', {
          'sessionId': _session,
          'prompt': [
            {'type': 'text', 'text': prompt},
          ],
        }, timeout: const Duration(hours: 2)),
        cancelled.future.then((_) => throw const AiFailure('cancelled')),
      ]);
      cancellation.check();
      final quota = (result['_meta'] as Map?)?['quota'] as Map?;
      final models = quota?['model_usage'] as List?;
      if (models == null ||
          models.isEmpty ||
          models.any((m) => (m as Map)['model'] != configuration.model)) {
        throw const AiFailure('acp_model');
      }
      events({'sessionUpdate': 'trail_complete', ...result});
    } on Object {
      final rpc = _rpc;
      _rpc = null;
      _closing = rpc?.dispose();
      rethrow;
    } finally {
      finished = true;
      _acceptUpdates = false;
      _bridgePermissions.clear();
      _running = false;
      _tools = null;
      _events = null;
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _tools = null;
    await _rpc?.dispose();
    await _closing;
    await _bridge?.dispose();
    if (_directory != null && await _directory!.exists()) {
      await _directory!.delete(recursive: true);
    }
  }
}
