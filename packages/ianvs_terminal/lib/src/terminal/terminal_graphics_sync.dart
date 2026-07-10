import 'terminal_graphics_cache.dart';
import 'terminal_models.dart';

final class TerminalGraphicsSync {
  Object? _controllerIdentity;
  TerminalGraphicsCache? _cache;
  int? _assetRevision;
  final Set<TerminalGraphicAssetKey> _liveAssetKeys =
      <TerminalGraphicAssetKey>{};
  final Object _scratchIdentity = Object();

  Set<TerminalGraphicAssetKey> get debugLiveAssetKeys =>
      Set<TerminalGraphicAssetKey>.unmodifiable(_liveAssetKeys);
  Object get debugScratchIdentity => _scratchIdentity;

  bool synchronize({
    required Object controllerIdentity,
    required TerminalGraphicsCache? cache,
    required int assetRevision,
    required Iterable<TerminalGraphicAssetKey> liveAssetKeys,
  }) {
    if (cache == null) {
      reset();
      return false;
    }
    if (identical(_controllerIdentity, controllerIdentity) &&
        identical(_cache, cache) &&
        _assetRevision == assetRevision) {
      return false;
    }
    _liveAssetKeys
      ..clear()
      ..addAll(liveAssetKeys);
    try {
      cache.evictExcept(_liveAssetKeys);
    } catch (_) {
      reset();
      rethrow;
    }
    _controllerIdentity = controllerIdentity;
    _cache = cache;
    _assetRevision = assetRevision;
    return true;
  }

  void reset() {
    _controllerIdentity = null;
    _cache = null;
    _assetRevision = null;
    _liveAssetKeys.clear();
  }
}
