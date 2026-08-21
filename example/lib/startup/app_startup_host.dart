import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_bootstrap.dart';
import '../data/configuration/data_api_configuration.dart';
import '../data/configuration/data_api_configuration_repository.dart';
import '../data/services/portable_master_key.dart';
import '../ui/app_ui.dart';
import 'app_startup_coordinator.dart';
import 'app_startup_lifecycle.dart';
import 'app_startup_models.dart';

typedef AppStartupRuntimeBuilder = Widget Function(AppRuntimeGraph graph);

final class AppStartupHost extends StatefulWidget {
  const AppStartupHost({
    required this.coordinator,
    this.disposeCoordinator = true,
    this.startAutomatically = true,
    this.enableSessionPolling = true,
    this.enableShellAnimations = true,
    this.enableReferenceDemoMode = false,
    this.shutdownChannel = const MethodChannel('app/shutdown'),
    this.runtimeBuilder,
    super.key,
  });

  final AppStartupCoordinator coordinator;
  final bool disposeCoordinator;
  final bool startAutomatically;
  final bool enableSessionPolling;
  final bool enableShellAnimations;
  final bool enableReferenceDemoMode;
  final MethodChannel shutdownChannel;
  final AppStartupRuntimeBuilder? runtimeBuilder;

  @override
  State<AppStartupHost> createState() => _AppStartupHostState();
}

final class _AppStartupHostState extends State<AppStartupHost> {
  @override
  void initState() {
    super.initState();
    if (widget.startAutomatically) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(widget.coordinator.start());
        }
      });
    }
  }

  @override
  void dispose() {
    if (widget.disposeCoordinator) {
      widget.coordinator.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppStartupLifecycleBoundary(
      coordinator: widget.coordinator,
      shutdownChannel: widget.shutdownChannel,
      closeOnDispose: widget.disposeCoordinator,
      child: ListenableBuilder(
        listenable: widget.coordinator,
        builder: (context, child) {
          return switch (widget.coordinator.state) {
            AppStartupLoading(:final attempt) => _StartupMaterialApp(
              home: _AppStartupLoadingView(attempt: attempt),
            ),
            AppStartupDataSetupRequired(:final requirement, :final settings) =>
              _StartupMaterialApp(
                home: _AppStartupDataSetupView(
                  requirement: requirement,
                  settings: settings,
                  coordinator: widget.coordinator,
                ),
              ),
            AppStartupRecoverableFailure(:final failure) => _StartupMaterialApp(
              home: _AppStartupFailureView(
                failure: failure,
                coordinator: widget.coordinator,
              ),
            ),
            AppStartupReady(:final graph) =>
              widget.runtimeBuilder?.call(graph) ??
                  buildIanvsTerminalRuntimeRoot(
                    graph: graph,
                    enableSessionPolling: widget.enableSessionPolling,
                    enableShellAnimations: widget.enableShellAnimations,
                    enableReferenceDemoMode: widget.enableReferenceDemoMode,
                  ),
          };
        },
      ),
    );
  }
}

final class _StartupMaterialApp extends StatelessWidget {
  const _StartupMaterialApp({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: resolveAppLocale,
      theme: buildIanvsTerminalTheme(
        Brightness.light,
        platform: defaultTargetPlatform,
      ),
      darkTheme: buildIanvsTerminalTheme(
        Brightness.dark,
        platform: defaultTargetPlatform,
      ),
      home: home,
    );
  }
}

final class _AppStartupDataSetupView extends StatefulWidget {
  const _AppStartupDataSetupView({
    required this.requirement,
    required this.settings,
    required this.coordinator,
  });

  final AppStartupDataSetupRequirement requirement;
  final AppStartupDataSettingsCapability settings;
  final AppStartupCoordinator coordinator;

  @override
  State<_AppStartupDataSetupView> createState() =>
      _AppStartupDataSetupViewState();
}

