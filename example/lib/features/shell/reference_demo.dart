import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences/app_preferences_models.dart';
import '../profiles/profile_models.dart';
import '../sessions/session_ports.dart';
import '../sessions/session_state.dart';
import '../terminal/terminal_painter_models.dart';

final referenceDemoModeProvider = Provider<bool>((ref) {
  return ref.watch(sessionDemoFixtureProvider) != null;
});

const referenceDemoActiveSessionId = 'demo-2';

const referenceDemoTabs = <TerminalTab>[
  TerminalTab(sessionId: 'demo-1', title: 'Shell', profileId: 'default'),
  TerminalTab(sessionId: 'demo-2', title: 'Shell', profileId: 'default'),
  TerminalTab(sessionId: 'demo-3', title: 'Shell', profileId: 'default'),
];

final TerminalFrameDiff referenceDemoPs1Frame = _buildReferenceDemoFrame(
  _referencePromptSegments,
);

final TerminalFrameDiff referenceDemoFrame = _buildReferenceDemoFrame(
  <_DemoSegment>[..._referencePromptSegments, ..._referenceCommandTailSegments],
);

final SessionDemoFixture referenceDemoFixture = SessionDemoFixture(
  profiles: <TerminalProfile>[defaultTerminalProfile()],
  tabs: referenceDemoTabs,
  activeSessionId: referenceDemoActiveSessionId,
  defaultProfileId: defaultTerminalProfile().id,
  themeMode: TerminalThemeMode.dark,
  frames: <String, TerminalFrameDiff>{
    for (final tab in referenceDemoTabs) tab.sessionId: referenceDemoFrame,
  },
);

TerminalFrameDiff _buildReferenceDemoFrame(List<_DemoSegment> segments) {
  final styleRuns = <TerminalStyleRun>[];
  final buffer = StringBuffer();
  var cursor = 0;

  for (final segment in segments) {
    buffer.write(segment.text);
    final nextCursor =
        cursor + TerminalTextCells.fromText(segment.text).cellCount;
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
    cursor: TerminalCursor(row: 0, col: cursor, visible: true),
    viewportRows: 24,
    viewportCols: 80,
    dirtyRanges: const [TerminalDirtyRange(start: 0, end: 1)],
    scrollbackOffset: 0,
    scrollbackMaxOffset: 0,
  );
}

const List<_DemoSegment> _referencePromptSegments = <_DemoSegment>[
  _DemoSegment(
    ' robinfai',
    foreground: Color(0xFF111827),
    background: Color(0xFFF08BB4),
    bold: true,
  ),
  _DemoSegment(
    '',
    foreground: Color(0xFFF6BC89),
    background: Color(0xFFF08BB4),
  ),
  _DemoSegment(
    ' ~ ',
    foreground: Color(0xFF111827),
    background: Color(0xFFF6BC89),
    bold: true,
  ),
  _DemoSegment(
    '',
    foreground: Color(0xFFE9E3A2),
    background: Color(0xFFF6BC89),
  ),
  _DemoSegment(
    '',
    foreground: Color(0xFFBDE8A0),
    background: Color(0xFFE9E3A2),
  ),
  _DemoSegment(
    '',
    foreground: Color(0xFF8FD3F4),
    background: Color(0xFFBDE8A0),
  ),
  _DemoSegment(
    '',
    foreground: Color(0xFF8DA7FF),
    background: Color(0xFF8FD3F4),
  ),
  _DemoSegment(
    '  19:23 ',
    foreground: Color(0xFF111827),
    background: Color(0xFFB7C1FF),
    bold: true,
  ),
  _DemoSegment('', foreground: Color(0xFFB7C1FF), background: null),
  _DemoSegment(
    ' ❯ ',
    foreground: Color(0xFFFFFFFF),
    background: null,
    bold: true,
  ),
];

const List<_DemoSegment> _referenceCommandTailSegments = <_DemoSegment>[
  _DemoSegment(
    'lsof',
    foreground: Color(0xFFFF6B6B),
    background: null,
    bold: true,
  ),
  _DemoSegment(
    ' -i:3306',
    foreground: Color(0xFFA5A5AF),
    background: null,
    bold: true,
  ),
];

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
