import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/app_ui.dart';
import 'sampled_recording_search_models.dart';

/// Presentation and form state only. The preview has no file/native dependency.
class RecordingSearchSurface extends StatefulWidget {
  const RecordingSearchSurface({
    super.key,
    required this.results,
    required this.loading,
    required this.hasCriteria,
    required this.pageNumber,
    required this.scannedFiles,
    required this.totalFiles,
    required this.skippedFiles,
    required this.onQuery,
    required this.onSelect,
    required this.onClose,
    required this.onRetry,
    this.onNext,
    this.onPrevious,
    this.onFirst,
    this.error,
    this.warning,
  });
  final List<RecordingSearchResult> results;
  final bool loading;
  final bool hasCriteria;
  final int pageNumber;
  final int scannedFiles;
  final int totalFiles;
  final int skippedFiles;
  final String? error;
  final String? warning;
  final ValueChanged<RecordingSearchQuery> onQuery;
  final ValueChanged<RecordingSearchResult> onSelect;
  final VoidCallback onClose;
  final VoidCallback onRetry;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onFirst;

  @override
  State<RecordingSearchSurface> createState() => _RecordingSearchSurfaceState();
}

class _RecordingSearchSurfaceState extends State<RecordingSearchSurface> {
  final _text = TextEditingController();
  final _host = TextEditingController();
  RecordingSearchScope _scope = RecordingSearchScope.all;
  DateTimeRange? _dates;

  @override
  void dispose() {
    _text.dispose();
    _host.dispose();
    super.dispose();
  }

  void _send() {
    final end = _dates?.end;
    widget.onQuery(
      RecordingSearchQuery(
        text: _text.text,
        hostname: _host.text,
        scope: _scope,
        fromUtc: _dates?.start.toUtc(),
        untilUtc: end == null
            ? null
            : DateTime(end.year, end.month, end.day + 1).toUtc(),
      ),
    );
  }

  Future<void> _pickDates() async {
    final dates = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: _dates,
      helpText: context.l10n.recordingSearchDates,
    );
    if (!mounted || dates == null) return;
    setState(() => _dates = dates);
    _send();
  }

  String _scopeLabel(RecordingSearchScope scope) => switch (scope) {
    RecordingSearchScope.all => context.l10n.recordingSearchAll,
    RecordingSearchScope.command => context.l10n.recordingSearchCommands,
    RecordingSearchScope.screen => context.l10n.recordingSearchScreens,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.appTheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Material(
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
                      l10n.recordingSearchTitle,
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
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: tokens.spacing.md,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.recordingSearchCoverage,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          SizedBox(height: tokens.spacing.md),
                          TextField(
                            controller: _text,
                            autofocus: true,
                            maxLength: 256,
                            decoration: InputDecoration(
                              labelText: l10n.recordingSearchQuery,
                              prefixIcon: const Icon(Icons.search),
                              counterText: '',
                            ),
                            textInputAction: TextInputAction.search,
                            onChanged: (_) => _send(),
                            onSubmitted: (_) => _send(),
                          ),
                          SizedBox(height: tokens.spacing.sm),
                          TextField(
                            controller: _host,
                            maxLength: 256,
                            decoration: InputDecoration(
                              labelText: l10n.recordingSearchHost,
                              prefixIcon: const Icon(Icons.dns_outlined),
                              counterText: '',
                            ),
                            onChanged: (_) {
                              setState(() {});
                              _send();
                            },
                          ),
                          SizedBox(height: tokens.spacing.sm),
                          LayoutBuilder(
                            builder: (context, constraints) => Wrap(
                              spacing: tokens.spacing.sm,
                              runSpacing: tokens.spacing.xs,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                  width: constraints.maxWidth
                                      .clamp(0, 320)
                                      .toDouble(),
                                  child: DropdownButton<RecordingSearchScope>(
                                    value: _scope,
                                    isDense: false,
                                    isExpanded: true,
                                    itemHeight: null,
                                    items: [
                                      for (final scope
                                          in RecordingSearchScope.values)
                                        DropdownMenuItem(
                                          value: scope,
                                          child: Text(_scopeLabel(scope)),
                                        ),
                                    ],
                                    onChanged: (scope) {
                                      if (scope == null) return;
                                      setState(() => _scope = scope);
                                      _send();
                                    },
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _pickDates,
                                  icon: const Icon(Icons.date_range),
                                  label: Text(l10n.recordingSearchDates),
                                ),
                                if (_dates != null ||
                                    _host.text.isNotEmpty ||
                                    _scope != RecordingSearchScope.all)
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _dates = null;
                                        _scope = RecordingSearchScope.all;
                                        _host.clear();
                                      });
                                      _send();
                                    },
                                    child: Text(
                                      l10n.recordingSearchClearFilters,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (_dates != null)
                            Padding(
                              padding: EdgeInsets.only(top: tokens.spacing.xs),
                              child: Text(
                                '${MaterialLocalizations.of(context).formatMediumDate(_dates!.start)} – ${MaterialLocalizations.of(context).formatMediumDate(_dates!.end)}',
                              ),
                            ),
                          SizedBox(height: tokens.spacing.sm),
                          if (widget.loading)
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                l10n.recordingSearchProgress(
                                  widget.scannedFiles,
                                  widget.totalFiles,
                                ),
                              ),
                            ),
                          if (widget.error != null) ...[
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                widget.error!,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: tokens.danger),
                              ),
                            ),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: TextButton(
                                onPressed: widget.onRetry,
                                child: Text(l10n.retry),
                              ),
                            ),
                          ],
                          if (widget.skippedFiles > 0)
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                l10n.recordingSearchSkipped(
                                  widget.skippedFiles,
                                ),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              children: [
                                if (widget.warning != null)
                                  Text(
                                    widget.warning!,
                                    maxLines: 5,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          if (!widget.loading &&
                              widget.results.isEmpty &&
                              widget.error == null)
                            Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: tokens.spacing.lg,
                              ),
                              child: Text(
                                widget.hasCriteria
                                    ? l10n.recordingSearchEmpty
                                    : l10n.recordingSearchHint,
                              ),
                            ),
                          const Divider(),
                        ],
                      ),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: widget.results.length,
                    itemBuilder: (context, index) {
                      final hit = widget.results[index];
                      final seconds = hit.offset.inSeconds;
                      final time =
                          '${seconds ~/ 3600}:${((seconds ~/ 60) % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
                      final date = MaterialLocalizations.of(
                        context,
                      ).formatMediumDate(hit.createdAtUtc.toLocal());
                      return ListTile(
                        enabled: !widget.loading,
                        leading: Icon(
                          hit.scope == RecordingSearchScope.command
                              ? Icons.terminal
                              : Icons.text_snippet_outlined,
                        ),
                        title: Text(
                          hit.preview,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${hit.title}\n${hit.hostname ?? l10n.recordingSearchUnknownHost} · $date · $time',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => widget.onSelect(hit),
                      );
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(tokens.spacing.xs),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: l10n.recordingSearchFirstPage,
                    onPressed: widget.loading ? null : widget.onFirst,
                    icon: const Icon(Icons.first_page),
                  ),
                  IconButton(
                    tooltip: l10n.recordingSearchPreviousPage,
                    onPressed: widget.loading ? null : widget.onPrevious,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(l10n.recordingSearchPage(widget.pageNumber)),
                  IconButton(
                    tooltip: l10n.recordingSearchNextPage,
                    onPressed: widget.loading ? null : widget.onNext,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
