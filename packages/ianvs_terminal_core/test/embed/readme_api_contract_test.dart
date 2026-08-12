import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('README Dart style snippet uses the published constructor API', () {
    final readme = File('README.md').readAsStringSync();
    final styleSource = File(
      'lib/src/embed/terminal_bottom_panel.dart',
    ).readAsStringSync();

    expect(_readmeStyleViolations(readme, styleSource), isEmpty);

    for (final staleName in <String>[
      'panelBackgroundColor',
      'tabBarBackgroundColor',
      'activeTabIndicatorColor',
    ]) {
      final mutation = readme.replaceFirst('backgroundColor', staleName);
      expect(
        _readmeStyleViolations(mutation, styleSource),
        isNotEmpty,
        reason: 'stale public parameter $staleName must fail the gate',
      );
    }
  });
}

List<String> _readmeStyleViolations(String readme, String styleSource) {
  final violations = <String>[];
  final dartSnippets = RegExp(
    r'```dart\s*\n([\s\S]*?)```',
  ).allMatches(readme).map((match) => match.group(1)!).toList(growable: false);
  if (dartSnippets.length < 2) {
    return <String>['README must retain its fenced Dart examples'];
  }

  final styleSnippet = dartSnippets.where(
    (snippet) => snippet.contains('TerminalBottomPanelStyle('),
  );
  if (styleSnippet.length != 1) {
    return <String>['README must have exactly one panel style example'];
  }
  final call = RegExp(
    r'TerminalBottomPanelStyle\(([\s\S]*?)\n\s*\)',
  ).firstMatch(styleSnippet.single);
  if (call == null) {
    return <String>['README panel style call is not parseable'];
  }
  final arguments = RegExp(
    r'^\s*([A-Za-z][A-Za-z0-9_]*):',
    multiLine: true,
  ).allMatches(call.group(1)!).map((match) => match.group(1)!).toSet();

  final constructor = RegExp(
    r'const TerminalBottomPanelStyle\(\{([\s\S]*?)\n\s*\}\);',
  ).firstMatch(styleSource);
  if (constructor == null) {
    return <String>['TerminalBottomPanelStyle constructor is not parseable'];
  }
  final parameters = RegExp(
    r'this\.([A-Za-z][A-Za-z0-9_]*)',
  ).allMatches(constructor.group(1)!).map((match) => match.group(1)!).toSet();
  for (final argument in arguments.difference(parameters)) {
    violations.add('README uses unknown TerminalBottomPanelStyle.$argument');
  }
  for (final requiredExample in <String>{
    'backgroundColor',
    'headerColor',
    'activeTabColor',
  }.difference(arguments)) {
    violations.add('README omits current style example $requiredExample');
  }
  return violations;
}
