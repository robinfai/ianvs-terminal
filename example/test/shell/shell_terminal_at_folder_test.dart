import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/layout/local_terminal_layout_models.dart';
import 'package:app/features/layout/local_terminal_layout_repository.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_profile_repository.dart';

class _MemoryLayoutRepository extends LocalTerminalLayoutRepository {
  TerminalLayout? layout;

  @override
  Future<TerminalLayout?> load() async => layout;

  @override
  Future<void> save(TerminalLayout layout) async {
    this.layout = layout;
  }
}

class _LayoutConfigRepository extends LocalTerminalConfigRepository {
  @override
  Future<LocalTerminalConfigDocument?> load() async {
    return const LocalTerminalConfigDocument(
      layout: LocalTerminalLayoutConfig(restoreLayout: true),
    );
  }

  @override
  Future<void> save(LocalTerminalConfigDocument document) async {}
}

Future<ProviderContainer> _pumpShell(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(FakePtyBackend()),
        profileRepositoryProvider.overrideWithValue(
          MemoryProfileRepository(
            TerminalProfilesDocument(
              profiles: <TerminalProfile>[defaultTerminalProfile()],
            ),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          _LayoutConfigRepository(),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          _MemoryLayoutRepository(),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        home: const ShellScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(ShellScreen)));
}

Future<void> _invokeNativeWindowBridge(
  WidgetTester tester,
  MethodCall call,
) async {
  const codec = StandardMethodCodec();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'app/window_bridge',
    codec.encodeMethodCall(call),
    (_) {},
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('chrome opens a terminal at a selected folder', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('app/window_bridge'),
      (call) async => call.method == 'chooseTerminalFolder'
          ? '/layout/selected-folder'
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('app/window_bridge'),
        null,
      ),
    );
    final container = await _pumpShell(tester);

    expect(
      find.byKey(const Key('shell-open-terminal-at-folder')),
      findsOneWidget,
    );
    expect(find.text('Open Project…'), findsNothing);
    expect(find.textContaining('Recent Layout'), findsNothing);

    await tester.tap(find.byKey(const Key('shell-open-terminal-at-folder')));
    await tester.pumpAndSettle();

    final state = container.read(sessionControllerProvider);
    expect(state.tabs, hasLength(2));
    expect(state.tabs.last.profileSnapshot!.cwd, '/layout/selected-folder');
  });

  testWidgets('native folder open handles selection and cancellation safely', (
    tester,
  ) async {
    final selectedPaths = <String?>['/layout/native-folder', null];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('app/window_bridge'),
      (call) async => call.method == 'chooseTerminalFolder'
          ? selectedPaths.removeAt(0)
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('app/window_bridge'),
        null,
      ),
    );
    final container = await _pumpShell(tester);

    await _invokeNativeWindowBridge(
      tester,
      const MethodCall('nativeOpenTerminalAtFolder'),
    );
    expect(container.read(sessionControllerProvider).tabs, hasLength(2));

    await _invokeNativeWindowBridge(
      tester,
      const MethodCall('nativeOpenTerminalAtFolder'),
    );
    expect(container.read(sessionControllerProvider).tabs, hasLength(2));
  });
}
