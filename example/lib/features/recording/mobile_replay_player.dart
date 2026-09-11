import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/app_ui.dart';
import '../terminal/terminal.dart' as terminal;
import 'replay_viewport_layout.dart';

/// A content-first touch player shared by saved recordings and recent activity.
/// Search and precise navigation are explicit modes; they never compete with
/// the transport controls for the same small row.
class MobileReplayPlayer extends StatefulWidget {
  const MobileReplayPlayer({
    super.key,
    required this.controller,
    required this.title,
    required this.details,
    required this.viewport,
    required this.recordedViewportSize,
    required this.onClose,
    required this.onSearchChanged,
    this.searchSummary,
    this.onSearchPrevious,
    this.onSearchNext,
    this.onCopyVisible,
    this.onClear,
  });

  final terminal.TerminalReplayController? controller;
  final String title;
  final String details;
  final Widget viewport;
  final Size? recordedViewportSize;
  final VoidCallback onClose;
  final ValueChanged<String> onSearchChanged;
  final String? searchSummary;
  final VoidCallback? onSearchPrevious;
  final VoidCallback? onSearchNext;
  final VoidCallback? onCopyVisible;
  final VoidCallback? onClear;

  @override
  State<MobileReplayPlayer> createState() => _MobileReplayPlayerState();
}

