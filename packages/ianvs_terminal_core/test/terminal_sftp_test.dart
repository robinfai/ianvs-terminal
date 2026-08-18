import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';

void main() {
  test('SFTP cancellation is observable and idempotent', () async {
    final cancellation = TerminalSftpCancellation();

    expect(cancellation.isCancelled, isFalse);
    cancellation.cancel();
    cancellation.cancel();

    expect(cancellation.isCancelled, isTrue);
    await expectLater(cancellation.whenCancelled, completes);
  });

  test('SFTP entry decoder rejects control characters in remote names', () {
    expect(
      () => TerminalSftpDirectoryEntry.fromJson(<String, Object?>{
        'name': 'line\nbreak',
        'kind': 'file',
      }),
      throwsFormatException,
    );
  });

  test('SFTP operation status decoder rejects unknown wire states', () {
    expect(
      TerminalSftpOperationPollResult.fromJson(<String, Object?>{
        'status': 'complete',
      }).status,
      TerminalSftpOperationPollStatus.complete,
    );
    expect(
      () => TerminalSftpOperationPollResult.fromJson(<String, Object?>{
        'status': 'surprise',
      }),
      throwsFormatException,
    );
  });
}
