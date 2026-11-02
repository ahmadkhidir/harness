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
///
/// Ultra-resilient component extractor:
/// - Supports components in `createSurface.components`, `updateComponents.components`,
///   `msg.components`, `surface.components`, or directly at root parameters.
/// - Supports components represented as either a `List` of items or a `Map` of ID -> component.
/// - Supports payloads wrapped in `messages: [...]` or direct single-surface payloads.
/// - Resolves root component automatically.
class A2UIValidator {
  /// Validates [payload] and returns a structured [A2UIValidationResult].
  static A2UIValidationResult validate(Map<String, dynamic>? payload) {
    if (payload == null) {
      return A2UIValidationResult.failure(
        'A2UI payload is null. A valid send_a2ui call must contain a "messages" list or components.',
        errors: const [
          JsonSchemaError(
            path: '/parameters',
            message: 'A2UI payload is null.',
            keyword: 'required',
          ),
        ],
      );
    }

    // Normalize messages list: support both wrapped {"messages": [...]} and flat {"createSurface": ...}
    List rawMessages;
    final messagesVal = payload['messages'];
    if (messagesVal is List && messagesVal.isNotEmpty) {
      rawMessages = messagesVal;
    } else if (messagesVal is Map) {
      rawMessages = [messagesVal];
    } else if (payload.containsKey('createSurface') ||
        payload.containsKey('updateComponents') ||
        payload.containsKey('components') ||
        payload.containsKey('surface')) {
      rawMessages = [payload];
    } else {
      return A2UIValidationResult.failure(
        'Missing or empty "messages" list in send_a2ui parameters. Expected an array of A2UI messages (createSurface, updateComponents).',
        errors: const [
          JsonSchemaError(
            path: '/parameters/messages',
            message: 'Missing or empty messages list.',
            keyword: 'required',
          ),
        ],
      );
    }

    final schemaErrors = <JsonSchemaError>[];
    String? surfaceId;
    String? catalogId;
    final componentsMap = <String, Map<String, dynamic>>{};
    final dataModel = <String, dynamic>{};

    String? cleanSurfaceId(dynamic raw) {
      if (raw == null) return null;
      final s = raw.toString().trim();
      if (s.isEmpty || s == 'null' || s == 'undefined') return null;
      return s;
    }

    // Extract top-level components or dataModel if present directly on payload
    if (payload['components'] != null) {
      _extractComponents(payload['components'], '/parameters/components', componentsMap, schemaErrors);
    }
    if (payload['dataModel'] is Map) {
      dataModel.addAll(Map<String, dynamic>.from(payload['dataModel'] as Map));
    }
    if (payload['surfaceId'] != null) {
      surfaceId = cleanSurfaceId(payload['surfaceId']);
    }

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

      // Top-level surfaceId on message
      if (surfaceId == null && msg['surfaceId'] != null) {
        surfaceId = cleanSurfaceId(msg['surfaceId']);
      }

      // 1. Handle createSurface
      if (msg.containsKey('createSurface')) {
        final createRaw = msg['createSurface'];
        if (createRaw is Map) {
          final create = Map<String, dynamic>.from(createRaw);
          if (create['surfaceId'] != null) {
            surfaceId = cleanSurfaceId(create['surfaceId']) ?? surfaceId;
          }
          if (create['catalogId'] != null) {
            catalogId = create['catalogId']?.toString();
          }

          if (create.containsKey('components')) {
            _extractComponents(
              create['components'],
              '$msgPath/createSurface/components',
              componentsMap,
              schemaErrors,
            );
          }

          if (create.containsKey('dataModel') && create['dataModel'] is Map) {
            dataModel.addAll(Map<String, dynamic>.from(create['dataModel'] as Map));
          }
        }
      }

      // 2. Handle updateComponents
      if (msg.containsKey('updateComponents')) {
        final ucRaw = msg['updateComponents'];
        if (ucRaw is Map) {
          final uc = Map<String, dynamic>.from(ucRaw);
          if (surfaceId == null && uc['surfaceId'] != null) {
            surfaceId = cleanSurfaceId(uc['surfaceId']);
          }
          if (uc.containsKey('components')) {
            _extractComponents(
              uc['components'],
              '$msgPath/updateComponents/components',
              componentsMap,
              schemaErrors,
            );
          }
        }
      }

      // 3. Handle updateDataModel
      if (msg.containsKey('updateDataModel')) {
        final dmRaw = msg['updateDataModel'];
        if (dmRaw is Map) {
          final dm = Map<String, dynamic>.from(dmRaw);
          if (surfaceId == null && dm['surfaceId'] != null) {
            surfaceId = cleanSurfaceId(dm['surfaceId']);
          }
          if (dm['value'] != null && dm['value'] is Map) {
            dataModel.addAll(Map<String, dynamic>.from(dm['value'] as Map));
          }
          if (dm['dataModel'] != null && dm['dataModel'] is Map) {
            dataModel.addAll(Map<String, dynamic>.from(dm['dataModel'] as Map));
          }
        }
      }

      // 4. Handle direct message-level components (e.g. {"surfaceId": "main", "components": [...]})
      if (msg.containsKey('components')) {
        _extractComponents(
          msg['components'],
          '$msgPath/components',
          componentsMap,
          schemaErrors,
        );
      }

      // 5. Handle surface wrapper (e.g. {"surface": {"surfaceId": "main", "components": [...]}})
      if (msg.containsKey('surface') && msg['surface'] is Map) {
        final sMap = Map<String, dynamic>.from(msg['surface'] as Map);
        if (surfaceId == null && sMap['surfaceId'] != null) {
          surfaceId = cleanSurfaceId(sMap['surfaceId']);
        }
        if (sMap.containsKey('components')) {
          _extractComponents(
            sMap['components'],
            '$msgPath/surface/components',
            componentsMap,
            schemaErrors,
          );
        }
      }
    }

