enum DataApiDeployment { disabled, local, remote }

final class DataApiConfiguration {
  const DataApiConfiguration.disabled()
    : deployment = DataApiDeployment.disabled,
      remoteBaseUri = null;

  const DataApiConfiguration.local()
    : deployment = DataApiDeployment.local,
      remoteBaseUri = null;

  factory DataApiConfiguration.remote(String remoteApiUrl) {
    final configured = remoteApiUrl.trim();
    final uri = Uri.tryParse(configured);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw FormatException(
        'The remote data API URL must be an http(s) base URL without '
        'credentials, query, or fragment.',
        remoteApiUrl,
      );
    }

    final path = uri.path.isEmpty
        ? '/'
        : uri.path.endsWith('/')
        ? uri.path
        : '${uri.path}/';
    return DataApiConfiguration._(
      deployment: DataApiDeployment.remote,
      remoteBaseUri: uri.replace(path: path),
    );
  }

  factory DataApiConfiguration.fromJson(Map<String, Object?> json) {
    if (json['version'] != currentVersion) {
      throw FormatException(
        'Unsupported data API configuration version: ${json['version']}.',
      );
    }
    final deployment = json['deployment'];
    return switch (deployment) {
      'disabled' => const DataApiConfiguration.disabled(),
      'local' => const DataApiConfiguration.local(),
      'remote' => switch (json['remote_base_url']) {
        final String value => DataApiConfiguration.remote(value),
        _ => throw const FormatException(
          'Remote data API configuration requires remote_base_url.',
        ),
      },
      _ => throw FormatException(
        'Unsupported data API deployment: $deployment.',
      ),
    };
  }

  const DataApiConfiguration._({
    required this.deployment,
    required this.remoteBaseUri,
  });

  static const currentVersion = 1;

  final DataApiDeployment deployment;
  final Uri? remoteBaseUri;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DataApiConfiguration &&
            deployment == other.deployment &&
            remoteBaseUri == other.remoteBaseUri;
  }

  @override
  int get hashCode => Object.hash(deployment, remoteBaseUri);

  Map<String, Object?> toJson() => <String, Object?>{
    'version': currentVersion,
    'deployment': deployment.name,
    if (remoteBaseUri != null) 'remote_base_url': remoteBaseUri.toString(),
  };
}
