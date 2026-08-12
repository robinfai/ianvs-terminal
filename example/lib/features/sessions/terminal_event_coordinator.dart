import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

typedef TerminalBusinessEffectSink =
    TerminalUiEffectContext? Function(TerminalBusinessEffect effect);
typedef TerminalPreCloseClaimSink =
    TerminalSessionPreCloseOutcome Function(TerminalSessionExitClaim claim);
typedef TerminalUiEffectSink = void Function(TerminalUiEffect effect);

/// Exact identity of one runtime-exit pre-close claim.
///
/// The claim is created synchronously before the native session mapping is
/// released and is joined to the later ordered exit signal. Its epoch prevents
/// a reused backend session id from inheriting work from an older incarnation.
final class TerminalSessionExitClaim {
  const TerminalSessionExitClaim({
    required this.claimId,
    required this.sessionId,
    required this.sessionEpoch,
    required this.exitCode,
  });

  final int claimId;
  final String sessionId;
  final int sessionEpoch;
  final int? exitCode;
}

/// Normalized business input delivered to the session reducer.
///
/// The reducer always receives this effect before the matching UI effect.
final class TerminalBusinessEffect {
  const TerminalBusinessEffect({required this.signal, this.exitClaim});

  final TerminalRuntimeSignal signal;
  final TerminalSessionExitClaim? exitClaim;
}

sealed class TerminalUiEffectContext {
  const TerminalUiEffectContext();
}

/// Last presentation identity captured by the reducer before exit removes the
/// session from durable feature state.
final class TerminalSessionExitUiContext extends TerminalUiEffectContext {
  const TerminalSessionExitUiContext({
    required this.title,
    required this.paneIndex,
    required this.paneCount,
  });

  final String title;
  final int paneIndex;
  final int paneCount;
}

/// Presentation-only effect emitted after the business reducer has observed
/// the same runtime signal.
sealed class TerminalUiEffect {
  const TerminalUiEffect({
    required this.signal,
    required this.attachmentGeneration,
  });

  final TerminalRuntimeSignal signal;
  final int attachmentGeneration;

  int get sequence => signal.sequence;
  int get sessionEpoch => signal.sessionEpoch;
  String get sessionId => signal.sessionId;
}

final class TerminalSessionUiEffect extends TerminalUiEffect {
  const TerminalSessionUiEffect({
    required TerminalRuntimeSessionEventSignal signal,
    required super.attachmentGeneration,
    this.context,
  }) : super(signal: signal);

  @override
  TerminalRuntimeSessionEventSignal get signal =>
      super.signal as TerminalRuntimeSessionEventSignal;

  TerminalSessionEvent get event => signal.payload;
  final TerminalUiEffectContext? context;

  TerminalSessionExitUiContext? get exitContext =>
      context is TerminalSessionExitUiContext
      ? context! as TerminalSessionExitUiContext
      : null;
}

final class TerminalZmodemUiEffect extends TerminalUiEffect {
  const TerminalZmodemUiEffect({
    required TerminalRuntimeZmodemEventSignal signal,
    required super.attachmentGeneration,
  }) : super(signal: signal);

  @override
  TerminalRuntimeZmodemEventSignal get signal =>
      super.signal as TerminalRuntimeZmodemEventSignal;

  TerminalSessionZmodemEvent get event => signal.payload;
}

final class TerminalZmodemDeferredFailureUiEffect extends TerminalUiEffect {
  const TerminalZmodemDeferredFailureUiEffect({
    required TerminalRuntimeZmodemDeferredFailureSignal signal,
    required super.attachmentGeneration,
  }) : super(signal: signal);

  @override
  TerminalRuntimeZmodemDeferredFailureSignal get signal =>
      super.signal as TerminalRuntimeZmodemDeferredFailureSignal;

  TerminalSessionZmodemDeferredWriteFailedDiagnostic get diagnostic =>
      signal.payload;
}

final class TerminalEventSinkAttachment {
  TerminalEventSinkAttachment._(this._detach);

  final void Function() _detach;
  bool _isDetached = false;

