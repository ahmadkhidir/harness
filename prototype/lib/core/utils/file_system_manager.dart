import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Exception thrown when a file operation attempts directory traversal outside authorized sandboxes.
class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);

  @override
  String toString() => 'SecurityException: $message';
}

/// Central filesystem and sandbox manager for Harness.
///
/// Implements the unified on-device filesystem layout specified in `docs/Harness/architecture.md`:
/// ```text
/// <AppDocumentsDirectory>/Harness/
///   ├── database/harness_app.db
///   ├── skills/<skill_name>/ (SKILL.md, references/, assets/, scripts/)
///   ├── storage/ (workspace/, downloads/)
///   └── sessions/<session_id>/ (turns.json, context.txt)
/// ```
class HarnessFileSystem {
  /// The root directory for all Harness data: `<AppDocuments>/Harness/`.
  final Directory rootDir;

  HarnessFileSystem({required this.rootDir});

  /// Initializes the Harness filesystem structure under [customRoot] (for testing)
  /// or defaults to the OS application documents directory.
  static Future<HarnessFileSystem> init([Directory? customRoot]) async {
    final baseDir = customRoot ?? await getApplicationDocumentsDirectory();
    final harnessRoot = Directory(p.join(baseDir.path, 'Harness'));
    if (!await harnessRoot.exists()) {
      await harnessRoot.create(recursive: true);
    }

    final fs = HarnessFileSystem(rootDir: harnessRoot);
    await fs.ensureBaseDirectories();
    return fs;
  }

  /// Directory holding the local SQLite database (`harness_app.db`).
  Directory get databaseDir => Directory(p.join(rootDir.path, 'database'));

  /// Directory holding installed skill packages (`skills/<skill_name>/`).
  Directory get skillsDir => Directory(p.join(rootDir.path, 'skills'));

  /// Sandboxed root directory for all agent working files (`storage/`).
  Directory get storageDir => Directory(p.join(rootDir.path, 'storage'));

  /// Sandboxed workspace subdirectory for working files (`storage/workspace/`).
  Directory get workspaceDir => Directory(p.join(storageDir.path, 'workspace'));

  /// Sandboxed downloads subdirectory for fetch outputs (`storage/downloads/`).
  Directory get downloadsDir => Directory(p.join(storageDir.path, 'downloads'));

  /// Root directory holding all isolated session folders (`sessions/<id>/`).
  Directory get sessionsDir => Directory(p.join(rootDir.path, 'sessions'));

  /// File reference to the local SQLite database file.
  File get dbFile => File(p.join(databaseDir.path, 'harness_app.db'));

  /// Ensures that all foundational directories in the layout exist on disk.
  Future<void> ensureBaseDirectories() async {
    await databaseDir.create(recursive: true);
    await skillsDir.create(recursive: true);
    await storageDir.create(recursive: true);
    await workspaceDir.create(recursive: true);
    await downloadsDir.create(recursive: true);
    await sessionsDir.create(recursive: true);
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
  /// Throws a [SecurityException] if the relative path resolves outside `storage/`.
  File resolveStorageFile(String relativePath) {
    final canonicalBase = p.canonicalize(storageDir.path);
    final targetPath = p.canonicalize(p.join(storageDir.path, relativePath));

    // Ensure any path starting with `..` or root slashes cannot reach
    // files outside the storage sandbox.
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
