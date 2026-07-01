import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_pty/ianvs_pty.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';
import 'package:ianvs_terminal/src/terminal/render_terminal_viewport.dart';

void main() {
  testWidgets('terminal input controller forwards repeated backspace events', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = _runtimeFor(backend);
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    final controller = TerminalInputController(
      sessionId: sessionId,
      runtime: runtime,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(_KeyHandlerHarness(onKeyEvent: controller.handle));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);

    expect(
      backend.writeCalls.map((bytes) => bytes.toList()).toList(growable: false),
      <List<int>>[
        <int>[0x7f],
        <int>[0x7f],
      ],
    );
  });

  testWidgets('terminal input controller maps Control ASCII keys', (
    tester,
  ) async {
    final previousOverride = debugDefaultTargetPlatformOverride;
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      final backend = _FakePtyBackend();
      final runtime = _runtimeFor(backend);
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final controller = TerminalInputController(
        sessionId: sessionId,
        runtime: runtime,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        _KeyHandlerHarness(onKeyEvent: controller.handle),
      );

      const cases = <(LogicalKeyboardKey, int)>[
        (LogicalKeyboardKey.space, 0x00),
        (LogicalKeyboardKey.digit0, 0x30),
        (LogicalKeyboardKey.digit1, 0x31),
        (LogicalKeyboardKey.digit2, 0x00),
        (LogicalKeyboardKey.digit3, 0x1B),
        (LogicalKeyboardKey.digit4, 0x1C),
        (LogicalKeyboardKey.digit5, 0x1D),
        (LogicalKeyboardKey.digit6, 0x1E),
        (LogicalKeyboardKey.digit7, 0x1F),
        (LogicalKeyboardKey.digit8, 0x7F),
        (LogicalKeyboardKey.digit9, 0x39),
        (LogicalKeyboardKey.slash, 0x1F),
        (LogicalKeyboardKey.semicolon, 0x3B),
        (LogicalKeyboardKey.bracketLeft, 0x1B),
        (LogicalKeyboardKey.backslash, 0x1C),
        (LogicalKeyboardKey.bracketRight, 0x1D),
        (LogicalKeyboardKey.keyA, 0x01),
        (LogicalKeyboardKey.keyB, 0x02),
        (LogicalKeyboardKey.keyC, 0x03),
        (LogicalKeyboardKey.keyD, 0x04),
        (LogicalKeyboardKey.keyE, 0x05),
        (LogicalKeyboardKey.keyF, 0x06),
        (LogicalKeyboardKey.keyG, 0x07),
        (LogicalKeyboardKey.keyH, 0x08),
        (LogicalKeyboardKey.keyI, 0x09),
        (LogicalKeyboardKey.keyJ, 0x0A),
        (LogicalKeyboardKey.keyK, 0x0B),
        (LogicalKeyboardKey.keyL, 0x0C),
        (LogicalKeyboardKey.keyM, 0x0D),
        (LogicalKeyboardKey.keyN, 0x0E),
        (LogicalKeyboardKey.keyO, 0x0F),
        (LogicalKeyboardKey.keyP, 0x10),
        (LogicalKeyboardKey.keyQ, 0x11),
        (LogicalKeyboardKey.keyR, 0x12),
        (LogicalKeyboardKey.keyS, 0x13),
        (LogicalKeyboardKey.keyT, 0x14),
        (LogicalKeyboardKey.keyU, 0x15),
        (LogicalKeyboardKey.keyV, 0x16),
        (LogicalKeyboardKey.keyW, 0x17),
        (LogicalKeyboardKey.keyX, 0x18),
        (LogicalKeyboardKey.keyY, 0x19),
        (LogicalKeyboardKey.keyZ, 0x1A),
      ];

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      for (final (key, expectedByte) in cases) {
        await tester.sendKeyDownEvent(key);
        await tester.pump();
        await tester.sendKeyUpEvent(key);
        await tester.pump();

        expect(backend.writeCalls.last.toList(), <int>[expectedByte]);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(backend.writeCalls, hasLength(cases.length));
    } finally {
      debugDefaultTargetPlatformOverride = previousOverride;
    }
  });

  testWidgets(
    'terminal input uses Kitty keyboard disambiguation for Control-C',
    (tester) async {
      final previousOverride = debugDefaultTargetPlatformOverride;
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

        final backend = _FakePtyBackend();
        final runtime = _runtimeFor(backend);
        addTearDown(runtime.dispose);
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        final controller = TerminalInputController(
          sessionId: sessionId,
          runtime: runtime,
          readFrame: () => const TerminalFrameDiff(
            rows: [],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
            modes: TerminalFrameModes(kittyKeyboardFlags: 1),
          ),
          readSelection: () => '',
          copySelection: (_) async {},
          readClipboard: () async => '',
        );

        await tester.pumpWidget(
          _KeyHandlerHarness(onKeyEvent: controller.handle),
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

        expect(backend.writeCalls, hasLength(1));
        expect(utf8.decode(backend.writeCalls.single), '\x1B[99;5u');
      } finally {
        debugDefaultTargetPlatformOverride = previousOverride;
      }
    },
  );

  testWidgets(
    'terminal input keeps Control ASCII keys disambiguated in Kitty keyboard mode',
    (tester) async {
      final previousOverride = debugDefaultTargetPlatformOverride;
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

        final backend = _FakePtyBackend();
        final runtime = _runtimeFor(backend);
        addTearDown(runtime.dispose);
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        final controller = TerminalInputController(
          sessionId: sessionId,
          runtime: runtime,
          readFrame: () => const TerminalFrameDiff(
            rows: [],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
            modes: TerminalFrameModes(kittyKeyboardFlags: 1),
          ),
          readSelection: () => '',
          copySelection: (_) async {},
          readClipboard: () async => '',
        );

        await tester.pumpWidget(
          _KeyHandlerHarness(onKeyEvent: controller.handle),
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.digit2);
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.digit2);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

        expect(
          backend.writeCalls.map(utf8.decode).toList(growable: false),
          <String>['\x1B[32;5u', '\x1B[50;5u'],
        );
      } finally {
        debugDefaultTargetPlatformOverride = previousOverride;
      }
    },
  );

  testWidgets(
    'terminal input ignores Kitty keyboard flags outside xterm emulation',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = _runtimeFor(backend);
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final controller = TerminalInputController(
        sessionId: sessionId,
        runtime: runtime,
        emulation: TerminalEmulation.vt220,
        readFrame: () => const TerminalFrameDiff(
          rows: [],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          modes: TerminalFrameModes(kittyKeyboardFlags: 8),
        ),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        _KeyHandlerHarness(onKeyEvent: controller.handle),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW, character: 'w');
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);

      expect(backend.writeCalls, hasLength(1));
      expect(backend.writeCalls.single, utf8.encode('w'));
    },
  );

  testWidgets(
    'terminal input reads current Kitty keyboard scope for each key event',
    (tester) async {
      final previousOverride = debugDefaultTargetPlatformOverride;
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

        final backend = _FakePtyBackend();
        final runtime = _runtimeFor(backend);
        addTearDown(runtime.dispose);
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        var kittyKeyboardFlags = 0;
        final controller = TerminalInputController(
          sessionId: sessionId,
          runtime: runtime,
          readFrame: () => TerminalFrameDiff(
            rows: const [],
            cursor: const TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: const [],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
            modes: TerminalFrameModes(kittyKeyboardFlags: kittyKeyboardFlags),
          ),
          readSelection: () => '',
          copySelection: (_) async {},
          readClipboard: () async => '',
        );

        await tester.pumpWidget(
          _KeyHandlerHarness(onKeyEvent: controller.handle),
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);

        kittyKeyboardFlags = 1;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);

        kittyKeyboardFlags = 0;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

        expect(
          backend.writeCalls.map(utf8.decode).toList(growable: false),
          <String>['\x00', '\x1B[32;5u', '\x00'],
        );
      } finally {
        debugDefaultTargetPlatformOverride = previousOverride;
      }
    },
  );

  test('kitty keyboard disambiguation preserves legacy C0 exceptions', () {
    const modes = TerminalFrameModes(kittyKeyboardFlags: 1);

    expect(
      TerminalInputController.keyBytesFor(
        event: const KeyDownEvent(
          timeStamp: Duration.zero,
          physicalKey: PhysicalKeyboardKey.enter,
          logicalKey: LogicalKeyboardKey.enter,
        ),
        emulation: TerminalEmulation.xterm256,
        modes: modes,
      ),
      ascii.encode('\r'),
    );
    expect(
      TerminalInputController.keyBytesFor(
        event: const KeyDownEvent(
          timeStamp: Duration.zero,
          physicalKey: PhysicalKeyboardKey.tab,
          logicalKey: LogicalKeyboardKey.tab,
        ),
        emulation: TerminalEmulation.xterm256,
        modes: modes,
      ),
      ascii.encode('\t'),
    );
    expect(
      TerminalInputController.keyBytesFor(
        event: const KeyDownEvent(
          timeStamp: Duration.zero,
          physicalKey: PhysicalKeyboardKey.backspace,
          logicalKey: LogicalKeyboardKey.backspace,
        ),
        emulation: TerminalEmulation.xterm256,
        modes: modes,
      ),
      const <int>[0x7f],
    );
    expect(
      TerminalInputController.keyBytesFor(
        event: const KeyDownEvent(
          timeStamp: Duration.zero,
          physicalKey: PhysicalKeyboardKey.space,
          logicalKey: LogicalKeyboardKey.space,
          character: ' ',
        ),
        emulation: TerminalEmulation.xterm256,
        modes: modes,
      ),
      ascii.encode(' '),
    );
  });

  test('terminal input reports Escape in legacy and Kitty keyboard modes', () {
    expect(
      TerminalInputController.keyBytesFor(
        event: const KeyDownEvent(
          timeStamp: Duration.zero,
          physicalKey: PhysicalKeyboardKey.escape,
          logicalKey: LogicalKeyboardKey.escape,
        ),
        emulation: TerminalEmulation.xterm256,
        modes: const TerminalFrameModes(),
      ),
      ascii.encode('\x1B'),
    );
    expect(
      utf8.decode(
        TerminalInputController.keyBytesFor(
          event: const KeyDownEvent(
            timeStamp: Duration.zero,
            physicalKey: PhysicalKeyboardKey.escape,
            logicalKey: LogicalKeyboardKey.escape,
          ),
          emulation: TerminalEmulation.xterm256,
          modes: const TerminalFrameModes(kittyKeyboardFlags: 1),
        )!,
      ),
      '\x1B[27u',
    );
    expect(
      utf8.decode(
        TerminalInputController.keyBytesFor(
          event: const KeyUpEvent(
            timeStamp: Duration.zero,
            physicalKey: PhysicalKeyboardKey.escape,
            logicalKey: LogicalKeyboardKey.escape,
          ),
          emulation: TerminalEmulation.xterm256,
          modes: const TerminalFrameModes(kittyKeyboardFlags: 3),
        )!,
      ),
      '\x1B[27;1:3u',
    );
  });

  testWidgets('kitty keyboard disambiguation ignores modifier-only events', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = _runtimeFor(backend);
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    final controller = TerminalInputController(
      sessionId: sessionId,
      runtime: runtime,
      readFrame: () => const TerminalFrameDiff(
        rows: [],
        cursor: TerminalCursor(row: 0, col: 0, visible: true),
        viewportRows: 24,
        viewportCols: 80,
        dirtyRanges: [],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        modes: TerminalFrameModes(kittyKeyboardFlags: 1),
      ),
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(_KeyHandlerHarness(onKeyEvent: controller.handle));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(backend.writeCalls, isEmpty);
  });

  testWidgets('kitty keyboard disambiguation reports modified C0 keys', (
    tester,
  ) async {
    final previousOverride = debugDefaultTargetPlatformOverride;
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      final backend = _FakePtyBackend();
      final runtime = _runtimeFor(backend);
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final controller = TerminalInputController(
        sessionId: sessionId,
        runtime: runtime,
        readFrame: () => const TerminalFrameDiff(
          rows: [],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          modes: TerminalFrameModes(kittyKeyboardFlags: 1),
        ),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        _KeyHandlerHarness(onKeyEvent: controller.handle),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(
        backend.writeCalls.map(utf8.decode).toList(growable: false),
        <String>['\x1B[13;3u', '\x1B[9;6u'],
      );
    } finally {
      debugDefaultTargetPlatformOverride = previousOverride;
    }
  });

  testWidgets('kitty keyboard report-all sends modifier-only events', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = _runtimeFor(backend);
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    final controller = TerminalInputController(
      sessionId: sessionId,
      runtime: runtime,
      readFrame: () => const TerminalFrameDiff(
        rows: [],
        cursor: TerminalCursor(row: 0, col: 0, visible: true),
        viewportRows: 24,
        viewportCols: 80,
        dirtyRanges: [],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        modes: TerminalFrameModes(kittyKeyboardFlags: 8),
      ),
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(_KeyHandlerHarness(onKeyEvent: controller.handle));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(backend.writeCalls, hasLength(1));
    expect(utf8.decode(backend.writeCalls.single), '\x1B[57441;2u');
  });

  testWidgets(
    'kitty keyboard event reporting distinguishes repeat and release',
    (tester) async {
      final previousOverride = debugDefaultTargetPlatformOverride;
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

        final backend = _FakePtyBackend();
        final runtime = _runtimeFor(backend);
        addTearDown(runtime.dispose);
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        final controller = TerminalInputController(
          sessionId: sessionId,
          runtime: runtime,
          readFrame: () => const TerminalFrameDiff(
            rows: [],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
            modes: TerminalFrameModes(kittyKeyboardFlags: 3),
          ),
          readSelection: () => '',
          copySelection: (_) async {},
          readClipboard: () async => '',
        );

        await tester.pumpWidget(
          _KeyHandlerHarness(onKeyEvent: controller.handle),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

        expect(
          backend.writeCalls.map(utf8.decode).toList(growable: false),
          <String>['\x1B[99;5u', '\x1B[99;5:2u', '\x1B[99;5:3u'],
        );
      } finally {
        debugDefaultTargetPlatformOverride = previousOverride;
      }
    },
  );

  testWidgets(
    'kitty keyboard event reporting covers functional key repeats and releases',
    (tester) async {
      final previousOverride = debugDefaultTargetPlatformOverride;
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

        final backend = _FakePtyBackend();
        final runtime = _runtimeFor(backend);
        addTearDown(runtime.dispose);
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        final controller = TerminalInputController(
          sessionId: sessionId,
          runtime: runtime,
          readFrame: () => const TerminalFrameDiff(
            rows: [],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
            modes: TerminalFrameModes(kittyKeyboardFlags: 3),
          ),
          readSelection: () => '',
          copySelection: (_) async {},
          readClipboard: () async => '',
        );

        await tester.pumpWidget(
          _KeyHandlerHarness(onKeyEvent: controller.handle),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

        expect(
          backend.writeCalls.map(utf8.decode).toList(growable: false),
          <String>['\x1B[1;5A', '\x1B[1;5:2A', '\x1B[1;5:3A'],
        );
      } finally {
        debugDefaultTargetPlatformOverride = previousOverride;
      }
    },
  );

  testWidgets(
    'kitty keyboard event reporting suppresses release after macOS app shortcuts',
    (tester) async {
      final previousOverride = debugDefaultTargetPlatformOverride;
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

        final backend = _FakePtyBackend();
        final runtime = _runtimeFor(backend);
        addTearDown(runtime.dispose);
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        final controller = TerminalInputController(
          sessionId: sessionId,
          runtime: runtime,
          readFrame: () => const TerminalFrameDiff(
            rows: [],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
            modes: TerminalFrameModes(kittyKeyboardFlags: 3),
          ),
          readSelection: () => '',
          copySelection: (_) async {},
          readClipboard: () async => '',
        );

        await tester.pumpWidget(
          _KeyHandlerHarness(onKeyEvent: controller.handle),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyW);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();

        expect(backend.writeCalls, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = previousOverride;
      }
    },
  );

  testWidgets(
    'kitty keyboard event reporting keeps macOS copy shortcut out of PTY input',
    (tester) async {
      final previousOverride = debugDefaultTargetPlatformOverride;
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

        final backend = _FakePtyBackend();
        final runtime = _runtimeFor(backend);
        addTearDown(runtime.dispose);
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        var copyCount = 0;
        var copiedText = '';
        final controller = TerminalInputController(
          sessionId: sessionId,
          runtime: runtime,
          readFrame: () => const TerminalFrameDiff(
            rows: [],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
            modes: TerminalFrameModes(kittyKeyboardFlags: 3),
          ),
          readSelection: () => 'selected text',
          copySelection: (text) async {
            copyCount += 1;
            copiedText = text;
          },
          readClipboard: () async => '',
        );

        await tester.pumpWidget(
          _KeyHandlerHarness(onKeyEvent: controller.handle),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();

        expect(copyCount, 1);
        expect(copiedText, 'selected text');
        expect(backend.writeCalls, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = previousOverride;
      }
    },
  );

  testWidgets(
    'kitty keyboard event reporting suppresses release after platform paste shortcut',
    (tester) async {
      final previousOverride = debugDefaultTargetPlatformOverride;
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;

        final backend = _FakePtyBackend();
        final runtime = _runtimeFor(backend);
        addTearDown(runtime.dispose);
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        final controller = TerminalInputController(
          sessionId: sessionId,
          runtime: runtime,
          readFrame: () => const TerminalFrameDiff(
            rows: [],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
            modes: TerminalFrameModes(kittyKeyboardFlags: 3),
          ),
          readSelection: () => '',
          copySelection: (_) async {},
          readClipboard: () async => 'clip',
        );

        await tester.pumpWidget(
          _KeyHandlerHarness(onKeyEvent: controller.handle),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();

        expect(backend.writeCalls.map(utf8.decode), <String>['clip']);
      } finally {
        debugDefaultTargetPlatformOverride = previousOverride;
      }
    },
  );

  testWidgets(
    'kitty keyboard report-all reports plain key repeats and release',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = _runtimeFor(backend);
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final controller = TerminalInputController(
        sessionId: sessionId,
        runtime: runtime,
        readFrame: () => const TerminalFrameDiff(
          rows: [],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          modes: TerminalFrameModes(kittyKeyboardFlags: 10),
        ),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        _KeyHandlerHarness(onKeyEvent: controller.handle),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);

      expect(
        backend.writeCalls.map(utf8.decode).toList(growable: false),
        <String>['\x1B[119u', '\x1B[119;1:2u', '\x1B[119;1:3u'],
      );
    },
  );

  test('kitty keyboard report-event-only flag keeps legacy key output', () {
    const modes = TerminalFrameModes(kittyKeyboardFlags: 2);

    expect(
      TerminalInputController.keyBytesFor(
        event: const KeyDownEvent(
          timeStamp: Duration.zero,
          physicalKey: PhysicalKeyboardKey.keyW,
          logicalKey: LogicalKeyboardKey.keyW,
          character: 'w',
        ),
        emulation: TerminalEmulation.xterm256,
        modes: modes,
      ),
      utf8.encode('w'),
    );
    expect(
      TerminalInputController.keyBytesFor(
        event: const KeyRepeatEvent(
          timeStamp: Duration.zero,
          physicalKey: PhysicalKeyboardKey.keyW,
          logicalKey: LogicalKeyboardKey.keyW,
          character: 'w',
        ),
        emulation: TerminalEmulation.xterm256,
        modes: modes,
      ),
      utf8.encode('w'),
    );
    expect(
      TerminalInputController.keyBytesFor(
        event: const KeyUpEvent(
          timeStamp: Duration.zero,
          physicalKey: PhysicalKeyboardKey.keyW,
          logicalKey: LogicalKeyboardKey.keyW,
        ),
        emulation: TerminalEmulation.xterm256,
        modes: modes,
      ),
      isNull,
    );
  });

  testWidgets(
    'kitty keyboard report-event-only keeps legacy input path and ignores releases',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = _runtimeFor(backend);
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final controller = TerminalInputController(
        sessionId: sessionId,
        runtime: runtime,
        readFrame: () => const TerminalFrameDiff(
          rows: [],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          modes: TerminalFrameModes(kittyKeyboardFlags: 2),
        ),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        _KeyHandlerHarness(onKeyEvent: controller.handle),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW, character: 'w');
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyW, character: 'w');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);

      expect(
        backend.writeCalls.map(utf8.decode).toList(growable: false),
        <String>['w', 'w', '\x1B[A', '\x1B[A'],
      );
    },
  );

  test('kitty keyboard reports tilde functional key event metadata', () {
    const modes = TerminalFrameModes(kittyKeyboardFlags: 3);

    expect(
      utf8.decode(
        TerminalInputController.keyBytesFor(
          event: const KeyDownEvent(
            timeStamp: Duration.zero,
            physicalKey: PhysicalKeyboardKey.delete,
            logicalKey: LogicalKeyboardKey.delete,
          ),
          emulation: TerminalEmulation.xterm256,
          modes: modes,
        )!,
      ),
      '\x1B[3~',
    );
    expect(
      utf8.decode(
        TerminalInputController.keyBytesFor(
          event: const KeyRepeatEvent(
            timeStamp: Duration.zero,
            physicalKey: PhysicalKeyboardKey.delete,
            logicalKey: LogicalKeyboardKey.delete,
          ),
          emulation: TerminalEmulation.xterm256,
          modes: modes,
        )!,
      ),
      '\x1B[3;1:2~',
    );
    expect(
      utf8.decode(
        TerminalInputController.keyBytesFor(
          event: const KeyUpEvent(
            timeStamp: Duration.zero,
            physicalKey: PhysicalKeyboardKey.delete,
            logicalKey: LogicalKeyboardKey.delete,
          ),
          emulation: TerminalEmulation.xterm256,
          modes: modes,
        )!,
      ),
      '\x1B[3;1:3~',
    );
    expect(
      utf8.decode(
        TerminalInputController.keyBytesFor(
          event: const KeyRepeatEvent(
            timeStamp: Duration.zero,
            physicalKey: PhysicalKeyboardKey.f3,
            logicalKey: LogicalKeyboardKey.f3,
          ),
          emulation: TerminalEmulation.xterm256,
          modes: modes,
        )!,
      ),
      '\x1B[13;1:2~',
    );
  });

  test('kitty keyboard associated text appends codepoint payloads', () {
    const modes = TerminalFrameModes(kittyKeyboardFlags: 24);

    expect(
      utf8.decode(
        TerminalInputController.keyBytesFor(
          event: const KeyDownEvent(
            timeStamp: Duration.zero,
            physicalKey: PhysicalKeyboardKey.keyE,
            logicalKey: LogicalKeyboardKey.keyE,
            character: 'é',
          ),
          emulation: TerminalEmulation.xterm256,
          modes: modes,
        )!,
      ),
      '\x1B[101;;233u',
    );
  });

  test('kitty keyboard associated text reports non-BMP codepoints', () {
    const modes = TerminalFrameModes(kittyKeyboardFlags: 24);

    expect(
      utf8.decode(
        TerminalInputController.keyBytesFor(
          event: const KeyDownEvent(
            timeStamp: Duration.zero,
            physicalKey: PhysicalKeyboardKey.keyS,
            logicalKey: LogicalKeyboardKey.keyS,
            character: '🌟',
          ),
          emulation: TerminalEmulation.xterm256,
          modes: modes,
        )!,
      ),
      '\x1B[115;;127775u',
    );
  });

  test('kitty keyboard associated text filters control codepoints', () {
    const modes = TerminalFrameModes(kittyKeyboardFlags: 24);

    expect(
      utf8.decode(
        TerminalInputController.keyBytesFor(
          event: const KeyDownEvent(
            timeStamp: Duration.zero,
            physicalKey: PhysicalKeyboardKey.keyA,
            logicalKey: LogicalKeyboardKey.keyA,
            character: 'A\n\u{0085}B',
          ),
          emulation: TerminalEmulation.xterm256,
          modes: modes,
        )!,
      ),
      '\x1B[97;;65:66u',
    );
  });

  test('kitty keyboard associated text keeps repeat event metadata', () {
    const modes = TerminalFrameModes(kittyKeyboardFlags: 26);

    expect(
      utf8.decode(
        TerminalInputController.keyBytesFor(
          event: const KeyRepeatEvent(
            timeStamp: Duration.zero,
            physicalKey: PhysicalKeyboardKey.keyW,
            logicalKey: LogicalKeyboardKey.keyW,
            character: 'w',
          ),
          emulation: TerminalEmulation.xterm256,
          modes: modes,
        )!,
      ),
      '\x1B[119;1:2;119u',
    );
  });

  test('kitty keyboard alternate flag alone keeps legacy text', () {
    expect(
      TerminalInputController.keyBytesFor(
        event: const KeyDownEvent(
          timeStamp: Duration.zero,
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.keyA,
          character: 'a',
        ),
        emulation: TerminalEmulation.xterm256,
        modes: const TerminalFrameModes(kittyKeyboardFlags: 4),
      ),
      utf8.encode('a'),
    );
  });

  testWidgets('kitty keyboard reports shifted alternate key subfield', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = _runtimeFor(backend);
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    final controller = TerminalInputController(
      sessionId: sessionId,
      runtime: runtime,
      readFrame: () => const TerminalFrameDiff(
        rows: [],
        cursor: TerminalCursor(row: 0, col: 0, visible: true),
        viewportRows: 24,
        viewportCols: 80,
        dirtyRanges: [],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        modes: TerminalFrameModes(kittyKeyboardFlags: 12),
      ),
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(_KeyHandlerHarness(onKeyEvent: controller.handle));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA, character: 'A');
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(backend.writeCalls.map(utf8.decode), <String>[
      '\x1B[57441;2u',
      '\x1B[97:65;2u',
    ]);
  });

  testWidgets(
    'kitty keyboard keeps alternate keys with associated text metadata',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = _runtimeFor(backend);
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final controller = TerminalInputController(
        sessionId: sessionId,
        runtime: runtime,
        readFrame: () => const TerminalFrameDiff(
          rows: [],
          cursor: TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: [],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          modes: TerminalFrameModes(kittyKeyboardFlags: 28),
        ),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        _KeyHandlerHarness(onKeyEvent: controller.handle),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.equal, character: '+');
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(backend.writeCalls.map(utf8.decode), <String>[
        '\x1B[57441;2u',
        '\x1B[61:43;2;43u',
      ]);
    },
  );

  test(
    'kitty keyboard associated text does not force plain keys into CSI-u',
    () {
      expect(
        TerminalInputController.keyBytesFor(
          event: const KeyDownEvent(
            timeStamp: Duration.zero,
            physicalKey: PhysicalKeyboardKey.keyE,
            logicalKey: LogicalKeyboardKey.keyE,
            character: 'é',
          ),
          emulation: TerminalEmulation.xterm256,
          modes: const TerminalFrameModes(kittyKeyboardFlags: 17),
        ),
        utf8.encode('é'),
      );
    },
  );

  test('bracketed paste removes embedded paste markers before wrapping', () {
    final bytes = TerminalInputController.clipboardPasteBytesFor(
      emulation: TerminalEmulation.xterm256,
      modes: const TerminalFrameModes(bracketedPaste: true),
      text: 'safe\x1B[201~echo unsafe\x1B[200~tail\u{009B}201~end',
    );

    expect(utf8.decode(bytes), '\x1B[200~safeecho unsafetailend\x1B[201~');
  });

  test('bracketed paste removes zero-padded embedded paste markers', () {
    final bytes = TerminalInputController.clipboardPasteBytesFor(
      emulation: TerminalEmulation.xterm256,
      modes: const TerminalFrameModes(bracketedPaste: true),
      text: 'safe\x1B[0201~echo unsafe\u{009B}0200~tail',
    );

    expect(utf8.decode(bytes), '\x1B[200~safeecho unsafetail\x1B[201~');
  });

  test('bracketed paste keeps non-marker CSI text intact', () {
    final bytes = TerminalInputController.clipboardPasteBytesFor(
      emulation: TerminalEmulation.xterm256,
      modes: const TerminalFrameModes(bracketedPaste: true),
      text: 'keep\x1B[1;201~literal\u{009B}202~\x1B[200:1~tail',
    );

    expect(
      utf8.decode(bytes),
      '\x1B[200~keep\x1B[1;201~literal\u{009B}202~\x1B[200:1~tail\x1B[201~',
    );
  });

  test('bracketed paste preserves non-BMP text while removing markers', () {
    final bytes = TerminalInputController.clipboardPasteBytesFor(
      emulation: TerminalEmulation.xterm256,
      modes: const TerminalFrameModes(bracketedPaste: true),
      text: 'UTF-8 🌟 \x1B[201~ok',
    );

    expect(utf8.decode(bytes), '\x1B[200~UTF-8 🌟 ok\x1B[201~');
  });

  test('bracketed paste treats empty and marker-only text as no-op', () {
    expect(
      TerminalInputController.clipboardPasteBytesFor(
        emulation: TerminalEmulation.xterm256,
        modes: const TerminalFrameModes(bracketedPaste: true),
        text: '',
      ),
      isEmpty,
    );
    expect(
      TerminalInputController.clipboardPasteBytesFor(
        emulation: TerminalEmulation.xterm256,
        modes: const TerminalFrameModes(bracketedPaste: true),
        text: '\x1B[200~\x1B[201~\u{009B}200~\u{009B}201~',
      ),
      isEmpty,
    );
  });

  testWidgets(
    'bracketed paste shortcut ignores marker-only clipboard content',
    (tester) async {
      final previousOverride = debugDefaultTargetPlatformOverride;
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;

        final backend = _FakePtyBackend();
        final runtime = _runtimeFor(backend);
        addTearDown(runtime.dispose);
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        final controller = TerminalInputController(
          sessionId: sessionId,
          runtime: runtime,
          readFrame: () => const TerminalFrameDiff(
            rows: [],
            cursor: TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 24,
            viewportCols: 80,
            dirtyRanges: [],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
            modes: TerminalFrameModes(bracketedPaste: true),
          ),
          readSelection: () => '',
          copySelection: (_) async {},
          readClipboard: () async =>
              '\x1B[200~\x1B[201~\u{009B}200~\u{009B}201~',
        );

        await tester.pumpWidget(
          _KeyHandlerHarness(onKeyEvent: controller.handle),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();

        expect(backend.writeCalls, isEmpty);
        expect(backend.writeSessionCalls, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = previousOverride;
      }
    },
  );

  testWidgets('bracketed paste shortcut stays scoped to the initiating pane', (
    tester,
  ) async {
    final previousOverride = debugDefaultTargetPlatformOverride;
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;

      final backend = _FakePtyBackend();
      final runtime = _runtimeFor(backend);
      addTearDown(runtime.dispose);
      final firstSessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final secondSessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final pasteCompleter = Completer<String>();
      var firstPaneBracketedPaste = false;
      var secondPaneBracketedPaste = false;
      var clipboardReads = 0;

      TerminalFrameDiff frameFor(bool bracketedPaste) {
        return TerminalFrameDiff(
          rows: const [],
          cursor: const TerminalCursor(row: 0, col: 0, visible: true),
          viewportRows: 24,
          viewportCols: 80,
          dirtyRanges: const [],
          scrollbackOffset: 0,
          scrollbackMaxOffset: 0,
          modes: TerminalFrameModes(bracketedPaste: bracketedPaste),
        );
      }

      final firstController = TerminalInputController(
        sessionId: firstSessionId,
        runtime: runtime,
        readFrame: () => frameFor(firstPaneBracketedPaste),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () {
          clipboardReads += 1;
          return pasteCompleter.future;
        },
      );
      final secondController = TerminalInputController(
        sessionId: secondSessionId,
        runtime: runtime,
        readFrame: () => frameFor(secondPaneBracketedPaste),
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => 'second pane clipboard',
      );

      await tester.pumpWidget(
        _KeyHandlerHarness(onKeyEvent: firstController.handle),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(clipboardReads, 1);
      expect(backend.writeSessionCalls, isEmpty);

      await tester.pumpWidget(
        _KeyHandlerHarness(onKeyEvent: secondController.handle),
      );
      firstPaneBracketedPaste = true;
      secondPaneBracketedPaste = false;
      pasteCompleter.complete('safe\x1B[200~unsafe\x1B[201~');
      await tester.pump();

      expect(
        backend.writeSessionCalls
            .map((call) => (call.$1, utf8.decode(call.$2)))
            .toList(growable: false),
        <(String, String)>[(firstSessionId, '\x1B[200~safeunsafe\x1B[201~')],
      );
    } finally {
      debugDefaultTargetPlatformOverride = previousOverride;
    }
  });

  test('focus reporting is ignored until focus tracking is enabled', () {
    final backend = _FakePtyBackend();
    final runtime = _runtimeFor(backend);
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    final controller = TerminalInputController(
      sessionId: sessionId,
      runtime: runtime,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    controller.sendFocusReport(focused: true);
    controller.sendFocusReport(focused: false);

    expect(backend.writeCalls, isEmpty);
  });

  test('focus reporting sends focus in and focus out bytes when enabled', () {
    final backend = _FakePtyBackend();
    final runtime = _runtimeFor(backend);
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    final controller = TerminalInputController(
      sessionId: sessionId,
      runtime: runtime,
      readFrame: () => const TerminalFrameDiff(
        rows: [],
        cursor: TerminalCursor(row: 0, col: 0, visible: true),
        viewportRows: 24,
        viewportCols: 80,
        dirtyRanges: [],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        modes: TerminalFrameModes(focusTracking: true),
      ),
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    controller.sendFocusReport(focused: true);
    controller.sendFocusReport(focused: false);

    expect(
      backend.writeCalls.map(ascii.decode).toList(growable: false),
      <String>['\x1B[I', '\x1B[O'],
    );
  });

  test('focus reporting ignores xterm focus mode outside xterm emulation', () {
    final backend = _FakePtyBackend();
    final runtime = _runtimeFor(backend);
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    final controller = TerminalInputController(
      sessionId: sessionId,
      runtime: runtime,
      emulation: TerminalEmulation.vt220,
      readFrame: () => const TerminalFrameDiff(
        rows: [],
        cursor: TerminalCursor(row: 0, col: 0, visible: true),
        viewportRows: 24,
        viewportCols: 80,
        dirtyRanges: [],
        scrollbackOffset: 0,
        scrollbackMaxOffset: 0,
        modes: TerminalFrameModes(focusTracking: true),
      ),
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    controller.sendFocusReport(focused: true);
    controller.sendFocusReport(focused: false);

    expect(backend.writeCalls, isEmpty);
  });

  testWidgets(
    'terminal viewport sends focus tracking reports on focus changes',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = _runtimeFor(backend);
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final focusNode = FocusNode(debugLabel: 'focus-tracking-terminal');
      final otherFocusNode = FocusNode(debugLabel: 'other-focus-target');
      final selectionController = SelectionController();
      addTearDown(focusNode.dispose);
      addTearDown(otherFocusNode.dispose);
      addTearDown(selectionController.dispose);
      final viewportController = TerminalViewportController()
        ..applySnapshot(
          TerminalFrameDiff.fromJson(<String, Object?>{
            ..._singleRowSnapshot(),
            'modes': const <String, Object?>{'focus_tracking': true},
          }),
        );
      final inputController = TerminalInputController(
        sessionId: sessionId,
        runtime: runtime,
        readFrame: () => viewportController.frame,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              SizedBox(
                width: 240,
                height: 120,
                child: TerminalViewport(
                  focusNode: focusNode,
                  controller: viewportController,
                  selectionController: selectionController,
                  inputController: inputController,
                  onScrollLines: (_) {},
                  onScrollToOffset: (_) {},
                ),
              ),
              Focus(
                focusNode: otherFocusNode,
                child: const SizedBox(width: 1, height: 1),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      focusNode.requestFocus();
      await tester.pump();
      otherFocusNode.requestFocus();
      await tester.pump();

      expect(
        backend.writeCalls.map(ascii.decode).toList(growable: false),
        <String>['\x1B[I', '\x1B[O'],
      );
    },
  );

  testWidgets('terminal viewport scopes focus reports across panes', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = _runtimeFor(backend);
    addTearDown(runtime.dispose);
    final firstSessionId = runtime.createSession(
      const TerminalSessionConfig(launch: TerminalLaunchConfig(program: 'sh')),
    );
    final secondSessionId = runtime.createSession(
      const TerminalSessionConfig(launch: TerminalLaunchConfig(program: 'zsh')),
    );
    final firstFocusNode = FocusNode(debugLabel: 'first-terminal-pane');
    final secondFocusNode = FocusNode(debugLabel: 'second-terminal-pane');
    final firstSelectionController = SelectionController();
    final secondSelectionController = SelectionController();
    addTearDown(firstFocusNode.dispose);
    addTearDown(secondFocusNode.dispose);
    addTearDown(firstSelectionController.dispose);
    addTearDown(secondSelectionController.dispose);

    final firstViewportController = TerminalViewportController()
      ..applySnapshot(
        TerminalFrameDiff.fromJson(<String, Object?>{
          ..._singleRowSnapshot(),
          'modes': const <String, Object?>{'focus_tracking': true},
        }),
      );
    final secondViewportController = TerminalViewportController()
      ..applySnapshot(
        TerminalFrameDiff.fromJson(<String, Object?>{
          ..._singleRowSnapshot(),
          'modes': const <String, Object?>{'focus_tracking': true},
        }),
      );
    final firstInputController = TerminalInputController(
      sessionId: firstSessionId,
      runtime: runtime,
      readFrame: () => firstViewportController.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );
    final secondInputController = TerminalInputController(
      sessionId: secondSessionId,
      runtime: runtime,
      readFrame: () => secondViewportController.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            SizedBox(
              width: 240,
              height: 120,
              child: TerminalViewport(
                focusNode: firstFocusNode,
                controller: firstViewportController,
                selectionController: firstSelectionController,
                inputController: firstInputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
            SizedBox(
              width: 240,
              height: 120,
              child: TerminalViewport(
                focusNode: secondFocusNode,
                controller: secondViewportController,
                selectionController: secondSelectionController,
                inputController: secondInputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    firstFocusNode.requestFocus();
    await tester.pump();
    secondFocusNode.requestFocus();
    await tester.pump();

    expect(
      backend.writeSessionCalls
          .map((call) => (call.$1, ascii.decode(call.$2)))
          .toList(growable: false),
      <(String, String)>[
        (firstSessionId, '\x1B[I'),
        (firstSessionId, '\x1B[O'),
        (secondSessionId, '\x1B[I'),
      ],
    );
  });

  testWidgets(
    'terminal viewport reports focus out when unmounted while focused',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = _runtimeFor(backend);
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final focusNode = FocusNode(debugLabel: 'unmounted-focus-terminal');
      final selectionController = SelectionController();
      addTearDown(focusNode.dispose);
      addTearDown(selectionController.dispose);
      final viewportController = TerminalViewportController()
        ..applySnapshot(
          TerminalFrameDiff.fromJson(<String, Object?>{
            ..._singleRowSnapshot(),
            'modes': const <String, Object?>{'focus_tracking': true},
          }),
        );
      final inputController = TerminalInputController(
        sessionId: sessionId,
        runtime: runtime,
        readFrame: () => viewportController.frame,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 240,
            height: 120,
            child: TerminalViewport(
              focusNode: focusNode,
              controller: viewportController,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      focusNode.requestFocus();
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(
        backend.writeCalls.map(ascii.decode).toList(growable: false),
        <String>['\x1B[I', '\x1B[O'],
      );
    },
  );

  group('mouse reporting', () {
    test('encodes SGR press and release bytes with modifiers', () {
      const modes = TerminalFrameModes(
        mouseMode: 'button_event',
        mouseEncoding: 'sgr',
      );

      expect(
        ascii.decode(
          TerminalInputController.mouseReportBytesFor(
            modes: modes,
            row: 2,
            col: 4,
            button: 0,
            pressed: true,
            modifiers: 5,
          ),
        ),
        '\x1B[<20;5;3M',
      );
      expect(
        ascii.decode(
          TerminalInputController.mouseReportBytesFor(
            modes: modes,
            row: 2,
            col: 4,
            button: 0,
            pressed: false,
            modifiers: 5,
          ),
        ),
        '\x1B[<20;5;3m',
      );
    });

    test('encodes SGR pixel bytes with viewport-local pixel coordinates', () {
      const modes = TerminalFrameModes(
        mouseMode: 'normal',
        mouseEncoding: 'sgr_pixels',
      );

      expect(
        ascii.decode(
          TerminalInputController.mouseReportBytesFor(
            modes: modes,
            row: 2,
            col: 4,
            pixelX: 57,
            pixelY: 23,
            button: 0,
            pressed: true,
            modifiers: 1,
          ),
        ),
        '\x1B[<4;58;24M',
      );
      expect(
        ascii.decode(
          TerminalInputController.mouseReportBytesFor(
            modes: modes,
            row: 2,
            col: 4,
            button: 0,
            pressed: false,
          ),
        ),
        '\x1B[<0;5;3m',
      );
    });

    test('clamps negative mouse coordinates before encoding reports', () {
      expect(
        ascii.decode(
          TerminalInputController.mouseReportBytesFor(
            modes: const TerminalFrameModes(
              mouseMode: 'normal',
              mouseEncoding: 'sgr',
            ),
            row: -3,
            col: -4,
            button: 0,
            pressed: true,
          ),
        ),
        '\x1B[<0;1;1M',
      );
      expect(
        ascii.decode(
          TerminalInputController.mouseReportBytesFor(
            modes: const TerminalFrameModes(
              mouseMode: 'normal',
              mouseEncoding: 'sgr_pixels',
            ),
            row: 1,
            col: 2,
            pixelX: -10,
            pixelY: -12,
            button: 0,
            pressed: true,
          ),
        ),
        '\x1B[<0;1;1M',
      );
      expect(
        ascii.decode(
          TerminalInputController.mouseReportBytesFor(
            modes: const TerminalFrameModes(
              mouseMode: 'normal',
              mouseEncoding: 'urxvt',
            ),
            row: -2,
            col: -1,
            button: 0,
            pressed: true,
          ),
        ),
        '\x1B[32;1;1M',
      );
      expect(
        TerminalInputController.mouseReportBytesFor(
          modes: const TerminalFrameModes(mouseMode: 'normal'),
          row: -2,
          col: -1,
          button: 0,
          pressed: true,
        ),
        <int>[0x1b, 0x5b, 0x4d, 32, 33, 33],
      );
      final utf8Bytes = TerminalInputController.mouseReportBytesFor(
        modes: const TerminalFrameModes(
          mouseMode: 'normal',
          mouseEncoding: 'utf8',
        ),
        row: -2,
        col: -1,
        button: 0,
        pressed: true,
      );
      expect(
        utf8.decode(utf8Bytes.skip(4).toList(growable: false)),
        String.fromCharCodes([33, 33]),
      );
    });

    test('limits mouse modifiers to xterm shift alt control bits', () {
      expect(
        ascii.decode(
          TerminalInputController.mouseReportBytesFor(
            modes: const TerminalFrameModes(
              mouseMode: 'normal',
              mouseEncoding: 'sgr',
            ),
            row: 0,
            col: 0,
            button: 0,
            pressed: true,
            modifiers: 0xff,
          ),
        ),
        '\x1B[<28;1;1M',
      );
      expect(
        TerminalInputController.mouseReportBytesFor(
          modes: const TerminalFrameModes(mouseMode: 'normal'),
          row: 0,
          col: 0,
          button: 0,
          pressed: true,
          modifiers: 0xff,
        ),
        <int>[0x1b, 0x5b, 0x4d, 60, 33, 33],
      );
    });

    test('encodes URXVT release bytes', () {
      final bytes = TerminalInputController.mouseReportBytesFor(
        modes: const TerminalFrameModes(
          mouseMode: 'normal',
          mouseEncoding: 'urxvt',
        ),
        row: 3,
        col: 6,
        button: 0,
        pressed: false,
      );

      expect(ascii.decode(bytes), '\x1B[35;7;4M');
    });

    test('clamps default X10 coordinates to single-byte bounds', () {
      final bytes = TerminalInputController.mouseReportBytesFor(
        modes: const TerminalFrameModes(mouseMode: 'normal'),
        row: 400,
        col: 500,
        button: 0,
        pressed: true,
      );

      expect(bytes, <int>[0x1b, 0x5b, 0x4d, 32, 255, 255]);
    });

    test('encodes UTF-8 coordinates beyond default X10 bounds', () {
      final bytes = TerminalInputController.mouseReportBytesFor(
        modes: const TerminalFrameModes(
          mouseMode: 'normal',
          mouseEncoding: 'utf8',
        ),
        row: 301,
        col: 300,
        button: 0,
        pressed: true,
      );

      expect(bytes.take(4).toList(growable: false), <int>[
        0x1b,
        0x5b,
        0x4d,
        32,
      ]);
      expect(
        utf8.decode(bytes.skip(4).toList()),
        String.fromCharCodes([333, 334]),
      );
    });

    test('treats X10 mouse mode as ordinary press-only reporting', () {
      const modes = TerminalFrameModes(mouseMode: 'x10', mouseEncoding: 'sgr');

      expect(
        ascii.decode(
          TerminalInputController.mouseReportBytesFor(
            modes: modes,
            row: 0,
            col: 0,
            button: 0,
            pressed: true,
          ),
        ),
        '\x1B[<0;1;1M',
      );
      expect(
        TerminalInputController.mouseReportBytesFor(
          modes: modes,
          row: 0,
          col: 0,
          button: 0,
          pressed: false,
        ),
        isEmpty,
      );
      expect(
        TerminalInputController.mouseReportBytesFor(
          modes: modes,
          row: 0,
          col: 0,
          button: 32,
          pressed: true,
        ),
        isEmpty,
      );
      expect(
        TerminalInputController.mouseReportBytesFor(
          modes: modes,
          row: 0,
          col: 0,
          button: 64,
          pressed: true,
        ),
        isEmpty,
      );
    });

    test('filters mouse motion by tracking mode', () {
      const normal = TerminalFrameModes(
        mouseMode: 'normal',
        mouseEncoding: 'sgr',
      );
      const buttonEvent = TerminalFrameModes(
        mouseMode: 'button_event',
        mouseEncoding: 'sgr',
      );
      const anyEvent = TerminalFrameModes(
        mouseMode: 'any_event',
        mouseEncoding: 'sgr',
      );

      expect(
        TerminalInputController.mouseReportBytesFor(
          modes: normal,
          row: 0,
          col: 0,
          button: 32,
          pressed: true,
        ),
        isEmpty,
      );
      expect(
        TerminalInputController.mouseReportBytesFor(
          modes: normal,
          row: 0,
          col: 0,
          button: 35,
          pressed: true,
        ),
        isEmpty,
      );
      expect(
        ascii.decode(
          TerminalInputController.mouseReportBytesFor(
            modes: normal,
            row: 0,
            col: 0,
            button: 64,
            pressed: true,
          ),
        ),
        '\x1B[<64;1;1M',
      );

      expect(
        ascii.decode(
          TerminalInputController.mouseReportBytesFor(
            modes: buttonEvent,
            row: 0,
            col: 0,
            button: 32,
            pressed: true,
          ),
        ),
        '\x1B[<32;1;1M',
      );
      expect(
        TerminalInputController.mouseReportBytesFor(
          modes: buttonEvent,
          row: 0,
          col: 0,
          button: 35,
          pressed: true,
        ),
        isEmpty,
      );

      expect(
        ascii.decode(
          TerminalInputController.mouseReportBytesFor(
            modes: anyEvent,
            row: 0,
            col: 0,
            button: 35,
            pressed: true,
          ),
        ),
        '\x1B[<35;1;1M',
      );
    });

    test('filters wheel releases because wheel reports are press-only', () {
      const sgrModes = TerminalFrameModes(
        mouseMode: 'normal',
        mouseEncoding: 'sgr',
      );

      expect(
        ascii.decode(
          TerminalInputController.mouseReportBytesFor(
            modes: sgrModes,
            row: 0,
            col: 0,
            button: 64,
            pressed: true,
          ),
        ),
        '\x1B[<64;1;1M',
      );
      expect(
        TerminalInputController.mouseReportBytesFor(
          modes: sgrModes,
          row: 0,
          col: 0,
          button: 64,
          pressed: false,
        ),
        isEmpty,
      );
      expect(
        TerminalInputController.mouseReportBytesFor(
          modes: const TerminalFrameModes(mouseMode: 'normal'),
          row: 0,
          col: 0,
          button: 65,
          pressed: false,
        ),
        isEmpty,
      );
    });

    test('does not encode bytes when mouse mode is off', () {
      final bytes = TerminalInputController.mouseReportBytesFor(
        modes: const TerminalFrameModes(mouseMode: 'off', mouseEncoding: 'sgr'),
        row: 0,
        col: 0,
        button: 0,
        pressed: true,
      );

      expect(bytes, isEmpty);
    });

    test('does not send bytes while mouse mode is off', () {
      final backend = _FakePtyBackend();
      final runtime = _runtimeFor(backend);
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final controller = TerminalInputController(
        sessionId: sessionId,
        runtime: runtime,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      controller.sendMouseReport(
        modes: const TerminalFrameModes(mouseMode: 'off'),
        row: 0,
        col: 0,
        button: 0,
        pressed: true,
      );
      controller.sendMouseReport(
        modes: const TerminalFrameModes(
          mouseMode: 'normal',
          mouseEncoding: 'sgr',
        ),
        row: 0,
        col: 0,
        button: 0,
        pressed: true,
      );

      expect(backend.writeCalls, hasLength(1));
      expect(ascii.decode(backend.writeCalls.single), '\x1B[<0;1;1M');
    });

    test('sends SGR pixel report bytes with pixel coordinates', () {
      final backend = _FakePtyBackend();
      final runtime = _runtimeFor(backend);
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final controller = TerminalInputController(
        sessionId: sessionId,
        runtime: runtime,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      controller.sendMouseReport(
        modes: const TerminalFrameModes(
          mouseMode: 'normal',
          mouseEncoding: 'sgr_pixels',
        ),
        row: 1,
        col: 2,
        pixelX: 31,
        pixelY: 12,
        button: 0,
        pressed: true,
      );

      expect(backend.writeCalls, hasLength(1));
      expect(ascii.decode(backend.writeCalls.single), '\x1B[<0;32;13M');
    });
  });

  testWidgets('terminal viewport sends SGR pixel mouse coordinates', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = _runtimeFor(backend);
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    final viewportController = TerminalViewportController()
      ..applySnapshot(
        TerminalFrameDiff.fromJson(<String, Object?>{
          ..._singleRowSnapshot(),
          'modes': const <String, Object?>{
            'mouse_mode': 'normal',
            'mouse_encoding': 'sgr_pixels',
          },
        }),
      );
    final selectionController = SelectionController();
    addTearDown(selectionController.dispose);
    final inputController = TerminalInputController(
      sessionId: sessionId,
      runtime: runtime,
      readFrame: () => viewportController.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            height: 80,
            child: TerminalViewport(
              controller: viewportController,
              selectionController: selectionController,
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final renderObject = tester.renderObject<RenderTerminalViewport>(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_TerminalViewportSurface',
      ),
    );
    const localPosition = Offset(37.6, 18.4);
    final globalPosition = renderObject.localToGlobal(localPosition);
    final pointer = TestPointer(11, ui.PointerDeviceKind.mouse);

    await tester.sendEventToBinding(pointer.down(globalPosition));
    await tester.pump();
    await tester.sendEventToBinding(pointer.up());
    await tester.pump();

    expect(
      backend.writeCalls.map(ascii.decode).toList(growable: false),
      <String>['\x1B[<0;38;19M', '\x1B[<0;38;19m'],
    );
  });

  testWidgets('terminal viewport scopes mouse reports across panes', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = _runtimeFor(backend);
    addTearDown(runtime.dispose);
    final firstSessionId = runtime.createSession(
      const TerminalSessionConfig(launch: TerminalLaunchConfig(program: 'sh')),
    );
    final secondSessionId = runtime.createSession(
      const TerminalSessionConfig(launch: TerminalLaunchConfig(program: 'zsh')),
    );
    final firstSelectionController = SelectionController();
    final secondSelectionController = SelectionController();
    addTearDown(firstSelectionController.dispose);
    addTearDown(secondSelectionController.dispose);

    TerminalViewportController mouseViewportController() {
      return TerminalViewportController()..applySnapshot(
        TerminalFrameDiff.fromJson(<String, Object?>{
          ..._singleRowSnapshot(),
          'modes': const <String, Object?>{
            'mouse_mode': 'normal',
            'mouse_encoding': 'sgr',
          },
        }),
      );
    }

    final firstViewportController = mouseViewportController();
    final secondViewportController = mouseViewportController();
    final firstInputController = TerminalInputController(
      sessionId: firstSessionId,
      runtime: runtime,
      readFrame: () => firstViewportController.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );
    final secondInputController = TerminalInputController(
      sessionId: secondSessionId,
      runtime: runtime,
      readFrame: () => secondViewportController.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            SizedBox(
              width: 180,
              height: 80,
              child: TerminalViewport(
                controller: firstViewportController,
                selectionController: firstSelectionController,
                inputController: firstInputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
            SizedBox(
              width: 180,
              height: 80,
              child: TerminalViewport(
                controller: secondViewportController,
                selectionController: secondSelectionController,
                inputController: secondInputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    final surfaceRenderObjects = find
        .byWidgetPredicate(
          (widget) =>
              widget.runtimeType.toString() == '_TerminalViewportSurface',
        )
        .evaluate()
        .map((element) => element.findRenderObject())
        .whereType<RenderTerminalViewport>()
        .toList(growable: false);
    expect(surfaceRenderObjects, hasLength(2));
    final secondRenderObject = surfaceRenderObjects[1];
    final cellSize = secondRenderObject.debugCellSize;
    final pointerPosition = secondRenderObject.localToGlobal(
      Offset(cellSize.width * 1.5, cellSize.height * 0.5),
    );
    final pointer = TestPointer(12, ui.PointerDeviceKind.mouse);

    await tester.sendEventToBinding(pointer.down(pointerPosition));
    await tester.pump();
    await tester.sendEventToBinding(pointer.up());
    await tester.pump();

    expect(
      backend.writeSessionCalls
          .map((call) => (call.$1, ascii.decode(call.$2)))
          .toList(growable: false),
      <(String, String)>[
        (secondSessionId, '\x1B[<0;2;1M'),
        (secondSessionId, '\x1B[<0;2;1m'),
      ],
    );
  });

  testWidgets('terminal viewport releases mouse at last in-bounds cell', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = _runtimeFor(backend);
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    final viewportController = TerminalViewportController()
      ..applySnapshot(
        TerminalFrameDiff.fromJson(<String, Object?>{
          ..._singleRowSnapshot(),
          'modes': const <String, Object?>{
            'mouse_mode': 'button_event',
            'mouse_encoding': 'sgr',
          },
        }),
      );
    final inputController = TerminalInputController(
      sessionId: sessionId,
      runtime: runtime,
      readFrame: () => viewportController.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            height: 80,
            child: TerminalViewport(
              controller: viewportController,
              selectionController: SelectionController(),
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final renderObject = tester.renderObject<RenderTerminalViewport>(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_TerminalViewportSurface',
      ),
    );
    final cellSize = renderObject.debugCellSize;
    final pressPosition = renderObject.localToGlobal(
      Offset(cellSize.width * 2.5, cellSize.height * 0.5),
    );
    final outsidePosition = renderObject.localToGlobal(
      Offset(renderObject.size.width + cellSize.width * 4, cellSize.height),
    );
    final pointer = TestPointer(1, ui.PointerDeviceKind.mouse);

    await tester.sendEventToBinding(pointer.down(pressPosition));
    await tester.pump();
    await tester.sendEventToBinding(pointer.move(outsidePosition));
    await tester.pump();
    await tester.sendEventToBinding(
      PointerUpEvent(
        pointer: pointer.pointer,
        position: outsidePosition,
        kind: ui.PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();

    expect(
      backend.writeCalls.map(ascii.decode).toList(growable: false),
      <String>['\x1B[<0;3;1M', '\x1B[<0;3;1m'],
    );
  });

  testWidgets('terminal viewport suppresses motion in normal mouse mode', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = _runtimeFor(backend);
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    final viewportController = TerminalViewportController()
      ..applySnapshot(
        TerminalFrameDiff.fromJson(<String, Object?>{
          ..._singleRowSnapshot(),
          'modes': const <String, Object?>{
            'mouse_mode': 'normal',
            'mouse_encoding': 'sgr',
          },
        }),
      );
    final inputController = TerminalInputController(
      sessionId: sessionId,
      runtime: runtime,
      readFrame: () => viewportController.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            height: 80,
            child: TerminalViewport(
              controller: viewportController,
              selectionController: SelectionController(),
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final renderObject = tester.renderObject<RenderTerminalViewport>(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_TerminalViewportSurface',
      ),
    );
    final cellSize = renderObject.debugCellSize;
    final pressPosition = renderObject.localToGlobal(
      Offset(cellSize.width * 1.5, cellSize.height * 0.5),
    );
    final movePosition = renderObject.localToGlobal(
      Offset(cellSize.width * 4.5, cellSize.height * 1.5),
    );
    final pointer = TestPointer(3, ui.PointerDeviceKind.mouse);

    await tester.sendEventToBinding(pointer.down(pressPosition));
    await tester.pump();
    await tester.sendEventToBinding(pointer.move(movePosition));
    await tester.pump();
    await tester.sendEventToBinding(pointer.up());
    await tester.pump();
    await tester.sendEventToBinding(pointer.hover(movePosition));
    await tester.pump();

    expect(
      backend.writeCalls.map(ascii.decode).toList(growable: false),
      <String>['\x1B[<0;2;1M', '\x1B[<0;5;2m'],
    );
  });

  testWidgets(
    'terminal viewport ignores mouse reports outside the terminal surface',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = _runtimeFor(backend);
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final viewportController = TerminalViewportController()
        ..applySnapshot(
          TerminalFrameDiff.fromJson(<String, Object?>{
            ..._singleRowSnapshot(),
            'modes': const <String, Object?>{
              'mouse_mode': 'any_event',
              'mouse_encoding': 'sgr',
            },
          }),
        );
      final inputController = TerminalInputController(
        sessionId: sessionId,
        runtime: runtime,
        readFrame: () => viewportController.frame,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              height: 80,
              child: TerminalViewport(
                controller: viewportController,
                selectionController: SelectionController(),
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
                contentPadding: const EdgeInsets.only(left: 24, top: 12),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final renderObject = tester.renderObject<RenderTerminalViewport>(
        find.byWidgetPredicate(
          (widget) =>
              widget.runtimeType.toString() == '_TerminalViewportSurface',
        ),
      );
      final cellSize = renderObject.debugCellSize;
      final paddingPosition = renderObject.localToGlobal(
        Offset(-8, cellSize.height * 0.5),
      );
      final insidePosition = renderObject.localToGlobal(
        Offset(cellSize.width * 1.5, cellSize.height * 0.5),
      );
      final pointer = TestPointer(2, ui.PointerDeviceKind.mouse);

      await tester.sendEventToBinding(pointer.hover(paddingPosition));
      await tester.pump();
      await tester.sendEventToBinding(pointer.down(paddingPosition));
      await tester.pump();
      await tester.sendEventToBinding(pointer.up());
      await tester.pump();

      expect(backend.writeCalls, isEmpty);

      await tester.sendEventToBinding(pointer.hover(insidePosition));
      await tester.pump();

      expect(
        backend.writeCalls.map(ascii.decode).toList(growable: false),
        <String>['\x1B[<35;2;1M'],
      );
    },
  );

  testWidgets(
    'terminal viewport sends cursor keys for alternate-screen scroll',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = _runtimeFor(backend);
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final viewportController = TerminalViewportController()
        ..applySnapshot(
          TerminalFrameDiff.fromJson(<String, Object?>{
            ..._singleRowSnapshot(),
            'modes': const <String, Object?>{
              'alternate_screen': true,
              'alternate_scroll': true,
              'application_cursor': true,
            },
          }),
        );
      final inputController = TerminalInputController(
        sessionId: sessionId,
        runtime: runtime,
        readFrame: () => viewportController.frame,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );
      final scrollLines = <int>[];
      final selectionController = SelectionController();
      addTearDown(selectionController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              height: 80,
              child: TerminalViewport(
                controller: viewportController,
                selectionController: selectionController,
                inputController: inputController,
                onScrollLines: scrollLines.add,
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final renderObject = tester.renderObject<RenderTerminalViewport>(
        find.byWidgetPredicate(
          (widget) =>
              widget.runtimeType.toString() == '_TerminalViewportSurface',
        ),
      );
      final cellSize = renderObject.debugCellSize;
      final position = renderObject.localToGlobal(
        Offset(cellSize.width * 2, cellSize.height / 2),
      );

      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: Offset(0, -cellSize.height),
          kind: ui.PointerDeviceKind.mouse,
        ),
      );
      await tester.pump();
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: Offset(0, cellSize.height * 2),
          kind: ui.PointerDeviceKind.mouse,
        ),
      );
      await tester.pump();

      expect(scrollLines, isEmpty);
      expect(
        backend.writeCalls.map(ascii.decode).toList(growable: false),
        <String>['\x1BOA', '\x1BOB\x1BOB'],
      );
    },
  );

  testWidgets('terminal viewport forwards repeated backspace events', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = _runtimeFor(backend);
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    final viewportController = TerminalViewportController()
      ..applySnapshot(TerminalFrameDiff.fromJson(_singleRowSnapshot()));
    final inputController = TerminalInputController(
      sessionId: sessionId,
      runtime: runtime,
      readFrame: () => viewportController.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 240,
            child: TerminalViewport(
              controller: viewportController,
              selectionController: SelectionController(),
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);

    expect(
      backend.writeCalls.map((bytes) => bytes.toList()).toList(growable: false),
      <List<int>>[
        <int>[0x7f],
        <int>[0x7f],
      ],
    );
  });

  testWidgets('terminal viewport forwards Kitty keyboard release events', (
    tester,
  ) async {
    final backend = _FakePtyBackend();
    final runtime = _runtimeFor(backend);
    addTearDown(runtime.dispose);
    final sessionId = runtime.createSession(
      const TerminalSessionConfig(
        launch: TerminalLaunchConfig(program: '/bin/sh'),
      ),
    );
    final viewportController = TerminalViewportController()
      ..applySnapshot(
        TerminalFrameDiff.fromJson(<String, Object?>{
          ..._singleRowSnapshot(),
          'modes': const <String, Object?>{'kitty_keyboard_flags': 10},
        }),
      );
    final inputController = TerminalInputController(
      sessionId: sessionId,
      runtime: runtime,
      readFrame: () => viewportController.frame,
      readSelection: () => '',
      copySelection: (_) async {},
      readClipboard: () async => '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 240,
            child: TerminalViewport(
              controller: viewportController,
              selectionController: SelectionController(),
              inputController: inputController,
              onScrollLines: (_) {},
              onScrollToOffset: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);

    expect(
      backend.writeCalls.map(utf8.decode).toList(growable: false),
      <String>['\x1B[119u', '\x1B[119;1:3u'],
    );
  });

  testWidgets('terminal viewport forwards raw ASCII IME composition on enter', (
    tester,
  ) async {
    final previousOverride = debugDefaultTargetPlatformOverride;
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      final backend = _FakePtyBackend();
      final runtime = _runtimeFor(backend);
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final viewportController = TerminalViewportController()
        ..applySnapshot(TerminalFrameDiff.fromJson(_singleRowSnapshot()));
      final inputController = TerminalInputController(
        sessionId: sessionId,
        runtime: runtime,
        readFrame: () => viewportController.frame,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 240,
              child: TerminalViewport(
                controller: viewportController,
                selectionController: SelectionController(),
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP, character: 'p');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'p',
          composing: TextRange(start: 0, end: 1),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW, character: 'w');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'p w',
          composing: TextRange(start: 0, end: 3),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD, character: 'd');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'p w d',
          composing: TextRange(start: 0, end: 5),
        ),
      );
      await tester.pump();

      expect(backend.writeCalls, isEmpty);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'p w d',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump();

      expect(
        backend.writeCalls.map(utf8.decode).toList(growable: false),
        <String>['pwd'],
      );
    } finally {
      debugDefaultTargetPlatformOverride = previousOverride;
    }
  });

  testWidgets(
    'terminal viewport keeps IME composing background off inline images',
    (tester) async {
      final backend = _FakePtyBackend();
      final runtime = _runtimeFor(backend);
      addTearDown(runtime.dispose);
      final sessionId = runtime.createSession(
        const TerminalSessionConfig(
          launch: TerminalLaunchConfig(program: '/bin/sh'),
        ),
      );
      final imageBytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
        'AAAADUlEQVR42mP8z8BQDwAFgwJ/lBnJ3wAAAABJRU5ErkJggg==',
      );
      final viewportController = TerminalViewportController()
        ..updateFrame(
          TerminalFrameDiff(
            rows: const [TerminalRow(index: 0, text: '')],
            cursor: const TerminalCursor(row: 0, col: 0, visible: true),
            viewportRows: 1,
            viewportCols: 40,
            dirtyRanges: const [TerminalDirtyRange(start: 0, end: 1)],
            scrollbackOffset: 0,
            scrollbackMaxOffset: 0,
            inlineImages: [
              TerminalInlineImage(
                row: 0,
                col: 10,
                widthCells: 4,
                heightCells: 1,
                bytes: imageBytes,
              ),
            ],
          ),
        );
      final inputController = TerminalInputController(
        sessionId: sessionId,
        runtime: runtime,
        readFrame: () => viewportController.frame,
        readSelection: () => '',
        copySelection: (_) async {},
        readClipboard: () async => '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 160,
              child: TerminalViewport(
                controller: viewportController,
                selectionController: SelectionController(),
                inputController: inputController,
                onScrollLines: (_) {},
                onScrollToOffset: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TerminalViewport));
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'sa',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();

      final composingRect = tester.getRect(
        find.byKey(const Key('terminal-composing-overlay')),
      );
      final imageRect = tester.getRect(
        find.byKey(const Key('terminal-inline-image-0-10')),
      );

      expect(composingRect.right, lessThanOrEqualTo(imageRect.left));
      expect(
        composingRect.width,
        lessThan(imageRect.left - composingRect.left),
      );
    },
  );

  testWidgets(
    'terminal input controller does not repeat app-modifier paste shortcuts',
    (tester) async {
      final previousOverride = debugDefaultTargetPlatformOverride;
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;

        final backend = _FakePtyBackend();
        final runtime = _runtimeFor(backend);
        addTearDown(runtime.dispose);
        final sessionId = runtime.createSession(
          const TerminalSessionConfig(
            launch: TerminalLaunchConfig(program: '/bin/sh'),
          ),
        );
        var clipboardReads = 0;
        final controller = TerminalInputController(
          sessionId: sessionId,
          runtime: runtime,
          readSelection: () => '',
          copySelection: (_) async {},
          readClipboard: () async {
            clipboardReads += 1;
            return 'clip';
          },
        );

        await tester.pumpWidget(
          _KeyHandlerHarness(onKeyEvent: controller.handle),
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
        await tester.pump();
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyV);
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

        expect(clipboardReads, 1);
        expect(
          backend.writeCalls.map(utf8.decode).toList(growable: false),
          <String>['clip'],
        );
      } finally {
        debugDefaultTargetPlatformOverride = previousOverride;
      }
    },
  );
}

class _KeyHandlerHarness extends StatelessWidget {
  const _KeyHandlerHarness({required this.onKeyEvent});

  final KeyEventResult Function(KeyEvent event) onKeyEvent;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) => onKeyEvent(event),
        child: const SizedBox.expand(),
      ),
    );
  }
}

TerminalRuntimeController _runtimeFor(_FakePtyBackend backend) {
  return TerminalRuntimeController(
    backend: backend,
    copyToClipboard: (_) async {},
    readClipboard: () async => '',
    enableSessionPolling: false,
  );
}

class _FakePtyBackend implements PtySessionBackend {
  final List<Uint8List> writeCalls = <Uint8List>[];
  final List<(String, Uint8List)> writeSessionCalls = <(String, Uint8List)>[];
  int _nextSessionId = 0;

  @override
  int ping() => 1;

  @override
  String createSession(String sessionConfigJson) {
    return (++_nextSessionId).toString();
  }

  @override
  void closeSession(String sessionId) {}

  @override
  void writeInput(String sessionId, List<int> bytes) {
    final copiedBytes = Uint8List.fromList(bytes);
    writeCalls.add(copiedBytes);
    writeSessionCalls.add((sessionId, copiedBytes));
  }

  @override
  void resizeSession(
    String sessionId, {
    required int cols,
    required int rows,
    required int pixelWidth,
    required int pixelHeight,
    int cellWidth = 0,
    int cellHeight = 0,
  }) {}

  @override
  String? takeFrameDiffJson(String sessionId) {
    return jsonEncode(_singleRowSnapshot());
  }

  @override
  List<PtyEvent> pollEvents(String sessionId) => const <PtyEvent>[];

  @override
  void scrollViewport(String sessionId, int deltaLines) {}

  @override
  void scrollViewportTo(String sessionId, int offset) {}
}

Map<String, Object?> _singleRowSnapshot() {
  return <String, Object?>{
    'rows': <Object?>[
      <String, Object?>{'index': 0, 'text': '', 'segments': const <Object?>[]},
    ],
    'cursor': <String, Object?>{'row': 0, 'col': 0, 'visible': true},
    'viewport_rows': 1,
    'viewport_cols': 80,
    'scrollback_offset': 0,
    'scrollback_max_offset': 0,
    'modes': const <String, Object?>{},
  };
}
