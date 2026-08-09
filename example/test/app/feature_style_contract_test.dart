import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feature ui keeps inline Color literals out of business widgets', () {
    final projectRoot = _projectRoot();
    final featuresDir = Directory('${projectRoot.path}/example/lib/features');
    const allowedFiles = <String>{
      'example/lib/features/shell/reference_demo.dart',
    };

    final violations = <String>[];
    final inlineColorPattern = RegExp(r'\bColor\(');

    for (final entity in featuresDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final relativePath = entity.path.replaceFirst('${projectRoot.path}/', '');
      if (allowedFiles.contains(relativePath)) {
        continue;
      }
      final content = entity.readAsStringSync();
      if (inlineColorPattern.hasMatch(content)) {
        violations.add(relativePath);
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Inline Color(...) literals should stay in the UI foundation layer,'
          ' except for approved demo fixtures.',
    );
  });

  test('form dropdowns use the shared app control', () {
    final projectRoot = _projectRoot();
    final libDir = Directory('${projectRoot.path}/example/lib');
    const sharedControl =
        'example/lib/ui/components/app_dropdown_form_field.dart';
    final violations = <String>[];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final relativePath = entity.path.replaceFirst('${projectRoot.path}/', '');
      if (relativePath == sharedControl) {
        continue;
      }
      if (entity.readAsStringSync().contains('DropdownButtonFormField<')) {
        violations.add(relativePath);
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Use AppDropdownFormField so form dropdowns share text metrics and '
          'height behavior with TextField.',
    );
  });
}

Directory _projectRoot() {
  final current = Directory.current;
  if (Directory('${current.path}/example/lib/features').existsSync()) {
    return current;
  }
  if (Directory('${current.path}/lib/features').existsSync()) {
    return current.parent;
  }
  return current;
}
