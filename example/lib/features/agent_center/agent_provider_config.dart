import 'agent_runtime_adapter.dart';

enum AgentProviderSecretBoundary { none, environmentVariable }

class AgentProviderSecretRef {
  const AgentProviderSecretRef.environmentVariable(this.name)
    : boundary = AgentProviderSecretBoundary.environmentVariable;

  final AgentProviderSecretBoundary boundary;
  final String name;

  String get label {
    return switch (boundary) {
      AgentProviderSecretBoundary.none => 'No secret',
      AgentProviderSecretBoundary.environmentVariable => 'Env: $name',
    };
  }
}

class AgentProviderConfig {
  const AgentProviderConfig({
    required this.id,
    required this.label,
    required this.model,
    required this.detail,
    this.secretRef,
  });

  final String id;
  final String label;
  final String model;
  final String detail;
  final AgentProviderSecretRef? secretRef;

  bool get requiresSecret => secretRef != null;

  String get boundaryLabel {
    final secret = secretRef;
    if (secret == null) {
      return 'No provider secret required.';
    }
    return '${secret.label}; secret value stays outside Agent requests.';
  }

  AgentModelConfig toModelConfig() {
    return AgentModelConfig(
      providerId: id,
      providerLabel: label,
      model: model,
      secretBoundary: boundaryLabel,
    );
  }
}

class AgentProviderCatalog {
  const AgentProviderCatalog({required this.providers});

  static const defaults = AgentProviderCatalog(
    providers: <AgentProviderConfig>[
      AgentProviderConfig(
        id: 'local',
        label: 'Local heuristic',
        model: 'local-heuristic',
        detail: 'Local only; no provider secret required.',
      ),
      AgentProviderConfig(
        id: 'agent',
        label: 'Agent draft',
        model: 'deepseek-command-draft',
        detail:
            'Env: DEEPSEEK_API_KEY; secret value stays outside Agent requests.',
        secretRef: AgentProviderSecretRef.environmentVariable(
          'DEEPSEEK_API_KEY',
        ),
      ),
      AgentProviderConfig(
        id: 'shell',
        label: 'Shell strict',
        model: 'shell-strict',
        detail: 'Command-first routing; no provider secret required.',
      ),
    ],
  );

  final List<AgentProviderConfig> providers;

  AgentProviderConfig byLabel(String label) {
    final trimmed = label.trim();
    for (final provider in providers) {
      if (provider.label == trimmed) {
        return provider;
      }
    }
    return providers.first;
  }
}
