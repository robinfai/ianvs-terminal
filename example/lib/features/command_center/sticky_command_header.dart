import 'package:flutter/material.dart';

import 'command_block_models.dart';
import 'command_invocation_models.dart';

enum StickyCommandHeaderDisabledReason {
  shellIntegrationDisabled,
  altBufferActive,
  fullscreenAppActive,
  pagerActive,
  noVisibleBlock,
}

enum StickyCommandHeaderTone { normal, success, warning, danger }

class StickyCommandHeaderViewport {
  const StickyCommandHeaderViewport({
    required this.scope,
    required this.visibleRange,
    this.altBufferActive = false,
    this.fullscreenAppActive = false,
    this.pagerActive = false,
  });

  final CommandBlockScope scope;
  final CommandBlockRowRange visibleRange;
  final bool altBufferActive;
  final bool fullscreenAppActive;
  final bool pagerActive;
}

class StickyCommandHeaderModel {
  const StickyCommandHeaderModel({
    required this.blockId,
    required this.command,
    required this.cwdLabel,
    required this.statusLabel,
    required this.durationLabel,
    required this.semanticLabel,
    required this.tone,
  });

  factory StickyCommandHeaderModel.fromBlock(CommandBlock block) {
    final command = block.command.trim().isEmpty
        ? 'Command'
        : block.command.trim();
    final cwdLabel = _labelOrFallback(block.cwd, 'CWD unavailable');
    final statusLabel = _statusLabel(block);
    final durationLabel = _durationLabel(
      block.finishedAt?.difference(block.startedAt),
    );

    return StickyCommandHeaderModel(
      blockId: block.id,
      command: command,
      cwdLabel: cwdLabel,
      statusLabel: statusLabel,
      durationLabel: durationLabel,
      semanticLabel:
          'Command $command, $statusLabel, cwd $cwdLabel, duration '
          '$durationLabel',
      tone: _toneForStatus(block.status),
    );
  }

  final String blockId;
  final String command;
  final String cwdLabel;
  final String statusLabel;
  final String durationLabel;
  final String semanticLabel;
  final StickyCommandHeaderTone tone;

  bool get writesToScrollback => false;
}

class StickyCommandHeaderResolution {
  const StickyCommandHeaderResolution.visible({
    required this.header,
    required this.visibleRange,
    this.scrollbackRowsInspected = 0,
  }) : disabledReason = null;

  const StickyCommandHeaderResolution.disabled({
    required this.visibleRange,
    required this.disabledReason,
    this.scrollbackRowsInspected = 0,
  }) : header = null;

  final StickyCommandHeaderModel? header;
  final CommandBlockRowRange visibleRange;
  final StickyCommandHeaderDisabledReason? disabledReason;
  final int scrollbackRowsInspected;

  bool get visible => header != null;
  bool get writesToScrollback => false;
}

class StickyCommandHeaderResolver {
  const StickyCommandHeaderResolver();

  StickyCommandHeaderResolution resolve({
    required Iterable<CommandBlock> blocks,
    required StickyCommandHeaderViewport viewport,
    bool shellIntegrationEnabled = true,
  }) {
    if (!shellIntegrationEnabled) {
      return _disabled(
        viewport,
        StickyCommandHeaderDisabledReason.shellIntegrationDisabled,
      );
    }
    if (viewport.altBufferActive) {
      return _disabled(
        viewport,
        StickyCommandHeaderDisabledReason.altBufferActive,
      );
    }
    if (viewport.fullscreenAppActive) {
      return _disabled(
        viewport,
        StickyCommandHeaderDisabledReason.fullscreenAppActive,
      );
    }
    if (viewport.pagerActive) {
      return _disabled(viewport, StickyCommandHeaderDisabledReason.pagerActive);
    }

    final visibleBlock = _visibleBlockFor(blocks, viewport);
    if (visibleBlock == null) {
      return _disabled(
        viewport,
        StickyCommandHeaderDisabledReason.noVisibleBlock,
      );
    }

    return StickyCommandHeaderResolution.visible(
      header: StickyCommandHeaderModel.fromBlock(visibleBlock),
      visibleRange: viewport.visibleRange,
    );
  }

