import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutterm_terminal/flutterm_terminal.dart';
import 'package:flutterm_pty/flutterm_pty.dart';

void main() {
  test(
    'terminal viewport controller normalizes delta fallback state as a snapshot',
    () {
      final controller = TerminalViewportController();

      controller.updateFrame(
        const TerminalFrameDiff(
          frameKind: TerminalFrameKind.delta,
          rows: [TerminalRow(index: 1, text: 'beta')],
          cursor: TerminalCursor(row: 1, col: 4, visible: true),
          viewportRows: 2,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 1, end: 2)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          viewportStartRow: 12,
          viewportRowShift: -1,
        ),
      );

      final frame = controller.frame;
      expect(frame.frameKind, TerminalFrameKind.snapshot);
      expect(frame.viewportRowShift, 0);
      expect(
        frame.dirtyRanges
            .map((range) => (range.start, range.end))
            .toList(growable: false),
        <(int, int)>[(0, 2)],
      );
      expect(
        frame.rows.map((row) => (row.index, row.text)).toList(growable: false),
        <(int, String)>[(0, ''), (1, 'beta')],
      );
    },
  );

  test(
    'terminal viewport controller treats incoming delta rows as dirty ranges',
    () {
      final controller = TerminalViewportController();

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [
            TerminalRow(index: 0, text: 'prompt'),
            TerminalRow(index: 1, text: 'old link'),
          ],
          cursor: TerminalCursor(row: 0, col: 6, visible: true),
          viewportRows: 2,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 2)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          hyperlinks: [
            TerminalHyperlinkRange(
              row: 1,
              startCol: 0,
              endCol: 8,
              uri: 'https://stale.example',
            ),
          ],
        ),
      );
      controller.updateFrame(
        const TerminalFrameDiff(
          frameKind: TerminalFrameKind.delta,
          rows: [TerminalRow(index: 1, text: 'fresh prompt')],
          cursor: TerminalCursor(row: 1, col: 12, visible: true),
          viewportRows: 2,
          viewportCols: 80,
          dirtyRanges: [],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

      final frame = controller.frame;
      expect(frame.rows.map((row) => row.text).toList(), <String>[
        'prompt',
        'fresh prompt',
      ]);
      expect(
        frame.dirtyRanges
            .map((range) => (range.start, range.end))
            .toList(growable: false),
        <(int, int)>[(1, 2)],
      );
      expect(frame.hyperlinks, isEmpty);
    },
  );

  test('terminal frame modes parse alternate screen hints', () {
    final modes = TerminalFrameModes.fromJson(const <String, Object?>{
      'alternate_screen': true,
    });

    expect(modes.alternateScreen, isTrue);
  });

  test('terminal runtime falls back when JSON requests are unsupported', () {
    final runtimeBackend = _FakePtyBackend()..returnNullJsonRequests = true;
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );

    expect(runtime.searchText(sessionId, 'demo'), isEmpty);
    expect(
      runtime.selectionText(
        sessionId,
        const TerminalSelection(startRow: 0, startCol: 0, endRow: 0, endCol: 4),
        block: false,
      ),
      'demo',
    );
    expect(
      runtimeBackend.jsonRequests.map((request) => request['kind']),
      <String>['terminal.search_text', 'terminal.selection_text'],
    );
  });

  testWidgets(
    'terminal runtime controller owns sessions and viewport state without demo imports',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );

      expect(sessionId, '1');
      expect(runtime.viewportFor(sessionId).frame.rows.first.text, 'demo');
      expect(runtimeBackend.lastCreateSessionJson, isNotNull);
      expect(runtimeBackend.lastCreateSessionPayload!['id'], 'runtime-1');
      expect(runtimeBackend.lastCreateSessionPayload!['name'], 'sh');
      expect(
        runtimeBackend.lastCreateSessionPayload!['launch'],
        <String, Object?>{
          'program': '/bin/sh',
          'args': const <String>[],
          'env': const <String, String>{},
          'cwd': null,
        },
      );
      expect(
        runtimeBackend.lastCreateSessionPayload!['shellIntegration'],
        <String, Object?>{'enabled': true},
      );
    },
  );

  testWidgets(
    'terminal runtime controller refreshes after input and scrolling when polling is disabled',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );

      expect(runtimeBackend.takeFrameDiffCalls, 1);
      expect(runtimeBackend.pollEventsCalls, 1);

      runtime.sendInput(sessionId, Uint8List.fromList(const [0x41]));
      runtime.scrollViewport(sessionId, 1);
      runtime.scrollViewportTo(sessionId, 2);
      await tester.pump();

      expect(runtimeBackend.takeFrameDiffCalls, 2);
      expect(runtimeBackend.pollEventsCalls, 2);
    },
  );

  testWidgets('terminal runtime controller exposes explicit full refresh', (
    tester,
  ) async {
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );

    runtimeBackend.setFrame(sessionId, _singleRowSnapshot('recovered prompt'));
    runtime.refreshSession(sessionId);
    await tester.pump();

    expect(runtimeBackend.scrollToCalls, <(String, int)>[(sessionId, 0)]);
    expect(
      runtime.viewportFor(sessionId).frame.rows.first.text,
      'recovered prompt',
    );
  });

  testWidgets('terminal runtime controller emits typed shell hook events', (
    tester,
  ) async {
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await tester.pump();

    final shellHooks = <TerminalSessionShellHookEvent>[];
    final subscription = runtime.events
        .where((event) => event is TerminalSessionShellHookEvent)
        .cast<TerminalSessionShellHookEvent>()
        .listen(shellHooks.add);
    addTearDown(subscription.cancel);

    runtimeBackend.enqueueEvent(
      sessionId,
      PtyEvent(
        kind: 'shell_hook',
        sessionId: sessionId,
        payload: <String, Object?>{
          'hook': 'command_finished',
          'command': 'echo ok',
          'pwd': '/tmp/project',
          'shell': 'zsh',
          'exit_code': 7,
          'extra': <String, Object?>{'kept': true},
        },
      ),
    );

    runtime.sendInput(sessionId, Uint8List(0));
    await tester.pump();

    final event = shellHooks.single;
    expect(event.sessionId, sessionId);
    expect(event.rawPayload['extra'], <String, Object?>{'kept': true});
    expect(event.hook, 'command_finished');
    expect(event.command, 'echo ok');
    expect(event.cwd, '/tmp/project');
    expect(event.shell, 'zsh');
    expect(event.exitCode, 7);
  });

  testWidgets('terminal runtime controller emits bell events', (tester) async {
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    await tester.pump();

    final bells = <TerminalSessionBellEvent>[];
    final subscription = runtime.events
        .where((event) => event is TerminalSessionBellEvent)
        .cast<TerminalSessionBellEvent>()
        .listen(bells.add);
    addTearDown(subscription.cancel);

    runtimeBackend.enqueueEvent(
      sessionId,
      PtyEvent(kind: 'bell', sessionId: sessionId),
    );

    runtime.sendInput(sessionId, Uint8List(0));
    await tester.pump();

    expect(bells.single.sessionId, sessionId);
  });

  testWidgets(
    'terminal runtime controller passes through unknown shell hooks',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();

      final shellHooks = <TerminalSessionShellHookEvent>[];
      final subscription = runtime.events
          .where((event) => event is TerminalSessionShellHookEvent)
          .cast<TerminalSessionShellHookEvent>()
          .listen(shellHooks.add);
      addTearDown(subscription.cancel);

      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'shell_hook',
          sessionId: sessionId,
          payload: const <String, Object?>{'hook': 'custom.future_hook'},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      final event = shellHooks.single;
      expect(event.hook, 'custom.future_hook');
      expect(event.command, isNull);
      expect(event.cwd, isNull);
      expect(event.shell, isNull);
      expect(event.exitCode, isNull);
      expect(event.rawPayload, containsPair('hook', 'custom.future_hook'));
    },
  );

  testWidgets(
    'terminal runtime controller emits shell hooks before same-batch exits',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      await tester.pump();

      final events = <TerminalSessionEvent>[];
      final subscription = runtime.events.listen(events.add);
      addTearDown(subscription.cancel);

      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'shell_hook',
          sessionId: sessionId,
          payload: const <String, Object?>{
            'hook': 'command_finished',
            'exit_code': 0,
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'exit',
          sessionId: sessionId,
          payload: const <String, Object?>{'code': 0},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      final lifecycleEvents = events
          .where(
            (event) =>
                event is TerminalSessionShellHookEvent ||
                event is TerminalSessionExitEvent,
          )
          .toList(growable: false);
      expect(lifecycleEvents, hasLength(2));
      expect(lifecycleEvents.first, isA<TerminalSessionShellHookEvent>());
      expect(lifecycleEvents.last, isA<TerminalSessionExitEvent>());
    },
  );

  test('terminal runtime owns search and selection JSON request shapes', () {
    final runtimeBackend = _FakePtyBackend()
      ..searchResponse = const <Map<String, Object?>>[
        <String, Object?>{
          'row': 2,
          'start_col': 4,
          'end_col': 9,
          'text': 'ready',
          'scrollback_offset': 2,
        },
      ]
      ..selectionResponse = 'selected text';
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    runtimeBackend.jsonRequests.clear();

    final matches = runtime.searchText(sessionId, 'ready');
    expect(matches.single.text, 'ready');
    expect(runtimeBackend.jsonRequests.single, <String, Object?>{
      'kind': 'terminal.search_text',
      'query': 'ready',
    });

    final text = runtime.selectionText(
      sessionId,
      const TerminalSelection(startRow: 0, startCol: 1, endRow: 0, endCol: 4),
      block: true,
    );
    expect(text, 'selected text');
    expect(runtimeBackend.jsonRequests.last, <String, Object?>{
      'kind': 'terminal.selection_text',
      'selection': <String, Object?>{
        'start_row': 0,
        'start_col': 1,
        'end_row': 0,
        'end_col': 4,
      },
      'block': true,
    });
  });

  testWidgets(
    'terminal runtime controller does not keep started-only refreshes in flight',
    (tester) async {
      final runtimeBackend = _StartedEventPtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );

      runtimeBackend.setFrame(sessionId, _singleRowSnapshot('fresh'));
      runtime.resizeSession(sessionId, const Size(180, 144), 1);
      expect(runtime.viewportFor(sessionId).frame.rows.first.text, 'fresh');
      await tester.pump();

      expect(runtimeBackend.takeFrameDiffCalls, 2);
      expect(runtime.viewportFor(sessionId).frame.rows.first.text, 'fresh');
    },
  );

  testWidgets(
    'terminal runtime controller merges delta frames into stable viewport state',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );

      runtimeBackend.setFrame(sessionId, <String, Object?>{
        'frame_kind': 'snapshot',
        'rows': <Object?>[
          <String, Object?>{
            'index': 0,
            'text': 'alpha',
            'style_runs': const <Object?>[],
          },
          <String, Object?>{
            'index': 1,
            'text': 'beta',
            'style_runs': const <Object?>[],
          },
        ],
        'cursor': <String, Object?>{'row': 1, 'col': 4, 'visible': true},
        'viewport_rows': 2,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 0, 'end': 2},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
        'hyperlinks': <Object?>[
          <String, Object?>{
            'row': 0,
            'start_col': 0,
            'end_col': 5,
            'uri': 'https://example.com/alpha',
          },
        ],
      });
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      runtimeBackend.setFrame(sessionId, <String, Object?>{
        'frame_kind': 'delta',
        'rows': <Object?>[
          <String, Object?>{
            'index': 1,
            'text': 'beta*',
            'style_runs': const <Object?>[],
          },
        ],
        'cursor': <String, Object?>{'row': 1, 'col': 5, 'visible': true},
        'viewport_rows': 2,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 1, 'end': 2},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
        'hyperlinks': <Object?>[
          <String, Object?>{
            'row': 1,
            'start_col': 0,
            'end_col': 5,
            'uri': 'https://example.com/beta',
          },
        ],
      });
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      final merged = runtime.viewportFor(sessionId).frame;
      expect(merged.frameKind, TerminalFrameKind.delta);
      expect(merged.rows.map((row) => row.text).toList(), <String>[
        'alpha',
        'beta*',
      ]);
      expect(merged.hyperlinks.map((range) => range.uri).toList(), <String>[
        'https://example.com/alpha',
        'https://example.com/beta',
      ]);
    },
  );

  testWidgets(
    'terminal runtime controller shifts viewport rows forward on scrolling delta frames',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );

      runtimeBackend.setFrame(sessionId, <String, Object?>{
        'frame_kind': 'snapshot',
        'rows': <Object?>[
          <String, Object?>{
            'index': 0,
            'text': 'alpha',
            'style_runs': const <Object?>[],
          },
          <String, Object?>{
            'index': 1,
            'text': 'beta',
            'style_runs': const <Object?>[],
          },
          <String, Object?>{
            'index': 2,
            'text': 'gamma',
            'style_runs': const <Object?>[],
          },
        ],
        'cursor': <String, Object?>{'row': 2, 'col': 5, 'visible': true},
        'viewport_rows': 3,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 0, 'end': 3},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 20,
        'viewport_start_row': 20,
        'hyperlinks': <Object?>[
          <String, Object?>{
            'row': 1,
            'start_col': 0,
            'end_col': 4,
            'uri': 'https://example.com/beta',
          },
        ],
      });
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      runtimeBackend.setFrame(sessionId, <String, Object?>{
        'frame_kind': 'delta',
        'rows': <Object?>[
          <String, Object?>{
            'index': 2,
            'text': 'delta',
            'style_runs': const <Object?>[],
          },
        ],
        'cursor': <String, Object?>{'row': 2, 'col': 5, 'visible': true},
        'viewport_rows': 3,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 2, 'end': 3},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 21,
        'viewport_start_row': 21,
        'viewport_row_shift': -1,
        'hyperlinks': <Object?>[
          <String, Object?>{
            'row': 2,
            'start_col': 0,
            'end_col': 5,
            'uri': 'https://example.com/delta',
          },
        ],
      });
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      final shifted = runtime.viewportFor(sessionId).frame;
      expect(shifted.rows.map((row) => row.text).toList(), <String>[
        'beta',
        'gamma',
        'delta',
      ]);
      expect(
        shifted.hyperlinks
            .map((range) => '${range.row}:${range.uri}')
            .toList(growable: false),
        <String>['0:https://example.com/beta', '2:https://example.com/delta'],
      );
    },
  );

  testWidgets(
    'terminal runtime controller coalesces refreshes while event handling is still in flight',
    (tester) async {
      final copyCompleter = Completer<void>();
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) => copyCompleter.future,
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final viewport = runtime.viewportFor(sessionId);
      runtimeBackend.setFrame(
        sessionId,
        _singleRowSnapshot('queued visible frame'),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: <String, Object?>{
            'data': base64.encode(utf8.encode('queued copy')),
          },
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(viewport.frame.rows.first.text, 'queued visible frame');

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(
        runtimeBackend.takeFrameDiffCalls,
        2,
        reason:
            'second refresh should queue instead of re-entering immediately',
      );

      copyCompleter.complete();
      await tester.pump();
      await tester.pump();

      expect(runtimeBackend.takeFrameDiffCalls, 3);
    },
  );

  testWidgets(
    'terminal runtime controller applies queued delta frames in order after a blocked refresh',
    (tester) async {
      final copyCompleter = Completer<void>();
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) => copyCompleter.future,
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final viewport = runtime.viewportFor(sessionId);
      await tester.pump();

      expect(viewport.frameVersion, 1);

      runtimeBackend.setFrame(sessionId, <String, Object?>{
        'frame_kind': 'snapshot',
        'rows': <Object?>[
          <String, Object?>{
            'index': 0,
            'text': 'alpha',
            'style_runs': const <Object?>[],
          },
          <String, Object?>{
            'index': 1,
            'text': 'beta',
            'style_runs': const <Object?>[],
          },
        ],
        'cursor': <String, Object?>{'row': 1, 'col': 4, 'visible': true},
        'viewport_rows': 2,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 0, 'end': 2},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(viewport.frame.rows.map((row) => row.text).toList(), <String>[
        'alpha',
        'beta',
      ]);

      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: <String, Object?>{
            'data': base64.encode(utf8.encode('block refresh')),
          },
        ),
      );
      runtimeBackend.enqueueFrame(sessionId, <String, Object?>{
        'frame_kind': 'delta',
        'rows': <Object?>[
          <String, Object?>{
            'index': 0,
            'text': 'alpha*',
            'style_runs': const <Object?>[],
          },
        ],
        'cursor': <String, Object?>{'row': 0, 'col': 6, 'visible': true},
        'viewport_rows': 2,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 0, 'end': 1},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });
      runtimeBackend.enqueueFrame(sessionId, <String, Object?>{
        'frame_kind': 'delta',
        'rows': <Object?>[
          <String, Object?>{
            'index': 1,
            'text': 'beta*',
            'style_runs': const <Object?>[],
          },
        ],
        'cursor': <String, Object?>{'row': 1, 'col': 5, 'visible': true},
        'viewport_rows': 2,
        'viewport_cols': 80,
        'dirty_ranges': <Object?>[
          <String, Object?>{'start': 1, 'end': 2},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
      });

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(viewport.frame.rows.map((row) => row.text).toList(), <String>[
        'alpha*',
        'beta',
      ]);

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(viewport.frame.rows.map((row) => row.text).toList(), <String>[
        'alpha*',
        'beta',
      ]);

      copyCompleter.complete();
      await tester.pump();
      await tester.pump();

      expect(viewport.frame.rows.map((row) => row.text).toList(), <String>[
        'alpha*',
        'beta*',
      ]);
    },
  );

  testWidgets(
    'terminal runtime controller lets a queued snapshot replace older blocked frames',
    (tester) async {
      final copyCompleter = Completer<void>();
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) => copyCompleter.future,
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final viewport = runtime.viewportFor(sessionId);
      await tester.pump();

      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: <String, Object?>{
            'data': base64.encode(utf8.encode('block refresh')),
          },
        ),
      );
      runtimeBackend.enqueueFrame(sessionId, _singleRowSnapshot('stale'));
      runtimeBackend.enqueueFrame(sessionId, _singleRowSnapshot('fresh'));

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();
      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(viewport.frame.rows.first.text, 'stale');

      copyCompleter.complete();
      await tester.pump();
      await tester.pump();

      expect(viewport.frame.rows.first.text, 'fresh');
    },
  );

  testWidgets(
    'terminal runtime controller applies visible frames before clipboard paste handling completes',
    (tester) async {
      final readClipboardCompleter = Completer<String>();
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () => readClipboardCompleter.future,
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final viewport = runtime.viewportFor(sessionId);
      runtimeBackend.setFrame(
        sessionId,
        _singleRowSnapshot('paste visible frame'),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_paste_request',
          sessionId: sessionId,
          payload: const <String, Object?>{'selection': 'c'},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(viewport.frame.rows.first.text, 'paste visible frame');
      expect(
        runtimeBackend.writeCalls.where((call) => call.isNotEmpty),
        isEmpty,
      );

      readClipboardCompleter.complete('paste me');
      await tester.pump();
      await tester.pump();

      expect(
        utf8.decode(runtimeBackend.writeCalls.last),
        '\x1B]52;c;cGFzdGUgbWU=\x07',
      );
    },
  );

  testWidgets('terminal runtime controller dispose closes active sessions', (
    tester,
  ) async {
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );

    runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/zsh'),
      ),
    );

    runtime.dispose();

    expect(runtimeBackend.closeCalls, <String>['1', '2']);
  });

  testWidgets('terminal runtime controller continues to handle exit events', (
    tester,
  ) async {
    final runtimeBackend = _FakePtyBackend();
    final runtime = TerminalRuntimeController(
      backend: runtimeBackend,
      copyToClipboard: (_) async {},
      readClipboard: () async => '',
      enableSessionPolling: false,
    );
    addTearDown(runtime.dispose);

    final seenEvents = <TerminalSessionEvent>[];
    final subscription = runtime.events.listen(seenEvents.add);
    addTearDown(subscription.cancel);

    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    runtimeBackend.enqueueEvent(
      sessionId,
      const PtyEvent(
        kind: 'exit',
        sessionId: '1',
        payload: <String, Object?>{'code': 7},
      ),
    );

    runtime.sendInput(sessionId, Uint8List(0));
    await tester.pump();

    expect(runtime.hasSession(sessionId), isFalse);
    expect(seenEvents.whereType<TerminalSessionExitEvent>().single.exitCode, 7);
  });

  testWidgets(
    'terminal runtime controller applies the final frame before handling exit',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final seenEvents = <TerminalSessionEvent>[];
      final subscription = runtime.events.listen(seenEvents.add);
      addTearDown(subscription.cancel);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final viewport = runtime.viewportFor(sessionId);
      await tester.pump();
      seenEvents.clear();
      runtimeBackend.setFrame(sessionId, _singleRowSnapshot('final output'));
      runtimeBackend.enqueueEvent(
        sessionId,
        const PtyEvent(
          kind: 'exit',
          sessionId: '1',
          payload: <String, Object?>{'code': 9},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(viewport.frame.rows.first.text, 'final output');
      expect(seenEvents.map((event) => event.runtimeType).toList(), <Type>[
        TerminalSessionFrameEvent,
        TerminalSessionExitEvent,
      ]);
      expect(
        seenEvents.whereType<TerminalSessionExitEvent>().single.exitCode,
        9,
      );
      expect(runtime.hasSession(sessionId), isFalse);
    },
  );

  testWidgets(
    'terminal runtime controller continues to handle clipboard and resize events',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      String copiedText = '';
      String? pasteWrite;
      double? resizeWidthDelta;
      double? resizeHeightDelta;
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (text) async {
          copiedText = text;
        },
        readClipboard: () async => 'paste me',
        resizeWindowBy:
            ({required double widthDelta, required double heightDelta}) async {
              resizeWidthDelta = widthDelta;
              resizeHeightDelta = heightDelta;
            },
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtime.resizeSession(sessionId, const Size(180, 144), 1);

      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: <String, Object?>{
            'data': base64.encode(utf8.encode('copied text')),
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_paste_request',
          sessionId: sessionId,
          payload: const <String, Object?>{'selection': 'c'},
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'resize',
          sessionId: sessionId,
          payload: const <String, Object?>{'cols': 21, 'rows': 9},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      pasteWrite = utf8.decode(runtimeBackend.writeCalls.last);

      expect(copiedText, 'copied text');
      expect(pasteWrite, '\x1B]52;c;cGFzdGUgbWU=\x07');
      expect(resizeWidthDelta, 9);
      expect(resizeHeightDelta, 18);
      expect(runtimeBackend.resizeCalls.last, <Object?>['1', 21, 9, 189, 162]);
    },
  );
}

