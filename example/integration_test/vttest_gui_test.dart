import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:app/app.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/terminal/terminal_viewport.dart';

import '../test/support/memory_app_preferences_repository.dart';
import '../test/support/memory_profile_repository.dart';

const _frameWait = Duration(seconds: 20);
const _pollStep = Duration(milliseconds: 100);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real VT220 profile can drive vttest through the GUI', (
    tester,
  ) async {
    final vttestBin = Platform.environment['IANVS_VTTEST_BIN'] ?? 'vttest';
    final profile = TerminalProfile(
      id: 'vttest-vt220',
      name: 'VTTEST VT220',
      shell: vttestBin,
      args: const ['-u', '24x80.80'],
      env: const {'TERM': 'vt220', 'LC_ALL': 'C'},
      terminalEmulation: TerminalEmulation.vt220,
    );
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(
          MemoryProfileRepository(
            TerminalProfilesDocument(profiles: [profile]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const IanvsTerminalApp(),
      ),
    );

    await _waitForActiveSession(tester, container);
    await _focusTerminal(tester);

    final boot = await _waitForTerminalText(
      tester,
      container,
      description: 'vttest boot menu',
      matches: (text) =>
          _containsAny(text, const ['VT100 test program', 'vttest', 'Test of']),
    );
    expect(
      boot.text,
      isNotEmpty,
      reason: 'vttest should render visible text in the terminal viewport',
    );

    await _assertControlKeyDoesNotTriggerAppShortcut(
      tester,
      container,
      LogicalKeyboardKey.keyT,
      shortcutName: 'Ctrl+T',
    );
    await _assertControlKeyDoesNotTriggerAppShortcut(
      tester,
      container,
      LogicalKeyboardKey.keyV,
      shortcutName: 'Ctrl+V',
    );

    await _sendMenuSelection(tester, '6');
    await _waitForTerminalText(
      tester,
      container,
      description: 'vttest terminal reports path',
      matches: (text) => _containsAny(text, const [
        'terminal reports',
        'Terminal Reports',
        'Device Attributes',
        'device attributes',
        'answerback',
      ]),
    );

    await _sendMenuSelection(tester, '0');
    await _waitForTerminalText(
      tester,
      container,
      description: 'vttest main menu after terminal reports',
      matches: (text) =>
          _containsAny(text, const ['VT100 test program', 'Test of']),
    );

    await _sendMenuSelection(tester, '2');
    final screenFeatures = await _waitForTerminalText(
      tester,
      container,
      description: 'vttest screen features path',
      matches: (text) =>
          _containsAny(text, const ['screen', 'Screen', 'wrap', 'Wrap']) ||
          _hasThreeFullWidthStarRows(text),
    );
    expect(
      _hasShortMiddleStarRow(screenFeatures.rows),
      isFalse,
      reason:
          'vttest screen-features output must not leave a shorter middle full-width row',
    );
  });
}

Future<void> _waitForActiveSession(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await _waitFor(
    tester,
    description: 'active terminal session',
    condition: () {
      final state = container.read(sessionControllerProvider);
      return state.isReady && state.activeSessionId != null;
    },
  );
}

Future<void> _focusTerminal(WidgetTester tester) async {
  await tester.tap(find.byType(TerminalViewport));
  await tester.pump();
}

Future<void> _assertControlKeyDoesNotTriggerAppShortcut(
  WidgetTester tester,
  ProviderContainer container,
  LogicalKeyboardKey key, {
  required String shortcutName,
}) async {
  final before = container.read(sessionControllerProvider).tabs.length;
  await tester.sendKeyDownEvent(
    LogicalKeyboardKey.controlLeft,
    platform: 'macos',
  );
  await tester.sendKeyDownEvent(key, platform: 'macos');
  await tester.sendKeyUpEvent(key, platform: 'macos');
  await tester.sendKeyUpEvent(
    LogicalKeyboardKey.controlLeft,
    platform: 'macos',
  );
  await tester.pump(_pollStep);
  final after = container.read(sessionControllerProvider).tabs.length;

  expect(
    after,
    before,
    reason: '$shortcutName must be delivered to the terminal, not app chrome',
  );
}

Future<void> _sendMenuSelection(WidgetTester tester, String value) async {
  await _sendCharacter(tester, value);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.enter, platform: 'macos');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.enter, platform: 'macos');
  await tester.pump(_pollStep);
}

Future<void> _sendCharacter(WidgetTester tester, String value) async {
  final key = switch (value) {
    '0' => LogicalKeyboardKey.digit0,
    '1' => LogicalKeyboardKey.digit1,
    '2' => LogicalKeyboardKey.digit2,
    '3' => LogicalKeyboardKey.digit3,
    '4' => LogicalKeyboardKey.digit4,
    '5' => LogicalKeyboardKey.digit5,
    '6' => LogicalKeyboardKey.digit6,
    '7' => LogicalKeyboardKey.digit7,
    '8' => LogicalKeyboardKey.digit8,
    '9' => LogicalKeyboardKey.digit9,
    _ => throw ArgumentError.value(value, 'value', 'unsupported menu key'),
  };
  await tester.sendKeyDownEvent(key, character: value, platform: 'macos');
  await tester.sendKeyUpEvent(key, platform: 'macos');
}

Future<_TerminalSnapshot> _waitForTerminalText(
  WidgetTester tester,
  ProviderContainer container, {
  required String description,
  required bool Function(String text) matches,
}) async {
  var latest = _terminalSnapshot(container);
  await _waitFor(
    tester,
    description: description,
    condition: () {
      latest = _terminalSnapshot(container);
      return matches(latest.text);
    },
    onTimeout: () => 'Last terminal frame:\n${latest.text}',
  );
  return latest;
}

Future<void> _waitFor(
  WidgetTester tester, {
  required String description,
  required bool Function() condition,
  String Function()? onTimeout,
}) async {
  final deadline = DateTime.now().add(_frameWait);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(_pollStep);
    if (condition()) {
      return;
    }
  }
  fail(
    'Timed out waiting for $description.${onTimeout == null ? '' : '\n${onTimeout()}'}',
  );
}

_TerminalSnapshot _terminalSnapshot(ProviderContainer container) {
  final state = container.read(sessionControllerProvider);
  final sessionId = state.activeSessionId;
  if (sessionId == null) {
    return const _TerminalSnapshot(<String>[]);
  }
  final frame = container
      .read(sessionControllerProvider.notifier)
      .viewportFor(sessionId)
      .frame;
  return _TerminalSnapshot(
    frame.rows.map((row) => row.text.trimRight()).toList(growable: false),
  );
}

bool _containsAny(String text, List<String> needles) {
  return needles.any(text.contains);
}

bool _hasThreeFullWidthStarRows(String text) {
  final starRows = text
      .split('\n')
      .where((row) => row.length >= 5 && row.runes.every((rune) => rune == 42))
      .length;
  return starRows >= 3;
}

bool _hasShortMiddleStarRow(List<String> rows) {
  for (var index = 1; index < rows.length - 1; index += 1) {
    final previous = rows[index - 1];
    final current = rows[index];
    final next = rows[index + 1];
    final allStars =
        _isStarRow(previous) && _isStarRow(current) && _isStarRow(next);
    if (allStars &&
        previous.length == next.length &&
        current.length < previous.length) {
      return true;
    }
  }
  return false;
}

bool _isStarRow(String row) {
  return row.isNotEmpty && row.runes.every((rune) => rune == 42);
}

class _TerminalSnapshot {
  const _TerminalSnapshot(this.rows);

  final List<String> rows;

  String get text => rows.join('\n');
}
