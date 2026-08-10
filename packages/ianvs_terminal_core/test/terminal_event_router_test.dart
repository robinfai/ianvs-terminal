import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';
import 'package:ianvs_terminal_core/src/runtime/terminal_event_router.dart';

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
        'ssh_auth_prompt': TerminalImmediateEventKind.sshAuthPrompt,
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
        'clear_captured_output': TerminalImmediateEventKind.clearCapturedOutput,
        'report_variable_request':
            TerminalImmediateEventKind.reportVariableRequest,
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

    test('routes typed Runtime Event gap diagnostics', () {
      final diagnostic = PtyRuntimeEventGapDiagnostic(
        sessionId: 'session-a',
        expectedSequence: 4,
        nextSequence: 7,
        droppedCount: 2,
        survivingEventCount: 1,
      );

      final route = router.route(diagnostic);

      expect(route, isA<TerminalRuntimeEventGapRoute>());
      expect(
        (route as TerminalRuntimeEventGapRoute).diagnostic,
        same(diagnostic),
      );
    });

    test('routes every ZMODEM event with its native kind preserved', () {
      for (final kind in const <String>[
        'zmodem_detected',
        'zmodem_file_offer',
        'zmodem_started',
        'zmodem_progress',
        'zmodem_file_completed',
        'zmodem_file_skipped',
        'zmodem_completed',
        'zmodem_failed',
        'zmodem_cancelled',
      ]) {
        final route = router.route(
          PtyEvent(
            kind: kind,
            sessionId: 'session-a',
            payload: const <String, Object?>{'source': 'zmodem'},
          ),
        );

        expect(route, isA<TerminalImmediateEventRoute>());
        final immediate = route as TerminalImmediateEventRoute;
        expect(immediate.kind, TerminalImmediateEventKind.zmodem);
        expect(immediate.payload, <String, Object?>{
          'source': 'zmodem',
          'eventKind': kind,
        });
      }
    });

    test('routes deferred ZMODEM write failures outside transfer events', () {
      final route = router.route(
        const PtyEvent(
          kind: 'zmodem_deferred_write_failed',
          sessionId: 'session-a',
          payload: <String, Object?>{
            'source': 'zmodem',
            'reason': 'io_error',
            'queuedChunks': 2,
            'queuedBytes': 8,
            'completedChunks': 1,
            'completedBytes': 3,
          },
        ),
      );

      expect(route, isA<TerminalImmediateEventRoute>());
      final immediate = route as TerminalImmediateEventRoute;
      expect(
        immediate.kind,
        TerminalImmediateEventKind.zmodemDeferredWriteFailure,
      );
      expect(immediate.kind, isNot(TerminalImmediateEventKind.zmodem));
    });
  });
}
