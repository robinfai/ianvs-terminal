part of 'shell_screen.dart';

extension _ShellScreenStateProfileActions on _ShellScreenState {
  Future<void> _openNewSessionLauncher(
    SessionController sessionController,
    SessionState sessionState,
  ) async {
    if (_isProfilesOpen) {
      return;
    }
    _mutateState(() => _isProfilesOpen = true);
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
    if (result.saveProfile) {
      try {
        await sessionController.saveProfile(result.profile);
      } on Object catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'SSH profile was not saved ($error). Connecting once instead.',
              ),
            ),
          );
        }
      }
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

    final activeSessionIdBeforeOpen = sessionState.activeSessionId;
    final animationsEnabled = ref.read(shellAnimationsEnabledProvider);
    final defaultsRoute = RawDialogRoute<DefaultsAndAppearanceSelection>(
      barrierColor: Colors.black.withValues(alpha: 0.34),
      barrierDismissible: true,
      barrierLabel: 'Close defaults',
      requestFocus: true,
      transitionDuration: animationsEnabled
          ? const Duration(milliseconds: 160)
          : Duration.zero,
      pageBuilder: (dialogContext, _, _) => SafeArea(
        child: Align(
          alignment: Alignment.center,
          child: DefaultsAndAppearanceDialog(
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
          ),
        ),
      ),
      transitionBuilder: (dialogContext, animation, _, child) {
        if (!animationsEnabled) {
          return child;
        }
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(opacity: curved, child: child);
      },
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
      final updatedProfile = selection.updatedProfile;
      if (updatedProfile != null) {
        await sessionController.saveProfile(updatedProfile);
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
            builder: (dialogContext) =>
                SshProfileEditorDialog(initialValue: profile),
          );
          edited = editResult?.profile;
          clearSecrets = editResult?.clearSecrets ?? const {};
        } else {
          edited = await showDialog<TerminalProfile>(
            context: context,
            builder: (dialogContext) =>
                ProfileEditorDialog(initialValue: profile),
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
          await sessionController.deleteProfile(profile.id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Deleted profile “${profile.name}”.')),
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
                builder: (dialogContext) =>
                    SshProfileEditorDialog(initialValue: template),
              ))?.profile
            : await showDialog<TerminalProfile>(
                context: context,
                builder: (dialogContext) => ProfileEditorDialog(
                  title: 'New profile',
                  initialValue: template,
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
      return true;
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile changes could not be saved: $error')),
        );
      }
      return false;
    }
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
      await sessionController.saveProfile(profile);
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
