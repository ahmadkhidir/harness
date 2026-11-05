import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../data/database/app_database.dart';

/// Exception thrown when a file operation attempts directory traversal outside authorized sandboxes.
class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);

  @override
  String toString() => 'SecurityException: $message';
}

/// Exception thrown when a virtual path references an unmounted or unknown storage volume tag.
class UnknownVolumeException implements Exception {
  final String message;
  UnknownVolumeException(this.message);

  @override
  String toString() => 'UnknownVolumeException: $message';
}

/// Central filesystem and sandbox manager for Harness.
///
/// Implements the unified on-device filesystem layout:
/// ```text
/// <HarnessRoot>/
///   ├── data/
///   │     └── models/ (LiteRT-LM weights)
///   ├── storage/ (primary clean user workspace, virtual tag "primary/")
///   ├── skills/<skill_name>/ (SKILL.md, references/, assets/, scripts/)
///   └── sessions/<session_id>/ (turns.json, context.txt)
/// ```
class HarnessFileSystem {
  /// Global singleton instance for convenient resolution across services.
  static HarnessFileSystem? instance;

  /// The root directory for all Harness data: `<HarnessRoot>/`.
  final Directory rootDir;

  /// The virtual mount table managing sandbox mounts (primary, external folders)
  /// with zero host path leakage.
  late final VirtualMountTable mounts;

  /// Active session identifier for the current agent context.
  String? activeSessionId;

  HarnessFileSystem({required this.rootDir}) {
    mounts = VirtualMountTable(primaryDir: storageDir);
    instance = this;
  }

  /// Initializes the Harness filesystem structure under [customRoot] (for testing)
  /// or resolves the user-selected or OS-specific top-level root directory:
  /// - User-persisted root: `<UserSelectedPath>/Harness` (via folder picker)
  /// - iOS: `<AppDocumentsDirectory>` (exposed via Apple Files app UIFileSharingEnabled)
  /// - Default fallback: `<AppDocumentsDirectory>/Harness`
  static Future<HarnessFileSystem> init([
    Directory? customRoot,
    AppDatabase? database,
  ]) async {
    Directory harnessRoot;

    if (customRoot != null) {
      harnessRoot = p.basename(customRoot.path) == 'Harness'
          ? customRoot
          : Directory(p.join(customRoot.path, 'Harness'));
    } else {
      // Check if user has a persisted root path in secure storage:
      final db = database ?? AppDatabase();
      final persistedPath = await db.getRootPath();
      if (persistedPath != null && persistedPath.isNotEmpty) {
        harnessRoot = p.basename(persistedPath) == 'Harness'
            ? Directory(persistedPath)
            : Directory(p.join(persistedPath, 'Harness'));
      } else if (Platform.isIOS) {
        final baseDir = await getApplicationDocumentsDirectory();
        harnessRoot = baseDir;
      } else {
        final baseDir = await getApplicationDocumentsDirectory();
        harnessRoot = Directory(p.join(baseDir.path, 'Harness'));
      }
    }

    if (!harnessRoot.existsSync()) {
      harnessRoot.createSync(recursive: true);
    }

    final fs = HarnessFileSystem(rootDir: harnessRoot);
    fs.ensureBaseDirectoriesSync();

    // Re-hydrate any external workspace mounts persisted by the user:
    try {
      final db = database ?? AppDatabase();
      final externalMounts = await db.getExternalMounts();
      for (final entry in externalMounts.entries) {
        final dir = Directory(entry.value);
        if (dir.existsSync()) {
          fs.mounts.registerMount(entry.key, dir);
        }
      }
    } catch (_) {}

    instance = fs;
    return fs;
  }

  /// Top-level internal engine directory (`data/`) holding models.
  Directory get dataDir => Directory(p.join(rootDir.path, 'data'));

  /// Directory holding downloaded on-device SLM weights (`data/models/`).
  Directory get modelsDir => Directory(p.join(dataDir.path, 'models'));

  /// Sandboxed primary user workspace directory (`storage/`).
  Directory get storageDir => Directory(p.join(rootDir.path, 'storage'));

  /// Directory holding installed skill packages (`skills/<skill_name>/`).
  Directory get skillsDir => Directory(p.join(rootDir.path, 'skills'));

  /// Root directory holding all isolated session folders (`sessions/<id>/`).
  Directory get sessionsDir => Directory(p.join(rootDir.path, 'sessions'));