    if (schemaErrors.isNotEmpty) {
      final summary = JsonSchemaValidationResult.failure(schemaErrors)
          .formatErrorSummary(contextName: 'send_a2ui');
      return A2UIValidationResult.failure(summary, errors: schemaErrors, surfaceId: surfaceId);
    }

    surfaceId = cleanSurfaceId(surfaceId) ?? 'main';

    if (componentsMap.isEmpty) {
      return A2UIValidationResult.failure(
        'No components defined for surface "$surfaceId". Specify components inside "createSurface.components" or "updateComponents.components" as either a list of component objects or an ID-to-component dictionary.',
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

  /// Extracts components from either a [List] or a [Map] (keyed by ID).
  static void _extractComponents(
    dynamic comps,
    String basePath,
    Map<String, Map<String, dynamic>> componentsMap,
    List<JsonSchemaError> schemaErrors,
  ) {
    if (comps == null) return;

    void processComponent(Map<String, dynamic> cMap, String defaultId, String compPath) {
      final idRaw = cMap['id']?.toString() ?? defaultId;
      final id = idRaw.trim();
      if (id.isEmpty) {
        schemaErrors.add(JsonSchemaError(
          path: '$compPath/id',
          message: 'Component is missing required property "id".',
          keyword: 'required',
        ));
        return;
      }

      // Handle nested component wrappers like {"component": {"Card": {...}}}
      if (cMap['component'] is Map) {
        final compObj = cMap['component'] as Map;
        if (compObj.isNotEmpty) {
          final firstKey = compObj.keys.first.toString();
          final innerProps = compObj[firstKey];
          cMap['component'] = firstKey;
          cMap['type'] = firstKey;
          if (innerProps is Map) {
            cMap.addAll(Map<String, dynamic>.from(innerProps));
          }
        }
      }
      if (cMap['type'] is Map) {
        final compObj = cMap['type'] as Map;
        if (compObj.isNotEmpty) {
          final firstKey = compObj.keys.first.toString();
          final innerProps = compObj[firstKey];
          cMap['component'] = firstKey;
          cMap['type'] = firstKey;
          if (innerProps is Map) {
            cMap.addAll(Map<String, dynamic>.from(innerProps));
          }
        }
      }

      final componentType = cMap['component']?.toString() ??
          cMap['type']?.toString() ??
          cMap['componentType']?.toString() ??
          cMap['widget']?.toString();

      if (componentType == null || componentType.trim().isEmpty) {
        schemaErrors.add(JsonSchemaError(
          path: '$compPath/component',
          message: 'Component "$id" is missing required discriminator ("component" or "type").',
          keyword: 'required',
        ));
        return;
      }

      cMap['id'] = id;
      cMap['component'] = componentType.trim();
      cMap['type'] = componentType.trim();
      componentsMap[id] = cMap;
    }

    if (comps is List) {
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

        processComponent(Map<String, dynamic>.from(c), '', compPath);
      }
    } else if (comps is Map) {
      // Map of ID -> component object: {"root": {"component": "Card", ...}}
      for (final entry in comps.entries) {
        final id = entry.key.toString().trim();
        final compVal = entry.value;
        final compPath = '$basePath/$id';

        if (compVal is! Map) {
          schemaErrors.add(JsonSchemaError(
            path: compPath,
            message: 'Expected component object for "$id" but got ${compVal.runtimeType}.',
            keyword: 'type',
          ));
          continue;
        }

        processComponent(Map<String, dynamic>.from(compVal), id, compPath);
      }
    } else {
      schemaErrors.add(JsonSchemaError(
        path: basePath,
        message: 'Expected components list or map but got ${comps.runtimeType}.',
        keyword: 'type',
      ));
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
