import 'dart:io';
import 'package:path/path.dart' as p;
import '../../core/models/installed_skill_package.dart';
import '../../core/models/skill_metadata.dart';
import '../../core/utils/file_system_manager.dart';

/// Service managing on-device skill packages stored in `<HarnessRoot>/skills/`.
///
/// Implements FEAT-003: On-Demand Transient Skill & Sub-File Loading:
/// - Discovers and indexes installed skill packages.
/// - Parses `SKILL.md` frontmatter into lightweight [SkillMetadata] catalogs.
/// - Excludes malformed packages (missing `SKILL.md`) from persistent prompt context.
/// - Safely loads root `SKILL.md` and auxiliary files (`references/`, `assets/`, `scripts/`)
///   with strict path-traversal sandboxing.
class SkillsService {
  final HarnessFileSystem? _explicitFileSystem;

  SkillsService({HarnessFileSystem? fileSystem})
      : _explicitFileSystem = fileSystem;

  /// Active filesystem manager, resolving explicitly injected instance or singleton.
  HarnessFileSystem? get fileSystem =>
      _explicitFileSystem ?? HarnessFileSystem.instance;

  /// Scans `<HarnessRoot>/skills/` and returns lightweight [SkillMetadata] entries
  /// for prompt injection.
  ///
  /// Malformed packages (missing `SKILL.md`) are excluded.
  List<SkillMetadata> scanAvailableSkills() {
    final fs = fileSystem;
    if (fs == null) return [];

    final dir = fs.skillsDir;
    if (!dir.existsSync()) return [];

    final available = <SkillMetadata>[];
    final entities = dir.listSync();

    for (final entity in entities) {
      if (entity is! Directory) continue;

      final dirName = p.basename(entity.path);
      final skillFile = File(p.join(entity.path, 'SKILL.md'));

      if (!skillFile.existsSync()) {
        continue; // Exclude malformed skill missing SKILL.md
      }

      try {
        final content = skillFile.readAsStringSync();
        final metadata = parseFrontmatter(content, dirName);
        if (metadata != null) {
          available.add(metadata);
        }
      } catch (_) {
        // Skip unparseable skills
      }
    }

    return available;
  }

  /// Scans all directories under `skills/` and returns detailed [InstalledSkillPackage]
  /// objects for UI inspection in Screen 4.
  List<InstalledSkillPackage> scanAllSkillPackages() {
    final fs = fileSystem;
    if (fs == null) return [];

    final dir = fs.skillsDir;
    if (!dir.existsSync()) return [];

    final packages = <InstalledSkillPackage>[];
    final entities = dir.listSync();

    for (final entity in entities) {
      if (entity is! Directory) continue;

      final dirName = p.basename(entity.path);
      final skillFile = File(p.join(entity.path, 'SKILL.md'));

      // Scan auxiliary files inside the skill directory (excluding SKILL.md)
      final auxiliary = <String>[];
      try {
        final allFiles = entity.listSync(recursive: true);
        for (final f in allFiles) {
          if (f is File) {
            final rel = p.relative(f.path, from: entity.path).replaceAll(r'\', '/');
            if (rel.toLowerCase() != 'skill.md') {
              auxiliary.add(rel);
            }
          }
        }
      } catch (_) {}

      if (!skillFile.existsSync()) {
        packages.add(InstalledSkillPackage(
          directoryName: dirName,
          isMalformed: true,
          malformedReason: 'Missing SKILL.md in skill package directory',
          auxiliaryFiles: auxiliary,
        ));
        continue;
      }

      try {
        final content = skillFile.readAsStringSync();
        final metadata = parseFrontmatter(content, dirName);
        if (metadata == null) {
          packages.add(InstalledSkillPackage(
            directoryName: dirName,
            isMalformed: true,
            malformedReason: 'Unable to parse valid frontmatter from SKILL.md',
            auxiliaryFiles: auxiliary,
            skillMdContent: content,
          ));
        } else {
          packages.add(InstalledSkillPackage(
            directoryName: dirName,
            metadata: metadata,
            isMalformed: false,
            auxiliaryFiles: auxiliary,
            skillMdContent: content,
          ));
        }
      } catch (e) {
        packages.add(InstalledSkillPackage(
          directoryName: dirName,
          isMalformed: true,
          malformedReason: 'Error reading SKILL.md: $e',
          auxiliaryFiles: auxiliary,
        ));
      }
    }

    return packages;
  }

  /// Reads and returns the content of `SKILL.md` for the specified skill package.
  ///
  /// Returns null if the skill or `SKILL.md` does not exist.
  String? readSkill(String skillName) {
    final fs = fileSystem;
    if (fs == null) return null;

    try {
      final file = fs.resolveSkillFile(skillName, 'SKILL.md');
      if (file.existsSync()) {
        return file.readAsStringSync();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Reads and returns an auxiliary file located within `references/`, `assets/`,
  /// or `scripts/` inside the skill directory.
  ///
  /// Enforces strict path canonicalization. Throws [SecurityException] if
  /// path traversal escapes the skill sandbox.
  String? readSkillFile(String skillName, String relativePath) {
    final fs = fileSystem;
    if (fs == null) return null;

    // resolveSkillFile checks p.isWithin and throws SecurityException on traversal
    final file = fs.resolveSkillFile(skillName, relativePath);
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
    return null;
  }

  /// Parses YAML frontmatter or Markdown headers from `SKILL.md` content.
  static SkillMetadata? parseFrontmatter(String content, String fallbackName) {
    final clean = content.trim();
    if (clean.isEmpty) return null;

    String? name;
    String? description;
    String? version;

    // Check for standard YAML frontmatter:
    // ---
    // name: ...
    // description: ...
    // version: ...
    // ---
    if (clean.startsWith('---')) {
      final endIndex = clean.indexOf('---', 3);
      if (endIndex != -1) {
        final yamlBlock = clean.substring(3, endIndex);
        final lines = yamlBlock.split(RegExp(r'\r?\n'));
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

          final colonIndex = trimmed.indexOf(':');
          if (colonIndex != -1) {
            final key = trimmed.substring(0, colonIndex).trim().toLowerCase();
            var value = trimmed.substring(colonIndex + 1).trim();
            if ((value.startsWith('"') && value.endsWith('"')) ||
                (value.startsWith("'") && value.endsWith("'"))) {
              value = value.substring(1, value.length - 1).trim();
            }

            if (key == 'name') {
              name = value;
            } else if (key == 'description') {
              description = value;
            } else if (key == 'version') {
              version = value;
            }
          }
        }
      }
    }

    // Markdown header fallback if YAML frontmatter missing
    if (name == null || description == null) {
      final lines = clean.split(RegExp(r'\r?\n'));
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('# ') && name == null) {
          name = trimmed.substring(2).trim();
        } else if (trimmed.isNotEmpty &&
            !trimmed.startsWith('#') &&
            !trimmed.startsWith('---') &&
            description == null) {
          description = trimmed;
        }
      }
    }

    name ??= fallbackName;
    name = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (name.isEmpty) name = fallbackName.toLowerCase();

    description ??= 'Custom skill: $name';
    if (description.length > 256) {
      description = '${description.substring(0, 253)}...';
    }
    version ??= '1.0.0';

    try {
      return SkillMetadata(
        name: name,
        description: description,
        version: version,
      );
    } catch (_) {
      return null;
    }
  }
}
