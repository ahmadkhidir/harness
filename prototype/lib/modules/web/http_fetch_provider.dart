import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'html_to_markdown.dart';
import 'web_providers.dart';

/// Fetches webpages over HTTP(S) and converts their main content to Markdown.
///
/// Security posture (FEAT-008):
/// - Only `http` and `https` are accepted.
/// - Loopback, private, link-local, and multicast hosts are rejected, including
///   redirect targets, to blunt SSRF attempts from model-controlled URLs.
/// - Responses larger than [maxBytes] are aborted.
/// - Extracted Markdown is capped at [maxMarkdownCharacters].
class HttpWebFetchProvider implements WebFetchProvider {
  /// HTTP client used for requests, injectable for tests.
  final http.Client? client;

  /// Overall fetch timeout.
  final Duration timeout;

  /// Maximum response body size in bytes.
  final int maxBytes;

  /// Maximum number of characters returned in the Markdown body.
  final int maxMarkdownCharacters;

  /// Maximum number of redirect hops followed.
  final int maxRedirects;

  /// Creates a provider with the FEAT-008 defaults.
  HttpWebFetchProvider({
    this.client,
    this.timeout = const Duration(seconds: 20),
    this.maxBytes = 2 * 1024 * 1024,
    this.maxMarkdownCharacters = 100000,
    this.maxRedirects = 5,
  });

  @override
  Future<WebFetchResult> fetchAsMarkdown(String url) async {
    final target = _validateTarget(Uri.tryParse(url.trim()));

    try {
      final page = await _fetch(target).timeout(timeout);
      final extraction = extractMarkdownFromHtml(
        page.body,
        maxCharacters: maxMarkdownCharacters,
      );
      return WebFetchResult(
        url: page.finalUrl.toString(),
        markdown: extraction.markdown,
        truncated: extraction.truncated,
      );
    } on TimeoutException {
      throw WebBridgeException(
        'Timed out after ${timeout.inSeconds} seconds fetching $target.',
      );
    }
  }

  /// Follows redirects manually so every hop can be validated.
  Future<_FetchedPage> _fetch(Uri start) async {
    final clientToUse = client ?? http.Client();
    var current = start;

    for (var hop = 0; hop <= maxRedirects; hop++) {
      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers.addAll(const {
          'Accept': 'text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.5',
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 HarnessAgent/1.0',
        });

      final response = await clientToUse.send(request);

      if (_isRedirect(response.statusCode)) {
        final location = response.headers['location'];
        if (location == null || location.trim().isEmpty) {
          throw WebBridgeException(
            'HTTP ${response.statusCode} from $current without a Location header.',
            statusCode: response.statusCode,
          );
        }
        current = _validateTarget(current.resolve(location));
        continue;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw WebBridgeException(
          'HTTP ${response.statusCode} fetching $current.',
          statusCode: response.statusCode,
        );
      }

      final contentType = response.headers['content-type'] ?? '';
      if (!_isSupportedContentType(contentType)) {
        throw WebBridgeException(
          'Unsupported content type "$contentType" at $current.',
        );
      }

      final bytes = await _readCapped(response.stream);
      return _FetchedPage(
        body: _decode(bytes, contentType),
        finalUrl: current,
      );
    }

    throw WebBridgeException(
      'Too many redirects while fetching $start (limit $maxRedirects).',
    );
  }

  /// Reads [stream] while enforcing [maxBytes].
  Future<List<int>> _readCapped(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;

    await for (final chunk in stream) {
      total += chunk.length;
      if (total > maxBytes) {
        throw WebBridgeException(
          'Response exceeded the ${(maxBytes / (1024 * 1024)).toStringAsFixed(1)} MB limit.',
        );
      }
      builder.add(chunk);
    }

    return builder.takeBytes();
  }

  /// Decodes [bytes] using the charset advertised by [contentType].
  String _decode(List<int> bytes, String contentType) {
    final charsetMatch =
        RegExp(r'charset=([^;]+)', caseSensitive: false).firstMatch(contentType);
    final charset = charsetMatch?.group(1)?.trim().toLowerCase();
    if (charset == 'iso-8859-1' || charset == 'latin1') {
      return latin1.decode(bytes, allowInvalid: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Validates scheme and host before any request is sent.
  Uri _validateTarget(Uri? uri) {
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
      throw const WebBridgeException(
        'Invalid URL: expected an absolute http(s) URL.',
      );
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw WebBridgeException(
        'Unsupported URL scheme "${uri.scheme}". Only http and https are allowed.',
      );
    }

    if (_isPrivateHost(uri.host)) {
      throw WebBridgeException(
        'Refusing to fetch a loopback, private, or link-local host: ${uri.host}.',
      );
    }

    return uri;
  }

  /// Conservative literal-host check; DNS resolution is intentionally not used
  /// so validation stays deterministic and offline-testable.
  bool _isPrivateHost(String host) {
    final value = host
        .toLowerCase()
        .replaceAll('[', '')
        .replaceAll(']', '')
        .trim();

    if (value.isEmpty) return true;
    if (value == 'localhost' ||
        value.endsWith('.localhost') ||
        value.endsWith('.local') ||
        value == 'metadata.google.internal') {
      return true;
    }

    if (value.contains(':')) {
      if (value == '::1' || value == '::' || value.startsWith('fe80')) {
        return true;
      }
      // Unique local addresses (fc00::/7) and IPv4-mapped loopback.
      if (value.startsWith('fc') || value.startsWith('fd')) return true;
      if (value.startsWith('::ffff:127.') || value.startsWith('::ffff:10.')) {
        return true;
      }
    }

    final parts = value.split('.');
    if (parts.length != 4) return false;

    final octets = parts.map(int.tryParse).toList();
    if (octets.any((octet) => octet == null || octet < 0 || octet > 255)) {
      return false;
    }

    final a = octets[0]!;
    final b = octets[1]!;
    if (a == 0 || a == 10 || a == 127) return true;
    if (a == 169 && b == 254) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    if (a == 100 && b >= 64 && b <= 127) return true;

    return false;
  }

  bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  bool _isSupportedContentType(String contentType) {
    if (contentType.isEmpty) return true;
    final normalized = contentType.toLowerCase();
    return normalized.contains('text/html') ||
        normalized.contains('application/xhtml+xml') ||
        normalized.contains('text/plain') ||
        normalized.contains('text/markdown');
  }
}

class _FetchedPage {
  final String body;
  final Uri finalUrl;

  const _FetchedPage({required this.body, required this.finalUrl});
}
