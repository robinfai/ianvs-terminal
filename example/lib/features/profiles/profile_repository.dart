import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../platform/corrupt_file_quarantine.dart';
import 'profile_models.dart';

typedef DirectoryResolver = Future<Directory> Function();

class ProfileRepository {
  ProfileRepository({DirectoryResolver? directoryResolver})
    : _directoryResolver = directoryResolver ?? getApplicationSupportDirectory;

  final DirectoryResolver _directoryResolver;

  Future<TerminalProfilesDocument> load() async {
    final file = await _profilesFile();
    if (!await file.exists()) {
      final fallback = TerminalProfilesDocument(
        profiles: [defaultTerminalProfile(), vt220TerminalProfile()],
      );
      await save(fallback);
      return fallback;
    }

    final raw = await file.readAsString();
    try {
      final decoded = jsonDecode(raw);
      final json = decoded is Map
          ? decoded.map(
              (key, value) => MapEntry(key.toString(), value as Object?),
            )
          : null;
      if (json == null) {
        return _repairInvalidLoad(
          file,
          rawValueSummary: 'root value was not an object',
        );
      }
      return TerminalProfilesDocument.fromJson(json);
    } on FormatException catch (error) {
      return _repairInvalidLoad(file, rawValueSummary: error.message);
    }
  }

  Future<void> save(TerminalProfilesDocument document) async {
    final file = await _profilesFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(document.encode());
  }

  Future<File> exportDocument(
    TerminalProfilesDocument document, {
    String basename = 'ianvs-profiles',
  }) async {
    final directory = await _directoryResolver();
    await directory.create(recursive: true);
    final safeBasename = _safeBasename(basename);
    final file = File(
      '${directory.path}/$safeBasename.ianvs-terminal-profiles.json',
    );
    await file.writeAsString(document.encode());
    return file;
  }

  Future<File> _profilesFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/ianvs_profiles.json');
  }

  String _safeBasename(String basename) {
    final safe = basename
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp('-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (safe.isEmpty) {
      return 'ianvs-profiles';
    }
    return safe;
  }

  Future<TerminalProfilesDocument> _repairInvalidLoad(
    File file, {
    required String rawValueSummary,
  }) async {
    await quarantineCorruptFile(file);
    final repaired = TerminalProfilesDocument(
      profiles: [defaultTerminalProfile(), vt220TerminalProfile()],
      loadWarnings: [
        TerminalProfileLoadWarning(
          profileId: 'document',
          profileName: 'Profiles document',
          path: 'document',
          rawValueSummary: rawValueSummary,
          fallbackSummary:
              'quarantined corrupt file and saved fallback profiles',
        ),
      ],
    );
    await save(repaired);
    return repaired;
  }
}
