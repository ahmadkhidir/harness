import 'skill_metadata.dart';

/// Representation of an installed skill package on disk, including its parsed metadata,
/// auxiliary sub-files, and malformed validation status.
class InstalledSkillPackage {
  /// Directory name under `<HarnessRoot>/skills/`.
  final String directoryName;

  /// Parsed metadata if `SKILL.md` is valid.
  final SkillMetadata? metadata;

  /// True if the package directory is missing `SKILL.md` or has unparseable metadata.
  final bool isMalformed;

  /// Human-readable explanation if [isMalformed] is true.
  final String? malformedReason;

  /// Relative paths to auxiliary files within the skill package (references/, assets/, scripts/).
  final List<String> auxiliaryFiles;

  /// Full text content of `SKILL.md` if loaded.
  final String? skillMdContent;

  const InstalledSkillPackage({
    required this.directoryName,
    this.metadata,
    this.isMalformed = false,
    this.malformedReason,
    this.auxiliaryFiles = const [],
    this.skillMdContent,
  });

  /// Display name of the skill, falling back to directory name.
  String get displayName => metadata?.name ?? directoryName;

  /// Description of the skill, falling back to malformed reason.
  String get description =>
      metadata?.description ?? (malformedReason ?? 'Malformed skill package');

  /// Semantic version string.
  String get version => metadata?.version ?? '1.0.0';

  /// Number of auxiliary reference, asset, or script files.
  int get subFileCount => auxiliaryFiles.length;
}

