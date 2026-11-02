import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/app_ui.dart';
import 'ai_purchases.dart';
import 'ai_usage.dart';

class AiPurchaseButton extends StatelessWidget {
  const AiPurchaseButton({super.key});
  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return const SizedBox.shrink();
    }
    return Consumer(
      builder: (context, ref, _) {
        final controller = ref.watch(aiPurchaseProvider);
        if (controller == null) return const SizedBox.shrink();
        final zh = Localizations.localeOf(context).languageCode == 'zh';
        return FilledButton.tonalIcon(
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => AiPurchasePage(controller: controller),
            ),
          ),
          icon: const Icon(Icons.add_circle_outline),
          label: Text(zh ? '购买额度' : 'Buy credits'),
        );
      },
    );
  }
}

class AiPurchasePage extends StatefulWidget {
  const AiPurchasePage({required this.controller, super.key});
  final AiPurchaseController controller;
  @override
  State<AiPurchasePage> createState() => _AiPurchasePageState();
}

class _AiPurchasePageState extends State<AiPurchasePage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.refresh());
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
              title: t('Buy AI credits', '购买 AI 额度'),
              leading: const BackButton(),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListenableBuilder(
                    listenable: widget.controller,
                    builder: (context, _) {
                      final c = widget.controller;
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text(
                            t(
                              'One-time purchase · no subscription · credits do not expire',
                              '一次性购买 · 无自动续费 · 额度长期有效',
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          if (c.loading) const LinearProgressIndicator(),
                          if (!c.loading && !c.enabled)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                t(
                                  'Credit purchases are not available yet. Please try again later.',
                                  '额度购买暂未开放，请稍后重试。',
                                ),
                              ),
                            ),
                          if (!c.loading && c.enabled && c.products.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                t(
                                  'No credit packs are available from the App Store right now.',
                                  'App Store 暂无可用额度包，请稍后重试。',
                                ),
                              ),
                            ),
                          for (final product in c.products)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      product.title,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      t(
                                        '${product.points} points',
                                        '${product.points} 点',
                                      ),
                                      style: theme.textTheme.headlineSmall,
                                    ),
                                    const SizedBox(height: 16),
                                    FilledButton(
                                      onPressed:
                                          c.buying || c.loading || c.recovering
                                          ? null
                                          : () => unawaited(c.buy(product)),
                                      child: Text(
                                        t(
                                          'Buy · ${product.price}',
                                          '购买 · ${product.price}',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (c.buying || c.recovering)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      t(
                                        'Confirming purchase and delivery…',
                                        '正在确认购买与到账…',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (c.message != null)
                            Semantics(
                              liveRegion: true,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Text(purchaseMessage(c.message!, zh)),
                              ),
                            ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: c.loading || c.buying
                                    ? null
                                    : () => unawaited(c.refresh()),
                                icon: const Icon(Icons.refresh),
                                label: Text(t('Refresh', '刷新')),
                              ),
                              TextButton(
                                onPressed:
                                    c.recovering || c.buying || !c.enabled
                                    ? null
                                    : () => unawaited(c.refresh()),
                                child: Text(
                                  t('Check pending purchases', '检查未到账购买'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            t('Purchase history', '购买记录'),
                            style: theme.textTheme.titleMedium,
                          ),
                          if (c.history.isEmpty && !c.loading)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(t('No purchases yet.', '暂无购买记录。')),
                            ),
                          for (final record in c.history)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${aiQuotaPoints(record['credit_nano_usd']! as int)} ${t('points', '点')}',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    Text(
                                      record['status'] == 'credited'
                                          ? t('Credited', '已到账')
                                          : t(
                                              'Refunded · credits withdrawn',
                                              '已退款 · 额度已撤回',
                                            ),
                                    ),
                                    Text(
                                      MaterialLocalizations.of(
                                        context,
                                      ).formatFullDate(
                                        DateTime.parse(
                                          record['created_at']! as String,
                                        ).toLocal(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String purchaseMessage(String code, bool zh) {
  final values = switch (code) {
    'purchase_success' => ('Credits added to your account.', '额度已到账。'),
    'purchase_cancelled' => (
      'Purchase cancelled. No credits were added.',
      '已取消购买，未增加额度。',
    ),
    'purchase_pending' => (
      'Waiting for App Store approval. Credits will be added after confirmation.',
      '等待 App Store 批准，确认后自动到账。',
    ),
    'purchase_account_mismatch' => (
      'Sign in to the Trail account used for this purchase to receive the credits.',
      '请登录购买时使用的 Trail 账号领取额度。',
    ),
    'purchase_revoked' => (
      'This purchase was refunded and its credits withdrawn.',
      '此购买已退款，对应额度已撤回。',
    ),
    'purchase_unavailable' => (
      'Cannot connect to the store or credit service. Please retry.',
      '暂时无法连接商店或额度服务，请重试。',
    ),
    _ => (
      'Delivery has not been confirmed. Check pending purchases to retry without buying again.',
      '尚未确认到账，请点击“检查未到账购买”重试，无需重复购买。',
    ),
  };
  return zh ? values.$2 : values.$1;
}
