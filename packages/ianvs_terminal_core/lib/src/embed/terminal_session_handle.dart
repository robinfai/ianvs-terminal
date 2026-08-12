import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Size;

import '../config/terminal_config.dart';
import '../runtime/terminal_runtime_controller.dart';
import '../terminal/terminal_models.dart';
import '../terminal/terminal_viewport.dart';

const Duration _terminalSessionDisposeRetryInterval = Duration(
  milliseconds: 50,
);

/// A narrow owner for one current terminal runtime session.
///
/// The handle deliberately exposes the controller's ordered
/// [TerminalRuntimeSignal] envelope instead of recreating the predecessor
/// facade's split callback and stream APIs.
final class TerminalSessionHandle {
  TerminalSessionHandle({
    required this.runtime,
    required this.sessionConfig,
    this.disposeRuntime = false,
  });

  final TerminalRuntimeController runtime;
  final TerminalSessionConfig sessionConfig;
  final bool disposeRuntime;

  String? _sessionId;
  int? _sessionEpoch;
  Timer? _disposeRetryTimer;
  bool _disposeRequested = false;
  bool _disposed = false;

  String? get sessionId => _sessionId;
  int? get sessionEpoch => _sessionEpoch;
  bool get isOpen {
    final id = _sessionId;
    return id != null && runtime.hasSession(id);
  }

  bool get disposed => _disposed;

  TerminalViewportController get viewportController =>
      runtime.viewportFor(_requireOpenSessionId());

  TerminalFrameDiff get frame {
    final id = _sessionId;
    return id == null
        ? TerminalFrameDiff.empty
        : runtime.existingViewportFor(id)?.frame ?? TerminalFrameDiff.empty;
  }

  /// Ordered current signals for the concrete session incarnation opened by
  /// this handle. A reused backend session ID cannot enter this stream.
  Stream<TerminalRuntimeSignal> get runtimeSignals {
    final id = _requireOpenSessionId();
    final epoch = _sessionEpoch!;
    return runtime.runtimeSignals.where(
      (signal) => signal.sessionId == id && signal.sessionEpoch == epoch,
    );
  }

  bool ownsSignal(TerminalRuntimeSignal signal) {
    return signal.sessionId == _sessionId &&
        signal.sessionEpoch == _sessionEpoch;
  }

  void open() {
    _ensureNotDisposed();
    if (isOpen) {
      return;
    }
    if (_sessionId != null) {
      throw StateError('The terminal session has already exited.');
    }
    final id = runtime.createSession(sessionConfig);
    final epoch = runtime.sessionEpochFor(id);
    if (epoch == null) {
      runtime.disposeSession(id);
      throw StateError('The terminal runtime did not assign a session epoch.');
    }
    _sessionId = id;
    _sessionEpoch = epoch;
  }

  void setActive({required bool active}) {
    final id = _sessionId;
    if (id != null) {
      runtime.setSessionActive(id, active: active);
    }
  }

  void setFocused({required bool focused}) {
    final id = _sessionId;
    if (id != null) {
      runtime.setSessionFocused(id, focused: focused);
    }
  }

  void writeBytes(List<int> bytes) {
    runtime.sendInput(_requireOpenSessionId(), Uint8List.fromList(bytes));
  }

  void resize(Size viewportSize, double devicePixelRatio) {
    runtime.resizeSession(
      _requireOpenSessionId(),
      viewportSize,
      devicePixelRatio,
    );
  }

  void scrollLines(int amount) {
    runtime.scrollViewport(_requireOpenSessionId(), amount);
  }

  void scrollToLine(int offset) {
    runtime.scrollViewportTo(_requireOpenSessionId(), offset);
  }

  bool setBlockFolded(String id, {required bool folded}) {
    return runtime.setBlockFolded(_requireOpenSessionId(), id, folded: folded);
  }

  bool setBlockRendered(String id, {required bool rendered}) {
    return runtime.setBlockRendered(
      _requireOpenSessionId(),
      id,
      rendered: rendered,
    );
  }

  TerminalInlineButtonActivation activateItermButton(int id) {
    return runtime.activateItermButton(_requireOpenSessionId(), id);
  }

  bool tryClose() {
    _ensureNotDisposed();
    final id = _sessionId;
    if (id == null) {
      return true;
    }
    if (!runtime.tryCloseSession(id)) {
      return false;
    }
    _sessionId = null;
    _sessionEpoch = null;
    return true;
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposeRequested = true;
    _tryCompleteDispose();
  }

  void _tryCompleteDispose() {
    if (!_disposeRequested || _disposed) {
      return;
    }
    if (disposeRuntime && !runtime.shutdownHasStarted && !runtime.disposed) {
      runtime.beginShutdown();
      runtime.dispose();
    }
    if (runtime.shutdownHasStarted || runtime.disposed) {
      // A process-level shutdown coordinator owns an externally supplied
      // runtime once product work is frozen. Releasing this handle locally
      // must not spin on disposeSession(), which intentionally rejects all
      // product calls after beginShutdown(). A handle-owned runtime starts the
      // same infrastructure settlement before the local capability is dropped.
      _completeLocalDispose(disposeOwnedRuntime: disposeRuntime);
      return;
    }
    final id = _sessionId;
    if (id != null && !runtime.disposeSession(id)) {
      _disposeRetryTimer ??= Timer(_terminalSessionDisposeRetryInterval, () {
        _disposeRetryTimer = null;
        _tryCompleteDispose();
      });
      return;
    }
    _completeLocalDispose(disposeOwnedRuntime: disposeRuntime);
  }

  void _completeLocalDispose({required bool disposeOwnedRuntime}) {
    _sessionId = null;
    _sessionEpoch = null;
    _disposeRetryTimer?.cancel();
    _disposeRetryTimer = null;
    _disposeRequested = false;
    _disposed = true;
    if (disposeOwnedRuntime) {
      runtime.dispose();
    }
  }

  String _requireOpenSessionId() {
    _ensureNotDisposed();
    final id = _sessionId;
    if (id == null || !runtime.hasSession(id)) {
      throw StateError('TerminalSessionHandle.open() must be called first.');
    }
    return id;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('TerminalSessionHandle has been disposed.');
    }
  }
}
