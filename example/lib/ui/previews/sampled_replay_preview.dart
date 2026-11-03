import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../features/recording/sampled_replay_surface.dart';
import '../app_ui.dart';

@Preview(
  name: 'Sampled replay · Light',
  group: 'Recording',
  size: Size(1100, 740),
)
Widget sampledReplayLightPreview() => _preview(Brightness.light);

@Preview(
  name: 'Sampled replay · Dark',
  group: 'Recording',
  size: Size(1100, 740),
)
Widget sampledReplayDarkPreview() => _preview(Brightness.dark);

@Preview(
  name: 'Sampled replay · Compact · 2× text',
  group: 'Recording',
  size: Size(390, 700),
  textScaleFactor: 2,
)
Widget sampledReplayCompactPreview() => _preview(Brightness.light);

Widget _preview(Brightness brightness) => MaterialApp(
  theme: buildIanvsTerminalTheme(brightness, platform: TargetPlatform.macOS),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SampledReplaySurface(
      title: '部署回顾 · app.example',
      viewport: const Center(
        child: SelectableText(
          r'$ printf "ready\n"'
          '\nready',
        ),
      ),
      position: const Duration(minutes: 3),
      duration: const Duration(hours: 27),
      playing: false,
      loading: false,
      interrupted: true,
      speed: 1,
      timelineLoading: false,
      commands: const [
        SampledReplayCommand(
          label: 'git status --short',
          detail: '退出状态 0 · app.example · /srv/app',
          offset: Duration(minutes: 3),
        ),
      ],
      onToggle: () {},
      onSeek: (_) {},
      onSpeed: (_) {},
      onCopy: () {},
      onClose: () {},
      onFirstPage: () {},
      onNextPage: () {},
    ),
  ),
);
