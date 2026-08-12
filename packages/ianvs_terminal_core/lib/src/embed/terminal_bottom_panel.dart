import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../config/terminal_config.dart';
import '../runtime/terminal_runtime_controller.dart';
import '../terminal/terminal_viewport_colors.dart';
import 'terminal_session_handle.dart';
import 'terminal_session_view.dart';

typedef TerminalPanelTabFactory =
    TerminalPanelTabDefinition Function(int index);

typedef TerminalPanelSessionBuilder =
    Widget Function(
      BuildContext context,
      TerminalPanelTab tab,
      Widget terminalView,
    );

@immutable
class TerminalPanelTabDefinition {
  const TerminalPanelTabDefinition({
    required this.title,
    required this.sessionConfig,
    this.id,
    this.followTerminalTitle = true,
  });

  final String? id;
  final String title;
  final TerminalSessionConfig sessionConfig;
  final bool followTerminalTitle;
}

/// A sensible platform-local shell definition for a panel's `+` action.
TerminalPanelTabDefinition defaultLocalTerminalPanelTab(int index) {
  final environmentShell = Platform.environment['SHELL']?.trim();
  final windowsShell = Platform.environment['ComSpec']?.trim();
  final program = Platform.isWindows
      ? (windowsShell?.isNotEmpty == true ? windowsShell! : 'cmd.exe')
      : (environmentShell?.isNotEmpty == true
            ? environmentShell!
            : Platform.isMacOS
            ? '/bin/zsh'
            : '/bin/sh');
  return TerminalPanelTabDefinition(
    title: index == 1 ? 'Local Terminal' : 'Local Terminal $index',
    sessionConfig: TerminalSessionConfig(
      launch: TerminalLaunchConfig(
        program: program,
        args: Platform.isWindows ? const <String>[] : const <String>['-l'],
      ),
    ),
  );
}

class TerminalPanelTab {
  TerminalPanelTab._({
    required this.id,
    required this.session,
    required this.definition,
  }) : _title = definition.title;

  final String id;
  final TerminalSessionHandle session;
  final TerminalPanelTabDefinition definition;
  String _title;
  bool _exited = false;
  int? _exitCode;
  StreamSubscription<TerminalRuntimeSignal>? _runtimeSubscription;

  String get title => _title;
  bool get exited => _exited;
  int? get exitCode => _exitCode;

  void _dispose() {
    unawaited(_runtimeSubscription?.cancel());
    _runtimeSubscription = null;
    session.dispose();
  }
}

/// Owns terminal tabs and their native sessions.
///
/// Closing a tab disposes its [TerminalSessionHandle]. Disposing the controller
/// closes every remaining tab, so placing this controller in a host session's
/// state ties all embedded PTYs to that host session's lifecycle.
class TerminalPanelController extends ChangeNotifier {
  TerminalPanelController({
    required this.runtime,
    this.defaultTabFactory = defaultLocalTerminalPanelTab,
    this.disposeRuntime = false,
    bool initiallyOpen = false,
  }) : _isOpen = initiallyOpen {
    if (initiallyOpen) {
      addTerminal();
    }
  }

  final TerminalRuntimeController runtime;
  final TerminalPanelTabFactory defaultTabFactory;
  final bool disposeRuntime;
  final List<TerminalPanelTab> _tabs = <TerminalPanelTab>[];
  bool _isOpen;
  String? _activeTabId;
  int _nextTabIndex = 0;
  bool _disposed = false;

  List<TerminalPanelTab> get tabs => List.unmodifiable(_tabs);
  bool get isOpen => _isOpen;
  String? get activeTabId => _activeTabId;
  TerminalPanelTab? get activeTab => _tabFor(_activeTabId);

  TerminalPanelTab addTerminal([TerminalPanelTabDefinition? definition]) {
    _ensureActive();
    final index = ++_nextTabIndex;
    final resolved = definition ?? defaultTabFactory(index);
    final id = resolved.id?.trim().isNotEmpty == true
        ? resolved.id!.trim()
        : 'terminal-$index';
    if (_tabs.any((tab) => tab.id == id)) {
      throw StateError('A terminal tab with id "$id" already exists.');
    }
    final session = TerminalSessionHandle(
      runtime: runtime,
      sessionConfig: resolved.sessionConfig,
    );
    final tab = TerminalPanelTab._(
      id: id,
      session: session,
      definition: resolved,
    );
    try {
      session.open();
      tab._runtimeSubscription = session.runtimeSignals.listen((signal) {
        if (_disposed || signal is! TerminalRuntimeSessionEventSignal) {
          return;
        }
        switch (signal.payload) {
          case TerminalSessionFrameEvent(:final frame):
            if (!resolved.followTerminalTitle) {
              return;
            }
            final normalized = frame.windowTitle?.trim();
            if (normalized == null ||
                normalized.isEmpty ||
                normalized == tab._title) {
              return;
            }
            tab._title = normalized;
            notifyListeners();
          case TerminalSessionExitEvent(:final exitCode):
            tab._exited = true;
            tab._exitCode = exitCode;
            notifyListeners();
          default:
            break;
        }
      });
    } on Object {
      unawaited(tab._runtimeSubscription?.cancel());
      session.dispose();
      rethrow;
    }
    _tabs.add(tab);
    _activeTabId = tab.id;
    _isOpen = true;
    _syncSessionActivity();
    notifyListeners();
    return tab;
  }

