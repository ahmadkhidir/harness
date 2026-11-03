import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/utils/file_system_manager.dart';
import '../../core/utils/network_guard.dart';
import 'transfer_exception.dart';

/// Result of a completed media download.
class DownloadedMedia {
  /// Registered storage tag receiving the file.
  final String storage;

  /// Path relative to the selected storage volume.
  final String path;

  /// MIME type reported by the server.
  final String mimeType;

  /// Number of bytes written.
  final int byteSize;

  const DownloadedMedia({
    required this.storage,
    required this.path,
    required this.mimeType,
    required this.byteSize,
  });

  Map<String, dynamic> toJson() => {
        'storage': storage,
        'path': path,
        'mimeType': mimeType,
        'byteSize': byteSize,
      };
}

/// Streams binary media into a registered storage volume (FEAT-009).
///
/// Safety posture:
/// - Only public `http`/`https` targets, including redirect targets.
/// - MIME allowlist: images, audio, video, and PDF.
/// - 25 MB cap enforced while streaming; partial files are removed.
/// - Destination paths are canonicalized inside the selected mount, existing
///   files are never overwritten, and names resolve from the caller,
///   `Content-Disposition`, the URL, or a generated timestamp.
class MediaDownloader {
  /// HTTP client used for requests, injectable for tests.
  final http.Client? client;

  /// Overall download timeout.
  final Duration timeout;

  /// Maximum bytes accepted per file (25 MB).
  final int maxBytes;

  /// Maximum redirect hops followed.
  final int maxRedirects;

  /// Resolves the active filesystem, or null when storage is unavailable.
  final HarnessFileSystem? Function() fileSystemProvider;

  /// Creates a downloader with the FEAT-009 defaults.
  MediaDownloader({
    required this.fileSystemProvider,
    this.client,
    this.timeout = const Duration(seconds: 60),
    this.maxBytes = 25 * 1024 * 1024,
    this.maxRedirects = 5,
  });

  static const List<String> _allowedMimePrefixes = [
    'image/',
    'audio/',
    'video/',
  ];

  /// Downloads [url] into [storage] (default `primary`).
  Future<DownloadedMedia> download({
    required String url,
    String storage = 'primary',
    String? path,
    String? filename,
  }) async {
    final fileSystem = fileSystemProvider();
    if (fileSystem == null) {
      throw const TransferException(
        'Storage is not initialized. Cannot save downloaded media.',
      );
    }

    final tag = storage.trim().isEmpty ? 'primary' : storage.trim();
    if (!fileSystem.mounts.hasMount(tag)) {
      throw TransferException(
        'Unknown storage volume "$tag". Available volumes: '
        '${fileSystem.mounts.mountTags.join(', ')}.',
      );
    }

    File? partialFile;
    try {
      final target = assertPublicHttpUri(Uri.tryParse(url.trim()));
      return await _download(
        fileSystem: fileSystem,
        storageTag: tag,
        target: target,
        requestedPath: path,
        requestedFilename: filename,
        onPartialFile: (file) => partialFile = file,
      ).timeout(timeout);
    } on TimeoutException {
      await _deleteQuietly(partialFile);
      throw TransferException(
        'Download timed out after ${timeout.inSeconds} seconds.',
      );
    } on UnsafeNetworkTargetException catch (e) {
      await _deleteQuietly(partialFile);
      throw TransferException(e.message);
    } on SecurityException catch (e) {
      await _deleteQuietly(partialFile);
      throw TransferException(e.message);
    } on UnknownVolumeException catch (e) {
      await _deleteQuietly(partialFile);
      throw TransferException(e.message);
    } on IOException catch (e) {
      await _deleteQuietly(partialFile);
      throw TransferException('Could not write the downloaded file: $e');
    }
  }

