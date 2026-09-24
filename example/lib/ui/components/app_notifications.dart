import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../foundation/app_theme_tokens.dart';
import 'app_panel.dart';

/// One presentation path for desktop notices and mobile snack bars.
abstract final class AppNotifications {
  static bool usesDesktopHost(BuildContext context) => _host(context) != null;

  static AppNotificationController show(
    BuildContext context,
    SnackBar notice, {
    String? deduplicationKey,
    IconData icon = Icons.info_outline,
    bool replaceCurrent = false,
    bool hasActions = false,
  }) {
    final host = _host(context);
    if (host != null) {
      return host.show(
        notice,
        deduplicationKey: deduplicationKey,
        icon: icon,
        hasActions: hasActions,
      );
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return AppNotificationController._(
        Future.value(SnackBarClosedReason.remove),
        () {},
      );
    }
    if (replaceCurrent) messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(notice);
    return AppNotificationController._(controller.closed, controller.close);
  }

  static void dismissLatest(BuildContext context) {
    final host = _host(context);
    if (host != null) {
      host.dismissLatest();
    } else {
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    }
  }

  static _AppNotificationHostState? _host(BuildContext context) {
    final desktop = switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
    return desktop
        ? context.findAncestorStateOfType<_AppNotificationHostState>()
        : null;
  }
}

class AppNotificationController {
  const AppNotificationController._(this.closed, this.close);

  final Future<SnackBarClosedReason> closed;
  final VoidCallback close;
}

/// Install in MaterialApp.builder so dialogs and the terminal share a host.
class AppNotificationHost extends StatefulWidget {
  const AppNotificationHost({
    required this.child,
    this.topInset = 0,
    super.key,
  });

  final Widget child;
  final double topInset;

  @override
  State<AppNotificationHost> createState() => _AppNotificationHostState();
}

class _AppNotificationHostState extends State<AppNotificationHost> {
  static const _maximumVisible = 3;
  final _entries = <_Notice>[];
  late final _layer = OverlayEntry(builder: _buildContent);

  @override
  void didUpdateWidget(AppNotificationHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _layer.markNeedsBuild();
  }

  AppNotificationController show(
    SnackBar notice, {
    required String? deduplicationKey,
    required IconData icon,
    required bool hasActions,
  }) {
    // Only passive text is coalesced. Actions own separate callbacks/resources.
    final passive = !hasActions && notice.action == null && !notice.persist;
    final identity = passive
        ? deduplicationKey ??
              (notice.content is Text ? (notice.content as Text).data : null)
        : null;
    final entry = _Notice(
      notice,
      identity: identity,
      icon: icon,
      isPassive: passive,
    );
    setState(() {
      if (identity != null) {
        for (final previous
            in _entries.where((item) => item.identity == identity).toList()) {
          _remove(previous, SnackBarClosedReason.hide);
        }
      }
      _entries.insert(0, entry);
      // Do not replay stale status messages after a burst. Actionable notices
      // remain queued and begin their timeout only when they become visible.
      for (final previous in _entries.skip(_maximumVisible).toList()) {
        if (previous.isPassive) _remove(previous, SnackBarClosedReason.remove);
      }
    });
    _layer.markNeedsBuild();
    return AppNotificationController._(
      entry.closed.future,
      () => _close(entry, SnackBarClosedReason.hide),
    );
  }

  void dismissLatest() {
    if (_entries.isNotEmpty) _close(_entries.first, SnackBarClosedReason.hide);
  }

  void _remove(_Notice entry, SnackBarClosedReason reason) {
    _entries.remove(entry);
    if (!entry.closed.isCompleted) entry.closed.complete(reason);
  }

  void _close(_Notice entry, SnackBarClosedReason reason) {
    if (!mounted || !_entries.contains(entry)) return;
    setState(() => _remove(entry, reason));
    _layer.markNeedsBuild();
  }

  @override
  void dispose() {
    for (final entry in _entries.toList()) {
      _remove(entry, SnackBarClosedReason.remove);
    }
    _layer.remove();
    _layer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_layer]);

  Widget _buildContent(BuildContext context) {
    final tokens = context.appTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final safe = MediaQuery.paddingOf(context);
        // Leave the title/tab controls free and keep notices in the upper half
        // of even a short window, away from the shell's command line.
        final top = safe.top + widget.topInset + tokens.spacing.xl;
        final width = math.max(
          0.0,
          math.min(
            360.0,
            constraints.maxWidth - safe.horizontal - tokens.spacing.xl * 2,
          ),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (_entries.isNotEmpty)
              Positioned(
                top: top,
                right: safe.right + tokens.spacing.xl,
                width: width,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.max(0, constraints.maxHeight / 2 - top),
                  ),
                  child: SingleChildScrollView(
                    primary: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final entry in _entries.take(_maximumVisible))
                          Padding(
                            key: entry.key,
                            padding: EdgeInsets.only(bottom: tokens.spacing.md),
                            child: _NotificationCard(
                              entry: entry,
                              onClose: (reason) => _close(entry, reason),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Notice {
  _Notice(
    this.content, {
    required this.identity,
    required this.icon,
    required this.isPassive,
  });

  final SnackBar content;
  final String? identity;
  final IconData icon;
  final key = UniqueKey();
  final closed = Completer<SnackBarClosedReason>();
  final bool isPassive;
}

class _NotificationCard extends StatefulWidget {
  const _NotificationCard({required this.entry, required this.onClose});

  final _Notice entry;
  final ValueChanged<SnackBarClosedReason> onClose;

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard> {
  Timer? _timer;
  bool _hovered = false;
  bool _focused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (_hovered || _focused || MediaQuery.accessibleNavigationOf(context)) {
      return;
    }
    _timer = Timer(widget.entry.content.duration, () {
      widget.onClose(SnackBarClosedReason.timeout);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTheme;
    final theme = Theme.of(context);
    final notice = widget.entry.content;
    final action = notice.action;
    return MouseRegion(
      onEnter: (_) {
        _hovered = true;
        _restartTimer();
      },
      onExit: (_) {
        _hovered = false;
        _restartTimer();
      },
      child: Focus(
        canRequestFocus: false,
        onFocusChange: (focused) {
          _focused = focused;
          _restartTimer();
        },
        child: Semantics(
          container: true,
          liveRegion: true,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 150),
            builder: (context, opacity, child) =>
                Opacity(opacity: opacity, child: child),
            child: AppPanel(
              key: notice.key,
              tone: AppPanelTone.overlay,
              shadow: true,
              borderRadius: BorderRadius.circular(tokens.radius.lg),
              padding: EdgeInsets.all(tokens.spacing.lg),
              child: DefaultTextStyle(
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: tokens.textPrimary,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: tokens.spacing.xs),
                      child: ExcludeSemantics(
                        child: Icon(
                          widget.entry.icon,
                          size: 18,
                          color: tokens.textMuted,
                        ),
                      ),
                    ),
                    SizedBox(width: tokens.spacing.md),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          notice.content,
                          if (action != null)
                            TextButton(
                              key: action.key,
                              onPressed: () {
                                widget.onClose(SnackBarClosedReason.action);
                                action.onPressed();
                              },
                              child: Text(action.label),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          widget.onClose(SnackBarClosedReason.dismiss),
                      icon: const Icon(Icons.close, size: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
