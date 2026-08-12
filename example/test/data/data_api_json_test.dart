import 'package:app/data/data_api_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes a canonical nested Data API JSON document', () {
    expect(
      decodeDataApiJsonObject(
        '{"version":1,"nested":{"values":[true,null,-1.5e2]}}',
        documentName: 'fixture',
      ),
      <String, Object?>{
        'version': 1,
        'nested': <String, Object?>{
          'values': <Object?>[true, null, -150.0],
        },
      },
    );
  });

  test('rejects duplicate keys recursively instead of applying last-wins', () {
    expect(
      () => decodeDataApiJsonObject(
        '{"version":1,"nested":{"credential":"a","credential":"b"}}',
        documentName: 'fixture',
      ),
      throwsA(
        isA<DataApiJsonDuplicateKeyException>()
            .having((error) => error.key, 'key', 'credential')
            .having((error) => error.documentName, 'documentName', 'fixture'),
      ),
    );
  });
}
