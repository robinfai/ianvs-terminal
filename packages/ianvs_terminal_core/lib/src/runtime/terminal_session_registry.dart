import '../terminal/terminal_graphics_cache.dart';
import '../terminal/terminal_models.dart';
import '../terminal/terminal_viewport.dart';
import 'terminal_benchmarking.dart';

typedef TerminalSessionGraphicAssetLoader =
    Future<TerminalGraphicAsset?> Function(
      String sessionId,
      TerminalGraphicAssetKey key,
    );

final class TerminalSessionRegistry {
  TerminalSessionRegistry({
    required TerminalSessionGraphicAssetLoader loadGraphicAsset,
    TerminalBenchmarkEventSink? diagnosticEventSink,
  }) : _loadGraphicAsset = loadGraphicAsset,
       _diagnosticEventSink = diagnosticEventSink;

  final TerminalSessionGraphicAssetLoader _loadGraphicAsset;
  final TerminalBenchmarkEventSink? _diagnosticEventSink;
  final Set<String> _activeSessionIds = <String>{};
  final Map<String, TerminalViewportController> _viewportControllers =
      <String, TerminalViewportController>{};
  final Map<String, TerminalGraphicsCache> _graphicsCaches =
      <String, TerminalGraphicsCache>{};

  List<String> get sessionIds => _activeSessionIds.toList(growable: false);

  bool get isEmpty => _activeSessionIds.isEmpty;

  bool hasSession(String sessionId) => _activeSessionIds.contains(sessionId);

  void register(String sessionId) {
    _activeSessionIds.add(sessionId);
    viewportFor(sessionId);
  }

  TerminalViewportController viewportFor(String sessionId) {
    return _viewportControllers.putIfAbsent(
      sessionId,
      TerminalViewportController.new,
    );
  }

  TerminalViewportController? existingViewportFor(String sessionId) {
    return _viewportControllers[sessionId];
  }

  TerminalGraphicsCache graphicsCacheFor(String sessionId) {
    return _graphicsCaches.putIfAbsent(
      sessionId,
      () => TerminalGraphicsCache(
        loadAsset: (key) => _loadGraphicAsset(sessionId, key),
        diagnosticSessionId: sessionId,
        diagnosticEventSink: _diagnosticEventSink,
      ),
    );
  }

  bool remove(String sessionId) {
    final wasActive = _activeSessionIds.remove(sessionId);
    _graphicsCaches.remove(sessionId)?.dispose();
    _viewportControllers.remove(sessionId)?.dispose();
    return wasActive;
  }

  void dispose() {
    for (final cache in _graphicsCaches.values) {
      cache.dispose();
    }
    for (final controller in _viewportControllers.values) {
      controller.dispose();
    }
    _activeSessionIds.clear();
    _graphicsCaches.clear();
    _viewportControllers.clear();
  }
}
