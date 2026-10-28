import 'dart:async';

import 'package:app/features/ai/ai_models.dart';
import 'package:app/features/ai/ai_settings.dart';
import 'package:app/features/preferences/app_preferences_models.dart';
import 'package:app/features/sessions/session_state.dart';
import 'package:app/features/terminal_composer/composer_pane.dart';
import 'package:app/features/terminal_composer/terminal_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'terminal_ai_test.dart' show MemoryAiStore;

class _DelayedStore extends MemoryAiStore {
  final completion = Completer<AiConfiguration?>();
  @override
  Future<AiConfiguration?> read() => completion.future;
}

class _Runtime extends Fake implements TerminalRuntimeController {
  @override
  CommandOccurrenceScope? commandOccurrenceScopeFor(String sessionId) => null;

  @override
  Map<String, Object?>? composerRequest(
    String id,
    String operation,
    Map<String, Object?> payload,
  ) => operation == 'composer.state'
      ? {
          'state': 'ready',
          'lease': 'lease',
          'transport': 'shell',
          'contextId': 'root',
        }
      : null;
  @override
  Map<String, Object?>? commandBlocks(
    String id, [
    Map<String, Object?> payload = const {},
  ]) => {'blocks': <Object?>[]};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final configuration in <AiConfiguration?>[
    null,
    const AiConfiguration(endpoint: 'invalid', apiKey: 'key', model: 'model'),
    const AiConfiguration(
      endpoint: 'https://llm.example',
      apiKey: '',
      model: 'model',
    ),
    const AiConfiguration.acp(agentCommand: '/agent'),
    const AiConfiguration.mock(),
  ]) {
    test(
      'only a valid saved LLM unlocks mobile Blocks: ${configuration?.backend} ${configuration?.endpoint}',
      () async {
        final settings = AiSettingsController(MemoryAiStore(configuration));
        addTearDown(settings.dispose);
        await settings.loaded;
        expect(
          settings.hasLlmConfiguration,
          configuration?.model == 'trail-mock',
        );
      },
    );
  }
  for (final preferred in TerminalViewMode.values) {
    test('delayed LLM loading preserves saved preference $preferred', () async {
      final store = _DelayedStore();
      final settings = AiSettingsController(store);
      final session = ComposerPaneSession(
        sessionId: 'one',
        runtime: _Runtime(),
        mobileAiSettings: settings,
        preferredMode: preferred,
      );
      session.updateEnvironment(
        const TerminalPane(sessionId: 'one', title: 'one', profileId: 'one'),
        readOnly: false,
      );
      session.refreshShellState();
      expect(session.enabled, false);
      expect(
        session.mode.state.unavailableReason,
        BlockUnavailableReason.llmRequired,
      );
      expect(session.selectMode(TerminalViewMode.blocks), false);
      store.completion.complete(const AiConfiguration.mock());
      await settings.loaded;
      expect(session.mode.state.mode, preferred);
      session.controller.editor.text = 'retained';
      await settings.save(null);
      session.refreshShellState(recheckSupport: true);
      expect(session.enabled, false);
      expect(session.selectMode(TerminalViewMode.blocks), false);
      expect(session.controller.editor.text, 'retained');
      session.dispose();
      settings.dispose();
    });
  }
  test('unreadable storage leaves mobile restricted to Normal', () async {
    final store = _DelayedStore();
    final settings = AiSettingsController(store);
    addTearDown(settings.dispose);
    store.completion.completeError(StateError('storage unavailable'));
    await settings.loaded;
    expect(settings.hasLlmConfiguration, false);
    expect(settings.error, 'storage');
  });
}
