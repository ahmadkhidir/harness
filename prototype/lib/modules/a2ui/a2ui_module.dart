import '../../core/models/command_definition.dart';
import '../../core/models/system_response.dart';
import '../base/harness_module.dart';
import 'catalogs/a2ui_catalog.dart';
import 'catalogs/basic_v1_catalog.dart';

/// Agent-to-User Interface (A2UI) Module.
///
/// Implements FEAT-006:
/// - Provides `load_a2ui_catalog` to transiently inject UI component schemas into working context.
/// - Provides `send_a2ui` to dispatch declarative interactive A2UI surfaces to the chat view.
/// - Supports extensible catalog registry with built-in `basic/v1` catalog.
class A2UIModule extends HarnessModule {
  A2UIModule() {
    BasicV1Catalog.register();
  }

  @override
  String get moduleName => 'a2ui';

  @override
  List<CommandDefinition> get commands => [
        CommandDefinition(
          command: 'load_a2ui_catalog',
          description:
              'Loads declarative UI component schemas and documentation for the specified catalog (e.g. "basic/v1") transiently into working memory for the active turn.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'catalog': {
                'type': 'string',
                'description': 'Catalog identifier to load, e.g. "basic/v1".',
              },
            },
            'required': ['catalog'],
          },
        ),
        CommandDefinition(
          command: 'send_a2ui',
          description:
              'Dispatches declarative interactive A2UI widget surfaces to render natively in the mobile chat screen.',
          parametersSchema: const {
            'type': 'object',
            'properties': {
              'messages': {
                'type': 'array',
                'description':
                    'Ordered list of A2UI messages (createSurface, updateComponents, updateDataModel).',
              },
              'text': {
                'type': 'string',
                'description':
                    'Optional companion text to display alongside the A2UI widget surface.',
              },
            },
            'required': ['messages'],
          },
        ),
      ];

  @override
  Future<SystemResponse> executeCommand(
    String command,
    Map<String, dynamic> parameters,
  ) async {
    switch (command) {
      case 'load_a2ui_catalog':
        return _handleLoadCatalog(parameters);
      case 'send_a2ui':
        return _handleSendA2UI(parameters);
      default:
        return SystemResponse.error(
          command: command,
          errorMessage: 'Unrecognized A2UI command: "$command".',
        );
    }
  }

  SystemResponse _handleLoadCatalog(Map<String, dynamic> parameters) {
    final catalog = parameters['catalog'] as String?;
    if (catalog == null || catalog.trim().isEmpty) {
      return SystemResponse.error(
        command: 'load_a2ui_catalog',
        errorMessage: 'Missing required parameter "catalog".',
      );
    }

    final cleanCatalog = catalog.trim();
    final catalogDef = A2UICatalogRegistry.instance.get(cleanCatalog);
    if (catalogDef != null) {
      return SystemResponse.success(
        command: 'load_a2ui_catalog',
        data: catalogDef.documentation,
      );
    }

    final available = A2UICatalogRegistry.instance.allCatalogs
        .map((c) => c.aliases.isNotEmpty ? c.aliases.first : c.catalogId)
        .join(', ');

    return SystemResponse.error(
      command: 'load_a2ui_catalog',
      errorMessage:
          'Unsupported catalog "$cleanCatalog". Available catalogs: $available',
    );
  }

  SystemResponse _handleSendA2UI(Map<String, dynamic> parameters) {
    final messages = parameters['messages'];
    if (messages == null || messages is! List || messages.isEmpty) {
      return SystemResponse.error(
        command: 'send_a2ui',
        errorMessage: 'Invalid or missing "messages" list in A2UI payload.',
      );
    }

    return SystemResponse.success(
      command: 'send_a2ui',
      data: 'A2UI surface validated and dispatched successfully.',
    );
  }
}

