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

  test(
    'terminal core client can roundtrip input through a real PTY session',
    () {
      final client = TerminalCoreClient(
        FluttermCoreBindings(
          ffi.DynamicLibrary.open(_resolveTestLibraryPath()),
        ),
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
            nextFrame.rows.any(
              (row) => row.text.contains('dart ffi roundtrip'),
            )) {
          frame = nextFrame;
          break;
        }
      }

      expect(
        frame,
        isNotNull,
        reason: 'expected PTY output to contain roundtrip marker',
      );
      expect(
        frame!.rows.any((row) => row.text.contains('dart ffi roundtrip')),
        isTrue,
      );
    },
  );

  test(
    'terminal core client can roundtrip multiple commands through one PTY session',
    () {
      final client = TerminalCoreClient(
        FluttermCoreBindings(
          ffi.DynamicLibrary.open(_resolveTestLibraryPath()),
        ),
      );

      final sessionId = client.createSession(
        defaultTerminalProfile().copyWith(
          id: 'interactive-multi',
          name: 'Interactive Multi',
          shell: '/bin/sh',
          args: const [],
        ),
      );
      addTearDown(() => client.closeSession(sessionId));

      sleep(const Duration(milliseconds: 250));
      client.takeFrameDiff(sessionId);

      client.sendInput(
        sessionId,
        Uint8List.fromList('printf \'first marker\\n\'\n'.codeUnits),
      );
      expect(
        _waitForFrameContaining(
          client,
          sessionId,
          'first marker',
        ).rows.any((row) => row.text.contains('first marker')),
        isTrue,
      );

      client.sendInput(
        sessionId,
        Uint8List.fromList('printf \'second marker\\n\'\n'.codeUnits),
      );
      expect(
        _waitForFrameContaining(
          client,
          sessionId,
          'second marker',
        ).rows.any((row) => row.text.contains('second marker')),
        isTrue,
      );
    },
  );

  test(
    'terminal core client stays interactive after a longer PTY output burst',
    () {
      final client = TerminalCoreClient(
        FluttermCoreBindings(
          ffi.DynamicLibrary.open(_resolveTestLibraryPath()),
        ),
      );

      final sessionId = client.createSession(
        defaultTerminalProfile().copyWith(
          id: 'interactive-long',
          name: 'Interactive Long',
          shell: '/bin/sh',
          args: const [],
        ),
      );
      addTearDown(() => client.closeSession(sessionId));

      sleep(const Duration(milliseconds: 250));
      client.takeFrameDiff(sessionId);

      client.sendInput(
        sessionId,
        Uint8List.fromList(
          "i=1; while [ \"\$i\" -le 24 ]; do printf 'burst %02d\\n' \"\$i\"; i=\$((i+1)); done\n"
              .codeUnits,
        ),
      );
      expect(
        _waitForFrameContaining(
          client,
          sessionId,
          'burst 24',
        ).rows.any((row) => row.text.contains('burst 24')),
        isTrue,
      );

      client.sendInput(
        sessionId,
        Uint8List.fromList('printf \'after burst marker\\n\'\n'.codeUnits),
      );
      expect(
        _waitForFrameContaining(
          client,
          sessionId,
          'after burst marker',
        ).rows.any((row) => row.text.contains('after burst marker')),
        isTrue,
      );
    },
  );

  test(
    'terminal core client stays interactive across different shell prompts',
    () {
      final client = TerminalCoreClient(
        FluttermCoreBindings(
          ffi.DynamicLibrary.open(_resolveTestLibraryPath()),
        ),
      );

      const cases = [
        ('prompt-one', 'ffi-one>', 'first prompt marker'),
        ('prompt-two', 'ffi-two#', 'second prompt marker'),
      ];

      for (final (id, prompt, marker) in cases) {
        final sessionId = client.createSession(
          defaultTerminalProfile().copyWith(
            id: id,
            name: id,
            shell: '/bin/sh',
            args: const ['-i'],
            env: {'PS1': '$prompt '},
          ),
        );
        addTearDown(() => client.closeSession(sessionId));

        expect(
          _waitForFrameContaining(
            client,
            sessionId,
            prompt,
          ).rows.any((row) => row.text.contains(prompt)),
          isTrue,
          reason: 'expected PTY frame to contain prompt $prompt',
        );

        client.sendInput(
          sessionId,
          Uint8List.fromList("printf '$marker\\n'\n".codeUnits),
        );
        expect(
          _waitForFrameContaining(
            client,
            sessionId,
            marker,
          ).rows.any((row) => row.text.contains(marker)),
          isTrue,
          reason: 'expected PTY output to contain marker $marker',
        );
      }
    },
  );

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

TerminalFrameDiff _waitForFrameContaining(
  TerminalCoreClient client,
  String sessionId,
  String needle,
) {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    sleep(const Duration(milliseconds: 100));
    final frame = client.takeFrameDiff(sessionId);
    if (frame != null && frame.rows.any((row) => row.text.contains(needle))) {
      return frame;
    }
  }

  throw StateError('Timed out waiting for frame containing "$needle"');
}
