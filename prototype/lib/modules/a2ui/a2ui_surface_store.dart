import 'dart:convert';

import '../../core/schema/json_schema_validator.dart';
import 'a2ui_validator.dart';
import 'json_pointer_resolver.dart';

/// Represents the live state of one A2UI surface.
///
/// A surface is created once and then mutated by `updateComponents`,
/// `updateDataModel`, and `deleteSurface` messages. The component map is kept
/// even when some referenced children are not present yet; the renderer simply
/// omits unresolved nodes until they arrive.
class A2UISurfaceState {
  /// Unique surface identifier.
  final String surfaceId;

  /// Catalog identifier used for component validation and rendering.
  final String catalogId;

  /// Flat component map keyed by component ID.
  final Map<String, Map<String, dynamic>> components;

  /// Surface data model used by JSON Pointer bindings.
  final Map<String, dynamic> dataModel;

  /// True after a `deleteSurface` message has removed this surface.
  final bool isDeleted;

  const A2UISurfaceState({
    required this.surfaceId,
    required this.catalogId,
    required this.components,
    required this.dataModel,
    this.isDeleted = false,
  });

  /// The conventional root component ID for A2UI v1.
  String? get rootId => components.containsKey('root') ? 'root' : null;

  /// Whether the surface has enough structure to render anything.
  bool get isRenderable => !isDeleted && rootId != null;

