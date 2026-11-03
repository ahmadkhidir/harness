import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Result of extracting readable Markdown from an HTML document.
class MarkdownExtraction {
  /// Extracted Markdown body.
  final String markdown;

  /// True when [markdown] was cut to the configured character cap.
  final bool truncated;

  const MarkdownExtraction({
    required this.markdown,
    required this.truncated,
  });
}

/// Converts an HTML document into clean, readable Markdown.
///
/// Navigation boilerplate (`script`, `style`, `nav`, `header`, `footer`,
/// `aside`, `form`, media embeds) is removed before extraction. When the page
/// exposes an `article` or `main` container, only that subtree is rendered;
/// otherwise the whole body is used.
MarkdownExtraction extractMarkdownFromHtml(
  String html, {
  int maxCharacters = 100000,
}) {
  final document = html_parser.parse(html);

  const removableSelectors = [
    'script',
    'style',
    'noscript',
    'template',
    'nav',
    'header',
    'footer',
    'aside',
    'form',
    'svg',
    'iframe',
    'canvas',
    'video',
    'audio',
  ];
  for (final selector in removableSelectors) {
    document.querySelectorAll(selector).forEach((element) => element.remove());
  }

  final root = document.querySelector('article') ??
      document.querySelector('main') ??
      document.body;

  final buffer = StringBuffer();
  if (root != null) {
    for (final node in root.nodes) {
      _renderBlock(node, buffer);
    }
  }

  var markdown = _normalize(buffer.toString());
  final truncated = markdown.length > maxCharacters;
  if (truncated) {
    markdown = markdown.substring(0, maxCharacters).trimRight();
  }

  return MarkdownExtraction(markdown: markdown, truncated: truncated);
}

/// Renders a block-level node into [buffer].
void _renderBlock(Node node, StringBuffer buffer) {
  if (node is Text) {
    final text = _collapse(node.text);
    if (text.isNotEmpty) buffer.write(text);
    return;
  }
  if (node is! Element) return;

  final tag = node.localName;
  switch (tag) {
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      final level = int.parse(tag!.substring(1));
      final text = _inline(node);
      if (text.isNotEmpty) {
        buffer.write('\n\n${'#' * level} $text\n\n');
      }
      return;
    case 'p':
      final text = _inline(node);
      if (text.isNotEmpty) buffer.write('\n\n$text\n\n');
      return;
    case 'br':
      buffer.writeln();
      return;
    case 'hr':
      buffer.write('\n\n---\n\n');
      return;
    case 'pre':
      final code = node.text.trimRight();
      if (code.isNotEmpty) buffer.write('\n\n```\n$code\n```\n\n');
      return;
    case 'blockquote':
      final text = _inline(node);
      if (text.isNotEmpty) {
        final quoted = text.split('\n').map((line) => '> $line').join('\n');
        buffer.write('\n\n$quoted\n\n');
      }
      return;
    case 'ul':
    case 'ol':
      _renderList(node, buffer, ordered: tag == 'ol');
      return;
    case 'table':
      _renderTable(node, buffer);
      return;
    case 'div':
    case 'section':
    case 'article':
    case 'main':
    case 'body':
      for (final child in node.nodes) {
        _renderBlock(child, buffer);
      }
      return;
    default:
      // Unknown containers still contribute their inline content.
      final text = _inline(node);
      if (text.isNotEmpty) buffer.write('\n\n$text\n\n');
  }
}

/// Renders an ordered or unordered list.
void _renderList(Element element, StringBuffer buffer, {required bool ordered}) {
  final items = element.children.where((child) => child.localName == 'li');
  if (items.isEmpty) return;

  buffer.write('\n');
  var index = 1;
  for (final item in items) {
    final text = _inline(item);
    if (text.isEmpty) continue;
    final marker = ordered ? '$index.' : '-';
    buffer.writeln('$marker $text');
    index++;
  }
  buffer.write('\n');
}

/// Renders a table as pipe-separated rows.
void _renderTable(Element element, StringBuffer buffer) {
  final rows = element.querySelectorAll('tr');
  if (rows.isEmpty) return;

  buffer.write('\n');
  for (final row in rows) {
    final cells = row.children
        .where((cell) => cell.localName == 'td' || cell.localName == 'th')
        .map((cell) => _inline(cell).replaceAll('|', r'\|'))
        .toList();
    if (cells.isEmpty) continue;
    buffer.writeln('| ${cells.join(' | ')} |');
  }
  buffer.write('\n');
}

/// Renders inline content of a node, preserving basic emphasis and links.
String _inline(Node node) {
  final buffer = StringBuffer();

  void visit(Node current) {
    if (current is Text) {
      // Preserve significant spacing between inline siblings ("Hello **world**.").
      buffer.write(_collapseWhitespace(current.text));
      return;
    }
    if (current is! Element) return;

    final tag = current.localName;
    switch (tag) {
      case 'strong':
      case 'b':
        final inner = _inline(current);
        if (inner.isNotEmpty) buffer.write('**$inner**');
        return;
      case 'em':
      case 'i':
        final inner = _inline(current);
        if (inner.isNotEmpty) buffer.write('*$inner*');
        return;
      case 'code':
        final code = current.text.trim();
        if (code.isNotEmpty) buffer.write('`$code`');
        return;
      case 'a':
        final inner = _inline(current);
        final href = current.attributes['href'] ?? '';
        if (inner.isEmpty) return;
        buffer.write(href.isEmpty ? inner : '[$inner]($href)');
        return;
      case 'img':
        final alt = current.attributes['alt'] ?? '';
        final src = current.attributes['src'] ?? '';
        if (src.isNotEmpty) buffer.write('![$alt]($src)');
        return;
      case 'br':
        buffer.write(' ');
        return;
      default:
        for (final child in current.nodes) {
          visit(child);
        }
    }
  }

  for (final child in node.nodes) {
    visit(child);
  }
  return _collapse(buffer.toString());
}

/// Collapses runs of whitespace so extracted prose reads as single lines.
String _collapse(String input) => _collapseWhitespace(input).trim();

/// Collapses whitespace without trimming boundary spaces.
String _collapseWhitespace(String input) =>
    input.replaceAll(RegExp(r'\s+'), ' ');

/// Normalizes paragraph spacing and trims the final document.
String _normalize(String input) {
  var output = input.replaceAll(RegExp(r'[ \t]+\n'), '\n');
  output = output.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return output.trim();
}
