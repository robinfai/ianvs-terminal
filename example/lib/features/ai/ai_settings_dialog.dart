import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

import '../../ui/components/app_configuration_field.dart';
import '../../ui/components/app_dropdown_form_field.dart';
import '../../ui/components/app_grouped_section.dart';
import '../../ui/components/app_notifications.dart';
import 'acp/acp_installation.dart';
import 'acp/codex_acp_backend.dart';
import 'ai_connection_test.dart';
import 'ai_connection_test_panel.dart';
import 'ai_connection_test_runner.dart';
import 'ai_model_picker.dart';
import 'ai_models.dart';
import 'ai_settings.dart';
import 'ai_strings.dart';
import 'ai_usage_page.dart';

Future<void> showAiSettings(
  BuildContext context,
  AiSettingsController settings, {
  ValueChanged<bool>? onSaved,
}) async {
  Widget buildSettings(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (_, _) => AiSettingsDialog(settings: settings),
  );
  final route = MediaQuery.disableAnimationsOf(context)
      ? PageRouteBuilder<bool>(
          pageBuilder: (context, animation, secondaryAnimation) =>
              buildSettings(context),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        )
      : MaterialPageRoute<bool>(builder: buildSettings);
  final result = await Navigator.of(context).push<bool>(route);
  if (!context.mounted || result == null) return;
  if (onSaved != null) {
    onSaved(result);
    return;
  }
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  AppNotifications.message(
    context,
    result
        ? (zh ? 'AI 连接已保存' : 'AI connection saved')
        : settings.usesGateway
        ? (zh ? '已恢复官方 AI 服务' : 'Backend AI service restored')
        : (zh ? 'AI 连接已移除' : 'AI connection removed'),
    kind: AppNoticeKind.success,
  );
}

class AiSettingsDialog extends StatefulWidget {
  const AiSettingsDialog({
    required this.settings,
    this.discoverAcp,
    this.connectionTestRunner,
    this.onDone,
    super.key,
  });
  final AiSettingsController settings;
  final AiConnectionTestRunner? connectionTestRunner;

