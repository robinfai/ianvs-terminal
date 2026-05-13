import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WindowBridge {
  const WindowBridge._();

  static const MethodChannel _channel = MethodChannel('app/window_bridge');

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

  static Future<void> openExternalUrl(String url) async {
    if (BindingBase.debugBindingType() == null) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('openExternalUrl', {'url': url});
    } on MissingPluginException {
      return;
    }
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
    } on MissingPluginException {
      return;
    }
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
      shortcut: map['shortcut'] as String? ?? '⌥⌘Space',
      errorCode: map['errorCode'] as int?,
    );
  }
}
