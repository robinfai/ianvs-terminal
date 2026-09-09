import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../foundation/app_theme_tokens.dart';

/// A form select whose anchored menu shares the field's typography and shape.
/// Menu rows adapt to pointer/touch input and grow with their content.
class AppDropdownFormField<T> extends StatelessWidget {
  const AppDropdownFormField({
    super.key,
    required this.items,
    required this.onChanged,
    this.initialValue,
    this.decoration = const InputDecoration(),
    this.isExpanded = false,
    this.iconSize,
    this.itemHeight,
    this.menuMaxHeight,
    this.borderRadius,
    this.selectedItemBuilder,
    this.hint,
  });
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final T? initialValue;
  final InputDecoration decoration;
  final bool isExpanded;
  final double? iconSize;

  /// Minimum menu row height; text may grow beyond it.
  final double? itemHeight;
  final double? menuMaxHeight;
  final BorderRadius? borderRadius;
  final DropdownButtonBuilder? selectedItemBuilder;
  final Widget? hint;

  @override
  Widget build(BuildContext context) =>
      _AppDropdownField<T>(configuration: this);
}

class _AppDropdownField<T> extends FormField<T> {
  _AppDropdownField({required this.configuration})
    : super(
        initialValue: configuration.initialValue,
        enabled:
            configuration.onChanged != null &&
            (configuration.items?.isNotEmpty ?? false),
        builder: (state) => (state as _AppDropdownFieldState<T>).buildControl(),
      );
  final AppDropdownFormField<T> configuration;
  @override
  FormFieldState<T> createState() => _AppDropdownFieldState<T>();
}

class _AppDropdownFieldState<T> extends FormFieldState<T> {
  final _controller = MenuController();
  final _fieldFocus = FocusNode();
  final _itemFocus = <FocusNode>[];
  bool _focused = false;
  AppDropdownFormField<T> get configuration =>
      (widget as _AppDropdownField<T>).configuration;

  @override
  void initState() {
    super.initState();
    _syncItemFocus();
  }

