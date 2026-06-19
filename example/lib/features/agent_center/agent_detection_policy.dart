enum AgentAmbiguousInputBehavior { requireChoice, preferShell, preferAgent }

class AgentDetectionPolicy {
  const AgentDetectionPolicy({
    this.shellPrefix = '!',
    this.agentPrefix = '?',
    this.actionPrefix = '/',
    this.enabled = true,
    this.naturalLanguageAutoDetectionEnabled = true,
    this.directRouteThreshold = 0.85,
    this.ambiguousRouteThreshold = 0.55,
    this.ambiguousInputBehavior = AgentAmbiguousInputBehavior.requireChoice,
  });

  const AgentDetectionPolicy.disabled()
    : this(enabled: false, naturalLanguageAutoDetectionEnabled: false);

  final String shellPrefix;
  final String agentPrefix;
  final String actionPrefix;
  final bool enabled;
  final bool naturalLanguageAutoDetectionEnabled;
  final double directRouteThreshold;
  final double ambiguousRouteThreshold;
  final AgentAmbiguousInputBehavior ambiguousInputBehavior;

  AgentDetectionPolicy copyWith({
    String? shellPrefix,
    String? agentPrefix,
    String? actionPrefix,
    bool? enabled,
    bool? naturalLanguageAutoDetectionEnabled,
    double? directRouteThreshold,
    double? ambiguousRouteThreshold,
    AgentAmbiguousInputBehavior? ambiguousInputBehavior,
  }) {
    return AgentDetectionPolicy(
      shellPrefix: shellPrefix ?? this.shellPrefix,
      agentPrefix: agentPrefix ?? this.agentPrefix,
      actionPrefix: actionPrefix ?? this.actionPrefix,
      enabled: enabled ?? this.enabled,
      naturalLanguageAutoDetectionEnabled:
          naturalLanguageAutoDetectionEnabled ??
          this.naturalLanguageAutoDetectionEnabled,
      directRouteThreshold: directRouteThreshold ?? this.directRouteThreshold,
      ambiguousRouteThreshold:
          ambiguousRouteThreshold ?? this.ambiguousRouteThreshold,
      ambiguousInputBehavior:
          ambiguousInputBehavior ?? this.ambiguousInputBehavior,
    );
  }
}
