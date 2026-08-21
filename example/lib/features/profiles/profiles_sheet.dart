import 'package:flutter/material.dart';

import '../../ui/app_ui.dart';
import 'profile_models.dart';

sealed class ProfilesSheetResult {
  const ProfilesSheetResult();
}

final class OpenProfileResult extends ProfilesSheetResult {
  const OpenProfileResult(this.profile);

  final TerminalProfile profile;
}

final class EditProfileResult extends ProfilesSheetResult {
  const EditProfileResult(this.profile);

  final TerminalProfile profile;
}

final class CreateProfileResult extends ProfilesSheetResult {
  const CreateProfileResult(this.connectionType);

  final NewProfileConnectionType connectionType;
}

enum NewProfileConnectionType { localShell, sshSession }

final class DeleteProfileResult extends ProfilesSheetResult {
  const DeleteProfileResult(this.profile);

  final TerminalProfile profile;
}

class ProfilesSheet extends StatefulWidget {
  const ProfilesSheet({
    super.key,
    required this.profiles,
    required this.effectiveDefaultProfileId,
    this.localShellProfilesEnabled = true,
    this.customSshProfilesEnabled = true,
  });

  final List<TerminalProfile> profiles;
  final String? effectiveDefaultProfileId;
  final bool localShellProfilesEnabled;
  final bool customSshProfilesEnabled;

  @override
  State<ProfilesSheet> createState() => _ProfilesSheetState();
}