  void activateTab(String tabId) {
    _ensureActive();
    if (_activeTabId == tabId || _tabFor(tabId) == null) {
      return;
    }
    _activeTabId = tabId;
    _syncSessionActivity();
    notifyListeners();
  }

  void closeTab(String tabId) {
    _ensureActive();
    final index = _tabs.indexWhere((tab) => tab.id == tabId);
    if (index < 0) {
      return;
    }
    final tab = _tabs.removeAt(index);
    if (_activeTabId == tabId) {
      _activeTabId = _tabs.isEmpty
          ? null
          : _tabs[index.clamp(0, _tabs.length - 1)].id;
    }
    _disposeTab(tab);
    _syncSessionActivity();
    notifyListeners();
  }

  void setOpen(bool value) {
    _ensureActive();
    if (value && _tabs.isEmpty) {
      addTerminal();
      return;
    }
    if (_isOpen == value) {
      return;
    }
    _isOpen = value;
    _syncSessionActivity();
    notifyListeners();
  }

  void toggle() => setOpen(!_isOpen);

  void renameTab(String tabId, String title) {
    _ensureActive();
    final tab = _tabFor(tabId);
    final normalized = title.trim();
    if (tab == null || normalized.isEmpty || normalized == tab._title) {
      return;
    }
    tab._title = normalized;
    notifyListeners();
  }

  TerminalPanelTab? _tabFor(String? id) {
    if (id == null) {
      return null;
    }
    for (final tab in _tabs) {
      if (tab.id == id) {
        return tab;
      }
    }
    return null;
  }

  void _syncSessionActivity() {
    for (final tab in _tabs) {
      final sessionId = tab.session.sessionId;
      if (sessionId == null) {
        continue;
      }
      runtime.setSessionActive(
        sessionId,
        active: _isOpen && tab.id == _activeTabId,
      );
    }
  }

  void _disposeTab(TerminalPanelTab tab) {
    tab._dispose();
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('TerminalPanelController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (disposeRuntime) {
      // Freeze product calls before releasing the tab-level capabilities so
      // the runtime's infrastructure settlement is the only PTY close owner.
      runtime.beginShutdown();
      runtime.dispose();
    }
    for (final tab in _tabs.toList(growable: false)) {
      _disposeTab(tab);
    }
    _tabs.clear();
    _activeTabId = null;
    super.dispose();
  }
}

@immutable
class TerminalBottomPanelStyle {
  const TerminalBottomPanelStyle({
    this.height = 288,
    this.headerHeight = 40,
    this.backgroundColor,
    this.headerColor,
    this.borderColor,
    this.activeTabColor,
    this.activeTabForegroundColor,
    this.inactiveTabForegroundColor,
    this.viewportColors,
    this.viewportPadding = const EdgeInsets.fromLTRB(10, 8, 10, 10),
    this.useFrameDefaultColors = true,
  });

  final double height;
  final double headerHeight;
  final Color? backgroundColor;
  final Color? headerColor;
  final Color? borderColor;
  final Color? activeTabColor;
  final Color? activeTabForegroundColor;
  final Color? inactiveTabForegroundColor;
  final TerminalViewportColors? viewportColors;
  final EdgeInsets viewportPadding;
  final bool useFrameDefaultColors;
}

class TerminalBottomPanel extends StatelessWidget {
  const TerminalBottomPanel({
    super.key,
    required this.controller,
    this.style = const TerminalBottomPanelStyle(),
    this.viewportBuilder,
    this.sessionBuilder,
  });

  final TerminalPanelController controller;
  final TerminalBottomPanelStyle style;
  final TerminalSessionViewportBuilder? viewportBuilder;
  final TerminalPanelSessionBuilder? sessionBuilder;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Offstage(
          offstage: !controller.isOpen,
          child: SizedBox(
            height: style.height,
            child: _TerminalPanelBody(
              controller: controller,
              style: style,
              viewportBuilder: viewportBuilder,
              sessionBuilder: sessionBuilder,
            ),
          ),
        );
      },
    );
  }
}

class TerminalPanelToggleButton extends StatelessWidget {
  const TerminalPanelToggleButton({
    super.key,
    required this.controller,
    this.openTooltip = 'Show terminal panel',
    this.closeTooltip = 'Hide terminal panel',
  });

