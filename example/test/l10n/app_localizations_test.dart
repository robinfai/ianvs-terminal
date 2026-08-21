import 'dart:convert';
import 'dart:io';

import 'package:app/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('application localizations', () {
    test('Chinese catalog covers every English message', () {
      final english = _messageKeys('lib/l10n/arb/app_en.arb');
      final chinese = _messageKeys('lib/l10n/arb/app_zh.arb');

      expect(chinese.difference(english), isEmpty);
      expect(english.difference(chinese), isEmpty);
    });

    test('catalogs do not contain duplicate top-level keys', () {
      expect(_duplicateKeys('lib/l10n/arb/app_en.arb'), isEmpty);
      expect(_duplicateKeys('lib/l10n/arb/app_zh.arb'), isEmpty);
    });

    test('generated lookup exposes distinct English and Chinese text', () {
      final english = lookupAppLocalizations(const Locale('en'));
      final chinese = lookupAppLocalizations(const Locale('zh'));

      expect(english.newTab, 'New tab');
      expect(chinese.newTab, '新建标签页');
      expect(english.newTab, isNot(chinese.newTab));
    });
  });
}

Set<String> _messageKeys(String path) {
  final catalog =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return catalog.keys.where((key) => !key.startsWith('@')).toSet();
}

Set<String> _duplicateKeys(String path) {
  final source = File(path).readAsStringSync();
  final seen = <String>{};
  final duplicates = <String>{};
  final keyPattern = RegExp(r'^  "([^"]+)"\s*:', multiLine: true);
  for (final match in keyPattern.allMatches(source)) {
    final key = match.group(1)!;
    if (!seen.add(key)) {
      duplicates.add(key);
    }
  }
  return duplicates;
}
