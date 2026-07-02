import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WindowBridge {
  const WindowBridge._();

  static const MethodChannel _channel = MethodChannel('app/window_bridge');

  static void setNativeMenuHandlers({
    Future<void> Function()? onPaste,
    Future<void> Function(NativeFindAction action)? onFind,
  }) {
    if (onPaste == null && onFind == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'nativePaste':
          final handler = onPaste;
          if (handler == null) {
            throw MissingPluginException('No handler for ${call.method}');
          }
          await handler();
        case 'nativeFind':
          final handler = onFind;
          if (handler == null) {
            throw MissingPluginException('No handler for ${call.method}');
          }
          await handler(NativeFindAction.fromTag(_findTagFrom(call.arguments)));
        default:
          throw MissingPluginException('No handler for ${call.method}');
      }
    });
  }

  static void setNativePasteHandler(Future<void> Function()? handler) {
    setNativeMenuHandlers(onPaste: handler);
  }

  static Future<void> resizeBy({
    required double widthDelta,
    required double heightDelta,
  }) async {
    if (BindingBase.debugBindingType() == null) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('resizeBy', {
        'widthDelta': widthDelta,
        'heightDelta': heightDelta,
      });
    } on MissingPluginException {
      return;
    }
  }

  static Future<void> setTitle(String title) async {
    if (BindingBase.debugBindingType() == null) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setTitle', {'title': title});
    } on MissingPluginException {
      return;
    }
  }

  static Future<void> requestQuitConfirmation() async {
    if (BindingBase.debugBindingType() == null) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('requestQuitConfirmation');
    } on MissingPluginException {
      return;
    }
  }

  static Future<void> beginWindowDrag() async {
    if (BindingBase.debugBindingType() == null) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('beginWindowDrag');
    } on MissingPluginException {
      return;
    }
  }

  static Future<void> toggleHotkeyWindow() async {
    if (BindingBase.debugBindingType() == null) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('toggleHotkeyWindow');
    } on MissingPluginException {
      return;
    }
  }

  static Future<HotkeyWindowStatus?> hotkeyStatus() async {
    if (BindingBase.debugBindingType() == null) {
      return null;
    }
    try {
      final status = await _channel.invokeMapMethod<String, Object?>(
        'hotkeyStatus',
      );
      if (status == null) {
        return null;
      }
      return HotkeyWindowStatus.fromMap(status);
    } on MissingPluginException {
      return null;
    }
  }

  static Future<WindowMetrics?> metrics() async {
    if (BindingBase.debugBindingType() == null) {
      return null;
    }
    try {
      final metrics = await _channel.invokeMapMethod<String, Object?>(
        'windowMetrics',
      );
      if (metrics == null) {
        return null;
      }
      return WindowMetrics.fromMap(metrics);
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> openExternalUrl(String url) async {
    if (BindingBase.debugBindingType() == null) {
      return;
    }
    final normalizedUrl = url.trim();
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null || !_isAllowedExternalUri(uri)) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('openExternalUrl', {
        'url': normalizedUrl,
      });
    } on MissingPluginException {
      return;
    }
  }

  static bool _isAllowedExternalUri(Uri uri) {
    return switch (uri.scheme.toLowerCase()) {
      'http' || 'https' => uri.host.isNotEmpty,
      'file' => uri.path.isNotEmpty,
      _ => false,
    };
  }

  static Future<void> showNotification({
    required String title,
    String? body,
    String? identifier,
  }) async {
    if (BindingBase.debugBindingType() == null) {
      return;
    }
    try {
      final arguments = <String, Object?>{'title': title};
      if (body != null) {
        arguments['body'] = body;
      }
      if (identifier != null) {
        arguments['identifier'] = identifier;
      }
      await _channel.invokeMethod<void>('showNotification', arguments);
    } on PlatformException catch (error) {
      if (error.code == 'notification_authorization_failed' ||
          error.code == 'notification_delivery_failed') {
        rethrow;
      }
      if (kDebugMode) {
        // ignore in release; keep diagnostics available in debug only
        debugPrint(
          'Failed to send notification '
          '[${error.code}] ${error.message ?? ''}',
        );
      }
    } on MissingPluginException {
      return;
    }
  }
}

class WindowMetrics {
  const WindowMetrics({
    this.contentSize,
    this.frameSize,
    this.devicePixelRatio,
  });

  final Size? contentSize;
  final Size? frameSize;
  final double? devicePixelRatio;

  factory WindowMetrics.fromMap(Map<String, Object?> map) {
    return WindowMetrics(
      contentSize: _sizeFromPlatformValues(
        map['contentWidth'],
        map['contentHeight'],
      ),
      frameSize: _sizeFromPlatformValues(map['frameWidth'], map['frameHeight']),
      devicePixelRatio: _positiveFiniteDoubleFromPlatformValue(
        map['devicePixelRatio'],
      ),
    );
  }
}

int? _findTagFrom(Object? arguments) {
  if (arguments is Map) {
    final tag = arguments['tag'];
    if (tag is int) {
      return tag;
    }
  }
  return null;
}

enum NativeFindAction {
  show,
  replace,
  next,
  previous,
  useSelection,
  jumpToSelection;

  factory NativeFindAction.fromTag(int? tag) {
    return switch (tag) {
      2 => NativeFindAction.next,
      3 => NativeFindAction.previous,
      7 => NativeFindAction.useSelection,
      12 => NativeFindAction.replace,
      _ => NativeFindAction.show,
    };
  }
}

class HotkeyWindowStatus {
  const HotkeyWindowStatus({
    required this.registered,
    required this.shortcut,
    this.errorCode,
  });

  final bool registered;
  final String shortcut;
  final int? errorCode;

  factory HotkeyWindowStatus.fromMap(Map<String, Object?> map) {
    return HotkeyWindowStatus(
      registered: map['registered'] == true,
      shortcut: _stringFromPlatformValue(map['shortcut']) ?? '⌥⌘Space',
      errorCode: _intFromPlatformValue(map['errorCode']),
    );
  }
}

String? _stringFromPlatformValue(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

Size? _sizeFromPlatformValues(Object? widthValue, Object? heightValue) {
  final width = _positiveFiniteDoubleFromPlatformValue(widthValue);
  final height = _positiveFiniteDoubleFromPlatformValue(heightValue);
  if (width == null || height == null) {
    return null;
  }
  return Size(width, height);
}

double? _positiveFiniteDoubleFromPlatformValue(Object? value) {
  if (value is num && value.isFinite && value > 0) {
    return value.toDouble();
  }
  return null;
}

int? _intFromPlatformValue(Object? value) {
  if (value is num && value.isFinite) {
    final parsed = value.toInt();
    if (value == parsed) {
      return parsed;
    }
  }
  return null;
}
