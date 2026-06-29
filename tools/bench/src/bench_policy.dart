enum BenchFramePolicy {
  snapshotOnly('snapshot_only'),
  deltaNoCoalesce('delta_no_coalesce'),
  deltaCoalesced('delta_coalesced');

  const BenchFramePolicy(this.wireName);

  final String wireName;

  static BenchFramePolicy parse(String value) {
    final normalized = value.trim();
    for (final policy in values) {
      if (policy.wireName == normalized) {
        return policy;
      }
    }
    throw FormatException('Unknown frame policy: $value');
  }
}

enum BenchRenderPolicy {
  normalRender('normal_render'),
  headlessStateOnly('headless_state_only');

  const BenchRenderPolicy(this.wireName);

  final String wireName;

  static BenchRenderPolicy parse(String value) {
    final normalized = value.trim();
    for (final policy in values) {
      if (policy.wireName == normalized) {
        return policy;
      }
    }
    throw FormatException('Unknown render policy: $value');
  }
}
