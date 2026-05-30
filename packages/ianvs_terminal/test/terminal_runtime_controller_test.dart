import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_pty/ianvs_pty.dart';

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

  test('terminal viewport controller timestamps changed rows', () {
    final firstModifiedAt = DateTime.utc(2026, 5, 13, 1, 2, 3);
    final secondModifiedAt = DateTime.utc(2026, 5, 13, 1, 2, 9);
    final timestamps = <DateTime>[firstModifiedAt, secondModifiedAt];
    final controller = TerminalViewportController(
      now: () => timestamps.removeAt(0),
    );

    controller.updateFrame(
      const TerminalFrameDiff(
        rows: [
          TerminalRow(index: 0, text: 'alpha'),
          TerminalRow(index: 1, text: 'beta'),
        ],
        cursor: TerminalCursor(row: 1, col: 4, visible: true),
        viewportRows: 2,
        viewportCols: 80,
        dirtyRanges: [TerminalDirtyRange(start: 0, end: 2)],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
    );
    controller.updateFrame(
      const TerminalFrameDiff(
        frameKind: TerminalFrameKind.delta,
        rows: [TerminalRow(index: 1, text: 'beta*')],
        cursor: TerminalCursor(row: 1, col: 5, visible: true),
        viewportRows: 2,
        viewportCols: 80,
        dirtyRanges: [],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
      ),
    );

    expect(controller.frame.rows[0].modifiedAt, firstModifiedAt);
    expect(controller.frame.rows[1].modifiedAt, secondModifiedAt);
  });

  test(
    'terminal viewport controller leaves whitespace-only rows untimestamped',
    () {
      final modifiedAt = DateTime.utc(2026, 5, 13, 1, 2, 3);
      final controller = TerminalViewportController(now: () => modifiedAt);

      controller.updateFrame(
        const TerminalFrameDiff(
          rows: [
            TerminalRow(index: 0, text: '        '),
            TerminalRow(index: 1, text: 'alpha'),
          ],
          cursor: TerminalCursor(row: 1, col: 5, visible: true),
          viewportRows: 2,
          viewportCols: 80,
          dirtyRanges: [TerminalDirtyRange(start: 0, end: 2)],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
        ),
      );

      expect(controller.frame.rows[0].modifiedAt, isNull);
      expect(controller.frame.rows[1].modifiedAt, modifiedAt);
    },
  );

  test('terminal frame modes parse alternate screen hints', () {
    final modes = TerminalFrameModes.fromJson(const <String, Object?>{
      'alternate_screen': true,
    });

    expect(modes.alternateScreen, isTrue);
  });

  test('terminal frames parse row timestamp metadata', () {
    final modifiedAt = DateTime.parse('2026-05-13T08:09:10Z');
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [
        {
          'index': 0,
          'text': 'timestamped',
          'modified_at': '2026-05-13T08:09:10Z',
          'style_runs': [],
        },
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 1,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });

    expect(frame.rows.single.modifiedAt, modifiedAt);
  });

  test('terminal frames ignore invalid numeric row timestamps', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [
        {'index': 0, 'text': 'non-finite', 'modified_at': double.infinity},
        {'index': 1, 'text': 'too-large', 'modified_at': 1e100},
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 2,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 2},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });

    expect(frame.rows.map((row) => row.modifiedAt), everyElement(isNull));
  });

  test('terminal style runs degrade malformed colors', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [
        {
          'index': 0,
          'text': 'styled',
          'style_runs': [
            {
              'start': 0,
              'end': 6,
              'foreground': 'not-a-color',
              'background': '#80445566',
            },
          ],
        },
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 1,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
    });

    final run = frame.rows.single.styleRuns.single;
    expect(run.foreground, isNull);
    expect(run.background, const Color(0x80445566));
  });

  test('terminal frames skip malformed collection entries', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'frame_kind': 'delta',
      'rows': [
        'bad-row',
        {
          'index': 0,
          'text': 'ok',
          'wrapped': 'not-a-bool',
          'style_runs': [
            'bad-style',
            {'start': 0, 'end': 2, 'bold': true},
            {'start': 'bad', 'end': 2},
            {'start': 2, 'end': 3, 'underline': 'yes'},
          ],
        },
        {'index': 'bad', 'text': 'ignored'},
        {'index': 1, 'text': 42},
      ],
      'cursor': {'row': 0, 'col': 2, 'visible': true},
      'viewport_rows': 1,
      'viewport_cols': 80,
      'dirty_ranges': [
        'bad-range',
        {'start': 0, 'end': 1},
        {'start': 'bad', 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'hyperlinks': [
        'bad-link',
        {'row': 0, 'start_col': 0, 'end_col': 2, 'uri': 'https://example.com'},
        {'row': 0, 'start_col': 0, 'end_col': 2, 'uri': 7},
      ],
      'inline_images': ['bad-image'],
      'modes': {'alternate_screen': true, 'mouse_mode': 7},
    });

    expect(frame.frameKind, TerminalFrameKind.delta);
    expect(frame.rows, hasLength(1));
    expect(frame.rows.single.index, 0);
    expect(frame.rows.single.text, 'ok');
    expect(frame.rows.single.wrapped, isFalse);
    expect(frame.rows.single.styleRuns, hasLength(2));
    expect(frame.rows.single.styleRuns.first.bold, isTrue);
    expect(frame.rows.single.styleRuns.last.underline, isFalse);
    expect(frame.dirtyRanges, hasLength(1));
    expect(frame.dirtyRanges.single.start, 0);
    expect(frame.hyperlinks, hasLength(1));
    expect(frame.hyperlinks.single.uri, 'https://example.com');
    expect(frame.inlineImages, isEmpty);
    expect(frame.modes.alternateScreen, isTrue);
    expect(frame.modes.mouseMode, 'off');
  });

  test('terminal frames default malformed scalar fields', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'frame_kind': 7,
      'rows': [],
      'cursor': {'row': 'bad', 'col': 2, 'visible': true},
      'selection': {'start_row': 0, 'start_col': 'bad'},
      'viewport_rows': 'bad',
      'viewport_cols': null,
      'dirty_ranges': [],
      'scrollback_offset': 'bad',
      'scrollback_max_offset': 'bad',
      'viewport_start_row': 'bad',
      'viewport_row_shift': 'bad',
      'modes': {
        'alternate_screen': 'yes',
        'mouse_mode': false,
        'mouse_encoding': 12,
      },
      'window_title': 99,
      'window_icon_name': false,
    });

    expect(frame.frameKind, TerminalFrameKind.snapshot);
    expect(frame.cursor.row, 0);
    expect(frame.cursor.col, 0);
    expect(frame.cursor.visible, isFalse);
    expect(frame.selection, isNull);
    expect(frame.viewportRows, 0);
    expect(frame.viewportCols, 0);
    expect(frame.scrollbackOffset, 0);
    expect(frame.scrollbackMaxOffset, 0);
    expect(frame.viewportStartRow, 0);
    expect(frame.viewportRowShift, 0);
    expect(frame.modes.alternateScreen, isFalse);
    expect(frame.modes.mouseMode, 'off');
    expect(frame.modes.mouseEncoding, 'default');
    expect(frame.windowTitle, isNull);
    expect(frame.windowIconName, isNull);
  });

  test('terminal frames parse inline image payloads', () {
    final imageBytes = utf8.encode('fake-png');
    final frame = TerminalFrameDiff.fromJson(<String, Object?>{
      'rows': const [
        {'index': 0, 'text': 'image', 'style_runs': []},
      ],
      'cursor': const {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 2,
      'viewport_cols': 80,
      'dirty_ranges': const [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'inline_images': [
        {
          'row': 0,
          'col': 2,
          'width_cells': 4,
          'height_cells': 3,
          'data': base64.encode(imageBytes),
          'alt': 'preview',
        },
      ],
    });

    expect(frame.inlineImages, hasLength(1));
    expect(frame.inlineImages.single.row, 0);
    expect(frame.inlineImages.single.col, 2);
    expect(frame.inlineImages.single.widthCells, 4);
    expect(frame.inlineImages.single.heightCells, 3);
    expect(frame.inlineImages.single.bytes, imageBytes);
    expect(frame.inlineImages.single.altText, 'preview');
  });

  test('terminal frames ignore malformed inline image payloads', () {
    final frame = TerminalFrameDiff.fromJson(const <String, Object?>{
      'rows': [
        {'index': 0, 'text': 'image', 'style_runs': []},
      ],
      'cursor': {'row': 0, 'col': 0, 'visible': true},
      'viewport_rows': 2,
      'viewport_cols': 80,
      'dirty_ranges': [
        {'start': 0, 'end': 1},
      ],
      'scrollback_offset': 0,
      'scrollback_max_offset': 0,
      'inline_images': [
        {
          'row': 0,
          'col': 2,
          'width_cells': 4,
          'height_cells': 3,
          'data': 'not-valid-base64!!!',
        },
        {'row': 0, 'col': 2, 'width_cells': 4, 'height_cells': 3, 'data': 42},
      ],
    });

    expect(frame.inlineImages, isEmpty);
  });

  test(
    'terminal frames ignore oversized inline image payloads before decoding',
    () {
      final oversizedPayload = 'A' * (6 * 1024 * 1024);
      final frame = TerminalFrameDiff.fromJson(<String, Object?>{
        'rows': const [
          {'index': 0, 'text': 'image', 'style_runs': []},
        ],
        'cursor': const {'row': 0, 'col': 0, 'visible': true},
        'viewport_rows': 2,
        'viewport_cols': 80,
        'dirty_ranges': const [
          {'start': 0, 'end': 1},
        ],
        'scrollback_offset': 0,
        'scrollback_max_offset': 0,
        'inline_images': [
          {
            'row': 0,
            'col': 2,
            'width_cells': 4,
            'height_cells': 3,
            'data': oversizedPayload,
          },
        ],
      });

      expect(frame.inlineImages, isEmpty);
    },
  );

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
          'hostname': 'buildbox.local',
          'username': 'dev',
          'prompt_scrollback_offset': 17,
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
    expect(event.hostname, 'buildbox.local');
    expect(event.username, 'dev');
    expect(event.promptScrollbackOffset, 17);
    expect(event.exitCode, 7);
  });

  test('terminal shell hook payload ignores non-finite numeric fields', () {
    final event = TerminalSessionShellHookEvent(
      '1',
      rawPayload: <String, Object?>{
        'prompt_scrollback_offset': double.infinity,
        'exit_code': double.nan,
      },
    );

    expect(event.promptScrollbackOffset, isNull);
    expect(event.exitCode, isNull);
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

    final search = runtime.searchTextResult(
      sessionId,
      'ready',
      mode: TerminalSearchMode.caseInsensitiveRegex,
    );
    expect(search.matches.single.text, 'ready');
    expect(search.errorText, isNull);
    expect(runtimeBackend.jsonRequests.single, <String, Object?>{
      'kind': 'terminal.search_text',
      'query': 'ready',
      'mode': 'case_insensitive_regex',
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

  test('terminal runtime degrades malformed JSON request responses', () {
    final runtimeBackend = _FakePtyBackend()
      ..searchRawResponse = '{'
      ..selectionRawResponse = '{'
      ..clearScrollbackRawResponse = '{'
      ..scrollbackRawResponse = '{';
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

    final search = runtime.searchTextResult(sessionId, 'ready');
    expect(search.matches, isEmpty);
    expect(search.errorText, isNull);

    final text = runtime.selectionText(
      sessionId,
      const TerminalSelection(startRow: 0, startCol: 0, endRow: 0, endCol: 4),
      block: false,
    );
    expect(text, 'demo');

    expect(runtime.clearScrollback(sessionId), isFalse);
    expect(runtime.exportScrollbackText(sessionId), isNull);

    runtimeBackend
      ..selectionRawResponse = jsonEncode(<String, Object?>{'text': 42})
      ..scrollbackRawResponse = jsonEncode(<String, Object?>{'content': 42});

    final invalidText = runtime.selectionText(
      sessionId,
      const TerminalSelection(startRow: 0, startCol: 0, endRow: 0, endCol: 4),
      block: false,
    );
    expect(invalidText, 'demo');
    expect(runtime.exportScrollbackText(sessionId), isNull);
  });

  test('terminal runtime skips malformed search match entries', () {
    final runtimeBackend = _FakePtyBackend()
      ..searchRawResponse = jsonEncode(<String, Object?>{
        'matches': <Object?>[
          <String, Object?>{
            'row': 0,
            'start_col': 1,
            'end_col': 5,
            'text': 'good',
            'scrollback_offset': 2,
          },
          null,
          <String, Object?>{'row': 'bad'},
        ],
      });
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

    final search = runtime.searchTextResult(sessionId, 'ready');

    expect(search.matches.map((match) => match.text), <String>['good']);
    expect(search.errorText, isNull);
  });

  testWidgets('terminal runtime skips malformed frame payloads', (
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
    expect(runtime.viewportFor(sessionId).frame.rows.first.text, 'demo');

    runtimeBackend
      ..enqueueRawFrame(sessionId, '[]')
      ..setFrame(sessionId, _singleRowSnapshot('recovered prompt'));

    runtime.sendInput(sessionId, Uint8List(0));
    await tester.pump();
    expect(runtime.viewportFor(sessionId).frame.rows.first.text, 'demo');

    runtime.sendInput(sessionId, Uint8List(0));
    await tester.pump();
    expect(
      runtime.viewportFor(sessionId).frame.rows.first.text,
      'recovered prompt',
    );
  });

  test('terminal runtime exports diagnostics with private defaults', () {
    final runtimeBackend = _FakePtyBackend()
      ..diagnosticsResponse = <String, Object?>{
        'manifest': <String, Object?>{
          'schema_version': 'terminal-diagnostics-session-v1',
          'session_id': 1,
        },
        'resource_samples': <Object?>[
          <String, Object?>{'timestamp_micros': 1, 'rss_bytes': 100},
          <String, Object?>{'timestamp_micros': 2, 'rss_bytes': 120},
        ],
        'terminal_stats': <String, Object?>{
          'session': <String, Object?>{'bytes_read': 4},
        },
        'events': <Object?>[
          <String, Object?>{'kind': 'started'},
        ],
        'summary': <String, Object?>{
          'conclusion': 'insufficient-evidence',
          'markdown': '# Terminal diagnostics',
        },
      };
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

    final export = runtime.exportSessionDiagnostics(sessionId);

    expect(export, isNotNull);
    expect(export!.conclusion, 'insufficient-evidence');
    expect(export.resourceSamples.map((sample) => sample['rss_bytes']), [
      100,
      120,
    ]);
    expect(runtimeBackend.jsonRequests.single, <String, Object?>{
      'kind': 'terminal.export_diagnostics',
      'maxSamples': 60,
      'includeContent': false,
      'redactionMode': 'basic',
      'policy': <String, Object?>{
        'includeScrollback': false,
        'includeRawCommand': false,
        'includeRawCwd': false,
        'includeEnv': false,
      },
    });
  });

  test('terminal diagnostics export tolerates malformed summary fields', () {
    final export = TerminalDiagnosticsExport.fromJson(<String, Object?>{
      'manifest': <Object?, Object?>{
        7: 'ignored',
        'schema_version': 'terminal-diagnostics-session-v1',
      },
      'resource_samples': <Object?>[
        <Object?, Object?>{7: 'ignored', 'rss_bytes': 100},
        'bad-sample',
      ],
      'summary': <String, Object?>{'conclusion': 42, 'markdown': false},
    });

    expect(export.manifest, <String, Object?>{
      'schema_version': 'terminal-diagnostics-session-v1',
    });
    expect(export.resourceSamples, <Map<String, Object?>>[
      <String, Object?>{'rss_bytes': 100},
    ]);
    expect(export.conclusion, isNull);
    expect(export.summaryMarkdown, isNull);
  });

  test(
    'terminal runtime degrades diagnostics export to null on bad backend data',
    () {
      final runtimeBackend = _FakePtyBackend()..diagnosticsRawResponse = '{';
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

      expect(runtime.exportSessionDiagnostics(sessionId), isNull);

      runtimeBackend
        ..diagnosticsRawResponse = ''
        ..jsonRequests.clear();
      expect(runtime.exportSessionDiagnostics(sessionId), isNull);

      runtimeBackend
        ..diagnosticsRawResponse = null
        ..diagnosticsResponse = null
        ..returnNullJsonRequests = true;
      expect(runtime.exportSessionDiagnostics(sessionId), isNull);
    },
  );

  test('terminal runtime returns null diagnostics for unsupported backend', () {
    final runtimeBackend = _FrameOnlyPtyBackend();
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

    expect(runtime.exportSessionDiagnostics(sessionId), isNull);
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

  testWidgets(
    'terminal runtime controller applies resize before queued write frames',
    (tester) async {
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (_) async {},
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final timeline = <String>[];
      final eventSubscription = runtime.events.listen((event) {
        if (event is TerminalSessionFrameEvent) {
          timeline.add(
            'frame:${event.frame.viewportCols}x'
            '${event.frame.viewportRows}:'
            '${event.frame.rows.first.text}',
          );
        }
      });
      addTearDown(eventSubscription.cancel);
      final resizeSubscription = runtime.resizeEvents.listen((event) {
        timeline.add('resize:${event.cols}x${event.rows}');
      });
      addTearDown(resizeSubscription.cancel);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtime.resizeSession(sessionId, const Size(180, 144), 1);
      await tester.pump();
      timeline.clear();

      runtimeBackend.enqueueFrame(
        sessionId,
        _singleRowSnapshot(
          'write before resize',
          viewportCols: 20,
          viewportRows: 8,
        ),
      );
      runtimeBackend.setFrame(
        sessionId,
        _singleRowSnapshot('resize settled', viewportCols: 21, viewportRows: 9),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'resize',
          sessionId: sessionId,
          payload: const <String, Object?>{'cols': 21, 'rows': 9},
        ),
      );

      runtime.sendInput(sessionId, Uint8List.fromList(const [0x41]));
      await tester.pump();
      await tester.pump();

      expect(utf8.decode(runtimeBackend.writeCalls.last), 'A');
      expect(runtimeBackend.resizeCalls.last, <Object?>['1', 21, 9, 189, 162]);
      expect(timeline, <String>['resize:21x9', 'frame:21x9:resize settled']);
      expect(
        runtime.viewportFor(sessionId).frame.rows.first.text,
        'resize settled',
      );
    },
  );

  testWidgets(
    'terminal runtime controller handles OSC 52 base64 copy edge cases',
    (tester) async {
      final copiedTexts = <String>[];
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (text) async {
          copiedTexts.add(text);
        },
        readClipboard: () async => '',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final paddedPayload = base64.encode(utf8.encode('padded ok'));
      final whitespacePayload =
          '${paddedPayload.substring(0, 4)}\n ${paddedPayload.substring(4)}';

      runtimeBackend.enqueueEvent(
        sessionId,
        const PtyEvent(
          kind: 'clipboard_copy',
          sessionId: '1',
          payload: <String, Object?>{'data': 'not-valid-base64!!!'},
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: <String, Object?>{'data': whitespacePayload},
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: const <String, Object?>{'data': ''},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();

      expect(copiedTexts, <String>['padded ok', '']);
    },
  );

  testWidgets(
    'terminal runtime controller skips malformed event payload fields',
    (tester) async {
      final copiedTexts = <String>[];
      final seenEvents = <TerminalSessionEvent>[];
      final runtimeBackend = _FakePtyBackend();
      final runtime = TerminalRuntimeController(
        backend: runtimeBackend,
        copyToClipboard: (text) async {
          copiedTexts.add(text);
        },
        readClipboard: () async => 'paste me',
        enableSessionPolling: false,
      );
      addTearDown(runtime.dispose);
      final subscription = runtime.events.listen(seenEvents.add);
      addTearDown(subscription.cancel);

      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      runtime.resizeSession(sessionId, const Size(180, 144), 1);
      runtimeBackend.resizeCalls.clear();

      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: const <String, Object?>{'data': 42},
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_copy',
          sessionId: sessionId,
          payload: <String, Object?>{
            'data': base64.encode(utf8.encode('copy ok')),
          },
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'clipboard_paste_request',
          sessionId: sessionId,
          payload: const <String, Object?>{'selection': 42},
        ),
      );
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'resize',
          sessionId: sessionId,
          payload: const <String, Object?>{'cols': 'wide', 'rows': 9},
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
      runtimeBackend.enqueueEvent(
        sessionId,
        PtyEvent(
          kind: 'exit',
          sessionId: sessionId,
          payload: const <String, Object?>{'code': 'bad'},
        ),
      );

      runtime.sendInput(sessionId, Uint8List(0));
      await tester.pump();
      await tester.pump();

      expect(copiedTexts, <String>['copy ok']);
      expect(
        utf8.decode(runtimeBackend.writeCalls.last),
        '\x1B]52;c;cGFzdGUgbWU=\x07',
      );
      expect(runtimeBackend.resizeCalls, <List<Object?>>[
        <Object?>[sessionId, 21, 9, 189, 162],
      ]);
      expect(
        seenEvents.whereType<TerminalSessionExitEvent>().single.exitCode,
        isNull,
      );
      expect(runtime.hasSession(sessionId), isFalse);
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
  String? searchRawResponse;
  String? searchErrorText;
  String selectionResponse = '';
  String? selectionRawResponse;
  String? clearScrollbackRawResponse;
  String? scrollbackRawResponse;
  Map<String, Object?>? diagnosticsResponse;
  String? diagnosticsRawResponse;
  bool returnNullJsonRequests = false;

  final Map<String, Map<String, Object?>> _frames =
      <String, Map<String, Object?>>{};
  final Map<String, List<Map<String, Object?>>> _queuedFrames =
      <String, List<Map<String, Object?>>>{};
  final Map<String, List<String>> _queuedRawFrames = <String, List<String>>{};
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

  void enqueueRawFrame(String sessionId, String rawFrame) {
    _queuedRawFrames.putIfAbsent(sessionId, () => <String>[]).add(rawFrame);
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
    _queuedRawFrames.remove(sessionId);
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
      'terminal.search_text' =>
        searchRawResponse ??
            jsonEncode(<String, Object?>{
              'matches': searchResponse,
              'error_text': searchErrorText,
            }),
      'terminal.selection_text' =>
        selectionRawResponse ??
            jsonEncode(<String, Object?>{'text': selectionResponse}),
      'terminal.clear_scrollback' =>
        clearScrollbackRawResponse ??
            jsonEncode(<String, Object?>{'cleared': true}),
      'terminal.export_scrollback' =>
        scrollbackRawResponse ??
            jsonEncode(<String, Object?>{'content': 'scrollback text'}),
      'terminal.export_diagnostics' =>
        diagnosticsRawResponse ?? jsonEncode(diagnosticsResponse),
      _ => null,
    };
  }

  @override
  String? takeFrameDiffJson(String sessionId) {
    takeFrameDiffCalls += 1;
    final queuedRawFrames = _queuedRawFrames[sessionId];
    if (queuedRawFrames != null && queuedRawFrames.isNotEmpty) {
      return queuedRawFrames.removeAt(0);
    }
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

class _FrameOnlyPtyBackend implements PtySessionBackend {
  final Map<String, Map<String, Object?>> _frames =
      <String, Map<String, Object?>>{};
  int _nextSessionId = 0;

  @override
  int ping() => 1;

  @override
  String createSession(String sessionConfigJson) {
    final sessionId = (++_nextSessionId).toString();
    _frames[sessionId] = _singleRowSnapshot('demo');
    return sessionId;
  }

  @override
  void closeSession(String sessionId) {
    _frames.remove(sessionId);
  }

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
  }) {}

  @override
  void writeInput(String sessionId, List<int> bytes) {}

  @override
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {}

  @override
  String? takeFrameDiffJson(String sessionId) {
    final frame = _frames[sessionId];
    return frame == null ? null : jsonEncode(frame);
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) => const <PtyEvent>[];
}

class _StartedEventPtyBackend extends _FakePtyBackend {
  @override
  String createSession(String sessionConfigJson) {
    final sessionId = super.createSession(sessionConfigJson);
    enqueueEvent(sessionId, PtyEvent(kind: 'started', sessionId: sessionId));
    return sessionId;
  }
}

Map<String, Object?> _singleRowSnapshot(
  String text, {
  int viewportRows = 24,
  int viewportCols = 80,
}) {
  return <String, Object?>{
    'frame_kind': 'snapshot',
    'rows': <Object?>[
      <String, Object?>{'index': 0, 'text': text, 'style_runs': const []},
    ],
    'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
    'viewport_rows': viewportRows,
    'viewport_cols': viewportCols,
    'dirty_ranges': <Object?>[
      <String, Object?>{'start': 0, 'end': 1},
    ],
    'scrollback_offset': 0,
    'scrollback_max_offset': 0,
  };
}
