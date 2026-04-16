import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/ffi/flutterm_core.dart';
import 'package:app/features/terminal/terminal_painter_models.dart';

import '../support/fake_core_bindings.dart';

void main() {
  test('terminal core client creates sessions and parses frame diffs', () {
    final bindings = FakeCoreBindings();
    final client = TerminalCoreClient(bindings);

    expect(client.ping(), 42);

    final sessionId = client.createSession(defaultTerminalProfile());
    final frame = client.takeFrameDiff(sessionId);

    expect(frame, isNotNull);
    expect(frame!.rows.single.text, 'flutterm ready');
    expect(client.pollEvents(sessionId).single.kind, 'started');

    client.closeSession(sessionId);
    expect(client.takeFrameDiff(sessionId), isNull);
  });

  test('terminal core client can roundtrip input through a real PTY session', () {
    final client = TerminalCoreClient(
      FluttermCoreBindings(ffi.DynamicLibrary.open(_resolveTestLibraryPath())),
    );

    final sessionId = client.createSession(
      defaultTerminalProfile().copyWith(
        id: 'interactive',
        name: 'Interactive',
        shell: '/bin/sh',
        args: const [],
      ),
    );
    addTearDown(() => client.closeSession(sessionId));

    sleep(const Duration(milliseconds: 250));
    client.takeFrameDiff(sessionId);

    client.sendInput(
      sessionId,
      Uint8List.fromList('printf \'dart ffi roundtrip\\n\'\n'.codeUnits),
    );

    TerminalFrameDiff? frame;
    for (var attempt = 0; attempt < 20; attempt += 1) {
      sleep(const Duration(milliseconds: 100));
      final nextFrame = client.takeFrameDiff(sessionId);
      if (nextFrame != null &&
          nextFrame.rows.any((row) => row.text.contains('dart ffi roundtrip'))) {
        frame = nextFrame;
        break;
      }
    }

    expect(frame, isNotNull, reason: 'expected PTY output to contain roundtrip marker');
    expect(
      frame!.rows.any((row) => row.text.contains('dart ffi roundtrip')),
      isTrue,
    );
  });

  test('terminal core client surfaces shell exit events', () {
    final client = TerminalCoreClient(
      FluttermCoreBindings(ffi.DynamicLibrary.open(_resolveTestLibraryPath())),
    );

    final sessionId = client.createSession(
      defaultTerminalProfile().copyWith(
        id: 'exit-check',
        name: 'Exit Check',
        shell: '/bin/sh',
        args: const ['-lc', 'exit 7'],
      ),
    );
    addTearDown(() => client.closeSession(sessionId));

    List<TerminalEvent> events = const [];
    for (var attempt = 0; attempt < 20; attempt += 1) {
      sleep(const Duration(milliseconds: 100));
      events = client.pollEvents(sessionId);
      if (events.any((event) => event.kind == 'exit')) {
        break;
      }
    }

    TerminalEvent? exitEvent;
    for (final event in events) {
      if (event.kind == 'exit') {
        exitEvent = event;
        break;
      }
    }

    expect(exitEvent, isNotNull, reason: 'expected shell exit event');
    expect(exitEvent!.payload?['code'], 7);
  });
}

String _resolveTestLibraryPath() {
  final candidates = <String>[
    'build/macos/Build/Products/Debug/app.app/Contents/Frameworks/libflutterm_core.dylib',
    '../native/core/target/debug/libflutterm_core.dylib',
  ];

  for (final candidate in candidates) {
    final file = File(candidate);
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }

  throw StateError(
    'Unable to locate libflutterm_core.dylib for Flutter-side PTY test.',
  );
}
