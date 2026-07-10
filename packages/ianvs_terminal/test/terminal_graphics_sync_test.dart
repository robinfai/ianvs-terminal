import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/src/terminal/terminal_graphics_cache.dart';
import 'package:ianvs_terminal/src/terminal/terminal_graphics_sync.dart';
import 'package:ianvs_terminal/src/terminal/terminal_models.dart';

void main() {
  group(TerminalGraphicsSync, () {
    late TerminalGraphicsSync sync;
    late _RecordingGraphicsCache firstCache;
    late _RecordingGraphicsCache secondCache;

    setUp(() {
      sync = TerminalGraphicsSync();
      firstCache = _RecordingGraphicsCache();
      secondCache = _RecordingGraphicsCache();
    });

    tearDown(() {
      firstCache.dispose();
      secondCache.dispose();
    });

    test('first non-null cache syncs and identical state is skipped', () {
      final controller = Object();

      expect(
        sync.synchronize(
          controllerIdentity: controller,
          cache: firstCache,
          assetRevision: 0,
          liveAssetKeys: const <TerminalGraphicAssetKey>{},
        ),
        isTrue,
      );
      expect(firstCache.liveKeySets, [<TerminalGraphicAssetKey>{}]);
      expect(
        sync.synchronize(
          controllerIdentity: controller,
          cache: firstCache,
          assetRevision: 0,
          liveAssetKeys: const <TerminalGraphicAssetKey>{},
        ),
        isFalse,
      );
      expect(firstCache.liveKeySets, hasLength(1));
    });

    test('higher revision deduplicates keys and authoritative empty syncs', () {
      const firstKey = TerminalGraphicAssetKey(id: 1, version: 1);
      const secondKey = TerminalGraphicAssetKey(id: 2, version: 1);
      final controller = Object();
      sync.synchronize(
        controllerIdentity: controller,
        cache: firstCache,
        assetRevision: 0,
        liveAssetKeys: const <TerminalGraphicAssetKey>{},
      );

      expect(
        sync.synchronize(
          controllerIdentity: controller,
          cache: firstCache,
          assetRevision: 1,
          liveAssetKeys: const <TerminalGraphicAssetKey>[
            firstKey,
            secondKey,
            firstKey,
          ],
        ),
        isTrue,
      );
      expect(sync.debugLiveAssetKeys, {firstKey, secondKey});

      expect(
        sync.synchronize(
          controllerIdentity: controller,
          cache: firstCache,
          assetRevision: 2,
          liveAssetKeys: const <TerminalGraphicAssetKey>{},
        ),
        isTrue,
      );
      expect(sync.debugLiveAssetKeys, isEmpty);
    });

    test('controller and cache replacement force same-revision sync', () {
      final firstController = Object();
      final secondController = Object();
      sync.synchronize(
        controllerIdentity: firstController,
        cache: firstCache,
        assetRevision: 0,
        liveAssetKeys: const <TerminalGraphicAssetKey>{},
      );

      expect(
        sync.synchronize(
          controllerIdentity: secondController,
          cache: firstCache,
          assetRevision: 0,
          liveAssetKeys: const <TerminalGraphicAssetKey>{},
        ),
        isTrue,
      );
      expect(
        sync.synchronize(
          controllerIdentity: secondController,
          cache: secondCache,
          assetRevision: 0,
          liveAssetKeys: const <TerminalGraphicAssetKey>{},
        ),
        isTrue,
      );
    });

    test('failed eviction resets binding and live-key scratch state', () {
      const firstKey = TerminalGraphicAssetKey(id: 1, version: 1);
      const secondKey = TerminalGraphicAssetKey(id: 2, version: 1);
      final firstController = Object();
      final secondController = Object();
      sync.synchronize(
        controllerIdentity: firstController,
        cache: firstCache,
        assetRevision: 0,
        liveAssetKeys: const <TerminalGraphicAssetKey>[firstKey],
      );

      firstCache.throwOnNextEviction = true;
      expect(
        () => sync.synchronize(
          controllerIdentity: secondController,
          cache: firstCache,
          assetRevision: 1,
          liveAssetKeys: const <TerminalGraphicAssetKey>[secondKey],
        ),
        throwsStateError,
      );
      expect(sync.debugLiveAssetKeys, isEmpty);

      expect(
        sync.synchronize(
          controllerIdentity: firstController,
          cache: firstCache,
          assetRevision: 0,
          liveAssetKeys: const <TerminalGraphicAssetKey>[firstKey],
        ),
        isTrue,
      );
      expect(firstCache.liveKeySets, [
        <TerminalGraphicAssetKey>{firstKey},
        <TerminalGraphicAssetKey>{secondKey},
        <TerminalGraphicAssetKey>{firstKey},
      ]);
    });

    test('debug live keys are an immutable snapshot', () {
      const key = TerminalGraphicAssetKey(id: 1, version: 1);
      final controller = Object();
      sync.synchronize(
        controllerIdentity: controller,
        cache: firstCache,
        assetRevision: 0,
        liveAssetKeys: const <TerminalGraphicAssetKey>[key],
      );

      final debugKeys = sync.debugLiveAssetKeys;
      expect(debugKeys.clear, throwsUnsupportedError);
      expect(sync.debugLiveAssetKeys, <TerminalGraphicAssetKey>{key});
    });

    test('feeding a debug snapshot back does not clear live keys', () {
      const key = TerminalGraphicAssetKey(id: 1, version: 1);
      final controller = Object();
      sync.synchronize(
        controllerIdentity: controller,
        cache: firstCache,
        assetRevision: 0,
        liveAssetKeys: const <TerminalGraphicAssetKey>[key],
      );
      final debugKeys = sync.debugLiveAssetKeys;

      expect(
        sync.synchronize(
          controllerIdentity: controller,
          cache: firstCache,
          assetRevision: 1,
          liveAssetKeys: debugKeys,
        ),
        isTrue,
      );
      expect(sync.debugLiveAssetKeys, <TerminalGraphicAssetKey>{key});
    });

    test('debug scratch identity is an independent stable token', () {
      final controller = Object();
      final scratchIdentity = sync.debugScratchIdentity;
      expect(identical(scratchIdentity, sync.debugLiveAssetKeys), isFalse);

      sync.synchronize(
        controllerIdentity: controller,
        cache: firstCache,
        assetRevision: 0,
        liveAssetKeys: const <TerminalGraphicAssetKey>{},
      );
      expect(identical(sync.debugScratchIdentity, scratchIdentity), isTrue);

      sync.reset();
      expect(identical(sync.debugScratchIdentity, scratchIdentity), isTrue);
    });

    test('reuses one scratch set and null cache clears the binding', () {
      final controller = Object();
      sync.synchronize(
        controllerIdentity: controller,
        cache: firstCache,
        assetRevision: 0,
        liveAssetKeys: const <TerminalGraphicAssetKey>{},
      );
      final scratchIdentity = sync.debugScratchIdentity;

      sync.synchronize(
        controllerIdentity: controller,
        cache: firstCache,
        assetRevision: 1,
        liveAssetKeys: const <TerminalGraphicAssetKey>[
          TerminalGraphicAssetKey(id: 1, version: 1),
        ],
      );
      expect(identical(sync.debugScratchIdentity, scratchIdentity), isTrue);

      expect(
        sync.synchronize(
          controllerIdentity: controller,
          cache: null,
          assetRevision: 1,
          liveAssetKeys: const <TerminalGraphicAssetKey>{},
        ),
        isFalse,
      );
      expect(
        sync.synchronize(
          controllerIdentity: controller,
          cache: firstCache,
          assetRevision: 1,
          liveAssetKeys: const <TerminalGraphicAssetKey>{},
        ),
        isTrue,
      );

      sync.reset();
      expect(sync.debugLiveAssetKeys, isEmpty);
      expect(identical(sync.debugScratchIdentity, scratchIdentity), isTrue);
    });
  });
}

final class _RecordingGraphicsCache extends TerminalGraphicsCache {
  _RecordingGraphicsCache() : super(loadAsset: (_) async => null);

  final List<Set<TerminalGraphicAssetKey>> liveKeySets =
      <Set<TerminalGraphicAssetKey>>[];
  bool throwOnNextEviction = false;

  @override
  void evictExcept(Set<TerminalGraphicAssetKey> liveKeys) {
    liveKeySets.add(Set<TerminalGraphicAssetKey>.of(liveKeys));
    if (throwOnNextEviction) {
      throwOnNextEviction = false;
      throw StateError('eviction failed');
    }
    super.evictExcept(liveKeys);
  }
}
