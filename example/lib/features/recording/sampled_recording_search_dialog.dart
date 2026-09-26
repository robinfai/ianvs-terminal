import 'package:flutter/material.dart';

import '../../ui/app_ui.dart';
import 'sampled_recording_library.dart';
import 'sampled_recording_search_controller.dart';
import 'sampled_recording_search_models.dart';
import 'sampled_recording_search_surface.dart';

Future<RecordingSearchResult?> showRecordingSearch({
  required BuildContext context,
  required SampledRecordingLibrary library,
}) => showDialog<RecordingSearchResult>(
  context: context,
  builder: (_) => _SearchDialog(library: library),
);

class _SearchDialog extends StatefulWidget {
  const _SearchDialog({required this.library});
  final SampledRecordingLibrary library;
  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  late final RecordingSearchController _search;
  @override
  void initState() {
    super.initState();
    _search = RecordingSearchController(widget.library);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    clipBehavior: Clip.antiAlias,
    insetPadding: EdgeInsets.all(context.appTheme.spacing.md),
    child: SizedBox(
      width: 900,
      height: 760,
      child: ListenableBuilder(
        listenable: _search,
        builder: (context, _) => RecordingSearchSurface(
          results: _search.results,
          loading: _search.loading,
          hasCriteria: _search.query.hasCriteria,
          pageNumber: _search.pageNumber,
          scannedFiles: _search.scannedFiles,
          totalFiles: _search.totalFiles,
          skippedFiles: _search.skippedFiles,
          error: _search.error,
          warning: _search.warning,
          onQuery: _search.setQuery,
          onSelect: (hit) => Navigator.of(context).pop(hit),
          onClose: () => Navigator.of(context).pop(),
          onRetry: () => _search.setQuery(_search.query),
          onNext: _search.hasNext ? _search.nextPage : null,
          onPrevious: _search.hasPrevious ? _search.previousPage : null,
          onFirst: _search.canRestart ? _search.firstPage : null,
        ),
      ),
    ),
  );
}
