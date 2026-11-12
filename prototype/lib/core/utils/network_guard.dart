/// Exception raised when a model-supplied URL targets an unsafe or malformed host.
class UnsafeNetworkTargetException implements Exception {
  /// Human- and model-readable explanation.
  final String message;

  const UnsafeNetworkTargetException(this.message);

  @override
  String toString() => message;
}

/// Validates that [uri] is an absolute HTTP(S) URL whose host is public.
///
/// Rejects loopback, private, link-local, and multicast destinations so
/// model-controlled URLs cannot reach device-local or metadata services.
Uri assertPublicHttpUri(Uri? uri) {
  if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
    throw const UnsafeNetworkTargetException(
      'Invalid URL: expected an absolute http(s) URL.',
    );
  }

  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    throw UnsafeNetworkTargetException(
      'Unsupported URL scheme "${uri.scheme}". Only http and https are allowed.',
    );
  }

  if (isPrivateHost(uri.host)) {
    throw UnsafeNetworkTargetException(
      'Refusing to contact a loopback, private, or link-local host: ${uri.host}.',
    );
  }

  return uri;
}

/// Conservative literal-host check for loopback/private/link-local addresses.
///
/// DNS resolution is intentionally not performed so validation stays
/// deterministic and offline-testable.
bool isPrivateHost(String host) {
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

/// Normalizes a user-entered allowlist host entry.
///
/// Accepts a bare hostname, `host:port`, or a wildcard pattern such as `*`,
/// `*.example.com`, or `api.*.com:443`. Schemes, paths, userinfo, and
/// whitespace are rejected so stored entries compare predictably against
/// request hosts.
String? normalizeHostEntry(String input) {
  var value = input.trim().toLowerCase();
  if (value.isEmpty) return null;
  if (value.contains('://') ||
      value.contains('/') ||
      value.contains('@') ||
      value.contains('?') ||
      value.contains('#')) {
    return null;
  }

  // Wildcards are matched as a glob against the hostname. Keep the accepted
  // grammar deliberately small: DNS-label characters, `*`, dots, and an
  // optional port (or `*` for any port).
  if (value.contains('*')) {
    final split = _splitHostPort(value);
    if (split == null) return null;
    final host = split.host;
    final port = split.port;
    if (host.isEmpty || host.contains('..')) return null;
    if (host.startsWith('.') || host.endsWith('.')) return null;
    if (!RegExp(r'^[a-z0-9*.-]+$').hasMatch(host)) return null;
    if (port != null && !_isValidPortPattern(port)) return null;
    return port == null ? host : '$host:$port';
  }

  final uri = Uri.tryParse('https://$value');
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.host != value && !value.startsWith('${uri.host}:')) return null;
  if (uri.host.startsWith('.') ||
      uri.host.endsWith('.') ||
      uri.host.contains('..')) {
    return null;
  }

  return value;
}

/// Checks whether [host] matches any allowlist entry.
///
/// A bare hostname entry allows the host on any port; a `host:port` entry
/// requires an exact match. A `*` entry allows every host and port. Wildcard
/// patterns use `*` to match zero or more characters, so `*.example.com`
/// allows subdomains and `api.*.com` allows any middle label.
bool isHostAllowed(String host, int? port, Iterable<String> allowedHosts) {
  final normalizedHost = host.toLowerCase();
  for (final raw in allowedHosts) {
    final entry = normalizeHostEntry(raw);
    if (entry == null) continue;

    if (entry == '*') return true;

    if (entry.contains('*')) {
      final split = _splitHostPort(entry);
      if (split == null) continue;
      if (split.port != null &&
          split.port != '*' &&
          int.tryParse(split.port!) != port) {
        continue;
      }
      if (_matchesHostPattern(split.host, normalizedHost)) return true;
      continue;
    }

    final entryUri = Uri.tryParse('https://$entry');
    if (entryUri == null) continue;

    if (entryUri.host == normalizedHost) {
      if (entry.contains(':')) {
        if (entryUri.port == port) return true;
      } else {
        return true;
      }
    }
  }
  return false;
}

/// Splits a wildcard entry into host and optional port.
///
/// IPv6 literals are intentionally excluded from wildcard entries; exact IPv6
/// hosts continue through the normal URI validation path.
({String host, String? port})? _splitHostPort(String value) {
  if (value.startsWith('[')) return null;
  final separator = value.lastIndexOf(':');
  if (separator == -1) return (host: value, port: null);
  final host = value.substring(0, separator);
  final port = value.substring(separator + 1);
  if (host.contains(':')) return null;
  return (host: host, port: port.isEmpty ? null : port);
}

/// True when [port] is a numeric port or the wildcard `*`.
bool _isValidPortPattern(String port) {
  if (port == '*') return true;
  final parsed = int.tryParse(port);
  return parsed != null && parsed >= 1 && parsed <= 65535;
}

/// Matches a hostname glob where `*` stands for zero or more characters.
bool _matchesHostPattern(String pattern, String host) {
  if (!pattern.contains('*')) return pattern == host;
  final escaped = pattern.split('*').map(RegExp.escape).join('.*');
  return RegExp('^$escaped\$').hasMatch(host);
}
