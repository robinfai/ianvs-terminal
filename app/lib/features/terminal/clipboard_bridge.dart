import 'package:flutter/services.dart';

class ClipboardBridge {
  const ClipboardBridge._();

  static Future<void> copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
  }

  static Future<String> paste() async {
    final data = await Clipboard.getData('text/plain');
    return data?.text ?? '';
  }
}
