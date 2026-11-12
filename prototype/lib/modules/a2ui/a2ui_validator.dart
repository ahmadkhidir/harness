import '../../core/schema/json_schema_validator.dart';
import 'catalogs/basic_v1_component_schemas.dart';
import 'json_pointer_resolver.dart';
import 'widgets/a2ui_component_registry.dart';

/// Normalizes and validates A2UI component definitions.
///
/// The store applies messages incrementally, so reference validation is
/// intentionally not performed here. A component may reference a child that
/// has not arrived yet; the renderer omits unresolved nodes until they appear.
class A2UIValidator {
  /// Extracts components from either a [List] or a [Map] keyed by component ID.
  ///
  /// [basePath] is used only to produce precise JSON Pointer paths in schema
  /// errors.
  static void normalizeComponents(
    dynamic comps,
    String basePath,
    Map<String, Map<String, dynamic>> out,
    List<JsonSchemaError> errors,
  ) {
    if (comps == null) return;

    void processComponent(
      Map<String, dynamic> cMap,
      String defaultId,
      String compPath,
    ) {
      final idRaw = cMap['id']?.toString() ?? defaultId;
      final id = idRaw.trim();
      if (id.isEmpty) {
        errors.add(JsonSchemaError(
          path: '$compPath/id',
          message: 'Component is missing required property "id".',
          keyword: 'required',
        ));
        return;
      }

      // Support nested wrappers such as {"component": {"Card": {...}}}.
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
        errors.add(JsonSchemaError(
          path: '$compPath/component',
          message: 'Component "$id" is missing its "component" discriminator.',
          keyword: 'required',
        ));
        return;
      }

      cMap['id'] = id;
      cMap['component'] = componentType.trim();
      cMap['type'] = componentType.trim();
      out[id] = cMap;
    }

    if (comps is List) {
      for (int i = 0; i < comps.length; i++) {
        final c = comps[i];
        final compPath = '$basePath/$i';
        if (c is! Map) {
          errors.add(JsonSchemaError(
            path: compPath,
            message: 'Expected component object but got ${c.runtimeType}.',
            keyword: 'type',
          ));
          continue;
        }
        processComponent(Map<String, dynamic>.from(c), '', compPath);
      }
    } else if (comps is Map) {
      for (final entry in comps.entries) {
        final id = entry.key.toString().trim();
        final compVal = entry.value;
        final compPath = '$basePath/$id';
        if (compVal is! Map) {
          errors.add(JsonSchemaError(
            path: compPath,
            message: 'Expected component object for "$id" but got ${compVal.runtimeType}.',
            keyword: 'type',
          ));
          continue;
        }
        processComponent(Map<String, dynamic>.from(compVal), id, compPath);
      }
    } else {
      errors.add(JsonSchemaError(
        path: basePath,
        message: 'Expected components list or map but got ${comps.runtimeType}.',
        keyword: 'type',
      ));
    }
  }

  /// Merges nested `properties` with top-level component fields.
  static Map<String, dynamic> componentProperties(
    Map<String, dynamic> component,
  ) {
    final properties = <String, dynamic>{};
    if (component['properties'] is Map) {
      properties.addAll(
        Map<String, dynamic>.from(component['properties'] as Map),
      );
    }
    const metadataKeys = {'id', 'component', 'type', 'properties'};
    for (final entry in component.entries) {
      if (!metadataKeys.contains(entry.key)) {
        properties[entry.key] = entry.value;
      }
    }
    return properties;
  }

  /// Collects component IDs referenced by a component's structural properties.
  ///
  /// Missing references are allowed; this is used by the renderer and for
  /// diagnostics, not for rejecting progressive updates.
  static Iterable<String> referencedComponentIds(
    Map<String, dynamic> component,
  ) {
    final properties = componentProperties(component);
    final references = <String>{};

    void addValue(dynamic value) {
      if (value is String && value.trim().isNotEmpty) {
        references.add(value.trim());
      }
    }

    addValue(properties['child']);
    addValue(properties['content']);
    addValue(properties['trigger']);

    final children = properties['children'];
    if (children is List) {
      for (final child in children) {
        addValue(child);
      }
    } else if (children is Map) {
      addValue(children['componentId']);
    }

    final tabs = properties['tabs'];
    if (tabs is List) {
      for (final tab in tabs) {
        if (tab is Map) addValue(tab['child']);
      }
    }

    return references;
  }

  /// Validates the shape of every component against the basic/v1 schemas.
  ///
  /// This deliberately does not check whether referenced child IDs exist.
  /// Incremental A2UI updates may reference components that arrive later.
  static List<JsonSchemaError> validateComponentShapes(
    Map<String, Map<String, dynamic>> components,
  ) {
    final errors = <JsonSchemaError>[];

    for (final entry in components.entries) {
      final id = entry.key;
      final component = entry.value;
      final type = component['component']?.toString() ??
          component['type']?.toString() ??
          '';
      final schema = kBasicV1ComponentSchemas[type];

      if (schema == null) {
        if (A2UIComponentRegistry.instance.getBuilder(type) == null) {
          errors.add(JsonSchemaError(
            path: '/components/$id/component',
            message: 'Unknown component type "$type".',
            value: type,
            keyword: 'enum',
          ));
        }
        continue;
      }

      final result = JsonSchemaValidator.validate(
        componentProperties(component),
        schema,
        rootPath: '/components/$id',
      );
      errors.addAll(result.errors);

      // Stateful inputs must bind their value to a data path so the renderer can
      // update it immediately and the action payload carries a semantic field.
      if (const {
        'CheckBox',
        'ChoicePicker',
        'Slider',
        'DateTimeInput',
        'TextField',
      }.contains(type)) {
        final value = componentProperties(component)['value'];
        if (JsonPointerResolver.bindingPath(value) == null) {
          errors.add(JsonSchemaError(
            path: '/components/$id/value',
            message:
                'Stateful component "$type" requires "value" to be a data binding, for example {"@path": "/form/field"}.',
            keyword: 'required',
          ));
        }
      }
    }

    return errors;
  }
}
