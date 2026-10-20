import 'dart:convert';

import 'package:app/features/terminal/terminal_input_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart' as terminal;

class _Sink implements terminal.TerminalInputSink {
  final writes = <(String, String)>[];

  @override
  void sendInput(String sessionId, Uint8List bytes) {
    writes.add((sessionId, utf8.decode(bytes)));
  }
}

class _ProtocolSink extends _Sink
    implements terminal.TerminalProtocolInputSink {
  final reports = <(String, String)>[];

  @override
  void sendProtocolInput(String sessionId, Uint8List bytes) {
    reports.add((sessionId, utf8.decode(bytes)));
  }
}

const _modes = terminal.TerminalFrameModes(
  focusTracking: true,
  mouseMode: 'normal',
  mouseEncoding: 'sgr',
);

void main() {
  for (final protocol in [false, true]) {
    test(
      'inactive focus loss is isolated and remains revocable, protocol: $protocol',
      () {
        final sink = protocol ? _ProtocolSink() : _Sink();
        var active = true;
        var revoked = false;
        final input = TerminalInputController(
          sessionId: 'original',
          runtime: sink,
          readOnly: () => !active || revoked,
          readOnlyFocusLoss: () => revoked,
          readSelection: () => '',
          copySelection: (_) async {},
          readClipboard: () async => '',
        );
        final retained = input.runtime as terminal.TerminalProtocolInputSink;
        active = false;

        input.sendFocusReport(focused: false, modes: _modes);
        final reports = sink is _ProtocolSink ? sink.reports : sink.writes;
        expect(reports, [('original', '\x1b[O')]);
        reports.clear();

        input.sendFocusReport(focused: true, modes: _modes);
        input.sendText('stale input');
        input.sendText('\x1b[O');
        input.sendMouseReport(
          modes: _modes,
          row: 0,
          col: 0,
          button: 0,
          pressed: true,
        );
        retained.sendInput(
          'original',
          Uint8List.fromList(ascii.encode('\x1b[O')),
        );
        for (final payload in ['', '\x1b[I', 'x', '\x1b[Ox', '\x1b[O\n']) {
          retained.sendProtocolInput(
            'original',
            Uint8List.fromList(ascii.encode(payload)),
          );
        }
        expect(sink.writes, isEmpty);
        expect(reports, isEmpty);

        // An actual read-only/epoch revocation still cancels both the public
        // callback and an already captured low-level protocol sink.
        revoked = true;
        input.sendFocusReport(focused: false, modes: _modes);
        retained.sendProtocolInput(
          'original',
          Uint8List.fromList(ascii.encode('\x1b[O')),
        );
        expect(sink.writes, isEmpty);
        expect(reports, isEmpty);
      },
    );
  }
}
