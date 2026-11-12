import 'dart:convert';

/// Resolves RFC 6901 JSON Pointers (`{"@path": "/..."}`) and string
/// interpolation (`${/path}`) against an A2UI surface data model.
class JsonPointerResolver {
  static final RegExp _interpolationRegex = RegExp(r'\$\{([^}]+)\}');
  static final RegExp _pureInterpolationRegex = RegExp(r'^\$\{([^}]+)\}$');

  /// Resolves an arbitrary property value which may be a literal, a dynamic
  /// `@path` pointer, or an interpolated string.
  static dynamic resolve(dynamic value, Map<String, dynamic> dataModel) {
    if (value == null) return null;

    if (value is Map) {
      if (value.containsKey('@path')) {
        final path = value['@path']?.toString() ?? '';
        return resolvePointer(path, dataModel);
      }
      if (value.containsKey('@call')) {
        return _evaluateCall(value, dataModel);
      }
    }

    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('@path:')) {
        final path = trimmed.substring(6).trim();
        return resolvePointer(path, dataModel);
      } else if (trimmed.startsWith('@path')) {
        final path = trimmed.substring(5).trim();
        return resolvePointer(path, dataModel);
      }

      if (_interpolationRegex.hasMatch(value)) {
        return value.replaceAllMapped(_interpolationRegex, (match) {
          final expr = match.group(1)?.trim() ?? '';
          final pointer = expr.startsWith('/') ? expr : '/$expr';
          final resolved = resolvePointer(pointer, dataModel);
          return resolved?.toString() ?? '';
        });
      }
    }

    return value;
  }

  /// Traverses [dataModel] using a standard JSON Pointer path.
  static dynamic resolvePointer(String pointer, Map<String, dynamic> dataModel) {
    if (pointer.isEmpty || pointer == '/') {
      return dataModel;
    }

    var cleanPointer = pointer.trim();
    if (cleanPointer.startsWith('/')) {
      cleanPointer = cleanPointer.substring(1);
    }

    final segments = cleanPointer.split('/').map(_unescapeSegment).toList();
    dynamic current = dataModel;

    for (final segment in segments) {
      if (current == null) return null;

      if (current is Map) {
        if (current.containsKey(segment)) {
          current = current[segment];
        } else {
          return null;
        }
      } else if (current is List) {
        final index = int.tryParse(segment);
        if (index != null && index >= 0 && index < current.length) {
          current = current[index];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }

    return current;
  }

  /// Returns the JSON Pointer path when [value] is a writable binding.
  ///
  /// Accepts `{"@path": "/form/agreed"}`, `"@path:/form/agreed"`, and the
  /// pure interpolation form `"${/form/agreed}"`. A mixed interpolation such
  /// as `"Hello ${/name}"` is not a writable binding and returns null.
  static String? bindingPath(dynamic value) {
    if (value is Map) {
      final raw = value['@path'];
      if (raw is String) {
        final path = raw.trim();
        return path.isEmpty ? null : path;
      }
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('@path:')) {
        final path = trimmed.substring(6).trim();
        return path.isEmpty ? null : path;
      }
      if (trimmed.startsWith('@path')) {
        final path = trimmed.substring(5).trim();
        return path.isEmpty ? null : path;
      }
      final match = _pureInterpolationRegex.firstMatch(trimmed);
      if (match != null) {
        final path = match.group(1)?.trim() ?? '';
        if (path.isEmpty) return null;
        return path.startsWith('/') ? path : '/$path';
      }
    }
    return null;
  }

  /// Returns a deep copy of [dataModel] with [binding] set to [newValue].
  ///
  /// Throws [ArgumentError] when [binding] is not a writable JSON Pointer.
  static Map<String, dynamic> withValue(
    Map<String, dynamic> dataModel,
    dynamic binding,
    dynamic newValue,
  ) {
    final path = bindingPath(binding);
    if (path == null) {
      throw ArgumentError('Stateful A2UI values must bind to a JSON Pointer.');
    }
    final updated = json.decode(json.encode(dataModel)) as Map<String, dynamic>;
    setValue(updated, path, newValue);
    return updated;
  }

  /// Sets [value] at an RFC 6901 JSON Pointer [path] inside [model].
  ///
  /// A missing intermediate object is created. A null value removes the key at
  /// the path. The root path (`/` or empty) replaces the whole model and
  /// therefore requires an object value.
  static void setValue(
    Map<String, dynamic> model,
    String path,
    dynamic value,
  ) {
    final clean = path.trim();
    if (clean.isEmpty || clean == '/') {
      if (value == null) {
        model.clear();
        return;
      }
      if (value is! Map) {
        throw ArgumentError('root data model value must be an object');
      }
      model
        ..clear()
        ..addAll(
          json.decode(json.encode(value)) as Map<String, dynamic>,
        );
      return;
    }

    var pointer = clean;
    if (pointer.startsWith('/')) pointer = pointer.substring(1);
    final segments = pointer.split('/').map(_unescapeSegment).toList();

    dynamic current = model;
    for (var i = 0; i < segments.length - 1; i++) {
      final segment = segments[i];
      if (current is Map<String, dynamic>) {
        final next = current[segment];
        if (next is Map<String, dynamic>) {
          current = next;
        } else if (next is List) {
          current = next;
        } else {
          final created = <String, dynamic>{};
          current[segment] = created;
          current = created;
        }
      } else if (current is List) {
        final index = int.tryParse(segment);
        if (index == null || index < 0 || index >= current.length) {
          throw ArgumentError('invalid list index "$segment"');
        }
        final next = current[index];
        if (next is Map<String, dynamic>) {
          current = next;
        } else if (next is List) {
          current = next;
        } else {
          final created = <String, dynamic>{};
          current[index] = created;
          current = created;
        }
      } else {
        throw ArgumentError('path traverses a non-object value');
      }
    }

    final last = segments.last;
    if (current is Map) {
      if (value == null) {
        current.remove(last);
      } else if (value is Map) {
        current[last] = json.decode(json.encode(value));
      } else if (value is List) {
        current[last] = json.decode(json.encode(value));
      } else {
        current[last] = value;
      }
    } else if (current is List) {
      final index = int.tryParse(last);
      if (index == null || index < 0 || index > current.length) {
        throw ArgumentError('invalid list index "$last"');
      }
      if (value == null) {
        if (index < current.length) {
          current.removeAt(index);
        }
      } else if (index == current.length) {
        current.add(value);
      } else {
        current[index] = value;
      }
    } else {
      throw ArgumentError('path traverses a non-object value');
    }
  }

  static String _unescapeSegment(String segment) {
    return segment.replaceAll('~1', '/').replaceAll('~0', '~');
  }

  static dynamic _evaluateCall(Map callMap, Map<String, dynamic> dataModel) {
    final functionName = callMap['@call']?.toString();
    final args = callMap['args'] is Map
        ? Map<String, dynamic>.from(callMap['args'] as Map)
        : <String, dynamic>{};

    switch (functionName) {
      case 'formatString':
        final val = args['value'];
        return resolve(val, dataModel)?.toString() ?? '';
      case 'formatCurrency':
        final rawVal = resolve(args['value'], dataModel);
        final numVal = num.tryParse(rawVal?.toString() ?? '') ?? 0;
        final currency = args['currency']?.toString() ?? '\$';
        return '$currency${numVal.toStringAsFixed(2)}';
      case 'formatNumber':
        final rawVal = resolve(args['value'], dataModel);
        final decimals = args['decimals'] is int ? args['decimals'] as int : 0;
        final numVal = num.tryParse(rawVal?.toString() ?? '');
        return numVal != null
            ? numVal.toStringAsFixed(decimals)
            : rawVal?.toString() ?? '';
      default:
        return args['value'] != null ? resolve(args['value'], dataModel) : null;
    }
  }
}
