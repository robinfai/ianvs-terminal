import 'package:flutter_riverpod/flutter_riverpod.dart';

/// User-managed SSH profiles are persisted locally on every supported platform.
/// A Data API may additionally synchronize them, but it is not a prerequisite
/// for creating, editing, or opening a saved profile.
final customSshProfileConfigurationEnabledProvider = Provider<bool>(
  (ref) => true,
);

/// Defensive error for callers that explicitly override SSH profile support.
/// Production enables local SSH profile persistence independently of Data API.
final class CustomSshProfileConfigurationUnavailableException
    implements Exception {
  const CustomSshProfileConfigurationUnavailableException();

  @override
  String toString() => 'Custom SSH profile configuration is unavailable.';
}
