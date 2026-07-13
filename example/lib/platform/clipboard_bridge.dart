import 'package:flutter/services.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

class ClipboardBridge {
  const ClipboardBridge._();

  static const MethodChannel _channel = MethodChannel('app/window_bridge');

  static Future<void> copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
  }

  static Future<void> writeText(String value, String selection) async {
    if (selection == 'c') {
      await copy(value);
      return;
    }
    await _channel.invokeMethod<void>('writeClipboardText', <String, Object?>{
      'text': value,
      'selection': selection,
    });
  }

  static Future<String> paste() async {
    final data = await Clipboard.getData('text/plain');
    return data?.text ?? '';
  }

  static Future<void> writeMimeItems(
    List<TerminalClipboardMimeItem> items,
  ) async {
    await _channel.invokeMethod<void>('writeClipboardMime', <String, Object?>{
      'items': <Map<String, Object?>>[
        for (final item in items)
          <String, Object?>{
            'mime': item.mimeType,
            'data': item.bytes,
            'aliases': item.aliases,
          },
      ],
    });
  }

  static Future<List<TerminalClipboardMimeItem>> readMimeItems(
    List<String> mimeTypes,
  ) async {
    final response = await _channel.invokeMapMethod<String, Object?>(
      'readClipboardMime',
      <String, Object?>{'mimeTypes': mimeTypes},
    );
    final rawItems = response?['items'];
    if (rawItems is! List<Object?>) {
      return const <TerminalClipboardMimeItem>[];
    }
    final items = <TerminalClipboardMimeItem>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map<Object?, Object?>) continue;
      final mime = rawItem['mime'];
      final data = rawItem['data'];
      if (mime is String && data is Uint8List) {
        items.add(TerminalClipboardMimeItem(mimeType: mime, bytes: data));
      }
    }
    return items;
  }

  static Future<List<String>> listMimeTypes() async {
    final values = await _channel.invokeListMethod<String>(
      'listClipboardMimeTypes',
    );
    return List<String>.unmodifiable(values ?? const <String>[]);
  }
}
