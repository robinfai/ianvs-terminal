import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/platform/clipboard_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('named iTerm2 text writes use the macOS clipboard bridge', () async {
    const channel = MethodChannel('app/window_bridge');
    MethodCall? call;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (value) async {
          call = value;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await ClipboardBridge.writeText('Find pasteboard value', 'find');

    expect(call?.method, 'writeClipboardText');
    expect(call?.arguments, <String, Object?>{
      'text': 'Find pasteboard value',
      'selection': 'find',
    });
  });
}
