import 'local_terminal_visual_models.dart';

class LocalTerminalGraphicsEntry {
  const LocalTerminalGraphicsEntry({
    required this.id,
    required this.bytes,
    required this.createdAtMillis,
  });

  final String id;
  final int bytes;
  final int createdAtMillis;

  bool get isValid => id.trim().isNotEmpty && bytes > 0;
}

class LocalTerminalGraphicsEvictionPlan {
  const LocalTerminalGraphicsEvictionPlan({
    required this.accepted,
    this.rejectedReason,
    this.evictIds = const <String>[],
  });

  final bool accepted;
  final String? rejectedReason;
  final List<String> evictIds;
}

class LocalTerminalGraphicsStorePlanner {
  const LocalTerminalGraphicsStorePlanner._();

  static LocalTerminalGraphicsEvictionPlan planInsert({
    required LocalTerminalGraphicsStoragePolicy policy,
    required List<LocalTerminalGraphicsEntry> existing,
    required LocalTerminalGraphicsEntry next,
  }) {
    if (!policy.enabled) {
      return const LocalTerminalGraphicsEvictionPlan(
        accepted: false,
        rejectedReason: 'Graphics storage is disabled.',
      );
    }
    if (!next.isValid || next.bytes > policy.maxBytes) {
      return const LocalTerminalGraphicsEvictionPlan(
        accepted: false,
        rejectedReason: 'Image exceeds graphics storage limits.',
      );
    }

    final validExisting = existing
        .where((entry) => entry.isValid)
        .toList(growable: false);
    final total = validExisting.fold<int>(0, (sum, entry) => sum + entry.bytes);
    final projected = total + next.bytes;
    if (projected <= policy.maxBytes) {
      return const LocalTerminalGraphicsEvictionPlan(accepted: true);
    }
    if (!policy.evictWhenExceeded) {
      return const LocalTerminalGraphicsEvictionPlan(
        accepted: false,
        rejectedReason: 'Graphics storage is full.',
      );
    }

    final sorted = [...validExisting]
      ..sort((a, b) => a.createdAtMillis.compareTo(b.createdAtMillis));
    var remainingTotal = total;
    final evictIds = <String>[];
    for (final entry in sorted) {
      if (remainingTotal + next.bytes <= policy.maxBytes) {
        break;
      }
      remainingTotal -= entry.bytes;
      evictIds.add(entry.id);
    }

    return LocalTerminalGraphicsEvictionPlan(
      accepted: remainingTotal + next.bytes <= policy.maxBytes,
      evictIds: evictIds,
      rejectedReason: remainingTotal + next.bytes <= policy.maxBytes
          ? null
          : 'Graphics storage is full.',
    );
  }
}
