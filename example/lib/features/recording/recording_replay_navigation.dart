import 'package:ianvs_terminal/ianvs_terminal.dart';

/// Frame navigation follows visible output, not sparse semantic/activity marks.
/// The initial frame remains reachable even in a one-event recording.
List<Duration> recordingReplayNavigationOffsets(TerminalRecording recording) {
  final offsets = <Duration>{
    Duration.zero,
    for (final event in recording.events)
      if (event.kind == TerminalRecordingEventKind.ptyOutput ||
          event.kind == TerminalRecordingEventKind.resize ||
          event.kind == TerminalRecordingEventKind.sessionExited)
        event.monotonicOffset,
  }.toList()..sort();
  return List.unmodifiable(offsets);
}
