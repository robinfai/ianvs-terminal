import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

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
    return TerminalProfilesDocument.fromJson(
      jsonDecode(raw) as Map<String, Object?>,
    );
  }

  Future<void> save(TerminalProfilesDocument document) async {
    final file = await _profilesFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(document.encode());
  }

  Future<File> _profilesFile() async {
    final directory = await _directoryResolver();
    return File('${directory.path}/flutterm_profiles.json');
  }
}
