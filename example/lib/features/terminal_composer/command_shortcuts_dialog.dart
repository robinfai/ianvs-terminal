import 'package:flutter/material.dart';

import '../../ui/app_ui.dart';

/// A reference for the existing command editor, not another shortcut owner.
class CommandShortcutsDialog extends StatelessWidget {
  const CommandShortcutsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    String label(String en, String cn) => zh ? cn : en;
    final mac = Theme.of(context).platform == TargetPlatform.macOS;
    final command = mac ? '⌘' : 'Ctrl';
    final option = mac ? 'Option' : 'Alt';
    final viewport = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final height = (viewport.height - padding.vertical - 48).clamp(0.0, 760.0);
    return AppDialogScaffold(
      key: const Key('command-shortcuts-dialog'),
      title: label('Command shortcuts', '命令快捷键'),
      width: 680,
      height: height,
      constraints: const BoxConstraints(maxWidth: 680),
      insetPadding: const EdgeInsets.all(24),
      expandBody: true,
      bodyPadding: EdgeInsets.zero,
      onClose: () => Navigator.of(context).pop(),
      body: SingleChildScrollView(
        key: const Key('command-shortcuts-scroll'),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ShortcutGroup(
              title: label('Completion & history', '补全与历史'),
              children: [
                _ShortcutRow(label('Complete / accept', '补全 / 采用'), const [
                  ['Tab'],
                ]),
                _ShortcutRow(label('Select candidate', '选择候选'), const [
                  ['↑'],
                  ['↓'],
                ]),
                _ShortcutRow(
                  label('Command history', '命令历史'),
                  const [
                    ['Ctrl', 'R'],
                    ['↑'],
                  ],
                  note: label('↑ on the first line', '↑ 仅在首行生效'),
                ),
                _ShortcutRow(label('Accept suggestion', '接受灰字建议'), const [
                  ['→'],
                  ['Ctrl', 'F'],
                  ['Ctrl', 'E'],
                ]),
                _ShortcutRow(label('Accept next segment', '接受下一段'), const [
                  ['Ctrl', '→'],
                ]),
              ],
            ),
            const Divider(height: 32),
            _ShortcutGroup(
              title: label('Edit & run', '编辑与执行'),
              children: [
                _ShortcutRow(label('Accept, then run', '先采用候选，再执行'), const [
                  ['Enter'],
                ]),
                _ShortcutRow(label('New line', '换行'), [
                  const ['Shift', 'Enter'],
                  const ['Ctrl', 'Enter'],
                  [option, 'Enter'],
                ]),
                _ShortcutRow(label('Undo', '撤销'), [
                  [command, 'Z'],
                ]),
                _ShortcutRow(label('Redo', '重做'), [
                  ['Shift', command, 'Z'],
                ]),
                _ShortcutRow(
                  label('Clear draft', '清空草稿'),
                  const [
                    ['Ctrl', 'C'],
                  ],
                  note: label(
                    'With no selection; does not interrupt the terminal',
                    '无选区时生效，不会中断终端',
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            _ShortcutGroup(
              title: label('Navigation', '导航'),
              children: [
                _ShortcutRow(
                  label('Close candidates / return to terminal', '关闭候选 / 返回终端'),
                  const [
                    ['Esc'],
                  ],
                ),
                _ShortcutRow(label('Previous control', '上一个控件'), const [
                  ['Shift', 'Tab'],
                ]),
              ],
            ),
          ],
        ),
      ),
      footer: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FilledButton(
          key: const Key('command-shortcuts-done'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(label('Done', '完成')),
        ),
      ),
    );
  }
}

class _ShortcutGroup extends StatelessWidget {
  const _ShortcutGroup({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: context.appTheme.textMuted),
        ),
      ),
      ...children,
    ],
  );
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow(this.label, this.alternatives, {this.note});
  final String label;
  final List<List<String>> alternatives;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.appTheme;
    final keys = Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var index = 0; index < alternatives.length; index++) ...[
          if (index > 0)
            Text(
              '/',
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.textSubtle,
              ),
            ),
          Semantics(
            label: alternatives[index]
                .map((key) => key == '⌘' ? 'Command' : key)
                .join(' + '),
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var key = 0; key < alternatives[index].length; key++) ...[
                  if (key > 0) const SizedBox(width: 4),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.chrome,
                      border: Border.all(color: tokens.border),
                      borderRadius: BorderRadius.circular(tokens.radius.sm),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        alternatives[index][key],
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
    final description = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(
            note!,
            style: theme.textTheme.bodySmall?.copyWith(color: tokens.textMuted),
          ),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final stacked =
              bounds.maxWidth < 460 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          return stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [description, const SizedBox(height: 8), keys],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: description),
                    const SizedBox(width: 20),
                    SizedBox(width: bounds.maxWidth * .56, child: keys),
                  ],
                );
        },
      ),
    );
  }
}
