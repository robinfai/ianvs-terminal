import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/app_ui.dart';
import 'ai_purchase_page.dart';
import 'ai_strings.dart';
import 'ai_usage.dart';

Future<void> showAiUsage(BuildContext context, AiUsageController controller) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => AiUsagePage(controller: controller)),
    );

class AiUsageSummary extends StatefulWidget {
  const AiUsageSummary({required this.controller, this.onDetails, super.key});
  final AiUsageController controller;
  final VoidCallback? onDetails;
  @override
  State<AiUsageSummary> createState() => _AiUsageSummaryState();
}

class _AiUsageSummaryState extends State<AiUsageSummary> {
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() {
      if (mounted) unawaited(widget.controller.refresh());
    });
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String t(String en, String cn) => zh ? cn : en;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller;
        final usage = state.snapshot;
        return AppGroupedSection(
          padding: const EdgeInsets.all(16),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t('AI credits', 'AI 可用额度'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (usage != null) ...[
                  Text(
                    t(
                      '${aiQuotaPoints(usage.remaining)} points remaining',
                      '剩余 ${aiQuotaPoints(usage.remaining)} 点',
                    ),
                    key: const Key('ai-quota-remaining'),
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  if (widget.onDetails == null)
                    LinearProgressIndicator(
                      value: usage.budget == 0
                          ? 0
                          : (usage.dailyRemaining / usage.budget).clamp(
                              0.0,
                              1.0,
                            ),
                      semanticsLabel: t('Remaining quota', '剩余额度'),
                    ),
                  const SizedBox(height: 12),
                  _UsageMetric(
                    label: t('Daily remaining', '今日剩余'),
                    value:
                        '${aiQuotaPoints(usage.dailyRemaining)} / ${aiQuotaPoints(usage.budget)}',
                  ),
                  _UsageMetric(
                    label: t('Purchased balance', '购买余额'),
                    value: aiQuotaPoints(usage.purchasedRemaining),
                  ),
                  if (usage.reserved > 0 || usage.pending > 0)
                    Text(
                      t(
                        'Reserved ${aiQuotaPoints(usage.reserved)} points · ${usage.pending} pending requests',
                        '预占 ${aiQuotaPoints(usage.reserved)} 点 · ${usage.pending} 次请求待结算',
                      ),
                    ),
                  if (usage.remaining == 0)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        t(
                          'No credits available. Buy credits or wait for the daily reset.',
                          '当前可用额度不足，可购买额度或等待每日额度重置。',
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (widget.onDetails == null)
                    Text(
                      t(
                        'Resets ${_localTime(context, usage.resetAt)}',
                        '重置时间 ${_localTime(context, usage.resetAt)}',
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                ] else if (state.loading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${usage == null ? '' : t('Showing previously fetched usage. ', '当前显示上次获取的数据。')}${aiErrorText(state.error!, zh)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    const AiPurchaseButton(),
                    if (widget.onDetails != null)
                      TextButton.icon(
                        onPressed: state.loading
                            ? null
                            : () => unawaited(state.refresh()),
                        icon: const Icon(Icons.refresh),
                        label: Text(t('Refresh quota', '刷新额度')),
                      ),
                    if (widget.onDetails != null)
                      TextButton(
                        onPressed: widget.onDetails,
                        child: Text(t('Usage details', '用量明细')),
                      ),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

String _localTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final l = MaterialLocalizations.of(context);
  return '${l.formatCompactDate(local)} ${l.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: true)}';
}

class AiUsagePage extends StatefulWidget {
  const AiUsagePage({required this.controller, super.key});
  final AiUsageController controller;
  @override
  State<AiUsagePage> createState() => _AiUsagePageState();
}

class _AiUsagePageState extends State<AiUsagePage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.controller.loadRecords());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    await Future.wait([
      widget.controller.refresh(),
      widget.controller.loadRecords(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String t(String en, String cn) => zh ? cn : en;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: context.groupedBackground,
      body: SafeArea(
        child: Column(
          children: [
            AppMobileHeader(
              title: t('AI quota and usage', 'AI 额度与用量'),
              leading: const BackButton(),
              actions: [
                IconButton(
                  onPressed: _refresh,
                  tooltip: t('Refresh', '刷新'),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListenableBuilder(
                      listenable: widget.controller,
                      builder: (context, _) {
                        final state = widget.controller;
                        return ListView(
                          padding: const EdgeInsets.all(16),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            AiUsageSummary(controller: state),
                            const SizedBox(height: 32),
                            Text(
                              t('Request history', '请求明细'),
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            if (state.snapshot case final usage?)
                              Text(
                                t(
                                  'Today: input ${usage.input} (cached ${usage.cached}) · output ${usage.output}',
                                  '今日输入 ${usage.input}（其中缓存 ${usage.cached}）· 输出 ${usage.output} token',
                                ),
                              ),
                            if (state.recordsError != null) ...[
                              Text(
                                aiErrorText(state.recordsError!, zh),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                              TextButton(
                                onPressed: state.loadRecords,
                                child: Text(t('Retry details', '重试明细')),
                              ),
                            ],
                            if (!state.loadingRecords &&
                                state.recordsError == null &&
                                state.records.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  t('No request records yet.', '暂无请求记录。'),
                                ),
                              ),
                            if (state.records.isNotEmpty)
                              AppGroupedSection(
                                flat: true,
                                separated: true,
                                children: [
                                  for (final record in state.records)
                                    _record(context, record, zh),
                                ],
                              ),
                            if (state.loadingRecords)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (state.nextCursor.isNotEmpty)
                              TextButton(
                                onPressed: () => state.loadRecords(more: true),
                                child: Text(t('Load more', '加载更多')),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _record(BuildContext context, AiUsageRecord record, bool zh) {
    String t(String en, String cn) => zh ? cn : en;
    final pending = record.status == 'pending';
    final status = switch (record.status) {
      'settled' => t('Settled', '已结算'),
      'refunded' => t('Refunded', '已退回'),
      'pending' => t('Pending settlement', '待结算'),
      _ => t('Unknown status', '状态未知'),
    };
    return ExpansionTile(
      key: ValueKey(record.id),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Text(record.model, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(
        '${_localTime(context, record.createdAt)} · $status',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${aiQuotaPoints(pending ? record.reserved : record.spent)} ${t('pts', '点')}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(width: 8),
          const Icon(Icons.expand_more, size: 18),
        ],
      ),
      children: [
        _UsageMetric(label: t('Provider', '服务商'), value: record.provider),
        _UsageMetric(
          label: t('Input / output', '输入 / 输出'),
          value: '${record.input} / ${record.output} token',
        ),
        _UsageMetric(label: t('Cached', '缓存'), value: '${record.cached} token'),
        if (pending) Text(t('Final usage is not confirmed.', '最终用量尚未确认。')),
        if (record.priceVersion.isNotEmpty)
          _UsageMetric(
            label: t('Price version', '费率版本'),
            value: record.priceVersion,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            '${t('Request ID', '请求编号')}\n${record.id}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _UsageMetric extends StatelessWidget {
  const _UsageMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(value, textAlign: TextAlign.end),
          ),
        ),
      ],
    ),
  );
}