final class _AppStartupDataSetupViewState
    extends State<_AppStartupDataSetupView> {
  final _urlController = TextEditingController(
    text: defaultRemoteDataApiBaseUrl,
  );
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _portableMasterKeyController = TextEditingController();
  bool _runningAction = false;
  String? _actionError;

  bool get _canConnect =>
      _urlController.text.trim().isNotEmpty &&
      _usernameController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_handleInputChanged);
    }
  }

  List<TextEditingController> get _controllers => <TextEditingController>[
    _urlController,
    _usernameController,
    _passwordController,
    _portableMasterKeyController,
  ];

  void _handleInputChanged() {
    if (mounted) {
      setState(() {
        _actionError = null;
      });
    }
  }

  Future<void> _connect() async {
    if (!_canConnect || _runningAction) {
      return;
    }
    await _run(() async {
      final portableMasterKey = _portableMasterKeyController.text.trim();
      if (portableMasterKey.isNotEmpty) {
        final settings = widget.settings;
        if (settings is! AppStartupMasterKeyCapability) {
          throw StateError(context.l10n.masterKeyImportUnavailable);
        }
        await (settings as AppStartupMasterKeyCapability)
            .importPortableMasterKey(portableMasterKey);
      }
      final configuration = DataApiConfiguration.remote(_urlController.text);
      await widget.settings.reconnect(
        DataApiRemoteLoginRequest(
          baseUri: configuration.remoteBaseUri!,
          username: _usernameController.text,
          password: _passwordController.text,
        ),
      );
      await widget.coordinator.retry();
    });
  }

  Future<void> _skip() async {
    if (widget.requirement != AppStartupDataSetupRequirement.optional ||
        _runningAction) {
      return;
    }
    await _run(() async {
      await widget.settings.saveDisabled();
      await widget.coordinator.retry();
    });
  }

  Future<void> _useLocalApi() async {
    if (widget.requirement != AppStartupDataSetupRequirement.optional ||
        !widget.settings.localDataApiAvailable ||
        _runningAction) {
      return;
    }
    await _run(() async {
      await widget.settings.saveLocal();
      await widget.coordinator.retry();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _runningAction = true;
      _actionError = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _actionError = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _runningAction = false;
        });
      }
    }
  }

  Widget _buildUrlField({required bool isIos}) {
    return TextField(
      key: const Key('app-startup-initial-data-api-url'),
      controller: _urlController,
      autofocus: !isIos,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      enableSuggestions: false,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(
        labelText: context.l10n.httpApiUrl,
        hintText: defaultRemoteDataApiBaseUrl,
      ),
      enabled: !_runningAction,
    );
  }

  Widget _buildUsernameField() {
    return TextField(
      key: const Key('app-startup-initial-data-api-username'),
      controller: _usernameController,
      textInputAction: TextInputAction.next,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: const <String>[AutofillHints.username],
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(labelText: context.l10n.username),
      enabled: !_runningAction,
    );
  }

  Widget _buildPasswordField() {
    final isLastEditableField = usesAutomaticallySynchronizedAppleKeychain;
    return TextField(
      key: const Key('app-startup-initial-data-api-password'),
      controller: _passwordController,
      textInputAction: isLastEditableField
          ? TextInputAction.done
          : TextInputAction.next,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: const <String>[AutofillHints.password],
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      onSubmitted: isLastEditableField
          ? (_) async {
              if (_canConnect) {
                await _connect();
              } else {
                FocusManager.instance.primaryFocus?.unfocus();
              }
            }
          : null,
      decoration: InputDecoration(labelText: context.l10n.password),
      enabled: !_runningAction,
    );
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller
        ..removeListener(_handleInputChanged)
        ..dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSkip =
        widget.requirement == AppStartupDataSetupRequirement.optional;
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('app-startup-data-api-setup'),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compactLandscape =
                isIos &&
                constraints.maxWidth >= 600 &&
                constraints.maxHeight < 600;
            final outerInset = compactLandscape ? 12.0 : 32.0;
            final cardInset = compactLandscape ? 16.0 : 28.0;
            final minimumHeight = constraints.maxHeight > outerInset * 2
                ? constraints.maxHeight - outerInset * 2
                : 0.0;
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.all(outerInset),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minimumHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: compactLandscape ? 760 : 560,
                    ),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.all(cardInset),
                        child: AutofillGroup(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (compactLandscape)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.cloud_outlined,
                                      size: 30,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        context.l10n.chooseDataMode,
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.titleLarge,
                                      ),
                                    ),
                                  ],
                                )
                              else ...[
                                Icon(
                                  Icons.cloud_outlined,
                                  size: 44,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  context.l10n.chooseDataMode,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineSmall,
                                ),
                              ],
                              SizedBox(height: compactLandscape ? 6 : 10),
                              Text(
                                canSkip
                                    ? widget.settings.localDataApiAvailable
                                          ? context
                                                .l10n
                                                .dataModeLocalBundledOrRemote
                                          : context.l10n.dataModeLocalOrRemote
                                    : context.l10n.remoteApiRequiredOnIos,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              SizedBox(height: compactLandscape ? 14 : 28),
                              _buildUrlField(isIos: isIos),
                              SizedBox(height: compactLandscape ? 10 : 14),
                              if (compactLandscape)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: _buildUsernameField()),
                                    const SizedBox(width: 12),
                                    Expanded(child: _buildPasswordField()),
                                  ],
                                )
                              else ...[
                                _buildUsernameField(),
                                const SizedBox(height: 14),
                                _buildPasswordField(),
                              ],
                              const SizedBox(height: 14),
                              if (usesAutomaticallySynchronizedAppleKeychain)
                                const _AppleMasterKeyNotice()
                              else
                                TextField(
                                  key: const Key(
                                    'app-startup-initial-master-key',
                                  ),
                                  controller: _portableMasterKeyController,
                                  textInputAction: TextInputAction.done,
                                  obscureText: true,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  onTapOutside: (_) => FocusManager
                                      .instance
                                      .primaryFocus
                                      ?.unfocus(),
                                  decoration: InputDecoration(
                                    labelText: context
                                        .l10n
                                        .masterKeyFromAnotherDeviceOptional,
                                    helperText:
                                        context.l10n.masterKeyOpenExistingHelp,
                                  ),
                                  enabled: !_runningAction,
                                  onSubmitted: (_) => _connect(),
                                ),
                              if (_actionError case final error?) ...[
                                const SizedBox(height: 14),
                                Text(
                                  error,
                                  key: const Key(
                                    'app-startup-initial-data-api-error',
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                              ],
                              if (_runningAction) ...[
                                const SizedBox(height: 18),
                                const LinearProgressIndicator(),
                              ],
                              SizedBox(height: compactLandscape ? 14 : 24),
                              if (canSkip)
                                if (compactLandscape &&
                                    !widget.settings.localDataApiAvailable)
                                  Row(
                                    children: [
                                      Expanded(
                                        child: SizedBox(
                                          height: 48,
                                          child: OutlinedButton(
                                            key: const Key(
                                              'app-startup-skip-data-api',
                                            ),
                                            onPressed: _runningAction
                                                ? null
                                                : _skip,
                                            child: Text(
                                              context
                                                  .l10n
                                                  .continueWithoutDataService,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: SizedBox(
                                          height: 48,
                                          child: FilledButton.icon(
                                            key: const Key(
                                              'app-startup-connect-data-api',
                                            ),
                                            onPressed:
                                                !_runningAction && _canConnect
                                                ? _connect
                                                : null,
                                            icon: const Icon(
                                              Icons.login_rounded,
                                            ),
                                            label: Text(
                                              context.l10n.connectRemoteApi,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (widget
                                          .settings
                                          .localDataApiAvailable) ...[
                                        OutlinedButton.icon(
                                          key: const Key(
                                            'app-startup-use-local-api',
                                          ),
                                          onPressed: !_runningAction
                                              ? _useLocalApi
                                              : null,
                                          icon: const Icon(
                                            Icons.storage_rounded,
                                          ),
                                          label: Text(
                                            context.l10n.useBundledLocalApi,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                      ],
                                      OverflowBar(
                                        alignment:
                                            MainAxisAlignment.spaceBetween,
                                        overflowAlignment:
                                            OverflowBarAlignment.end,
                                        spacing: 12,
                                        children: [
                                          TextButton(
                                            key: const Key(
                                              'app-startup-skip-data-api',
                                            ),
                                            onPressed: _runningAction
                                                ? null
                                                : _skip,
                                            child: Text(
                                              widget
                                                      .settings
                                                      .localDataApiAvailable
                                                  ? context
                                                        .l10n
                                                        .useLocalTerminalOnly
                                                  : context
                                                        .l10n
                                                        .continueWithoutDataService,
                                            ),
                                          ),
                                          FilledButton.icon(
                                            key: const Key(
                                              'app-startup-connect-data-api',
                                            ),
                                            onPressed:
                                                !_runningAction && _canConnect
                                                ? _connect
                                                : null,
                                            icon: const Icon(
                                              Icons.login_rounded,
                                            ),
                                            label: Text(
                                              context.l10n.connectRemoteApi,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  )
                              else
                                SizedBox(
                                  height: 48,
                                  child: FilledButton.icon(
                                    key: const Key(
                                      'app-startup-connect-data-api',
                                    ),
                                    onPressed: !_runningAction && _canConnect
                                        ? _connect
                                        : null,
                                    icon: const Icon(Icons.login_rounded),
                                    label: Text(
                                      context.l10n.connectAndContinue,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

final class _AppStartupLoadingView extends StatelessWidget {
  const _AppStartupLoadingView({required this.attempt});

  final int attempt;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Semantics(
          liveRegion: true,
          label: context.l10n.startingAppAttempt(attempt),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(context.l10n.preparingTerminalRuntime),
            ],
          ),
        ),
      ),
    );
  }
}

final class _AppStartupFailureView extends StatefulWidget {
  const _AppStartupFailureView({
    required this.failure,
    required this.coordinator,
  });

  final AppStartupFailure failure;
  final AppStartupCoordinator coordinator;

  @override
  State<_AppStartupFailureView> createState() => _AppStartupFailureViewState();
}

final class _AppStartupFailureViewState extends State<_AppStartupFailureView> {
  bool _runningAction = false;
  String? _actionError;

  Future<void> _retry() => _run(widget.coordinator.retry);

  Future<void> _openSettings() async {
    final settings = widget.failure.dataSettings;
    if (settings == null || _runningAction) {
      return;
    }
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AppStartupDataSettingsDialog(settings: settings),
    );
    if (changed == true && mounted) {
      await _retry();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_runningAction) {
      return;
    }
    setState(() {
      _runningAction = true;
      _actionError = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _actionError = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _runningAction = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = widget.failure;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.appCouldNotStart,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.startupStage(
                      context.l10n.startupStageName(failure.stage.name),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(failure.error.toString()),
                  if (_actionError case final error?) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      key: const Key('app-startup-action-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        key: const Key('app-startup-retry'),
                        onPressed: _runningAction ? null : _retry,
                        icon: const Icon(Icons.refresh),
                        label: Text(context.l10n.retryStartup),
                      ),
                      if (failure.dataSettings != null)
                        OutlinedButton.icon(
                          key: const Key('app-startup-open-data-settings'),
                          onPressed: _runningAction ? null : _openSettings,
                          icon: const Icon(Icons.storage_outlined),
                          label: Text(context.l10n.dataServiceSettings),
                        ),
                    ],
                  ),
                  if (_runningAction) ...[
                    const SizedBox(height: 20),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _AppStartupDataSettingsDialog extends StatefulWidget {
  const _AppStartupDataSettingsDialog({required this.settings});

  final AppStartupDataSettingsCapability settings;

  @override
  State<_AppStartupDataSettingsDialog> createState() =>
      _AppStartupDataSettingsDialogState();
}

final class _AppStartupDataSettingsDialogState
    extends State<_AppStartupDataSettingsDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _portableMasterKeyController = TextEditingController();
  DataApiConfiguration? _configuration;
  String? _loadError;
  String? _saveError;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final configuration = await widget.settings.loadForRecovery();
      if (mounted) {
        setState(() {
          _configuration = configuration;
          _loading = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _disable() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.disableDataServiceQuestion),
        content: Text(dialogContext.l10n.disableDataServiceExplanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(dialogContext.l10n.cancel),
          ),
          FilledButton(
            key: const Key('app-startup-confirm-disabled'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.l10n.useLocalTerminal),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _save(widget.settings.saveDisabled);
    }
  }

  Future<void> _reconnect() async {
    final remoteUri = _configuration?.remoteBaseUri;
    if (remoteUri == null) {
      return;
    }
    await _save(() async {
      final portableMasterKey = _portableMasterKeyController.text.trim();
      if (portableMasterKey.isNotEmpty) {
        final settings = widget.settings;
        if (settings is! AppStartupMasterKeyCapability) {
          throw StateError(context.l10n.masterKeyImportUnavailable);
        }
        await (settings as AppStartupMasterKeyCapability)
            .importPortableMasterKey(portableMasterKey);
      }
      return widget.settings.reconnect(
        DataApiRemoteLoginRequest(
          baseUri: remoteUri,
          username: _usernameController.text,
          password: _passwordController.text,
        ),
      );
    });
  }

  Future<void> _save(Future<void> Function() operation) async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await operation();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saveError = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _portableMasterKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remoteUri = _configuration?.remoteBaseUri;
    return AlertDialog(
      title: Text(context.l10n.dataServiceRecovery),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_loadError case final error?) ...[
                      Text(context.l10n.configurationReadFailed),
                      const SizedBox(height: 8),
                      SelectableText(error),
                    ] else if (remoteUri != null) ...[
                      Text(context.l10n.reconnectConfiguredOrigin),
                      const SizedBox(height: 12),
                      SelectableText(
                        remoteUri.toString(),
                        key: const Key('app-startup-remote-origin'),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('app-startup-remote-username'),
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: context.l10n.username,
                        ),
                        enabled: !_saving,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('app-startup-remote-password'),
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: context.l10n.password,
                        ),
                        obscureText: true,
                        enabled: !_saving,
                      ),
                      const SizedBox(height: 12),
                      if (usesAutomaticallySynchronizedAppleKeychain)
                        const _AppleMasterKeyNotice()
                      else
                        TextField(
                          key: const Key('app-startup-remote-master-key'),
                          controller: _portableMasterKeyController,
                          decoration: InputDecoration(
                            labelText:
                                context.l10n.masterKeyFromAnotherDeviceOptional,
                            helperText: context.l10n.masterKeyImportHelp,
                          ),
                          obscureText: true,
                          enabled: !_saving,
                        ),
                    ] else ...[
                      Text(
                        _configuration?.deployment == DataApiDeployment.local
                            ? context.l10n.localDataServiceStartFailed
                            : context.l10n.alreadyUsingLocalTerminal,
                      ),
                    ],
                    if (_saveError case final error?) ...[
                      const SizedBox(height: 12),
                      Text(
                        error,
                        key: const Key('app-startup-settings-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (_saving) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(context.l10n.cancel),
        ),
        OutlinedButton(
          key: const Key('app-startup-save-disabled'),
          onPressed: _saving ? null : _disable,
          child: Text(context.l10n.useLocalTerminal),
        ),
        if (remoteUri != null)
          FilledButton(
            key: const Key('app-startup-reconnect'),
            onPressed: _saving ? null : _reconnect,
            child: Text(context.l10n.reconnectAndRetry),
          ),
      ],
    );
  }
}

final class _AppleMasterKeyNotice extends StatelessWidget {
  const _AppleMasterKeyNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      key: const Key('app-startup-apple-keychain-status'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(
            Icons.cloud_done_rounded,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            context.l10n.appleMasterKeySynchronized,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
