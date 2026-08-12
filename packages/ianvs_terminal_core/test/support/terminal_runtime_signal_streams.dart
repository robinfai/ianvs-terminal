import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

Stream<TerminalSessionEvent> terminalSessionEvents(
  TerminalRuntimeController runtime,
) => runtime.runtimeSignals
    .where((signal) => signal is TerminalRuntimeSessionEventSignal)
    .cast<TerminalRuntimeSessionEventSignal>()
    .map((signal) => signal.payload);

Stream<TerminalSessionZmodemEvent> terminalZmodemEvents(
  TerminalRuntimeController runtime,
) => runtime.runtimeSignals
    .where((signal) => signal is TerminalRuntimeZmodemEventSignal)
    .cast<TerminalRuntimeZmodemEventSignal>()
    .map((signal) => signal.payload);

Stream<TerminalSessionZmodemDeferredWriteFailedDiagnostic>
terminalZmodemDeferredWriteFailures(TerminalRuntimeController runtime) =>
    runtime.runtimeSignals
        .where((signal) => signal is TerminalRuntimeZmodemDeferredFailureSignal)
        .cast<TerminalRuntimeZmodemDeferredFailureSignal>()
        .map((signal) => signal.payload);
