import 'package:app/features/agent_center/agent_center.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentProviderCatalog', () {
    test('resolves the Agent draft provider with an environment boundary', () {
      final provider = AgentProviderCatalog.defaults.byLabel('Agent draft');

      expect(provider.id, 'agent');
      expect(provider.label, 'Agent draft');
      expect(provider.model, 'deepseek-command-draft');
      expect(provider.requiresSecret, isTrue);
      expect(provider.secretRef?.name, 'DEEPSEEK_API_KEY');
      expect(
        provider.boundaryLabel,
        'Env: DEEPSEEK_API_KEY; secret value stays outside Agent requests.',
      );
      expect(provider.detail, provider.boundaryLabel);

      final modelConfig = provider.toModelConfig();

      expect(modelConfig.providerId, 'agent');
      expect(modelConfig.providerLabel, 'Agent draft');
      expect(modelConfig.model, 'deepseek-command-draft');
      expect(modelConfig.secretBoundary, provider.boundaryLabel);
    });

    test('falls back to local provider for unknown labels', () {
      final provider = AgentProviderCatalog.defaults.byLabel('unknown');

      expect(provider.id, 'local');
      expect(provider.requiresSecret, isFalse);
      expect(provider.boundaryLabel, 'No provider secret required.');
      expect(provider.toModelConfig().secretBoundary, provider.boundaryLabel);
    });
  });
}
