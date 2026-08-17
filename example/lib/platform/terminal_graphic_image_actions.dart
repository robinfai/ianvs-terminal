import 'package:ianvs_terminal/ianvs_terminal.dart';

import 'clipboard_bridge.dart';

typedef TerminalGraphicImageLocationPicker =
    Future<String?> Function(String suggestedName);
typedef TerminalGraphicImageWriter =
    Future<void> Function(String path, List<int> bytes);

Future<String?> saveTerminalGraphicImage(
  TerminalGraphicImage image, {
  required TerminalGraphicImageLocationPicker chooseLocation,
  required TerminalGraphicImageWriter write,
}) async {
  String? path;
  try {
    path = await chooseLocation(image.suggestedFileName);
  } on Object {
    return 'Could not open the image save dialog';
  }
  if (path == null) {
    return null;
  }
  try {
    await write(path, image.pngBytes);
  } on Object {
    return 'Could not save image';
  }
  return 'Saved image';
}

Future<String> copyTerminalGraphicImage(TerminalGraphicImage image) async {
  try {
    await ClipboardBridge.writeMimeItems(<TerminalClipboardMimeItem>[
      TerminalClipboardMimeItem(mimeType: 'image/png', bytes: image.pngBytes),
    ]);
  } on Object {
    return 'Could not copy image';
  }
  return 'Copied image';
}