  /// Deprecated helper: returns the primary storage directory.
  @Deprecated('Use storageDir directly. User files reside directly in storage/.')
  Directory get workspaceDir => storageDir;

  /// Deprecated helper: returns the cache directory under data/.
  @Deprecated('Use storageDir directly.')
  Directory get downloadsDir => storageDir;

  /// Deprecated helper: SQLite database has been removed in favor of FlutterSecureStorage.
  @Deprecated('SQLite database has been removed in favor of FlutterSecureStorage.')
  Directory get databaseDir => Directory(p.join(dataDir.path, 'database'));

  /// Deprecated helper: Cache directory removed.
  @Deprecated('Cache directory removed.')
  Directory get cacheDir => Directory(p.join(dataDir.path, 'cache'));

  /// Deprecated helper: SQLite database has been removed in favor of FlutterSecureStorage.
  @Deprecated('SQLite database has been removed in favor of FlutterSecureStorage.')
  File get dbFile => File(p.join(databaseDir.path, 'harness_app.db'));

  /// Ensures that all foundational directories in the layout exist on disk.
  Future<void> ensureBaseDirectories() async {
    ensureBaseDirectoriesSync();
  }

  /// Synchronously ensures all foundational directories exist on disk.
  void ensureBaseDirectoriesSync() {
    dataDir.createSync(recursive: true);
    modelsDir.createSync(recursive: true);
    storageDir.createSync(recursive: true);
    skillsDir.createSync(recursive: true);
    sessionsDir.createSync(recursive: true);
  }

  /// Resolves an on-device model weight file inside `data/models/`.
  File modelFile(String fileName) {
    final clean = fileName.trim();
    _validatePathSegment(clean, 'fileName');
    return File(p.join(modelsDir.path, clean));
  }

  /// Resolves an in-progress on-device model download part file (`data/models/<fileName>.part`).
  File modelPartFile(String fileName) {
    final clean = fileName.trim();
    _validatePathSegment(clean, 'fileName');
    return File(p.join(modelsDir.path, '$clean.part'));
  }

  /// Returns the isolated directory for a specific session ID.
  Directory sessionDir(String sessionId) {
    _validatePathSegment(sessionId, 'sessionId');
    return Directory(p.join(sessionsDir.path, sessionId));
  }

  /// Returns the `turns.json` audit file for a specific session.
  File sessionTurnsFile(String sessionId) {
    return File(p.join(sessionDir(sessionId).path, 'turns.json'));
  }

  /// Returns the `context.txt` line transcript file for a specific session.
  File sessionContextFile(String sessionId) {
    return File(p.join(sessionDir(sessionId).path, 'context.txt'));
  }

  /// Returns the package directory for a specific skill.
  Directory skillDir(String skillName) {
    _validatePathSegment(skillName, 'skillName');
    return Directory(p.join(skillsDir.path, skillName));
  }

  /// Resolves an auxiliary file within a skill package (`SKILL.md`, `references/`, etc.)
  /// with strict path canonicalization to prevent path traversal attacks.
  File resolveSkillFile(String skillName, [String relativePath = 'SKILL.md']) {
    final sDir = skillDir(skillName);
    final canonicalBase = p.canonicalize(sDir.path);
    final targetPath = p.canonicalize(p.join(sDir.path, relativePath));

    // Canonicalize paths to detect and block directory traversal attempts
    // (e.g. "../../database/harness_app.db") before accessing the filesystem.
    if (!p.isWithin(canonicalBase, targetPath) && canonicalBase != targetPath) {
      throw SecurityException(
        'Access denied: Path "$relativePath" escapes the skill "$skillName" sandbox.',
      );
    }
    return File(targetPath);
  }

  /// Resolves a file path strictly jailed within the `storage/` directory.
  ///
  /// Throws a [SecurityException] if the relative path resolves outside the storage sandbox.
  File resolveStorageFile(String relativePath) {
    final canonicalBase = p.canonicalize(storageDir.path);
    final targetPath = p.canonicalize(p.join(storageDir.path, relativePath));

    if (!p.isWithin(canonicalBase, targetPath) && canonicalBase != targetPath) {
      throw SecurityException(
        'Access denied: Path "$relativePath" escapes the storage sandbox.',
      );
    }
    return File(targetPath);
  }

  /// Resolves a directory path strictly jailed within the `storage/` directory.
  Directory resolveStorageDir([String relativePath = '']) {
    final canonicalBase = p.canonicalize(storageDir.path);
    final targetPath = p.canonicalize(p.join(storageDir.path, relativePath));

    if (!p.isWithin(canonicalBase, targetPath) && canonicalBase != targetPath) {
      throw SecurityException(
        'Access denied: Directory "$relativePath" escapes the storage sandbox.',
      );
    }
    return Directory(targetPath);
  }

