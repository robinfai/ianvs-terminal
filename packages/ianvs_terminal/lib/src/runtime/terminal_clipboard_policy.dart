enum TerminalClipboardOperation { copy, pasteRequest }

enum TerminalClipboardDecision { allowed, blocked, invalidPayload }

final class TerminalClipboardAccessRequest {
  const TerminalClipboardAccessRequest({
    required this.sessionId,
    required this.operation,
    this.selection,
    this.byteCount,
    this.characterCount,
    this.textPreview,
    this.textPreviewTruncated = false,
    this.resolveText,
  });

  final String sessionId;
  final TerminalClipboardOperation operation;
  final String? selection;
  final int? byteCount;
  final int? characterCount;
  final String? textPreview;
  final bool textPreviewTruncated;
  final Future<String> Function()? resolveText;
}

final class TerminalClipboardPolicyAdapter {
  const TerminalClipboardPolicyAdapter({
    this.allowClipboardCopy,
    this.allowClipboardPasteRequest,
    this.allowClipboardCopyWithContext,
    this.allowClipboardPasteRequestWithContext,
  });

  final Future<bool> Function()? allowClipboardCopy;
  final Future<bool> Function()? allowClipboardPasteRequest;
  final Future<bool> Function(TerminalClipboardAccessRequest request)?
  allowClipboardCopyWithContext;
  final Future<bool> Function(TerminalClipboardAccessRequest request)?
  allowClipboardPasteRequestWithContext;

  Future<bool> allowCopy(TerminalClipboardAccessRequest request) {
    final contextual = allowClipboardCopyWithContext;
    if (contextual != null) {
      return contextual(request);
    }
    final legacy = allowClipboardCopy;
    if (legacy != null) {
      return legacy();
    }
    return _blockByDefault();
  }

  Future<bool> allowPasteRequest(TerminalClipboardAccessRequest request) {
    final contextual = allowClipboardPasteRequestWithContext;
    if (contextual != null) {
      return contextual(request);
    }
    final legacy = allowClipboardPasteRequest;
    if (legacy != null) {
      return legacy();
    }
    return _blockByDefault();
  }
}

Future<bool> _blockByDefault() async => false;
