import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/app_motion.dart';
import '../foundation/app_theme_tokens.dart';

/// One command model for pointer menus and touch action sheets. Shortcuts are
/// display hints: the owning screen registers their actions with its shortcuts.
class AppMenuEntry {
  const AppMenuEntry({
    required this.label,
    this.key,
    this.icon,
    this.onSelected,
    this.enabled = true,
    this.selected = false,
    this.destructive = false,
    this.shortcut,
    this.children = const [],
  }) : divider = false;

  const AppMenuEntry.divider()
    : label = '',
      key = null,
      icon = null,
      onSelected = null,
      enabled = false,
      selected = false,
      destructive = false,
      shortcut = null,
      children = const [],
      divider = true;

  final String label;
  final Key? key;
  final IconData? icon;
  final VoidCallback? onSelected;
  final bool enabled;
  final bool selected;
  final bool destructive;
  final MenuSerializableShortcut? shortcut;
  final List<AppMenuEntry> children;
  final bool divider;
}

MenuStyle appMenuStyle(BuildContext context) {
  final theme = Theme.of(context);
  final size = MediaQuery.sizeOf(context);
  return (theme.menuTheme.style ?? const MenuStyle()).copyWith(
    maximumSize: WidgetStatePropertyAll(
      Size(
        math.max(0, math.min(360, size.width - 16)),
        math.max(0, size.height - MediaQuery.paddingOf(context).vertical - 16),
      ),
    ),
    minimumSize: WidgetStatePropertyAll(
      Size(math.min(220, math.max(0, size.width - 16)), 0),
    ),
  );
}

ButtonStyle appMenuItemStyle(BuildContext context, {bool destructive = false}) {
  final theme = Theme.of(context);
  final tokens = context.appTheme;
  return (theme.menuButtonTheme.style ?? const ButtonStyle()).copyWith(
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? tokens.textSubtle
          : destructive
          ? tokens.danger
          : tokens.textPrimary,
    ),
    side: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: tokens.focus, width: 2)
          : BorderSide.none,
    ),
  );
}

/// Uses Flutter's menu geometry, pointer corridor and directional keyboard
/// traversal. Touch uses a single-column, drill-down action sheet instead of
/// cascading panels that compete for narrow screen space.
class AppMenuButton extends StatefulWidget {
  const AppMenuButton({
    super.key,
    required this.tooltip,
    required this.entries,
    this.icon = Icons.more_horiz_rounded,
    this.label,
    this.enabled = true,
    this.contextChild,
  });

  final String tooltip;
  final List<AppMenuEntry> entries;
  final IconData icon;
  final String? label;
  final bool enabled;

  /// Right click / long press are additional entry points. A visible, accessible
  /// button is always retained next to this content.
  final Widget? contextChild;

  @override
  State<AppMenuButton> createState() => _AppMenuButtonState();
}

class _AppMenuButtonState extends State<AppMenuButton> {
  final _controller = MenuController();
  final _focus = FocusNode();
  final _firstFocus = FocusNode();
  bool _sheetOpen = false;

