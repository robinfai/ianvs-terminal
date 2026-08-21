import 'package:ianvs_terminal/ianvs_terminal.dart';

import '../l10n/l10n.dart';
import 'clipboard_bridge.dart';

typedef TerminalGraphicImageLocationPicker =
    Future<String?> Function(String suggestedName);
typedef TerminalGraphicImageWriter =
    Future<void> Function(String path, List<int> bytes);

Future<String?> saveTerminalGraphicImage(
  TerminalGraphicImage image, {
  required TerminalGraphicImageLocationPicker chooseLocation,
  required TerminalGraphicImageWriter write,
  required AppLocalizations l10n,
}) async {
  String? path;
  try {
    path = await chooseLocation(image.suggestedFileName);
  } on Object {
    return l10n.couldNotOpenImageSaveDialog;
  }
  if (path == null) {
    return null;
  }
  try {
    await write(path, image.pngBytes);
  } on Object {
    return l10n.couldNotSaveImage;
  }
  return l10n.savedImage;
}

Future<String> copyTerminalGraphicImage(
  TerminalGraphicImage image, {
  required AppLocalizations l10n,
}) async {
  try {
    await ClipboardBridge.writeMimeItems(<TerminalClipboardMimeItem>[
      TerminalClipboardMimeItem(mimeType: 'image/png', bytes: image.pngBytes),
    ]);
  } on Object {
    return l10n.couldNotCopyImage;
  }
  return l10n.copiedImage;
}
