import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/shell/window_bridge.dart';

void main() {
  test('hotkey window status tolerates malformed platform fields', () {
    final status = HotkeyWindowStatus.fromMap(const <String, Object?>{
      'registered': 'yes',
      'shortcut': 42,
      'errorCode': 'bad',
    });

    expect(status.registered, isFalse);
    expect(status.shortcut, '⌥⌘Space');
    expect(status.errorCode, isNull);
  });

  test('hotkey window status accepts numeric error codes', () {
    final status = HotkeyWindowStatus.fromMap(const <String, Object?>{
      'registered': true,
      'shortcut': '⌃Space',
      'errorCode': 12.0,
    });

    expect(status.registered, isTrue);
    expect(status.shortcut, '⌃Space');
    expect(status.errorCode, 12);
  });
}
