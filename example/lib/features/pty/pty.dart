import 'package:ianvs_pty/ianvs_pty.dart';

export 'package:ianvs_pty/ianvs_pty.dart'
    show
        NativePtyBackend,
        PtyBindings,
        PtyEvent,
        PtySessionBackend,
        PtySessionJsonRequestBackend;

PtySessionBackend loadDefaultPtySessionBackend() {
  return NativePtyBackend.load(emitRuntimeEventGapDiagnostics: true);
}
