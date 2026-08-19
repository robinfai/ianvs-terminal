part of 'shell_screen.dart';

extension _ShellScreenStateProfileActions on _ShellScreenState {
  bool get _localSessionsEnabled =>
      ref.read(terminalSessionLaunchPolicyProvider).localSessionsEnabled;
  bool get _customSshProfilesEnabled =>
      ref.read(customSshProfileConfigurationEnabledProvider);

  bool _canOpenNewSessionLauncher(SessionState sessionState) =>
      !_localSessionsEnabled || sessionState.profiles.isNotEmpty;

  Future<void> _openNewSessionLauncher(
    SessionController sessionController,
    SessionState sessionState,
  ) async {
    if (_isProfilesOpen) {
      return;
    }
    _mutateState(() => _isProfilesOpen = true);
    await releaseTerminalInputForModal();
    if (!mounted) return;
    final activeSessionIdBeforeOpen = sessionState.activeSessionId;
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    final result = await showModalBottomSheet<NewSessionSelection>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (context) => NewSessionLauncher(
        profiles: ref.read(sessionControllerProvider).profiles,
        localSessionsEnabled: _localSessionsEnabled,
        customSshProfilesEnabled: _customSshProfilesEnabled,
        importOpenSshProfiles: () =>
            ref.read(sshProfileImportServiceProvider).load(),
      ),
    );
    if (!mounted) {
      return;
    }
    _mutateState(() => _isProfilesOpen = false);
    if (result == null) {
      _restoreSessionFocus(
        activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
        activeSessionIdAfterClose: ref
            .read(sessionControllerProvider)
            .activeSessionId,
      );
      return;
    }
    await _completeNewSessionSelection(
      sessionController,
      result,
      activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
    );
  }

  Future<void> _openSshProfileCreator(
    SessionController sessionController,
    SessionState sessionState,
  ) async {
    if (_isProfilesOpen) {
      return;
    }
    _mutateState(() => _isProfilesOpen = true);
    await releaseTerminalInputForModal();
    if (!mounted) return;
    final activeSessionIdBeforeOpen = sessionState.activeSessionId;
    final result = await showCreateSshProfileDialog(
      context,
      saveProfileAvailable: _customSshProfilesEnabled,
    );
    if (!mounted) {
      return;
    }
    _mutateState(() => _isProfilesOpen = false);
    if (result == null) {
      _restoreSessionFocus(
        activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
        activeSessionIdAfterClose: ref
            .read(sessionControllerProvider)
            .activeSessionId,
      );
      return;
    }
    await _completeNewSessionSelection(
      sessionController,
      NewSessionSelection(
        profile: result.profile,
        saveProfile: result.saveProfile,
      ),
      activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
    );
  }

  Future<void> _completeNewSessionSelection(
    SessionController sessionController,
    NewSessionSelection result, {
    required String? activeSessionIdBeforeOpen,
  }) async {
    if (result.saveProfile) {
      try {
        if (!_customSshProfilesEnabled) {
          throw const CustomSshProfileConfigurationUnavailableException();
        }
        await sessionController.saveProfile(result.profile);
        _showShellSnackBar(
          '${result.openSession ? 'Saved' : 'Imported'} SSH profile '
          '“${result.profile.name}” to '
          '${_activeProfilePersistenceLabel()}.',
        );
      } on Object catch (error) {
        final connectOnce = await _showProfileSaveFailure(
          profileName: result.profile.name,
          error: error,
          allowConnectOnce: result.openSession,
        );
        if (!mounted || !connectOnce) {
          _restoreSessionFocus(
            activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
            activeSessionIdAfterClose: ref
                .read(sessionControllerProvider)
                .activeSessionId,
          );
          return;
        }
      }
    }
    if (!result.openSession) {
      _restoreSessionFocus(
        activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
        activeSessionIdAfterClose: ref
            .read(sessionControllerProvider)
            .activeSessionId,
      );
      return;
    }
    _createSession(
      sessionController,
      result.profile,
      returningToLayout: activeSessionIdBeforeOpen == null,
    );
  }

  Future<void> _handleNativeAppMenuAction(NativeAppMenuAction action) {
    switch (action) {
      case NativeAppMenuAction.settings:
        unawaited(
          _openDefaultsAndAppearance(
            ref.read(sessionControllerProvider.notifier),
            ref.read(sessionControllerProvider),
          ),
        );
    }
    return Future<void>.value();
  }

  Future<void> _openDefaultsAndAppearance(
    SessionController sessionController,
    SessionState sessionState,
  ) async {
    if (_isDefaultsOpen) {
      return;
    }

    _mutateState(() {
      _isDefaultsOpen = true;
    });
    _publishAcceptanceSnapshot(sessionState);

    final dataApiConfigurationRepository = ref.read(
      dataApiConfigurationRepositoryProvider,
    );
    var dataApiConfiguration = const DataApiConfiguration.disabled();
    if (dataApiConfigurationRepository != null) {
      try {
        dataApiConfiguration = switch (dataApiConfigurationRepository) {
          final DataApiConfigurationRecoveryLoader recoveryLoader =>
            await recoveryLoader.loadForRecovery(),
          _ => await dataApiConfigurationRepository.load(),
        };
      } on Object catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Unable to read the data service configuration: $error',
              ),
            ),
          );
        }
      }
    }
    final dataApiConfigurationRecoveryRequired =
        ref.read(dataApiConfigurationRecoveryRequiredProvider) ||
        switch (dataApiConfigurationRepository) {
          final DataApiConfigurationRecoveryStatus status =>
            status.recoveryRequired,
          _ => false,
        };

    if (!mounted) {
      return;
    }

    final activeSessionIdBeforeOpen = sessionState.activeSessionId;
    final defaultsRoute = DialogRoute<DefaultsAndAppearanceSelection>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.34),
      barrierDismissible: true,
      barrierLabel: 'Close defaults',
      requestFocus: true,
      builder: (dialogContext) => DefaultsAndAppearanceDialog(
        profiles: sessionState.profiles,
        configuredDefaultProfileId: sessionState.configuredDefaultProfileId,
        effectiveDefaultProfileId: sessionState.defaultProfileId,
        themeMode: sessionState.themeMode,
        terminalViewportPadding: sessionState.terminalViewportPadding,
        restoreLayout: _notificationLocalConfig.layout.restoreLayout,
        osc52Policy: _clipboardConfig.osc52,
        openUrlPolicy: _hostActionsConfig.osc1337OpenUrl,
        requestAttentionPolicy: _hostActionsConfig.osc1337RequestAttention,
        reportVariableDecisions: _hostActionsConfig.osc1337ReportVariables,
        keybindings: _keybindingsConfig,
        dataApiConfiguration: dataApiConfiguration,
        activeDataApiDeployment:
            widget.activeDataApiDeployment ??
            ref.read(dataApiRuntimeProvider)?.deployment ??
            dataApiConfiguration.deployment,
        dataApiConfigurationRecoveryRequired:
            dataApiConfigurationRecoveryRequired,
        localDataApiAvailable: defaultTargetPlatform == TargetPlatform.macOS,
        localSessionsEnabled: _localSessionsEnabled,
        masterKeyRepository: ref.read(portableMasterKeyRepositoryProvider),
      ),
    );
    final selection = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<DefaultsAndAppearanceSelection>(defaultsRoute);
    await defaultsRoute.completed;

    if (!mounted) {
      return;
    }

    _mutateState(() {
      _isDefaultsOpen = false;
    });
    _publishAcceptanceSnapshot();

    if (selection != null) {
      if (selection.openProfiles) {
        await _openProfilesSheet(
          sessionController,
          ref.read(sessionControllerProvider),
        );
        return;
      }
      final stateBeforeSave = ref.read(sessionControllerProvider);
      if (selection.configuredDefaultProfileId !=
          stateBeforeSave.configuredDefaultProfileId) {
        if (selection.configuredDefaultProfileId == null) {
          await sessionController.resetDefaultProfile();
        } else {
          await sessionController.setDefaultProfile(
            selection.configuredDefaultProfileId!,
          );
        }
      }
      if (selection.themeMode != stateBeforeSave.themeMode) {
        await sessionController.setThemeMode(selection.themeMode);
      }
      if (selection.terminalViewportPadding !=
          stateBeforeSave.terminalViewportPadding) {
        await sessionController.setTerminalViewportPadding(
          selection.terminalViewportPadding,
        );
      }
      if (selection.restoreLayout !=
          _notificationLocalConfig.layout.restoreLayout) {
        await sessionController.setRestoreLayout(selection.restoreLayout);
        if (!mounted) {
          return;
        }
        _mutateState(() {
          _notificationConfigSource =
              LocalTerminalConfigBootstrapSource.localConfig;
          _notificationLocalConfig = _notificationLocalConfig.copyWith(
            layout: LocalTerminalLayoutConfig(
              restoreLayout: selection.restoreLayout,
            ),
          );
        });
      }
      if (selection.osc52Policy != _clipboardConfig.osc52) {
        await sessionController.setOsc52Policy(selection.osc52Policy);
        if (!mounted) {
          return;
        }
        _mutateState(() {
          _clipboardConfig = _clipboardConfig.copyWith(
            osc52: selection.osc52Policy,
          );
        });
      }
      if (selection.openUrlPolicy != _hostActionsConfig.osc1337OpenUrl) {
        await sessionController.setOsc1337OpenUrlPolicy(
          selection.openUrlPolicy,
        );
        if (!mounted) {
          return;
        }
        _mutateState(() {
          _hostActionsConfig = _hostActionsConfig.copyWith(
            osc1337OpenUrl: selection.openUrlPolicy,
          );
        });
      }
      if (selection.requestAttentionPolicy !=
          _hostActionsConfig.osc1337RequestAttention) {
        await sessionController.setOsc1337RequestAttentionPolicy(
          selection.requestAttentionPolicy,
        );
        if (!mounted) {
          return;
        }
        _mutateState(() {
          _hostActionsConfig = _hostActionsConfig.copyWith(
            osc1337RequestAttention: selection.requestAttentionPolicy,
          );
        });
        if (selection.requestAttentionPolicy ==
            LocalTerminalRequestAttentionPolicy.disabled) {
          unawaited(_cancelAllOsc1337AttentionRequests());
        }
      }
      if (!mapEquals(
        selection.reportVariableDecisions,
        _hostActionsConfig.osc1337ReportVariables,
      )) {
        await sessionController.replaceOsc1337ReportVariableDecisions(
          selection.reportVariableDecisions,
        );
        if (!mounted) {
          return;
        }
        _mutateState(() {
          _hostActionsConfig = _hostActionsConfig.copyWith(
            osc1337ReportVariables: Map.unmodifiable(
              selection.reportVariableDecisions,
            ),
          );
        });
      }
      if (selection.keybindings != _keybindingsConfig) {
        await sessionController.setKeybindings(selection.keybindings);
        if (!mounted) {
          return;
        }
        _mutateState(() {
          _notificationConfigSource =
              LocalTerminalConfigBootstrapSource.localConfig;
          _keybindingsConfig = selection.keybindings;
          _notificationLocalConfig = _notificationLocalConfig.copyWith(
            keybindings: selection.keybindings,
          );
        });
      }
      if (selection.dataApiConfiguration != dataApiConfiguration ||
          selection.dataApiRemoteLogin != null ||
          dataApiConfigurationRecoveryRequired) {
        if (dataApiConfigurationRepository == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Data service configuration is unavailable in this build.',
                ),
              ),
            );
          }
        } else {
          try {
            final remoteLogin = selection.dataApiRemoteLogin;
            if (selection.dataApiConfiguration.deployment ==
                DataApiDeployment.remote) {
              final DataApiRemoteConfigurationConnector? connector =
                  switch (dataApiConfigurationRepository) {
                    final DataApiRemoteConfigurationConnector value => value,
                    _ => null,
                  };
              if (remoteLogin == null || connector == null) {
                throw StateError(
                  'Remote authentication is unavailable in this build.',
                );
              }
              DataApiMigrationSummary? migrationSummary;
              if (selection.migrateLocalDataToRemote) {
                final migrationConnector =
                    switch (dataApiConfigurationRepository) {
                      final DataApiLocalToRemoteConfigurationConnector value =>
                        value,
                      _ => null,
                    };
                final sourceRuntime = ref.read(dataApiRuntimeProvider);
                if (migrationConnector == null ||
                    sourceRuntime == null ||
                    !sourceRuntime.isLocal) {
                  throw StateError(
                    'The active bundled local API is unavailable for migration.',
                  );
                }
                migrationSummary = await migrationConnector
                    .migrateLocalAndSaveRemote(
                      remoteLogin,
                      sourceRuntime: sourceRuntime,
                    );
              } else {
                await connector.connectAndSaveRemote(remoteLogin);
              }
              if (mounted && migrationSummary != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    key: const Key('data-api-migration-complete'),
                    content: Text(
                      'Migrated ${migrationSummary.resourceCount} local '
                      'resource(s): ${migrationSummary.created} created, '
                      '${migrationSummary.updated} updated, '
                      '${migrationSummary.skipped} already current. Restart '
                      'the app to use the remote API.',
                    ),
                  ),
                );
              }
            } else if (selection.migrateRemoteDataToLocal) {
              final migrationConnector =
                  switch (dataApiConfigurationRepository) {
                    final DataApiRemoteToLocalConfigurationConnector value =>
                      value,
                    _ => null,
                  };
              final sourceRuntime = ref.read(dataApiRuntimeProvider);
              final startLocalRuntime = ref.read(
                dataApiLocalMigrationRuntimeStarterProvider,
              );
              if (migrationConnector == null ||
                  sourceRuntime == null ||
                  sourceRuntime.deployment != DataApiDeployment.remote ||
                  startLocalRuntime == null) {
                throw StateError(
                  'Remote-to-local migration is unavailable in this build.',
                );
              }
              final migrationSummary =
                  await withTemporaryDataApiRuntime<DataApiMigrationSummary>(
                    startRuntime: startLocalRuntime,
                    operation: (destinationRuntime) =>
                        migrationConnector.migrateRemoteAndSaveLocal(
                          sourceRuntime: sourceRuntime,
                          destinationRuntime: destinationRuntime,
                        ),
                  );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    key: const Key('data-api-migration-complete'),
                    content: Text(
                      'Migrated ${migrationSummary.resourceCount} remote '
                      'resource(s): ${migrationSummary.created} created, '
                      '${migrationSummary.updated} updated, '
                      '${migrationSummary.skipped} already current. Restart '
                      'the app to use the bundled local API.',
                    ),
                  ),
                );
              }
            } else {
              await dataApiConfigurationRepository.save(
                selection.dataApiConfiguration,
              );
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Data service configuration saved. Restart the app to apply it.',
                  ),
                ),
              );
            }
          } on DataApiRemoteRevocationPendingWarning catch (warning) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  key: const Key('data-api-revocation-pending-warning'),
                  content: Text(warning.toString()),
                ),
              );
            }
          } on DataApiSecureSessionMutationException catch (warning) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  key: const Key('data-api-secure-session-warning'),
                  content: Text(warning.toString()),
                ),
              );
            }
          } on Object catch (error) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Unable to save the data service configuration: $error',
                  ),
                ),
              );
            }
          }
        }
      }
      final updatedProfile = selection.updatedProfile;
      if (updatedProfile != null) {
        await _saveProfileWithFeedback(sessionController, updatedProfile);
      }
    }

    _restoreSessionFocus(
      activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
      activeSessionIdAfterClose: ref
          .read(sessionControllerProvider)
          .activeSessionId,
    );
  }

  Future<void> _openProfilesSheet(
    SessionController sessionController,
    SessionState sessionState,
  ) async {
    if (_isProfilesOpen) {
      return;
    }

    _mutateState(() {
      _isProfilesOpen = true;
    });
    _publishAcceptanceSnapshot(sessionState);

    final activeSessionIdBeforeOpen = sessionState.activeSessionId;
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    final result = await showModalBottomSheet<ProfilesSheetResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) {
        return ProfilesSheet(
          profiles: sessionState.profiles,
          effectiveDefaultProfileId: sessionState.defaultProfileId,
          localShellProfilesEnabled: _localSessionsEnabled,
          customSshProfilesEnabled: _customSshProfilesEnabled,
        );
      },
    );

    if (!mounted) {
      return;
    }

    _mutateState(() {
      _isProfilesOpen = false;
    });
    _publishAcceptanceSnapshot();

    switch (result) {
      case OpenProfileResult(:final profile):
        _createSession(
          sessionController,
          profile,
          returningToLayout: activeSessionIdBeforeOpen == null,
        );
        return;
      case EditProfileResult(:final profile):
        final TerminalProfile? edited;
        var clearSecrets = const <ProfileSecretField>{};
        if (profile.isSsh) {
          final editResult = await showDialog<SshProfileEditorResult>(
            context: context,
            builder: (dialogContext) => SshProfileEditorDialog(
              initialValue: profile,
              saveWhenPristine: false,
            ),
          );
          edited = editResult?.profile;
          clearSecrets = editResult?.clearSecrets ?? const {};
        } else {
          edited = await showDialog<TerminalProfile>(
            context: context,
            builder: (dialogContext) => ProfileEditorDialog(
              initialValue: profile,
              saveWhenPristine: false,
            ),
          );
        }
        if (edited != null) {
          await _saveProfileWithFeedback(
            sessionController,
            edited,
            clearSecrets: clearSecrets,
          );
        }
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: ref
              .read(sessionControllerProvider)
              .activeSessionId,
        );
        return;
      case DeleteProfileResult(:final profile):
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete profile?'),
            content: Text(
              'Delete “${profile.name}”? Open terminal tabs will keep their current session settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              AppActionButton(
                buttonKey: const Key('confirm-delete-profile'),
                tone: AppActionTone.danger,
                label: 'Delete',
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          try {
            await sessionController.deleteProfile(profile.id);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Deleted profile “${profile.name}”.')),
              );
            }
          } on Object catch (error) {
            await _showProfileSaveFailure(
              profileName: profile.name,
              error: error,
              allowConnectOnce: false,
              title: 'Profile was not deleted',
              summary:
                  '“${profile.name}” is still stored in '
                  '${_activeProfilePersistenceLabel()}.',
            );
          }
        }
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: ref
              .read(sessionControllerProvider)
              .activeSessionId,
        );
        return;
      case CreateProfileResult(:final connectionType):
        final template = _newProfileTemplate(
          sessionState.profiles,
          connectionType: connectionType,
        );
        final edited = connectionType == NewProfileConnectionType.sshSession
            ? (await showDialog<SshProfileEditorResult>(
                context: context,
                builder: (dialogContext) => SshProfileEditorDialog(
                  initialValue: template,
                  saveWhenPristine: true,
                ),
              ))?.profile
            : await showDialog<TerminalProfile>(
                context: context,
                builder: (dialogContext) => ProfileEditorDialog(
                  title: 'New profile',
                  initialValue: template,
                  saveWhenPristine: true,
                ),
              );
        if (edited != null) {
          await _saveProfileWithFeedback(sessionController, edited);
        }
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: ref
              .read(sessionControllerProvider)
              .activeSessionId,
        );
        return;
      case null:
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: ref
              .read(sessionControllerProvider)
              .activeSessionId,
        );
        return;
    }
  }

  TerminalProfile _newProfileTemplate(
    List<TerminalProfile> existingProfiles, {
    NewProfileConnectionType connectionType =
        NewProfileConnectionType.localShell,
  }) {
    final existingIds = {for (final profile in existingProfiles) profile.id};
    var suffix = 1;
    var id = 'profile-$suffix';
    while (existingIds.contains(id)) {
      suffix += 1;
      id = 'profile-$suffix';
    }
    final profile = defaultTerminalProfile().copyWith(
      id: id,
      name: connectionType == NewProfileConnectionType.sshSession
          ? 'New SSH Profile'
          : 'New Profile',
    );
    if (connectionType == NewProfileConnectionType.localShell) {
      return profile;
    }
    return profile.copyWith(
      connection: const terminal.TerminalConnectionConfig.ssh(
        host: '',
        user: '',
      ),
    );
  }

  Future<bool> _saveProfileWithFeedback(
    SessionController sessionController,
    TerminalProfile profile, {
    Set<ProfileSecretField> clearSecrets = const {},
  }) async {
    try {
      await sessionController.saveProfile(profile, clearSecrets: clearSecrets);
      _showShellSnackBar(
        'Saved profile “${profile.name}” to '
        '${_activeProfilePersistenceLabel()}.',
      );
      return true;
    } on Object catch (error) {
      await _showProfileSaveFailure(
        profileName: profile.name,
        error: error,
        allowConnectOnce: false,
      );
      return false;
    }
  }

  String _activeProfilePersistenceLabel() {
    return switch (ref.read(dataApiRuntimeProvider)?.deployment) {
      DataApiDeployment.remote => 'Remote service',
      DataApiDeployment.local => 'Bundled local service',
      DataApiDeployment.disabled || null => 'profile storage',
    };
  }

  Future<bool> _showProfileSaveFailure({
    required String profileName,
    required Object error,
    required bool allowConnectOnce,
    String title = 'Profile was not saved',
    String? summary,
  }) async {
    if (!mounted) {
      return false;
    }
    final destination = _activeProfilePersistenceLabel();
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            key: const Key('profile-save-failure-dialog'),
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary ??
                      '“$profileName” was not written to $destination. '
                          'It will not appear on your other devices.',
                ),
                const SizedBox(height: 12),
                Text(
                  _profileSaveFailureMessage(error),
                  key: const Key('profile-save-failure-message'),
                ),
                if (allowConnectOnce) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'You can cancel and try saving again, or explicitly '
                    'continue with a one-time connection.',
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                key: const Key('profile-save-failure-cancel'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(allowConnectOnce ? 'Cancel connection' : 'OK'),
              ),
              if (allowConnectOnce)
                FilledButton(
                  key: const Key('profile-save-failure-connect-once'),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Connect once without saving'),
                ),
            ],
          ),
        ) ??
        false;
  }

  String _profileSaveFailureMessage(Object error) {
    return switch (error) {
      DataApiRevisionConflictException() =>
        'Profiles changed on another device while this save was in progress. '
            'Reload the profiles and try again.',
      DataApiAuthenticationRequiredException() =>
        'The Remote service session is no longer authenticated. Open Data '
            'service settings, sign in again, and retry the save.',
      DataApiTimeoutException() =>
        'The Remote service did not respond in time. Check the network '
            'connection and try again.',
      DataApiRequestException(:final statusCode, :final code, :final message) =>
        'Remote service rejected the save ($statusCode/$code): $message',
      DataApiProtocolException(:final message) =>
        'The Remote service returned an invalid response: $message',
      CustomSshProfileConfigurationUnavailableException() =>
        'Persistent SSH profiles require a connected bundled local or Remote '
            'service. Open Data service settings and connect one first.',
      _ => 'Save failed: $error',
    };
  }

  Future<void> _openDynamicProfiles(SessionController sessionController) async {
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    final result = await showModalBottomSheet<DynamicProfilesImportResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: animationsEnabled
          ? null
          : AnimationStyle.noAnimation,
      builder: (sheetContext) => DynamicProfilesSheet(
        existingProfiles: ref.read(sessionControllerProvider).profiles,
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    for (final profile in result.profiles) {
      if (!await _saveProfileWithFeedback(sessionController, profile)) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Imported ${result.profiles.length} dynamic profile${result.profiles.length == 1 ? '' : 's'}'
          '${result.replacementCount == 0 ? '' : ' (${result.addedCount} new, ${result.replacementCount} replaced)'}'
          '${result.warningCount == 0 ? '' : ' with ${result.warningCount} warning${result.warningCount == 1 ? '' : 's'}'}',
        ),
      ),
    );
  }

  ShellActionProductionRuntimeAdapter _buildScopedProductionActionAdapter({
    required Set<String> requiredActionNames,
    required ShellActionProductionCallbacks callbacks,
  }) {
    return ShellActionProductionRuntimeAdapter.fromCallbacks(
      actionSet: ShellActionProductionActionSet(
        requiredActionNames: requiredActionNames,
      ),
      callbacks: callbacks,
    );
  }
}
