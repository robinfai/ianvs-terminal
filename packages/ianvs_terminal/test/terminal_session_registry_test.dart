import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/src/runtime/terminal_session_registry.dart';
import 'package:ianvs_terminal/src/terminal/terminal_models.dart';

void main() {
  group('TerminalSessionRegistry', () {
    test('registers sessions and reuses viewport controllers', () {
      final registry = TerminalSessionRegistry(
        loadGraphicAsset: (_, _) async => null,
      );

      registry.register('session-a');

      expect(registry.hasSession('session-a'), isTrue);
      expect(registry.hasSession('missing'), isFalse);
      expect(registry.sessionIds, <String>['session-a']);
      expect(
        identical(
          registry.viewportFor('session-a'),
          registry.viewportFor('session-a'),
        ),
        isTrue,
      );
      expect(registry.existingViewportFor('missing'), isNull);

      registry.dispose();
    });

    test('keeps graphics caches scoped to each session', () {
      final registry = TerminalSessionRegistry(
        loadGraphicAsset: (_, _) async => null,
      );

      registry
        ..register('session-a')
        ..register('session-b');

      final first = registry.graphicsCacheFor('session-a');
      final second = registry.graphicsCacheFor('session-b');

      expect(identical(first, registry.graphicsCacheFor('session-a')), isTrue);
      expect(identical(first, second), isFalse);

      registry.dispose();
    });

    test(
      'removing a session disposes its graphics cache and viewport',
      () async {
        final diagnostics = <Map<String, Object?>>[];
        final registry = TerminalSessionRegistry(
          loadGraphicAsset: (_, _) async => null,
          diagnosticEventSink: diagnostics.add,
        );
        const key = TerminalGraphicAssetKey(id: 7, version: 1);

        registry.register('session-a');
        final viewport = registry.viewportFor('session-a');
        final cache = registry.graphicsCacheFor('session-a');

        expect(registry.remove('session-a'), isTrue);
        expect(registry.hasSession('session-a'), isFalse);
        expect(registry.existingViewportFor('session-a'), isNull);

        await cache.imageFor(key);

        expect(
          diagnostics,
          contains(
            isA<Map<String, Object?>>()
                .having(
                  (event) => event['event'],
                  'event',
                  'cache_disposed_request',
                )
                .having((event) => event['session_id'], 'session', 'session-a'),
          ),
        );

        registry.register('session-a');
        expect(identical(viewport, registry.viewportFor('session-a')), isFalse);
        expect(
          identical(cache, registry.graphicsCacheFor('session-a')),
          isFalse,
        );

        registry.dispose();
      },
    );
  });
}
