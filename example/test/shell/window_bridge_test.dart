import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:app/features/shell/window_bridge.dart';

void main() {
  test('window metrics accepts finite platform sizes', () {
    final metrics = WindowMetrics.fromMap(const <String, Object?>{
      'contentWidth': 900.0,
      'contentHeight': 600.0,
      'frameWidth': 940.0,
      'frameHeight': 660.0,
      'devicePixelRatio': 2.0,
    });

    expect(metrics.contentSize, const Size(900, 600));
    expect(metrics.frameSize, const Size(940, 660));
    expect(metrics.devicePixelRatio, 2);
  });

  test('window metrics ignores invalid platform sizes', () {
    final metrics = WindowMetrics.fromMap(const <String, Object?>{
      'contentWidth': -1.0,
      'contentHeight': 600.0,
      'frameWidth': 940.0,
      'frameHeight': double.infinity,
      'devicePixelRatio': 0.0,
    });

    expect(metrics.contentSize, isNull);
    expect(metrics.frameSize, isNull);
    expect(metrics.devicePixelRatio, isNull);
  });

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
      'shortcut': ' ⌃Space ',
      'errorCode': 12.0,
    });

    expect(status.registered, isTrue);
    expect(status.shortcut, '⌃Space');
    expect(status.errorCode, 12);
  });

  test('hotkey window status rejects fractional error codes', () {
    final status = HotkeyWindowStatus.fromMap(const <String, Object?>{
      'registered': true,
      'errorCode': 12.5,
    });

    expect(status.errorCode, isNull);
  });

  test('hotkey window status falls back for blank shortcuts', () {
    final status = HotkeyWindowStatus.fromMap(const <String, Object?>{
      'registered': true,
      'shortcut': '   ',
    });

    expect(status.shortcut, '⌥⌘Space');
  });
}
