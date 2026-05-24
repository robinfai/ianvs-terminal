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
  const CreateProfileResult();
}

class ProfilesSheet extends StatefulWidget {
  const ProfilesSheet({
    super.key,
    required this.profiles,
    required this.effectiveDefaultProfileId,
  });

  final List<TerminalProfile> profiles;
  final String? effectiveDefaultProfileId;

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
      return widget.profiles;
    }
    return [
      for (final profile in widget.profiles)
        if (_profileMatchesQuery(profile, normalizedQuery)) profile,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appTheme;
    final filteredProfiles = _filteredProfiles;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        key: const Key('profiles-sheet'),
        color: palette.overlay,
        borderRadius: BorderRadius.circular(palette.radius.xl),
        elevation: 0,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              palette.spacing.xl,
              palette.spacing.lg,
              palette.spacing.xl,
              palette.spacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Profiles',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      key: const Key('profiles-create'),
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(const CreateProfileResult()),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('New'),
                    ),
                    const SizedBox(width: 6),
                    AppActionButton(
                      tooltip: 'Close profiles',
                      tone: AppActionTone.ghost,
                      size: AppActionSize.dense,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icons.close_rounded,
                    ),
                  ],
                ),
                Text(
                  'Open a tab with any saved profile or edit its terminal settings.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.textSubtle),
                ),
                SizedBox(height: palette.spacing.md),
                TextField(
                  key: const Key('profiles-search-field'),
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    labelText: 'Search profiles or tags',
                  ),
                  onChanged: (value) {
                    setState(() {
                      _query = value;
                    });
                  },
                ),
                SizedBox(height: palette.spacing.md),
                Flexible(
                  child: filteredProfiles.isEmpty
                      ? Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: palette.spacing.xl,
                          ),
                          child: AppEmptyState(
                            title: 'No matching profiles',
                            message:
                                'Try a different profile name, shell, or tag.',
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: filteredProfiles.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final profile = filteredProfiles[index];
                            final isDefault =
                                profile.id == widget.effectiveDefaultProfileId;
                            final summary = _profileSummary(
                              profile,
                              isDefault: isDefault,
                            );
                            return ListTile(
                              key: Key('profile-entry-${profile.id}'),
                              title: Text(
                                profile.name,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: palette.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              subtitle: _ProfileEntrySubtitle(
                                summary: summary,
                                tags: profile.tags,
                              ),
                              trailing: AppActionButton(
                                tooltip: 'Edit ${profile.name}',
                                tone: AppActionTone.ghost,
                                size: AppActionSize.dense,
                                onPressed: () => Navigator.of(
                                  context,
                                ).pop(EditProfileResult(profile)),
                                icon: Icons.edit_outlined,
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
        ),
      ),
    );
  }

  String _profileSummary(TerminalProfile profile, {required bool isDefault}) {
    final base =
        '${profile.shell} • ${terminalEmulationLabel(profile.terminalEmulation)} • ${profile.scrollbackLines} lines';
    return isDefault ? '$base • Default profile' : base;
  }

  bool _profileMatchesQuery(TerminalProfile profile, String query) {
    if (profile.name.toLowerCase().contains(query) ||
        profile.shell.toLowerCase().contains(query)) {
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
