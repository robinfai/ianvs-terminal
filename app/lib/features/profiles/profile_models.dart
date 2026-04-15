import 'dart:convert';

class TerminalProfile {
  const TerminalProfile({
    required this.id,
    required this.name,
    required this.shell,
    this.args = const [],
    this.env = const {},
    this.cwd,
  });

  final String id;
  final String name;
  final String shell;
  final List<String> args;
  final Map<String, String> env;
  final String? cwd;

  TerminalProfile copyWith({
    String? id,
    String? name,
    String? shell,
    List<String>? args,
    Map<String, String>? env,
    String? cwd,
  }) {
    return TerminalProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      shell: shell ?? this.shell,
      args: args ?? this.args,
      env: env ?? this.env,
      cwd: cwd ?? this.cwd,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'shell': shell,
      'args': args,
      'env': env,
      'cwd': cwd,
    };
  }

  static TerminalProfile fromJson(Map<String, Object?> json) {
    return TerminalProfile(
      id: json['id']! as String,
      name: json['name']! as String,
      shell: json['shell']! as String,
      args: (json['args'] as List<dynamic>? ?? const []).cast<String>(),
      env: ((json['env'] as Map<Object?, Object?>?) ?? const {}).map(
        (key, value) => MapEntry(key! as String, value! as String),
      ),
      cwd: json['cwd'] as String?,
    );
  }
}

class TerminalProfilesDocument {
  const TerminalProfilesDocument({
    required this.defaultProfileId,
    required this.profiles,
  });

  final String defaultProfileId;
  final List<TerminalProfile> profiles;

  Map<String, Object?> toJson() {
    return {
      'defaultProfileId': defaultProfileId,
      'profiles': profiles.map((profile) => profile.toJson()).toList(),
    };
  }

  String encode() => jsonEncode(toJson());

  static TerminalProfilesDocument fromJson(Map<String, Object?> json) {
    return TerminalProfilesDocument(
      defaultProfileId: json['defaultProfileId']! as String,
      profiles: (json['profiles']! as List<dynamic>)
          .map(
            (entry) => TerminalProfile.fromJson(entry as Map<String, Object?>),
          )
          .toList(),
    );
  }
}

TerminalProfile defaultTerminalProfile() {
  return TerminalProfile(
    id: 'default',
    name: 'Local Shell',
    shell: const String.fromEnvironment(
      'FLUTTERM_DEFAULT_SHELL',
      defaultValue: '/bin/zsh',
    ),
  );
}
