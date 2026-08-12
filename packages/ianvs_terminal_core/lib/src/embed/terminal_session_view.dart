import 'dart:async';

import 'package:flutter/material.dart';

import '../runtime/terminal_runtime_controller.dart';
import '../terminal/selection_controller.dart';
import '../terminal/terminal_input_controller.dart';
import '../terminal/terminal_viewport.dart';
import '../terminal/terminal_viewport_colors.dart';
import 'terminal_session_handle.dart';

/// Lets a host wrap or replace the fully wired default viewport.
///
/// The supplied [viewport] already handles keyboard input, selection,
/// scrolling, focus reporting, graphics, and resize synchronization.
typedef TerminalSessionViewportBuilder =
    Widget Function(
      BuildContext context,
      TerminalSessionHandle session,
      Widget viewport,
    );

typedef TerminalSessionErrorBuilder =
    Widget Function(BuildContext context, Object error, StackTrace stackTrace);

typedef TerminalSessionExitBuilder =
    Widget Function(BuildContext context, TerminalSessionExitEvent event);

/// A Flutter surface for an already configured [TerminalSessionHandle].
///
/// The widget opens the session when needed and wires the low-level viewport
/// to its runtime. Set [disposeSession] when this widget owns the session;
/// tab containers normally keep ownership in their controller instead.
class TerminalSessionView extends StatefulWidget {
  const TerminalSessionView({
    super.key,
    required this.session,
    this.disposeSession = false,
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

  final TerminalSessionHandle session;
  final bool disposeSession;
  final bool autofocus;
  final EdgeInsets contentPadding;
  final TerminalViewportColors? colors;
  final bool useFrameDefaultColors;
  final TerminalSessionViewportBuilder? viewportBuilder;
  final TerminalSessionErrorBuilder? errorBuilder;
  final TerminalSessionExitBuilder? exitBuilder;
  final ValueChanged<TerminalSessionHandle>? onReady;
  final ValueChanged<TerminalSessionExitEvent>? onExit;
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
  StreamSubscription<TerminalRuntimeSignal>? _runtimeSubscription;
  TerminalSessionExitEvent? _exitEvent;
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
    if (!identical(oldWidget.session, widget.session)) {
      _detachSession(oldWidget.session, dispose: oldWidget.disposeSession);
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
      if (!widget.session.isOpen) {
        widget.session.open();
      }
      final sessionId = widget.session.sessionId!;
      final runtime = widget.session.runtime;
      final viewport = widget.session.viewportController;
      _viewportController = viewport;
      _inputController = TerminalInputController(
        sessionId: sessionId,
        runtime: runtime,
        readFrame: () => viewport.frame,
        emulation: widget.session.sessionConfig.emulation,
        readSelection: () => _selectionController.textForFrame(viewport.frame),
        copySelection: runtime.copyToClipboard,
        readClipboard: runtime.readClipboard,
      );
      _runtimeSubscription = widget.session.runtimeSignals.listen(
        _handleRuntimeSignal,
      );
      widget.onReady?.call(widget.session);
      if (widget.autofocus) {
        _scheduleAutofocus();
      }
    } on Object catch (error, stackTrace) {
      _openError = error;
      _openStackTrace = stackTrace;
      widget.onError?.call(error, stackTrace);
    }
  }

  void _detachSession(TerminalSessionHandle session, {required bool dispose}) {
    unawaited(_runtimeSubscription?.cancel());
    _runtimeSubscription = null;
    _viewportController = null;
    _inputController = null;
    _scheduledViewportSize = null;
    _scheduledDevicePixelRatio = null;
    _resizeScheduled = false;
    if (dispose) {
      session.dispose();
    }
  }

  void _handleRuntimeSignal(TerminalRuntimeSignal signal) {
    if (signal case TerminalRuntimeSessionEventSignal(
      payload: final TerminalSessionExitEvent event,
    )) {
      _handleExit(event);
    }
  }

  void _handleExit(TerminalSessionExitEvent event) {
    if (!mounted) {
      return;
    }
    setState(() {
      _exitEvent = event;
    });
    widget.onExit?.call(event);
  }

  void _handleFocusChanged() {
    final sessionId = widget.session.sessionId;
    if (sessionId == null) {
      return;
    }
    widget.session.setFocused(focused: _focusNode.hasFocus);
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
      final sessionId = widget.session.sessionId;
      if (size == null || ratio == null || sessionId == null) {
        return;
      }
      widget.session.resize(size, ratio);
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
    final config = widget.session.sessionConfig;
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
          graphicsCache: widget.session.runtime.graphicsCacheFor(
            widget.session.sessionId!,
          ),
          graphicsDiagnosticSessionId: widget.session.sessionId,
          onHostKeyEvent: widget.onHostKeyEvent,
          onMeasuredCellSizeChanged: (_) {
            _scheduleResize(viewportSize, devicePixelRatio, force: true);
          },
          onScrollLines: widget.session.scrollLines,
          onScrollToOffset: widget.session.scrollToLine,
          onToggleBlock: (block) {
            _selectionController.clear();
            widget.session.setBlockFolded(block.id, folded: !block.folded);
          },
          onDismissBlockRender: (block) {
            _selectionController.clear();
            widget.session.setBlockRendered(block.id, rendered: false);
          },
          onActivateInlineButton: (button) {
            widget.session.activateItermButton(button.id);
          },
          onOpenLink: widget.onOpenLink,
          onOpenLinkTarget: widget.onOpenLinkTarget,
          onLinkHoverChanged: widget.onLinkHoverChanged,
          onLinkContextMenu: widget.onLinkContextMenu,
        );
        return widget.viewportBuilder?.call(
              context,
              widget.session,
              viewport,
            ) ??
            viewport;
      },
    );
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _detachSession(widget.session, dispose: widget.disposeSession);
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
