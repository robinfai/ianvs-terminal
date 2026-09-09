import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/sessions/session_controller.dart';
import '../../platform/app_shutdown_coordinator.dart';
import 'local_first_sync.dart';

/// Owns scheduling inside the active application graph, including foreground
/// retries. Graph shutdown separately waits for any in-flight operation.
class LocalFirstSyncBoundary extends ConsumerStatefulWidget {
  const LocalFirstSyncBoundary({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<LocalFirstSyncBoundary> createState() =>
      _LocalFirstSyncBoundaryState();
}

class _LocalFirstSyncBoundaryState extends ConsumerState<LocalFirstSyncBoundary>
    with WidgetsBindingObserver {
  LocalFirstSyncCoordinator? _sync;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sync = ref.read(localFirstSyncProvider);
      if (_sync case final sync?) {
        ref
            .read(appShutdownCoordinatorProvider)
            .registerTask('local-first-sync', sync.close);
      }
      _sync?.addListener(_onSyncChanged);
      _sync?.start();
    });
  }

  void _onSyncChanged() {
    final sync = _sync;
    if (!mounted || sync == null || sync.pulledGeneration == _generation) {
      return;
    }
    _generation = sync.pulledGeneration;
    unawaited(
      ref.read(sessionControllerProvider.notifier).refreshSyncedConfiguration(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_sync?.synchronize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sync?.removeListener(_onSyncChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
