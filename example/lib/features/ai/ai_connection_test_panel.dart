import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/foundation/app_theme_tokens.dart';
import 'ai_connection_test.dart';
import 'ai_models.dart';
import 'ai_strings.dart';

class AiConnectionTestPanel extends StatefulWidget {
  const AiConnectionTestPanel({
    required this.controller,
    required this.onTest,
    required this.saved,
    super.key,
  });
  final AiConnectionTestController controller;
  final VoidCallback? onTest;
  final bool saved;

  @override
  State<AiConnectionTestPanel> createState() => _AiConnectionTestPanelState();
}

class _AiConnectionTestPanelState extends State<AiConnectionTestPanel> {
  bool? _expanded;
  bool _copied = false;
  late AiConnectionTestStatus _lastStatus;
  AiConnectionTestController get test => widget.controller;
  bool get zh => Localizations.localeOf(context).languageCode == 'zh';
  String t(String en, String cn) => zh ? cn : en;

  @override
  void initState() {
    super.initState();
    _lastStatus = test.status;
    test.addListener(_changed);
  }

  void _changed() {
    setState(() {
      if (_lastStatus != test.status) {
        _expanded = null;
        _copied = false;
        _lastStatus = test.status;
      }
    });
  }

  @override
  void dispose() {
    test.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTheme;
    final failed = {
      AiConnectionTestStatus.failed,
      AiConnectionTestStatus.timedOut,
    }.contains(test.status);
    final expanded = test.running || (_expanded ?? failed);
    final success = test.status == AiConnectionTestStatus.success;
    final color = test.stale
        ? tokens.textMuted
        : success
        ? tokens.success
        : test.status == AiConnectionTestStatus.timedOut
        ? tokens.warning
        : failed
        ? tokens.danger
        : tokens.textMuted;
    final title = test.stale
        ? t('Configuration changed. Test again.', '配置已更改，请重新测试。')
        : switch (test.status) {
            AiConnectionTestStatus.idle => '',
            AiConnectionTestStatus.running => t('Testing connection', '正在测试连接'),
            AiConnectionTestStatus.success => t('Connection succeeded', '连接成功'),
            AiConnectionTestStatus.failed => t('Connection failed', '连接失败'),
            AiConnectionTestStatus.timedOut => t('Test timed out', '测试超时'),
            AiConnectionTestStatus.cancelled => t('Test cancelled', '已取消测试'),
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                t('Connection test', '连接测试'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (test.running)
              OutlinedButton(
                key: const Key('ai-cancel-test'),
                onPressed: test.cancel,
                child: Text(t('Cancel test', '取消测试')),
              )
            else
              TextButton(
                key: const Key('ai-test-connection'),
                onPressed: widget.onTest,
                child: Text(
                  test.hasResult
                      ? t('Test again', '重新测试')
                      : t('Test connection', '测试连接'),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (!test.hasResult)
          Text(
            t(
              'Sends a short model request. Stops after 60 seconds.',
              '发送一条简短模型请求，最多等待 60 秒。',
            ),
            style: TextStyle(color: tokens.textMuted),
          )
        else ...[
          if (!test.running) ...[
            Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    test.stale
                        ? Icons.info_outline
                        : success
                        ? Icons.check_circle
                        : failed
                        ? Icons.error_outline
                        : Icons.stop_circle_outlined,
                    size: 22,
                    color: color,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          key: success && !test.stale
                              ? const Key('ai-connection-ok')
                              : const Key('ai-test-result'),
                          style: Theme.of(
                            context,
                          ).textTheme.titleSmall?.copyWith(color: color),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${test.backend == AiBackendKind.acp ? 'Codex ACP' : 'Model API'} · ${test.model}',
                          style: TextStyle(color: tokens.textMuted),
                        ),
                        if (!test.stale && failed) ...[
                          const SizedBox(height: 6),
                          Text(
                            test.status == AiConnectionTestStatus.timedOut
                                ? t(
                                    'No response in time. Check your network or sign-in, then retry.',
                                    '未在时限内完成。请检查网络或登录状态后重试。',
                                  )
                                : aiErrorText(test.error ?? 'connection', zh),
                          ),
                        ],
                        if (!test.stale && success)
                          Text(
                            widget.saved
                                ? t(
                                    'Model response received. Configuration saved.',
                                    '已收到模型回复，配置已保存。',
                                  )
                                : t(
                                    'Model response received. Not saved yet.',
                                    '已收到模型回复，当前配置尚未保存。',
                                  ),
                            style: TextStyle(color: tokens.textMuted),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          '${t('Total', '总耗时')} ${_seconds(test.elapsed)}',
                          style: TextStyle(color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('ai-test-details'),
                onPressed: () => setState(() => _expanded = !expanded),
                icon: Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                ),
                label: Text(
                  test.stale
                      ? t('Previous test details', '上次测试过程')
                      : t('Test details', '测试过程'),
                ),
              ),
            ),
          ],
          if (expanded) ...[
            for (final stage in test.stages) _stageRow(stage, color),
            if (test.running)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${t('Elapsed', '已用时')} ${test.elapsed.inSeconds} ${t('s', '秒')} · ${t('Limit', '总时限')} ${test.limit.inSeconds} ${t('s', '秒')}',
                  key: const Key('ai-test-elapsed'),
                  style: TextStyle(color: tokens.textMuted),
                ),
              ),
          ],
          if (!test.running) ...[
            const SizedBox(height: 8),
            const Divider(),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  key: const Key('ai-copy-test-diagnostics'),
                  onPressed: () async {
                    try {
                      await Clipboard.setData(
                        ClipboardData(text: test.diagnostics()),
                      );
                      if (mounted) setState(() => _copied = true);
                    } on Object {
                      /* Keep the report visible if clipboard is unavailable. */
                    }
                  },
                  icon: Icon(
                    _copied ? Icons.check : Icons.copy_outlined,
                    size: 16,
                  ),
                  label: Text(
                    _copied
                        ? t('Copied', '已复制')
                        : t('Copy diagnostics', '复制诊断信息'),
                  ),
                ),
                if (!widget.saved)
                  Text(
                    t('Configuration not saved', '配置尚未保存'),
                    style: TextStyle(color: tokens.textMuted),
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  String _seconds(Duration value) =>
      '${(value.inMilliseconds / 1000).toStringAsFixed(1)} ${t('s', '秒')}';

  Widget _stageRow(AiConnectionStage stage, Color resultColor) {
    final tokens = context.appTheme;
    final done = test.completed.containsKey(stage);
    final active = test.stage == stage;
    final color = test.stale
        ? tokens.textMuted
        : done
        ? tokens.success
        : active && test.running
        ? tokens.accent
        : active
        ? resultColor
        : tokens.textSubtle;
    final status = done
        ? _seconds(test.completed[stage]!)
        : active
        ? test.running
              ? t('In progress', '进行中')
              : test.status == AiConnectionTestStatus.cancelled
              ? t('Cancelled', '已取消')
              : test.status == AiConnectionTestStatus.timedOut
              ? t('Timed out', '已超时')
              : t('Failed', '失败')
        : t('Not run', '未执行');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: active && test.running
                ? CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                    semanticsLabel: connectionStageLabel(stage, zh),
                  )
                : Icon(
                    done
                        ? Icons.check_circle
                        : active
                        ? Icons.error_outline
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: color,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(connectionStageLabel(stage, zh))),
          const SizedBox(width: 12),
          Text(
            status,
            style: TextStyle(color: done ? tokens.textMuted : color),
          ),
        ],
      ),
    );
  }
}

String connectionStageLabel(AiConnectionStage stage, bool zh) {
  final labels = switch (stage) {
    AiConnectionStage.launch => ('Start agent', '启动代理'),
    AiConnectionStage.handshake => ('Verify protocol', '检查协议'),
    AiConnectionStage.session => ('Create session', '创建会话'),
    AiConnectionStage.model => ('Set model', '设置模型'),
    AiConnectionStage.reply => ('Wait for model response', '等待模型回复'),
    AiConnectionStage.request => ('Request model response', '请求模型回复'),
  };
  return zh ? labels.$2 : labels.$1;
}
