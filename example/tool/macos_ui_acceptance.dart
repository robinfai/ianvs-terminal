// Isolated UI acceptance: production widgets and native PTY, memory-only
// preferences/profiles. No Data API credentials or user repositories are read.
import 'dart:io';

import 'package:app/app.dart';
import 'package:app/features/profiles/profile_models.dart';
import 'package:app/features/pty/pty.dart';
import 'package:app/features/recording/local_session_recording_repository.dart';
import 'package:app/features/sessions/session_controller.dart';
import 'package:app/features/shell/shell_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../test/support/memory_app_preferences_repository.dart';
import '../test/support/memory_local_terminal_config_repository.dart';
import '../test/support/memory_paste_history_repository.dart';
import '../test/support/memory_profile_repository.dart';
import '../test/support/no_io_local_terminal_layout_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final scratch = Directory.systemTemp.createTempSync('ianvs-macos-ui-');
  runApp(
    ProviderScope(
      overrides: [
        ptySessionBackendProvider.overrideWithValue(NativePtyBackend.load()),
        profileRepositoryProvider.overrideWithValue(
          MemoryProfileRepository(
            TerminalProfilesDocument(profiles: [defaultTerminalProfile()]),
          ),
        ),
        appPreferencesRepositoryProvider.overrideWithValue(
          MemoryAppPreferencesRepository(null),
        ),
        localTerminalConfigRepositoryProvider.overrideWithValue(
          MemoryLocalTerminalConfigRepository(null),
        ),
        pasteHistoryRepositoryProvider.overrideWithValue(
          MemoryPasteHistoryRepository(),
        ),
        localTerminalLayoutRepositoryProvider.overrideWithValue(
          noIoLocalTerminalLayoutRepository(),
        ),
        localSessionRecordingRepositoryProvider.overrideWithValue(
          LocalSessionRecordingRepository(
            directoryResolver: () async => scratch,
          ),
        ),
      ],
      child: const IanvsTerminalApp(),
    ),
  );
}