  final TerminalPanelController controller;
  final String openTooltip;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final open = controller.isOpen;
        final scheme = Theme.of(context).colorScheme;
        return Semantics(
          button: true,
          selected: open,
          label: open ? closeTooltip : openTooltip,
          child: IconButton(
            key: const Key('terminal-panel-toggle'),
            tooltip: open ? closeTooltip : openTooltip,
            onPressed: controller.toggle,
            style: IconButton.styleFrom(
              backgroundColor: open ? scheme.secondaryContainer : null,
              foregroundColor: open
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant,
            ),
            icon: const Icon(Icons.terminal_rounded),
          ),
        );
      },
    );
  }
}

class _TerminalPanelBody extends StatelessWidget {
  const _TerminalPanelBody({
    required this.controller,
    required this.style,
    required this.viewportBuilder,
    required this.sessionBuilder,
  });

  final TerminalPanelController controller;
  final TerminalBottomPanelStyle style;
  final TerminalSessionViewportBuilder? viewportBuilder;
  final TerminalPanelSessionBuilder? sessionBuilder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = style.backgroundColor ?? scheme.surfaceContainerLowest;
    final header = style.headerColor ?? scheme.surfaceContainer;
    final border = style.borderColor ?? scheme.outlineVariant;
    final tabs = controller.tabs;
    final activeIndex = tabs.indexWhere(
      (tab) => tab.id == controller.activeTabId,
    );
    return Semantics(
      container: true,
      label: 'Terminal panel',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          border: Border(top: BorderSide(color: border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: style.headerHeight,
              child: ColoredBox(
                color: header,
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final tab in tabs)
                              _TerminalPanelTabButton(
                                tab: tab,
                                active: tab.id == controller.activeTabId,
                                activeColor: style.activeTabColor ?? background,
                                activeForeground:
                                    style.activeTabForegroundColor ??
                                    scheme.onSurface,
                                inactiveForeground:
                                    style.inactiveTabForegroundColor ??
                                    scheme.onSurfaceVariant,
                                borderColor: border,
                                onActivate: () =>
                                    controller.activateTab(tab.id),
                                onClose: () => controller.closeTab(tab.id),
                              ),
                            Tooltip(
                              message: 'New local terminal',
                              child: IconButton(
                                key: const Key('terminal-panel-add'),
                                onPressed: controller.addTerminal,
                                icon: const Icon(Icons.add_rounded),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    VerticalDivider(width: 1, thickness: 1, color: border),
                    Tooltip(
                      message: 'Hide terminal panel',
                      child: IconButton(
                        key: const Key('terminal-panel-close'),
                        onPressed: () => controller.setOpen(false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            Divider(height: 1, thickness: 1, color: border),
            Expanded(
              child: tabs.isEmpty || activeIndex < 0
                  ? _TerminalPanelEmpty(onAdd: controller.addTerminal)
                  : IndexedStack(
                      index: activeIndex,
                      children: [
                        for (final tab in tabs)
                          Builder(
                            key: ValueKey(tab.id),
                            builder: (context) {
                              final terminalView = TerminalSessionView(
                                session: tab.session,
                                contentPadding: style.viewportPadding,
                                colors: style.viewportColors,
                                useFrameDefaultColors:
                                    style.useFrameDefaultColors,
                                viewportBuilder: viewportBuilder,
                              );
                              return sessionBuilder?.call(
                                    context,
                                    tab,
                                    terminalView,
                                  ) ??
                                  terminalView;
                            },
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalPanelTabButton extends StatelessWidget {
  const _TerminalPanelTabButton({
    required this.tab,
    required this.active,
    required this.activeColor,
    required this.activeForeground,
    required this.inactiveForeground,
    required this.borderColor,
    required this.onActivate,
    required this.onClose,
  });

  final TerminalPanelTab tab;
  final bool active;
  final Color activeColor;
  final Color activeForeground;
  final Color inactiveForeground;
  final Color borderColor;
  final VoidCallback onActivate;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final foreground = active ? activeForeground : inactiveForeground;
    return Semantics(
      button: true,
      selected: active,
      label: '${tab.title}${tab.exited ? ', exited' : ''}',
      child: InkWell(
        key: Key('terminal-panel-tab-${tab.id}'),
        onTap: onActivate,
        child: Container(
          constraints: const BoxConstraints(minWidth: 104, maxWidth: 220),
          height: double.infinity,
          padding: const EdgeInsets.only(left: 12, right: 2),
          decoration: BoxDecoration(
            color: active ? activeColor : Colors.transparent,
            border: Border(
              right: BorderSide(color: borderColor),
              bottom: active
                  ? BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    )
                  : BorderSide.none,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                tab.exited
                    ? Icons.stop_circle_outlined
                    : Icons.terminal_rounded,
                size: 14,
                color: foreground,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  tab.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                key: Key('terminal-panel-tab-close-${tab.id}'),
                tooltip: 'Close ${tab.title}',
                onPressed: onClose,
                iconSize: 14,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded),
                color: foreground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalPanelEmpty extends StatelessWidget {
  const _TerminalPanelEmpty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: TextButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New local terminal'),
        style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
      ),
    );
  }
}
