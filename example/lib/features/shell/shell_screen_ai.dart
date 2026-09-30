part of 'shell_screen.dart';

extension _ShellScreenAi on _ShellScreenState {
  TerminalAiController _aiFor(String sessionId) => _aiSessions.putIfAbsent(
    sessionId,
    () => TerminalAiController(
      settings: ref.read(aiSettingsProvider),
      terminal: TerminalAiRuntime(
        sessionId: sessionId,
        runtime: ref.read(terminalRuntimeControllerProvider),
        readPane: () =>
            _paneForSession(ref.read(sessionControllerProvider), sessionId),
        isReadOnly: () => _isSessionReadOnly(sessionId),
      ),
    ),
  );

  void _openAi(
    String sessionId, {
    String? prompt,
    terminal.CommandBlock? block,
  }) {
    final ai = _aiFor(sessionId);
    _mutateState(() => _openAiSessions.add(sessionId));
    unawaited(() async {
      await ai.refreshContext();
      if (!mounted) return;
      if (prompt == null && block == null) return;
      await ai.settings.loaded;
      if (!mounted) return;
      if (ai.settings.configuration == null) {
        await showAiSettings(context, ai.settings);
        if (!mounted || ai.settings.configuration == null) return;
      }
      if (!_openAiSessions.contains(sessionId)) return;
      final runtime = ai.terminal as TerminalAiRuntime;
      final selected = block == null ? null : runtime.blockContext(block);
      final query =
          prompt ??
          (block?.exitCode != null && block!.exitCode != 0
              ? '请解释这条命令失败的原因并提出修正。Explain and correct this failed command.'
              : '请解释这个命令块。Explain this command block.');
      unawaited(ai.ask(query, block: selected));
      final composer = _composerSessions[sessionId]?.controller;
      if (prompt != null && composer?.editor.text == prompt) {
        composer?.clearDraft();
      }
    }());
  }

  void _closeAi(String sessionId) {
    _aiSessions[sessionId]?.takeOver();
    _mutateState(() => _openAiSessions.remove(sessionId));
    _focusSession(sessionId);
  }

  Widget _aiOverlay(String sessionId, Size available, AppThemeTokens palette) {
    if (_openAiSessions.contains(sessionId)) {
      return Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: math.min(460.0, math.max(0.0, available.width - 16)),
            height: math
                .min(520.0, math.max(180.0, available.height * .72))
                .clamp(0.0, math.max(0.0, available.height - 16)),
            child: TerminalAiPanel(
              controller: _aiFor(sessionId),
              onClose: () => _closeAi(sessionId),
            ),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: TextButton(
          key: Key('terminal-ai-open-$sessionId'),
          style: TextButton.styleFrom(
            backgroundColor: palette.panel,
            foregroundColor: palette.textMuted,
            minimumSize: const Size(44, 44),
          ),
          onPressed: () => _openAi(sessionId),
          child: const Text('AI'),
        ),
      ),
    );
  }
}
