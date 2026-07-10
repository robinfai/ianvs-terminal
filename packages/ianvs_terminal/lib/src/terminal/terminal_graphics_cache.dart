import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../runtime/terminal_benchmarking.dart';
import 'terminal_graphics_diagnostics.dart';
import 'terminal_models.dart';

typedef TerminalGraphicAssetLoader =
    Future<TerminalGraphicAsset?> Function(TerminalGraphicAssetKey key);

typedef TerminalGraphicImageDecoder =
    Future<ui.Image> Function(Uint8List rgba, int width, int height);

class TerminalGraphicAsset {
  const TerminalGraphicAsset({
    required this.key,
    required this.width,
    required this.height,
    required this.rgba,
  });

  final TerminalGraphicAssetKey key;
  final int width;
  final int height;
  final Uint8List rgba;

  bool get isValid {
    return width > 0 && height > 0 && rgba.length == width * height * 4;
  }
}

class TerminalGraphicsCache {
  TerminalGraphicsCache({
    required TerminalGraphicAssetLoader loadAsset,
    TerminalGraphicImageDecoder? decodeImage,
    String? diagnosticSessionId,
    TerminalBenchmarkEventSink? diagnosticEventSink,
  }) : _loadAsset = loadAsset,
       _decodeImage = decodeImage ?? _decodeRgbaImage,
       _diagnosticSessionId = diagnosticSessionId,
       _diagnosticEventSink = diagnosticEventSink;

  static const int _maxCachedImages = 128;

  final TerminalGraphicAssetLoader _loadAsset;
  final TerminalGraphicImageDecoder _decodeImage;
  final String? _diagnosticSessionId;
  final TerminalBenchmarkEventSink? _diagnosticEventSink;
  final Map<TerminalGraphicAssetKey, Future<ui.Image?>> _pending =
      <TerminalGraphicAssetKey, Future<ui.Image?>>{};
  final Map<TerminalGraphicAssetKey, ui.Image> _images =
      <TerminalGraphicAssetKey, ui.Image>{};
  final Map<TerminalGraphicAssetKey, Object> _activeLoadTokens =
      <TerminalGraphicAssetKey, Object>{};
  final Map<TerminalGraphicAssetKey, int> _lastSeenGeneration =
      <TerminalGraphicAssetKey, int>{};
  int _evictionGeneration = 0;
  bool _disposed = false;

  Future<ui.Image?> imageFor(TerminalGraphicAssetKey key) {
    if (_disposed) {
      _emitDiagnostic('cache_disposed_request', assetKey: key);
      return Future<ui.Image?>.value();
    }
    _lastSeenGeneration[key] = _evictionGeneration;
    final cached = _images[key];
    if (cached != null) {
      _emitDiagnostic('cache_hit', assetKey: key);
      return Future<ui.Image?>.value(cached);
    }
    final pending = _pending[key];
    if (pending != null) {
      _emitDiagnostic('cache_pending_hit', assetKey: key);
      return pending;
    }

    final loadToken = Object();
    _activeLoadTokens[key] = loadToken;
    late final Future<ui.Image?> load;
    load = _loadImage(key, loadToken).whenComplete(() {
      if (identical(_pending[key], load)) {
        _pending.remove(key);
      }
      if (identical(_activeLoadTokens[key], loadToken)) {
        _activeLoadTokens.remove(key);
      }
    });
    _pending[key] = load;
    _emitDiagnostic('cache_load_start', assetKey: key);
    return load;
  }

  Future<ui.Image?> _loadImage(
    TerminalGraphicAssetKey key,
    Object loadToken,
  ) async {
    final asset = await _loadAsset(key);
    if (asset == null || !asset.isValid) {
      _emitDiagnostic(
        asset == null ? 'cache_asset_missing' : 'cache_asset_invalid',
        assetKey: key,
        fields: asset == null
            ? const <String, Object?>{}
            : <String, Object?>{
                'width': asset.width,
                'height': asset.height,
                'rgba_bytes': asset.rgba.length,
              },
      );
      return null;
    }
    _emitDiagnostic(
      'cache_decode_start',
      assetKey: key,
      fields: <String, Object?>{
        'width': asset.width,
        'height': asset.height,
        'rgba_bytes': asset.rgba.length,
      },
    );
    final image = await _decodeImage(
      _premultiplyRgba(asset.rgba),
      asset.width,
      asset.height,
    );
    if (_isLoadStale(key, loadToken)) {
      _emitDiagnostic('cache_stale_after_decode', assetKey: key);
      image.dispose();
      return null;
    }
    _images[key] = image;
    _lastSeenGeneration[key] = _evictionGeneration;
    _emitDiagnostic(
      'cache_store',
      assetKey: key,
      fields: <String, Object?>{
        'cached_images': _images.length,
        'pending_images': _pending.length,
      },
    );
    return image;
  }

