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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.cloud_outlined, size: 40, color: palette.accent),
                const SizedBox(height: 12),
                Text(
                  'Connect with SSH',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  sshProfiles.isEmpty
                      ? 'Create an SSH connection to open your first tab.'
                      : 'Choose a saved profile to open a terminal tab.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: palette.textSubtle),
                ),
                const SizedBox(height: 4),
                Text(
                  'Local terminal sessions are unavailable on iPhone.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: palette.textMuted),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: sshProfiles.isEmpty
                      ? Center(
                          child: Text(
                            'No SSH profiles yet',
                            key: const Key('ios-ssh-empty-profile-list'),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: palette.textMuted),
                          ),
                        )
                      : ListView.separated(
                          key: const Key('ios-ssh-profile-list'),
                          itemCount: sshProfiles.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final profile = sshProfiles[index];
                            final connection = profile.connection;
                            return Material(
                              color: palette.panel,
                              borderRadius: BorderRadius.circular(
                                palette.radius.lg,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                key: Key('ios-ssh-empty-profile-${profile.id}'),
                                minTileHeight: 56,
                                leading: Icon(
                                  Icons.dns_outlined,
                                  color: palette.accent,
                                ),
                                title: Text(
                                  profile.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${connection.user}@${connection.host}:${connection.port}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(
                                  Icons.arrow_forward_rounded,
                                ),
                                onTap: () => onOpenProfile(profile),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: AppActionButton(
                    buttonKey: const Key('ios-ssh-create-profile'),
                    icon: Icons.add_rounded,
                    label: 'New SSH Connection',
                    onPressed: onCreateProfile,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
