import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sessions/session_state.dart';
import '../terminal/terminal_painter_models.dart';

final referenceDemoModeProvider = Provider<bool>((ref) => false);

const referenceDemoActiveSessionId = 'demo-2';

const referenceDemoTabs = <TerminalTab>[
  TerminalTab(sessionId: 'demo-1', title: 'Shell', profileId: 'default'),
  TerminalTab(sessionId: 'demo-2', title: 'Shell', profileId: 'default'),
  TerminalTab(sessionId: 'demo-3', title: 'Shell', profileId: 'default'),
];

final TerminalFrameDiff referenceDemoFrame = _buildReferenceDemoFrame();

TerminalFrameDiff _buildReferenceDemoFrame() {
  final segments = <_DemoSegment>[
    const _DemoSegment(
      ' robinfai',
      foreground: Color(0xFF111827),
      background: Color(0xFFF08BB4),
      bold: true,
    ),
    const _DemoSegment(
      '',
      foreground: Color(0xFFF6BC89),
      background: Color(0xFFF08BB4),
    ),
    const _DemoSegment(
      ' ~ ',
      foreground: Color(0xFF111827),
      background: Color(0xFFF6BC89),
      bold: true,
    ),
    const _DemoSegment(
      '',
      foreground: Color(0xFFE9E3A2),
      background: Color(0xFFF6BC89),
    ),
    const _DemoSegment(
      '',
      foreground: Color(0xFFBDE8A0),
      background: Color(0xFFE9E3A2),
    ),
    const _DemoSegment(
      '',
      foreground: Color(0xFF8FD3F4),
      background: Color(0xFFBDE8A0),
    ),
    const _DemoSegment(
      '',
      foreground: Color(0xFF8DA7FF),
      background: Color(0xFF8FD3F4),
    ),
    const _DemoSegment(
      '  19:23 ',
      foreground: Color(0xFF111827),
      background: Color(0xFFB7C1FF),
      bold: true,
    ),
    const _DemoSegment('', foreground: Color(0xFFB7C1FF), background: null),
    const _DemoSegment(
      ' ❯ ',
      foreground: Color(0xFFFFFFFF),
      background: null,
      bold: true,
    ),
    const _DemoSegment(
      'lsof',
      foreground: Color(0xFFFF6B6B),
      background: null,
      bold: true,
    ),
    const _DemoSegment(
      ' -i:3306',
      foreground: Color(0xFFA5A5AF),
      background: null,
      bold: true,
    ),
  ];

  final styleRuns = <TerminalStyleRun>[];
  final buffer = StringBuffer();
  var cursor = 0;

  for (final segment in segments) {
    buffer.write(segment.text);
    final nextCursor = cursor + segment.text.length;
    styleRuns.add(
      TerminalStyleRun(
        start: cursor,
        end: nextCursor,
        foreground: segment.foreground,
        background: segment.background,
        bold: segment.bold,
      ),
    );
    cursor = nextCursor;
  }

  return TerminalFrameDiff(
    rows: [
      TerminalRow(index: 0, text: buffer.toString(), styleRuns: styleRuns),
    ],
    cursor: TerminalCursor(row: 0, col: buffer.length, visible: true),
    viewportRows: 24,
    viewportCols: 80,
    dirtyRanges: const [TerminalDirtyRange(start: 0, end: 1)],
    scrollbackOffset: 0,
    scrollbackMaxOffset: 0,
  );
}

class _DemoSegment {
  const _DemoSegment(
    this.text, {
    required this.foreground,
    required this.background,
    this.bold = false,
  });

  final String text;
  final Color? foreground;
  final Color? background;
  final bool bold;
}