  @override
  void didUpdateWidget(covariant _AppDropdownField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      setValue(widget.initialValue);
    }
    _syncItemFocus();
  }

  void _syncItemFocus() {
    final count = configuration.items?.length ?? 0;
    while (_itemFocus.length > count) {
      _itemFocus.removeLast().dispose();
    }
    while (_itemFocus.length < count) {
      _itemFocus.add(FocusNode());
    }
  }

  @override
  void dispose() {
    _fieldFocus.dispose();
    for (final node in _itemFocus) {
      node.dispose();
    }
    super.dispose();
  }

  int get _selectedIndex =>
      configuration.items?.indexWhere((item) => item.value == value) ?? -1;

  void _focusSelectedItem() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.isOpen) return;
      final items = configuration.items!;
      final selected = _selectedIndex;
      final index = selected >= 0 && items[selected].enabled
          ? selected
          : items.indexWhere((item) => item.enabled);
      if (index >= 0) _itemFocus[index].requestFocus();
    });
  }

  void _toggleMenu() {
    if (!widget.enabled) return;
    _fieldFocus.requestFocus();
    if (_controller.isOpen) {
      _controller.close();
    } else {
      _controller.open();
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!widget.enabled || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _toggleMenu();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget buildControl() {
    final config = configuration;
    final theme = Theme.of(context);
    final tokens = context.appTheme;
    final textStyle = theme.textTheme.bodyLarge!;
    final items = config.items ?? <DropdownMenuItem<T>>[];
    final selected = _selectedIndex;
    final selectedChildren = config.selectedItemBuilder?.call(context);
    final selectedChild = selected < 0
        ? config.hint ?? const SizedBox.shrink()
        : selectedChildren?[selected] ?? items[selected].child;
    final touch = theme.materialTapTargetSize == MaterialTapTargetSize.padded;
    final rowHeight = config.itemHeight ?? (touch ? 48.0 : 32.0);
    final radius =
        config.borderRadius ?? BorderRadius.circular(tokens.radius.md);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 240.0;
        final maxHeight = math.min(
          config.menuMaxHeight ?? 320.0,
          math.max(0.0, MediaQuery.sizeOf(context).height - 32),
        );
        return MenuAnchor(
          controller: _controller,
          childFocusNode: _fieldFocus,
          consumeOutsideTap: true,
          onOpen: _focusSelectedItem,
          crossAxisUnconstrained: false,
          alignmentOffset: const Offset(0, 4),
          style: MenuStyle(
            alignment: AlignmentDirectional.bottomStart,
            backgroundColor: WidgetStatePropertyAll(tokens.panel),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            shadowColor: WidgetStatePropertyAll(
              theme.colorScheme.shadow.withValues(alpha: 0.22),
            ),
            elevation: const WidgetStatePropertyAll(4),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
            minimumSize: WidgetStatePropertyAll(Size(width, 0)),
            maximumSize: WidgetStatePropertyAll(Size(width, maxHeight)),
            side: WidgetStatePropertyAll(BorderSide(color: tokens.border)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: radius),
            ),
            visualDensity: VisualDensity.standard,
          ),
          menuChildren: [
            for (var index = 0; index < items.length; index++)
              Semantics(
                selected: index == selected,
                child: MenuItemButton(
                  key: items[index].key,
                  focusNode: _itemFocus[index],
                  onPressed: !items[index].enabled
                      ? null
                      : () {
                          if (!mounted) return;
                          didChange(items[index].value);
                          items[index].onTap?.call();
                          config.onChanged?.call(items[index].value);
                        },
                  style: ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(0, rowHeight)),
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    textStyle: WidgetStatePropertyAll(textStyle),
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.disabled)
                          ? tokens.textSubtle
                          : tokens.textPrimary,
                    ),
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) =>
                          states.contains(WidgetState.focused) ||
                              states.contains(WidgetState.hovered) ||
                              index == selected
                          ? tokens.selected
                          : Colors.transparent,
                    ),
                    overlayColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(tokens.radius.sm),
                      ),
                    ),
                    visualDensity: VisualDensity.standard,
                    tapTargetSize: touch
                        ? MaterialTapTargetSize.padded
                        : MaterialTapTargetSize.shrinkWrap,
                    animationDuration: Duration.zero,
                  ),
                  trailingIcon: SizedBox.square(
                    dimension: 16,
                    child: index == selected
                        ? Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: tokens.accent,
                          )
                        : null,
                  ),
                  child: items[index].child,
                ),
              ),
          ],
          builder: (context, controller, _) => Semantics(
            button: true,
            enabled: widget.enabled,
            expanded: controller.isOpen,
            onTap: widget.enabled ? _toggleMenu : null,
            child: Focus(
              canRequestFocus: false,
              onKeyEvent: _handleKey,
              child: InkWell(
                focusNode: _fieldFocus,
                canRequestFocus: widget.enabled,
                onTap: widget.enabled ? _toggleMenu : null,
                onFocusChange: (focused) => setState(() => _focused = focused),
                borderRadius: radius,
                excludeFromSemantics: true,
                child: InputDecorator(
                  decoration: config.decoration
                      .applyDefaults(theme.inputDecorationTheme)
                      .copyWith(enabled: widget.enabled),
                  isFocused: _focused || controller.isOpen,
                  isEmpty: selected < 0 && config.hint == null,
                  child: DefaultTextStyle(
                    style: textStyle.copyWith(
                      color: widget.enabled
                          ? tokens.textPrimary
                          : tokens.textSubtle,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: Row(
                      mainAxisSize: config.isExpanded
                          ? MainAxisSize.max
                          : MainAxisSize.min,
                      children: [
                        Flexible(
                          fit: config.isExpanded
                              ? FlexFit.tight
                              : FlexFit.loose,
                          child: selectedChild,
                        ),
                        SizedBox(width: tokens.spacing.md),
                        Icon(
                          Icons.arrow_drop_down,
                          size: config.iconSize ?? theme.iconTheme.size ?? 24,
                          color: widget.enabled
                              ? tokens.textMuted
                              : tokens.textSubtle,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
