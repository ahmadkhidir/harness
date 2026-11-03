/// Universal JSON Schema validator for agent tool parameters and A2UI surface models.
///
/// Implements standard JSON Schema validation:
/// - Validates primitive types (`string`, `number`, `integer`, `boolean`, `null`).
/// - Validates composite types (`object`, `array`).
/// - Checks `required` fields on objects.
/// - Validates nested `properties` schemas.
/// - Validates `items` schema for arrays.
/// - Checks `enum` constraints and `const` literals.
/// - Checks `minLength`, `maxLength`, `minimum`, `maximum`.
/// - Pinpoints exact JSON Pointer locations (`/path/to/field`) for every error.
library;

/// Represents a single schema validation failure at a specific JSON Pointer path.
class JsonSchemaError {
  /// RFC 6901 JSON Pointer path where the violation occurred (e.g. `/messages/0/createSurface`).
  final String path;

  /// Human-readable explanation of the validation failure.
  final String message;

  /// Offending runtime value, if any.
  final dynamic value;

  /// Schema keyword that caused the failure (e.g. `required`, `type`, `enum`).
  final String keyword;

  const JsonSchemaError({
    required this.path,
    required this.message,
    this.value,
    required this.keyword,
  });

  @override
  String toString() => '[$path] $message';
}

/// Aggregated result of validating a JSON data structure against a schema.
class JsonSchemaValidationResult {
  /// Whether the data conforms to the schema with zero errors.
  final bool isValid;

  /// List of all validation errors encountered, or empty if valid.
  final List<JsonSchemaError> errors;

  const JsonSchemaValidationResult({
    required this.isValid,
    this.errors = const [],
  });

  factory JsonSchemaValidationResult.success() =>
      const JsonSchemaValidationResult(isValid: true, errors: []);

  factory JsonSchemaValidationResult.failure(List<JsonSchemaError> errors) =>
      JsonSchemaValidationResult(isValid: false, errors: errors);

  /// Returns a formatted, multi-line summary of all errors with their locations.
  String formatErrorSummary({String? contextName}) {
    if (isValid) return 'Validation passed.';
    final buffer = StringBuffer();
    final header = contextName != null
        ? 'Schema validation failed for "$contextName":'
        : 'Schema validation failed:';
    buffer.writeln(header);
    for (int i = 0; i < errors.length; i++) {
      final err = errors[i];
      final displayPath = err.path.isEmpty ? '/' : err.path;
      buffer.writeln('  ${i + 1}. at $displayPath: ${err.message}');
    }
    return buffer.toString().trim();
  }
}

/// Evaluator that validates runtime Dart data structures (Maps, Lists, primitives)
/// against JSON Schema definitions.
class JsonSchemaValidator {
  /// Validates [data] against [schema].
  ///
  /// Returns a [JsonSchemaValidationResult] containing any errors with exact JSON Pointer paths.
  static JsonSchemaValidationResult validate(
    dynamic data,
    Map<String, dynamic> schema, {
    String rootPath = '',
  }) {
    final errors = <JsonSchemaError>[];
    _validateNode(data, schema, rootPath, errors);
    return errors.isEmpty
        ? JsonSchemaValidationResult.success()
        : JsonSchemaValidationResult.failure(errors);
  }

