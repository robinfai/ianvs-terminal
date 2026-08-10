import 'package:flutter/material.dart';

import '../terminal/selection_controller.dart';
import '../terminal/terminal_input_controller.dart';
import '../terminal/terminal_viewport.dart';
import '../terminal/terminal_viewport_colors.dart';
import '../xterm/terminal_api.dart';

/// Lets a host wrap or replace the fully wired default viewport.
///
/// The supplied [viewport] already handles keyboard input, selection,
/// scrolling, focus reporting, graphics, and resize synchronization.
typedef TerminalSessionViewportBuilder =
    Widget Function(BuildContext context, Terminal terminal, Widget viewport);

typedef TerminalSessionErrorBuilder =
    Widget Function(BuildContext context, Object error, StackTrace stackTrace);

typedef TerminalSessionExitBuilder =
    Widget Function(BuildContext context, TerminalExitEvent event);

/// A Flutter surface for an already configured [Terminal].
///
/// The widget opens the terminal when needed and wires the low-level viewport
/// to its runtime. Set [disposeTerminal] when this widget owns the terminal;
/// tab containers normally keep ownership in their controller instead.
class TerminalSessionView extends StatefulWidget {
  const TerminalSessionView({
    super.key,
    required this.terminal,
    this.disposeTerminal = false,
    this.autofocus = false,
    this.contentPadding = EdgeInsets.zero,
    this.colors,
    this.useFrameDefaultColors = true,
    this.viewportBuilder,
    this.errorBuilder,
    this.exitBuilder,
    this.onReady,
    this.onExit,
    this.onError,
    this.onOpenLink,
    this.onOpenLinkTarget,
    this.onLinkHoverChanged,
    this.onLinkContextMenu,
    this.onHostKeyEvent,
  });

  final Terminal terminal;
  final bool disposeTerminal;
  final bool autofocus;
  final EdgeInsets contentPadding;
  final TerminalViewportColors? colors;
  final bool useFrameDefaultColors;
  final TerminalSessionViewportBuilder? viewportBuilder;
  final TerminalSessionErrorBuilder? errorBuilder;
  final TerminalSessionExitBuilder? exitBuilder;
  final ValueChanged<Terminal>? onReady;
  final ValueChanged<TerminalExitEvent>? onExit;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final ValueChanged<String>? onOpenLink;
  final ValueChanged<TerminalLinkTarget>? onOpenLinkTarget;
  final ValueChanged<TerminalLinkTarget?>? onLinkHoverChanged;
  final ValueChanged<TerminalLinkTarget>? onLinkContextMenu;
  final KeyEventResult Function(KeyEvent event)? onHostKeyEvent;

  @override
  State<TerminalSessionView> createState() => _TerminalSessionViewState();
}

