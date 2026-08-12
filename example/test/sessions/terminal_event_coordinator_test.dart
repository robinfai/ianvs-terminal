import 'dart:async';

import 'package:app/features/sessions/terminal_event_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../support/fake_pty_backend.dart';

void main() {
  test(
    'single runtime subscription reduces exit before UI and survives UI reattach',
    () async {
      final backend = FakePtyBackend();
      late final TerminalEventCoordinator coordinator;
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
        beforeSessionCloseOnExitSignal: (signal) {
          return coordinator.handlePreClose(signal);
        },
      );
      final countedSignals = _CountingStream(runtime.runtimeSignals);
      coordinator = TerminalEventCoordinator(signals: countedSignals);

      final order = <String>[];
      TerminalSessionExitClaim? claim;
      coordinator.attachBusinessSink(
        onEffect: (effect) {
          final signal = effect.signal;
          if (signal is TerminalRuntimeSessionEventSignal) {
            order.add('business:${signal.payload.runtimeType}');
            if (signal.payload is TerminalSessionExitEvent) {
              claim = effect.exitClaim;
              return const TerminalSessionExitUiContext(
                title: 'Build',
                paneIndex: 1,
                paneCount: 2,
              );
            }
          }
          return null;
        },
        onPreClose: (value) {
          order.add('pre-close');
          return const TerminalSessionPreCloseOutcome.allowClose();
        },
      );
      final firstUiEffects = <TerminalUiEffect>[];
      final initialEffect = Completer<void>();
      final exitEffect = Completer<void>();
      final firstAttachment = coordinator.attachUiSink((effect) {
        firstUiEffects.add(effect);
        order.add('ui:${effect.runtimeType}');
        if (!initialEffect.isCompleted) {
          initialEffect.complete();
        }
        if (effect is TerminalSessionUiEffect &&
            effect.event is TerminalSessionExitEvent &&
            !exitEffect.isCompleted) {
          exitEffect.complete();
        }
      });

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await initialEffect.future;
      order.clear();
      firstUiEffects.clear();
      final sessionEpoch = runtime.sessionEpochFor(sessionId)!;
      final preCloseSignal = TerminalSessionPreCloseSignal(
        sessionId: sessionId,
        sessionEpoch: sessionEpoch,
        exitCode: 7,
      );
      coordinator
        ..handlePreClose(preCloseSignal)
        ..handlePreClose(preCloseSignal);
      backend
        ..clearFrame(sessionId)
        ..enqueueEvent(
          sessionId,
          PtyEvent(
            kind: 'exit',
            sessionId: sessionId,
            payload: const <String, Object?>{'code': 7},
          ),
        );

      runtime.refreshSession(sessionId);
      await exitEffect.future;

      expect(countedSignals.listenCount, 1);
      expect(claim, isNotNull);
      expect(order.first, 'pre-close');
      expect(order.where((entry) => entry == 'pre-close'), hasLength(1));
      expect(
        (firstUiEffects.single as TerminalSessionUiEffect).exitContext?.title,
        'Build',
      );
      expect(
        order.indexWhere((entry) => entry.startsWith('business:')),
        lessThan(order.indexWhere((entry) => entry.startsWith('ui:'))),
      );

      firstAttachment.detach();
      final secondUiEffects = <TerminalUiEffect>[];
      final reattachedBell = Completer<void>();
      coordinator.attachUiSink((effect) {
        secondUiEffects.add(effect);
        if (effect is TerminalSessionUiEffect &&
            effect.event is TerminalSessionBellEvent &&
            !reattachedBell.isCompleted) {
          reattachedBell.complete();
        }
      });
      expect(coordinator.isCurrentUiEffect(firstUiEffects.single), isFalse);
      final reattachedSessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/zsh'),
        ),
      );
      backend
        ..clearFrame(reattachedSessionId)
        ..enqueueEvent(
          reattachedSessionId,
          PtyEvent(kind: 'bell', sessionId: reattachedSessionId),
        );
      runtime.refreshSession(reattachedSessionId);
      await reattachedBell.future;

      expect(firstUiEffects, hasLength(1));
      expect(
        secondUiEffects
            .whereType<TerminalSessionUiEffect>()
            .where((effect) => effect.event is TerminalSessionBellEvent)
            .single
            .event,
        isA<TerminalSessionBellEvent>(),
      );
      expect(countedSignals.listenCount, 1);
      await coordinator.beginShutdown();
      expect(countedSignals.cancelCount, 1);
      expect(runtime.tryDispose(), isTrue);
    },
  );

  test(
    'session epoch reuse invalidates old effects and shutdown drops all UI',
    () async {
      final backend = FakePtyBackend()..forcedSessionId = 'reused';
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      final countedSignals = _CountingStream(runtime.runtimeSignals);
      final coordinator = TerminalEventCoordinator(signals: countedSignals);
      coordinator.attachBusinessSink(
        onEffect: (_) => null,
        onPreClose: (_) => const TerminalSessionPreCloseOutcome.allowClose(),
      );
      final uiEffects = <TerminalUiEffect>[];
      var awaitedBellEpoch = 0;
      var bellEffect = Completer<TerminalUiEffect>();
      coordinator.attachUiSink((effect) {
        uiEffects.add(effect);
        if (effect is TerminalSessionUiEffect &&
            effect.event is TerminalSessionBellEvent &&
            effect.sessionEpoch > awaitedBellEpoch &&
            !bellEffect.isCompleted) {
          bellEffect.complete(effect);
        }
      });

      final oldSessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      backend.clearFrame(oldSessionId);
      uiEffects.clear();
      backend.enqueueEvent(
        oldSessionId,
        PtyEvent(kind: 'bell', sessionId: oldSessionId),
      );
      runtime.refreshSession(oldSessionId);
      final oldEffect = await bellEffect.future;
      awaitedBellEpoch = oldEffect.sessionEpoch;
      bellEffect = Completer<TerminalUiEffect>();

      runtime.closeSession(oldSessionId);
      final newSessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/zsh'),
        ),
      );
      expect(newSessionId, oldSessionId);
      backend.clearFrame(newSessionId);
      backend.enqueueEvent(
        newSessionId,
        PtyEvent(kind: 'bell', sessionId: newSessionId),
      );
      runtime.refreshSession(newSessionId);
      final newEffect = await bellEffect.future;

      expect(newEffect.sessionEpoch, greaterThan(oldEffect.sessionEpoch));
      expect(coordinator.isCurrentUiEffect(oldEffect), isFalse);
      expect(coordinator.isCurrentUiEffect(newEffect), isTrue);

      await coordinator.beginShutdown();
      final uiCountAtShutdown = uiEffects.length;
      backend.enqueueEvent(
        newSessionId,
        PtyEvent(kind: 'bell', sessionId: newSessionId),
      );
      runtime.refreshSession(newSessionId);

      expect(uiEffects, hasLength(uiCountAtShutdown));
      expect(countedSignals.listenCount, 1);
      expect(countedSignals.cancelCount, 1);
      expect(runtime.tryDispose(), isTrue);
    },
  );

  test(
    'missing business and pre-close owners fail closed without progress',
    () async {
      final backend = FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      final coordinator = TerminalEventCoordinator(
        signals: runtime.runtimeSignals,
      );
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      expect(coordinator.lastReducedSequenceForTesting, 0);
      final signal = TerminalSessionPreCloseSignal(
        sessionId: sessionId,
        sessionEpoch: runtime.sessionEpochFor(sessionId)!,
        exitCode: 1,
      );
      expect(coordinator.handlePreClose(signal).permitsClose, isFalse);
      expect(coordinator.pendingExitClaimCountForTesting, 0);
      expect(TerminalPreCloseSignalRelay().add(signal).permitsClose, isFalse);

      var preCloseCalls = 0;
      coordinator.attachBusinessSink(
        onEffect: (_) => null,
        onPreClose: (_) {
          preCloseCalls += 1;
          return const TerminalSessionPreCloseOutcome.allowClose();
        },
      );
      expect(coordinator.handlePreClose(signal).permitsClose, isTrue);
      expect(coordinator.pendingExitClaimCountForTesting, 1);
      expect(preCloseCalls, 1);

      await coordinator.beginShutdown();
      expect(runtime.tryDispose(), isTrue);
    },
  );

  test(
    'buffers a bounded business-sink gap and drains each signal once',
    () async {
      final backend = FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      final coordinator = TerminalEventCoordinator(
        signals: runtime.runtimeSignals,
      );
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      backend
        ..clearFrame(sessionId)
        ..enqueueEvent(sessionId, PtyEvent(kind: 'bell', sessionId: sessionId));
      runtime.refreshSession(sessionId);

      expect(coordinator.lastReducedSequenceForTesting, 0);
      expect(coordinator.pendingSignalCountForTesting, greaterThanOrEqualTo(2));
      final expectedSignalCount = coordinator.pendingSignalCountForTesting;
      final businessSequences = <int>[];
      final uiSequences = <int>[];
      final drained = Completer<void>();
      coordinator.attachUiSink((effect) {
        uiSequences.add(effect.sequence);
        if (uiSequences.length == expectedSignalCount && !drained.isCompleted) {
          drained.complete();
        }
      });
      coordinator.attachBusinessSink(
        onEffect: (effect) {
          businessSequences.add(effect.signal.sequence);
          return null;
        },
        onPreClose: (_) => const TerminalSessionPreCloseOutcome.allowClose(),
      );
      await drained.future;

      expect(businessSequences, orderedEquals(uiSequences));
      expect(businessSequences.toSet(), hasLength(businessSequences.length));
      expect(coordinator.pendingSignalCountForTesting, 0);
      await coordinator.beginShutdown();
      expect(runtime.tryDispose(), isTrue);
    },
  );

  test(
    'signal drain preserves reducer and UI total order across exit',
    () async {
      final backend = FakePtyBackend();
      late final TerminalEventCoordinator coordinator;
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
        beforeSessionCloseOnExitSignal: (signal) =>
            coordinator.handlePreClose(signal),
      );
      coordinator = TerminalEventCoordinator(signals: runtime.runtimeSignals);
      final order = <String>[];
      final exitUi = Completer<void>();
      coordinator.attachBusinessSink(
        onEffect: (effect) {
          if (effect.signal case TerminalRuntimeSessionEventSignal(
            :final payload,
          )) {
            order.add('B:${payload.runtimeType}');
          }
          return null;
        },
        onPreClose: (_) => const TerminalSessionPreCloseOutcome.allowClose(),
      );
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      coordinator.attachUiSink((effect) {
        if (effect case TerminalSessionUiEffect(:final event)) {
          order.add('U:${event.runtimeType}');
          if (event is TerminalSessionExitEvent && !exitUi.isCompleted) {
            exitUi.complete();
          }
        }
      });
      order.clear();
      backend
        ..setFrame(sessionId, <String, Object?>{
          'rows': <Object?>[
            <String, Object?>{'index': 0, 'text': 'final frame'},
          ],
          'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
          'viewport_rows': 24,
          'viewport_cols': 80,
          'dirty_ranges': <Object?>[
            <String, Object?>{'start': 0, 'end': 1},
          ],
        })
        ..enqueueEvent(
          sessionId,
          PtyEvent(
            kind: 'exit',
            sessionId: sessionId,
            payload: const <String, Object?>{'code': 0},
          ),
        );
      runtime.refreshSession(sessionId);
      await exitUi.future;

      expect(order, <String>[
        'B:TerminalSessionFrameEvent',
        'U:TerminalSessionFrameEvent',
        'B:TerminalSessionExitEvent',
        'U:TerminalSessionExitEvent',
      ]);
      await coordinator.beginShutdown();
      expect(runtime.tryDispose(), isTrue);
    },
  );

  test(
    'UI-triggered nested runtime signal is queued after its source effect',
    () async {
      final backend = FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      final coordinator = TerminalEventCoordinator(
        signals: runtime.runtimeSignals,
      );
      final order = <String>[];
      coordinator.attachBusinessSink(
        onEffect: (effect) {
          if (effect.signal case TerminalRuntimeSessionEventSignal(
            payload: TerminalSessionBellEvent(),
          )) {
            order.add('B${effect.signal.sequence}');
          }
          return null;
        },
        onPreClose: (_) => const TerminalSessionPreCloseOutcome.allowClose(),
      );
      final nestedUi = Completer<void>();
      var bellUiCount = 0;
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      coordinator.attachUiSink((effect) {
        if (effect case TerminalSessionUiEffect(
          event: TerminalSessionBellEvent(),
        )) {
          bellUiCount += 1;
          order.add('U${effect.sequence}');
          if (bellUiCount == 1) {
            backend.enqueueEvent(
              sessionId,
              PtyEvent(kind: 'bell', sessionId: sessionId),
            );
            runtime.refreshSession(sessionId);
          } else if (!nestedUi.isCompleted) {
            nestedUi.complete();
          }
        }
      });
      order.clear();
      backend
        ..clearFrame(sessionId)
        ..enqueueEvent(sessionId, PtyEvent(kind: 'bell', sessionId: sessionId));
      runtime.refreshSession(sessionId);
      await nestedUi.future;

      final firstSequence = int.parse(order[0].substring(1));
      final nestedSequence = int.parse(order[2].substring(1));
      expect(order, <String>[
        'B$firstSequence',
        'U$firstSequence',
        'B$nestedSequence',
        'U$nestedSequence',
      ]);
      expect(nestedSequence, greaterThan(firstSequence));
      await coordinator.beginShutdown();
      expect(runtime.tryDispose(), isTrue);
    },
  );

  test(
    'bounded sink-gap overflow is typed and permanently fail-closed',
    () async {
      final backend = FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: backend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      final coordinator = TerminalEventCoordinator(
        signals: runtime.runtimeSignals,
        pendingSignalLimit: 1,
      );
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      backend
        ..clearFrame(sessionId)
        ..enqueueEvent(sessionId, PtyEvent(kind: 'bell', sessionId: sessionId));
      runtime.refreshSession(sessionId);

      final failure = coordinator.failure;
      expect(failure, isA<TerminalEventCoordinatorOverflowException>());
      expect(coordinator.pendingSignalCountForTesting, 0);
      expect(
        coordinator
            .handlePreClose(
              TerminalSessionPreCloseSignal(
                sessionId: sessionId,
                sessionEpoch: runtime.sessionEpochFor(sessionId)!,
                exitCode: 1,
              ),
            )
            .error,
        same(failure),
      );
      expect(
        () => coordinator.attachBusinessSink(
          onEffect: (_) => null,
          onPreClose: (_) => const TerminalSessionPreCloseOutcome.allowClose(),
        ),
        throwsA(same(failure)),
      );
      await coordinator.beginShutdown();
      expect(runtime.tryDispose(), isTrue);
    },
  );
}

final class _CountingStream<T> extends Stream<T> {
  _CountingStream(this._delegate);

  final Stream<T> _delegate;
  int listenCount = 0;
  int cancelCount = 0;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    listenCount += 1;
    // The returned wrapper owns and forwards cancellation to this delegate.
    // ignore: cancel_subscriptions
    final delegateSubscription = _delegate.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    return _CountingSubscription<T>(delegateSubscription, () {
      cancelCount += 1;
    });
  }
}

final class _CountingSubscription<T> implements StreamSubscription<T> {
  _CountingSubscription(this._delegate, this._onCancel);

  final StreamSubscription<T> _delegate;
  final void Function() _onCancel;
  bool _cancelled = false;

  @override
  Future<void> cancel() {
    if (!_cancelled) {
      _cancelled = true;
      _onCancel();
    }
    return _delegate.cancel();
  }

  @override
  void onData(void Function(T data)? handleData) =>
      _delegate.onData(handleData);

  @override
  void onError(Function? handleError) => _delegate.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _delegate.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _delegate.pause(resumeSignal);

  @override
  void resume() => _delegate.resume();

  @override
  bool get isPaused => _delegate.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => _delegate.asFuture<E>(futureValue);
}
