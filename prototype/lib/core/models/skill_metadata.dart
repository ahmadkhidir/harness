/// Metadata descriptor for an installed skill package.
///
/// Parsed from `<AppDocuments>/Harness/skills/<name>/SKILL.md` frontmatter and included
/// in the persistent `available_skills` prompt catalog. Directory location is deterministically
/// derived from [name] (`<AppDocuments>/Harness/skills/<name>/`).
/// Conforms to JSON Schema `https://harness.agent/schemas/skill-metadata.schema.json`.
class SkillMetadata {
  /// Strict kebab-case regex pattern: lower-case alphanumeric segments joined by single hyphens.
  static final RegExp _namePattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

  /// Unique kebab-case name of the skill matching its directory name under `skills/`.
  final String name;

  /// One-line summary of what the skill does (max 256 characters), used by the model for routing.
  final String description;

  /// Semantic version string, e.g. `1.0.0`.
  final String version;

  /// True when the skill is a built-in package that the UI treats as read-only.
  ///
  /// This is a UX lock only. The skill lives in user-accessible storage and can
  /// still be edited manually; the app never treats it as a security boundary.
  final bool isLocked;

  SkillMetadata({
    required this.name,
    required this.description,
    required this.version,
    this.isLocked = false,
  }) {
    // Strictly enforce kebab-case matching the filesystem folder naming rule.
    // This guarantees safe directory resolution without special characters or path separators.
    if (!_namePattern.hasMatch(name)) {
      throw ArgumentError(
        'Skill name "$name" must be lower-case kebab-case matching pattern ^[a-z0-9]+(-[a-z0-9]+)*\$.',
      );
    }
    if (description.length > 256) {
      throw ArgumentError('description cannot exceed 256 characters.');
    }
    if (version.trim().isEmpty) {
      throw ArgumentError('version cannot be empty.');
    }
  }

  /// Serializes the skill metadata to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'version': version,
      if (isLocked) 'isLocked': true,
    };
  }

  /// Deserializes skill metadata from a JSON map.
  factory SkillMetadata.fromJson(Map<String, dynamic> json) {
    return SkillMetadata(
      name: json['name'] as String,
      description: json['description'] as String,
      version: json['version'] as String? ?? '1.0.0',
      isLocked: json['isLocked'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillMetadata &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          version == other.version &&
          isLocked == other.isLocked;

  @override
  int get hashCode => name.hashCode ^ version.hashCode ^ isLocked.hashCode;
}