class _FakePtyBackend
    implements PtySessionBackend, PtySessionJsonRequestBackend {
  String? lastCreateSessionJson;
  int takeFrameDiffCalls = 0;
  int pollEventsCalls = 0;
  final List<String> closeCalls = <String>[];
  final List<Uint8List> writeCalls = <Uint8List>[];
  final List<List<Object?>> resizeCalls = <List<Object?>>[];
  final List<(String, int)> scrollToCalls = <(String, int)>[];
  final List<Map<String, Object?>> jsonRequests = <Map<String, Object?>>[];
  List<Map<String, Object?>> searchResponse = const <Map<String, Object?>>[];
  String selectionResponse = '';
  bool returnNullJsonRequests = false;

  final Map<String, Map<String, Object?>> _frames =
      <String, Map<String, Object?>>{};
  final Map<String, List<Map<String, Object?>>> _queuedFrames =
      <String, List<Map<String, Object?>>>{};
  final Map<String, List<PtyEvent>> _queuedEvents = <String, List<PtyEvent>>{};
  int _nextSessionId = 0;

  Map<String, Object?>? get lastCreateSessionPayload {
    final raw = lastCreateSessionJson;
    if (raw == null) {
      return null;
    }
    return (jsonDecode(raw) as Map).cast<String, Object?>();
  }

  void setFrame(String sessionId, Map<String, Object?> frame) {
    _frames[sessionId] = frame;
  }

  void enqueueFrame(String sessionId, Map<String, Object?> frame) {
    _queuedFrames
        .putIfAbsent(sessionId, () => <Map<String, Object?>>[])
        .add(frame);
  }

  void enqueueEvent(String sessionId, PtyEvent event) {
    _queuedEvents.putIfAbsent(sessionId, () => <PtyEvent>[]).add(event);
  }

  @override
  int ping() => 1;

  @override
  String createSession(String sessionConfigJson) {
    lastCreateSessionJson = sessionConfigJson;
    final sessionId = (++_nextSessionId).toString();
    _frames[sessionId] = <String, Object?>{
      'frame_kind': 'snapshot',
      'rows': <Object?>[
        <String, Object?>{
          'index': 0,
          'text': 'demo',
          'style_runs': <Object?>[],
        },
      ],
      'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 24,
      'viewport_cols': 80,
      'dirty_ranges': <Object?>[],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    };
    return sessionId;
  }

  @override
  void closeSession(String sessionId) {
    closeCalls.add(sessionId);
    _frames.remove(sessionId);
    _queuedFrames.remove(sessionId);
    _queuedEvents.remove(sessionId);
  }

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
  }) {
    resizeCalls.add(<Object?>[sessionId, cols, rows, pixelWidth, pixelHeight]);
    final frame = _frames[sessionId];
    if (frame != null) {
      frame['viewport_cols'] = cols;
      frame['viewport_rows'] = rows;
    }
  }

  @override
  void writeInput(String sessionId, List<int> bytes) {
    writeCalls.add(Uint8List.fromList(bytes));
  }

  @override
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {
    scrollToCalls.add((sessionId, offset));
  }

  @override
  String? requestSessionJson(String sessionId, String requestJson) {
    final request = (jsonDecode(requestJson) as Map).cast<String, Object?>();
    jsonRequests.add(request);
    if (returnNullJsonRequests) {
      return null;
    }
    return switch (request['kind']) {
      'terminal.search_text' => jsonEncode(searchResponse),
      'terminal.selection_text' => jsonEncode(<String, Object?>{
        'text': selectionResponse,
      }),
      _ => null,
    };
  }

  @override
  String? takeFrameDiffJson(String sessionId) {
    takeFrameDiffCalls += 1;
    final queuedFrames = _queuedFrames[sessionId];
    if (queuedFrames != null && queuedFrames.isNotEmpty) {
      return jsonEncode(queuedFrames.removeAt(0));
    }
    final frame = _frames[sessionId];
    return frame == null ? null : jsonEncode(frame);
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) {
    pollEventsCalls += 1;
    return _queuedEvents.remove(sessionId) ?? const <PtyEvent>[];
  }
}

class _StartedEventPtyBackend extends _FakePtyBackend {
  @override
  String createSession(String sessionConfigJson) {
    final sessionId = super.createSession(sessionConfigJson);
    enqueueEvent(sessionId, PtyEvent(kind: 'started', sessionId: sessionId));
    return sessionId;
  }
}

Map<String, Object?> _singleRowSnapshot(String text) {
  return <String, Object?>{
    'frame_kind': 'snapshot',
    'rows': <Object?>[
      <String, Object?>{'index': 0, 'text': text, 'style_runs': const []},
    ],
    'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
    'viewport_rows': 24,
    'viewport_cols': 80,
    'dirty_ranges': <Object?>[
      <String, Object?>{'start': 0, 'end': 1},
    ],
    'scrollback_offset': 0,
    'scrollback_max_offset': 0,
  };
}