  @override
  void didUpdateWidget(covariant AppMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!widget.enabled || widget.entries.isEmpty) && _controller.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.close();
      });
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _firstFocus.dispose();
    super.dispose();
  }

  Future<void> _open([Offset? position]) async {
    if (!widget.enabled || widget.entries.isEmpty || _sheetOpen) return;
    _focus.requestFocus();
    if (context.usesTouchControlDensity) {
      setState(() => _sheetOpen = true);
      final command = await showModalBottomSheet<AppMenuEntry>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        sheetAnimationStyle: appDialogAnimation(context),
        builder: (_) =>
            _AppMenuSheet(title: widget.tooltip, entries: widget.entries),
      );
      if (!mounted) return;
      setState(() => _sheetOpen = false);
      if (_focus.canRequestFocus) _focus.requestFocus();
      // A parent may disable this control while the sheet is open.
      if (widget.enabled && widget.entries.isNotEmpty) {
        command?.onSelected?.call();
      }
    } else if (_controller.isOpen) {
      _controller.close();
    } else {
      _controller.open(position: position);
    }
  }

  Widget _entry(AppMenuEntry entry, {FocusNode? focus}) {
    if (entry.divider) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Divider(),
      );
    }
    final leading = SizedBox.square(
      dimension: 18,
      child: entry.selected
          ? const Icon(Icons.check_rounded, size: 18)
          : entry.icon == null
          ? null
          : Icon(entry.icon, size: 18),
    );
    if (entry.children.isNotEmpty) {
      return SubmenuButton(
        key: entry.key,
        focusNode: focus,
        menuStyle: appMenuStyle(context),
        hoverOpenDelay: const Duration(milliseconds: 120),
        submenuIcon: const WidgetStatePropertyAll(
          Icon(Icons.chevron_right, size: 18),
        ),
        style: appMenuItemStyle(context),
        leadingIcon: leading,
        menuChildren: entry.enabled
            ? entry.children.map(_entry).toList()
            : const [],
        child: Text(entry.label),
      );
    }
    return Semantics(
      selected: entry.selected,
      child: MenuItemButton(
        key: entry.key,
        focusNode: focus,
        style: appMenuItemStyle(context, destructive: entry.destructive),
        leadingIcon: leading,
        shortcut: entry.shortcut,
        onPressed: entry.enabled ? entry.onSelected : null,
        child: Text(entry.label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.entries
        .where(
          (entry) =>
              !entry.divider &&
              entry.enabled &&
              (entry.children.isNotEmpty || entry.onSelected != null),
        )
        .firstOrNull;
    return MenuAnchor(
      controller: _controller,
      childFocusNode: _focus,
      consumeOutsideTap: true,
      onOpen: () => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.isOpen && _firstFocus.context != null) {
          _firstFocus.requestFocus();
        }
      }),
      useRootOverlay: true,
      style: appMenuStyle(context),
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        for (final entry in widget.entries)
          _entry(entry, focus: identical(first, entry) ? _firstFocus : null),
      ],
      builder: (context, controller, child) {
        final active = widget.enabled && widget.entries.isNotEmpty;
        final trigger = Semantics(
          expanded: controller.isOpen || _sheetOpen,
          child: widget.label == null
              ? IconButton(
                  focusNode: _focus,
                  tooltip: widget.tooltip,
                  onPressed: active ? _open : null,
                  icon: Icon(widget.icon),
                )
              : OutlinedButton.icon(
                  focusNode: _focus,
                  onPressed: active ? _open : null,
                  icon: Icon(widget.icon),
                  label: Text(widget.label!),
                ),
        );
        return Focus(
          onKeyEvent: (_, event) {
            if (active &&
                _focus.hasPrimaryFocus &&
                event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                    event.logicalKey == LogicalKeyboardKey.arrowUp)) {
              unawaited(_open());
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          canRequestFocus: false,
          child: widget.contextChild == null
              ? trigger
              : GestureDetector(
                  onSecondaryTapUp: active
                      ? (details) => _open(details.localPosition)
                      : null,
                  onLongPressStart: active
                      ? (details) => _open(details.localPosition)
                      : null,
                  child: Row(
                    children: [
                      Expanded(child: widget.contextChild!),
                      trigger,
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _AppMenuSheet extends StatefulWidget {
  const _AppMenuSheet({required this.title, required this.entries});
  final String title;
  final List<AppMenuEntry> entries;
  @override
  State<_AppMenuSheet> createState() => _AppMenuSheetState();
}

class _AppMenuSheetState extends State<_AppMenuSheet> {
  final _path = <AppMenuEntry>[];
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _back() {
    if (_path.isEmpty) {
      Navigator.of(context).pop();
    } else {
      setState(_path.removeLast);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _path.isEmpty ? widget.entries : _path.last.children;
    final title = _path.isEmpty ? widget.title : _path.last.label;
    return PopScope<AppMenuEntry>(
      canPop: _path.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _back},
        child: Focus(
          autofocus: true,
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (_path.isNotEmpty) BackButton(onPressed: _back),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Semantics(
                            header: true,
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                      ),
                      CloseButton(onPressed: () => Navigator.of(context).pop()),
                    ],
                  ),
                  const Divider(),
                  Flexible(
                    child: ListView(
                      controller: _scroll,
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(8),
                      children: [
                        for (final entry in entries)
                          if (entry.divider)
                            const Divider(height: 16)
                          else
                            ListTile(
                              key: entry.key,
                              enabled:
                                  entry.enabled &&
                                  (entry.children.isNotEmpty ||
                                      entry.onSelected != null),
                              selected: entry.selected,
                              textColor: entry.destructive
                                  ? context.appTheme.danger
                                  : null,
                              leading: Icon(
                                entry.selected
                                    ? Icons.check_rounded
                                    : entry.icon,
                              ),
                              title: Text(entry.label),
                              trailing: entry.children.isEmpty
                                  ? null
                                  : const Icon(Icons.chevron_right),
                              onTap: !entry.enabled
                                  ? null
                                  : () {
                                      if (entry.children.isEmpty) {
                                        Navigator.of(context).pop(entry);
                                      } else {
                                        setState(() => _path.add(entry));
                                        if (_scroll.hasClients) {
                                          _scroll.jumpTo(0);
                                        }
                                      }
                                    },
                            ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
