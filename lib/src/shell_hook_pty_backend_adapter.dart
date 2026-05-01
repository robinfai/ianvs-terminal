import 'dart:async';

import 'package:flutterm_pty/flutterm_pty.dart';

class ShellHookEvent {
  const ShellHookEvent({
    required this.sessionId,
    required this.hook,
    required this.payload,
  });

  final String sessionId;
  final String hook;
  final Map<String, Object?> payload;
}

class ShellHookPtyBackendAdapter
    implements PtySessionBackend, PtySessionDebugBackend {
  ShellHookPtyBackendAdapter._(this._delegate);

  final PtySessionBackend _delegate;
  final StreamController<ShellHookEvent> _shellHooks =
      StreamController<ShellHookEvent>.broadcast(sync: true);

  factory ShellHookPtyBackendAdapter.wrap(PtySessionBackend backend) {
    if (backend is ShellHookPtyBackendAdapter) {
      return backend;
    }
    return ShellHookPtyBackendAdapter._(backend);
  }

  Stream<ShellHookEvent> get shellHooks => _shellHooks.stream;

  @override
  int ping() => _delegate.ping();

  @override
  String createSession(String sessionConfigJson) {
    return _delegate.createSession(sessionConfigJson);
  }

  @override
  void closeSession(String sessionId) {
    _delegate.closeSession(sessionId);
  }

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
  }) {
    _delegate.resizeSession(
      sessionId,
      cols: cols,
      rows: rows,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
    );
  }

  @override
  void writeInput(String sessionId, List<int> bytes) {
    _delegate.writeInput(sessionId, bytes);
  }

  @override
  void scrollViewport(String sessionId, int deltaLines) {
    _delegate.scrollViewport(sessionId, deltaLines);
  }

  @override
  void scrollViewportTo(String sessionId, int offset) {
    _delegate.scrollViewportTo(sessionId, offset);
  }

  @override
  String? searchTextJson(String sessionId, String query) {
    return _delegate.searchTextJson(sessionId, query);
  }

  @override
  String? selectionText(String sessionId, String requestJson) {
    return _delegate.selectionText(sessionId, requestJson);
  }

  @override
  String? takeFrameDiffJson(String sessionId) {
    return _delegate.takeFrameDiffJson(sessionId);
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    final events = _delegate.pollEvents(sessionId);
    for (final event in events) {
      _emitShellHookIfPresent(event);
    }
    return events;
  }

  @override
  String? takeFrameDebugStatsJson(String sessionId) {
    return _delegate.takeFrameDebugStatsJson(sessionId);
  }

  @override
  String? takeSessionDebugStatsJson(String sessionId) {
    return _delegate.takeSessionDebugStatsJson(sessionId);
  }

  void dispose() {
    _shellHooks.close();
  }

  void _emitShellHookIfPresent(PtyEvent event) {
    if (event.kind != 'shell_hook' || _shellHooks.isClosed) {
      return;
    }
    final payload = event.payload;
    final hook = payload?['hook'];
    if (payload == null || hook is! String || hook.isEmpty) {
      return;
    }
    _shellHooks.add(
      ShellHookEvent(
        sessionId: event.sessionId,
        hook: hook,
        payload: Map<String, Object?>.from(payload),
      ),
    );
  }
}