  /// When provided, render inside the existing settings navigation.
  final ValueChanged<bool?>? onDone;
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
  final _endpointFocus = FocusNode();
  final _keyFocus = FocusNode();
  final _modelFocus = FocusNode();
  final GlobalKey _endpointField = GlobalKey();
  final GlobalKey _keyField = GlobalKey();
  final GlobalKey _modelField = GlobalKey();
  final _fieldErrors = <String, String>{};
  AiBackendKind _backend = AiBackendKind.llm;
  AiApprovalMode _approvalMode = AiApprovalMode.smart;
  AiApprovalSensitivity _approvalSensitivity = AiApprovalSensitivity.relaxed;
  String _officialModel = 'default';
  String? _apiModel;
  String? _acpModel;
  bool _working = false;
  bool get _busy => _working || _connection.running;
  late final AiConnectionTestController _connection;
  bool _customize = false;
  bool _loaded = false;
  bool _showKey = false;
  bool _detecting = false;
  bool _autoDetectionAttempted = false;
  bool _savedAcpUnsupported = false;
  int _detectionEpoch = 0;
  String? _discoveryNotice;
  String? _error;
  bool get zh => Localizations.localeOf(context).languageCode == 'zh';
  String t(String en, String cn) => zh ? cn : en;
  bool get _supportsLocalAcp => switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.android => false,
    _ => true,
  };

  @override
  void initState() {
    super.initState();
    _connection = AiConnectionTestController(
      runner: widget.connectionTestRunner ?? runAiConnectionTest,
    )..addListener(_connectionChanged);
    unawaited(_load());
  }

  void _connectionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    await widget.settings.loaded;
    if (!mounted) return;
    _officialModel = widget.settings.officialModel;
    final value = widget.settings.customConfiguration;
    if (value != null) {
      _fill(value);
    } else {
      _approvalMode = widget.settings.officialApprovalMode;
      _approvalSensitivity = widget.settings.officialApprovalSensitivity;
    }
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
    _connection.invalidate();
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
    _connection.invalidate();
    _error = null;
    _discoveryNotice = null;
    _fieldErrors.clear();
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
      _fieldErrors.clear();
      _model.text = _backend == AiBackendKind.acp
          ? (_acpModel ?? 'gpt-5.6-sol')
          : (_apiModel ?? '');
      _connection.invalidate();
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
      _connection.invalidate();
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

  bool _validateFields() {
    if (_backend != AiBackendKind.llm) return true;
    final endpoint = Uri.tryParse(_endpoint.text.trim());
    final errors = <String, String>{
      if (endpoint == null ||
          !{'http', 'https'}.contains(endpoint.scheme) ||
          endpoint.host.isEmpty ||
          endpoint.userInfo.isNotEmpty ||
          endpoint.hasQuery ||
          endpoint.hasFragment)
        'endpoint': t(
          'Enter a valid HTTP or HTTPS endpoint.',
          '请输入有效的 HTTP 或 HTTPS 地址。',
        ),
      if (_key.text.trim().isEmpty || _key.text.contains(RegExp(r'[\r\n]')))
        'key': t(
          'Enter an API key without line breaks.',
          '请输入 API Key，且不要包含换行。',
        ),
      if (_model.text.trim().isEmpty || _model.text.trim().length > 200)
        'model': t(
          'Enter a model name (up to 200 characters).',
          '请输入模型名称（不超过 200 个字符）。',
        ),
    };
    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(errors);
      _error = null;
    });
    if (errors.isEmpty) return true;
    final (focus, field) = switch (errors.keys.first) {
      'endpoint' => (_endpointFocus, _endpointField),
      'key' => (_keyFocus, _keyField),
      _ => (_modelFocus, _modelField),
    };
    focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final fieldContext = field.currentContext;
      if (fieldContext != null) {
        unawaited(Scrollable.ensureVisible(fieldContext, alignment: 0));
      }
    });
    return false;
  }

  Future<void> _save({bool remove = false}) async {
    if (!remove && !_validateFields()) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      if (!remove || widget.settings.customConfiguration != null) {
        await widget.settings.save(remove ? null : _value);
      }
      if (mounted) {
        if (remove) {
          setState(() {
            _customize = false;
            _officialModel = widget.settings.officialModel;
            _approvalMode = widget.settings.officialApprovalMode;
            _approvalSensitivity = widget.settings.officialApprovalSensitivity;
            _tested = false;
          });
        } else {
          _finish(true);
        }
      }
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
      if (mounted) setState(() => _working = false);
    }
  }

  void _checkConnection() {
    if (!_validateFields()) return;
    try {
      final configuration = _value;
      setState(() => _error = null);
      _connection.start(configuration);
    } on Object catch (failure) {
      setState(
        () => _error = failure is AiFailure ? failure.code : 'configuration',
      );
    }
  }

  @override
  void dispose() {
    _detectionEpoch++;
    _connection.removeListener(_connectionChanged);
    _connection.dispose();
    _endpointFocus.dispose();
    _keyFocus.dispose();
    _modelFocus.dispose();
    _endpoint.dispose();
    _key.dispose();
    _model.dispose();
    _agentCommand.dispose();
    _agentArguments.dispose();
    super.dispose();
  }

  Widget _approvalSection(BuildContext context) => AppSettingsSection(
    title: t('Command approval', '命令审批'),
    children: [
      AppConfigurationField(
        label: t('Mode', '模式'),
        child: AppDropdownFormField<AiApprovalMode>(
          key: const Key('ai-approval-mode'),
          initialValue: _approvalMode,
          isExpanded: true,
          decoration: const InputDecoration(),
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
                  if (value != null) {
                    setState(() => _approvalMode = value);
                  }
                },
        ),
      ),
      if (_approvalMode == AiApprovalMode.smart) ...[
        const SizedBox(height: 16),
        AppConfigurationField(
          label: t('Review sensitivity', '审核敏感性'),
          child: AppDropdownFormField<AiApprovalSensitivity>(
            key: const Key('ai-approval-sensitivity'),
            initialValue: _approvalSensitivity,
            isExpanded: true,
            decoration: const InputDecoration(),
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
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(
          t('Review rules', '审核规则'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        children: [
          Text(
            t(
              'Unclear risk or unavailable review always requires confirmation. Reviews use this connection and consume credits.',
              '风险不明或审核不可用时始终需要确认。审核使用当前连接并消耗额度。',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (_loaded && widget.settings.customConfiguration == null && !_customize) {
      return _surface(
        title: t('Official AI service', '官方 AI 服务'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSettingsSection(
              title: t('Model', '模型'),
              children: [
                if (widget.settings.gatewayConfiguration case final gateway?)
                  AiModelPicker(
                    configuration: gateway,
                    selected: _officialModel,
                    autoLoad: true,
                    enabled: !_busy,
                    onSelected: (value) =>
                        setState(() => _officialModel = value),
                  )
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text(t('Sign in to choose a model', '登录后选择模型')),
                  ),
                if (_error != null)
                  Text(
                    aiErrorText(_error!, zh),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            _approvalSection(context),
            if (widget.settings.usage case final usage?) ...[
              const SizedBox(height: 24),
              AiUsageSummary(
                controller: usage,
                onDetails: () => showAiUsage(context, usage),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            key: const Key('ai-custom-connection'),
            onPressed: _busy ? null : () => setState(() => _customize = true),
            child: Text(t('Custom connection', '自定义连接')),
          ),
          FilledButton(
            key: const Key('ai-save-official'),
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _working = true);
                    try {
                      await widget.settings.save(
                        AiConfiguration.official(
                          model: _officialModel,
                          approvalMode: _approvalMode,
                          approvalSensitivity: _approvalSensitivity,
                        ),
                      );
                      if (context.mounted) _finish(true);
                    } on Object {
                      if (mounted) {
                        setState(() => _error = 'configuration_save');
                      }
                    } finally {
                      if (mounted) setState(() => _working = false);
                    }
                  },
            child: Text(t('Save', '保存')),
          ),
        ],
      );
    }
    final content = SizedBox(
      width: 632,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSettingsSection(
            title: t('Connection', '连接'),
            children: [
              AppConfigurationField(
                label: t('Connection type', '连接方式'),
                child: AppDropdownFormField<AiBackendKind>(
                  isExpanded: true,
                  key: const Key('ai-backend'),
                  initialValue: _backend,
                  decoration: const InputDecoration(),
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
              if (_backend == AiBackendKind.acp) ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const Key('ai-detect-acp'),
                    onPressed: _loaded && !_busy && !_detecting
                        ? _detectAcp
                        : null,
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
                AppConfigurationField(
                  label: t('Executable path', '可执行文件路径'),
                  child: TextField(
                    key: const Key('ai-agent-command'),
                    controller: _agentCommand,
                    enabled: _loaded && !_busy,
                    autocorrect: false,
                    onChanged: _edited,
                    decoration: const InputDecoration(),
                  ),
                ),
                const SizedBox(height: 16),
                AppConfigurationField(
                  label: t('Arguments (JSON array)', '启动参数（JSON 数组）'),
                  child: TextField(
                    key: const Key('ai-agent-arguments'),
                    controller: _agentArguments,
                    enabled: _loaded && !_busy,
                    autocorrect: false,
                    onChanged: _edited,
                    decoration: const InputDecoration(),
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                AppConfigurationField(
                  key: _endpointField,
                  label: 'Endpoint',
                  stackedOnPhone: true,
                  child: TextField(
                    key: const Key('ai-endpoint'),
                    controller: _endpoint,
                    focusNode: _endpointFocus,
                    enabled: _loaded && !_busy,
                    autocorrect: false,
                    keyboardType: TextInputType.url,
                    onChanged: _edited,
                    decoration: InputDecoration(
                      errorText: _fieldErrors['endpoint'],
                      errorMaxLines: 3,
                      hintText: 'https://api.example.com/v1',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AppConfigurationField(
                  key: _keyField,
                  label: 'API Key',
                  child: TextField(
                    key: const Key('ai-api-key'),
                    controller: _key,
                    focusNode: _keyFocus,
                    enabled: _loaded && !_busy,
                    obscureText: !_showKey,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: _edited,
                    decoration: InputDecoration(
                      suffixIcon: IconButton(
                        tooltip: _showKey
                            ? t('Hide API key', '隐藏 API Key')
                            : t('Show API key', '显示 API Key'),
                        onPressed: () => setState(() => _showKey = !_showKey),
                        icon: Icon(
                          _showKey
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                      errorText: _fieldErrors['key'],
                      errorMaxLines: 3,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (_backend == AiBackendKind.llm)
                AiModelPicker(
                  configuration: AiConfiguration(
                    endpoint: _endpoint.text.trim(),
                    apiKey: _key.text.trim(),
                    model: 'catalog',
                  ),
                  selected: _model.text,
                  enabled: _loaded && !_busy,
                  onSelected: (value) {
                    _model.text = value;
                    _edited(value);
                  },
                ),
              AppConfigurationField(
                key: _modelField,
                label: t('Model', '模型'),
                child: TextField(
                  key: const Key('ai-model'),
                  controller: _model,
                  focusNode: _modelFocus,
                  enabled: _loaded && !_busy,
                  autocorrect: false,
                  onChanged: _edited,
                  decoration: InputDecoration(
                    errorText: _fieldErrors['model'],
                    errorMaxLines: 3,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
          const SizedBox(height: 24),
          _approvalSection(context),
          const SizedBox(height: 24),
          if (_backend == AiBackendKind.llm && !kReleaseMode)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('ai-use-mock'),
                onPressed: _loaded && !_busy
                    ? () => setState(() => _fill(const AiConfiguration.mock()))
                    : null,
                child: Text(t('Local mock', '本机 Mock')),
              ),
            ),
          AiConnectionTestPanel(
            controller: _connection,
            onTest: _loaded && !_busy && !_detecting ? _checkConnection : null,
            saved: !_connection.stale && _matchesSavedConfiguration,
          ),
          if (_working || !_loaded) const LinearProgressIndicator(),
          if (!_loaded) Text(t('Loading saved configuration…', '正在读取已保存的配置…')),
          if (_error != null)
            Text(
              aiErrorText(_error!, zh),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
    final actions = <Widget>[
      if (_customize || widget.settings.configuration != null)
        TextButton(
          key: const Key('ai-remove-settings'),
          onPressed: _busy || _detecting ? null : () => _save(remove: true),
          child: Text(t('Use official service', '使用官方服务')),
        ),
      TextButton(
        onPressed: _busy ? null : () => _finish(null),
        child: Text(t('Cancel', '取消')),
      ),
      FilledButton(
        key: const Key('ai-save-settings'),
        onPressed: _loaded && !_busy && !_detecting ? _save : null,
        child: Text(t('Save', '保存')),
      ),
    ];
    return _surface(
      title: t('AI connection', 'AI 连接'),
      content: content,
      actions: actions,
    );
  }

  bool get _matchesSavedConfiguration {
    try {
      return jsonEncode(widget.settings.configuration?.toJson()) ==
          jsonEncode(_value.toJson());
    } on Object {
      return false;
    }
  }

  void _finish(bool? result) {
    if (widget.onDone case final onDone?) {
      onDone(result);
    } else {
      Navigator.of(context).pop(result);
    }
  }

  Widget _surface({
    required String title,
    required Widget content,
    required List<Widget> actions,
  }) {
    final body = Column(
      key: const Key('ai-settings-dialog'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(20),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_customize &&
                        widget.settings.customConfiguration == null) ...[
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                    ],
                    content,
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 8,
            children: actions,
          ),
        ),
      ],
    );
    if (widget.onDone != null) return body;
    return Scaffold(
      backgroundColor: context.groupedBackground,
      appBar: AppBar(title: const Text('AI')),
      body: SafeArea(child: body),
    );
  }
}
