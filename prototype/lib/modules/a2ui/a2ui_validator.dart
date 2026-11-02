import '../../core/schema/json_schema_validator.dart';

/// Result of validating and normalizing an A2UI payload.
class A2UIValidationResult {
  /// Whether the payload is structurally valid and contains renderable components.
  final bool isValid;

  /// Human-readable error message explaining why validation failed, or null if valid.
  final String? errorMessage;

  /// Detailed list of schema errors pinpointed to their JSON Pointer paths.
  final List<JsonSchemaError> errors;

  /// Resolved surface ID (e.g. "main").
  final String? surfaceId;

  /// Resolved catalog identifier (e.g. "basic/v1" or canonical URL).
  final String? catalogId;

  /// Map of component ID to normalized component definition.
  final Map<String, Map<String, dynamic>> componentsMap;

  /// Normalized runtime data model key-value dictionary.
  final Map<String, dynamic> dataModel;

  /// ID of the resolved root component.
  final String? rootComponentId;

  const A2UIValidationResult({
    required this.isValid,
    this.errorMessage,
    this.errors = const [],
    this.surfaceId,
    this.catalogId,
    this.componentsMap = const {},
    this.dataModel = const {},
    this.rootComponentId,
  });

  factory A2UIValidationResult.failure(
    String errorMessage, {
    String? surfaceId,
    List<JsonSchemaError> errors = const [],
  }) {
    return A2UIValidationResult(
      isValid: false,
      errorMessage: errorMessage,
      errors: errors,
      surfaceId: surfaceId,
    );
  }
}

/// Normalizes and validates incoming A2UI payloads against schema specifications.
class A2UIValidator {
  /// Base schema for top-level send_a2ui payload
  static const Map<String, dynamic> kPayloadSchema = {
    'type': 'object',
    'required': ['messages'],
    'properties': {
      'messages': {
        'type': 'array',
        'minItems': 1,
      },
      'text': {'type': 'string'},
    },
  };

  /// Validates [payload] and returns a structured [A2UIValidationResult].
  static A2UIValidationResult validate(Map<String, dynamic>? payload) {
    if (payload == null) {
      return A2UIValidationResult.failure(
        'A2UI payload is null. A valid send_a2ui call must contain a "messages" list.',
        errors: const [
          JsonSchemaError(
            path: '/parameters',
            message: 'A2UI payload is null.',
            keyword: 'required',
          ),
        ],
      );
    }

    // Step 1: Validate top-level schema
    final schemaRes = JsonSchemaValidator.validate(payload, kPayloadSchema, rootPath: '/parameters');
    if (!schemaRes.isValid) {
      return A2UIValidationResult.failure(
        schemaRes.formatErrorSummary(contextName: 'send_a2ui'),
        errors: schemaRes.errors,
      );
    }

    final rawMessages = payload['messages'] as List;
    final schemaErrors = <JsonSchemaError>[];

    String? surfaceId;
    String? catalogId;
    final componentsMap = <String, Map<String, dynamic>>{};
    final dataModel = <String, dynamic>{};

    for (int msgIdx = 0; msgIdx < rawMessages.length; msgIdx++) {
      final msgItem = rawMessages[msgIdx];
      final msgPath = '/messages/$msgIdx';

      if (msgItem is! Map) {
        schemaErrors.add(JsonSchemaError(
          path: msgPath,
          message: 'Expected message object but got ${msgItem.runtimeType}.',
          keyword: 'type',
        ));
        continue;
      }

      final msg = Map<String, dynamic>.from(msgItem);

      // Handle createSurface
      if (msg.containsKey('createSurface')) {
        final createRaw = msg['createSurface'];
        if (createRaw is Map) {
          final create = Map<String, dynamic>.from(createRaw);
          if (create['surfaceId'] != null) {
            surfaceId = create['surfaceId']?.toString();
          }
          if (create['catalogId'] != null) {
            catalogId = create['catalogId']?.toString();
          }

          if (create.containsKey('components')) {
            if (create['components'] is List) {
              _extractAndValidateComponents(
                create['components'] as List,
                '$msgPath/createSurface/components',
                componentsMap,
                schemaErrors,
              );
            } else {
              schemaErrors.add(JsonSchemaError(
                path: '$msgPath/createSurface/components',
                message: 'Expected components list but got ${create['components'].runtimeType}.',
                keyword: 'type',
              ));
            }
          }

          if (create.containsKey('dataModel') && create['dataModel'] is Map) {
            dataModel.addAll(Map<String, dynamic>.from(create['dataModel'] as Map));
          }
        } else {
          schemaErrors.add(JsonSchemaError(
            path: '$msgPath/createSurface',
            message: 'Expected createSurface object but got ${createRaw.runtimeType}.',
            keyword: 'type',
          ));
        }
      }

      // Handle updateComponents
      if (msg.containsKey('updateComponents')) {
        final ucRaw = msg['updateComponents'];
        if (ucRaw is Map) {
          final uc = Map<String, dynamic>.from(ucRaw);
          if (surfaceId == null && uc['surfaceId'] != null) {
            surfaceId = uc['surfaceId']?.toString();
          }
          if (uc.containsKey('components')) {
            if (uc['components'] is List) {
              _extractAndValidateComponents(
                uc['components'] as List,
                '$msgPath/updateComponents/components',
                componentsMap,
                schemaErrors,
              );
            } else {
              schemaErrors.add(JsonSchemaError(
                path: '$msgPath/updateComponents/components',
                message: 'Expected components list but got ${uc['components'].runtimeType}.',
                keyword: 'type',
              ));
            }
          }
        }
      }

      // Handle updateDataModel
      if (msg.containsKey('updateDataModel')) {
        final dmRaw = msg['updateDataModel'];
        if (dmRaw is Map) {
          final dm = Map<String, dynamic>.from(dmRaw);
          if (surfaceId == null && dm['surfaceId'] != null) {
            surfaceId = dm['surfaceId']?.toString();
          }
          if (dm['value'] != null && dm['value'] is Map) {
            dataModel.addAll(Map<String, dynamic>.from(dm['value'] as Map));
          }
        }
      }
    }

    if (schemaErrors.isNotEmpty) {
      final summary = JsonSchemaValidationResult.failure(schemaErrors)
          .formatErrorSummary(contextName: 'send_a2ui');
      return A2UIValidationResult.failure(summary, errors: schemaErrors, surfaceId: surfaceId);
    }

    surfaceId ??= 'main';

    if (componentsMap.isEmpty) {
      return A2UIValidationResult.failure(
        'No components defined for surface "$surfaceId". Specify components inside "createSurface.components" or "updateComponents.components".',
        surfaceId: surfaceId,
        errors: [
          JsonSchemaError(
            path: '/messages/0/createSurface/components',
            message: 'No components defined for surface "$surfaceId".',
            keyword: 'minItems',
          ),
        ],
      );
    }

    final rootId = _findRootComponentId(componentsMap);
    if (rootId == null || !componentsMap.containsKey(rootId)) {
      return A2UIValidationResult.failure(
        'Cannot resolve root component for surface "$surfaceId". Define an element with id: "root" or ensure the root container is not a child of any other component.',
        surfaceId: surfaceId,
        errors: [
          JsonSchemaError(
            path: '/components',
            message: 'Cannot resolve root component for surface "$surfaceId".',
            keyword: 'required',
          ),
        ],
      );
    }

    return A2UIValidationResult(
      isValid: true,
      surfaceId: surfaceId,
      catalogId: catalogId ?? 'basic/v1',
      componentsMap: Map.unmodifiable(componentsMap),
      dataModel: Map.unmodifiable(dataModel),
      rootComponentId: rootId,
    );
  }

