import 'package:app/features/shell/shell_action_error_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Shell action error diagnostics', () {
    test('returns null when no external error exists', () {
      expect(
        ShellActionErrorDiagnostics.fromExternalExecutorError(null),
        isNull,
      );
    });

    test('formats external executor errors for UI', () {
      final diagnostic = ShellActionErrorDiagnostics.fromExternalExecutorError(
        StateError('paste failed'),
      );

      expect(diagnostic, isNotNull);
      expect(diagnostic!.title, 'Action side effect failed');
      expect(diagnostic.description, contains('paste failed'));
    });
  });
}