  A2UISurfaceState copyWith({
    String? surfaceId,
    String? catalogId,
    Map<String, Map<String, dynamic>>? components,
    Map<String, dynamic>? dataModel,
    bool? isDeleted,
  }) {
    return A2UISurfaceState(
      surfaceId: surfaceId ?? this.surfaceId,
      catalogId: catalogId ?? this.catalogId,
      components: components ?? this.components,
      dataModel: dataModel ?? this.dataModel,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}

/// Result of applying one or more A2UI messages to a [A2UISurfaceStore].
class A2UIApplyResult {
  /// True when every message was applied.
  final bool success;

  /// Human- and model-readable error when [success] is false.
  final String? errorMessage;

  /// Structured schema errors, if any.
  final List<JsonSchemaError> errors;

  /// Surfaces touched by the message batch.
  final Set<String> affectedSurfaceIds;

  /// Surface that should be associated with the delivered chat turn.
  final String? primarySurfaceId;

  const A2UIApplyResult({
    required this.success,
    this.errorMessage,
    this.errors = const [],
    this.affectedSurfaceIds = const {},
    this.primarySurfaceId,
  });

  factory A2UIApplyResult.failure(
    String message, {
    List<JsonSchemaError> errors = const [],
  }) {
    return A2UIApplyResult(
      success: false,
      errorMessage: message,
      errors: errors,
    );
  }
}

/// Per-session store of live A2UI surfaces.
///
/// Messages are applied transactionally: if any message in a batch fails, the
/// store is left unchanged so the engine can ask the model to repair the batch.
class A2UISurfaceStore {
  final Map<String, A2UISurfaceState> _surfaces = {};

  /// Read-only view of all surfaces.
  Map<String, A2UISurfaceState> get surfaces => Map.unmodifiable(_surfaces);

  /// Returns one surface, or null when it does not exist.
  A2UISurfaceState? surface(String surfaceId) => _surfaces[surfaceId];

  /// Clears all surfaces (used when switching sessions).
  void clear() => _surfaces.clear();

  /// Replaces the store contents, used when replaying a persisted session.
  void replaceAll(Map<String, A2UISurfaceState> surfaces) {
    _surfaces
      ..clear()
      ..addAll(surfaces);
  }

  /// Writes one value into an existing surface's data model.
  ///
  /// Used for in-progress component state such as typing in a text field or
  /// dragging a slider. Returns false when the surface does not exist or the
  /// path is invalid.
  bool setDataModelValue(String surfaceId, String path, dynamic value) {
    final current = _surfaces[surfaceId];
    if (current == null || current.isDeleted) return false;
    final updated = _copyMap(current.dataModel);
    try {
      JsonPointerResolver.setValue(updated, path, value);
    } catch (_) {
      return false;
    }
    _surfaces[surfaceId] = current.copyWith(dataModel: updated);
    return true;
  }

  /// Applies a batch of A2UI envelope messages.
  A2UIApplyResult applyMessages(List<dynamic> messages) {
    if (messages.isEmpty) {
      return A2UIApplyResult.failure('A2UI message list is empty.');
    }

    final working = <String, A2UISurfaceState>{};
    for (final entry in _surfaces.entries) {
      working[entry.key] = entry.value.copyWith(
        components: _copyComponents(entry.value.components),
        dataModel: _copyMap(entry.value.dataModel),
      );
    }

    final affected = <String>{};
    String? primarySurfaceId;

    for (int index = 0; index < messages.length; index++) {
      final raw = messages[index];
      if (raw is! Map) {
        return A2UIApplyResult.failure(
          'A2UI message at index $index is not an object.',
        );
      }

      final message = Map<String, dynamic>.from(raw);
      final keys = <String>[
        if (message.containsKey('createSurface')) 'createSurface',
        if (message.containsKey('updateComponents')) 'updateComponents',
        if (message.containsKey('updateDataModel')) 'updateDataModel',
        if (message.containsKey('deleteSurface')) 'deleteSurface',
      ];

      if (keys.length != 1) {
        return A2UIApplyResult.failure(
          'A2UI message at index $index must contain exactly one of '
          'createSurface, updateComponents, updateDataModel, or deleteSurface.',
        );
      }

      final type = keys.single;
      final payload = message[type];
      if (payload is! Map) {
        return A2UIApplyResult.failure(
          'A2UI "$type" message at index $index must be an object.',
        );
      }

      final data = Map<String, dynamic>.from(payload);
      final basePath = '/messages/$index/$type';
      late A2UIApplyResult result;
      switch (type) {
        case 'createSurface':
          result = _applyCreateSurface(
            working,
            data,
            basePath,
            affected,
          );
        case 'updateComponents':
          result = _applyUpdateComponents(
            working,
            data,
            basePath,
            affected,
          );
        case 'updateDataModel':
          result = _applyUpdateDataModel(
            working,
            data,
            affected,
          );
        case 'deleteSurface':
          result = _applyDeleteSurface(
            working,
            data,
            affected,
          );
        default:
          result = A2UIApplyResult.failure('Unsupported A2UI message "$type".');
      }

      if (!result.success) return result;
      primarySurfaceId = result.primarySurfaceId ?? primarySurfaceId;
    }

    _surfaces
      ..clear()
      ..addAll(working);

    return A2UIApplyResult(
      success: true,
      affectedSurfaceIds: affected,
      primarySurfaceId: primarySurfaceId,
    );
  }

  A2UIApplyResult _applyCreateSurface(
    Map<String, A2UISurfaceState> working,
    Map<String, dynamic> data,
    String basePath,
    Set<String> affected,
  ) {
    final surfaceId = _readSurfaceId(data);
    if (surfaceId == null) {
      return A2UIApplyResult.failure(
        'A2UI createSurface is missing "surfaceId".',
      );
    }
    if (working.containsKey(surfaceId)) {
      return A2UIApplyResult.failure(
        'INTEGRITY_ERROR: surface "$surfaceId" already exists. '
        'Delete it before creating it again.',
      );
    }

    final catalogId = (data['catalogId']?.toString().trim().isNotEmpty ?? false)
        ? data['catalogId'].toString().trim()
        : 'basic/v1';

    final components = <String, Map<String, dynamic>>{};
    final errors = <JsonSchemaError>[];
    if (data.containsKey('components')) {
      A2UIValidator.normalizeComponents(
        data['components'],
        '$basePath/components',
        components,
        errors,
      );
    }
    errors.addAll(A2UIValidator.validateComponentShapes(components));
    if (errors.isNotEmpty) {
      return _schemaFailure(errors, surfaceId);
    }

    final dataModel = <String, dynamic>{};
    if (data.containsKey('dataModel')) {
      final rawDataModel = data['dataModel'];
      if (rawDataModel is! Map) {
        return A2UIApplyResult.failure(
          'A2UI createSurface "dataModel" must be an object.',
        );
      }
      dataModel.addAll(_copyMap(Map<String, dynamic>.from(rawDataModel)));
    }

    working[surfaceId] = A2UISurfaceState(
      surfaceId: surfaceId,
      catalogId: catalogId,
      components: components,
      dataModel: dataModel,
    );
    affected.add(surfaceId);
    return A2UIApplyResult(
      success: true,
      affectedSurfaceIds: {surfaceId},
      primarySurfaceId: surfaceId,
    );
  }

  A2UIApplyResult _applyUpdateComponents(
    Map<String, A2UISurfaceState> working,
    Map<String, dynamic> data,
    String basePath,
    Set<String> affected,
  ) {
    final surfaceId = _readSurfaceId(data);
    if (surfaceId == null) {
      return A2UIApplyResult.failure(
        'A2UI updateComponents is missing "surfaceId".',
      );
    }
    final current = working[surfaceId];
    if (current == null || current.isDeleted) {
      return A2UIApplyResult.failure(
        'A2UI updateComponents targets unknown surface "$surfaceId".',
      );
    }
    if (!data.containsKey('components')) {
      return A2UIApplyResult.failure(
        'A2UI updateComponents is missing "components".',
      );
    }

    final incoming = <String, Map<String, dynamic>>{};
    final errors = <JsonSchemaError>[];
    A2UIValidator.normalizeComponents(
      data['components'],
      '$basePath/components',
      incoming,
      errors,
    );
    errors.addAll(A2UIValidator.validateComponentShapes(incoming));
    if (errors.isNotEmpty) {
      return _schemaFailure(errors, surfaceId);
    }

    final merged = _copyComponents(current.components)..addAll(incoming);
    working[surfaceId] = current.copyWith(components: merged);
    affected.add(surfaceId);
    return A2UIApplyResult(
      success: true,
      affectedSurfaceIds: {surfaceId},
      primarySurfaceId: surfaceId,
    );
  }

  A2UIApplyResult _applyUpdateDataModel(
    Map<String, A2UISurfaceState> working,
    Map<String, dynamic> data,
    Set<String> affected,
  ) {
    final surfaceId = _readSurfaceId(data);
    if (surfaceId == null) {
      return A2UIApplyResult.failure(
        'A2UI updateDataModel is missing "surfaceId".',
      );
    }
    final current = working[surfaceId];
    if (current == null || current.isDeleted) {
      return A2UIApplyResult.failure(
        'A2UI updateDataModel targets unknown surface "$surfaceId".',
      );
    }
    if (!data.containsKey('value')) {
      return A2UIApplyResult.failure(
        'A2UI updateDataModel is missing "value".',
      );
    }

    final path = (data['path']?.toString() ?? '/').trim();
    final updated = _copyMap(current.dataModel);
    try {
      _setPointer(updated, path, data['value']);
    } catch (e) {
      return A2UIApplyResult.failure(
        'Invalid updateDataModel path "$path": $e',
      );
    }

    working[surfaceId] = current.copyWith(dataModel: updated);
    affected.add(surfaceId);
    return A2UIApplyResult(
      success: true,
      affectedSurfaceIds: {surfaceId},
      primarySurfaceId: surfaceId,
    );
  }

  A2UIApplyResult _applyDeleteSurface(
    Map<String, A2UISurfaceState> working,
    Map<String, dynamic> data,
    Set<String> affected,
  ) {
    final surfaceId = _readSurfaceId(data);
    if (surfaceId == null) {
      return A2UIApplyResult.failure(
        'A2UI deleteSurface is missing "surfaceId".',
      );
    }

    // A2UI defines deleting a non-existent surface as a no-op.
    working.remove(surfaceId);
    affected.add(surfaceId);
    return A2UIApplyResult(
      success: true,
      affectedSurfaceIds: {surfaceId},
      primarySurfaceId: surfaceId,
    );
  }

  String? _readSurfaceId(Map<String, dynamic> data) {
    final raw = data['surfaceId'];
    if (raw == null) return null;
    final value = raw.toString().trim();
    if (value.isEmpty) return null;
    return value;
  }

  A2UIApplyResult _schemaFailure(
    List<JsonSchemaError> errors,
    String surfaceId,
  ) {
    final summary = JsonSchemaValidationResult.failure(errors)
        .formatErrorSummary(contextName: 'A2UI surface "$surfaceId"');
    return A2UIApplyResult.failure(summary, errors: errors);
  }

  static Map<String, Map<String, dynamic>> _copyComponents(
    Map<String, Map<String, dynamic>> source,
  ) {
    return {
      for (final entry in source.entries)
        entry.key: _copyMap(entry.value),
    };
  }

  static Map<String, dynamic> _copyMap(Map<String, dynamic> source) {
    return json.decode(json.encode(source)) as Map<String, dynamic>;
  }

  /// Sets [value] at an RFC 6901 JSON Pointer [path].
  ///
  /// A missing intermediate object is created. A null value removes the key at
  /// the path. The root path (`/` or empty) replaces the whole data model and
  /// therefore requires an object value.
  static void _setPointer(
    Map<String, dynamic> model,
    String path,
    dynamic value,
  ) {
    JsonPointerResolver.setValue(model, path, value);
  }
}
