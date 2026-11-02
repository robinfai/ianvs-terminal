import 'dart:async';
import 'package:flutter/material.dart';
import '../../ui/components/app_dropdown_form_field.dart';
import 'ai_model_catalog.dart';
import 'ai_models.dart';
import 'ai_strings.dart';

class AiModelPicker extends StatefulWidget {
  const AiModelPicker({
    required this.configuration,
    required this.selected,
    required this.onSelected,
    this.catalog = const AiModelCatalog(),
    this.autoLoad = false,
    this.enabled = true,
    super.key,
  });
  final AiModelCatalog catalog;
  final AiConfiguration configuration;
  final String selected;
  final ValueChanged<String> onSelected;
  final bool autoLoad;
  final bool enabled;
  @override
  State<AiModelPicker> createState() => _AiModelPickerState();
}

class _AiModelPickerState extends State<AiModelPicker> {
  List<String>? _models;
  String? _error;
  bool _loading = false;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) unawaited(_load());
  }

  @override
  void didUpdateWidget(AiModelPicker old) {
    super.didUpdateWidget(old);
    if (old.configuration.endpoint != widget.configuration.endpoint ||
        old.configuration.apiKey != widget.configuration.apiKey) {
      _epoch++;
      _models = null;
      _error = null;
      _loading = false;
      if (widget.autoLoad) unawaited(_load());
    }
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final models = await widget.catalog.fetch(widget.configuration);
      if (mounted && epoch == _epoch) setState(() => _models = models);
    } on AiFailure catch (e) {
      if (mounted && epoch == _epoch) setState(() => _error = e.code);
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final models = _models;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (models != null && models.isNotEmpty)
          AppDropdownFormField<String>(
            key: ValueKey('ai-catalog-${models.join('|')}-${widget.selected}'),
            initialValue: models.contains(widget.selected)
                ? widget.selected
                : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: zh ? '选择模型' : 'Choose model',
            ),
            items: [
              for (final id in models)
                DropdownMenuItem(
                  value: id,
                  child: Text(id, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: !widget.enabled || _loading
                ? null
                : (value) {
                    if (value != null) widget.onSelected(value);
                  },
          ),
        if (models != null && models.isEmpty)
          Text(
            zh
                ? '服务没有返回可用模型，请检查账号权限。'
                : 'No models available. Check account permissions.',
          ),
        if (_error != null)
          Text(
            aiErrorText(_error!, zh),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_loading) const LinearProgressIndicator(),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('ai-load-models'),
            onPressed: !widget.enabled || _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            label: Text(
              _loading
                  ? (zh ? '正在加载模型…' : 'Loading models…')
                  : (zh ? '获取模型列表' : 'Load models'),
            ),
          ),
        ),
      ],
    );
  }
}
