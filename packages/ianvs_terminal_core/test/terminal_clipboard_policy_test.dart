import 'package:flutter_test/flutter_test.dart';
import 'package:ianvs_terminal_core/ianvs_terminal_core.dart';
import 'package:ianvs_terminal_core/src/runtime/terminal_runtime_controller.dart'
    as runtime_src;

void main() {
  group('TerminalClipboardPolicyAdapter', () {
    const copyRequest = TerminalClipboardAccessRequest(
      sessionId: 'session-1',
      operation: TerminalClipboardOperation.copy,
      selection: 'c',
      byteCount: 4,
      characterCount: 4,
      textPreview: 'copy',
    );

    const pasteRequest = TerminalClipboardAccessRequest(
      sessionId: 'session-1',
      operation: TerminalClipboardOperation.pasteRequest,
      selection: 'p',
    );

    test('blocks copy and paste requests without an explicit policy', () async {
      const adapter = TerminalClipboardPolicyAdapter();

      expect(await adapter.allowCopy(copyRequest), isFalse);
      expect(await adapter.allowPasteRequest(pasteRequest), isFalse);
    });

    test('uses legacy callbacks when contextual policies are absent', () async {
      final adapter = TerminalClipboardPolicyAdapter(
        allowClipboardCopy: () async => true,
        allowClipboardPasteRequest: () async => true,
      );

      expect(await adapter.allowCopy(copyRequest), isTrue);
      expect(await adapter.allowPasteRequest(pasteRequest), isTrue);
    });

    test('prefers contextual callbacks over legacy callbacks', () async {
      final seenOperations = <TerminalClipboardOperation>[];
      final adapter = TerminalClipboardPolicyAdapter(
        allowClipboardCopy: () async => false,
        allowClipboardPasteRequest: () async => false,
        allowClipboardCopyWithContext: (request) async {
          seenOperations.add(request.operation);
          return true;
        },
        allowClipboardPasteRequestWithContext: (request) async {
          seenOperations.add(request.operation);
          return true;
        },
      );

      expect(await adapter.allowCopy(copyRequest), isTrue);
      expect(await adapter.allowPasteRequest(pasteRequest), isTrue);
      expect(seenOperations, <TerminalClipboardOperation>[
        TerminalClipboardOperation.copy,
        TerminalClipboardOperation.pasteRequest,
      ]);
    });

    test(
      'stays available from the runtime controller source library',
      () async {
        const request = runtime_src.TerminalClipboardAccessRequest(
          sessionId: 'session-1',
          operation: runtime_src.TerminalClipboardOperation.copy,
        );
        const adapter = runtime_src.TerminalClipboardPolicyAdapter();

        expect(request.operation, runtime_src.TerminalClipboardOperation.copy);
        expect(await adapter.allowCopy(request), isFalse);
      },
    );
  });
}
