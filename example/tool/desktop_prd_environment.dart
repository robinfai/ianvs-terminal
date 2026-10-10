import 'dart:convert';
import 'dart:io';

import 'package:app/app_bootstrap.dart';
import 'package:app/data/services/portable_master_key.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/persistence_repository_composition.dart';
import 'package:app/startup/app_environment.dart';
import 'package:app/startup/app_startup_coordinator.dart';
import 'package:app/startup/app_startup_host.dart';
import 'package:app/startup/production_app_startup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Storage and initial shell data for the manual desktop PRD entrypoint only.
/// This is a data fixture, not an operating-system sandbox for shell commands.
final class DesktopPrdEnvironment {
  DesktopPrdEnvironment._(this.root);

  static const markerName = '.trail-desktop-prd-fixture.v1.json';
  static const localProfileId = 'desktop-prd-local';

  final Directory root;
  Directory get supportBase => Directory('${root.path}/app-support');
  Directory get support =>
      AppEnvironment.development.supportDirectory(supportBase);
  Directory get home => Directory('${root.path}/home');
  Directory get temporary => Directory('${root.path}/tmp');

  late final PortableMasterKeyRepository masterKeyRepository =
      PortableMasterKeyRepository(
        allowLegacyMigration: false,
        storage: DevelopmentPortableMasterKeyStorage(
          directoryResolver: () async => support,
        ),
      );
  late final AiConfigurationStore aiConfigurationStore =
      createAiConfigurationStore(
        environment: AppEnvironment.development,
        appSupportDirectoryResolver: () async => supportBase,
      );

  Map<String, String> get shellEnvironment => Map<String, String>.unmodifiable({
    'HOME': home.path,
    'ZDOTDIR': home.path,
    'XDG_CONFIG_HOME': '${home.path}/.config',
    'XDG_CACHE_HOME': '${home.path}/.cache',
    'XDG_DATA_HOME': '${home.path}/.local/share',
    'XDG_STATE_HOME': '${home.path}/.local/state',
    'TMPDIR': '${temporary.path}/',
  });

  /// Only empty directories or complete fixtures created here may be opened.
  /// Reuse keeps manually saved AI, profile, layout and shell configuration.
  static Future<DesktopPrdEnvironment> prepare(Directory requestedRoot) async {
    final absolute = requestedRoot.absolute;
    final type = await FileSystemEntity.type(absolute.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Fixture root must be a directory, not a link.',
        absolute.path,
      );
    }
    await absolute.create(recursive: true);
    final root = Directory(await absolute.resolveSymbolicLinks());
    final fixture = DesktopPrdEnvironment._(root);
    final fresh = await root.list(followLinks: false).isEmpty;
    final marker = File('${root.path}/$markerName');
    final expectedMarker = <String, Object>{
      'schema_version': 1,
      'purpose': 'trail-desktop-prd-manual',
      'root': root.path,
    };
    if (!fresh) {
      final markerType = await FileSystemEntity.type(
        marker.path,
        followLinks: false,
      );
      Object? contents;
      if (markerType == FileSystemEntityType.file) {
        try {
          contents = jsonDecode(await marker.readAsString());
        } on FormatException {
          // An invalid marker must not authorize existing user data.
        }
      }
      if (contents is! Map<String, dynamic> ||
          !mapEquals(contents, expectedMarker)) {
        throw FileSystemException(
          'Refusing a nonempty directory without its matching PRD fixture marker.',
          root.path,
        );
      }
    }
    await fixture._prepareDirectories();
    if (fresh) {
      await File('${fixture.home.path}/.zshrc').writeAsString(
        "PROMPT='trail-prd%# '\nRPROMPT=''\nHISTFILE=\"\$HOME/.zsh_history\"\n",
        flush: true,
      );
      await fixture.masterKeyRepository.readOrCreate();
      final repositories = PersistenceRepositoryComposition.forRuntime(
        null,
        profileExportDirectoryResolver: () async => fixture.support,
        masterKeyRepository: fixture.masterKeyRepository,
      );
      try {
        await repositories.profiles.save(
          TerminalProfilesDocument(
            profiles: [
              TerminalProfile(
                id: localProfileId,
                name: 'Desktop PRD local fixture',
                shell: '/bin/zsh',
                args: const ['-l'],
                cwd: fixture.home.path,
                env: fixture.shellEnvironment,
              ),
            ],
          ),
        );
      } finally {
        await repositories.sync.close();
      }
      // A failed preparation leaves no marker, so it cannot silently reuse a
      // partially initialized directory on the next launch.
      await marker.writeAsString(jsonEncode(expectedMarker), flush: true);
    }
    return fixture;
  }

  Future<void> _prepareDirectories() async {
    final directories = [
      root,
      supportBase,
      support,
      Directory('${support.path}/secrets'),
      home,
      temporary,
      Directory('${home.path}/.config'),
      Directory('${home.path}/.cache'),
      Directory('${home.path}/.local'),
      Directory('${home.path}/.local/share'),
      Directory('${home.path}/.local/state'),
    ];
    for (final directory in directories) {
      final type = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw FileSystemException(
          'Fixture storage directories must not be symbolic links.',
          directory.path,
        );
      }
      await directory.create(recursive: true);
    }
    final chmod = await Process.run('/bin/chmod', ['700', root.path]);
    if (chmod.exitCode != 0) {
      throw FileSystemException(
        'Could not restrict fixture access.',
        root.path,
      );
    }
  }
}

AppStartupCoordinator createDesktopPrdStartupCoordinator(
  DesktopPrdEnvironment environment, {
  AppStartupNativePtyLoader? nativePtyLoader,
}) => createProductionAppStartupCoordinator(
  platform: TargetPlatform.macOS,
  environment: AppEnvironment.development,
  appSupportDirectoryResolver: () async => environment.supportBase,
  masterKeyRepository: environment.masterKeyRepository,
  nativePtyLoader: nativePtyLoader,
);

Widget buildDesktopPrdApp({
  required DesktopPrdEnvironment environment,
  required AppStartupCoordinator coordinator,
}) => AppStartupHost(
  coordinator: coordinator,
  runtimeBuilder: (graph) {
    final root = buildIanvsTerminalRuntimeRoot(
      graph: graph,
      sessionEnvironmentOverrides: environment.shellEnvironment,
    );
    if (root is! ProviderScope) {
      throw StateError(
        'The production runtime must supply its root ProviderScope.',
      );
    }
    // Keep one root: an outer scope would own providers that do not declare
    // scoped dependencies and could bypass the production runtime overrides.
    // Reuse the production graph's entire assembly and add only fixture AI
    // storage; the startup host retains its normal runtime/shutdown ownership.
    return ProviderScope(
      key: root.key,
      observers: root.observers,
      retry: root.retry,
      overrides: [
        ...root.overrides,
        aiSettingsProvider.overrideWith((ref) {
          final controller = AiSettingsController(
            environment.aiConfigurationStore,
          );
          ref.onDispose(controller.dispose);
          return controller;
        }),
      ],
      child: root.child,
    );
  },
);
