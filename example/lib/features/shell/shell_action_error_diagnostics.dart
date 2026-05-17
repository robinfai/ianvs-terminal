class ShellActionErrorDiagnostic {
  const ShellActionErrorDiagnostic({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;
}

class ShellActionErrorDiagnostics {
  const ShellActionErrorDiagnostics._();

  static ShellActionErrorDiagnostic? fromExternalExecutorError(Object? error) {
    if (error == null) {
      return null;
    }

    return ShellActionErrorDiagnostic(
      title: 'Action side effect failed',
      description: error.toString(),
    );
  }
}
