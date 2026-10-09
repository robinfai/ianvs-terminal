import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../ui/components/app_dropdown_form_field.dart';
import '../../ui/foundation/app_motion.dart';
import 'acp/acp_installation.dart';
import 'acp/codex_acp_backend.dart';
import 'ai_api_client.dart';
import 'ai_models.dart';
import 'ai_settings.dart';
import 'ai_strings.dart';

Future<void> showAiSettings(
  BuildContext context,
  AiSettingsController settings, {
  ValueChanged<bool>? onSaved,
}) async {
  final result = await showDialog<bool>(
    context: context,
    animationStyle: appDialogAnimation(context),
    builder: (_) => AiSettingsDialog(settings: settings),
  );
  if (!context.mounted || result == null) return;
  if (onSaved != null) {
    onSaved(result);
    return;
  }
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(
        result
            ? (zh ? 'AI 连接已保存，任务尚未发送。' : 'AI connection saved. Task not sent.')
            : (zh ? 'AI 连接配置已移除。' : 'AI connection configuration removed.'),
      ),
    ),
  );
}

class AiSettingsDialog extends StatefulWidget {
  const AiSettingsDialog({required this.settings, this.discoverAcp, super.key});
  final AiSettingsController settings;
  final Future<AcpInstallation> Function()? discoverAcp;
  @override
  State<AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<AiSettingsDialog> {
  final _endpoint = TextEditingController();
  final _key = TextEditingController();
  final _model = TextEditingController();
  final _agentCommand = TextEditingController();
  final _agentArguments = TextEditingController(text: '[]');
  AiBackendKind _backend = AiBackendKind.llm;
  AiApprovalMode _approvalMode = AiApprovalMode.smart;
  AiApprovalSensitivity _approvalSensitivity = AiApprovalSensitivity.relaxed;
  String? _apiModel;
  String? _acpModel;
  bool _busy = false;
  bool _loaded = false;
  bool _tested = false;
  bool _detecting = false;
  bool _autoDetectionAttempted = false;
  bool _savedAcpUnsupported = false;
  int _detectionEpoch = 0;
  String? _discoveryNotice;
  String? _error;
  AiCancellation? _test;
  bool get zh => Localizations.localeOf(context).languageCode == 'zh';
  String t(String en, String cn) => zh ? cn : en;
  bool get _supportsLocalAcp => switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.android => false,
    _ => true,
  };

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await widget.settings.loaded;
    if (!mounted) return;
    final value = widget.settings.configuration;
    if (value != null) _fill(value);
    setState(() {
      _loaded = true;
      _error = widget.settings.error;
    });
    _maybeDiscoverAcp();
  }

  void _fill(AiConfiguration value) {
    _approvalMode = value.approvalMode;
    _approvalSensitivity = value.approvalSensitivity;
    _savedAcpUnsupported =
        value.backend == AiBackendKind.acp && !_supportsLocalAcp;
    _backend = _savedAcpUnsupported ? AiBackendKind.llm : value.backend;
    _agentCommand.text = value.agentCommand;
    _agentArguments.text = jsonEncode(value.agentArguments);
    _endpoint.text = value.endpoint;
    _key.text = value.apiKey;
    _model.text = _savedAcpUnsupported ? '' : value.model;
    if (value.backend == AiBackendKind.acp) {
      _acpModel = value.model;
    } else {
      _apiModel = value.model;
    }
    _tested = false;
  }

  AiConfiguration get _value {
    if (_backend == AiBackendKind.acp) {
      if (!_supportsLocalAcp) throw const AiFailure('acp_desktop_only');
      try {
        return AiConfiguration.acp(
          approvalMode: _approvalMode,
          approvalSensitivity: _approvalSensitivity,
          agentCommand: _agentCommand.text.trim(),
          agentArguments: (jsonDecode(_agentArguments.text) as List)
              .cast<String>(),
          model: _model.text.trim(),
        );
      } on Object {
        throw const AiFailure('configuration');
      }
    }
    return AiConfiguration(
      approvalMode: _approvalMode,
      approvalSensitivity: _approvalSensitivity,
      endpoint: _endpoint.text.trim(),
      apiKey: _key.text.trim(),
      model: _model.text.trim(),
    );
  }

  void _edited(String _) => setState(() {
    _tested = false;
    _error = null;
    _discoveryNotice = null;
  });

  void _selectBackend(AiBackendKind? value) {
    if (value == null ||
        value == _backend ||
        (value == AiBackendKind.acp && !_supportsLocalAcp)) {
      return;
    }
    setState(() {
      if (_backend == AiBackendKind.acp) {
        _acpModel = _model.text;
      } else {
        _apiModel = _model.text;
      }
      _backend = value;
      _model.text = _backend == AiBackendKind.acp
          ? (_acpModel ?? 'gpt-5.6-sol')
          : (_apiModel ?? '');
      _tested = false;
      _error = null;
      _discoveryNotice = null;
      _detecting = false;
      _detectionEpoch++;
    });
    _maybeDiscoverAcp();
  }

  void _maybeDiscoverAcp() {
    if (!_supportsLocalAcp ||
        _backend != AiBackendKind.acp ||
        _autoDetectionAttempted ||
        _agentCommand.text.trim().isNotEmpty ||
        !{'', '[]'}.contains(_agentArguments.text.trim())) {
      return;
    }
    _autoDetectionAttempted = true;
    unawaited(_detectAcp());
  }

  Future<void> _detectAcp() async {
    if (!_supportsLocalAcp) return;
    final epoch = ++_detectionEpoch;
    final commandBefore = _agentCommand.text;
    final argumentsBefore = _agentArguments.text;
    setState(() {
      _detecting = true;
      _tested = false;
      _error = null;
      _discoveryNotice = null;
    });
    try {
      final installation =
          await (widget.discoverAcp ?? CodexAcpBackend.discoverInstallation)()
              .timeout(const Duration(seconds: 8));
      if (!mounted || epoch != _detectionEpoch) return;
      setState(() {
        if (_agentCommand.text != commandBefore ||
            _agentArguments.text != argumentsBefore) {
          _discoveryNotice = 'acp_discovery_edited';
          return;
        }
        _agentCommand.text = installation.command;
        _agentArguments.text = jsonEncode(installation.arguments);
        if (_model.text.trim().isEmpty) _model.text = 'gpt-5.6-sol';
        _discoveryNotice = 'acp_discovery_found';
      });
    } on Object catch (failure) {
      if (mounted && epoch == _detectionEpoch) {
        setState(() {
          _error = failure is AiFailure ? failure.code : 'acp_discovery_failed';
        });
      }
    } finally {
      if (mounted && epoch == _detectionEpoch) {
        setState(() => _detecting = false);
      }
    }
  }

  Future<void> _save({bool remove = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.settings.save(remove ? null : _value);
      if (mounted) Navigator.of(context).pop(!remove);
    } on Object catch (failure) {
      if (mounted) {
        final code = failure is AiFailure ? failure.code : 'storage';
        setState(() {
          _error = code == 'storage'
              ? (remove ? 'configuration_remove' : 'configuration_save')
              : code;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkConnection() async {
    setState(() {
      _busy = true;
      _error = null;
      _tested = false;
    });
    final cancellation = _test = AiCancellation();
    try {
      if (_backend == AiBackendKind.acp) {
        final agent = CodexAcpBackend(_value);
        try {
          await agent.prompt(
            'Connection check. Reply with OK. Do not use tools.',
            tools: (_, _) async => throw const AiFailure('read_only'),
            events: (_) {},
            cancellation: cancellation,
          );
        } finally {
          await agent.dispose();
        }
      } else {
        await const AiApiClient().complete(_value, [
          {
            'role': 'user',
            'content':
                'Trail connection check. Reply with a brief greeting without tool calls.',
          },
        ], cancellation);
      }
      if (mounted) setState(() => _tested = true);
    } on Object catch (failure) {
      if (mounted) {
        setState(
          () => _error = failure is AiFailure ? failure.code : 'connection',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _detectionEpoch++;
    _test?.cancel();
    _endpoint.dispose();
    _key.dispose();
    _model.dispose();
    _agentCommand.dispose();
    _agentArguments.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('ai-settings-dialog'),
    // A tight preferred width avoids intrinsic layout through the anchored
    // dropdown. Dialog still clamps this to the available window width.
    constraints: const BoxConstraints.tightFor(width: 528),
    title: Text(t('AI connection', 'AI 连接')),
    scrollable: true,
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDropdownFormField<AiBackendKind>(
            isExpanded: true,
            key: const Key('ai-backend'),
            initialValue: _backend,
            decoration: InputDecoration(
              labelText: t('Connection type', '连接方式'),
            ),
            items: [
              DropdownMenuItem(
                value: AiBackendKind.llm,
                child: Text(t('Model API', '模型 API')),
              ),
              if (_supportsLocalAcp)
                const DropdownMenuItem(
                  value: AiBackendKind.acp,
                  child: Text('Codex ACP'),
                ),
            ],
            onChanged: !_loaded || _busy || !_supportsLocalAcp
                ? null
                : _selectBackend,
          ),
          const SizedBox(height: 16),
          if (_savedAcpUnsupported) ...[
            Text(
              t(
                'Local Codex ACP is available on desktop only. Configure a Model API connection for this device. Your saved connection stays unchanged until you save; saving does not send a task.',
                '本地 Codex ACP 仅支持桌面。请为此设备配置模型 API 连接。保存前保留原连接设置；保存不会发送任务。',
              ),
              key: const Key('ai-acp-unavailable-on-mobile'),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            _backend == AiBackendKind.acp
                ? t(
                    'Run Codex ACP on this Mac using your Codex login. Commands are reviewed here and sent to the current terminal.',
                    '在本机运行 Codex ACP，使用已有 Codex 登录。命令在此批准后发送到当前终端。',
                  )
                : t(
                    'Connect directly to an OpenAI-compatible endpoint. Configuration stays on this device.',
                    '直接连接 OpenAI 兼容端点。配置仅保存在本机。',
                  ),
          ),
          const SizedBox(height: 20),
          if (_backend == AiBackendKind.acp) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const Key('ai-detect-acp'),
                onPressed: _loaded && !_busy && !_detecting ? _detectAcp : null,
                icon: const Icon(Icons.search, size: 18),
                label: Text(t('Auto-detect', '自动检测')),
              ),
            ),
            if (_detecting) ...[
              const LinearProgressIndicator(),
              Text(
                t(
                  'Looking for a local Codex ACP installation…',
                  '正在查找本机 Codex ACP…',
                ),
              ),
            ],
            if (_discoveryNotice != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  aiErrorText(_discoveryNotice!, zh),
                  key: const Key('ai-acp-discovery-notice'),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('ai-agent-command'),
              controller: _agentCommand,
              enabled: _loaded && !_busy,
              autocorrect: false,
              onChanged: _edited,
              decoration: InputDecoration(
                labelText: t('Executable path', '可执行文件路径'),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('ai-agent-arguments'),
              controller: _agentArguments,
              enabled: _loaded && !_busy,
              autocorrect: false,
              onChanged: _edited,
              decoration: InputDecoration(
                labelText: t('Arguments (JSON array)', '启动参数（JSON 数组）'),
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            TextField(
              key: const Key('ai-endpoint'),
              controller: _endpoint,
              enabled: _loaded && !_busy,
              autocorrect: false,
              keyboardType: TextInputType.url,
              onChanged: _edited,
              decoration: const InputDecoration(
                labelText: 'Endpoint',
                hintText: 'https://api.example.com/v1',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('ai-api-key'),
              controller: _key,
              enabled: _loaded && !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: _edited,
              decoration: const InputDecoration(labelText: 'API Key'),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            key: const Key('ai-model'),
            controller: _model,
            enabled: _loaded && !_busy,
            autocorrect: false,
            onChanged: _edited,
            decoration: InputDecoration(labelText: t('Model', '模型')),
          ),
          const SizedBox(height: 16),
          AppDropdownFormField<AiApprovalMode>(
            key: const Key('ai-approval-mode'),
            initialValue: _approvalMode,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: t('Command approval', '命令审批'),
            ),
            items: [
              DropdownMenuItem(
                value: AiApprovalMode.smart,
                child: Text(t('Smart review', '智能审核')),
              ),
              DropdownMenuItem(
                value: AiApprovalMode.manual,
                child: Text(t('Confirm every command', '每次确认')),
              ),
            ],
            onChanged: !_loaded || _busy
                ? null
                : (value) {
                    if (value != null) setState(() => _approvalMode = value);
                  },
          ),
          if (_approvalMode == AiApprovalMode.smart) ...[
            const SizedBox(height: 16),
            AppDropdownFormField<AiApprovalSensitivity>(
              key: const Key('ai-approval-sensitivity'),
              initialValue: _approvalSensitivity,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: t('Review sensitivity', '审核敏感性'),
              ),
              items: [
                DropdownMenuItem(
                  value: AiApprovalSensitivity.cautious,
                  child: Text(t('Cautious', '谨慎')),
                ),
                DropdownMenuItem(
                  value: AiApprovalSensitivity.balanced,
                  child: Text(t('Standard', '标准')),
                ),
                DropdownMenuItem(
                  value: AiApprovalSensitivity.relaxed,
                  child: Text(t('Relaxed · confirm high risk', '宽松 · 高危确认')),
                ),
              ],
              onChanged: !_loaded || _busy
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _approvalSensitivity = value);
                      }
                    },
            ),
            const SizedBox(height: 8),
            Text(switch (_approvalSensitivity) {
              AiApprovalSensitivity.cautious => t(
                'Automatically allow low-risk, read-only commands. Confirm changes.',
                '自动放行低风险只读命令；修改操作需确认。',
              ),
              AiApprovalSensitivity.balanced => t(
                'Automatically allow low-risk reads and recoverable changes. Confirm medium and high risk.',
                '自动放行低风险查询和可恢复修改；中、高风险需确认。',
              ),
              AiApprovalSensitivity.relaxed => t(
                'Automatically allow low- and medium-risk actions within your task. Confirm high-risk actions.',
                '自动放行任务范围内的低、中风险操作；高危操作需确认。',
              ),
            }, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Text(
            _approvalMode == AiApprovalMode.smart
                ? t(
                    'Each command is independently reviewed using this connection. Unclear risk, unavailable review, and your explicit confirmation requirements still need confirmation. Reviews add time and usage.',
                    '每条命令使用此连接独立审核。风险不明、审核不可用或你明确要求确认时，仍需确认。审核会增加等待时间和用量。',
                  )
                : t(
                    'Review and confirm every command before it runs.',
                    '执行前逐条审阅并确认命令。',
                  ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (_backend == AiBackendKind.llm)
                TextButton(
                  key: const Key('ai-use-mock'),
                  onPressed: _loaded && !_busy
                      ? () =>
                            setState(() => _fill(const AiConfiguration.mock()))
                      : null,
                  child: Text(t('Local mock', '本机 Mock')),
                ),
              TextButton(
                key: const Key('ai-test-connection'),
                onPressed: _loaded && !_busy && !_detecting
                    ? _checkConnection
                    : null,
                child: Text(t('Test connection', '测试连接')),
              ),
            ],
          ),
          if (_busy || !_loaded) const LinearProgressIndicator(),
          if (!_loaded) Text(t('Loading saved configuration…', '正在读取已保存的配置…')),
          if (_tested)
            Text(
              t('Connection succeeded. Not saved yet.', '连接成功，尚未保存。'),
              key: const Key('ai-connection-ok'),
            ),
          if (_error != null)
            Text(
              aiErrorText(_error!, zh),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 8),
          if (_backend == AiBackendKind.llm)
            Text(
              t(
                'For an iPhone, use the Mac’s LAN address instead of 127.0.0.1.',
                '在 iPhone 上使用时，请将 127.0.0.1 替换为 Mac 的局域网地址。',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    ),
    actions: [
      if (widget.settings.configuration != null)
        TextButton(
          key: const Key('ai-remove-settings'),
          onPressed: _busy || _detecting ? null : () => _save(remove: true),
          child: Text(t('Disconnect', '断开配置')),
        ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: Text(t('Cancel', '取消')),
      ),
      FilledButton(
        key: const Key('ai-save-settings'),
        onPressed: _loaded && !_busy && !_detecting ? _save : null,
        child: Text(t('Save', '保存')),
      ),
    ],
  );
}
