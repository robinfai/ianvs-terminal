part of 'shell_screen.dart';

class _SshOnlyShellEmptyState extends StatelessWidget {
  const _SshOnlyShellEmptyState({
    super.key,
    required this.palette,
    required this.profiles,
    required this.onOpenProfile,
    required this.onCreateProfile,
  });

  final AppThemeTokens palette;
  final List<TerminalProfile> profiles;
  final ValueChanged<TerminalProfile> onOpenProfile;
  final VoidCallback? onCreateProfile;

  @override
  Widget build(BuildContext context) {
    final sshProfiles = profiles
        .where((profile) => profile.isSsh)
        .toList(growable: false);
    return DecoratedBox(
      key: const Key('ios-ssh-profile-empty-state'),
      decoration: BoxDecoration(
        color: palette.terminalSurface,
        border: Border(top: BorderSide(color: palette.terminalFrame)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compactHeight = constraints.maxHeight < 320;
              if (compactHeight) {
                return SingleChildScrollView(
                  key: const Key('ios-ssh-empty-state-scroll'),
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(context, sshProfiles, compact: true),
                      const SizedBox(height: 12),
                      _buildCompactProfiles(context, sshProfiles),
                      const SizedBox(height: 12),
                      _buildCreateButton(context),
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(context, sshProfiles),
                    const SizedBox(height: 20),
                    Expanded(
                      child: _buildRegularProfiles(context, sshProfiles),
                    ),
                    const SizedBox(height: 16),
                    _buildCreateButton(context),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    List<TerminalProfile> sshProfiles, {
    bool compact = false,
  }) {
    final title = Text(
      context.l10n.connectWithSsh,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
        color: palette.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (compact)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_outlined, size: 28, color: palette.accent),
              const SizedBox(width: 10),
              Flexible(child: title),
            ],
          )
        else ...[
          Icon(Icons.cloud_outlined, size: 40, color: palette.accent),
          const SizedBox(height: 12),
          title,
        ],
        const SizedBox(height: 8),
        Text(
          sshProfiles.isEmpty
              ? context.l10n.createSshConnectionFirstTab
              : context.l10n.chooseSavedProfileForTab,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: palette.textSubtle),
        ),
        const SizedBox(height: 4),
        Text(
          context.l10n.localSessionsUnavailableOnIphone,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
        ),
      ],
    );
  }

  Widget _buildRegularProfiles(
    BuildContext context,
    List<TerminalProfile> sshProfiles,
  ) {
    if (sshProfiles.isEmpty) {
      return Center(child: _emptyProfilesLabel(context));
    }
    return ListView.separated(
      key: const Key('ios-ssh-profile-list'),
      itemCount: sshProfiles.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _profileTile(sshProfiles[index]),
    );
  }

  Widget _buildCompactProfiles(
    BuildContext context,
    List<TerminalProfile> sshProfiles,
  ) {
    if (sshProfiles.isEmpty) {
      return _emptyProfilesLabel(context);
    }
    return Column(
      key: const Key('ios-ssh-profile-list'),
      children: [
        for (var index = 0; index < sshProfiles.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          _profileTile(sshProfiles[index]),
        ],
      ],
    );
  }

  Widget _emptyProfilesLabel(BuildContext context) {
    return Text(
      context.l10n.noSshProfilesYet,
      key: const Key('ios-ssh-empty-profile-list'),
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
    );
  }

  Widget _profileTile(TerminalProfile profile) {
    final connection = profile.connection;
    return Material(
      color: palette.panel,
      borderRadius: BorderRadius.circular(palette.radius.lg),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: Key('ios-ssh-empty-profile-${profile.id}'),
        minTileHeight: 56,
        leading: Icon(Icons.dns_outlined, color: palette.accent),
        title: Text(profile.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${connection.user}@${connection.host}:${connection.port}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.arrow_forward_rounded),
        onTap: () => onOpenProfile(profile),
      ),
    );
  }

  Widget _buildCreateButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AppActionButton(
        buttonKey: const Key('ios-ssh-create-profile'),
        icon: Icons.add_rounded,
        label: context.l10n.newSshConnection,
        onPressed: onCreateProfile,
      ),
    );
  }
}
