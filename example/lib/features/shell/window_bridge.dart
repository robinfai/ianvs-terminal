import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum NativeUserAttentionType { critical, informational }

enum NativeAppMenuAction {
  settings;

  static NativeAppMenuAction fromPlatform(Object? arguments) {
    final action = arguments is Map ? arguments['action'] : null;
    return switch (action) {
      'settings' => NativeAppMenuAction.settings,
      _ => throw PlatformException(
        code: 'unknown_native_app_action',
        message: 'Unknown native app action: $action',
      ),
    };
  }
}

class WindowBridge {
  const WindowBridge._();

  static const MethodChannel _channel = MethodChannel('app/window_bridge');

  @visibleForTesting
  static TargetPlatform? debugZmodemFileDialogPlatformOverride;

  // The example runner currently implements these native dialogs on macOS.
  // The runtime core remains independently usable on supported Linux hosts.
  static bool get supportsZmodemFileDialogs =>
      !kIsWeb &&
      (debugZmodemFileDialogPlatformOverride ?? defaultTargetPlatform) ==
          TargetPlatform.macOS;

  static bool get supportsPathReveal => !kIsWeb;

  static void setNativeMenuHandlers({
    Future<void> Function()? onPaste,
    Future<void> Function()? onOpenTerminalAtFolder,
    Future<void> Function(NativeAppMenuAction action)? onAppAction,
    Future<void> Function(NativeFindAction action)? onFind,
    Future<void> Function(NativeOsc72DragEvent event)? onOsc72DragEvent,
  }) {
    if (onPaste == null &&
        onOpenTerminalAtFolder == null &&
        onAppAction == null &&
        onFind == null &&
        onOsc72DragEvent == null) {
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
        case 'nativeOpenTerminalAtFolder':
          final handler = onOpenTerminalAtFolder;
          if (handler == null) {
            throw MissingPluginException('No handler for ${call.method}');
          }
          await handler();
        case 'nativeAppAction':
          final handler = onAppAction;
          if (handler == null) {
            throw MissingPluginException('No handler for ${call.method}');
          }
          await handler(NativeAppMenuAction.fromPlatform(call.arguments));
        case 'nativeFind':
          final handler = onFind;
          if (handler == null) {
            throw MissingPluginException('No handler for ${call.method}');
          }
          await handler(NativeFindAction.fromTag(_findTagFrom(call.arguments)));
        case 'osc72DragEvent':
          final handler = onOsc72DragEvent;
          if (handler == null) {
            throw MissingPluginException('No handler for ${call.method}');
          }
          await handler(NativeOsc72DragEvent.fromPlatform(call.arguments));
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
    try {
      await _channel.invokeMethod<void>('setTitle', {'title': title});
    } on MissingPluginException {
      return;
    }
  }

  static Future<void> requestQuitConfirmation() async {
    try {
      await _channel.invokeMethod<void>('requestQuitConfirmation');
    } on MissingPluginException {
      return;
    }
  }

  static Future<void> beginWindowDrag() async {
    try {
      await _channel.invokeMethod<void>('beginWindowDrag');
    } on MissingPluginException {
      return;
    }
  }

  static Future<void> toggleHotkeyWindow() async {
    try {
      await _channel.invokeMethod<void>('toggleHotkeyWindow');
    } on MissingPluginException {
      return;
    }
  }

  static Future<HotkeyWindowStatus?> hotkeyStatus() async {
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

  static Future<int?> requestUserAttention(NativeUserAttentionType type) async {
    try {
      final requestId = await _channel.invokeMethod<int>(
        'requestUserAttention',
        <String, Object?>{'type': type.name},
      );
      return requestId != null && requestId >= 0 ? requestId : null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> cancelUserAttention(int requestId) async {
    if (requestId < 0) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(
        'cancelUserAttention',
        <String, Object?>{'requestId': requestId},
      );
    } on MissingPluginException {
      return;
    }
  }

  static Future<String?> chooseFileDownloadLocation({
    required String suggestedName,
  }) async {
    final safeName = _safeSuggestedFileName(suggestedName);
    try {
      final selected = await _channel.invokeMethod<String>(
        'chooseFileDownloadLocation',
        <String, Object?>{'suggestedName': safeName},
      );
      return selected == null || selected.isEmpty ? null : selected;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<String?> chooseTerminalFolder() async {
    try {
      final selected = await _channel.invokeMethod<String>(
        'chooseTerminalFolder',
      );
      return selected == null || selected.isEmpty ? null : selected;
    } on MissingPluginException {
      return null;
    }
  }

  /// Opens the platform directory picker.
  ///
  /// The current platform channel cannot dismiss a picker that is already in
  /// flight. Callers must correlate the returned value with their own request
  /// token and ignore it when the owning operation has ended.
  static Future<String?> chooseZmodemReceiveDirectory() async {
    if (!supportsZmodemFileDialogs) {
      throw UnsupportedError('ZMODEM file dialogs are unavailable');
    }
    final selected = await _channel.invokeMethod<String>(
      'chooseZmodemReceiveDirectory',
    );
    return selected == null || selected.isEmpty ? null : selected;
  }

  /// Opens the platform multi-file picker.
  ///
  /// The current platform channel cannot dismiss a picker that is already in
  /// flight. Callers must correlate the returned value with their own request
  /// token and ignore it when the owning operation has ended.
  static Future<List<String>?> chooseZmodemSendFiles() async {
    if (!supportsZmodemFileDialogs) {
      throw UnsupportedError('ZMODEM file dialogs are unavailable');
    }
    final selected = await _channel.invokeListMethod<String>(
      'chooseZmodemSendFiles',
    );
    if (selected == null) {
      return null;
    }
    final paths = selected
        .where((path) => path.isNotEmpty)
        .toSet()
        .toList(growable: false);
    return paths.isEmpty ? null : paths;
  }

  static Future<String?> chooseRecordingFile({String? initialDirectory}) async {
    final normalizedInitialDirectory = initialDirectory?.trim();
    try {
      final selected = await _channel
          .invokeMethod<String>('chooseRecordingFile', <String, Object?>{
            if (normalizedInitialDirectory != null &&
                normalizedInitialDirectory.isNotEmpty)
              'initialDirectory': normalizedInitialDirectory,
          });
      return selected == null || selected.isEmpty ? null : selected;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<bool> revealInFinder(String value) async {
    if (value.trim().isEmpty) {
      throw const FormatException('Finder path must not be empty.');
    }
    if (!supportsPathReveal) {
      return false;
    }
    try {
      await _channel.invokeMethod<void>('revealInFinder', <String, Object?>{
        'path': value,
      });
      return true;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> movePathToTrash(String value) async {
    if (value.trim().isEmpty) {
      throw const FormatException('Trash path must not be empty.');
    }
    try {
      return await _channel.invokeMethod<bool>(
            'movePathToTrash',
            <String, Object?>{'path': value},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  static String _safeSuggestedFileName(String value) {
    final basename = value.split(RegExp(r'[/\\]')).last;
    final runes = basename.runes
        .where((rune) => rune >= 0x20 && rune != 0x7f)
        .take(160)
        .toList(growable: false);
    final safe = String.fromCharCodes(runes).trim();
    return safe.isEmpty || safe == '.' || safe == '..' ? 'Unnamed file' : safe;
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
    int? expiresAfterMs,
  }) async {
    try {
      final arguments = <String, Object?>{'title': title};
      if (body != null) {
        arguments['body'] = body;
      }
      if (identifier != null) {
        arguments['identifier'] = identifier;
      }
      if (expiresAfterMs != null) {
        arguments['expiresAfterMs'] = expiresAfterMs;
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

  static Future<void> closeNotification(String identifier) async {
    if (identifier.isEmpty) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('closeNotification', {
        'identifier': identifier,
      });
    } on MissingPluginException {
      return;
    }
  }

  static Future<void> configureOsc72DropTarget({
    required bool enabled,
    String? sessionId,
    List<String> mimeTypes = const <String>[],
  }) async {
    try {
      await _channel.invokeMethod<void>('configureOsc72DropTarget', {
        'enabled': enabled,
        'sessionId': ?sessionId,
        'mimeTypes': mimeTypes,
      });
    } on MissingPluginException {
      return;
    }
  }

  static Future<void> setOsc72DropDecision(int operation) async {
    try {
      await _channel.invokeMethod<void>('setOsc72DropDecision', {
        'operation': operation,
      });
    } on MissingPluginException {
      return;
    }
  }

  static Future<NativeOsc72DropChunk> readOsc72DropData({
    required String dropId,
    required String mimeType,
    required int offset,
    int maxBytes = 3072,
  }) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'readOsc72DropData',
      {
        'dropId': dropId,
        'mimeType': mimeType,
        'offset': offset,
        'maxBytes': maxBytes,
      },
    );
    if (result == null || result['bytes'] is! Uint8List) {
      throw const FormatException('Invalid OSC 72 drop chunk');
    }
    return NativeOsc72DropChunk(
      bytes: result['bytes']! as Uint8List,
      eof: result['eof'] == true,
      size: _nonNegativeInt(result['size']),
    );
  }

  static Future<void> releaseOsc72Drop(String dropId) async {
    if (dropId.isEmpty) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('releaseOsc72Drop', {'dropId': dropId});
    } on MissingPluginException {
      return;
    }
  }

  static Future<NativeOsc72DropTargetStatus?> osc72DropTargetStatus() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'osc72DropTargetStatus',
      );
      return result == null
          ? null
          : NativeOsc72DropTargetStatus.fromPlatform(result);
    } on MissingPluginException {
      return null;
    }
  }
}

class NativeOsc72DragEvent {
  const NativeOsc72DragEvent({
    required this.phase,
    required this.sessionId,
    required this.mimeTypes,
    required this.position,
    required this.operations,
    this.dropId,
  });

  final String phase;
  final String sessionId;
  final List<String> mimeTypes;
  final Offset position;
  final int operations;
  final String? dropId;

  factory NativeOsc72DragEvent.fromPlatform(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid OSC 72 drag event');
    }
    final phase = value['phase'];
    final sessionId = value['sessionId'];
    if (phase is! String || sessionId is! String) {
      throw const FormatException('Invalid OSC 72 drag event identity');
    }
    final rawMimeTypes = value['mimeTypes'];
    final mimeTypes = rawMimeTypes is List
        ? rawMimeTypes.whereType<String>().take(64).toList(growable: false)
        : const <String>[];
    return NativeOsc72DragEvent(
      phase: phase,
      sessionId: sessionId,
      mimeTypes: mimeTypes,
      position: Offset(_finiteDouble(value['x']), _finiteDouble(value['y'])),
      operations: _nonNegativeInt(value['operations']) ?? 0,
      dropId: value['dropId'] is String ? value['dropId'] as String : null,
    );
  }
}

class NativeOsc72DropChunk {
  const NativeOsc72DropChunk({
    required this.bytes,
    required this.eof,
    this.size,
  });

  final Uint8List bytes;
  final bool eof;
  final int? size;
}

class NativeOsc72DropTargetStatus {
  const NativeOsc72DropTargetStatus({
    required this.enabled,
    required this.mimeTypes,
    required this.decision,
    required this.cachedDrops,
    this.sessionId,
  });

  final bool enabled;
  final String? sessionId;
  final List<String> mimeTypes;
  final int decision;
  final int cachedDrops;

  factory NativeOsc72DropTargetStatus.fromPlatform(Map<String, Object?> value) {
    final rawMimeTypes = value['mimeTypes'];
    return NativeOsc72DropTargetStatus(
      enabled: value['enabled'] == true,
      sessionId: value['sessionId'] is String
          ? value['sessionId']! as String
          : null,
      mimeTypes: rawMimeTypes is List
          ? rawMimeTypes.whereType<String>().take(64).toList(growable: false)
          : const <String>[],
      decision: _nonNegativeInt(value['decision']) ?? 0,
      cachedDrops: _nonNegativeInt(value['cachedDrops']) ?? 0,
    );
  }
}

double _finiteDouble(Object? value) {
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  return 0;
}

int? _nonNegativeInt(Object? value) {
  if (value is int && value >= 0) {
    return value;
  }
  return null;
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
