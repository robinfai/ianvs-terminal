import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/configuration/data_api_configuration_providers.dart';
import 'data/configuration/data_api_configuration_repository.dart';
import 'data/services/data_api_lifecycle.dart';
import 'data/services/data_api_runtime.dart';
import 'features/pty/pty.dart';
import 'features/sessions/session_controller.dart';
import 'features/sessions/session_ports.dart';
import 'features/shell/reference_demo.dart';
import 'features/shell/shell_acceptance.dart';
import 'features/shell/shell_screen.dart';
import 'features/shell/window_bridge.dart';
import 'platform/app_shutdown_coordinator.dart';
import 'platform/clipboard_bridge.dart';

Widget buildIanvsTerminalRoot({
  bool enableSessionPolling = true,
  bool enableShellAnimations = true,
  bool enableDriverWarmUpRefresh = false,
  bool enableReferenceDemoMode = false,
  PtySessionBackend? ptySessionBackend,
  ShellAcceptanceProbe? acceptanceProbe,
  DataApiRuntime? dataApiRuntime,
  DataApiConfigurationRepository? dataApiConfigurationRepository,
  Map<String, String> sessionEnvironmentOverrides = const <String, String>{},
}) {
  final shutdownCoordinator = AppShutdownCoordinator();
  return ProviderScope(
    overrides: [
      appShutdownCoordinatorProvider.overrideWithValue(shutdownCoordinator),
      sessionPollingEnabledProvider.overrideWithValue(enableSessionPolling),
      dataApiRuntimeProvider.overrideWithValue(dataApiRuntime),
      if (dataApiConfigurationRepository != null)
        dataApiConfigurationRepositoryProvider.overrideWithValue(
          dataApiConfigurationRepository,
        ),
      if (ptySessionBackend != null)
        ptySessionBackendProvider.overrideWithValue(ptySessionBackend),
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
    child: DataApiLifecycleBoundary(
      runtime: dataApiRuntime,
      shutdownCoordinator: shutdownCoordinator,
      child: const IanvsTerminalApp(),
    ),
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
  DataApiConfigurationRepository? dataApiConfigurationRepository,
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
      dataApiConfigurationRepository: dataApiConfigurationRepository,
      sessionEnvironmentOverrides: sessionEnvironmentOverrides,
      enableShellAnimations: enableShellAnimations,
    ),
  );
}
