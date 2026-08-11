import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _httpMethods = <String>{'get', 'post', 'put', 'patch', 'delete'};
const _schemaTypes = <String>{
  'array',
  'boolean',
  'integer',
  'number',
  'object',
  'string',
};
const _securitySchemeTypes = <String>{
  'apiKey',
  'http',
  'mutualTLS',
  'oauth2',
  'openIdConnect',
};

void main() {
  test(
    'OpenAPI document is valid YAML with resolvable component contracts',
    () {
      final source = File('backend/openapi.yaml').readAsStringSync();
      final Object? parsed = loadYaml(source);
      expect(parsed, isA<YamlMap>());
      final document = parsed! as YamlMap;

      expect(document['openapi'], isA<String>());
      expect((document['openapi']! as String).startsWith('3.1.'), isTrue);
      final info = _expectMap(document, 'info');
      final keyContract = _expectMap(info, 'x-ianvs-encryption-key-contract');
      expect(keyContract['version'], 1);
      expect(keyContract['rotation_supported'], isFalse);
      expect(info['x-ianvs-json-response-limit-bytes'], 12 * 1024 * 1024);
      expect(info['x-ianvs-json-request-limit-bytes'], 12 * 1024 * 1024);
      final paths = _expectMap(document, 'paths');
      final components = _expectMap(document, 'components');
      final schemas = _expectMap(components, 'schemas');
      _expectMap(components, 'responses');
      final parameters = _expectMap(components, 'parameters');
      _expectMap(components, 'securitySchemes');
      expect(
        (parameters['PageCursor']! as YamlMap)['description'],
        allOf(
          contains('server-signed'),
          contains('database-owned UTC creation cutoff'),
        ),
      );

      final resourceWrite = schemas['ResourceWrite']! as YamlMap;
      final writeProperties = resourceWrite['properties']! as YamlMap;
      final expectedRevision = writeProperties['expected_revision']! as YamlMap;
      expect(expectedRevision['minimum'], 0);
      expect(
        expectedRevision['description'],
        contains('Zero creates only when absent'),
      );

      final resourcePage = schemas['ResourcePage']! as YamlMap;
      final resourcePageProperties = resourcePage['properties']! as YamlMap;
      final pageResources = resourcePageProperties['resources']! as YamlMap;
      expect(pageResources['maxItems'], 100);
      expect(resourcePageProperties, contains('next_cursor'));
      final migrationBundle = schemas['MigrationBundle']! as YamlMap;
      final migrationProperties = migrationBundle['properties']! as YamlMap;
      expect((migrationProperties['resources']! as YamlMap)['maxItems'], 100);
      expect(migrationProperties, contains('next_cursor'));

      for (final path in <String>['/v1/resources', '/v1/migrations/export']) {
        final operation = (paths[path]! as YamlMap)['get']! as YamlMap;
        expect(
          _parameterReferences(operation),
          containsAll(<String>[
            '#/components/parameters/PageLimit',
            '#/components/parameters/PageCursor',
          ]),
          reason: path,
        );
      }
      final resourceGet =
          (paths['/v1/resources/{kind}/{id}']! as YamlMap)['get']! as YamlMap;
      expect(
        _parameterReferences(resourceGet),
        isNot(contains('#/components/parameters/PageCursor')),
      );

      final encryptionKeyRequest = schemas['EncryptionKeyRequest']! as YamlMap;
      final encryptionKeyProperties =
          encryptionKeyRequest['properties']! as YamlMap;
      final encryptionKey =
          encryptionKeyProperties['encryption_key']! as YamlMap;
      expect(encryptionKey['x-ianvs-min-utf8-bytes'], 16);
      expect(encryptionKey['x-ianvs-max-utf8-bytes'], 1024);

      final user = schemas['User']! as YamlMap;
      expect(
        user['required'],
        containsAll(<String>['key_contract_version', 'key_rotation_supported']),
      );
      final userProperties = user['properties']! as YamlMap;
      expect((userProperties['key_contract_version']! as YamlMap)['const'], 1);
      expect(
        (userProperties['key_rotation_supported']! as YamlMap)['const'],
        isFalse,
      );

      final verifyKey =
          (paths['/v1/auth/verify-key']! as YamlMap)['post']! as YamlMap;
      final verifyResponses = verifyKey['responses']! as YamlMap;
      expect(
        verifyResponses.keys.map((key) => key.toString()),
        containsAll(<String>['400', '401', '428', '429']),
      );
      final exactErrors = <String, String>{
        'InvalidEncryptionKeyError': 'invalid_encryption_key',
        'EncryptionKeyRequiredError': 'encryption_key_required',
        'EncryptionKeyTooLongError': 'encryption_key_too_long',
        'KeyDerivationBusyError': 'key_derivation_busy',
      };
      for (final entry in exactErrors.entries) {
        final envelope = schemas[entry.key]! as YamlMap;
        final envelopeProperties = envelope['properties']! as YamlMap;
        final error = envelopeProperties['error']! as YamlMap;
        final errorProperties = error['properties']! as YamlMap;
        expect(
          (errorProperties['code']! as YamlMap)['const'],
          entry.value,
          reason: entry.key,
        );
      }

      for (final MapEntry<Object?, Object?> entry in paths.entries) {
        expect(entry.key, isA<String>());
        expect((entry.key! as String).startsWith('/'), isTrue);
        expect(entry.value, isA<YamlMap>(), reason: 'path ${entry.key}');
        final pathItem = entry.value! as YamlMap;
        for (final method in _httpMethods.where(pathItem.containsKey)) {
          final operation = pathItem[method];
          expect(operation, isA<YamlMap>(), reason: '$method ${entry.key}');
          final operationMap = operation! as YamlMap;
          expect(
            operationMap['operationId'],
            isA<String>(),
            reason: '$method ${entry.key} operationId',
          );
          final responses = _expectMap(operationMap, 'responses');
          expect(
            responses,
            isNotEmpty,
            reason: '$method ${entry.key} responses',
          );
          for (final status in responses.keys) {
            expect(
              status.toString(),
              anyOf('default', matches(RegExp(r'^[1-5][0-9]{2}$'))),
              reason: '$method ${entry.key} response status',
            );
          }
        }
      }

      _visit(document, r'$', document);
    },
  );
}

