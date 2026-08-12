import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../platform/app_shutdown_coordinator.dart';
import 'data_api_runtime.dart';

class DataApiLifecycleBoundary extends StatefulWidget {
  const DataApiLifecycleBoundary({
    required this.runtime,
    required this.shutdownCoordinator,
    required this.child,
    this.shutdownChannel = const MethodChannel('app/shutdown'),
    super.key,
  });

  final DataApiRuntime? runtime;
  final AppShutdownCoordinator shutdownCoordinator;
  final Widget child;
  final MethodChannel shutdownChannel;

  @override
  State<DataApiLifecycleBoundary> createState() =>
      _DataApiLifecycleBoundaryState();
}

class _DataApiLifecycleBoundaryState extends State<DataApiLifecycleBoundary> {
  static const String _dataApiShutdownTaskName = 'data-api-runtime';

  late final AppLifecycleListener _listener;
  bool _didReportShutdownResult = false;

  @override
  void initState() {
    super.initState();
    widget.shutdownCoordinator.registerTask(
      _dataApiShutdownTaskName,
      _closeRuntime,
      phase: AppShutdownPhase.infrastructure,
    );
    widget.shutdownChannel.setMethodCallHandler(_handleShutdownMethodCall);
    _listener = AppLifecycleListener(
      onDetach: () => unawaited(_shutdown()),
      onExitRequested: () async {
        final result = await _shutdown();
        return result.safeToTerminate
            ? AppExitResponse.exit
            : AppExitResponse.cancel;
      },
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    widget.shutdownChannel.setMethodCallHandler(null);
    unawaited(_shutdown());
    super.dispose();
  }

  Future<Object?> _handleShutdownMethodCall(MethodCall call) async {
    if (call.method != 'requestShutdown') {
      throw MissingPluginException('Unknown shutdown method: ${call.method}');
    }
    return (await _shutdown()).toPlatformMessage();
  }

  Future<AppShutdownResult> _shutdown() async {
    final result = await widget.shutdownCoordinator.shutdown();
    if (!_didReportShutdownResult) {
      _didReportShutdownResult = true;
      _reportFailures(result);
    }
    return result;
  }

  void _reportFailures(AppShutdownResult result) {
    for (final failure in result.failures) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: failure.error,
          stack: failure.stackTrace,
          library: 'Ianvs Terminal shutdown',
          context: ErrorDescription(
            'while running shutdown task "${failure.taskName}"',
          ),
        ),
      );
    }
    if (result.timedOut) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: TimeoutException(
            'Application shutdown exceeded its bounded timeout.',
            widget.shutdownCoordinator.timeout,
          ),
          library: 'Ianvs Terminal shutdown',
        ),
      );
    }
  }

  Future<void> _closeRuntime() {
    return widget.runtime?.close() ?? Future<void>.value();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
