import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../profiles/profile_models.dart';

/// Product policy for the kinds of terminal sessions a platform may launch.
///
/// iOS intentionally exposes only remote SSH sessions. The policy lives
/// outside the widget tree so startup, layout recovery, command actions, and
/// direct controller calls all enforce the same boundary.
final class TerminalSessionLaunchPolicy {
  const TerminalSessionLaunchPolicy({required this.localSessionsEnabled});

  const TerminalSessionLaunchPolicy.sshOnly() : localSessionsEnabled = false;

  const TerminalSessionLaunchPolicy.localAndSsh() : localSessionsEnabled = true;

  factory TerminalSessionLaunchPolicy.forPlatform(TargetPlatform platform) {
    return platform == TargetPlatform.iOS
        ? const TerminalSessionLaunchPolicy.sshOnly()
        : const TerminalSessionLaunchPolicy.localAndSsh();
  }

  final bool localSessionsEnabled;

  bool get isSshOnly => !localSessionsEnabled;

  bool allows(TerminalProfile profile) {
    return localSessionsEnabled || profile.isSsh;
  }

  List<TerminalProfile> visibleProfiles(Iterable<TerminalProfile> profiles) {
    return List<TerminalProfile>.unmodifiable(profiles.where(allows));
  }

  /// SSH-only platforms wait for an explicit profile choice on an empty
  /// layout instead of opening any default session automatically.
  bool get opensDefaultSessionOnEmptyLayout => localSessionsEnabled;
}

final terminalSessionLaunchPolicyProvider =
    Provider<TerminalSessionLaunchPolicy>((ref) {
      return TerminalSessionLaunchPolicy.forPlatform(defaultTargetPlatform);
    });
