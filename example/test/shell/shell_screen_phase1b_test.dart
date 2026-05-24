import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/sessions/session_ports.dart';
import 'package:app/features/shell/reference_demo.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/ui/app_ui.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';

Future<void> pumpShellScreen(
  WidgetTester tester, {
  required FakePtyBackend fakeBindings,
  required MemoryProfileRepository repository,
  bool referenceDemoMode = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(fakeBindings),
        profileRepositoryProvider.overrideWithValue(repository),
        pasteHistoryRepositoryProvider.overrideWithValue(
          MemoryPasteHistoryRepository(),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
        ),
        sessionDemoFixtureProvider.overrideWithValue(
          referenceDemoMode ? referenceDemoFixture : null,
        ),
      ],
      child: MaterialApp(
        theme: buildFluttermTheme(Brightness.light),
        darkTheme: buildFluttermTheme(Brightness.dark),
        home: const ShellScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> sendMetaShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
  await tester.sendKeyDownEvent(key, platform: 'macos');
  await tester.pumpAndSettle();
  await tester.sendKeyUpEvent(key, platform: 'macos');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft, platform: 'macos');
  await tester.pump();
}

void main() {
  testWidgets('shell screen exposes a selected tab in the hyper-style strip', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    expect(find.byKey(const Key('shell-tab-strip')), findsOneWidget);
    expect(find.bySemanticsIdentifier('shell-tab-1'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsIdentifier('shell-tab-1')),
      matchesSemantics(
        label: 'Local Shell tab, Command 1',
        hasSelectedState: true,
        isButton: true,
        isSelected: true,
      ),
    );
    expect(find.bySemanticsLabel('New tab'), findsOneWidget);
    expect(find.bySemanticsLabel('Open command menu'), findsOneWidget);
  });

  testWidgets(
    'shell screen keeps tab hierarchy clear after opening a second tab',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      await tester.tap(find.byKey(const Key('shell-chrome-new-tab')));
      await tester.pumpAndSettle();

      expect(find.bySemanticsIdentifier('shell-tab-1'), findsOneWidget);
      expect(find.bySemanticsIdentifier('shell-tab-2'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsIdentifier('shell-tab-2')),
        matchesSemantics(
          hasSelectedState: true,
          isButton: true,
          isSelected: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsIdentifier('shell-tab-1')),
        matchesSemantics(hasSelectedState: true, isButton: true),
      );
    },
  );

  testWidgets('shell tabs share the available strip width before overflow', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    final stripWidth = tester
        .getSize(find.byKey(const Key('shell-tab-strip')))
        .width;
    final singleTabWidth = tester
        .getSize(find.byKey(const Key('shell-tab-1')))
        .width;
    expect(singleTabWidth, closeTo(stripWidth - 30, 1));

    await tester.tap(find.byKey(const Key('shell-chrome-new-tab')));
    await tester.pumpAndSettle();

    final firstTabWidth = tester
        .getSize(find.byKey(const Key('shell-tab-1')))
        .width;
    final secondTabWidth = tester
        .getSize(find.byKey(const Key('shell-tab-2')))
        .width;
    expect(firstTabWidth, closeTo(secondTabWidth, 1));
    expect(firstTabWidth, greaterThan(112));
    expect(find.byKey(const Key('shell-tab-overflow-button')), findsNothing);
  });

  testWidgets('shell tab background follows terminal profile background', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(
          profiles: [_profileWithTerminalBackground('#11141A')],
        ),
      ),
    );

    final activeBackground = _tabButtonBackground(
      tester,
      const Key('shell-tab-1'),
      const <WidgetState>{},
    );
    expect(activeBackground, const Color(0xFF11141A));
    expect(
      _tabButtonOverlay(tester, const Key('shell-tab-1'), {
        WidgetState.hovered,
      }),
      Colors.transparent,
    );
    expect(
      _iconButtonOverlay(tester, const Key('shell-chrome-new-tab'), {
        WidgetState.hovered,
      }),
      Colors.transparent,
    );
    final newTabHoverBackground = _iconButtonBackground(
      tester,
      const Key('shell-chrome-new-tab'),
      const <WidgetState>{WidgetState.hovered},
    )!;
    expect(_channelSpread(newTabHoverBackground), lessThanOrEqualTo(2));
    expect(
      _decoratedBoxColor(tester, const Key('shell-chrome-bar')),
      const Color(0xFF11141A),
    );
    expect(
      _decoratedBoxColor(tester, const Key('shell-status-bar-surface')),
      const Color(0xFF11141A),
    );

    await tester.tap(find.byKey(const Key('shell-chrome-new-tab')));
    await tester.pumpAndSettle();

    final inactiveBackground = _tabButtonBackground(
      tester,
      const Key('shell-tab-1'),
      const <WidgetState>{},
    );
    expect(inactiveBackground, Colors.transparent);
    final inactiveBorder = _decoratedBoxBorder(
      tester,
      const Key('shell-tab-border-1'),
    );
    expect(inactiveBorder.top, BorderSide.none);
    expect(inactiveBorder.left.width, 1);
    expect(inactiveBorder.right.width, 1);
    expect(inactiveBorder.bottom.width, 1);
    final hoverBackground = _tabButtonBackground(
      tester,
      const Key('shell-tab-1'),
      const <WidgetState>{WidgetState.hovered},
    );
    expect(_channelSpread(hoverBackground), lessThanOrEqualTo(2));
    expect(
      hoverBackground.computeLuminance(),
      greaterThan(inactiveBackground.computeLuminance()),
    );
  });

  testWidgets('shell tabs overflow into a selector at readable widths', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    for (var index = 0; index < 11; index += 1) {
      await tester.tap(find.byKey(const Key('shell-chrome-new-tab')));
      await tester.pumpAndSettle();
    }

    expect(find.byKey(const Key('shell-tab-overflow-button')), findsOneWidget);
    expect(find.bySemanticsIdentifier('shell-tab-12'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('shell-tab-1'))).width,
      greaterThanOrEqualTo(112),
    );

    await tester.tap(find.byKey(const Key('shell-tab-overflow-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-tab-overflow-panel')), findsOneWidget);
    expect(find.byKey(const Key('shell-tab-overflow-item-12')), findsOneWidget);
  });

  testWidgets('inactive tabs mark and clear new output activity', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    await pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await tester.tap(find.byKey(const Key('shell-chrome-new-tab')));
    await tester.pumpAndSettle();

    fakeBindings.setFrame(1, _terminalFrame('background build done'));
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byKey(const Key('shell-tab-new-output-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('shell-tab-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-tab-new-output-1')), findsNothing);
  });

  testWidgets('overflow menu only dots hidden tabs with new output', (
    tester,
  ) async {
    final fakeBindings = FakePtyBackend();
    await pumpShellScreen(
      tester,
      fakeBindings: fakeBindings,
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    for (var index = 0; index < 11; index += 1) {
      await tester.tap(find.byKey(const Key('shell-chrome-new-tab')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('shell-tab-1')));
    await tester.pumpAndSettle();

    fakeBindings.setFrame(12, _terminalFrame('hidden tab output'));
    await tester.pump(const Duration(milliseconds: 40));

    await tester.tap(find.byKey(const Key('shell-tab-overflow-button')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('shell-tab-overflow-new-output')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('shell-tab-new-output-12')), findsOneWidget);
    expect(find.byKey(const Key('shell-tab-new-output-11')), findsNothing);
  });

  testWidgets(
    'shell chrome leading gap starts native window drag on macOS',
    (tester) async {
      const channel = MethodChannel('app/window_bridge');
      final methodCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        methodCalls.add(call.method);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      final dragHandle = find.byKey(const Key('shell-window-drag-leading'));
      expect(dragHandle, findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(dragHandle));
      await gesture.moveBy(const Offset(28, 0));
      await tester.pumpAndSettle();
      await gesture.up();

      expect(methodCalls, contains('beginWindowDrag'));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'shell screen reorders tabs through a direct drag gesture',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
      );

      for (var index = 0; index < 2; index += 1) {
        await tester.tap(find.byKey(const Key('shell-chrome-new-tab')));
        await tester.pumpAndSettle();
      }

      final tabOne = find.byKey(const Key('shell-tab-drag-1'));
      final tabTwo = find.byKey(const Key('shell-tab-drag-2'));
      final tabThree = find.byKey(const Key('shell-tab-drag-3'));
      expect(tabOne, findsOneWidget);
      expect(tabTwo, findsOneWidget);
      expect(tabThree, findsOneWidget);
      expect(
        tester.getCenter(tabOne).dx,
        lessThan(tester.getCenter(tabTwo).dx),
      );
      expect(
        tester.getCenter(tabTwo).dx,
        lessThan(tester.getCenter(tabThree).dx),
      );

      final gesture = await tester.startGesture(tester.getCenter(tabOne));
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.moveBy(const Offset(360, 0));
      await tester.pump(const Duration(milliseconds: 360));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        tester.getCenter(tabTwo).dx,
        lessThan(tester.getCenter(tabThree).dx),
      );
      expect(
        tester.getCenter(tabThree).dx,
        lessThan(tester.getCenter(tabOne).dx),
      );
      expect(
        tester.getSemantics(find.bySemanticsIdentifier('shell-tab-3')),
        matchesSemantics(
          hasSelectedState: true,
          isButton: true,
          isSelected: true,
        ),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('shell screen uses the same dark empty-state language everywhere', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
    );

    await tester.tap(find.byTooltip('Close Local Shell'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shell-empty-state')), findsOneWidget);
    expect(find.text('Shell workspace is idle'), findsOneWidget);
    expect(
      find.text(
        'The last session has closed. Open a new tab to keep working in the shell workspace.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('reference demo mode keeps the middle Shell tab selected', (
    tester,
  ) async {
    await pumpShellScreen(
      tester,
      fakeBindings: FakePtyBackend(),
      repository: MemoryProfileRepository(
        TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
      ),
      referenceDemoMode: true,
    );

    expect(find.text('⌘1'), findsOneWidget);
    expect(find.text('⌘2'), findsOneWidget);
    expect(find.text('⌘3'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsIdentifier('shell-tab-demo-2')),
      matchesSemantics(
        label: 'Shell tab, Command 2',
        hasSelectedState: true,
        isButton: true,
        isSelected: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsIdentifier('shell-tab-demo-1')),
      matchesSemantics(hasSelectedState: true, isButton: true),
    );
  });

  testWidgets(
    'reference demo mode supports command-number tab selection',
    (tester) async {
      await pumpShellScreen(
        tester,
        fakeBindings: FakePtyBackend(),
        repository: MemoryProfileRepository(
          TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
        ),
        referenceDemoMode: true,
      );

      await sendMetaShortcut(tester, LogicalKeyboardKey.digit1);

      expect(
        tester.getSemantics(find.bySemanticsIdentifier('shell-tab-demo-1')),
        matchesSemantics(
          hasSelectedState: true,
          isButton: true,
          isSelected: true,
        ),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}

Color _tabButtonBackground(
  WidgetTester tester,
  Key key,
  Set<WidgetState> states,
) {
  final button = tester.widget<TextButton>(find.byKey(key));
  return button.style!.backgroundColor!.resolve(states)!;
}

Color? _tabButtonOverlay(
  WidgetTester tester,
  Key key,
  Set<WidgetState> states,
) {
  final button = tester.widget<TextButton>(find.byKey(key));
  return button.style!.overlayColor!.resolve(states);
}

Color? _iconButtonBackground(
  WidgetTester tester,
  Key key,
  Set<WidgetState> states,
) {
  final button = tester.widget<IconButton>(find.byKey(key));
  return button.style!.backgroundColor!.resolve(states);
}

Color? _iconButtonOverlay(
  WidgetTester tester,
  Key key,
  Set<WidgetState> states,
) {
  final button = tester.widget<IconButton>(find.byKey(key));
  return button.style!.overlayColor!.resolve(states);
}

Color? _decoratedBoxColor(WidgetTester tester, Key key) {
  final decoratedBox = tester.widget<DecoratedBox>(find.byKey(key));
  return (decoratedBox.decoration as BoxDecoration).color;
}

Border _decoratedBoxBorder(WidgetTester tester, Key key) {
  final decoratedBox = tester.widget<DecoratedBox>(find.byKey(key));
  return (decoratedBox.decoration as BoxDecoration).border! as Border;
}

int _channelSpread(Color color) {
  final argb = color.toARGB32();
  final red = (argb >> 16) & 0xff;
  final green = (argb >> 8) & 0xff;
  final blue = argb & 0xff;
  return [
    (red - green).abs(),
    (red - blue).abs(),
    (green - blue).abs(),
  ].reduce(math.max);
}

TerminalProfile _profileWithTerminalBackground(String background) {
  final base = defaultTerminalProfile();
  return base.copyWith(
    appearance: TerminalProfileAppearance(
      colors: TerminalProfileColors(
        special: TerminalSpecialColors(background: background),
      ),
    ),
  );
}

Map<String, Object?> _terminalFrame(String text) {
  return {
    'rows': [
      {'index': 0, 'text': text, 'style_runs': const []},
    ],
    'cursor': {'row': 0, 'col': text.length, 'visible': true},
    'selection': null,
    'viewport_rows': 24,
    'viewport_cols': 80,
    'dirty_ranges': [
      {'start': 0, 'end': 1},
    ],
    'scrollback_offset': 0,
    'scrollback_max_offset': 0,
  };
}
