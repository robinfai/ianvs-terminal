import 'profile_models.dart';

/// Boundary adapter for the external iTerm2 Dynamic Profiles interchange
/// format. Its shape is never accepted by the internal persisted document
/// decoder.
final class ITermDynamicProfileImporter {
  const ITermDynamicProfileImporter();

  TerminalProfilesDocument decode(Map<String, Object?> json) {
    final warnings = <TerminalProfileLoadWarning>[];
    final profiles = <TerminalProfile>[];
    final seenIds = <String>{};
    final rawProfiles = json['Profiles'];
    if (rawProfiles is! List) {
      throw const FormatException('iTerm2 Dynamic Profiles requires Profiles.');
    }
    for (
      var index = 0;
      index < rawProfiles.length && profiles.length < maxTerminalProfiles;
      index += 1
    ) {
      final raw = rawProfiles[index];
      if (raw is! Map) {
        continue;
      }
      final mapped = _mapExternalProfile(raw.cast<Object?, Object?>());
      final profile = TerminalProfile.fromJson(
        mapped,
        fallbackId: 'dynamic-profile-${index + 1}',
        loadWarnings: warnings,
      );
      if (seenIds.add(profile.id)) {
        profiles.add(profile);
      }
    }
    return TerminalProfilesDocument(profiles: profiles, loadWarnings: warnings);
  }
}

Map<String, Object?> _mapExternalProfile(Map<Object?, Object?> source) {
  final guid = _text(source['Guid']);
  final name = _text(source['Name']);
  final command = _text(source['Command']);
  final customCommand = _text(source['Custom Command'])?.toLowerCase();
  final cwd = _text(source['Working Directory']);
  final tags = <String>[];
  final rawTags = source['Tags'] ?? source['tags'];
  if (rawTags is List) {
    for (final value in rawTags.take(maxTerminalProfileTags * 4)) {
      final tag = _text(value);
      if (tag != null &&
          !tags.contains(tag) &&
          tags.length < maxTerminalProfileTags - 1) {
        tags.add(tag);
      }
    }
  }
  tags.add('Dynamic');
  final launch = <String, Object?>{
    'program': defaultTerminalProfile().shell,
    'args': const <String>['-l'],
  };
  if (const {'yes', 'true', '1'}.contains(customCommand) && command != null) {
    launch
      ..['program'] = '/bin/sh'
      ..['args'] = <String>['-lc', command];
  }
  if (cwd != null) {
    launch['cwd'] = cwd;
  }
  final tab = _usesTabColor(source['Use Tab Color'])
      ? _color(source['Tab Color'])
      : null;
  final result = <String, Object?>{'tags': tags, 'launch': launch};
  if (guid != null) result['id'] = guid;
  if (name != null) result['name'] = name;
  if (tab != null) {
    result['appearance'] = <String, Object?>{
      'colors': <String, Object?>{
        'special': <String, Object?>{'tab': tab},
      },
    };
  }
  return result;
}

String? _text(Object? value) {
  if (value is! String) return null;
  final result = value.trim();
  return result.isEmpty ? null : result;
}

bool _usesTabColor(Object? value) {
  if (value == null) return true;
  if (value is bool) return value;
  if (value is num && value.isFinite) return value != 0;
  return const {'yes', 'true', '1'}.contains(_text(value)?.toLowerCase());
}

String? _color(Object? value) {
  if (value is String) {
    final normalized = value.trim().toUpperCase();
    return RegExp(r'^#[0-9A-F]{6}$').hasMatch(normalized) ? normalized : null;
  }
  if (value is! Map) return null;
  final red = _component(value['Red Component']);
  final green = _component(value['Green Component']);
  final blue = _component(value['Blue Component']);
  if (red == null || green == null || blue == null) return null;
  String byte(int component) => component.toRadixString(16).padLeft(2, '0');
  return '#${byte(red)}${byte(green)}${byte(blue)}'.toUpperCase();
}

int? _component(Object? value) {
  if (value is! num || !value.isFinite || value < 0 || value > 1) return null;
  return (value * 255).round();
}
