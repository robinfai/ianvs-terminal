import 'package:flutter/material.dart';

import '../../ui/app_ui.dart';

class SampledReplayCommand {
  const SampledReplayCommand({
    required this.label,
    required this.detail,
    required this.offset,
  });
  final String label;
  final String detail;
  final Duration offset;
}

/// Native-free presentation surface, also used by widget previews.
class SampledReplaySurface extends StatefulWidget {
  const SampledReplaySurface({
    super.key,
    required this.title,
    required this.viewport,
    required this.position,
    required this.duration,
    required this.playing,
    required this.loading,
    required this.speed,
    required this.commands,
    required this.timelineLoading,
    required this.onToggle,
    required this.onSeek,
    required this.onSpeed,
    required this.onCopy,
    required this.onClose,
    required this.onFirstPage,
    this.interrupted = false,
    this.error,
    this.timelineError,
    this.onPreviousPage,
    this.onNextPage,
  });
  final String title;
  final Widget viewport;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool loading;
  final bool interrupted;
  final double speed;
  final List<SampledReplayCommand> commands;
  final bool timelineLoading;
  final String? error;
  final String? timelineError;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onSpeed;
  final VoidCallback onCopy;
  final VoidCallback onClose;
  final VoidCallback onFirstPage;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;

  @override
  State<SampledReplaySurface> createState() => _SampledReplaySurfaceState();
}

class _SampledReplaySurfaceState extends State<SampledReplaySurface> {
  bool _commandsVisible = false;
  double? _scrub;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.appTheme;
    final maxMicros = widget.duration.inMicroseconds
        .clamp(1, 1 << 62)
        .toDouble();
    return Material(
      key: const Key('recording-replay-layout'),
      color: tokens.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.all(tokens.spacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: l10n.close,
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (widget.loading) const LinearProgressIndicator(minHeight: 2),
          if (widget.error != null)
            Padding(
              padding: EdgeInsets.all(tokens.spacing.sm),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  widget.error!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tokens.danger),
                ),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 860;
                if (!wide && _commandsVisible) return _timeline(context);
                return Row(
                  children: [
                    Expanded(child: widget.viewport),
                    if (wide && _commandsVisible)
                      SizedBox(width: 340, child: _timeline(context)),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing.sm),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: tokens.spacing.xs,
              children: [
                IconButton(
                  tooltip: widget.playing ? l10n.pauseReplay : l10n.playReplay,
                  onPressed: widget.onToggle,
                  icon: Icon(widget.playing ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(
                  tooltip: l10n.stepBackInReplay,
                  onPressed: () => widget.onSeek(
                    widget.position - const Duration(seconds: 10),
                  ),
                  icon: const Icon(Icons.replay_10),
                ),
                IconButton(
                  tooltip: l10n.stepForwardInReplay,
                  onPressed: () => widget.onSeek(
                    widget.position + const Duration(seconds: 10),
                  ),
                  icon: const Icon(Icons.forward_10),
                ),
                PopupMenuButton<double>(
                  tooltip: l10n.playbackSpeed,
                  initialValue: widget.speed,
                  onSelected: widget.onSpeed,
                  itemBuilder: (_) => [
                    for (final speed in <double>[0.5, 1, 2, 4])
                      PopupMenuItem(value: speed, child: Text('$speed×')),
                  ],
                  child: Padding(
                    padding: EdgeInsets.all(tokens.spacing.sm),
                    child: Text('${widget.speed}×'),
                  ),
                ),
                IconButton(
                  tooltip: l10n.copyVisible,
                  onPressed: widget.onCopy,
                  icon: const Icon(Icons.copy),
                ),
                IconButton(
                  tooltip: l10n.commands,
                  isSelected: _commandsVisible,
                  onPressed: () =>
                      setState(() => _commandsVisible = !_commandsVisible),
                  icon: const Icon(Icons.list_alt),
                ),
                Text(
                  '${formatRecordingPosition(widget.position)} / ${formatRecordingPosition(widget.duration)}',
                ),
              ],
            ),
          ),
          Slider(
            key: const Key('sampled-recording-timeline'),
            value: (_scrub ?? widget.position.inMicroseconds.toDouble()).clamp(
              0,
              maxMicros,
            ),
            max: maxMicros,
            semanticFormatterCallback: (value) =>
                formatRecordingPosition(Duration(microseconds: value.round())),
            onChanged: (value) => setState(() => _scrub = value),
            onChangeEnd: (value) {
              setState(() => _scrub = null);
              widget.onSeek(Duration(microseconds: value.round()));
            },
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.spacing.sm,
              0,
              tokens.spacing.sm,
              tokens.spacing.sm,
            ),
            child: Text(
              '${widget.interrupted ? '${l10n.sampledRecordingInterrupted} · ' : ''}${l10n.sampledRecordingDisclosure}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeline(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(l10n.commands, style: Theme.of(context).textTheme.titleSmall),
            IconButton(
              tooltip: l10n.sampledTimelineFirst,
              onPressed: widget.timelineLoading ? null : widget.onFirstPage,
              icon: const Icon(Icons.first_page),
            ),
            IconButton(
              tooltip: l10n.sampledTimelinePrevious,
              onPressed: widget.timelineLoading ? null : widget.onPreviousPage,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: l10n.sampledTimelineNext,
              onPressed: widget.timelineLoading ? null : widget.onNextPage,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        if (widget.timelineLoading) const LinearProgressIndicator(),
        if (widget.timelineError != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(widget.timelineError!, maxLines: 3),
          ),
        Expanded(
          child: widget.commands.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l10n.sampledTimelineEmpty),
                  ),
                )
              : ListView.builder(
                  itemCount: widget.commands.length,
                  itemBuilder: (context, index) {
                    final command = widget.commands[index];
                    return ListTile(
                      key: ValueKey(('sampled-command', index, command.offset)),
                      title: Text(
                        command.label,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${formatRecordingPosition(command.offset)} · ${command.detail}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        widget.onSeek(command.offset);
                        if (MediaQuery.sizeOf(context).width < 860) {
                          setState(() => _commandsVisible = false);
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

String formatRecordingPosition(Duration value) {
  final seconds = value.inSeconds;
  return '${seconds ~/ 3600}:${((seconds ~/ 60) % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}
