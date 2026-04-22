import 'dart:convert';

enum TerminalEmulation { xterm256, vt220 }

class TerminalProfile {
  const TerminalProfile({
    required this.id,
    required this.name,
    required this.shell,
    this.args = const [],
    this.env = const {},
    this.cwd,
    this.terminalEmulation = TerminalEmulation.xterm256,
  });

  final String id;
  final String name;
  final String shell;
  final List<String> args;
  final Map<String, String> env;
  final String? cwd;
  final TerminalEmulation terminalEmulation;

  TerminalProfile copyWith({
    String? id,
    String? name,
    String? shell,
    List<String>? args,
    Map<String, String>? env,
    String? cwd,
    TerminalEmulation? terminalEmulation,
  }) {
    return TerminalProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      shell: shell ?? this.shell,
      args: args ?? this.args,
      env: env ?? this.env,
      cwd: cwd ?? this.cwd,
      terminalEmulation: terminalEmulation ?? this.terminalEmulation,
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
      'terminalEmulation': terminalEmulation.name,
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
      terminalEmulation: _terminalEmulationFromJson(json['terminalEmulation']),
    );
  }
}

class TerminalProfilesDocument {
  const TerminalProfilesDocument({required this.profiles});

  final List<TerminalProfile> profiles;

  Map<String, Object?> toJson() {
    return {'profiles': profiles.map((profile) => profile.toJson()).toList()};
  }

  String encode() => jsonEncode(toJson());

  static TerminalProfilesDocument fromJson(Map<String, Object?> json) {
    return TerminalProfilesDocument(
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

TerminalProfile vt220TerminalProfile() {
  return TerminalProfile(
    id: 'vt220',
    name: 'Strict VT220',
    shell: const String.fromEnvironment(
      'FLUTTERM_DEFAULT_SHELL',
      defaultValue: '/bin/zsh',
    ),
    terminalEmulation: TerminalEmulation.vt220,
  );
}

TerminalEmulation _terminalEmulationFromJson(Object? raw) {
  return switch (raw) {
    'vt220' => TerminalEmulation.vt220,
    _ => TerminalEmulation.xterm256,
  };
}