  StickyCommandHeaderResolution _disabled(
    StickyCommandHeaderViewport viewport,
    StickyCommandHeaderDisabledReason reason,
  ) {
    return StickyCommandHeaderResolution.disabled(
      visibleRange: viewport.visibleRange,
      disabledReason: reason,
    );
  }
}

class StickyCommandHeaderOverlay extends StatelessWidget {
  const StickyCommandHeaderOverlay({
    required this.resolution,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 0),
    super.key,
  });

  final StickyCommandHeaderResolution resolution;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final header = resolution.header;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: child),
        if (header != null)
          Positioned(
            top: padding.top,
            left: padding.left,
            right: padding.right,
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child: StickyCommandHeader(header: header),
              ),
            ),
          ),
      ],
    );
  }
}

class StickyCommandHeader extends StatelessWidget {
  const StickyCommandHeader({required this.header, super.key});

  final StickyCommandHeaderModel header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = _colorsForTone(colorScheme, header.tone);

    return Semantics(
      label: header.semanticLabel,
      container: true,
      child: Material(
        key: const Key('sticky-command-header'),
        elevation: 4,
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 420;
                final title = _HeaderTitle(
                  command: header.command,
                  foreground: colors.foreground,
                );
                final meta = _HeaderMeta(
                  header: header,
                  colors: colors,
                  colorScheme: colorScheme,
                );
                if (compact) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 6), meta],
                  );
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 10),
                    Flexible(child: meta),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle({required this.command, required this.foreground});

  final String command;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.terminal_rounded, size: 18, color: foreground),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            command,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: foreground,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderMeta extends StatelessWidget {
  const _HeaderMeta({
    required this.header,
    required this.colors,
    required this.colorScheme,
  });

  final StickyCommandHeaderModel header;
  final _HeaderToneColors colors;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        _HeaderMetaChip(
          icon: _statusIcon(header.tone),
          label: header.statusLabel,
          background: colors.strongBackground,
          foreground: colors.strongForeground,
        ),
        _HeaderMetaChip(
          icon: Icons.folder_open_rounded,
          label: header.cwdLabel,
          background: colorScheme.surfaceContainerHighest,
          foreground: colorScheme.onSurfaceVariant,
        ),
        _HeaderMetaChip(
          icon: Icons.timer_outlined,
          label: header.durationLabel,
          background: colorScheme.surfaceContainerHighest,
          foreground: colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _HeaderMetaChip extends StatelessWidget {
  const _HeaderMetaChip({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

CommandBlock? _visibleBlockFor(
  Iterable<CommandBlock> blocks,
  StickyCommandHeaderViewport viewport,
) {
  CommandBlock? firstIntersecting;
  for (final block in blocks) {
    if (block.scope != viewport.scope) {
      continue;
    }
    final range = _visibleRangeForBlock(block);
    if (range == null) {
      continue;
    }
    if (range.containsRow(viewport.visibleRange.startRow)) {
      return block;
    }
    if (firstIntersecting == null &&
        _intersects(range, viewport.visibleRange)) {
      firstIntersecting = block;
    }
  }
  return firstIntersecting;
}

CommandBlockRowRange? _visibleRangeForBlock(CommandBlock block) {
  int? start;
  int? end;

  void include(CommandBlockRowRange? range) {
    if (range == null || range.isEmpty) {
      return;
    }
    start = start == null ? range.startRow : _min(start!, range.startRow);
    end = end == null
        ? range.endRowExclusive
        : _max(end!, range.endRowExclusive);
  }

  include(block.inputRange);
  include(block.outputRange);

  if (start == null || end == null) {
    return null;
  }
  return CommandBlockRowRange(startRow: start!, endRowExclusive: end!);
}

bool _intersects(CommandBlockRowRange a, CommandBlockRowRange b) {
  return a.startRow < b.endRowExclusive && b.startRow < a.endRowExclusive;
}

int _min(int a, int b) => a < b ? a : b;
int _max(int a, int b) => a > b ? a : b;

String _statusLabel(CommandBlock block) {
  return switch (block.status) {
    CommandInvocationStatus.running => 'Running',
    CommandInvocationStatus.succeeded => 'Succeeded',
    CommandInvocationStatus.failed =>
      block.exitCode == null ? 'Failed' : 'Failed exit ${block.exitCode}',
    CommandInvocationStatus.unknown => 'Status unknown',
  };
}

String _durationLabel(Duration? duration) {
  if (duration == null) {
    return 'Duration unavailable';
  }
  final milliseconds = duration.inMilliseconds;
  if (milliseconds < 1000) {
    return '${milliseconds}ms';
  }
  final seconds = duration.inSeconds;
  if (seconds < 60) {
    return '${seconds}s';
  }
  final minutes = duration.inMinutes;
  final remainingSeconds = seconds.remainder(60);
  if (remainingSeconds == 0) {
    return '${minutes}m';
  }
  return '${minutes}m ${remainingSeconds}s';
}

String _labelOrFallback(String? value, String fallback) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return fallback;
  }
  return trimmed;
}

StickyCommandHeaderTone _toneForStatus(CommandInvocationStatus status) {
  return switch (status) {
    CommandInvocationStatus.running => StickyCommandHeaderTone.warning,
    CommandInvocationStatus.succeeded => StickyCommandHeaderTone.success,
    CommandInvocationStatus.failed => StickyCommandHeaderTone.danger,
    CommandInvocationStatus.unknown => StickyCommandHeaderTone.normal,
  };
}

IconData _statusIcon(StickyCommandHeaderTone tone) {
  return switch (tone) {
    StickyCommandHeaderTone.success => Icons.check_circle_outline,
    StickyCommandHeaderTone.warning => Icons.timelapse,
    StickyCommandHeaderTone.danger => Icons.error_outline,
    StickyCommandHeaderTone.normal => Icons.info_outline,
  };
}

_HeaderToneColors _colorsForTone(
  ColorScheme colorScheme,
  StickyCommandHeaderTone tone,
) {
  return switch (tone) {
    StickyCommandHeaderTone.success => _HeaderToneColors(
      background: colorScheme.surfaceContainerHigh,
      foreground: colorScheme.onSurface,
      strongBackground: colorScheme.tertiaryContainer,
      strongForeground: colorScheme.onTertiaryContainer,
    ),
    StickyCommandHeaderTone.warning => _HeaderToneColors(
      background: colorScheme.surfaceContainerHigh,
      foreground: colorScheme.onSurface,
      strongBackground: colorScheme.secondaryContainer,
      strongForeground: colorScheme.onSecondaryContainer,
    ),
    StickyCommandHeaderTone.danger => _HeaderToneColors(
      background: colorScheme.errorContainer,
      foreground: colorScheme.onErrorContainer,
      strongBackground: colorScheme.error,
      strongForeground: colorScheme.onError,
    ),
    StickyCommandHeaderTone.normal => _HeaderToneColors(
      background: colorScheme.surfaceContainerHigh,
      foreground: colorScheme.onSurface,
      strongBackground: colorScheme.surfaceContainerHighest,
      strongForeground: colorScheme.onSurfaceVariant,
    ),
  };
}

class _HeaderToneColors {
  const _HeaderToneColors({
    required this.background,
    required this.foreground,
    required this.strongBackground,
    required this.strongForeground,
  });

  final Color background;
  final Color foreground;
  final Color strongBackground;
  final Color strongForeground;
}
