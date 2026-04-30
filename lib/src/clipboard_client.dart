import 'package:flutter/services.dart';

abstract class ClipboardClient {
  Future<String> readText();
  Future<void> writeText(String text);
}

class FlutterClipboardClient implements ClipboardClient {
  const FlutterClipboardClient();

  @override
  Future<String> readText() async {
    return (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
  }

  @override
  Future<void> writeText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }
}