  /// Resolves a virtual file path (e.g. `primary/notes.txt` or `downloads/data.csv`).
  File resolveVirtualFile(String virtualPath) => mounts.resolveVirtualFile(virtualPath);

  /// Resolves a virtual directory path (e.g. `primary/docs` or `downloads/`).
  Directory resolveVirtualDir([String virtualPath = 'primary']) => mounts.resolveVirtualDir(virtualPath);

  /// Formats the virtual filesystem tree (`<filesystem>...`) for prompt injection with zero host path leakage.
  String formatFilesystemTree() => mounts.formatFilesystemTree();

  /// Validates that an ID or folder name segment contains no path separators or traversal characters.
  void _validatePathSegment(String segment, String fieldName) {
    if (segment.isEmpty ||
        segment.contains('/') ||
        segment.contains('\\') ||
        segment.contains('..')) {
      throw SecurityException(
        'Invalid $fieldName: "$segment". Path traversal characters are prohibited.',
      );
    }
  }
}

/// Manages virtual filesystem mounts, mapping virtual mount tags (e.g. `primary`, `downloads`)
/// to physical directories while ensuring zero host path leakage to the LLM model.
class VirtualMountTable {
  final Map<String, Directory> _mounts = {};

  VirtualMountTable({required Directory primaryDir}) {
    _mounts['primary'] = primaryDir;
  }

  /// Registers an additional named directory mount (e.g., `downloads`, `sdcard`).
  void registerMount(String tag, Directory directory) {
    _validateTag(tag);
    _mounts[tag] = directory;
  }

  /// Unregisters an existing mount. Cannot unregister the default `primary` mount.
  void unregisterMount(String tag) {
    if (tag == 'primary') {
      throw ArgumentError('Cannot unregister the default primary mount.');
    }
    _mounts.remove(tag);
  }

  /// Returns the registered mount tags.
  List<String> get mountTags => List.unmodifiable(_mounts.keys);

  /// Checks if a named mount tag is registered.
  bool hasMount(String tag) => _mounts.containsKey(tag);

  /// Converts a physical file or directory path back to its virtual path representation
  /// (e.g. `<HarnessRoot>/storage/notes.txt` -> `primary/notes.txt`).
  ///
  /// Strictly prevents host operating system paths from leaking into engine outputs
  /// while preserving original file casing.
  String toVirtualPath(FileSystemEntity entity) {
    final canonicalEntity = p.canonicalize(entity.path);
    for (final entry in _mounts.entries) {
      final canonicalMount = p.canonicalize(entry.value.path);
      if (canonicalEntity == canonicalMount) {
        return entry.key;
      }
      if (p.isWithin(canonicalMount, canonicalEntity)) {
        final mountLen = canonicalMount.length;
        String rawRel = canonicalEntity.length > mountLen
            ? entity.path.substring(entity.path.length - (canonicalEntity.length - mountLen))
            : p.basename(entity.path);
        if (rawRel.startsWith(r'\') || rawRel.startsWith('/')) {
          rawRel = rawRel.substring(1);
        }
        final normalized = rawRel.replaceAll('\\', '/');
        return '${entry.key}/$normalized';
      }
    }
    // Fallback: if not within any mount, return just the basename under primary
    return 'primary/${p.basename(entity.path)}';
  }

  /// Resolves a virtual path (e.g. `primary/notes.txt` or `downloads/data.csv`)
  /// to its physical [File] on disk, strictly jailed within the mounted directory.
  File resolveVirtualFile(String virtualPath) {
    final (mountDir, relativePath) = _resolveMount(virtualPath);
    final canonicalBase = p.canonicalize(mountDir.path);
    final targetPath = p.canonicalize(p.join(mountDir.path, relativePath));

    if (!p.isWithin(canonicalBase, targetPath) && canonicalBase != targetPath) {
      throw SecurityException(
        'Access denied: Path "$virtualPath" escapes the mount sandbox.',
      );
    }
    return File(targetPath);
  }

  /// Resolves a virtual directory path (e.g. `primary/docs`)
  /// to its physical [Directory] on disk, strictly jailed within the mounted directory.
  Directory resolveVirtualDir(String virtualPath) {
    final (mountDir, relativePath) = _resolveMount(virtualPath);
    final canonicalBase = p.canonicalize(mountDir.path);
    final targetPath = p.canonicalize(p.join(mountDir.path, relativePath));

    if (!p.isWithin(canonicalBase, targetPath) && canonicalBase != targetPath) {
      throw SecurityException(
        'Access denied: Directory "$virtualPath" escapes the mount sandbox.',
      );
    }
    return Directory(targetPath);
  }

  /// Parses `virtualPath` into its (mountDirectory, relativeSubPath).
  /// If no tag prefix is supplied (e.g. `notes.txt`), defaults to `primary`.
  (Directory, String) _resolveMount(String virtualPath) {
    final normalized = virtualPath.replaceAll('\\', '/').trim();
    if (normalized.isEmpty) {
      final primary = _mounts['primary'];
      if (primary == null) throw StateError('Primary mount not found.');
      return (primary, '');
    }

    var cleanPath = normalized;
    if (cleanPath.startsWith('/')) {
      cleanPath = cleanPath.substring(1);
    }

    final segments = cleanPath.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      return (_mounts['primary']!, '');
    }

    final firstSegment = segments.first;
    if (_mounts.containsKey(firstSegment)) {
      final subPath = segments.skip(1).join('/');
      return (_mounts[firstSegment]!, subPath);
    }

    // If there are multiple segments (e.g. "unknown_vol/data.csv") and firstSegment is neither
    // a registered mount tag nor an existing folder/file in primary, treat it as an unknown volume tag.
    if (segments.length > 1) {
      final primary = _mounts['primary']!;
      final primarySubItem = p.join(primary.path, firstSegment);
      if (!Directory(primarySubItem).existsSync() && !File(primarySubItem).existsSync()) {
        throw UnknownVolumeException(
          "Unknown storage volume '$firstSegment'. Available volumes: ${_mounts.keys.join(', ')}",
        );
      }
    }

    // Default to primary mount if tag is not an explicit registered mount tag
    return (_mounts['primary']!, cleanPath);
  }

