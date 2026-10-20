import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../../features/sessions/session_state.dart';
import '../../features/shell/widgets/desktop_session_status.dart';
import '../app_ui.dart';

@Preview(
  name: 'Evidence reader · Light',
  group: 'Desktop',
  size: Size(1200, 760),
)
Widget desktopEvidenceLightPreview() => const DesktopEvidencePreview();

@Preview(
  name: 'Evidence reader · Dark',
  group: 'Desktop',
  size: Size(1200, 760),
)
Widget desktopEvidenceDarkPreview() =>
    const DesktopEvidencePreview(brightness: Brightness.dark);

@Preview(
  name: 'Evidence reader · High contrast',
  group: 'Desktop',
  size: Size(1200, 760),
)
Widget desktopEvidenceContrastPreview() => const DesktopEvidencePreview(
  brightness: Brightness.dark,
  highContrast: true,
);

@Preview(name: 'Evidence reader · 2×', group: 'Desktop', size: Size(360, 640))
Widget desktopEvidenceNarrowPreview() =>
    const DesktopEvidencePreview(textScale: 2);

/// Real reader and footer with paginated, in-memory output from a closed pane.
/// No PTY, platform channel, file, network or model connection is created.
class DesktopEvidencePreview extends StatefulWidget {
  const DesktopEvidencePreview({
    super.key,
    this.brightness = Brightness.light,
    this.textScale = 1,
    this.highContrast = false,
    this.theme,
  });

  final Brightness brightness;
  final double textScale;
  final bool highContrast;
  final ThemeData? theme;

  @override
  State<DesktopEvidencePreview> createState() => _DesktopEvidencePreviewState();
}

class _DesktopEvidencePreviewState extends State<DesktopEvidencePreview> {
  static const pane = TerminalPane(
    sessionId: 'preview-source',
    title: 'Build log · preview',
    profileId: 'preview',
    isExited: true,
    exitCode: 0,
    shellIntegration: TerminalShellIntegrationSnapshot(
      hostname: 'preview.example',
      username: 'reviewer',
      currentDirectory: '/workspace/example',
      contextId: 'preview-node',
    ),
  );

  final reader = CommandBlockReaderHostController();
  late final blocks = CommandBlockController(request: _request)..refresh();
  bool initialOpen = true;

  Map<String, Object?> _request(Map<String, Object?> request) {
    final offset = request['offset'] as int? ?? 0;
    final limit = request['limit'] as int? ?? 20;
    final end = (offset + limit).clamp(0, 240);
    final block = <String, Object?>{
      'id': 'preview-build',
      'command': 'flutter test',
      'cwd': '/workspace/example',
      'exitCode': 0,
      'running': false,
      'columns': 80,
      'totalLines': 240,
      'matchingLines': 240,
      'offset': offset,
      'nextOffset': end < 240 ? end : null,
      'lines': [
        for (var i = offset; i < end; i++)
          {
            'index': i,
            'source_row': i,
            'text': i == 239
                ? 'All tests passed! · 示例输出'
                : 'Test ${i + 1}: retained original output · 保留来源',
            'wrapped': false,
          },
      ],
    };
    return request['id'] == null
        ? {
            'blocks': [block],
          }
        : {'block': block};
  }

  void _open(BuildContext context) {
    unawaited(
      showCommandBlockReader(
        context,
        controller: blocks,
        id: 'preview-build',
        font: const TerminalFontConfig(family: 'monospace'),
        initialRow: 120,
      ),
    );
  }

  @override
  void dispose() {
    blocks.dispose();
    reader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme:
        widget.theme ??
        buildIanvsTerminalTheme(
          widget.brightness,
          platform: TargetPlatform.macOS,
          highContrast: widget.highContrast,
        ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(widget.textScale),
        highContrast: widget.highContrast,
      ),
      child: child!,
    ),
    home: Scaffold(
      body: Column(
        children: [
          Expanded(
            child: CommandBlockReaderHost(
              controller: reader,
              sourceLabel: pane.title,
              sourceDetails: 'preview-source / preview-node',
              child: Builder(
                builder: (context) {
                  if (initialOpen) {
                    initialOpen = false;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _open(context);
                    });
                  }
                  return Center(
                    child: TextButton.icon(
                      key: const Key('desktop-preview-open-reader'),
                      onPressed: () => _open(context),
                      icon: const Icon(Icons.article_outlined),
                      label: const Text('Read retained build output'),
                    ),
                  );
                },
              ),
            ),
          ),
          DesktopSessionStatus(
            sessionId: pane.sessionId,
            pane: pane,
            composer: null,
            ai: null,
            aiVisible: false,
            observing: false,
            readOnly: true,
            replaying: false,
            reader: reader,
            onDetails: null,
          ),
        ],
      ),
    ),
  );
}
