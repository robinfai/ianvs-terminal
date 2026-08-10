typedef TerminalBackendRequestErrorHandler =
    void Function(
      String sessionId,
      String operation,
      Object error,
      StackTrace stackTrace,
    );
