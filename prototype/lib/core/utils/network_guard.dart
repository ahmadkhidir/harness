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

/// Normalizes a user-entered allowlist host entry (e.g. `API.Example.com:8443`).
///
/// Accepts a bare hostname or `host:port`; rejects schemes, paths, userinfo, and
/// whitespace so stored entries compare predictably against request hosts.
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

  final uri = Uri.tryParse('https://$value');
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.host != value && !value.startsWith('${uri.host}:')) return null;

  return value;
}

/// Checks whether [host] matches any allowlist entry.
///
/// A bare hostname entry allows the host on any port; a `host:port` entry
/// requires an exact match.
bool isHostAllowed(String host, int? port, Iterable<String> allowedHosts) {
  final normalizedHost = host.toLowerCase();
  for (final raw in allowedHosts) {
    final entry = normalizeHostEntry(raw);
    if (entry == null) continue;

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
