import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../terminal/terminal.dart';

import '../preferences/app_preferences_models.dart';
import '../profiles/profile_models.dart';
import 'session_state.dart';

typedef SessionClipboardCopy = Future<void> Function(String text);
typedef SessionClipboardTextWrite =
    Future<void> Function(String text, String selection);
typedef SessionClipboardPaste = Future<String> Function();
typedef SessionClipboardMimeWrite = TerminalClipboardMimeWriter;
typedef SessionClipboardMimeRead = TerminalClipboardMimeReader;
typedef SessionClipboardMimeTypeList = TerminalClipboardMimeTypeLister;
typedef SessionWindowTitleWriter = Future<void> Function(String title);
typedef SessionTerminalContentPublisher =
    void Function({
      required bool terminalHasVisibleContent,
      required String? terminalPreview,
    });

class SessionDemoFixture {
  const SessionDemoFixture({
    required this.profiles,
    required this.tabs,
    required this.activeSessionId,
    required this.defaultProfileId,
    required this.themeMode,
    required this.frames,
  });

  final List<TerminalProfile> profiles;
  final List<TerminalTab> tabs;
  final String? activeSessionId;
  final String? defaultProfileId;
  final TerminalThemeMode themeMode;
  final Map<String, TerminalFrameDiff> frames;

  TerminalFrameDiff? frameFor(String sessionId) {
    final activeSessionId = this.activeSessionId;
    return frames[sessionId] ??
        (activeSessionId == null ? null : frames[activeSessionId]) ??
        (frames.isEmpty ? null : frames.values.first);
  }
}

final sessionClipboardCopyProvider = Provider<SessionClipboardCopy>((ref) {
  return (_) async {};
});

final sessionClipboardPasteProvider = Provider<SessionClipboardPaste>((ref) {
  return () async => '';
});

final sessionClipboardTextWriteProvider = Provider<SessionClipboardTextWrite>((
  ref,
) {
  return (text, selection) => ref.read(sessionClipboardCopyProvider)(text);
});

final sessionClipboardMimeWriteProvider = Provider<SessionClipboardMimeWrite?>(
  (ref) => null,
);
final sessionClipboardMimeReadProvider = Provider<SessionClipboardMimeRead?>(
  (ref) => null,
);
final sessionClipboardMimeTypeListProvider =
    Provider<SessionClipboardMimeTypeList?>((ref) => null);

final sessionWindowResizeProvider = Provider<TerminalWindowResizeCallback?>(
  (ref) => null,
);

final sessionWindowTitleWriterProvider = Provider<SessionWindowTitleWriter>((
  ref,
) {
  return (_) async {};
});

final sessionTerminalContentPublisherProvider =
    Provider<SessionTerminalContentPublisher>((ref) {
      return ({
        required terminalHasVisibleContent,
        required terminalPreview,
      }) {};
    });

final sessionDemoFixtureProvider = Provider<SessionDemoFixture?>((ref) => null);
