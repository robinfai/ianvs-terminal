import 'package:ianvs_pty/ianvs_pty.dart';

enum TerminalAsyncEventKind {
  resize,
  clipboardCopy,
  clipboardPasteRequest,
  clipboardMimeWrite,
  clipboardMimeReadRequest,
  clipboardMimeError,
}

enum TerminalImmediateEventKind {
  bell,
  shellHook,
  shellContext,
  shellCommand,
  shellUserVar,
  sessionAnnotation,
  sessionNotification,
  sessionProgress,
  sessionBadge,
  sessionTabStatus,
  terminalContext,
  dragDropCommand,
  fileDownload,
  fileDownloadFailed,
  fileUploadDenied,
  zmodem,
  zmodemDeferredWriteFailure,
  cellSizeReportRequest,
  clearCapturedOutput,
  reportVariableRequest,
  openUrlRequest,
  attentionRequest,
  sessionReset,
}

sealed class TerminalEventRoute {
  const TerminalEventRoute();
}

final class TerminalExitEventRoute extends TerminalEventRoute {
  const TerminalExitEventRoute({required this.exitCode});

  final int? exitCode;
}

final class TerminalAsyncEventRoute extends TerminalEventRoute {
  const TerminalAsyncEventRoute({
    required this.kind,
    this.payload,
    this.hostRequest,
  });

  final TerminalAsyncEventKind kind;
  final Map<String, Object?>? payload;
  final PtyHostRequestV1? hostRequest;
}

final class TerminalImmediateEventRoute extends TerminalEventRoute {
  const TerminalImmediateEventRoute({required this.kind, this.payload});

  final TerminalImmediateEventKind kind;
  final Map<String, Object?>? payload;
}

final class TerminalIgnoredEventRoute extends TerminalEventRoute {
  const TerminalIgnoredEventRoute();
}

final class TerminalRuntimeEventGapRoute extends TerminalEventRoute {
  const TerminalRuntimeEventGapRoute(this.diagnostic);

  final PtyRuntimeEventGapDiagnostic diagnostic;
}

final class TerminalEventRouter {
  const TerminalEventRouter();

  TerminalEventRoute route(PtyEvent event) {
    if (event is PtyRuntimeEventGapDiagnostic) {
      return TerminalRuntimeEventGapRoute(event);
    }
    return switch (event.kind) {
      'exit' => TerminalExitEventRoute(
        exitCode: _wholeIntValue(event.payload?['code']),
      ),
      'resize' => TerminalAsyncEventRoute(
        kind: TerminalAsyncEventKind.resize,
        payload: event.payload,
      ),
      'clipboard_copy' => TerminalAsyncEventRoute(
        kind: TerminalAsyncEventKind.clipboardCopy,
        payload: event.payload,
      ),
      'clipboard_paste_request' => TerminalAsyncEventRoute(
        kind: TerminalAsyncEventKind.clipboardPasteRequest,
        payload: event.payload,
        hostRequest: event.hostRequest,
      ),
      'clipboard_mime_write' => TerminalAsyncEventRoute(
        kind: TerminalAsyncEventKind.clipboardMimeWrite,
        payload: event.payload,
      ),
      'clipboard_mime_read_request' => TerminalAsyncEventRoute(
        kind: TerminalAsyncEventKind.clipboardMimeReadRequest,
        payload: event.payload,
      ),
      'clipboard_mime_error' => TerminalAsyncEventRoute(
        kind: TerminalAsyncEventKind.clipboardMimeError,
        payload: event.payload,
      ),
      'bell' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.bell,
        payload: event.payload,
      ),
      'shell_hook' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.shellHook,
        payload: event.payload,
      ),
      'shell_context' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.shellContext,
        payload: event.payload,
      ),
      'shell_command' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.shellCommand,
        payload: event.payload,
      ),
      'shell_user_var' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.shellUserVar,
        payload: event.payload,
      ),
      'session_annotation' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.sessionAnnotation,
        payload: event.payload,
      ),
      'session_notification' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.sessionNotification,
        payload: event.payload,
      ),
      'session_progress' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.sessionProgress,
        payload: event.payload,
      ),
      'session_badge' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.sessionBadge,
        payload: event.payload,
      ),
      'session_tab_status' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.sessionTabStatus,
        payload: event.payload,
      ),
      'terminal_context' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.terminalContext,
        payload: event.payload,
      ),
      'drag_drop_command' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.dragDropCommand,
        payload: event.payload,
      ),
      'file_download' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.fileDownload,
        payload: event.payload,
      ),
      'file_download_failed' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.fileDownloadFailed,
        payload: event.payload,
      ),
      'file_upload_denied' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.fileUploadDenied,
        payload: event.payload,
      ),
      'zmodem_detected' ||
      'zmodem_file_offer' ||
      'zmodem_started' ||
      'zmodem_progress' ||
      'zmodem_file_completed' ||
      'zmodem_file_skipped' ||
      'zmodem_completed' ||
      'zmodem_failed' ||
      'zmodem_cancelled' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.zmodem,
        payload: <String, Object?>{...?event.payload, 'eventKind': event.kind},
      ),
      'zmodem_deferred_write_failed' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.zmodemDeferredWriteFailure,
        payload: event.payload,
      ),
      'cell_size_report_request' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.cellSizeReportRequest,
        payload: event.payload,
      ),
      'clear_captured_output' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.clearCapturedOutput,
        payload: event.payload,
      ),
      'report_variable_request' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.reportVariableRequest,
        payload: event.payload,
      ),
      'open_url_request' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.openUrlRequest,
        payload: event.payload,
      ),
      'attention_request' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.attentionRequest,
        payload: event.payload,
      ),
      'session_reset' => TerminalImmediateEventRoute(
        kind: TerminalImmediateEventKind.sessionReset,
        payload: event.payload,
      ),
      _ => const TerminalIgnoredEventRoute(),
    };
  }
}

int? _wholeIntValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite) {
    final parsed = value.toInt();
    if (value == parsed) {
      return parsed;
    }
  }
  return null;
}
