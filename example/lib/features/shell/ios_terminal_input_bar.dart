import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../ui/foundation/app_theme_tokens.dart';

part 'ios_terminal_input_keys.dart';

/// Touch shortcuts stay outside the terminal focus chain so the IME stays open.
class IosTerminalInputBar extends StatefulWidget {
  const IosTerminalInputBar({
    super.key,
    required this.palette,
    required this.keyboardVisible,
    required this.onSendBytes,
    required this.onDismissKeyboard,
  });

  final AppThemeTokens palette;
  final bool keyboardVisible;
  final ValueChanged<List<int>> onSendBytes;
  final VoidCallback onDismissKeyboard;

  @override
  State<IosTerminalInputBar> createState() => _IosTerminalInputBarState();
}

class _IosTerminalInputBarState extends State<IosTerminalInputBar> {
  bool _expanded = false;
  _KeyGroup _group = _KeyGroup.editing;

  // Retain the accessory's 44pt targets, 4pt gaps, 8pt radius and theme tokens.
  // Both target height and label width grow with Dynamic Type.
  static const _gap = 4.0;
  static const _minimumTarget = 44.0;

  TextStyle get _keyStyle => Theme.of(context).textTheme.labelLarge!.copyWith(
    color: widget.palette.textPrimary,
    fontWeight: FontWeight.w600,
  );

  Size _measure(String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: _keyStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final size = painter.size;
    painter.dispose();
    return size;
  }

  double _keyWidth(_KeySpec key) =>
      math.max(_minimumTarget, _measure(key.label).width.ceilToDouble() + 16);

  double get _height =>
      math.max(_minimumTarget, _measure('⌃W').height.ceilToDouble() + 16);

  @override
  Widget build(BuildContext context) {
    final height = _height;
    return Semantics(
      container: true,
      label: context.l10n.terminalKeyboardShortcuts,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.palette.panel,
          border: Border(top: BorderSide(color: widget.palette.border)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            spacing: _gap,
            children: [
              Expanded(
                child: _expanded
                    ? _buildExtraKeys(height)
                    : _keyRow(
                        [..._commonKeys, ..._arrowKeys],
                        height,
                        'primary',
                      ),
              ),
              _action(
                key: 'more',
                label: _expanded
                    ? context.l10n.terminalFewerKeys
                    : context.l10n.terminalMoreKeys,
                icon: _expanded ? Icons.chevron_left : Icons.more_horiz,
                height: height,
                selected: _expanded,
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
              if (widget.keyboardVisible)
                _action(
                  key: 'dismiss-keyboard',
                  label: context.l10n.dismissKeyboard,
                  icon: Icons.keyboard_hide_rounded,
                  height: height,
                  onPressed: widget.onDismissKeyboard,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keyRow(List<_KeySpec> keys, double height, String id) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = keys.fold<double>(
            (keys.length - 1) * _gap,
            (width, key) => width + _keyWidth(key),
          );
          final fits = totalWidth <= constraints.maxWidth;
          final row = Row(
            spacing: _gap,
            children: [for (final key in keys) _keyButton(key, height)],
          );
          if (fits) return row;
          return SingleChildScrollView(
            key: ValueKey('ios-terminal-$id-list'),
            scrollDirection: Axis.horizontal,
            child: row,
          );
        },
      ),
    );
  }

  Widget _buildExtraKeys(double height) {
    return Row(
      key: const Key('ios-terminal-extra-keys'),
      spacing: 8,
      children: [
        PopupMenuButton<_KeyGroup>(
          key: const Key('ios-terminal-key-group'),
          tooltip: context.l10n.terminalKeyGroup,
          requestFocus: false,
          initialValue: _group,
          onSelected: (group) => setState(() => _group = group),
          itemBuilder: (context) => [
            for (final group in _KeyGroup.values)
              PopupMenuItem(
                key: Key('ios-terminal-group-${group.name}'),
                value: group,
                child: Text(group.label(context.l10n)),
              ),
          ],
          child: Container(
            height: height,
            constraints: const BoxConstraints(minWidth: _minimumTarget),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: widget.palette.selected,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                Text(_group.label(context.l10n), style: _keyStyle),
                Icon(
                  Icons.expand_more,
                  size: 16,
                  color: widget.palette.textPrimary,
                ),
              ],
            ),
          ),
        ),
        Expanded(child: _keyRow(_group.keys, height, _group.name)),
      ],
    );
  }

  Widget _keyButton(_KeySpec spec, double height) {
    final description = spec.description?.call(context.l10n);
    final label = description == null
        ? context.l10n.insertTerminalKey(spec.accessibleLabel)
        : '${spec.accessibleLabel} · $description';
    return _button(
      key: Key('ios-terminal-key-${spec.accessibleLabel}'),
      label: label,
      width: _keyWidth(spec),
      height: height,
      child: Text(spec.label, maxLines: 1, style: _keyStyle),
      onPressed: () {
        widget.onSendBytes(spec.bytes);
        unawaited(HapticFeedback.selectionClick());
      },
    );
  }

  Widget _action({
    required String key,
    required String label,
    required IconData icon,
    required double height,
    required VoidCallback onPressed,
    bool selected = false,
  }) => _button(
    key: Key('ios-terminal-$key'),
    label: label,
    height: height,
    width: height,
    expanded: key == 'more' ? _expanded : null,
    selected: selected,
    onPressed: onPressed,
    child: Icon(icon, size: 20, color: widget.palette.textPrimary),
  );

  Widget _button({
    required Key key,
    required String label,
    required double width,
    required double height,
    required Widget child,
    required VoidCallback onPressed,
    bool selected = false,
    bool? expanded,
  }) => Semantics(
    key: key,
    button: true,
    label: label,
    expanded: expanded,
    onTap: onPressed,
    excludeSemantics: true,
    child: Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Material(
        color: selected
            ? widget.palette.selected
            : widget.palette.chromeElevated,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: SizedBox(
            width: width,
            height: height,
            child: Center(child: child),
          ),
        ),
      ),
    ),
  );
}