class _MobileReplayPlayerState extends State<MobileReplayPlayer>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _transform = TransformationController();
  bool _searching = false;
  bool _contentOnly = false;
  bool _resumeAfterSeek = false;
  double? _scrubPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _searching) return;
      FocusManager.instance.primaryFocus?.unfocus();
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) widget.controller?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    _searchFocus.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    _search.clear();
    widget.onSearchChanged('');
    setState(() => _searching = false);
  }

  void _seekBy(int seconds) {
    final controller = widget.controller;
    if (controller == null) return;
    final playing = controller.state.isPlaying;
    controller.seekToPresentation(
      controller.state.presentationPosition + Duration(seconds: seconds),
    );
    if (playing && !controller.state.isEnded) controller.play();
  }

  Future<void> _showOptions() async {
    final controller = widget.controller;
    controller?.pause();
    _searchFocus.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .78,
          ),
          child: StatefulBuilder(
            builder: (context, refresh) {
              final l10n = context.l10n;
              final state = controller?.state;
              return ListView(
                key: const Key('mobile-replay-options-sheet'),
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.mobilePlaybackOptions,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.close,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  if (controller != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      l10n.mobilePlaybackSpeed,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final speed in [0.25, 0.5, 1.0, 2.0, 4.0])
                          ChoiceChip(
                            key: Key('mobile-replay-speed-$speed'),
                            label: Text(
                              '${speed == speed.roundToDouble() ? speed.toInt() : speed}×',
                            ),
                            selected: state?.speed == speed,
                            onSelected: (_) =>
                                refresh(() => controller.setSpeed(speed)),
                          ),
                      ],
                    ),
                    SwitchListTile.adaptive(
                      key: const Key('mobile-replay-skip-idle'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.mobileSkipIdle),
                      subtitle: Text(l10n.mobileSkipIdleHelp),
                      value:
                          state?.timeMode ==
                          terminal.TerminalReplayTimeMode.smart,
                      onChanged: (enabled) => refresh(
                        () => controller.setTimeMode(
                          enabled
                              ? terminal.TerminalReplayTimeMode.smart
                              : terminal.TerminalReplayTimeMode.realTime,
                        ),
                      ),
                    ),
                    ExpansionTile(
                      key: const Key('mobile-replay-frame-options'),
                      tilePadding: EdgeInsets.zero,
                      title: Text(l10n.mobileFrameNavigation),
                      children: [
                        ListTile(
                          title: Text(l10n.stepBackInReplay),
                          leading: const Icon(Icons.skip_previous_rounded),
                          enabled: controller.canStepPrevious,
                          onTap: controller.canStepPrevious
                              ? () => refresh(controller.stepPrevious)
                              : null,
                        ),
                        ListTile(
                          title: Text(l10n.stepForwardInReplay),
                          leading: const Icon(Icons.skip_next_rounded),
                          enabled: controller.canStepNext,
                          onTap: controller.canStepNext
                              ? () => refresh(controller.stepNext)
                              : null,
                        ),
                      ],
                    ),
                  ],
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.zoom_out_map_rounded),
                    title: Text(l10n.mobileResetZoom),
                    subtitle: Text(l10n.mobileReplayZoomHint),
                    onTap: () {
                      _transform.value = Matrix4.identity();
                      Navigator.pop(context);
                    },
                  ),
                  if (widget.onCopyVisible != null)
                    ListTile(
                      key: const Key('mobile-replay-copy-visible'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.copy_rounded),
                      title: Text(l10n.copyVisible),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onCopyVisible!();
                      },
                    ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(l10n.mobileReplayDetails),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(widget.details),
                        ),
                      ),
                    ],
                  ),
                  if (widget.onClear != null)
                    ListTile(
                      key: const Key('mobile-replay-clear'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.delete_outline_rounded),
                      iconColor: Theme.of(context).colorScheme.error,
                      textColor: Theme.of(context).colorScheme.error,
                      title: Text(l10n.clearHistory),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onClear!();
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(
    children: [
      IconButton(
        key: const Key('mobile-replay-close'),
        tooltip: context.l10n.closeReplay,
        onPressed: widget.onClose,
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
      ),
      Expanded(
        child: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      IconButton(
        key: const Key('mobile-replay-open-search'),
        tooltip: context.l10n.searchReplay,
        onPressed: () {
          widget.controller?.pause();
          setState(() => _searching = true);
          _searchFocus.requestFocus();
        },
        icon: const Icon(Icons.search_rounded),
      ),
      IconButton(
        key: const Key('mobile-replay-more'),
        tooltip: context.l10n.mobilePlaybackOptions,
        onPressed: _showOptions,
        icon: const Icon(Icons.more_horiz_rounded),
      ),
    ],
  );

  Widget _searchBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('mobile-replay-search'),
                controller: _search,
                focusNode: _searchFocus,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                onChanged: widget.onSearchChanged,
                onSubmitted: (_) => _searchFocus.unfocus(),
                decoration: InputDecoration(
                  hintText: context.l10n.searchReplay,
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
              ),
            ),
            IconButton(
              key: const Key('mobile-replay-close-search'),
              tooltip: context.l10n.close,
              onPressed: _closeSearch,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                widget.searchSummary ?? '',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            IconButton(
              key: const Key('mobile-replay-search-previous'),
              tooltip: context.l10n.previousSearchMatch,
              onPressed: widget.onSearchPrevious,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            IconButton(
              key: const Key('mobile-replay-search-next'),
              tooltip: context.l10n.nextSearchMatch,
              onPressed: widget.onSearchNext,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _transport() {
    final controller = widget.controller;
    final state = controller?.state;
    final duration = state?.presentationDuration ?? Duration.zero;
    final position = state?.presentationPosition ?? Duration.zero;
    final maximum = duration.inMicroseconds.toDouble();
    final enabled = controller != null && maximum > 0;
    final largeText = MediaQuery.textScalerOf(context).scale(13) > 20;
    final timeStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final currentTime = Text(
      _time(
        Duration(
          microseconds: (_scrubPosition ?? position.inMicroseconds).round(),
        ),
      ),
      style: timeStyle,
    );
    final totalTime = Text(_time(duration), style: timeStyle);
    final progress = Slider(
      key: const Key('mobile-replay-progress'),
      value: (_scrubPosition ?? position.inMicroseconds.toDouble()).clamp(
        0,
        maximum,
      ),
      max: maximum > 0 ? maximum : 1,
      semanticFormatterCallback: (v) =>
          _time(Duration(microseconds: v.round())),
      onChangeStart: !enabled
          ? null
          : (_) {
              _resumeAfterSeek = controller.state.isPlaying;
              controller.pause();
            },
      onChanged: !enabled
          ? null
          : (value) => setState(() => _scrubPosition = value),
      onChangeEnd: !enabled
          ? null
          : (value) {
              controller.seekToPresentation(
                Duration(microseconds: value.round()),
              );
              setState(() => _scrubPosition = null);
              if (_resumeAfterSeek && !controller.state.isEnded) {
                controller.play();
              }
            },
    );
    return Material(
      key: const Key('mobile-replay-transport'),
      color: context.appTheme.panel,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (largeText) ...[
              progress,
              Row(children: [currentTime, const Spacer(), totalTime]),
            ] else
              Row(
                children: [
                  currentTime,
                  Expanded(child: progress),
                  totalTime,
                ],
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (MediaQuery.textScalerOf(context).scale(17) > 24)
                  IconButton(
                    key: const Key('mobile-replay-speed'),
                    tooltip:
                        '${context.l10n.mobilePlaybackSpeed} · ${state?.speed ?? 1}×',
                    onPressed: _showOptions,
                    icon: const Icon(Icons.speed_rounded),
                  )
                else
                  TextButton(
                    key: const Key('mobile-replay-speed'),
                    onPressed: _showOptions,
                    child: Text('${state?.speed ?? 1}×'),
                  ),
                IconButton(
                  key: const Key('mobile-replay-back-ten'),
                  tooltip: context.l10n.mobileSkipBack,
                  onPressed: enabled ? () => _seekBy(-10) : null,
                  icon: const Icon(Icons.replay_10_rounded),
                ),
                IconButton.filled(
                  key: const Key('mobile-replay-toggle'),
                  tooltip: state?.isPlaying == true
                      ? context.l10n.pauseReplay
                      : context.l10n.playReplay,
                  onPressed: enabled ? controller.togglePlayback : null,
                  iconSize: 24,
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(48),
                  ),
                  icon: Icon(
                    state?.isPlaying == true
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                IconButton(
                  key: const Key('mobile-replay-forward-ten'),
                  tooltip: context.l10n.mobileSkipForward,
                  onPressed: enabled ? () => _seekBy(10) : null,
                  icon: const Icon(Icons.forward_10_rounded),
                ),
                IconButton(
                  key: const Key('mobile-replay-content-only'),
                  tooltip: context.l10n.mobileHidePlaybackControls,
                  onPressed: () => setState(() => _contentOnly = true),
                  icon: const Icon(Icons.fullscreen_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    Widget contents() => ColoredBox(
      key: const Key('mobile-replay-player'),
      color: context.appTheme.canvas,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: _searching ? MediaQuery.viewInsetsOf(context).bottom : 0,
        ),
        child: Column(
          children: [
            if (!_contentOnly) _header(),
            if (_searching) _searchBar(),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Semantics(
                      label: context.l10n.mobileReplayZoomHint,
                      child: InteractiveViewer(
                        key: const Key('mobile-replay-viewport'),
                        transformationController: _transform,
                        minScale: 1,
                        maxScale: 4,
                        child: IgnorePointer(
                          child: ReplayViewportFit(
                            recordedViewportSize: widget.recordedViewportSize,
                            child: ExcludeFocus(child: widget.viewport),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_contentOnly)
                    Positioned(
                      top: 0,
                      right: 8,
                      child: IconButton.filledTonal(
                        key: const Key('mobile-replay-show-controls'),
                        tooltip: context.l10n.mobileShowPlaybackControls,
                        onPressed: () => setState(() => _contentOnly = false),
                        icon: const Icon(Icons.fullscreen_exit_rounded),
                      ),
                    ),
                ],
              ),
            ),
            if (!_contentOnly && !_searching) _transport(),
          ],
        ),
      ),
    );
    return controller == null
        ? contents()
        : ListenableBuilder(
            listenable: controller,
            builder: (_, _) => contents(),
          );
  }

  static String _time(Duration duration) {
    final seconds = duration.inSeconds;
    final s = (seconds % 60).toString().padLeft(2, '0');
    if (seconds < 3600) return '${seconds ~/ 60}:$s';
    return '${seconds ~/ 3600}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:$s';
  }
}
