import 'dart:io';

import 'package:app/features/command_center/command_history_privacy_filter.dart';
import 'package:app/features/command_center/global_command_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandHistoryPrivacyFilter', () {
    final finishedAt = DateTime.utc(2026, 6, 15, 10);

    test('blocks obvious sensitive command values with reasons', () {
      const filter = CommandHistoryPrivacyFilter();

      expect(
        filter.evaluateCommand('docker login --password=swordfish').reason,
        CommandHistoryPrivacyReason.sensitivePassword,
      );
      expect(
        filter.evaluateCommand('export API_TOKEN=abc123').reason,
        CommandHistoryPrivacyReason.sensitiveToken,
      );
      expect(
        filter.evaluateCommand('AWS_ACCESS_KEY_ID=AKIA123 deploy').reason,
        CommandHistoryPrivacyReason.sensitiveToken,
      );
      expect(
        filter
            .evaluateCommand('aws configure set aws_access_key_id AKIA123')
            .reason,
        CommandHistoryPrivacyReason.sensitiveToken,
      );
      expect(
        filter.evaluateCommand('curl --api-key sk-secret-value').reason,
        CommandHistoryPrivacyReason.sensitiveToken,
      );
      expect(
        filter.evaluateCommand('deploy --auth-token bearer-secret').reason,
        CommandHistoryPrivacyReason.sensitiveToken,
      );
      expect(
        filter.evaluateCommand('SECRET_KEY=abc deploy').reason,
        CommandHistoryPrivacyReason.sensitiveSecret,
      );
      expect(
        filter.evaluateCommand('printf "-----BEGIN PRIVATE KEY-----"').reason,
        CommandHistoryPrivacyReason.sensitivePrivateKey,
      );
    });

    test('allows common non-secret commands', () {
      const filter = CommandHistoryPrivacyFilter();

      expect(filter.evaluateCommand('grep password README.md').allowed, isTrue);
      expect(filter.evaluateCommand('git status --short').allowed, isTrue);
      expect(filter.evaluateCommand('flutter test').reason, isNull);
    });

    test('filters sensitive entries before repository save', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-command-history-filter-save',
      );
      final repository = GlobalCommandHistoryRepository(
        directoryResolver: () async => directory,
      );
      final document = GlobalCommandHistoryDocument(
        entries: [
          GlobalCommandHistoryEntry(
            command: 'flutter test',
            finishedAt: finishedAt,
          ),
          GlobalCommandHistoryEntry(
            command: 'export API_TOKEN=abc123',
            finishedAt: finishedAt.add(const Duration(seconds: 1)),
          ),
        ],
      );

      await repository.save(document);
      final loaded = await repository.load();

      expect(loaded.entries.map((entry) => entry.command), ['flutter test']);
    });

    test('does not write repository when history is disabled', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-command-history-disabled',
      );
      final repository = GlobalCommandHistoryRepository(
        directoryResolver: () async => directory,
        privacyFilter: const CommandHistoryPrivacyFilter(historyEnabled: false),
      );

      await repository.save(
        GlobalCommandHistoryDocument(
          entries: [
            GlobalCommandHistoryEntry(
              command: 'flutter test',
              finishedAt: finishedAt,
            ),
          ],
        ),
      );

      expect(
        File('${directory.path}/ianvs_command_history.json').existsSync(),
        isFalse,
      );
      expect(
        const CommandHistoryPrivacyFilter(
          historyEnabled: false,
        ).persistenceDecision().reason,
        CommandHistoryPrivacyReason.historyDisabled,
      );
    });

    test('clear intent deletes local repository history', () async {
      final directory = await Directory.systemTemp.createTemp(
        'ianvs terminal-command-history-clear',
      );
      final repository = GlobalCommandHistoryRepository(
        directoryResolver: () async => directory,
      );
      await repository.save(
        GlobalCommandHistoryDocument(
          entries: [
            GlobalCommandHistoryEntry(
              command: 'flutter test',
              finishedAt: finishedAt,
            ),
          ],
        ),
      );

      await repository.save(
        const GlobalCommandHistoryDocument(),
        intent: CommandHistoryWriteIntent.clear,
      );

      expect(
        File('${directory.path}/ianvs_command_history.json').existsSync(),
        isFalse,
      );
      expect((await repository.load()).entries, isEmpty);
      expect(
        const CommandHistoryPrivacyFilter()
            .persistenceDecision(intent: CommandHistoryWriteIntent.clear)
            .reason,
        CommandHistoryPrivacyReason.clearRequested,
      );
    });
  });
}
