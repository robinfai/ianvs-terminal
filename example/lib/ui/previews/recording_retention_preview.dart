import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../features/recording/recording_retention_policy.dart';
import '../../features/recording/recording_retention_surface.dart';
import '../app_ui.dart';

@Preview(
  name: 'Recording retention · Light',
  group: 'Recording',
  size: Size(1100, 740),
)
Widget recordingRetentionLightPreview() => _preview(Brightness.light);

@Preview(
  name: 'Recording retention · Dark',
  group: 'Recording',
  size: Size(1100, 740),
)
Widget recordingRetentionDarkPreview() => _preview(Brightness.dark);

@Preview(
  name: 'Recording retention · Compact · 2× text',
  group: 'Recording',
  size: Size(390, 700),
  textScaleFactor: 2,
)
Widget recordingRetentionCompactPreview() => _preview(Brightness.light);

Widget _preview(Brightness brightness) => MaterialApp(
  theme: buildIanvsTerminalTheme(brightness, platform: TargetPlatform.macOS),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: RecordingRetentionSurface(
      policy: RecordingRetentionPolicy(
        maximumAgeDays: 30,
        maximumBytes: 20 * 1024 * 1024 * 1024,
      ),
      usedBytes: 3 * 1024 * 1024 * 1024,
      loading: false,
      saving: false,
      onSave: (_) {},
      onClose: () {},
      onRetry: () {},
    ),
  ),
);
