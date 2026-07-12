import 'dart:typed_data';

enum TerminalClipboardOperation { copy, pasteRequest, mimeWrite, mimeRead }

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
    this.protocol = 'osc52',
    this.mimeTypes = const <String>[],
  });

  final String sessionId;
  final TerminalClipboardOperation operation;
  final String? selection;
  final int? byteCount;
  final int? characterCount;
  final String? textPreview;
  final bool textPreviewTruncated;
  final Future<String> Function()? resolveText;
  final String protocol;
  final List<String> mimeTypes;
}

final class TerminalClipboardMimeItem {
  TerminalClipboardMimeItem({
    required this.mimeType,
    required Uint8List bytes,
    List<String> aliases = const <String>[],
  }) : bytes = Uint8List.fromList(bytes),
       aliases = List<String>.unmodifiable(aliases);

  final String mimeType;
  final Uint8List bytes;
  final List<String> aliases;
}

typedef TerminalClipboardMimeWriter =
    Future<void> Function(List<TerminalClipboardMimeItem> items);
typedef TerminalClipboardMimeReader =
    Future<List<TerminalClipboardMimeItem>> Function(List<String> mimeTypes);
typedef TerminalClipboardMimeTypeLister = Future<List<String>> Function();

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