  bool get isDetached => _isDetached;

  void detach() {
    if (_isDetached) {
      return;
    }
    _isDetached = true;
    _detach();
  }
}

/// Narrow synchronous relay used to break the runtime/coordinator provider
/// construction cycle. It owns no subscription and never buffers a pre-close
/// signal: the feature reducer must already be attached before sessions start.
final class TerminalPreCloseSignalRelay {
  TerminalSessionPreCloseOutcome Function(TerminalSessionPreCloseSignal signal)?
  _sink;
  int _generation = 0;

  TerminalEventSinkAttachment attach(
    TerminalSessionPreCloseOutcome Function(
      TerminalSessionPreCloseSignal signal,
    )
    sink,
  ) {
    _generation += 1;
    final generation = _generation;
    _sink = sink;
    return TerminalEventSinkAttachment._(() {
      if (_generation == generation) {
        _sink = null;
      }
    });
  }

  TerminalSessionPreCloseOutcome add(TerminalSessionPreCloseSignal signal) {
    final sink = _sink;
    if (sink == null) {
      return TerminalSessionPreCloseOutcome.retryableFailure(
        error: StateError('Terminal pre-close owner is unavailable.'),
        stackTrace: StackTrace.current,
      );
    }
    return sink(signal);
  }
}

/// Feature-owned boundary between terminal transport signals, session state,
/// and transient Shell presentation.
///
/// Exactly one subscription is made to the controller-wide ordered signal
/// stream. Legacy streams remain public compatibility APIs, but application
/// features do not subscribe to them independently.
final class TerminalEventCoordinatorOverflowException implements Exception {
  const TerminalEventCoordinatorOverflowException({
    required this.pendingSignalLimit,
    required this.rejectedSequence,
  });

  final int pendingSignalLimit;
  final int rejectedSequence;

  @override
  String toString() =>
      'TerminalEventCoordinatorOverflowException('
      'limit: $pendingSignalLimit, rejected sequence: $rejectedSequence)';
}

final class TerminalEventCoordinator {
  TerminalEventCoordinator({
    required Stream<TerminalRuntimeSignal> signals,
    this.pendingSignalLimit = 1024,
  }) {
    if (pendingSignalLimit <= 0) {
      throw ArgumentError.value(
        pendingSignalLimit,
        'pendingSignalLimit',
        'Must be positive.',
      );
    }
    _runtimeSubscription = signals.listen(_handleSignal);
  }

  final int pendingSignalLimit;
  late final StreamSubscription<TerminalRuntimeSignal> _runtimeSubscription;
  final Queue<TerminalRuntimeSignal> _pendingSignals =
      Queue<TerminalRuntimeSignal>();
  final Map<String, int> _currentSessionEpochs = <String, int>{};
  final Map<({String sessionId, int sessionEpoch}), TerminalSessionExitClaim>
  _exitClaims =
      <({String sessionId, int sessionEpoch}), TerminalSessionExitClaim>{};
  final Set<int> _approvedExitClaimIds = <int>{};

  TerminalBusinessEffectSink? _businessSink;
  TerminalPreCloseClaimSink? _preCloseSink;
  TerminalUiEffectSink? _uiSink;
  int _businessAttachmentGeneration = 0;
  int _uiAttachmentGeneration = 0;
  int _claimSeed = 0;
  int _lastSequence = 0;
  bool _acceptingEffects = true;
  bool _isDraining = false;
  bool _isAwaitingUiEffect = false;
  Future<void>? _closeFuture;
  TerminalEventCoordinatorOverflowException? _failure;

  bool get isShuttingDown => !_acceptingEffects;

  @visibleForTesting
  bool get hasRuntimeSubscriptionForTesting => _closeFuture == null;

  @visibleForTesting
  int get lastReducedSequenceForTesting => _lastSequence;

  @visibleForTesting
  int get pendingExitClaimCountForTesting => _exitClaims.length;

  @visibleForTesting
  int get pendingSignalCountForTesting => _pendingSignals.length;

  TerminalEventCoordinatorOverflowException? get failure => _failure;

