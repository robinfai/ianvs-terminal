part of 'shell_screen.dart';

extension _ShellScreenStateProfileActions on _ShellScreenState {
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
            osc52Policy: _clipboardConfig.osc52,
            openUrlPolicy: _hostActionsConfig.osc1337OpenUrl,
            requestAttentionPolicy: _hostActionsConfig.osc1337RequestAttention,
            reportVariableDecisions: _hostActionsConfig.osc1337ReportVariables,
            localConfig: sessionController.localConfig,
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
      final updatedProfile = selection.updatedProfile;
      if (updatedProfile != null) {
        await sessionController.saveProfile(updatedProfile);
      }
      await sessionController.setAppSettings(
        keybindings: selection.keybindings,
        workspace: selection.workspace,
        globalCopyOnSelect: selection.globalCopyOnSelect,
        paste: selection.paste,
        shellIntegration: selection.shellIntegration,
        notifications: selection.notifications,
        hotkeyWindow: selection.hotkeyWindow,
      );
      if (!mounted) {
        return;
      }
      final nextConfig = sessionController.localConfig;
      _mutateState(() {
        _notificationConfigSource =
            LocalTerminalConfigBootstrapSource.localConfig;
        _notificationLocalConfig = nextConfig;
        _keybindingsConfig = nextConfig.keybindings;
        _clipboardConfig = nextConfig.clipboard;
        _bracketedPastePolicy = nextConfig.paste.bracketedPaste;
        _pastePolicy = _pastePolicyFromConfig(nextConfig.paste);
        _pasteHistoryPolicy = _pasteHistoryPolicyFromConfig(nextConfig.paste);
        _pasteHistoryEntries = _pasteHistoryEntries
            .take(_effectivePasteHistoryLimit)
            .toList(growable: false);
        _commandFinishedNotificationsEnabled =
            nextConfig.notifications.commandFinished;
        _bellNotificationsEnabled = nextConfig.notifications.bell;
        _activityNotificationsEnabled = nextConfig.notifications.activity;
      });
      await WindowBridge.setHotkeyWindowEnabled(
        nextConfig.hotkeyWindow.enabled,
      );
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
          returningToWorkspace: activeSessionIdBeforeOpen == null,
        );
        return;
      case EditProfileResult(:final profile):
        final edited = await showDialog<TerminalProfile>(
          context: context,
          builder: (dialogContext) =>
              ProfileEditorDialog(initialValue: profile),
        );
        if (edited != null) {
          await sessionController.saveProfile(edited);
        }
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: ref
              .read(sessionControllerProvider)
              .activeSessionId,
        );
        return;
      case CreateProfileResult():
        final edited = await showDialog<TerminalProfile>(
          context: context,
          builder: (dialogContext) => ProfileEditorDialog(
            title: 'New profile',
            initialValue: _newProfileTemplate(sessionState.profiles),
          ),
        );
        if (edited != null) {
          await sessionController.saveProfile(edited);
        }
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: ref
              .read(sessionControllerProvider)
              .activeSessionId,
        );
        return;
      case ImportProfilesResult():
        await _openDynamicProfiles(sessionController);
        _restoreSessionFocus(
          activeSessionIdBeforeOpen: activeSessionIdBeforeOpen,
          activeSessionIdAfterClose: ref
              .read(sessionControllerProvider)
              .activeSessionId,
        );
        return;
      case DuplicateProfileResult(:final profile):
        final edited = await showDialog<TerminalProfile>(
          context: context,
          builder: (dialogContext) => ProfileEditorDialog(
            title: 'Duplicate profile',
            initialValue: _duplicateProfileTemplate(
              profile,
              sessionState.profiles,
            ),
          ),
        );
        if (edited != null) {
          await sessionController.saveProfile(edited);
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
          builder: (dialogContext) => AppDialogScaffold(
            key: const Key('delete-profile-confirmation'),
            title: 'Delete ${profile.name}?',
            subtitle:
                'Existing sessions stay open, but this Profile will no longer be available for new tabs.',
            body: const SizedBox.shrink(),
            footer: Wrap(
              alignment: WrapAlignment.end,
              spacing: dialogContext.appTheme.spacing.sm,
              children: [
                AppActionButton(
                  tone: AppActionTone.secondary,
                  label: 'Cancel',
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                AppActionButton(
                  buttonKey: const Key('delete-profile-confirm'),
                  tone: AppActionTone.danger,
                  icon: Icons.delete_outline,
                  label: 'Delete profile',
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            ),
          ),
        );
        if (confirmed == true) {
          await sessionController.deleteProfile(profile.id);
          if (mounted) {
            _showShellSnackBar('${profile.name} deleted.');
          }
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

  TerminalProfile _newProfileTemplate(List<TerminalProfile> existingProfiles) {
    final existingIds = {for (final profile in existingProfiles) profile.id};
    var suffix = 1;
    var id = 'profile-$suffix';
    while (existingIds.contains(id)) {
      suffix += 1;
      id = 'profile-$suffix';
    }
    return defaultTerminalProfile().copyWith(id: id, name: 'New Profile');
  }

  TerminalProfile _duplicateProfileTemplate(
    TerminalProfile source,
    List<TerminalProfile> existingProfiles,
  ) {
    final existingIds = {for (final profile in existingProfiles) profile.id};
    var suffix = 2;
    var id = '${source.id}-copy';
    while (existingIds.contains(id)) {
      id = '${source.id}-copy-$suffix';
      suffix += 1;
    }
    return source.copyWith(id: id, name: '${source.name} Copy');
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