  static void _validateNode(
    dynamic data,
    Map<String, dynamic> schema,
    String currentPath,
    List<JsonSchemaError> errors,
  ) {
    // 1. Const check
    if (schema.containsKey('const')) {
      final expectedConst = schema['const'];
      if (data != expectedConst) {
        errors.add(JsonSchemaError(
          path: currentPath,
          message: 'Expected constant value "$expectedConst" but got "$data".',
          value: data,
          keyword: 'const',
        ));
        return;
      }
    }

    // 2. Enum check
    if (schema.containsKey('enum') && schema['enum'] is List) {
      final allowed = schema['enum'] as List;
      if (!allowed.contains(data)) {
        errors.add(JsonSchemaError(
          path: currentPath,
          message: 'Value "$data" is not one of allowed values: $allowed.',
          value: data,
          keyword: 'enum',
        ));
        return;
      }
    }

    // 3. Type check (supports unions such as ["string", "object"])
    if (schema.containsKey('type')) {
      final rawType = schema['type'];
      final expectedTypes = rawType is List
          ? rawType.map((type) => type.toString()).toList()
          : [rawType.toString()];
      final matches = expectedTypes.any((type) => _checkType(data, type));
      if (!matches) {
        errors.add(JsonSchemaError(
          path: currentPath,
          message:
              'Expected type "${expectedTypes.join(' or ')}" but got ${_describeType(data)} ($data).',
          value: data,
          keyword: 'type',
        ));
        return; // Skip further type-specific checks if type is fundamentally wrong
      }
    }

    // 4. String-specific constraints
    if (data is String) {
      if (schema.containsKey('minLength') && schema['minLength'] is num) {
        final minLen = (schema['minLength'] as num).toInt();
        if (data.length < minLen) {
          errors.add(JsonSchemaError(
            path: currentPath,
            message: 'String length (${data.length}) is shorter than minLength ($minLen).',
            value: data,
            keyword: 'minLength',
          ));
        }
      }
      if (schema.containsKey('maxLength') && schema['maxLength'] is num) {
        final maxLen = (schema['maxLength'] as num).toInt();
        if (data.length > maxLen) {
          errors.add(JsonSchemaError(
            path: currentPath,
            message: 'String length (${data.length}) is longer than maxLength ($maxLen).',
            value: data,
            keyword: 'maxLength',
          ));
        }
      }
    }

    // 5. Number-specific constraints
    if (data is num) {
      if (schema.containsKey('minimum') && schema['minimum'] is num) {
        final minVal = schema['minimum'] as num;
        if (data < minVal) {
          errors.add(JsonSchemaError(
            path: currentPath,
            message: 'Number ($data) is less than minimum ($minVal).',
            value: data,
            keyword: 'minimum',
          ));
        }
      }
      if (schema.containsKey('maximum') && schema['maximum'] is num) {
        final maxVal = schema['maximum'] as num;
        if (data > maxVal) {
          errors.add(JsonSchemaError(
            path: currentPath,
            message: 'Number ($data) is greater than maximum ($maxVal).',
            value: data,
            keyword: 'maximum',
          ));
        }
      }
    }

    // 6. Object-specific constraints (required & properties)
    if (data is Map) {
      final mapData = Map<String, dynamic>.from(data);

      // Check required properties
      if (schema.containsKey('required') && schema['required'] is List) {
        final requiredFields = schema['required'] as List;
        for (final field in requiredFields) {
          final fieldStr = field.toString();
          if (!mapData.containsKey(fieldStr) || mapData[fieldStr] == null) {
            errors.add(JsonSchemaError(
              path: '$currentPath/$fieldStr',
              message: 'Required property "$fieldStr" is missing.',
              value: null,
              keyword: 'required',
            ));
          }
        }
      }

      final propsSchema = schema['properties'] is Map
          ? Map<String, dynamic>.from(schema['properties'] as Map)
          : const <String, dynamic>{};

      // Check defined properties
      for (final entry in propsSchema.entries) {
        final propName = entry.key;
        final propSchema = entry.value;

        if (mapData.containsKey(propName) && mapData[propName] != null) {
          if (propSchema is Map) {
            _validateNode(
              mapData[propName],
              Map<String, dynamic>.from(propSchema),
              '$currentPath/$propName',
              errors,
            );
          }
        }
      }

      // Handle additionalProperties (false forbids unknown keys; a schema
      // validates unknown values).
      final additional = schema['additionalProperties'];
      if (additional == false || additional is Map) {
        for (final key in mapData.keys) {
          if (propsSchema.containsKey(key)) continue;
          if (additional == false) {
            errors.add(JsonSchemaError(
              path: '$currentPath/$key',
              message: 'Property "$key" is not allowed by the schema.',
              value: mapData[key],
              keyword: 'additionalProperties',
            ));
          } else if (additional is Map) {
            _validateNode(
              mapData[key],
              Map<String, dynamic>.from(additional),
              '$currentPath/$key',
              errors,
            );
          }
        }
      }
    }

    // 7. Array-specific constraints (items)
    if (data is List) {
      if (schema.containsKey('minItems') && schema['minItems'] is num) {
        final minItems = (schema['minItems'] as num).toInt();
        if (data.length < minItems) {
          errors.add(JsonSchemaError(
            path: currentPath,
            message: 'Array has ${data.length} items, expected at least $minItems.',
            value: data,
            keyword: 'minItems',
          ));
        }
      }

      if (schema.containsKey('items') && schema['items'] is Map) {
        final itemsSchema = Map<String, dynamic>.from(schema['items'] as Map);
        for (int i = 0; i < data.length; i++) {
          _validateNode(data[i], itemsSchema, '$currentPath/$i', errors);
        }
      }
    }
  }

  static bool _checkType(dynamic data, String expectedType) {
    switch (expectedType) {
      case 'string':
        return data is String;
      case 'number':
        return data is num;
      case 'integer':
        return data is int;
      case 'boolean':
        return data is bool;
      case 'array':
        return data is List;
      case 'object':
        return data is Map;
      case 'null':
        return data == null;
      default:
        return true;
    }
  }

  static String _describeType(dynamic data) {
    if (data == null) return 'null';
    if (data is String) return 'string';
    if (data is int) return 'integer';
    if (data is double) return 'number';
    if (data is bool) return 'boolean';
    if (data is List) return 'array';
    if (data is Map) return 'object';
    return data.runtimeType.toString();
  }
}
