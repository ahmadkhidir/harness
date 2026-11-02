/// Validator and normalizer for Agent-to-User Interface (A2UI) payloads.
///
/// Implements FEAT-006:
/// - Conforms to the official A2UI specification (`a2ui-project/a2ui`).
/// - Supports both `createSurface.components` and `updateComponents.components`.
/// - Supports both `createSurface.dataModel` and `updateDataModel.value`.
/// - Supports both `component` and `type` component discriminators.
/// - Supports direct properties on the component object and nested `properties: {...}`.
/// - Resolves root component ID safely.
/// - Produces clear, actionable error messages for the autonomous tool self-healing loop.
library;

/// Result of validating and normalizing an A2UI payload.
class A2UIValidationResult {
  /// Whether the payload is structurally valid and contains renderable components.
  final bool isValid;

  /// Human-readable error message explaining why validation failed, or null if valid.
  final String? errorMessage;

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
    this.surfaceId,
    this.catalogId,
    this.componentsMap = const {},
    this.dataModel = const {},
    this.rootComponentId,
  });

  factory A2UIValidationResult.failure(String errorMessage, {String? surfaceId}) {
    return A2UIValidationResult(
      isValid: false,
      errorMessage: errorMessage,
      surfaceId: surfaceId,
    );
  }
}

/// Normalizes and validates incoming A2UI payloads.
class A2UIValidator {
  /// Validates [payload] and returns a structured [A2UIValidationResult].
  static A2UIValidationResult validate(Map<String, dynamic>? payload) {
    if (payload == null) {
      return A2UIValidationResult.failure(
        'A2UI payload is null. A valid send_a2ui call must contain a "messages" list.',
      );
    }

    final rawMessages = payload['messages'];
    if (rawMessages == null || rawMessages is! List || rawMessages.isEmpty) {
      return A2UIValidationResult.failure(
        'Missing or empty "messages" list in send_a2ui parameters.',
      );
    }

    String? surfaceId;
    String? catalogId;
    final componentsMap = <String, Map<String, dynamic>>{};
    final dataModel = <String, dynamic>{};

    for (final msgItem in rawMessages) {
      if (msgItem is! Map) continue;
      final msg = Map<String, dynamic>.from(msgItem);

      // Handle createSurface
      if (msg.containsKey('createSurface')) {
        final create = Map<String, dynamic>.from(msg['createSurface'] as Map);
        if (create['surfaceId'] != null) {
          surfaceId = create['surfaceId']?.toString();
        }
        if (create['catalogId'] != null) {
          catalogId = create['catalogId']?.toString();
        }

        // Components inside createSurface (Official A2UI specification)
        if (create.containsKey('components') && create['components'] is List) {
          _extractComponents(create['components'] as List, componentsMap);
        }

        // Data model inside createSurface
        if (create.containsKey('dataModel') && create['dataModel'] is Map) {
          dataModel.addAll(Map<String, dynamic>.from(create['dataModel'] as Map));
        }
      }

      // Handle updateComponents
      if (msg.containsKey('updateComponents')) {
        final uc = Map<String, dynamic>.from(msg['updateComponents'] as Map);
        if (surfaceId == null && uc['surfaceId'] != null) {
          surfaceId = uc['surfaceId']?.toString();
        }
        if (uc.containsKey('components') && uc['components'] is List) {
          _extractComponents(uc['components'] as List, componentsMap);
        }
      }

      // Handle updateDataModel
      if (msg.containsKey('updateDataModel')) {
        final dm = Map<String, dynamic>.from(msg['updateDataModel'] as Map);
        if (surfaceId == null && dm['surfaceId'] != null) {
          surfaceId = dm['surfaceId']?.toString();
        }
        if (dm['value'] != null && dm['value'] is Map) {
          dataModel.addAll(Map<String, dynamic>.from(dm['value'] as Map));
        }
      }
    }

    // Default surfaceId to 'main' if unspecified but components are present
    surfaceId ??= 'main';

    if (componentsMap.isEmpty) {
      return A2UIValidationResult.failure(
        'No components defined for surface "$surfaceId". Specify components inside "createSurface.components" or "updateComponents.components".',
        surfaceId: surfaceId,
      );
    }

    final rootId = _findRootComponentId(componentsMap);
    if (rootId == null || !componentsMap.containsKey(rootId)) {
      return A2UIValidationResult.failure(
        'Cannot resolve root component for surface "$surfaceId". Define an element with id: "root" or ensure the root container is not a child of any other component.',
        surfaceId: surfaceId,
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

  static void _extractComponents(
    List comps,
    Map<String, Map<String, dynamic>> componentsMap,
  ) {
    for (final c in comps) {
      if (c is! Map) continue;
      final cMap = Map<String, dynamic>.from(c);
      final id = cMap['id']?.toString();
      if (id == null || id.isEmpty) continue;

      // Normalize discriminator: support both 'component' and 'type'
      final componentType = cMap['component']?.toString() ?? cMap['type']?.toString();
      if (componentType != null) {
        cMap['component'] = componentType;
        cMap['type'] = componentType;
      }

      componentsMap[id] = cMap;
    }
  }

  /// Identifies the root component ID from the components map.
  static String? _findRootComponentId(Map<String, Map<String, dynamic>> componentsMap) {
    if (componentsMap.containsKey('root')) {
      return 'root';
    }

    final allChildIds = <String>{};
    for (final comp in componentsMap.values) {
      // Direct properties or nested properties map
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

    // A candidate root is any component that is NOT a child of another component
    for (final id in componentsMap.keys) {
      if (!allChildIds.contains(id)) {
        return id;
      }
    }

    return componentsMap.keys.isNotEmpty ? componentsMap.keys.first : null;
  }
}
