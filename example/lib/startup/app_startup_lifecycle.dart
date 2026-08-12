import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_startup_coordinator.dart';

/// Stable process-lifecycle boundary that exists for loading, failure, and
/// ready states alike.
///
/// Runtime ProviderScope generations are descendants, so replacing one can
/// never clear or replace the native shutdown handler owned here.
final class AppStartupLifecycleBoundary extends StatefulWidget {
  const AppStartupLifecycleBoundary({
    required this.coordinator,
    required this.child,
    this.shutdownChannel = const MethodChannel('app/shutdown'),
    this.closeOnDispose = true,
    super.key,
  });

  final AppStartupCoordinator coordinator;
  final Widget child;
  final MethodChannel shutdownChannel;
  final bool closeOnDispose;

  @override
  State<AppStartupLifecycleBoundary> createState() =>
      _AppStartupLifecycleBoundaryState();
}

final class _AppStartupLifecycleBoundaryState
    extends State<AppStartupLifecycleBoundary> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    widget.shutdownChannel.setMethodCallHandler(_handleShutdownMethodCall);
    _listener = AppLifecycleListener(
      onDetach: () => unawaited(widget.coordinator.close()),
      onExitRequested: () async {
        final result = await widget.coordinator.close();
        return result.safeToTerminate
            ? AppExitResponse.exit
            : AppExitResponse.cancel;
      },
    );
  }

  @override
  void didUpdateWidget(AppStartupLifecycleBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shutdownChannel != widget.shutdownChannel ||
        oldWidget.coordinator != widget.coordinator) {
      oldWidget.shutdownChannel.setMethodCallHandler(null);
      widget.shutdownChannel.setMethodCallHandler(_handleShutdownMethodCall);
    }
  }

  @override
  void dispose() {
    _listener.dispose();
    widget.shutdownChannel.setMethodCallHandler(null);
    if (widget.closeOnDispose) {
      unawaited(widget.coordinator.close());
    }
    super.dispose();
  }

  Future<Object?> _handleShutdownMethodCall(MethodCall call) async {
    if (call.method == 'getShutdownStatus') {
      return <String, Object>{
        'available': true,
        'shutdownStarted': widget.coordinator.shutdownHasStarted,
      };
    }
    if (call.method == 'requestShutdown') {
      return (await widget.coordinator.close()).toPlatformMessage();
    }
    throw MissingPluginException('Unknown shutdown method: ${call.method}');
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