Set<String> _parameterReferences(YamlMap operation) {
  final parameters = operation['parameters']! as YamlList;
  return parameters
      .whereType<YamlMap>()
      .map((parameter) => parameter[r'$ref'])
      .whereType<String>()
      .toSet();
}

YamlMap _expectMap(YamlMap owner, String key) {
  final value = owner[key];
  expect(value, isA<YamlMap>(), reason: '$key must be a map');
  return value! as YamlMap;
}

void _visit(Object? value, String location, YamlMap document) {
  if (value is YamlMap) {
    final reference = value[r'$ref'];
    if (reference != null) {
      expect(reference, isA<String>(), reason: '$location.\$ref');
      _resolveReference(document, reference! as String, location);
    }
    final type = value['type'];
    if (type != null) {
      expect(type, isA<String>(), reason: '$location.type');
      expect(
        {..._schemaTypes, ..._securitySchemeTypes},
        contains(type),
        reason: '$location.type',
      );
      if (type == 'array') {
        expect(value['items'], isNotNull, reason: '$location.items');
      }
    }
    final required = value['required'];
    final properties = value['properties'];
    if (required is YamlList && properties is YamlMap) {
      for (final field in required) {
        expect(
          properties.containsKey(field),
          isTrue,
          reason: '$location requires undefined property $field',
        );
      }
    }
    for (final entry in value.entries) {
      _visit(entry.value, '$location.${entry.key}', document);
    }
  } else if (value is YamlList) {
    for (var index = 0; index < value.length; index += 1) {
      _visit(value[index], '$location[$index]', document);
    }
  }
}

void _resolveReference(YamlMap document, String reference, String location) {
  expect(
    reference.startsWith('#/components/'),
    isTrue,
    reason: '$location uses unsupported reference $reference',
  );
  Object? current = document;
  for (final segment in reference.substring(2).split('/')) {
    expect(
      current,
      isA<YamlMap>(),
      reason: '$location cannot resolve $reference',
    );
    final map = current! as YamlMap;
    expect(
      map.containsKey(segment),
      isTrue,
      reason: '$location cannot resolve $reference',
    );
    current = map[segment];
  }
}
