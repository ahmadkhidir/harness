import 'dart:io';

import '../../../core/utils/file_system_manager.dart';

/// Resolved source for an A2UI media component.
///
/// Accepts remote `http(s)` URLs, absolute `file:` URIs, and virtual storage
/// paths such as `primary/projects/cover.png` (or a bare relative path, which
/// resolves inside `primary`). Local paths are canonicalized through the
/// Virtual Mount Table, so host filesystem paths never leak to the model.
class A2UIMediaSource {
  /// Original property value.
  final String raw;

  /// Remote URL when the source is networked.
  final String? networkUrl;

  /// Local file when the source resolves inside a registered storage volume.
  final File? file;

  const A2UIMediaSource._({
    required this.raw,
    this.networkUrl,
    this.file,
  });

  /// True when the value is empty or cannot be resolved.
  bool get isEmpty => networkUrl == null && file == null;

  /// True when the source points at a local file.
  bool get isLocal => file != null;

  /// Resolves [source] into a network URL or a local file.
  static A2UIMediaSource resolve(String source) {
    final raw = source.trim();
    if (raw.isEmpty) return const A2UIMediaSource._(raw: '');

    final uri = Uri.tryParse(raw);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return A2UIMediaSource._(raw: raw, networkUrl: raw);
    }
    if (uri != null && uri.isScheme('file')) {
      return A2UIMediaSource._(raw: raw, file: File.fromUri(uri));
    }

    var virtualPath = raw;
    const prefix = 'harness-file:';
    if (virtualPath.startsWith(prefix)) {
      virtualPath = virtualPath.substring(prefix.length);
    }

    final fileSystem = HarnessFileSystem.instance;
    if (fileSystem == null) return A2UIMediaSource._(raw: raw);

    try {
      return A2UIMediaSource._(
        raw: raw,
        file: fileSystem.resolveVirtualFile(virtualPath),
      );
    } catch (_) {
      return A2UIMediaSource._(raw: raw);
    }
  }
}
