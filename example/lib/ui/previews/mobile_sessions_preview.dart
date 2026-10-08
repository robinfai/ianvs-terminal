import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../features/sessions/session_state.dart';
import '../../features/shell/widgets/mobile_disconnected_session_notice.dart';
import '../../features/shell/widgets/mobile_session_list.dart';
import '../app_ui.dart';

@Preview(name: 'Sessions · Light · 中文', group: 'Sessions', size: Size(390, 844))
Widget mobileSessionsLightPreview() => _preview(
  brightness: Brightness.light,
  locale: const Locale('zh'),
  child: const _SessionListPreview(),
);

@Preview(
  name: 'Sessions · Dark · English',
  group: 'Sessions',
  size: Size(390, 844),
)
Widget mobileSessionsDarkPreview() => _preview(
  brightness: Brightness.dark,
  locale: const Locale('en'),
  child: const _SessionListPreview(),
);

@Preview(
  name: 'Sessions · 320 px · English',
  group: 'Sessions',
  size: Size(320, 700),
)
Widget mobileSessionsNarrowEnglishPreview() => _preview(
  brightness: Brightness.light,
  locale: const Locale('en'),
  child: const _SessionListPreview(),
);

@Preview(
  name: 'Sessions · 320 px · 中文',
  group: 'Sessions',
  size: Size(320, 700),
)
Widget mobileSessionsNarrowChinesePreview() => _preview(
  brightness: Brightness.dark,
  locale: const Locale('zh'),
  child: const _SessionListPreview(),
);

@Preview(
  name: 'Disconnected notice · 320 px · English',
  group: 'Sessions',
  size: Size(320, 360),
)
Widget mobileDisconnectedNoticePreview() => _preview(
  brightness: Brightness.light,
  locale: const Locale('en'),
  child: const _NoticePreview(),
);

@Preview(
  name: 'Reconnected notice · 320 px · 中文',
  group: 'Sessions',
  size: Size(320, 360),
)
Widget mobileReconnectedNoticePreview() => _preview(
  brightness: Brightness.dark,
  locale: const Locale('zh'),
  child: const _NoticePreview(reconnected: true),
);

@Preview(
  name: 'Disconnected notice · Landscape',
  group: 'Sessions',
  size: Size(844, 160),
)
Widget mobileDisconnectedNoticeLandscapePreview() => _preview(
  brightness: Brightness.dark,
  locale: const Locale('en'),
  child: const _NoticePreview(compact: true),
);

Widget _preview({
  required Brightness brightness,
  required Locale locale,
  required Widget child,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildIanvsTerminalTheme(brightness, platform: TargetPlatform.iOS),
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
    child: child!,
  ),
  home: Scaffold(body: SafeArea(child: child)),
);

/// Interactive snapshots only; no provider, credentials, network or PTY.
class _SessionListPreview extends StatefulWidget {
  const _SessionListPreview();

  @override
  State<_SessionListPreview> createState() => _SessionListPreviewState();
}

class _SessionListPreviewState extends State<_SessionListPreview> {
  var _panes = <TerminalPane>[
    _pane('production', 'Production · 生产环境', 'production.example.com'),
    _pane(
      'previous',
      'Previous connection · 上一次连接',
      'production.example.com',
      exited: true,
    ),
    _pane('audit', 'AI evidence · 任务原始输出', 'audit.example.com', exited: true),
  ];
  final _reconnections = <String, String>{'previous': 'production'};
  String? _selected = 'production';
  var _nextId = 0;

  void _remove(TerminalPane pane) {
    setState(() {
      _panes.removeWhere((candidate) => candidate.sessionId == pane.sessionId);
      _reconnections.removeWhere(
        (source, target) =>
            source == pane.sessionId || target == pane.sessionId,
      );
      if (_selected == pane.sessionId) _selected = null;
    });
  }

  void _reconnect(TerminalPane pane) {
    setState(() {
      final current = _reconnections[pane.sessionId];
      if (current != null) {
        _selected = current;
        return;
      }
      final id = 'reconnected-${_nextId++}';
      _panes.add(
        TerminalPane(
          sessionId: id,
          title: pane.title,
          profileId: pane.profileId,
          shellIntegration: pane.shellIntegration,
        ),
      );
      _reconnections[pane.sessionId] = id;
      _selected = id;
    });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.all(context.appTheme.spacing.lg),
    child: MobileSessionList(
      tabs: [
        for (final pane in _panes)
          TerminalTab(
            sessionId: pane.sessionId,
            title: pane.title,
            profileId: pane.profileId,
            panes: [pane],
          ),
      ],
      activeSessionId: _selected,
      liveReconnections: _reconnections,
      protectedSessionIds: const {'audit'},
      onSelect: (pane) => setState(() => _selected = pane.sessionId),
      onReconnect: _reconnect,
      onDisconnect: _remove,
      onRemove: _remove,
      onClearDisconnected: () => setState(() {
        _panes = _panes
            .where((pane) => !pane.isExited || pane.sessionId == 'audit')
            .toList();
        final remaining = _panes.map((pane) => pane.sessionId).toSet();
        _reconnections.removeWhere((source, _) => !remaining.contains(source));
        if (!remaining.contains(_selected)) _selected = null;
      }),
    ),
  );
}

TerminalPane _pane(
  String id,
  String title,
  String host, {
  bool exited = false,
}) => TerminalPane(
  sessionId: id,
  title: title,
  profileId: 'preview-$id',
  isExited: exited,
  exitCode: exited ? 255 : null,
  shellIntegration: TerminalShellIntegrationSnapshot(
    connectionChain: [
      ShellConnectionHop(
        kind: ShellConnectionHopKind.sshShell,
        host: host,
        user: 'deploy',
        port: 2222,
      ),
    ],
  ),
);

class _NoticePreview extends StatefulWidget {
  const _NoticePreview({this.reconnected = false, this.compact = false});

  final bool reconnected;
  final bool compact;

  @override
  State<_NoticePreview> createState() => _NoticePreviewState();
}

class _NoticePreviewState extends State<_NoticePreview> {
  late bool _reconnected = widget.reconnected;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: MobileDisconnectedSessionNotice(
      sessionId: 'preview-history',
      reconnected: _reconnected,
      compact: widget.compact,
      exitCode: 255,
      onReconnect: () => setState(() => _reconnected = !_reconnected),
    ),
  );
}
