import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/configuration/data_api_configuration_providers.dart';
import 'data/configuration/data_api_configuration_repository.dart';
import 'data/services/data_api_lifecycle.dart';
import 'data/services/data_api_runtime.dart';
import 'features/profiles/profile_repository.dart';
import 'features/pty/pty.dart';
import 'features/sessions/session_controller.dart';
import 'features/sessions/session_ports.dart';
import 'features/shell/reference_demo.dart';
import 'features/shell/shell_acceptance.dart';
import 'features/shell/shell_screen.dart';
import 'features/shell/window_bridge.dart';
import 'persistence_repository_composition.dart';
import 'platform/app_shutdown_coordinator.dart';
import 'platform/clipboard_bridge.dart';
import 'startup/app_startup_models.dart';

Widget buildIanvsTerminalRoot({
  bool enableSessionPolling = true,
  bool enableShellAnimations = true,
  bool enableDriverWarmUpRefresh = false,
  bool enableReferenceDemoMode = false,
  PtySessionBackend? ptySessionBackend,
  ShellAcceptanceProbe? acceptanceProbe,
  DataApiRuntime? dataApiRuntime,
  bool dataApiPersistenceRequired = false,
  bool dataApiPersistenceUnavailable = false,
  DataApiStartupWarning? dataApiStartupWarning,
  DataApiConfigurationRepository? dataApiConfigurationRepository,
  bool dataApiConfigurationRecoveryRequired = false,
  DirectoryResolver? profileExportDirectoryResolver,
  Map<String, String> sessionEnvironmentOverrides = const <String, String>{},
  AppRuntimeGraph? runtimeGraph,
  Key? providerScopeKey,
}) {
  final effectiveDataApiRuntime =
      runtimeGraph?.dataApiRuntime ?? dataApiRuntime;
  final effectiveDataApiStartupWarning =
      runtimeGraph?.dataApiStartupWarning ?? dataApiStartupWarning;
  final effectiveDataApiConfigurationRepository =
      runtimeGraph?.dataApiConfigurationRepository ??
      dataApiConfigurationRepository;
  final effectivePtySessionBackend =
      runtimeGraph?.ptySessionBackend ?? ptySessionBackend;
  final shutdownCoordinator =
      runtimeGraph?.shutdownCoordinator ?? AppShutdownCoordinator();
  final persistenceRepositories =
      runtimeGraph?.persistenceRepositories ??
      PersistenceRepositoryComposition.forRuntime(
        effectiveDataApiRuntime,
        profileExportDirectoryResolver:
            profileExportDirectoryResolver ?? getApplicationSupportDirectory,
        dataApiPersistenceRequired: dataApiPersistenceRequired,
        dataApiPersistenceUnavailable: dataApiPersistenceUnavailable,
      );
  return ProviderScope(
    key: providerScopeKey,
    overrides: [
      appShutdownCoordinatorProvider.overrideWithValue(shutdownCoordinator),
      sessionPollingEnabledProvider.overrideWithValue(enableSessionPolling),
      dataApiRuntimeProvider.overrideWithValue(effectiveDataApiRuntime),
      dataApiStartupWarningProvider.overrideWithValue(
        effectiveDataApiStartupWarning,
      ),
      profileRepositoryProvider.overrideWithValue(
        persistenceRepositories.profiles,
      ),
      appPreferencesRepositoryProvider.overrideWithValue(
        persistenceRepositories.preferences,
      ),
      localTerminalConfigRepositoryProvider.overrideWithValue(
        persistenceRepositories.terminalConfig,
      ),
      localTerminalLayoutRepositoryProvider.overrideWithValue(
        persistenceRepositories.terminalLayout,
      ),
      pasteHistoryRepositoryProvider.overrideWithValue(
        persistenceRepositories.pasteHistory,
      ),
      if (runtimeGraph != null)
        localSessionRecordingRepositoryProvider.overrideWithValue(
          runtimeGraph.recordingRepository,
        ),
      if (effectiveDataApiConfigurationRepository != null)
        dataApiConfigurationRepositoryProvider.overrideWithValue(
          effectiveDataApiConfigurationRepository,
        ),
      dataApiConfigurationRecoveryRequiredProvider.overrideWithValue(
        dataApiConfigurationRecoveryRequired,
      ),
      if (effectivePtySessionBackend != null)
        ptySessionBackendProvider.overrideWithValue(effectivePtySessionBackend),
      driverWarmUpRefreshEnabledProvider.overrideWithValue(
        enableDriverWarmUpRefresh,
      ),
      sessionEnvironmentOverridesProvider.overrideWithValue(
        sessionEnvironmentOverrides,
      ),
      sessionClipboardCopyProvider.overrideWithValue(ClipboardBridge.copy),
      sessionClipboardTextWriteProvider.overrideWithValue(
        ClipboardBridge.writeText,
      ),
      sessionClipboardPasteProvider.overrideWithValue(ClipboardBridge.paste),
      sessionClipboardMimeWriteProvider.overrideWithValue(
        ClipboardBridge.writeMimeItems,
      ),
      sessionClipboardMimeReadProvider.overrideWithValue(
        ClipboardBridge.readMimeItems,
      ),
      sessionClipboardMimeTypeListProvider.overrideWithValue(
        ClipboardBridge.listMimeTypes,
      ),
      sessionWindowResizeProvider.overrideWithValue(WindowBridge.resizeBy),
      sessionWindowTitleWriterProvider.overrideWithValue(WindowBridge.setTitle),
      if (acceptanceProbe != null) ...[
        shellAcceptanceProbeProvider.overrideWithValue(acceptanceProbe),
        sessionTerminalContentPublisherProvider.overrideWithValue(({
          required terminalHasVisibleContent,
          required terminalPreview,
        }) {
          acceptanceProbe.mergeTerminalContent(
            terminalHasVisibleContent: terminalHasVisibleContent,
            terminalPreview: terminalPreview,
          );
        }),
      ],
      sessionDemoFixtureProvider.overrideWithValue(
        enableReferenceDemoMode ? referenceDemoFixture : null,
      ),
      shellAnimationsEnabledProvider.overrideWithValue(enableShellAnimations),
    ],
    child: runtimeGraph == null
        ? DataApiLifecycleBoundary(
            runtime: effectiveDataApiRuntime,
            shutdownCoordinator: shutdownCoordinator,
            child: const IanvsTerminalApp(),
          )
        : const IanvsTerminalApp(),
  );
}

