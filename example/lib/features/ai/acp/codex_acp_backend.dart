import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:ianvs_acp_runtime/ianvs_acp_runtime.dart';

import '../ai_models.dart';
import 'acp_environment.dart';
import 'acp_installation.dart';

import 'acp_runtime_connection.dart';
import 'agent_backend.dart';
import 'bridge_permissions.dart';
import 'terminal_mcp_server.dart';

/// Pinned Codex ACP profile. No host shell, filesystem write, plugins or apps.
/// Agent credentials are isolated from Trail's model API configuration.
class CodexAcpBackend implements AgentBackend {
  CodexAcpBackend(this.configuration, {this.reviewOnly = false});
  final AiConfiguration configuration;
  final bool reviewOnly;
  AcpRuntimeConnection? _rpc;
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
    if (!Platform.isMacOS) {
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
      _restrictAuthentication(isolatedAuth.path);
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
    final rpc = _rpc = AcpRuntimeConnection(
      onUpdate: (update) {
        if (!_running || !_acceptUpdates || update['sessionId'] != _session) {
          return;
        }
        if ({'tool_call', 'plan', 'thought'}.contains(update['kind'])) {
          _events?.call({'sessionUpdate': 'trail_content', ...update});
        } else if (update['kind'] == 'assistant_text') {
          _events?.call({
            'sessionUpdate': 'agent_message_chunk',
            'content': {'type': 'text', 'text': update['text'] ?? ''},
          });
        }
      },
      permissionOption: (request) => reviewOnly
          ? null
          : _bridgePermissions.option(
              request,
              session: _session ?? '',
              active: _running && _acceptUpdates,
            ),
    );
    final initialized = await rpc.start(
      () => rpc.runtime.startAgent(
        agentName: 'Trail Codex',
        command: configuration.agentCommand,
        args: configuration.agentArguments,
        processCwd: cwd.path,
        environmentPolicy: AcpEnvironmentPolicy.replace,
        maxRestartAttempts: 0,
        environment: {
          ...readAcpProcessEnvironment(),
          'CODEX_HOME': home.path,
          'CODEX_CONFIG': jsonEncode(profile(configuration.model)),
          'INITIAL_AGENT_MODE': 'read-only',
          'NO_BROWSER': '1',
        },
        mcpServers: [
          if (bridge != null)
            {
              'name': 'trail_terminal',
              'type': 'http',
              'url': bridge.url,
              'headers': {'Authorization': 'Bearer ${bridge.token}'},
            },
        ],
      ),
    );
    check();
    if (initialized['protocolVersion'] != 1 ||
        (initialized['agentInfo'] as Map?)?['name'] !=
            '@agentclientprotocol/codex-acp' ||
        initialized['mcpHttp'] != true) {
      throw const AiFailure('acp_capability');
    }
    final reconnected = _session != null;
    final session = await rpc.session(cwd: cwd.path, sessionId: _session);
    check();
    _session = session['sessionId']! as String;
    final options = (session['configOptions'] as List? ?? [])
        .cast<Map<Object?, Object?>>();
    final model = options
        .where((o) => o['category'] == 'model' || o['id'] == 'model')
        .firstOrNull;
    if (model == null) throw const AiFailure('acp_model');
    final configured = await rpc.configure(
      sessionId: _session!,
      configId: model['id']! as String,
      value: configuration.model,
    );
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
      'reconnected': reconnected,
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
      final prompting = _acceptUpdates;
      _acceptUpdates = false;
      _tools = null;
      _events = null;
      final rpc = _rpc;
      void disconnect() {
        if (rpc == null || !identical(_rpc, rpc)) return;
        _rpc = null;
        final closing = _closing = rpc.dispose();
        unawaited(closing.then<void>((_) {}, onError: (Object _) {}));
      }

      if (prompting && rpc != null && !rpc.closed && _session != null) {
        try {
          rpc.cancel(_session!);
          // A cancellation notification is not completion. Let the original
          // request settle; a non-responsive agent is forcibly disconnected.
          turn.cancelTimer = Timer(const Duration(seconds: 4), disconnect);
        } on Object {
          disconnect();
        }
      } else {
        // There is no prompt to cancel during initialize/new/config/load.
        disconnect();
      }
    });
    try {
      await _connect(turn.cancellation);
      turn.cancellation.check();
      _acceptUpdates = true;
      final rpc = _rpc!;
      final result = await rpc.prompt(_session!, prompt);
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
      turn.cancelTimer?.cancel();
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
  Timer? cancelTimer;
  final finished = Completer<void>();
}

// Do not spawn a Dart child while native ACP/PTY children are alive: Dart's
// macOS child reaper can consume their exit statuses. chmod needs no process.
void _restrictAuthentication(String path) {
  final chmod = DynamicLibrary.process()
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Uint16),
        int Function(Pointer<Utf8>, int)
      >('chmod');
  final nativePath = path.toNativeUtf8();
  try {
    if (chmod(nativePath, 384) != 0) {
      throw const AiFailure('acp_authentication');
    }
  } finally {
    malloc.free(nativePath);
  }
}
