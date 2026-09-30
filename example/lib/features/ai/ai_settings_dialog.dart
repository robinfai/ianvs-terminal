import 'dart:async';

import 'package:flutter/material.dart';

import 'ai_api_client.dart';
import 'ai_models.dart';
import 'ai_settings.dart';
import 'ai_strings.dart';

Future<void> showAiSettings(
  BuildContext context,
  AiSettingsController settings,
) => showDialog<void>(
  context: context,
  builder: (_) => AiSettingsDialog(settings: settings),
);

class AiSettingsDialog extends StatefulWidget {
  const AiSettingsDialog({required this.settings, super.key});
  final AiSettingsController settings;
  @override
  State<AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<AiSettingsDialog> {
  final _endpoint = TextEditingController();
  final _key = TextEditingController();
  final _model = TextEditingController();
  bool _busy = false;
  bool _loaded = false;
  bool _tested = false;
  String? _error;
  AiCancellation? _test;
  bool get zh => Localizations.localeOf(context).languageCode == 'zh';
  String t(String en, String cn) => zh ? cn : en;

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
  }

  void _fill(AiConfiguration value) {
    _endpoint.text = value.endpoint;
    _key.text = value.apiKey;
    _model.text = value.model;
    _tested = false;
  }

  AiConfiguration get _value => AiConfiguration(
    endpoint: _endpoint.text.trim(),
    apiKey: _key.text.trim(),
    model: _model.text.trim(),
  );

  void _edited(String _) => setState(() {
    _tested = false;
    _error = null;
  });

  Future<void> _save({bool remove = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.settings.save(remove ? null : _value);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (failure) {
      if (mounted) {
        setState(
          () => _error = failure is AiFailure ? failure.code : 'storage',
        );
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
      await const AiApiClient().complete(_value, [
        {
          'role': 'user',
          'content':
              'Trail connection check. Reply with a brief greeting without tool calls.',
        },
      ], cancellation);
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
    _test?.cancel();
    _endpoint.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('ai-settings-dialog'),
    title: Text(t('AI connection', 'AI 连接')),
    scrollable: true,
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t(
              'Connect directly to an OpenAI-compatible endpoint. Your configuration is stored only in this device’s secure storage.',
              '直接连接 OpenAI 兼容端点。配置仅保存在本机安全存储中。',
            ),
          ),
          const SizedBox(height: 20),
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
          const SizedBox(height: 16),
          TextField(
            key: const Key('ai-model'),
            controller: _model,
            enabled: _loaded && !_busy,
            autocorrect: false,
            onChanged: _edited,
            decoration: InputDecoration(labelText: t('Model', '模型')),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton(
                key: const Key('ai-use-mock'),
                onPressed: _loaded && !_busy
                    ? () => setState(() => _fill(const AiConfiguration.mock()))
                    : null,
                child: Text(t('Local mock', '本机 Mock')),
              ),
              TextButton(
                key: const Key('ai-test-connection'),
                onPressed: _loaded && !_busy ? _checkConnection : null,
                child: Text(t('Test connection', '测试连接')),
              ),
            ],
          ),
          if (_busy || !_loaded) const LinearProgressIndicator(),
          if (!_loaded) Text(t('Waiting for secure storage…', '正在等待安全存储…')),
          if (_tested)
            Text(
              t('Connection succeeded.', '连接成功。'),
              key: const Key('ai-connection-ok'),
            ),
          if (_error != null)
            Text(
              aiErrorText(_error!, zh),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 8),
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
          onPressed: _busy ? null : () => _save(remove: true),
          child: Text(t('Disconnect', '断开配置')),
        ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: Text(t('Cancel', '取消')),
      ),
      FilledButton(
        key: const Key('ai-save-settings'),
        onPressed: _loaded && !_busy ? _save : null,
        child: Text(t('Save', '保存')),
      ),
    ],
  );
}
