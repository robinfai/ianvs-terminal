import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

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
  }) : _loadAsset = loadAsset,
       _decodeImage = decodeImage ?? _decodeRgbaImage;

  static const int _maxCachedImages = 128;

  final TerminalGraphicAssetLoader _loadAsset;
  final TerminalGraphicImageDecoder _decodeImage;
  final Map<TerminalGraphicAssetKey, Future<ui.Image?>> _pending =
      <TerminalGraphicAssetKey, Future<ui.Image?>>{};
  final Map<TerminalGraphicAssetKey, ui.Image> _images =
      <TerminalGraphicAssetKey, ui.Image>{};
  final Map<TerminalGraphicAssetKey, int> _lastSeenGeneration =
      <TerminalGraphicAssetKey, int>{};
  int _evictionGeneration = 0;

  Future<ui.Image?> imageFor(TerminalGraphicAssetKey key) {
    _lastSeenGeneration[key] = _evictionGeneration;
    final cached = _images[key];
    if (cached != null) {
      return Future<ui.Image?>.value(cached);
    }
    return _pending.putIfAbsent(key, () async {
      try {
        final asset = await _loadAsset(key);
        if (asset == null || !asset.isValid) {
          return null;
        }
        final image = await _decodeImage(
          _premultiplyRgba(asset.rgba),
          asset.width,
          asset.height,
        );
        _images[key] = image;
        _lastSeenGeneration[key] = _evictionGeneration;
        return image;
      } finally {
        _pending.remove(key);
      }
    });
  }

  void evictExcept(Set<TerminalGraphicAssetKey> liveKeys) {
    _evictionGeneration += 1;
    for (final key in liveKeys) {
      _lastSeenGeneration[key] = _evictionGeneration;
    }
    final unusedKeys = _images.keys
        .where((key) => !liveKeys.contains(key))
        .toList(growable: false);
    for (final key in unusedKeys) {
      _images.remove(key)?.dispose();
      _lastSeenGeneration.remove(key);
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
      _images.remove(key)?.dispose();
      _lastSeenGeneration.remove(key);
    }
  }

  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _lastSeenGeneration.clear();
    _pending.clear();
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
