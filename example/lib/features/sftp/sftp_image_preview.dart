import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

bool isSftpPreviewImage(String name) => const {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'ico',
}.contains(name.split('.').last.toLowerCase());

/// Remote bytes live only for the lifetime of this preview.
class SftpImagePreview extends StatefulWidget {
  const SftpImagePreview({
    required this.name,
    required this.load,
    required this.onDownload,
    super.key,
  });

  final String name;
  final Future<Uint8List> Function() load;
  final Future<void> Function() onDownload;

  @override
  State<SftpImagePreview> createState() => _SftpImagePreviewState();
}

class _SftpImagePreviewState extends State<SftpImagePreview> {
  late Future<Uint8List> _image = widget.load();
  bool _downloading = false;
  MemoryImage? _provider;

  @override
  void dispose() {
    unawaited(_provider?.evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    Widget failure() => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          zh
              ? '无法预览此图片，可重试或下载查看。'
              : 'Cannot preview this image. Retry or download it.',
        ),
        TextButton.icon(
          onPressed: () => setState(() => _image = widget.load()),
          icon: const Icon(Icons.refresh),
          label: Text(zh ? '重试' : 'Retry'),
        ),
      ],
    );
    return Dialog(
      child: SizedBox(
        width: 800,
        height: MediaQuery.sizeOf(context).height * .8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _downloading
                        ? null
                        : () async {
                            setState(() => _downloading = true);
                            try {
                              await widget.onDownload();
                            } finally {
                              if (mounted) setState(() => _downloading = false);
                            }
                          },
                    icon: const Icon(Icons.download_outlined),
                    label: Text(zh ? '下载' : 'Download'),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<Uint8List>(
                future: _image,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData) return Center(child: failure());
                  if (!identical(_provider?.bytes, snapshot.data)) {
                    unawaited(_provider?.evict());
                    _provider = MemoryImage(snapshot.data!);
                  }
                  return InteractiveViewer(
                    minScale: .5,
                    maxScale: 8,
                    child: Center(
                      child: Image(
                        image: _provider!,
                        fit: BoxFit.contain,
                        semanticLabel: widget.name,
                        errorBuilder: (_, error, stackTrace) => failure(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