/// Builds the application only from a fully prepared startup graph.
///
/// The generation key replaces the complete ProviderScope on retry. Runtime
/// resources remain owned by [AppRuntimeGraph.shutdownCoordinator], so widget
/// disposal never races a second close against coordinator-managed teardown.
Widget buildIanvsTerminalRuntimeRoot({
  required AppRuntimeGraph graph,
  bool enableSessionPolling = true,
  bool enableShellAnimations = true,
  bool enableDriverWarmUpRefresh = false,
  bool enableReferenceDemoMode = false,
  ShellAcceptanceProbe? acceptanceProbe,
  Map<String, String> sessionEnvironmentOverrides = const <String, String>{},
}) {
  return buildIanvsTerminalRoot(
    runtimeGraph: graph,
    providerScopeKey: ValueKey<int>(graph.generation),
    enableSessionPolling: enableSessionPolling,
    enableShellAnimations: enableShellAnimations,
    enableDriverWarmUpRefresh: enableDriverWarmUpRefresh,
    enableReferenceDemoMode: enableReferenceDemoMode,
    acceptanceProbe: acceptanceProbe,
    sessionEnvironmentOverrides: sessionEnvironmentOverrides,
  );
}

void runIanvsTerminalApp({
  bool enableSessionPolling = true,
  bool enableShellAnimations = true,
  bool enableDriverWarmUpRefresh = false,
  bool enableReferenceDemoMode = false,
  PtySessionBackend? ptySessionBackend,
  ShellAcceptanceProbe? acceptanceProbe,
  DataApiRuntime? dataApiRuntime,
  bool dataApiPersistenceRequired = false,
  bool dataApiPersistenceUnavailable = false,
  DataApiStartupWarning? dataApiStartupWarning,
  DataApiConfigurationRepository? dataApiConfigurationRepository,
  bool dataApiConfigurationRecoveryRequired = false,
  DirectoryResolver? profileExportDirectoryResolver,
  Map<String, String> sessionEnvironmentOverrides = const <String, String>{},
}) {
  runApp(
    buildIanvsTerminalRoot(
      enableSessionPolling: enableSessionPolling,
      enableDriverWarmUpRefresh: enableDriverWarmUpRefresh,
      enableReferenceDemoMode: enableReferenceDemoMode,
      ptySessionBackend: ptySessionBackend,
      acceptanceProbe: acceptanceProbe,
      dataApiRuntime: dataApiRuntime,
      dataApiPersistenceRequired: dataApiPersistenceRequired,
      dataApiPersistenceUnavailable: dataApiPersistenceUnavailable,
      dataApiStartupWarning: dataApiStartupWarning,
      dataApiConfigurationRepository: dataApiConfigurationRepository,
      dataApiConfigurationRecoveryRequired:
          dataApiConfigurationRecoveryRequired,
      profileExportDirectoryResolver: profileExportDirectoryResolver,
      sessionEnvironmentOverrides: sessionEnvironmentOverrides,
      enableShellAnimations: enableShellAnimations,
    ),
  );
}