  TerminalEventSinkAttachment attachBusinessSink({
    required TerminalBusinessEffectSink onEffect,
    required TerminalPreCloseClaimSink onPreClose,
  }) {
    if (!_acceptingEffects) {
      final failure = _failure;
      if (failure != null) {
        throw failure;
      }
      throw StateError('Terminal event coordinator is shutting down.');
    }
    _businessAttachmentGeneration += 1;
    final generation = _businessAttachmentGeneration;
    _businessSink = onEffect;
    _preCloseSink = onPreClose;
    _drainPendingSignals();
    return TerminalEventSinkAttachment._(() {
      if (_businessAttachmentGeneration == generation) {
        _businessSink = null;
        _preCloseSink = null;
      }
    });
  }

  TerminalEventSinkAttachment attachUiSink(TerminalUiEffectSink sink) {
    if (!_acceptingEffects) {
      final failure = _failure;
      if (failure != null) {
        throw failure;
      }
      throw StateError('Terminal event coordinator is shutting down.');
    }
    _uiAttachmentGeneration += 1;
    final generation = _uiAttachmentGeneration;
    _uiSink = sink;
    return TerminalEventSinkAttachment._(() {
      if (_uiAttachmentGeneration == generation) {
        _uiSink = null;
      }
    });
  }

  /// Claims pre-close work synchronously and at most once per session epoch.
  TerminalSessionPreCloseOutcome handlePreClose(
    TerminalSessionPreCloseSignal signal,
  ) {
    final sink = _preCloseSink;
    if (!_acceptingEffects || sink == null) {
      return TerminalSessionPreCloseOutcome.retryableFailure(
        error:
            _failure ??
            StateError('Terminal business pre-close owner is unavailable.'),
        stackTrace: StackTrace.current,
      );
    }
    if (!_acceptEpoch(signal.sessionId, signal.sessionEpoch)) {
      return TerminalSessionPreCloseOutcome.retryableFailure(
        error: StateError('Terminal pre-close signal used a stale epoch.'),
        stackTrace: StackTrace.current,
      );
    }
    final key = (
      sessionId: signal.sessionId,
      sessionEpoch: signal.sessionEpoch,
    );
    final existing = _exitClaims[key];
    if (existing != null) {
      if (_approvedExitClaimIds.contains(existing.claimId)) {
        return const TerminalSessionPreCloseOutcome.allowClose();
      }
      final outcome = sink(existing);
      if (outcome.permitsClose) {
        _approvedExitClaimIds.add(existing.claimId);
      }
      return outcome;
    }
    _claimSeed += 1;
    final claim = TerminalSessionExitClaim(
      claimId: _claimSeed,
      sessionId: signal.sessionId,
      sessionEpoch: signal.sessionEpoch,
      exitCode: signal.exitCode,
    );
    _exitClaims[key] = claim;
    final outcome = sink(claim);
    if (outcome.permitsClose) {
      _approvedExitClaimIds.add(claim.claimId);
    }
    return outcome;
  }

  bool isCurrentUiEffect(TerminalUiEffect effect) {
    return _acceptingEffects &&
        effect.attachmentGeneration == _uiAttachmentGeneration &&
        _currentSessionEpochs[effect.sessionId] == effect.sessionEpoch;
  }

