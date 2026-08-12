// This adversarial fixture proves that erased runtime stream access is denied.
// ignore_for_file: avoid_dynamic_calls

import 'dart:async';

import 'package:ianvs_terminal/ianvs_terminal.dart';

void directoryEscape(TerminalRuntimeController runtime) {
  final unifiedAlias = runtime.runtimeSignals;

  unifiedAlias.listen((_) {});
}

void dynamicEscape(TerminalRuntimeController runtime) {
  final dynamic erasedRuntime = runtime;
  erasedRuntime.events.listen((Object? _) {});
  erasedRuntime.zmodemEvents.listen((Object? _) {});
  subscribe<Object?>(
    erasedRuntime.zmodemDeferredWriteFailures as Stream<Object?>,
  );
}

void duplicateCoordinatorSubscription(Stream<Object?> signals) {
  final duplicate = signals;
  signals.listen((_) {});
  subscribe(duplicate);
}

void subscribe<T>(Stream<T> stream) {
  stream.listen((_) {});
}
