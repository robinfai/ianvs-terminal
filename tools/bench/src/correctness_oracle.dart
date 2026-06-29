import 'bench_policy.dart';
import 'replay_terminal.dart';

final class CorrectnessOracle {
  const CorrectnessOracle._();

  static Map<String, Object?> compare({
    required BenchRunData reference,
    required BenchRunData tested,
  }) {
    final hashMatch = reference.finalViewportHash == tested.finalViewportHash;
    return <String, Object?>{
      'schema_version': 'ianvs-bench-correctness-v1',
      'workload': tested.workload,
      'reference_policy': reference.framePolicy.wireName,
      'tested_policy': tested.framePolicy.wireName,
      'reference_final_viewport_hash': reference.finalViewportHash,
      'tested_final_viewport_hash': tested.finalViewportHash,
      'hash_match': hashMatch,
      'first_divergence': hashMatch
          ? null
          : _firstDivergence(reference: reference, tested: tested),
    };
  }
}

Map<String, Object?> _firstDivergence({
  required BenchRunData reference,
  required BenchRunData tested,
}) {
  final byGeneration = <int, Map<String, Object?>>{};
  for (final event in reference.rustFrameEvents) {
    final generation = _intValue(event['semantic_generation']);
    if (generation != null) {
      byGeneration[generation] = event;
    }
  }
  for (final event in tested.rustFrameEvents) {
    final generation = _intValue(event['semantic_generation']);
    final referenceEvent = generation == null ? null : byGeneration[generation];
    final testedHash = event['viewport_hash']?.toString();
    final referenceHash = referenceEvent?['viewport_hash']?.toString();
    if (referenceHash != null &&
        testedHash != null &&
        referenceHash != testedHash) {
      return _diagnosticEvent(event, referenceHash: referenceHash);
    }
  }
  final last = tested.rustFrameEvents.isEmpty
      ? const <String, Object?>{}
      : tested.rustFrameEvents.last;
  return _diagnosticEvent(last, referenceHash: reference.finalViewportHash);
}

Map<String, Object?> _diagnosticEvent(
  Map<String, Object?> event, {
  required String referenceHash,
}) {
  return <String, Object?>{
    'frame_id': event['frame_id'],
    'semantic_generation': event['semantic_generation'],
    'reference_hash': referenceHash,
    'tested_hash': event['viewport_hash'],
    'frame_kind':
        event['frame_kind'] ?? BenchFramePolicy.deltaCoalesced.wireName,
    'snapshot_fallback_reason': event['snapshot_fallback_reason'],
    'viewport_row_shift': event['viewport_row_shift'],
    'rows_emitted': event['rows_emitted'],
  };
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}
