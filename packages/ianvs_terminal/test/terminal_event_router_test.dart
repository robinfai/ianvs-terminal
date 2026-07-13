import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/src/runtime/terminal_event_router.dart';

void main() {
  group('TerminalEventRouter', () {
    const router = TerminalEventRouter();

    test('routes exit events with a whole numeric exit code', () {
      final route = router.route(
        const PtyEvent(
          kind: 'exit',
          sessionId: 'session-a',
          payload: <String, Object?>{'code': 7.0},
        ),
      );

      expect(route, isA<TerminalExitEventRoute>());
      expect((route as TerminalExitEventRoute).exitCode, 7);

      final malformed = router.route(
        const PtyEvent(
          kind: 'exit',
          sessionId: 'session-a',
          payload: <String, Object?>{'code': 7.5},
        ),
      );

      expect((malformed as TerminalExitEventRoute).exitCode, isNull);
    });

    test('routes side-effecting events as async work', () {
      expect(
        router.route(const PtyEvent(kind: 'resize', sessionId: 'session-a')),
        isA<TerminalAsyncEventRoute>().having(
          (route) => route.kind,
          'kind',
          TerminalAsyncEventKind.resize,
        ),
      );
      expect(
        router.route(
          const PtyEvent(kind: 'clipboard_copy', sessionId: 'session-a'),
        ),
        isA<TerminalAsyncEventRoute>().having(
          (route) => route.kind,
          'kind',
          TerminalAsyncEventKind.clipboardCopy,
        ),
      );
      expect(
        router.route(
          const PtyEvent(
            kind: 'clipboard_paste_request',
            sessionId: 'session-a',
          ),
        ),
        isA<TerminalAsyncEventRoute>().having(
          (route) => route.kind,
          'kind',
          TerminalAsyncEventKind.clipboardPasteRequest,
        ),
      );
    });

    test('routes passive session events for immediate emission', () {
      final cases = <String, TerminalImmediateEventKind>{
        'bell': TerminalImmediateEventKind.bell,
        'shell_hook': TerminalImmediateEventKind.shellHook,
        'shell_context': TerminalImmediateEventKind.shellContext,
        'shell_command': TerminalImmediateEventKind.shellCommand,
        'shell_user_var': TerminalImmediateEventKind.shellUserVar,
        'session_annotation': TerminalImmediateEventKind.sessionAnnotation,
        'session_notification': TerminalImmediateEventKind.sessionNotification,
        'session_progress': TerminalImmediateEventKind.sessionProgress,
        'session_badge': TerminalImmediateEventKind.sessionBadge,
        'session_tab_status': TerminalImmediateEventKind.sessionTabStatus,
        'drag_drop_command': TerminalImmediateEventKind.dragDropCommand,
        'file_download': TerminalImmediateEventKind.fileDownload,
        'file_download_failed': TerminalImmediateEventKind.fileDownloadFailed,
        'file_upload_denied': TerminalImmediateEventKind.fileUploadDenied,
        'cell_size_report_request':
            TerminalImmediateEventKind.cellSizeReportRequest,
        'open_url_request': TerminalImmediateEventKind.openUrlRequest,
        'attention_request': TerminalImmediateEventKind.attentionRequest,
        'session_reset': TerminalImmediateEventKind.sessionReset,
      };

      for (final entry in cases.entries) {
        final route = router.route(
          PtyEvent(
            kind: entry.key,
            sessionId: 'session-a',
            payload: const <String, Object?>{'value': 'payload'},
          ),
        );

        expect(route, isA<TerminalImmediateEventRoute>());
        final immediate = route as TerminalImmediateEventRoute;
        expect(immediate.kind, entry.value);
        expect(immediate.payload, <String, Object?>{'value': 'payload'});
      }
    });

    test('ignores unknown events', () {
      expect(
        router.route(const PtyEvent(kind: 'started', sessionId: 'session-a')),
        isA<TerminalIgnoredEventRoute>(),
      );
    });
  });
}
