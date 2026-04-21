import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
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

  test('terminal core client surfaces OSC window title requests', () {
    final client = _loadRealClient();

    final sessionId = client.createSession(
      defaultTerminalProfile().copyWith(
        id: 'title-check',
        name: 'Title Check',
        shell: '/bin/sh',
        args: const [],
      ),
    );
    addTearDown(() => client.closeSession(sessionId));

    sleep(const Duration(milliseconds: 250));
    client.takeFrameDiff(sessionId);

    client.sendInput(
      sessionId,
      Uint8List.fromList("printf '\\033]2;Build Target\\a'\n".codeUnits),
    );

    final frame = _waitForFrameWhere(
      client,
      sessionId,
      (frame) => frame.windowTitle == 'Build Target',
    );

    expect(frame.windowTitle, 'Build Target');
  });

  test('terminal core client surfaces OSC window icon requests', () {
    final client = _loadRealClient();

    final sessionId = client.createSession(
      defaultTerminalProfile().copyWith(
        id: 'icon-check',
        name: 'Icon Check',
        shell: '/bin/sh',
        args: const ['-lc', "printf '\\033]1;Build Icon\\a'"],
      ),
    );
    addTearDown(() => client.closeSession(sessionId));

    final frame = _waitForFrameWhere(
      client,
      sessionId,
      (frame) => frame.windowIconName == 'Build Icon',
    );

    expect(frame.windowIconName, 'Build Icon');
  });

  test(
    'terminal core client suppresses xterm window chrome callbacks in VT220 mode',
    () {
      final client = _loadRealClient();

      final sessionId = client.createSession(
        vt220TerminalProfile().copyWith(
          id: 'vt220-host-chrome',
          name: 'VT220 Host Chrome',
          shell: '/bin/sh',
          args: const [
            '-lc',
            "printf '\\033]2;Build Target\\a\\033]1;Build Icon\\a'",
          ],
        ),
      );
      addTearDown(() => client.closeSession(sessionId));

      final frame = _waitForFrameWhere(
        client,
        sessionId,
        (_) => true,
        description: 'initial VT220 frame',
      );

      expect(frame.windowTitle, isNull);
      expect(frame.windowIconName, isNull);
    },
  );

  test(
    'terminal core client can roundtrip input through a real PTY session',
    () {
      final client = _loadRealClient();

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
      final client = _loadRealClient();

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
      final client = _loadRealClient();

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

  test('terminal core client reflows long lines across resize', () {
    final client = _loadRealClient();

    final sessionId = client.createSession(
      defaultTerminalProfile().copyWith(
        id: 'interactive-reflow',
        name: 'Interactive Reflow',
        shell: '/bin/sh',
        args: const [],
      ),
    );
    addTearDown(() => client.closeSession(sessionId));

    final marker = 'reflow-${List.filled(130, '0').join()}';

    sleep(const Duration(milliseconds: 250));
    client.takeFrameDiff(sessionId);

    client.sendInput(
      sessionId,
      Uint8List.fromList("printf 'reflow-%0130d\\n' 0\n".codeUnits),
    );
    expect(
      _waitForFrameWhere(
        client,
        sessionId,
        (frame) =>
            _logicalRowsFromFrame(frame).any((row) => row.contains(marker)),
      ),
      isNotNull,
    );

    client.resizeSession(
      sessionId,
      cols: 40,
      rows: 24,
      pixelSize: const Size(400, 432),
      devicePixelRatio: 1,
    );

    final frame = _waitForFrameWhere(
      client,
      sessionId,
      (frame) =>
          _logicalRowsFromFrame(frame).any((row) => row.contains(marker)),
      description: 'containing reflow marker after resize',
    );

    expect(
      _logicalRowsFromFrame(frame),
      contains(marker),
      reason: 'expected resized frame to preserve the full logical line',
    );
    expect(frame.rows.any((row) => row.wrapped), isTrue);
  });

  test(
    'terminal core client stays interactive across different shell prompts',
    () {
      final client = _loadRealClient();

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
    final client = _loadRealClient();

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

  test(
    'terminal core client emits OSC 52 clipboard callbacks in xterm mode',
    () {
      final client = _loadRealClient();

      final sessionId = client.createSession(
        defaultTerminalProfile().copyWith(
          id: 'xterm-clipboard-check',
          name: 'Xterm Clipboard Check',
          shell: '/bin/sh',
          args: const [],
        ),
      );
      addTearDown(() => client.closeSession(sessionId));

      sleep(const Duration(milliseconds: 250));
      client.takeFrameDiff(sessionId);
      client.pollEvents(sessionId);

      client.sendInput(
        sessionId,
        Uint8List.fromList(
          "printf '\\033]52;c;5aSN5Yi25YaF5a658J+Mnw==\\a'\n".codeUnits,
        ),
      );
      final copyEvent = _waitForEventKind(client, sessionId, 'clipboard_copy');
      expect(copyEvent.payload?['selection'], 'c');
      expect(copyEvent.payload?['data'], '5aSN5Yi25YaF5a658J+Mnw==');

      client.sendInput(
        sessionId,
        Uint8List.fromList("printf '\\033]52;c;?\\a'\n".codeUnits),
      );
      final pasteEvent = _waitForEventKind(
        client,
        sessionId,
        'clipboard_paste_request',
      );
      expect(pasteEvent.payload?['selection'], 'c');
    },
  );

  test(
    'terminal core client suppresses OSC 52 clipboard callbacks in VT220 mode',
    () {
      final client = _loadRealClient();

      final sessionId = client.createSession(
        vt220TerminalProfile().copyWith(
          id: 'vt220-clipboard-check',
          name: 'VT220 Clipboard Check',
          shell: '/bin/sh',
          args: const [],
        ),
      );
      addTearDown(() => client.closeSession(sessionId));

      sleep(const Duration(milliseconds: 250));
      client.takeFrameDiff(sessionId);
      client.pollEvents(sessionId);

      client.sendInput(
        sessionId,
        Uint8List.fromList(
          "printf '\\033]52;c;5aSN5Yi25YaF5a658J+Mnw==\\a'\n".codeUnits,
        ),
      );
      _expectNoEventKind(client, sessionId, 'clipboard_copy');

      client.sendInput(
        sessionId,
        Uint8List.fromList("printf '\\033]52;c;?\\a'\n".codeUnits),
      );
      _expectNoEventKind(client, sessionId, 'clipboard_paste_request');
    },
  );
}

TerminalCoreClient _loadRealClient() {
  final libraryPath = _resolveTestLibraryPath();
  try {
    return TerminalCoreClient(
      FluttermCoreBindings(ffi.DynamicLibrary.open(libraryPath)),
    );
  } on ArgumentError catch (error) {
    throw StateError(
      'Failed to load libflutterm_core.dylib from $libraryPath. '
      'Run /Users/robinfai/personal/flutterm/tools/build_core.sh before Flutter-side PTY tests. '
      'Original error: $error',
    );
  }
}

String _resolveTestLibraryPath() {
  final candidates = <String>[
    '../native/core/target/debug/libflutterm_core.dylib',
    'build/macos/Build/Products/Debug/app.app/Contents/Frameworks/libflutterm_core.dylib',
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

TerminalEvent _waitForEventKind(
  TerminalCoreClient client,
  String sessionId,
  String kind,
) {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    sleep(const Duration(milliseconds: 100));
    final matching = client
        .pollEvents(sessionId)
        .where((event) => event.kind == kind)
        .toList();
    if (matching.isNotEmpty) {
      return matching.first;
    }
  }

  throw StateError('Timed out waiting for event "$kind".');
}

void _expectNoEventKind(
  TerminalCoreClient client,
  String sessionId,
  String kind,
) {
  for (var attempt = 0; attempt < 10; attempt += 1) {
    sleep(const Duration(milliseconds: 100));
    final matching = client
        .pollEvents(sessionId)
        .where((event) => event.kind == kind)
        .toList();
    expect(
      matching,
      isEmpty,
      reason:
          'unexpected $kind events: ${matching.map((event) => event.payload).toList()}',
    );
  }
}

TerminalFrameDiff _waitForFrameContaining(
  TerminalCoreClient client,
  String sessionId,
  String needle,
) {
  return _waitForFrameWhere(
    client,
    sessionId,
    (frame) => frame.rows.any((row) => row.text.contains(needle)),
    description: 'containing "$needle"',
  );
}

TerminalFrameDiff _waitForFrameWhere(
  TerminalCoreClient client,
  String sessionId,
  bool Function(TerminalFrameDiff frame) matches, {
  String description = 'matching predicate',
}) {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    sleep(const Duration(milliseconds: 100));
    final frame = client.takeFrameDiff(sessionId);
    if (frame != null && matches(frame)) {
      return frame;
    }
  }

  throw StateError('Timed out waiting for frame $description');
}

List<String> _logicalRowsFromFrame(TerminalFrameDiff frame) {
  final logicalRows = <String>[];
  var current = '';

  for (final row in frame.rows) {
    current += row.text.trimRight();
    if (!row.wrapped) {
      logicalRows.add(current);
      current = '';
    }
  }

  if (current.isNotEmpty) {
    logicalRows.add(current);
  }

  return logicalRows;
}