  bool _isLoadStale(TerminalGraphicAssetKey key, Object loadToken) {
    return _disposed ||
        !identical(_activeLoadTokens[key], loadToken) ||
        !_lastSeenGeneration.containsKey(key);
  }

  void _invalidateKey(TerminalGraphicAssetKey key) {
    final hadImage = _images.containsKey(key);
    final hadPending = _pending.containsKey(key);
    _images.remove(key)?.dispose();
    _pending.remove(key);
    _activeLoadTokens.remove(key);
    _lastSeenGeneration.remove(key);
    _emitDiagnostic(
      'cache_evict',
      assetKey: key,
      fields: <String, Object?>{
        'had_image': hadImage,
        'had_pending': hadPending,
      },
    );
  }

  void evictExcept(Set<TerminalGraphicAssetKey> liveKeys) {
    if (_diagnosticEventSink != null) {
      _emitDiagnostic(
        'cache_sync',
        fields: <String, Object?>{
          'live_asset_count': liveKeys.length,
          'cached_images_before': _images.length,
          'pending_images_before': _pending.length,
        },
      );
    }
    _evictionGeneration += 1;
    for (final key in liveKeys) {
      _lastSeenGeneration[key] = _evictionGeneration;
    }
    final unusedKeys = <TerminalGraphicAssetKey>{
      ..._images.keys.where((key) => !liveKeys.contains(key)),
      ..._pending.keys.where((key) => !liveKeys.contains(key)),
    };
    for (final key in unusedKeys) {
      _invalidateKey(key);
    }

    if (_images.length <= _maxCachedImages) {
      return;
    }
    final overflowKeys =
        _images.keys
            .where((key) => !liveKeys.contains(key))
            .toList(growable: false)
          ..sort(
            (left, right) => (_lastSeenGeneration[left] ?? 0).compareTo(
              _lastSeenGeneration[right] ?? 0,
            ),
          );
    for (final key in overflowKeys) {
      if (_images.length <= _maxCachedImages) {
        break;
      }
      _invalidateKey(key);
    }
  }

  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _lastSeenGeneration.clear();
    _pending.clear();
    _activeLoadTokens.clear();
  }

  void _emitDiagnostic(
    String event, {
    TerminalGraphicAssetKey? assetKey,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    emitTerminalGraphicsDiagnostic(
      _diagnosticEventSink,
      layer: 'graphics_cache',
      event: event,
      sessionId: _diagnosticSessionId,
      assetKey: assetKey,
      fields: fields,
    );
  }
}

Future<ui.Image> _decodeRgbaImage(Uint8List rgba, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

Uint8List _premultiplyRgba(Uint8List rgba) {
  Uint8List? premultiplied;
  for (var offset = 0; offset + 3 < rgba.length; offset += 4) {
    final alpha = rgba[offset + 3];
    if (alpha == 255) {
      continue;
    }
    premultiplied ??= Uint8List.fromList(rgba);
    if (alpha == 0) {
      premultiplied[offset] = 0;
      premultiplied[offset + 1] = 0;
      premultiplied[offset + 2] = 0;
      continue;
    }
    premultiplied[offset] = _premultiplyChannel(rgba[offset], alpha);
    premultiplied[offset + 1] = _premultiplyChannel(rgba[offset + 1], alpha);
    premultiplied[offset + 2] = _premultiplyChannel(rgba[offset + 2], alpha);
  }
  return premultiplied ?? rgba;
}

int _premultiplyChannel(int channel, int alpha) {
  return ((channel * alpha) + 127) ~/ 255;
}
