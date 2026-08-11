import 'dart:convert';
import 'dart:io';

import '../../platform/corrupt_file_quarantine.dart';
import '../../platform/local_json_file.dart';
import 'data_api_configuration.dart';

abstract interface class DataApiConfigurationRepository {
  Future<DataApiConfiguration> load();

  Future<void> save(DataApiConfiguration configuration);
}

final class FileDataApiConfigurationRepository
    implements DataApiConfigurationRepository {
  FileDataApiConfigurationRepository({required Directory appSupportDirectory})
    : configurationFile = File(
        '${appSupportDirectory.path}${Platform.pathSeparator}'
        'data-api${Platform.pathSeparator}configuration.json',
      );

  FileDataApiConfigurationRepository.forFile(this.configurationFile);

  final File configurationFile;

  @override
  Future<DataApiConfiguration> load() async {
    if (!await configurationFile.exists()) {
      return const DataApiConfiguration.disabled();
    }
    try {
      final json = decodeJsonObject(
        await configurationFile.readAsString(),
        documentName: 'Data API configuration',
      );
      return DataApiConfiguration.fromJson(json);
    } on FormatException {
      await quarantineCorruptFile(configurationFile);
      const repaired = DataApiConfiguration.disabled();
      await save(repaired);
      return repaired;
    }
  }

  @override
  Future<void> save(DataApiConfiguration configuration) {
    return writeStringAtomically(
      configurationFile,
      '${jsonEncode(configuration.toJson())}\n',
    );
  }
}