  /// Formats the virtual filesystem tree representation for model prompt injection,
  /// completely concealing host operating system paths.
  String formatFilesystemTree() {
    final buffer = StringBuffer();
    buffer.writeln('<filesystem>');
    for (final entry in _mounts.entries) {
      final tag = entry.key;
      final dir = entry.value;
      buffer.writeln('- $tag/');
      if (dir.existsSync()) {
        try {
          final entities = _sortedDirectoryEntities(dir);
          if (entities.isEmpty) {
            buffer.writeln('    (empty)');
          } else {
            _formatTreeLevel(entities, buffer, prefix: '    ', currentDepth: 1, maxDepth: 4);
          }
        } catch (_) {
          buffer.writeln('    (empty)');
        }
      } else {
        buffer.writeln('    (empty)');
      }
    }
    buffer.write('</filesystem>');
    return buffer.toString();
  }

  static List<FileSystemEntity> _sortedDirectoryEntities(Directory dir) {
    final list = dir.listSync(recursive: false);
    list.sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir != bIsDir) {
        return aIsDir ? -1 : 1;
      }
      return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
    });
    return list;
  }

  static void _formatTreeLevel(
    List<FileSystemEntity> entities,
    StringBuffer buffer, {
    required String prefix,
    required int currentDepth,
    required int maxDepth,
  }) {
    for (int i = 0; i < entities.length; i++) {
      final entity = entities[i];
      final isLast = i == entities.length - 1;
      final branch = isLast ? '└── ' : '├── ';
      final name = p.basename(entity.path);

      if (entity is Directory) {
        buffer.writeln('$prefix$branch$name/');
        if (currentDepth < maxDepth) {
          try {
            final children = _sortedDirectoryEntities(entity);
            if (children.isNotEmpty) {
              final nextPrefix = prefix + (isLast ? '    ' : '│   ');
              _formatTreeLevel(
                children,
                buffer,
                prefix: nextPrefix,
                currentDepth: currentDepth + 1,
                maxDepth: maxDepth,
              );
            }
          } catch (_) {}
        }
      } else {
        buffer.writeln('$prefix$branch$name');
      }
    }
  }

  void _validateTag(String tag) {
    if (tag.isEmpty ||
        tag.contains('/') ||
        tag.contains('\\') ||
        tag.contains('..') ||
        tag.contains(' ')) {
      throw ArgumentError('Invalid mount tag: "$tag". Must be a single alphanumeric tag name.');
    }
  }
}
