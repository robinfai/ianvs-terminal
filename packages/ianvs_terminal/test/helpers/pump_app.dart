import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

extension PumpApp on WidgetTester {
  Future<void> pumpApp(Widget child, {ThemeData? theme}) =>
      pumpWidget(MaterialApp(theme: theme, home: child));
}
