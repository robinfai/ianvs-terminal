import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/features/config/local_terminal_config_models.dart';
import 'package:app/features/config/local_terminal_config_repository.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:app/features/workspace/local_workspace_models.dart';
import 'package:app/features/workspace/local_workspace_repository.dart';

import '../support/fake_pty_backend.dart';
import '../support/memory_app_preferences_repository.dart';
import '../support/memory_profile_repository.dart';

class _WorkspaceMenuRepository extends LocalWorkspaceRepository {
  _WorkspaceMenuRepository({
    required TerminalWorkspace current,
    required Iterable<TerminalWorkspace> workspaces,
  }) : _current = current,
       _documents = <String, TerminalWorkspace>{
         current.identity.id: current,
         for (final workspace in workspaces) workspace.identity.id: workspace,
       };

  TerminalWorkspace _current;
  final Map<String, TerminalWorkspace> _documents;

  @override
  Future<TerminalWorkspace?> load() async => _current;

  @override
  Future<TerminalWorkspace?> loadWorkspace(String workspaceId) async {
    return _documents[workspaceId];
  }

  @override
  Future<TerminalWorkspace> loadOrCreateProject({
    required String projectPath,
    String? name,
  }) async {
    final identity = TerminalWorkspaceIdentity.forProject(
      projectPath,
      name: name,
    );
    return _documents.putIfAbsent(
      identity.id,
      () => TerminalWorkspace(identity: identity),
    );
  }

  @override
  Future<void> activateWorkspace(TerminalWorkspace workspace) async {
    _documents[workspace.identity.id] = workspace;
    _current = workspace;
  }

  @override
  Future<void> save(TerminalWorkspace workspace) async {
    _documents[workspace.identity.id] = workspace;
    if (_current.identity.id == workspace.identity.id) {
      _current = workspace;
    }
  }

  @override
  Future<List<TerminalWorkspaceRecentEntry>> loadRecent() async {
    return <TerminalWorkspaceRecentEntry>[
      for (final workspace in _documents.values.toList().reversed)
        TerminalWorkspaceRecentEntry(
          identity: workspace.identity,
          lastOpenedAtUtc: DateTime.utc(2026, 7, 21),
        ),
    ];
  }
}

class _WorkspaceConfigRepository extends LocalTerminalConfigRepository {
  @override
  Future<LocalTerminalConfigDocument?> load() async {
    return const LocalTerminalConfigDocument(
      workspace: LocalTerminalWorkspaceConfig(restoreLayout: true),
    );
  }

  @override
  Future<void> save(LocalTerminalConfigDocument document) async {}
}

Future<ProviderContainer> _pumpWorkspaceShell(
  WidgetTester tester,
  _WorkspaceMenuRepository workspaceRepository,
) async {
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
          _WorkspaceConfigRepository(),
        ),
        localWorkspaceRepositoryProvider.overrideWithValue(workspaceRepository),
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

  testWidgets(
    'workspace menu names active project and opens a recent project',
    (tester) async {
      final projectA = TerminalWorkspaceIdentity.forProject(
        '/workspace/a',
        name: 'Project A',
      );
      final projectB = TerminalWorkspaceIdentity.forProject(
        '/workspace/b',
        name: 'Project B',
      );
      final repository = _WorkspaceMenuRepository(
        current: TerminalWorkspace(identity: projectA),
        workspaces: <TerminalWorkspace>[TerminalWorkspace(identity: projectB)],
      );
      final container = await _pumpWorkspaceShell(tester, repository);

      expect(find.byKey(const Key('shell-chrome-workspaces')), findsOneWidget);
      expect(find.text('Project A'), findsOneWidget);

      await tester.tap(find.byKey(const Key('shell-chrome-workspaces')));
      await tester.pumpAndSettle();

      expect(find.text('Open Project…'), findsOneWidget);
      expect(find.text('Project B'), findsOneWidget);
      expect(find.text('Project A'), findsOneWidget);

      await tester.tap(find.text('Project B'));
      await tester.pumpAndSettle();

      expect(
        container
            .read(sessionControllerProvider.notifier)
            .activeWorkspaceIdentity,
        projectB,
      );
      expect(find.text('Project B'), findsOneWidget);
    },
  );

  testWidgets(
    'native Open Project uses the directory picker and cancellation is safe',
    (tester) async {
      final projectA = TerminalWorkspaceIdentity.forProject('/workspace/a');
      final repository = _WorkspaceMenuRepository(
        current: TerminalWorkspace(identity: projectA),
        workspaces: const <TerminalWorkspace>[],
      );
      final selectedPaths = <String?>['/workspace/new-project', null];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('app/window_bridge'),
        (call) async {
          if (call.method == 'chooseProjectDirectory') {
            return selectedPaths.removeAt(0);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('app/window_bridge'),
          null,
        ),
      );
      final container = await _pumpWorkspaceShell(tester, repository);

      await _invokeNativeWindowBridge(
        tester,
        const MethodCall('nativeOpenProject'),
      );
      final openedIdentity = container
          .read(sessionControllerProvider.notifier)
          .activeWorkspaceIdentity;
      expect(
        openedIdentity,
        TerminalWorkspaceIdentity.forProject('/workspace/new-project'),
      );

      await _invokeNativeWindowBridge(
        tester,
        const MethodCall('nativeOpenProject'),
      );
      expect(
        container
            .read(sessionControllerProvider.notifier)
            .activeWorkspaceIdentity,
        openedIdentity,
      );
    },
  );
}