  static void _extractAndValidateComponents(
    List comps,
    String basePath,
    Map<String, Map<String, dynamic>> componentsMap,
    List<JsonSchemaError> schemaErrors,
  ) {
    for (int i = 0; i < comps.length; i++) {
      final c = comps[i];
      final compPath = '$basePath/$i';

      if (c is! Map) {
        schemaErrors.add(JsonSchemaError(
          path: compPath,
          message: 'Expected component object but got ${c.runtimeType}.',
          keyword: 'type',
        ));
        continue;
      }

      final cMap = Map<String, dynamic>.from(c);
      final id = cMap['id']?.toString();
      if (id == null || id.trim().isEmpty) {
        schemaErrors.add(JsonSchemaError(
          path: '$compPath/id',
          message: 'Component is missing required property "id".',
          keyword: 'required',
        ));
        continue;
      }

      // Check discriminator: support both 'component' and 'type'
      final componentType = cMap['component']?.toString() ?? cMap['type']?.toString();
      if (componentType == null || componentType.trim().isEmpty) {
        schemaErrors.add(JsonSchemaError(
          path: '$compPath/component',
          message: 'Component "$id" is missing required discriminator ("component" or "type").',
          keyword: 'required',
        ));
        continue;
      }

      cMap['component'] = componentType.trim();
      cMap['type'] = componentType.trim();
      componentsMap[id.trim()] = cMap;
    }
  }

  /// Identifies the root component ID from the components map.
  static String? _findRootComponentId(Map<String, Map<String, dynamic>> componentsMap) {
    if (componentsMap.containsKey('root')) {
      return 'root';
    }

    final allChildIds = <String>{};
    for (final comp in componentsMap.values) {
      final props = comp['properties'] is Map
          ? Map<String, dynamic>.from(comp['properties'] as Map)
          : comp;

      final child = props['child']?.toString();
      if (child != null && child.isNotEmpty) {
        allChildIds.add(child);
      }

      final children = props['children'];
      if (children is List) {
        for (final ch in children) {
          if (ch != null) allChildIds.add(ch.toString());
        }
      } else if (children is Map && children['componentId'] != null) {
        allChildIds.add(children['componentId'].toString());
      }

      final tabs = props['tabs'];
      if (tabs is List) {
        for (final t in tabs) {
          if (t is Map && t['child'] != null) {
            allChildIds.add(t['child'].toString());
          }
        }
      }

      final content = props['content']?.toString();
      if (content != null && content.isNotEmpty) {
        allChildIds.add(content);
      }
      final trigger = props['trigger']?.toString();
      if (trigger != null && trigger.isNotEmpty) {
        allChildIds.add(trigger);
      }
    }

    for (final id in componentsMap.keys) {
      if (!allChildIds.contains(id)) {
        return id;
      }
    }

    return componentsMap.keys.isNotEmpty ? componentsMap.keys.first : null;
  }
}
