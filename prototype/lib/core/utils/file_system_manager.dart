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

  /// Resolves a file path strictly jailed within the `storage/` directory or virtual mounts.
  ///
  /// Throws a [SecurityException] if the relative path resolves outside authorized mounts.
  File resolveStorageFile(String relativePath) {
    return mounts.resolveVirtualFile(relativePath);
  }

  /// Resolves a directory path strictly jailed within the `storage/` directory or virtual mounts.
  Directory resolveStorageDir([String relativePath = '']) {
    return mounts.resolveVirtualDir(relativePath);
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

    final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) {
      return (_mounts['primary']!, '');
    }

    final firstSegment = segments.first;
    if (_mounts.containsKey(firstSegment)) {
      final subPath = segments.skip(1).join('/');
      return (_mounts[firstSegment]!, subPath);
    }

    // Default to primary mount if tag is not an explicit registered mount tag
    return (_mounts['primary']!, normalized);
  }

  /// Formats the virtual filesystem tree representation for model prompt injection,
  /// completely concealing host operating system paths.
  String formatFilesystemTree() {
    final buffer = StringBuffer();
    buffer.writeln('<filesystem>');
    for (final entry in _mounts.entries) {
      final tag = entry.key;
      final dir = entry.value;
      buffer.writeln('$tag/');
      if (dir.existsSync()) {
        try {
          final entities = dir.listSync(recursive: false);
          if (entities.isEmpty) {
            buffer.writeln('  (empty)');
          } else {
            for (final entity in entities) {
              final name = p.basename(entity.path);
              final isDir = entity is Directory;
              buffer.writeln('  ├── $name${isDir ? '/' : ''}');
            }
          }
        } catch (_) {
          buffer.writeln('  (empty)');
        }
      } else {
        buffer.writeln('  (empty)');
      }
    }
    buffer.write('</filesystem>');
    return buffer.toString();
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
