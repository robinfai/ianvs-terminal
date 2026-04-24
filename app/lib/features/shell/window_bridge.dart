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
}
