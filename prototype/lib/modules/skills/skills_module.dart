import '../../core/models/command_definition.dart';
import '../../core/models/system_response.dart';
import '../../core/utils/file_system_manager.dart';
import '../../data/services/skills_service.dart';
import '../base/harness_module.dart';

/// Module exposing on-demand transient skill loading commands for the agent.
///
/// Implements FEAT-003:
/// - `load_skill`: Dynamically loads root `SKILL.md` instructions into active turn context.
/// - `load_skill_file`: Dynamically loads auxiliary reference documents, schemas, or scripts
///   within `references/`, `assets/`, or `scripts/` with sandbox boundary enforcement.
class SkillsModule extends HarnessModule {
  final SkillsService skillsService;

  SkillsModule({SkillsService? skillsService})
      : skillsService = skillsService ?? SkillsService();

  @override
  String get moduleName => 'skills';

  @override
  List<CommandDefinition> get commands => [
        CommandDefinition(
          command: 'load_skill',
          description:
              'Dynamically loads the root SKILL.md instructions of an installed skill package into active working context.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'name': {
                'type': 'string',
                'description':
                    'Unique identifier of the installed skill package to load (e.g. "summarizer").',
              },
            },
            'required': ['name'],
          },
        ),
        CommandDefinition(
          command: 'load_skill_file',
          description:
              'Dynamically loads auxiliary reference documents, schemas, or scripts located within references/, assets/, or scripts/ of an installed skill package.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'name': {
                'type': 'string',
                'description': 'Unique identifier of the installed skill package.',
              },
              'path': {
                'type': 'string',
                'description':
                    'Relative path to the auxiliary file within the skill directory (e.g. "references/guide.md").',
              },
            },
            'required': ['name', 'path'],
          },
        ),
      ];

  @override
  Future<SystemResponse> executeCommand(
    String command,
    Map<String, dynamic> parameters,
  ) async {
    switch (command) {
      case 'load_skill':
        final name = parameters['name'] as String?;
        if (name == null || name.trim().isEmpty) {
          return SystemResponse.error(
            command: command,
            errorMessage: 'Missing required parameter "name"',
          );
        }

        try {
          final content = skillsService.readSkill(name.trim());
          if (content == null) {
            return SystemResponse.error(
              command: command,
              errorMessage: 'Skill or file not found',
            );
          }

          return SystemResponse.success(
            command: command,
            data: content,
          );
        } on SecurityException catch (e) {
          return SystemResponse.error(
            command: command,
            errorMessage: e.message,
          );
        } catch (_) {
          return SystemResponse.error(
            command: command,
            errorMessage: 'Skill or file not found',
          );
        }

      case 'load_skill_file':
        final name = parameters['name'] as String?;
        final path = parameters['path'] as String?;
        if (name == null || name.trim().isEmpty) {
          return SystemResponse.error(
            command: command,
            errorMessage: 'Missing required parameter "name"',
          );
        }
        if (path == null || path.trim().isEmpty) {
          return SystemResponse.error(
            command: command,
            errorMessage: 'Missing required parameter "path"',
          );
        }

        try {
          final content = skillsService.readSkillFile(name.trim(), path.trim());
          if (content == null) {
            return SystemResponse.error(
              command: command,
              errorMessage: 'Skill or file not found',
            );
          }

          return SystemResponse.success(
            command: command,
            data: content,
          );
        } on SecurityException catch (e) {
          return SystemResponse.error(
            command: command,
            errorMessage: e.message,
          );
        } catch (_) {
          return SystemResponse.error(
            command: command,
            errorMessage: 'Skill or file not found',
          );
        }

      default:
        return SystemResponse.error(
          command: command,
          errorMessage: 'Unknown command "$command" in module "$moduleName"',
        );
    }
  }
}