  Future<DownloadedMedia> _download({
    required HarnessFileSystem fileSystem,
    required String storageTag,
    required Uri target,
    required String? requestedPath,
    required String? requestedFilename,
    required void Function(File) onPartialFile,
  }) async {
    final page = await _open(target);
    final mimeType = _primaryMimeType(page.headers['content-type']);
    if (!_isAllowedMimeType(mimeType)) {
      throw TransferException(
        'Unsupported media type "$mimeType". Allowed types are images, audio, video, and PDF.',
      );
    }

    final declaredLength = int.tryParse(page.headers['content-length'] ?? '');
    if (declaredLength != null && declaredLength > maxBytes) {
      throw TransferException(
        'File exceeds the ${_megabytes(maxBytes)} MB download limit.',
      );
    }

    final relativePath = _resolveRelativePath(
      requestedPath: requestedPath,
      requestedFilename: requestedFilename,
      contentDisposition: page.headers['content-disposition'],
      sourceUri: page.finalUri,
      mimeType: mimeType,
    );

    final virtualPath = '$storageTag/$relativePath';
    final file = _uniqueDestination(fileSystem.resolveVirtualFile(virtualPath));
    await file.parent.create(recursive: true);

    final part = File('${file.path}.part');
    if (await part.exists()) await part.delete();
    onPartialFile(part);

    var total = 0;
    final sink = part.openWrite();
    try {
      await for (final chunk in page.response.stream) {
        total += chunk.length;
        if (total > maxBytes) {
          throw TransferException(
            'File exceeds the ${_megabytes(maxBytes)} MB download limit.',
          );
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      await part.rename(file.path);
    } catch (_) {
      await sink.close().catchError((_) {});
      await _deleteQuietly(part);
      rethrow;
    }

    return DownloadedMedia(
      storage: storageTag,
      path: _relativeToMount(fileSystem, storageTag, file),
      mimeType: mimeType,
      byteSize: total,
    );
  }

  Future<_OpenedPage> _open(Uri start) async {
    final clientToUse = client ?? http.Client();
    var current = start;

    for (var hop = 0; hop <= maxRedirects; hop++) {
      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers.addAll(const {
          'Accept': 'image/*,audio/*,video/*,application/pdf,*/*;q=0.5',
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 HarnessAgent/1.0',
        });

      final response = await clientToUse.send(request);

      if (_isRedirect(response.statusCode)) {
        final location = response.headers['location'];
        if (location == null || location.trim().isEmpty) {
          throw TransferException(
            'HTTP ${response.statusCode} from $current without a Location header.',
          );
        }
        current = assertPublicHttpUri(current.resolve(location));
        continue;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw TransferException(
          'HTTP ${response.statusCode} downloading $current.',
        );
      }

      return _OpenedPage(
        response: response,
        headers: response.headers,
        finalUri: current,
      );
    }

    throw TransferException(
      'Too many redirects while downloading $start (limit $maxRedirects).',
    );
  }

  /// Resolves the destination path relative to the selected mount.
  String _resolveRelativePath({
    required String? requestedPath,
    required String? requestedFilename,
    required String? contentDisposition,
    required Uri sourceUri,
    required String mimeType,
  }) {
    final normalizedPath = (requestedPath ?? '')
        .replaceAll('\\', '/')
        .trim()
        .replaceFirst(RegExp(r'^/+'), '');

    // A concrete file path always wins.
    if (normalizedPath.isNotEmpty && !normalizedPath.endsWith('/')) {
      return normalizedPath;
    }

    final directory = normalizedPath.isEmpty
        ? ''
        : normalizedPath.endsWith('/')
            ? normalizedPath.substring(0, normalizedPath.length - 1)
            : normalizedPath;

    final name = _sanitizeFileName(
          requestedFilename?.trim().isNotEmpty == true
              ? requestedFilename!.trim()
              : _filenameFromDisposition(contentDisposition) ??
                  _filenameFromUrl(sourceUri) ??
                  _generatedFileName(mimeType),
        ) ??
        _generatedFileName(mimeType);

    return directory.isEmpty ? name : '$directory/$name';
  }

  /// Extracts a filename from a `Content-Disposition` header.
  String? _filenameFromDisposition(String? header) {
    if (header == null || header.trim().isEmpty) return null;

    final extended = RegExp(
      r"filename\*\s*=\s*(?:UTF-8'')?([^;]+)",
      caseSensitive: false,
    ).firstMatch(header);
    if (extended != null) {
      final value = extended.group(1)!.trim().replaceAll('"', '');
      try {
        return Uri.decodeComponent(value);
      } catch (_) {
        return value;
      }
    }

    final plain = RegExp(
      r'filename\s*=\s*"?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(header);
    return plain?.group(1)?.trim();
  }

  /// Uses the last URL path segment as a name when it is usable.
  String? _filenameFromUrl(Uri uri) {
    if (uri.path.isEmpty) return null;
    final decoded = Uri.decodeComponent(uri.path);
    final base = p.basename(decoded);
    return base.isEmpty || base == '/' || base == '.' ? null : base;
  }

  /// Generates a timestamped fallback name with a MIME-implied extension.
  String _generatedFileName(String mimeType) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return 'download_$stamp${_extensionForMime(mimeType)}';
  }

  /// Strips unsafe characters from a filename.
  String? _sanitizeFileName(String candidate) {
    var name = candidate
        .replaceAll(RegExp(r'[\x00-\x1f<>:"/\\|?*]'), '_')
        .replaceAll('..', '_')
        .trim();

    if (name.isEmpty || name == '.' || name == '..') return null;

    if (name.length > 120) {
      final extension = p.extension(name);
      final base = p.basenameWithoutExtension(name);
      final maxBase = 120 - extension.length;
      name = '${base.substring(0, maxBase.clamp(1, base.length))}$extension';
    }

    return name;
  }

  /// Returns [file] or the next free `-1`, `-2`, ... sibling.
  File _uniqueDestination(File file) {
    if (!file.existsSync()) return file;

    final directory = p.dirname(file.path);
    final base = p.basenameWithoutExtension(file.path);
    final extension = p.extension(file.path);

    for (var index = 1; index < 1000; index++) {
      final candidate = File(p.join(directory, '$base-$index$extension'));
      if (!candidate.existsSync() && !File('${candidate.path}.part').existsSync()) {
        return candidate;
      }
    }

    throw const TransferException(
      'Could not find a free destination filename after 999 attempts.',
    );
  }

  /// Converts the physical file path back to a path relative to its mount.
  String _relativeToMount(
    HarnessFileSystem fileSystem,
    String storageTag,
    File file,
  ) {
    for (final tag in fileSystem.mounts.mountTags) {
      if (tag != storageTag) continue;
      final directory = fileSystem.resolveVirtualDir(tag);
      final relative = p.relative(file.path, from: directory.path);
      return relative.replaceAll('\\', '/');
    }
    return p.basename(file.path);
  }

  String _primaryMimeType(String? contentType) =>
      (contentType ?? '').split(';').first.trim().toLowerCase();

  bool _isAllowedMimeType(String mimeType) {
    if (mimeType == 'application/pdf') return true;
    return _allowedMimePrefixes.any(mimeType.startsWith);
  }

  String _extensionForMime(String mimeType) {
    const mapping = {
      'image/png': '.png',
      'image/jpeg': '.jpg',
      'image/gif': '.gif',
      'image/webp': '.webp',
      'image/svg+xml': '.svg',
      'audio/mpeg': '.mp3',
      'audio/mp4': '.m4a',
      'audio/wav': '.wav',
      'audio/ogg': '.ogg',
      'video/mp4': '.mp4',
      'video/webm': '.webm',
      'video/quicktime': '.mov',
      'application/pdf': '.pdf',
    };
    return mapping[mimeType] ?? '';
  }

  String _megabytes(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(0);

  bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  Future<void> _deleteQuietly(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

class _OpenedPage {
  final http.StreamedResponse response;
  final Map<String, String> headers;
  final Uri finalUri;

  const _OpenedPage({
    required this.response,
    required this.headers,
    required this.finalUri,
  });
}
