import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_bootstrap.dart';
import '../data/configuration/data_api_configuration.dart';
import '../data/configuration/data_api_configuration_repository.dart';
import '../ui/app_ui.dart';
import 'app_startup_coordinator.dart';
import 'app_startup_lifecycle.dart';
import 'app_startup_models.dart';

typedef AppStartupRuntimeBuilder = Widget Function(AppRuntimeGraph graph);

final class AppStartupHost extends StatefulWidget {
  const AppStartupHost({
    required this.coordinator,
    this.disposeCoordinator = true,
    this.enableSessionPolling = true,
    this.enableShellAnimations = true,
    this.enableReferenceDemoMode = false,
    this.shutdownChannel = const MethodChannel('app/shutdown'),
    this.runtimeBuilder,
    super.key,
  });

  final AppStartupCoordinator coordinator;
  final bool disposeCoordinator;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(widget.coordinator.start());
      }
    });
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
      title: 'Ianvs Terminal',
      debugShowCheckedModeBanner: false,
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
  final _urlController = TextEditingController();
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
          throw StateError('Master-key import is unavailable.');
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
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('app-startup-data-api-setup'),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final minimumHeight = constraints.maxHeight > 64
                ? constraints.maxHeight - 64
                : 0.0;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minimumHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: AutofillGroup(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Icon(
                                Icons.cloud_outlined,
                                size: 44,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Choose your data mode',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                canSkip
                                    ? widget.settings.localDataApiAvailable
                                          ? 'Use only local terminals, start '
                                                'the bundled offline API, or '
                                                'connect a remote API for '
                                                'cross-device sync.'
                                          : 'Continue without a data service '
                                                'for one-time SSH connections, '
                                                'or connect a remote API to '
                                                'save profiles and sync them.'
                                    : 'A remote HTTP API connection is '
                                          'required before Ianvs Terminal can '
                                          'be used on iOS.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 28),
                              TextField(
                                key: const Key(
                                  'app-startup-initial-data-api-url',
                                ),
                                controller: _urlController,
                                autofocus: true,
                                keyboardType: TextInputType.url,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: const InputDecoration(
                                  labelText: 'HTTP API URL',
                                  hintText: 'https://api.example.com/',
                                ),
                                enabled: !_runningAction,
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                key: const Key(
                                  'app-startup-initial-data-api-username',
                                ),
                                controller: _usernameController,
                                textInputAction: TextInputAction.next,
                                autocorrect: false,
                                enableSuggestions: false,
                                autofillHints: const <String>[
                                  AutofillHints.username,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                ),
                                enabled: !_runningAction,
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                key: const Key(
                                  'app-startup-initial-data-api-password',
                                ),
                                controller: _passwordController,
                                textInputAction: TextInputAction.next,
                                obscureText: true,
                                autocorrect: false,
                                enableSuggestions: false,
                                autofillHints: const <String>[
                                  AutofillHints.password,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                ),
                                enabled: !_runningAction,
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                key: const Key(
                                  'app-startup-initial-master-key',
                                ),
                                controller: _portableMasterKeyController,
                                textInputAction: TextInputAction.done,
                                obscureText: true,
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: const InputDecoration(
                                  labelText:
                                      'Master key from another device (optional)',
                                  helperText:
                                      'Paste an exported ianvs-key-v1 key to '
                                      'open existing encrypted data.',
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
                              const SizedBox(height: 24),
                              if (canSkip)
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
                                        icon: const Icon(Icons.storage_rounded),
                                        label: const Text(
                                          'Use bundled local API',
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                    OverflowBar(
                                      alignment: MainAxisAlignment.spaceBetween,
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
                                                ? 'Use local terminal only'
                                                : 'Continue without data service',
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
                                          icon: const Icon(Icons.login_rounded),
                                          label: const Text(
                                            'Connect remote API',
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
                                    label: const Text('Connect and continue'),
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
          label: 'Starting Ianvs Terminal, attempt $attempt',
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Preparing terminal runtime…'),
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
                    'Ianvs Terminal could not start',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text('Stage: ${failure.stage.name}'),
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
                        label: const Text('Retry startup'),
                      ),
                      if (failure.dataSettings != null)
                        OutlinedButton.icon(
                          key: const Key('app-startup-open-data-settings'),
                          onPressed: _runningAction ? null : _openSettings,
                          icon: const Icon(Icons.storage_outlined),
                          label: const Text('Data service settings'),
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
        title: const Text('Disable the data service?'),
        content: const Text(
          'This explicitly switches to local-terminal-only mode on the next '
          'startup attempt. No API process will start; existing remote data '
          'is not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('app-startup-confirm-disabled'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Use local terminal'),
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
          throw StateError('Master-key import is unavailable.');
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
      title: const Text('Data service recovery'),
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
                      const Text(
                        'The current configuration could not be read. You can '
                        'still explicitly select Disabled.',
                      ),
                      const SizedBox(height: 8),
                      SelectableText(error),
                    ] else if (remoteUri != null) ...[
                      const Text(
                        'Reconnect to the configured remote origin before '
                        'startup retries. The origin cannot be changed here.',
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        remoteUri.toString(),
                        key: const Key('app-startup-remote-origin'),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('app-startup-remote-username'),
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                        ),
                        enabled: !_saving,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('app-startup-remote-password'),
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                        obscureText: true,
                        enabled: !_saving,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('app-startup-remote-master-key'),
                        controller: _portableMasterKeyController,
                        decoration: const InputDecoration(
                          labelText:
                              'Master key from another device (optional)',
                          helperText:
                              'Paste an exported ianvs-key-v1 key when this '
                              'device does not already have it.',
                        ),
                        obscureText: true,
                        enabled: !_saving,
                      ),
                    ] else ...[
                      Text(
                        _configuration?.deployment == DataApiDeployment.local
                            ? 'The local data service could not start. Select '
                                  'local terminal mode to continue without an '
                                  'API. Local API data is retained.'
                            : 'The app is already in local terminal mode. '
                                  'Retry startup or save that mode again to '
                                  'clear its recovery lock.',
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
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          key: const Key('app-startup-save-disabled'),
          onPressed: _saving ? null : _disable,
          child: const Text('Use local terminal'),
        ),
        if (remoteUri != null)
          FilledButton(
            key: const Key('app-startup-reconnect'),
            onPressed: _saving ? null : _reconnect,
            child: const Text('Reconnect and retry'),
          ),
      ],
    );
  }
}
