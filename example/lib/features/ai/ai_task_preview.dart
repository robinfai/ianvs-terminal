import 'package:characters/characters.dart';
import 'package:markdown/markdown.dart' as md;

/// Menu-only text. Never use this projection as stored or model conversation.
String aiTaskPreview(String source) {
  const inputLimit = 8192;
  const previewLimit = 160;
  final bounded = source.characters.take(inputLimit).toString();
  final clipped = bounded.length < source.length;
  final clean = bounded.replaceAll('[earlier content omitted]', '');
  final nodes = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  ).parseLines(clean.split('\n'));

  String plain(md.Node node) {
    if (node is! md.Element) return node.textContent;
    if (node.tag == 'img') return node.attributes['alt'] ?? '';
    if (node.tag == 'br') return ' ';
    final children = node.children ?? const <md.Node>[];
    final separator = switch (node.tag) {
      'tr' => ' · ',
      'table' || 'thead' || 'tbody' || 'ul' || 'ol' => ' ',
      _ => '',
    };
    return children.map(plain).join(separator);
  }

  final text = nodes
      .map(plain)
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final prefix = text.characters.take(previewLimit).toString();
  return prefix.length < text.length || clipped
      ? '${prefix.trimRight()}…'
      : text;
}
