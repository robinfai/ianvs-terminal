import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons_300.dart';

import '../../ui/app_ui.dart';
import 'ai_model_catalog.dart';
import 'ai_models.dart';
import 'ai_settings.dart';
import 'ai_strings.dart';

/// One list presentation for API and ACP catalogs. It never submits a prompt.
class AiComposerModelMenu extends StatelessWidget {
  const AiComposerModelMenu({
    required this.settings,
    required this.enabled,
    required this.onConfigure,
    required this.onSelect,
    required this.canSelect,
    this.catalog = const AiModelCatalog(),
    super.key,
  });
  final AiSettingsController settings;
  final bool enabled;
  final VoidCallback onConfigure;
  final Future<bool> Function(String, AiConfiguration) onSelect;
  final bool Function() canSelect;
  final AiModelCatalog catalog;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) {
      final zh = Localizations.localeOf(context).languageCode == 'zh';
      final config = settings.configuration;
      final label = config == null
          ? (zh ? '选择模型' : 'Choose model')
          : config.model == 'default'
          ? (zh ? '默认模型' : 'Default model')
          : config.model;
      return TextButton(
        key: const Key('ai-composer-model'),
        style: TextButton.styleFrom(
          foregroundColor: context.appTheme.textMuted,
          textStyle: Theme.of(context).textTheme.bodyMedium,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: !enabled || settings.loading
            ? null
            : () async {
                if (config == null) {
                  onConfigure();
                  return;
                }
                final box = context.findRenderObject()! as RenderBox;
                final anchor = box.localToGlobal(Offset.zero);
                await showDialog<void>(
                  context: context,
                  barrierColor: Colors.transparent,
                  animationStyle: appDialogAnimation(context),
                  builder: (context) {
                    final size = MediaQuery.sizeOf(context);
                    final width = math.min(240.0, size.width - 32);
                    final bottom = math.max(16.0, size.height - anchor.dy + 8);
                    final height = math.min(360.0, size.height - bottom - 16);
                    final left = anchor.dx.clamp(
                      16.0,
                      math.max(16.0, size.width - width - 16),
                    );
                    return Dialog(
                      elevation: 8,
                      constraints: BoxConstraints(minWidth: 0, maxWidth: width),
                      alignment: Alignment.bottomLeft,
                      insetPadding: EdgeInsets.fromLTRB(
                        left.toDouble(),
                        16,
                        16,
                        bottom,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: context.appTheme.border),
                      ),
                      child: Container(
                        width: width,
                        constraints: BoxConstraints(maxHeight: height),
                        child: _ModelChoices(
                          config: config,
                          catalog: catalog,
                          settings: settings,
                          canSelect: canSelect,
                          onSelect: onSelect,
                        ),
                      ),
                    );
                  },
                );
              },
        child: Tooltip(
          message: '${zh ? '选择模型' : 'Choose model'} · $label',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(LucideIcons300.chevronDown, size: 16),
            ],
          ),
        ),
      );
    },
  );
}

class _ModelChoices extends StatefulWidget {
  const _ModelChoices({
    required this.settings,
    required this.config,
    required this.catalog,
    required this.canSelect,
    required this.onSelect,
  });
  final AiSettingsController settings;
  final AiConfiguration config;
  final AiModelCatalog catalog;
  final bool Function() canSelect;
  final Future<bool> Function(String, AiConfiguration) onSelect;
  @override
  State<_ModelChoices> createState() => _ModelChoicesState();
}

class _ModelChoicesState extends State<_ModelChoices> {
  final _search = TextEditingController();
  List<AiModelOption> _models = [];
  bool _loading = false;
  bool _saving = false;
  bool _empty = false;
  String? _error;
  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  bool get _stale =>
      !widget.config.hasSameValues(widget.settings.configuration);

  @override
  void initState() {
    super.initState();
    _models = [AiModelOption(widget.config.model)];
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final options = await widget.catalog.choices(widget.config);
      if (mounted) {
        setState(() {
          _empty = options.isEmpty;
          final unique = <String, AiModelOption>{
            for (final model in options) model.id: model,
          };
          unique.putIfAbsent(
            widget.config.model,
            () => AiModelOption(widget.config.model),
          );
          _models = unique.values.toList();
        });
      }
    } on AiFailure catch (e) {
      if (mounted) setState(() => _error = e.code);
    } on Object {
      if (mounted) setState(() => _error = 'models_unavailable');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(String id) async {
    if (_saving) return;
    if (_stale || !widget.canSelect()) {
      setState(() => _error = 'configuration_changed');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.onSelect(id, widget.config);
      if (!mounted) return;
      if (saved) {
        Navigator.pop(context);
        return;
      }
      setState(() => _error = 'configuration_changed');
    } on AiFailure catch (e) {
      if (mounted) setState(() => _error = e.code);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final search = _models.length > 10;
    final query = search ? _search.text.trim().toLowerCase() : '';
    final models = _models
        .where(
          (m) =>
              m.id.toLowerCase().contains(query) ||
              m.name.toLowerCase().contains(query),
        )
        .toList();
    final source = widget.config.backend == AiBackendKind.acp
        ? 'ACP · Codex'
        : widget.settings.usesGateway
        ? (_zh ? 'LLM API · 官方服务' : 'LLM API · Official service')
        : 'LLM API · ${Uri.tryParse(widget.config.endpoint)?.host ?? ''}';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _zh ? '选择模型' : 'Choose model',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (search) ...[
            const SizedBox(height: 10),
            TextField(
              key: const Key('ai-model-search'),
              controller: _search,
              enabled: !_saving,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _zh ? '搜索模型' : 'Search models',
                prefixIcon: const Icon(LucideIcons300.search, size: 18),
                isDense: true,
              ),
            ),
          ],
          const Divider(),
          Text(
            source,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.appTheme.textMuted),
          ),
          const SizedBox(height: 4),
          if (_loading || _saving) const LinearProgressIndicator(),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final model in models)
                  ListTile(
                    key: ValueKey('ai-model-choice-${model.id}'),
                    dense: true,
                    minTileHeight: 32,
                    visualDensity: VisualDensity.compact,
                    selected: model.id == widget.config.model,
                    selectedTileColor: context.appTheme.focus.withValues(
                      alpha: .1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    title: Text(
                      model.id == 'default'
                          ? (_zh ? '默认模型' : 'Default model')
                          : model.name,
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: model.id == widget.config.model
                        ? Icon(
                            LucideIcons300.check,
                            size: 16,
                            color: context.appTheme.focus,
                          )
                        : null,
                    onTap: _saving ? null : () => _select(model.id),
                  ),
                if (models.isEmpty || _empty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(_zh ? '没有其他可用模型' : 'No other available models'),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      aiErrorText(_error!, _zh),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!_loading)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('ai-model-refresh'),
                onPressed: _saving || _stale ? null : _load,
                icon: const Icon(LucideIcons300.refreshCw, size: 16),
                label: Text(_zh ? '刷新列表' : 'Refresh models'),
              ),
            ),
        ],
      ),
    );
  }
}
