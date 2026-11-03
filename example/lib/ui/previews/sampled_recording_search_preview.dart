import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../features/recording/sampled_recording_search_models.dart';
import '../../features/recording/sampled_recording_search_surface.dart';
import '../app_ui.dart';

@Preview(
  name: 'Search recordings · Light',
  group: 'Recording',
  size: Size(1100, 740),
)
Widget recordingSearchLightPreview() => _preview(Brightness.light);

@Preview(
  name: 'Search recordings · Dark',
  group: 'Recording',
  size: Size(1100, 740),
)
Widget recordingSearchDarkPreview() => _preview(Brightness.dark);

@Preview(
  name: 'Search recordings · Compact · 2× text',
  group: 'Recording',
  size: Size(390, 700),
  textScaleFactor: 2,
)
Widget recordingSearchCompactPreview() => _preview(Brightness.light);

Widget _preview(Brightness brightness) => MaterialApp(
  theme: buildIanvsTerminalTheme(brightness, platform: TargetPlatform.macOS),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: RecordingSearchSurface(
      results: [
        RecordingSearchResult(
          path: '/recordings/example.trailrec',
          title: '部署回顾',
          createdAtUtc: DateTime.utc(2026, 9, 27),
          offset: const Duration(minutes: 3),
          scope: RecordingSearchScope.command,
          preview: 'git status --short',
          hostname: 'app.example',
        ),
      ],
      loading: false,
      hasCriteria: true,
      pageNumber: 1,
      scannedFiles: 3,
      totalFiles: 3,
      skippedFiles: 0,
      onQuery: (_) {},
      onSelect: (_) {},
      onClose: () {},
      onRetry: () {},
      onNext: () {},
    ),
  ),
);