class _TerminalSessionViewState extends State<TerminalSessionView> {
  final SelectionController _selectionController = SelectionController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'embedded-terminal');
  TerminalViewportController? _viewportController;
  TerminalInputController? _inputController;
  TerminalDisposable? _exitListener;
  TerminalExitEvent? _exitEvent;
  Object? _openError;
  StackTrace? _openStackTrace;
  Size? _scheduledViewportSize;
  double? _scheduledDevicePixelRatio;
  bool _resizeScheduled = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
    _attachTerminal();
  }

  @override
  void didUpdateWidget(covariant TerminalSessionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.terminal, widget.terminal)) {
      _detachTerminal(oldWidget.terminal, dispose: oldWidget.disposeTerminal);
      _attachTerminal();
    }
    if (!oldWidget.autofocus && widget.autofocus) {
      _scheduleAutofocus();
    }
  }

  void _attachTerminal() {
    _exitEvent = null;
    _openError = null;
    _openStackTrace = null;
    try {
      if (!widget.terminal.isOpen) {
        widget.terminal.open();
      }
      final sessionId = widget.terminal.sessionId!;
      final runtime = widget.terminal.runtimeController;
      final viewport = widget.terminal.viewportController;
      _viewportController = viewport;
      _inputController = TerminalInputController(
        sessionId: sessionId,
        runtime: runtime,
        readFrame: () => viewport.frame,
        emulation: widget.terminal.effectiveSessionConfig.emulation,
        readSelection: () => _selectionController.textForFrame(viewport.frame),
        copySelection: runtime.copyToClipboard,
        readClipboard: runtime.readClipboard,
      );
      _exitListener = widget.terminal.onExit(_handleExit);
      widget.onReady?.call(widget.terminal);
      if (widget.autofocus) {
        _scheduleAutofocus();
      }
    } on Object catch (error, stackTrace) {
      _openError = error;
      _openStackTrace = stackTrace;
      widget.onError?.call(error, stackTrace);
    }
  }

  void _detachTerminal(Terminal terminal, {required bool dispose}) {
    _exitListener?.dispose();
    _exitListener = null;
    _viewportController = null;
    _inputController = null;
    _scheduledViewportSize = null;
    _scheduledDevicePixelRatio = null;
    _resizeScheduled = false;
    if (dispose) {
      terminal.dispose();
    }
  }

  void _handleExit(TerminalExitEvent event) {
    if (!mounted) {
      return;
    }
    setState(() {
      _exitEvent = event;
    });
    widget.onExit?.call(event);
  }

  void _handleFocusChanged() {
    final sessionId = widget.terminal.sessionId;
    if (sessionId == null) {
      return;
    }
    widget.terminal.runtimeController.setSessionFocused(
      sessionId,
      focused: _focusNode.hasFocus,
    );
  }

  void _scheduleAutofocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.autofocus && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  void _scheduleResize(
    Size viewportSize,
    double devicePixelRatio, {
    bool force = false,
  }) {
    if (!viewportSize.isFinite ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0) {
      return;
    }
    if (!force &&
        _scheduledViewportSize == viewportSize &&
        _scheduledDevicePixelRatio == devicePixelRatio) {
      return;
    }
    _scheduledViewportSize = viewportSize;
    _scheduledDevicePixelRatio = devicePixelRatio;
    if (_resizeScheduled) {
      return;
    }
    _resizeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resizeScheduled = false;
      if (!mounted) {
        return;
      }
      final size = _scheduledViewportSize;
      final ratio = _scheduledDevicePixelRatio;
      final sessionId = widget.terminal.sessionId;
      if (size == null || ratio == null || sessionId == null) {
        return;
      }
      widget.terminal.runtimeController.resizeSession(sessionId, size, ratio);
    });
  }

  Size _contentSizeFor(BoxConstraints constraints) {
    final size = constraints.biggest;
    return Size(
      (size.width - widget.contentPadding.horizontal).clamp(1, double.infinity),
      (size.height - widget.contentPadding.vertical).clamp(1, double.infinity),
    );
  }

  TerminalViewportColors _resolvedColors(BuildContext context) {
    final supplied = widget.colors;
    if (supplied != null) {
      return supplied;
    }
    final scheme = Theme.of(context).colorScheme;
    return TerminalViewportColors(
      canvasBackground: scheme.surfaceContainerLowest,
      foreground: scheme.onSurface,
      cursor: scheme.primary,
      selection: scheme.primary.withValues(alpha: 0.28),
      scrollbarTrack: scheme.outlineVariant.withValues(alpha: 0.32),
      scrollbarThumb: scheme.onSurfaceVariant.withValues(alpha: 0.62),
      minimumContrastRatio: 4.5,
      smartCursorColor: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _openError;
    if (error != null) {
      final stackTrace = _openStackTrace ?? StackTrace.empty;
      return widget.errorBuilder?.call(context, error, stackTrace) ??
          _TerminalSessionMessage(
            icon: Icons.error_outline_rounded,
            message: 'Unable to open terminal',
            detail: error.toString(),
          );
    }
    final exitEvent = _exitEvent;
    if (exitEvent != null) {
      return widget.exitBuilder?.call(context, exitEvent) ??
          _TerminalSessionMessage(
            icon: Icons.stop_circle_outlined,
            message: exitEvent.exitCode == null
                ? 'Terminal exited'
                : 'Terminal exited with code ${exitEvent.exitCode}',
          );
    }
    final viewportController = _viewportController;
    final inputController = _inputController;
    if (viewportController == null || inputController == null) {
      return const SizedBox.shrink();
    }
    final config = widget.terminal.effectiveSessionConfig;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = _contentSizeFor(constraints);
        _scheduleResize(viewportSize, devicePixelRatio);
        final viewport = TerminalViewport(
          controller: viewportController,
          selectionController: _selectionController,
          inputController: inputController,
          focusNode: _focusNode,
          contentPadding: widget.contentPadding,
          colors: _resolvedColors(context),
          useFrameDefaultColors: widget.useFrameDefaultColors,
          font: config.display.font,
          cursor: config.display.cursor,
          copyOnSelect: config.interaction.copyOnSelect,
          optionDragMode: config.interaction.optionDragMode,
          graphicsCache: widget.terminal.runtimeController.graphicsCacheFor(
            widget.terminal.sessionId!,
          ),
          graphicsDiagnosticSessionId: widget.terminal.sessionId,
          onHostKeyEvent: widget.onHostKeyEvent,
          onMeasuredCellSizeChanged: (_) {
            _scheduleResize(viewportSize, devicePixelRatio, force: true);
          },
          onScrollLines: widget.terminal.scrollLines,
          onScrollToOffset: widget.terminal.scrollToLine,
          onToggleBlock: (block) {
            _selectionController.clear();
            widget.terminal.setBlockFolded(block.id, folded: !block.folded);
          },
          onDismissBlockRender: (block) {
            _selectionController.clear();
            widget.terminal.setBlockRendered(block.id, rendered: false);
          },
          onActivateInlineButton: (button) {
            widget.terminal.activateItermButton(button.id);
          },
          onOpenLink: widget.onOpenLink,
          onOpenLinkTarget: widget.onOpenLinkTarget,
          onLinkHoverChanged: widget.onLinkHoverChanged,
          onLinkContextMenu: widget.onLinkContextMenu,
        );
        return widget.viewportBuilder?.call(
              context,
              widget.terminal,
              viewport,
            ) ??
            viewport;
      },
    );
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _detachTerminal(widget.terminal, dispose: widget.disposeTerminal);
    _selectionController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}

class _TerminalSessionMessage extends StatelessWidget {
  const _TerminalSessionMessage({
    required this.icon,
    required this.message,
    this.detail,
  });

  final IconData icon;
  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerLowest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: scheme.onSurfaceVariant),
              const SizedBox(height: 8),
              Text(message, style: Theme.of(context).textTheme.bodyMedium),
              if (detail != null) ...[
                const SizedBox(height: 4),
                Text(
                  detail!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
