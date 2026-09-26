part of 'shell_screen.dart';

class _RecordingLibraryLayout extends StatelessWidget {
  const _RecordingLibraryLayout({
    required this.palette,
    required this.shelfOpen,
    required this.layout,
    required this.shelf,
    required this.onClose,
  });

  final AppThemeTokens palette;
  final bool shelfOpen;
  final Widget layout;
  final Widget shelf;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (context.usesMobileNavigation) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: shelfOpen,
              child: ExcludeFocus(excluding: shelfOpen, child: layout),
            ),
            if (shelfOpen) Positioned.fill(child: shelf),
          ],
        );
      }
      final compact = constraints.maxWidth < 960;
      return Stack(
        children: [
          Positioned.fill(
            right: shelfOpen && !compact ? 372 : 0,
            child: ExcludeFocus(excluding: shelfOpen, child: layout),
          ),
          if (shelfOpen && compact)
            Positioned.fill(
              child: ModalBarrier(
                color: palette.inactiveScrim.withValues(alpha: 0.58),
                onDismiss: onClose,
                semanticsLabel: MaterialLocalizations.of(
                  context,
                ).modalBarrierDismissLabel,
              ),
            ),
          if (shelfOpen)
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: compact ? math.min(400, constraints.maxWidth) : 372,
              child: BlockSemantics(
                blocking: compact,
                child: KeyedSubtree(
                  key: compact
                      ? const Key('saved-recordings-shelf-compact')
                      : null,
                  child: shelf,
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// A small entry point into existing replay capabilities. Recordings stay in
/// the local library; opening this surface does not start recording a session.
class _SavedRecordingsShelf extends StatelessWidget {
  const _SavedRecordingsShelf({
    required this.palette,
    required this.entries,
    required this.mutationPaths,
    required this.selectedPath,
    required this.loading,
    required this.selectionLoading,
    required this.error,
    required this.onRefresh,
    required this.onOpenFile,
    required this.onSearch,
    required this.onRetention,
    required this.onKeep,
    required this.onDelete,
    required this.onRecent,
    required this.onToggleRecording,
    required this.recording,
    required this.pendingSave,
    required this.onSelect,
    required this.onClose,
  });

  final AppThemeTokens palette;
  final List<SampledRecordingEntry> entries;
  final Set<String> mutationPaths;
  final String? selectedPath;
  final bool loading;
  final bool selectionLoading;
  final String? error;
  final VoidCallback onRefresh;
  final VoidCallback onOpenFile;
  final VoidCallback onSearch;
  final VoidCallback onRetention;
  final ValueChanged<SampledRecordingEntry> onKeep;
  final ValueChanged<SampledRecordingEntry> onDelete;
  final VoidCallback? onRecent;
  final VoidCallback? onToggleRecording;
  final bool recording;
  final bool pendingSave;
  final ValueChanged<SampledRecordingEntry> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
    },
    child: Actions(
      actions: {
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            onClose();
            return null;
          },
        ),
      },
      child: FocusScope(
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: context.l10n.replayHubTitle,
          child: Material(
            key: const Key('saved-recordings-shelf'),
            color: palette.chrome,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: palette.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context),
                  Expanded(child: _contents(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _header(BuildContext context) {
    final mobile = context.usesMobileNavigation;
    final close = MergeSemantics(
      child: Semantics(
        label: mobile ? context.l10n.mobileBack : context.l10n.close,
        child: IconButton(
          key: const Key('recording-library-close'),
          autofocus: !mobile,
          tooltip: mobile ? context.l10n.mobileBack : context.l10n.close,
          onPressed: onClose,
          icon: Icon(
            mobile ? Icons.arrow_back_ios_new_rounded : Icons.close_rounded,
          ),
        ),
      ),
    );
    if (mobile) {
      return AppMobileHeader(
        title: context.l10n.replayHubTitle,
        leading: close,
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: palette.spacing.sm,
        vertical: palette.spacing.sm,
      ),
      child: Row(
        children: [
          if (mobile) close,
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: palette.spacing.sm),
              child: Text(
                context.l10n.replayHubTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          if (!mobile) close,
        ],
      ),
    );
  }

  Widget _contents(BuildContext context) {
    final ordered = [...entries]
      ..sort((a, b) {
        final date = b.createdAtUtc.compareTo(a.createdAtUtc);
        return date == 0 ? a.path.compareTo(b.path) : date;
      });
    return CustomScrollView(
      key: const Key('recording-library-scroll'),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: palette.spacing.lg),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!context.usesMobileNavigation || onRecent != null)
                  _recent(context),
                SizedBox(height: palette.spacing.lg),
                const Divider(),
                SizedBox(height: palette.spacing.sm),
                _savedControls(context),
                SizedBox(height: palette.spacing.md),
                _status(context, empty: ordered.isEmpty),
              ],
            ),
          ),
        ),
        SliverList.builder(
          itemCount: ordered.length,
          itemBuilder: (context, index) => _entry(context, ordered[index]),
        ),
        SliverToBoxAdapter(child: SizedBox(height: palette.spacing.lg)),
      ],
    );
  }

  Widget _recent(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.replayRecentTitle, style: textTheme.titleSmall),
        SizedBox(height: palette.spacing.xs),
        if (!context.usesMobileNavigation)
          Text(l10n.replayRecentExplanation, style: textTheme.bodySmall),
        SizedBox(height: palette.spacing.sm),
        OutlinedButton.icon(
          key: const Key('shell-replay-recent-activity'),
          onPressed: selectionLoading ? null : onRecent,
          icon: const Icon(Icons.history_rounded),
          label: Text(l10n.replayRecentActivity),
        ),
        if (onRecent == null)
          Text(l10n.replayRecentNeedsSession, style: textTheme.bodySmall),
      ],
    );
  }

  Widget _savedControls(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.savedRecordings,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            MergeSemantics(
              child: Semantics(
                label: l10n.refreshRecordings,
                child: IconButton(
                  key: const Key('recording-library-refresh'),
                  tooltip: l10n.refreshRecordings,
                  onPressed: loading || selectionLoading ? null : onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
            ),
          ],
        ),
        if (!context.usesMobileNavigation)
          Text(
            l10n.replaySavedExplanation,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        SizedBox(height: palette.spacing.sm),
        if (!context.usesMobileNavigation && onRecent != null)
          _recordingButton(context),
        OutlinedButton.icon(
          key: const Key('recording-library-search'),
          onPressed: selectionLoading ? null : onSearch,
          icon: const Icon(Icons.search),
          label: Text(l10n.recordingSearchTitle),
        ),
        OutlinedButton.icon(
          key: const Key('recording-library-retention'),
          onPressed: selectionLoading ? null : onRetention,
          icon: const Icon(Icons.auto_delete_outlined),
          label: Text(l10n.recordingRetentionTitle),
        ),
        OutlinedButton.icon(
          key: const Key('recording-library-open-file'),
          onPressed: selectionLoading ? null : onOpenFile,
          icon: const Icon(Icons.folder_open_rounded),
          label: Text(l10n.replayOpenFile),
        ),
      ],
    );
  }

  Widget _recordingButton(BuildContext context) => FilledButton.tonalIcon(
    key: const Key('recording-library-toggle-recording'),
    onPressed: selectionLoading ? null : onToggleRecording,
    icon: Icon(
      recording
          ? Icons.stop_circle_outlined
          : pendingSave
          ? Icons.save_outlined
          : Icons.fiber_manual_record_outlined,
    ),
    label: Text(
      recording
          ? context.l10n.stopAndSaveRecording
          : pendingSave
          ? context.l10n.retrySavingRecording
          : context.l10n.startRecordingForReplay,
    ),
  );

  Widget _status(BuildContext context, {required bool empty}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (loading || selectionLoading) const LinearProgressIndicator(),
      if (error != null)
        Padding(
          padding: EdgeInsets.symmetric(vertical: palette.spacing.sm),
          child: Semantics(
            liveRegion: true,
            child: Text(
              error!,
              key: const Key('recording-library-error'),
              style: TextStyle(color: palette.danger),
            ),
          ),
        ),
      if (!loading && error == null && empty)
        Padding(
          padding: EdgeInsets.symmetric(vertical: palette.spacing.lg),
          child: Text(
            context.usesMobileNavigation
                ? context.l10n.mobileSavedEmpty
                : context.l10n.replayLibraryEmpty,
            key: const Key('recording-library-empty'),
          ),
        ),
    ],
  );

  Widget _entry(BuildContext context, SampledRecordingEntry entry) {
    final date = entry.createdAtUtc.toLocal();
    final material = MaterialLocalizations.of(context);
    final details = entry.isReadable
        ? '${material.formatCompactDate(date)} · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(date))} · ${_formatRecordingDuration(entry.duration)}'
        : context.l10n.replayRecordingUnavailable;
    final enabled =
        entry.isReadable &&
        !selectionLoading &&
        !mutationPaths.contains(entry.path);
    return ListTile(
      key: ValueKey('recording-entry-${entry.path}'),
      selected: selectedPath == entry.path,
      enabled: enabled,
      leading: Icon(
        entry.keep
            ? Icons.bookmark_rounded
            : entry.isReadable
            ? Icons.play_circle_outline_rounded
            : Icons.error_outline_rounded,
      ),
      title: Text(
        entry.displayName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        entry.keep ? '$details · ${context.l10n.recordingKept}' : details,
      ),
      trailing: PopupMenuButton<String>(
        key: ValueKey('recording-actions-${entry.path}'),
        enabled: enabled,
        tooltip: context.l10n.recordingActions,
        onSelected: (action) =>
            action == 'keep' ? onKeep(entry) : onDelete(entry),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'keep',
            child: Text(
              entry.keep
                  ? context.l10n.recordingUnkeep
                  : context.l10n.recordingKeep,
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            enabled: selectedPath != entry.path,
            child: Text(
              selectedPath == entry.path
                  ? context.l10n.recordingDeleteInUse
                  : context.l10n.delete,
            ),
          ),
        ],
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: palette.spacing.lg,
        vertical: palette.spacing.xs,
      ),
      onTap: enabled ? () => onSelect(entry) : null,
    );
  }
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _formatRecordingDuration(Duration value) {
  final totalSeconds = math.max(0, value.inSeconds);
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${_twoDigits(minutes)}:${_twoDigits(seconds)}';
  }
  return '${_twoDigits(minutes)}:${_twoDigits(seconds)}';
}
