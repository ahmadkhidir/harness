import '../../core/models/command_definition.dart';
import '../../core/models/system_response.dart';
import '../base/harness_module.dart';
import 'catalogs/basic_v1_catalog.dart';

/// Agent-to-User Interface (A2UI) Module.
///
/// Implements FEAT-006:
/// - Provides `load_a2ui_catalog` to transiently inject UI component schemas into working context.
/// - Provides `send_a2ui` to dispatch declarative interactive A2UI surfaces to the chat view.
/// - Supports on-demand component catalog `basic/v1`.
class A2UIModule extends HarnessModule {
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
    if (cleanCatalog == 'basic/v1') {
      return SystemResponse.success(
        command: 'load_a2ui_catalog',
        data: kBasicV1CatalogDocumentation,
      );
    }

    return SystemResponse.error(
      command: 'load_a2ui_catalog',
      errorMessage:
          'Unsupported catalog "$cleanCatalog". Available catalogs: basic/v1',
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
