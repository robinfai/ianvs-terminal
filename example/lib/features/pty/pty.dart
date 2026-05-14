import 'package:flutterm_pty/flutterm_pty.dart';

export 'package:flutterm_pty/flutterm_pty.dart'
    show
        NativePtyBackend,
        PtyBindings,
        PtyEvent,
        PtySessionBackend,
        PtySessionJsonRequestBackend;

PtySessionBackend loadDefaultPtySessionBackend() {
  return NativePtyBackend.load();
}