  Future<void> beginShutdown() {
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }
    _acceptingEffects = false;
    _businessAttachmentGeneration += 1;
    _uiAttachmentGeneration += 1;
    _businessSink = null;
    _preCloseSink = null;
    _uiSink = null;
    _pendingSignals.clear();
    _exitClaims.clear();
    _approvedExitClaimIds.clear();
    _currentSessionEpochs.clear();
    return _closeFuture = _runtimeSubscription.cancel();
  }

  void _handleSignal(TerminalRuntimeSignal signal) {
    if (!_acceptingEffects) {
      return;
    }
    if (_pendingSignals.length >= pendingSignalLimit) {
      _failOverflow(signal.sequence);
      return;
    }
    _pendingSignals.addLast(signal);
    _drainPendingSignals();
  }

  void _drainPendingSignals() {
    if (_isDraining || _isAwaitingUiEffect || !_acceptingEffects) {
      return;
    }
    _isDraining = true;
    try {
      while (_acceptingEffects &&
          _businessSink != null &&
          _pendingSignals.isNotEmpty) {
        final signal = _pendingSignals.removeFirst();
        if (signal.sequence <= _lastSequence ||
            !_acceptEpoch(signal.sessionId, signal.sessionEpoch)) {
          continue;
        }
        _lastSequence = signal.sequence;
        final TerminalSessionExitClaim? exitClaim;
        if (signal case TerminalRuntimeSessionEventSignal(
          payload: TerminalSessionExitEvent(),
        )) {
          exitClaim = _exitClaims.remove((
            sessionId: signal.sessionId,
            sessionEpoch: signal.sessionEpoch,
          ));
          if (exitClaim != null) {
            _approvedExitClaimIds.remove(exitClaim.claimId);
          }
        } else {
          exitClaim = null;
        }
        final uiContext = _businessSink!(
          TerminalBusinessEffect(signal: signal, exitClaim: exitClaim),
        );
        if (!_acceptingEffects) {
          return;
        }
        final sink = _uiSink;
        if (sink == null) {
          continue;
        }
        final generation = _uiAttachmentGeneration;
        final effect = switch (signal) {
          TerminalRuntimeSessionEventSignal() => TerminalSessionUiEffect(
            signal: signal,
            attachmentGeneration: generation,
            context: uiContext,
          ),
          TerminalRuntimeZmodemEventSignal() => TerminalZmodemUiEffect(
            signal: signal,
            attachmentGeneration: generation,
          ),
          TerminalRuntimeZmodemDeferredFailureSignal() =>
            TerminalZmodemDeferredFailureUiEffect(
              signal: signal,
              attachmentGeneration: generation,
            ),
        };
        if (_uiSink == sink &&
            generation == _uiAttachmentGeneration &&
            _currentSessionEpochs[effect.sessionId] == effect.sessionEpoch) {
          _isAwaitingUiEffect = true;
          scheduleMicrotask(() {
            try {
              if (_acceptingEffects &&
                  _uiSink == sink &&
                  generation == _uiAttachmentGeneration &&
                  _currentSessionEpochs[effect.sessionId] ==
                      effect.sessionEpoch) {
                sink(effect);
              }
            } finally {
              _isAwaitingUiEffect = false;
              _drainPendingSignals();
            }
          });
          return;
        }
      }
    } finally {
      _isDraining = false;
    }
  }

  void _failOverflow(int rejectedSequence) {
    _failure = TerminalEventCoordinatorOverflowException(
      pendingSignalLimit: pendingSignalLimit,
      rejectedSequence: rejectedSequence,
    );
    _acceptingEffects = false;
    _businessAttachmentGeneration += 1;
    _uiAttachmentGeneration += 1;
    _businessSink = null;
    _preCloseSink = null;
    _uiSink = null;
    _pendingSignals.clear();
    _exitClaims.clear();
    _approvedExitClaimIds.clear();
    _currentSessionEpochs.clear();
    _closeFuture ??= _runtimeSubscription.cancel();
  }

  bool _acceptEpoch(String sessionId, int sessionEpoch) {
    final current = _currentSessionEpochs[sessionId];
    if (current != null && sessionEpoch < current) {
      return false;
    }
    if (current == null || sessionEpoch > current) {
      _currentSessionEpochs[sessionId] = sessionEpoch;
      final staleClaimIds = _exitClaims.entries
          .where(
            (entry) =>
                entry.key.sessionId == sessionId &&
                entry.key.sessionEpoch < sessionEpoch,
          )
          .map((entry) => entry.value.claimId)
          .toList(growable: false);
      _exitClaims.removeWhere(
        (key, _) =>
            key.sessionId == sessionId && key.sessionEpoch < sessionEpoch,
      );
      _approvedExitClaimIds.removeAll(staleClaimIds);
    }
    return true;
  }
}
