import 'dart:io';

import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_acceptance.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/ssh/ssh_feature_access.dart';
import 'package:app/ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_local_terminal_config_repository.dart';
import '../support/memory_paste_history_repository.dart';
import '../support/memory_profile_repository.dart';
import '../support/no_io_local_session_recording_repository.dart';
import '../support/no_io_local_terminal_layout_repository.dart';

const _surfaceSize = Size(1280, 800);

Future<ByteData> _readFont(String path) async {
  final bytes = await File(path).readAsBytes();
  return ByteData.sublistView(Uint8List.fromList(bytes));
}

Future<void> _loadVisualFonts() async {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final text = FontLoader('AppSurfaceCaptureSans')
    ..addFont(_readFont('/System/Library/Fonts/SFNS.ttf'));
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(
      _readFont(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    );
  await Future.wait([text.load(), materialIcons.load()]);
}

Future<void> _pumpShell(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _surfaceSize;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final local = defaultTerminalProfile().copyWith(
    tags: const <String>['local', 'login'],
  );
  final ssh = TerminalProfile(
    id: 'ssh-capture',
    name: 'Production SSH',
    shell: '/usr/bin/ssh',
    tags: const <String>['remote', 'ops'],
  );
  final baseTheme = buildIanvsTerminalTheme(
    Brightness.dark,
    platform: TargetPlatform.macOS,
  );
  const captureFont = 'AppSurfaceCaptureSans';

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        shellAcceptanceProbeProvider.overrideWithValue(shellAcceptanceProbe),
        customSshProfileConfigurationEnabledProvider.overrideWithValue(true),
        ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
        profileRepositoryProvider.overrideWithValue(
          MemoryProfileRepository(
            TerminalProfilesDocument(profiles: <TerminalProfile>[local, ssh]),
          ),
        ),
        pasteHistoryRepositoryProvider.overrideWithValue(
          MemoryPasteHistoryRepository(),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(
            const TerminalAppPreferencesDocument(
              appearance: TerminalAppAppearance(
                themeMode: TerminalThemeMode.dark,
              ),
            ),
          ),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          MemoryLocalTerminalConfigRepository(null),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          noIoLocalSessionRecordingRepository(),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          noIoLocalTerminalLayoutRepository(),
        ),
      ],
      child: RepaintBoundary(
        key: const Key('app-surface-capture-root'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: baseTheme.copyWith(
            textTheme: baseTheme.textTheme.apply(fontFamily: captureFont),
            primaryTextTheme: baseTheme.primaryTextTheme.apply(
              fontFamily: captureFont,
            ),
          ),
          home: const ShellScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String goldenName) async {
  await expectLater(
    find.byKey(const Key('app-surface-capture-root')),
    matchesGoldenFile(
      '../../../docs/design/app-surfaces/current/$goldenName.png',
    ),
  );
}

void main() {
  if (!Platform.isMacOS) {
    test('app surface visual captures require macOS fonts', () {}, skip: true);
    return;
  }

  setUpAll(_loadVisualFonts);

  testWidgets('captures the desktop shell', (tester) async {
    await _pumpShell(tester);
    await _capture(tester, '01-desktop-shell');
  });

  testWidgets('captures the command palette', (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();
    await _capture(tester, '02-command-palette');
  });

  testWidgets('captures the profiles sheet', (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const Key('shell-chrome-menu')));
    await tester.pumpAndSettle();
    final profilesAction = find.text('Profiles…');
    await tester.ensureVisible(profilesAction);
    await tester.tap(profilesAction);
    await tester.pumpAndSettle();
    await _capture(tester, '03-profiles-sheet');
  });
}
