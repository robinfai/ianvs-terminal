import 'dart:io';

enum DataApiDeployment { disabled, local, remote }

bool isSecureDataApiRemoteOrigin(Uri uri) {
  final parsedAddress = InternetAddress.tryParse(uri.host);
  final isLoopback =
      uri.host.toLowerCase() == 'localhost' ||
      parsedAddress?.isLoopback == true;
  return uri.scheme == 'https' || (uri.scheme == 'http' && isLoopback);
}

final class DataApiConfiguration {
  const DataApiConfiguration.disabled()
    : deployment = DataApiDeployment.disabled,
      remoteBaseUri = null,
      generation = 0,
      remoteCredentialRef = null,
      lastTransactionId = null;

  const DataApiConfiguration.local()
    : deployment = DataApiDeployment.local,
      remoteBaseUri = null,
      generation = 0,
      remoteCredentialRef = null,
      lastTransactionId = null;

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
    if (!isSecureDataApiRemoteOrigin(uri)) {
      throw FormatException(
        'Remote data API authentication requires HTTPS. HTTP is allowed only '
        'for a loopback development endpoint.',
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
      generation: 0,
      remoteCredentialRef: null,
      lastTransactionId: null,
    );
  }

  factory DataApiConfiguration.fromJson(Map<String, Object?> json) {
    const allowedKeys = <String>{
      'version',
      'deployment',
      'generation',
      'remote_base_url',
      'remote_credential_ref',
      'last_transaction_id',
    };
    if (json.keys.any((key) => !allowedKeys.contains(key))) {
      throw const FormatException(
        'Data API configuration contains an unsupported field.',
      );
    }
    final version = json['version'];
    if (version != currentVersion) {
      throw DataApiConfigurationUnsupportedVersionException(version: version);
    }
    final generation = json['generation'];
    if (generation is! int || generation < 0) {
      throw const FormatException(
        'Data API configuration generation is invalid.',
      );
    }
    final credentialRef = json['remote_credential_ref'];
    if (credentialRef != null &&
        (credentialRef is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(credentialRef))) {
      throw const FormatException(
        'Data API remote credential reference is invalid.',
      );
    }
    final transactionId = json['last_transaction_id'];
    if (transactionId != null && !_isPersistenceId(transactionId)) {
      throw const FormatException(
        'Data API configuration transaction identifier is invalid.',
      );
    }
    final deployment = json['deployment'];
    final configuration = switch (deployment) {
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
    if (configuration.deployment != DataApiDeployment.remote &&
        (credentialRef != null || json.containsKey('remote_base_url'))) {
      throw const FormatException(
        'Only remote Data API configuration may contain remote fields.',
      );
    }
    return configuration.withPersistenceState(
      generation: generation,
      remoteCredentialRef: credentialRef as String?,
      lastTransactionId: transactionId as String?,
    );
  }

  const DataApiConfiguration._({
    required this.deployment,
    required this.remoteBaseUri,
    required this.generation,
    required this.remoteCredentialRef,
    required this.lastTransactionId,
  });

  /// The sole configuration schema shipped by the unreleased product.
  ///
  /// This version belongs only to the configuration document; secure session
  /// slots and saga journals version their own independent formats.
  static const currentVersion = 1;

  final DataApiDeployment deployment;
  final Uri? remoteBaseUri;
  final int generation;
  final String? remoteCredentialRef;
  final String? lastTransactionId;

  DataApiConfiguration withPersistenceState({
    required int generation,
    required String? remoteCredentialRef,
    required String? lastTransactionId,
  }) {
    if (generation < 0 ||
        (lastTransactionId != null && !_isPersistenceId(lastTransactionId)) ||
        (deployment != DataApiDeployment.remote &&
            remoteCredentialRef != null)) {
      throw ArgumentError('Invalid Data API persistence state.');
    }
    return DataApiConfiguration._(
      deployment: deployment,
      remoteBaseUri: remoteBaseUri,
      generation: generation,
      remoteCredentialRef: remoteCredentialRef,
      lastTransactionId: lastTransactionId,
    );
  }

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
    'generation': generation,
    if (remoteBaseUri != null) 'remote_base_url': remoteBaseUri.toString(),
    if (remoteCredentialRef != null)
      'remote_credential_ref': remoteCredentialRef,
    if (lastTransactionId != null) 'last_transaction_id': lastTransactionId,
  };
}

final class DataApiConfigurationUnsupportedVersionException
    implements Exception {
  const DataApiConfigurationUnsupportedVersionException({
    required this.version,
  });

  final Object? version;

  @override
  String toString() {
    return 'Unsupported Data API configuration version: $version. The '
        'original configuration was preserved.';
  }
}

bool _isPersistenceId(Object? value) {
  return value is String && RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(value);
}