class _ProfilesSheetState extends State<ProfilesSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<TerminalProfile> get _filteredProfiles {
    final normalizedQuery = _query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return widget.profiles
          .where(_profileTypeIsAvailable)
          .toList(growable: false);
    }
    return [
      for (final profile in widget.profiles)
        if (_profileTypeIsAvailable(profile) &&
            _profileMatchesQuery(profile, normalizedQuery))
          profile,
    ];
  }

  bool get _canCreateProfile =>
      widget.localShellProfilesEnabled || widget.customSshProfilesEnabled;

  bool _profileTypeIsAvailable(TerminalProfile profile) => profile.isSsh
      ? widget.customSshProfilesEnabled
      : widget.localShellProfilesEnabled;

  String get _sheetDescription {
    if (!widget.localShellProfilesEnabled && !widget.customSshProfilesEnabled) {
      return context.l10n.savedSshProfilesRequireRemote;
    }
    if (!widget.localShellProfilesEnabled) {
      return context.l10n.openSavedSshOrEdit;
    }
    return context.l10n.openSavedProfileOrEdit;
  }

  String get _emptyTitle {
    if (_query.trim().isNotEmpty) {
      return context.l10n.noMatchingProfiles;
    }
    if (!widget.localShellProfilesEnabled && !widget.customSshProfilesEnabled) {
      return context.l10n.noSavedProfiles;
    }
    if (!widget.localShellProfilesEnabled) {
      return context.l10n.noSshProfilesYet;
    }
    return context.l10n.noProfilesYet;
  }

  String get _emptyMessage {
    if (_query.trim().isNotEmpty) {
      return context.l10n.tryDifferentProfileSearch;
    }
    if (!widget.localShellProfilesEnabled && !widget.customSshProfilesEnabled) {
      return context.l10n.connectRemoteToCreateSyncSsh;
    }
    if (!widget.localShellProfilesEnabled) {
      return context.l10n.createSshProfileToConnect;
    }
    return context.l10n.createProfileToCustomize;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final filteredProfiles = _filteredProfiles;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final animationDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    return Semantics(
      label: context.l10n.profiles,
      container: true,
      explicitChildNodes: true,
      child: AnimatedPadding(
        duration: animationDuration,
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + keyboardInset),
        child: Material(
          key: const Key('profiles-sheet'),
          color: palette.overlay,
          borderRadius: BorderRadius.circular(palette.radius.xl),
          elevation: 0,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compactLayout =
                  context.usesTouchControlDensity &&
                  constraints.maxHeight < 260;
              return SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    palette.spacing.xl,
                    compactLayout ? palette.spacing.xs : palette.spacing.lg,
                    palette.spacing.xl,
                    compactLayout ? palette.spacing.xs : palette.spacing.lg,
                  ),
                  child: Column(
                    mainAxisSize: compactLayout
                        ? MainAxisSize.max
                        : MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.l10n.profiles,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: palette.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          Tooltip(
                            message: _canCreateProfile
                                ? context.l10n.createProfile
                                : context.l10n.connectRemoteToCreateSavedSsh,
                            child: FilledButton.icon(
                              key: const Key('profiles-create'),
                              onPressed: _canCreateProfile
                                  ? _createProfile
                                  : null,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: Text(context.l10n.newAction),
                            ),
                          ),
                          const SizedBox(width: 6),
                          AppActionButton(
                            tooltip: context.l10n.closeProfiles,
                            tone: AppActionTone.ghost,
                            size: AppActionSize.dense,
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icons.close_rounded,
                          ),
                        ],
                      ),
                      if (!compactLayout)
                        Text(
                          _sheetDescription,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: palette.textSubtle),
                        ),
                      if (_canCreateProfile || filteredProfiles.isNotEmpty) ...[
                        SizedBox(
                          height: compactLayout
                              ? palette.spacing.sm
                              : palette.spacing.md,
                        ),
                        Semantics(
                          identifier: 'profiles-search-field',
                          label: context.l10n.searchProfilesOrTags,
                          container: true,
                          explicitChildNodes: true,
                          child: TextField(
                            key: const Key('profiles-search-field'),
                            controller: _searchController,
                            autofocus: !context.usesTouchControlDensity,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search_rounded),
                              labelText: context.l10n.searchProfilesOrTags,
                            ),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) =>
                                FocusScope.of(context).unfocus(),
                            onTapOutside: (_) =>
                                FocusScope.of(context).unfocus(),
                            onChanged: (value) {
                              setState(() {
                                _query = value;
                              });
                            },
                          ),
                        ),
                      ],
                      if (!compactLayout) SizedBox(height: palette.spacing.md),
                      Flexible(
                        child: filteredProfiles.isEmpty
                            ? SingleChildScrollView(
                                key: const Key('profiles-empty-scroll'),
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: palette.spacing.lg,
                                  ),
                                  child: AppEmptyState(
                                    title: _emptyTitle,
                                    message: _emptyMessage,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: filteredProfiles.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final profile = filteredProfiles[index];
                                  final isDefault =
                                      profile.id ==
                                      widget.effectiveDefaultProfileId;
                                  final summary = _profileSummary(
                                    profile,
                                    isDefault: isDefault,
                                  );
                                  return ListTile(
                                    key: Key('profile-entry-${profile.id}'),
                                    title: Text(
                                      profile.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: palette.textPrimary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    subtitle: _ProfileEntrySubtitle(
                                      summary: summary,
                                      tags: profile.tags,
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AppActionButton(
                                          tooltip: context.l10n.editNamedItem(
                                            profile.name,
                                          ),
                                          tone: AppActionTone.ghost,
                                          size: AppActionSize.dense,
                                          onPressed: () => Navigator.of(
                                            context,
                                          ).pop(EditProfileResult(profile)),
                                          icon: Icons.edit_outlined,
                                        ),
                                        AppActionButton(
                                          tooltip: context.l10n.deleteNamedItem(
                                            profile.name,
                                          ),
                                          tone: AppActionTone.ghost,
                                          size: AppActionSize.dense,
                                          onPressed: widget.profiles.length <= 1
                                              ? null
                                              : () => Navigator.of(context).pop(
                                                  DeleteProfileResult(profile),
                                                ),
                                          icon: Icons.delete_outline_rounded,
                                        ),
                                      ],
                                    ),
                                    onTap: () => Navigator.of(
                                      context,
                                    ).pop(OpenProfileResult(profile)),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _createProfile() async {
    final connectionType = await showDialog<NewProfileConnectionType>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(dialogContext.l10n.newProfile),
        children: [
          if (widget.localShellProfilesEnabled)
            SimpleDialogOption(
              key: const Key('profiles-create-local'),
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(NewProfileConnectionType.localShell),
              child: ListTile(
                leading: const Icon(Icons.terminal_rounded),
                title: Text(dialogContext.l10n.localShell),
                subtitle: Text(dialogContext.l10n.runShellOnDevice),
              ),
            ),
          if (widget.customSshProfilesEnabled)
            SimpleDialogOption(
              key: const Key('profiles-create-ssh'),
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(NewProfileConnectionType.sshSession),
              child: ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text(dialogContext.l10n.sshSession),
                subtitle: Text(dialogContext.l10n.connectRemoteHost),
              ),
            ),
        ],
      ),
    );
    if (!mounted || connectionType == null) {
      return;
    }
    Navigator.of(context).pop(CreateProfileResult(connectionType));
  }

  String _profileSummary(TerminalProfile profile, {required bool isDefault}) {
    final base = profile.isSsh
        ? 'SSH • ${profile.connection.user}@${profile.connection.host}:${profile.connection.port}'
        : '${profile.shell} • ${terminalEmulationLabel(profile.terminalEmulation)} • ${context.l10n.scrollbackLineCount(profile.scrollbackLines)}';
    return isDefault ? '$base • ${context.l10n.defaultProfile}' : base;
  }

  bool _profileMatchesQuery(TerminalProfile profile, String query) {
    if (profile.name.toLowerCase().contains(query) ||
        profile.shell.toLowerCase().contains(query) ||
        profile.connection.host.toLowerCase().contains(query) ||
        profile.connection.user.toLowerCase().contains(query)) {
      return true;
    }
    return profile.tags.any((tag) => tag.toLowerCase().contains(query));
  }
}

class _ProfileEntrySubtitle extends StatelessWidget {
  const _ProfileEntrySubtitle({required this.summary, required this.tags});

  final String summary;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final summaryStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: palette.textSubtle);
    if (tags.isEmpty) {
      return Text(summary, style: summaryStyle);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(summary, style: summaryStyle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tag in tags)
              DecoratedBox(
                key: Key('profile-tag-$tag'),
                decoration: BoxDecoration(
                  color: palette.panel,
                  border: Border.all(color: palette.border),
                  borderRadius: BorderRadius.circular(palette.radius.sm),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: Text(
                    tag,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
