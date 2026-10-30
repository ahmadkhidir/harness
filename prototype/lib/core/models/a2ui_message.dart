/// Standard A2UI v1 protocol message for constructing and updating declarative UI surfaces.
///
/// Passed inside `send_a2ui` parameters.
/// Conforms to JSON Schema `https://harness.agent/schemas/a2ui-message.schema.json`.
class A2UIMessage {
  /// A2UI specification version string (must be `"1.0"`).
  final String version;

  /// Declares a new UI surface identifier and bound catalog.
  final A2UICreateSurface? createSurface;

  /// Supplies or updates the flat component node list for a surface.
  final A2UIUpdateComponents? updateComponents;

  /// Supplies runtime data values bound via JSON Pointers (`@path`).
  final A2UIUpdateDataModel? updateDataModel;

  A2UIMessage({
    this.version = '1.0',
    this.createSurface,
    this.updateComponents,
    this.updateDataModel,
  }) {
    if (version != '1.0') {
      throw ArgumentError('A2UI version must be "1.0", got "$version".');
    }
  }

  /// Serializes the A2UI message to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      if (createSurface != null) 'createSurface': createSurface!.toJson(),
      if (updateComponents != null)
        'updateComponents': updateComponents!.toJson(),
      if (updateDataModel != null)
        'updateDataModel': updateDataModel!.toJson(),
    };
  }

  /// Deserializes an A2UI message from a JSON map.
  factory A2UIMessage.fromJson(Map<String, dynamic> json) {
    final version = json['version'] as String? ?? '1.0';
    return A2UIMessage(
      version: version,
      createSurface: json['createSurface'] != null
          ? A2UICreateSurface.fromJson(
              Map<String, dynamic>.from(json['createSurface'] as Map))
          : null,
      updateComponents: json['updateComponents'] != null
          ? A2UIUpdateComponents.fromJson(
              Map<String, dynamic>.from(json['updateComponents'] as Map))
          : null,
      updateDataModel: json['updateDataModel'] != null
          ? A2UIUpdateDataModel.fromJson(
              Map<String, dynamic>.from(json['updateDataModel'] as Map))
          : null,
    );
  }
}

/// Declares a new UI surface identifier and bound component catalog in A2UI.
class A2UICreateSurface {
  /// Unique surface identifier (e.g. `card_flight_01`).
  final String surfaceId;

  /// Catalog identifier, e.g. `basic/v1`.
  final String catalogId;

  /// Whether the client should send the data model state back upon events.
  final bool sendDataModel;

  A2UICreateSurface({
    required this.surfaceId,
    required this.catalogId,
    this.sendDataModel = false,
  }) {
    if (surfaceId.trim().isEmpty) {
      throw ArgumentError('surfaceId cannot be empty.');
    }
    if (catalogId.trim().isEmpty) {
      throw ArgumentError('catalogId cannot be empty.');
    }
  }

  /// Serializes surface creation to a JSON map.
  Map<String, dynamic> toJson() => {
        'surfaceId': surfaceId,
        'catalogId': catalogId,
        if (sendDataModel) 'sendDataModel': sendDataModel,
      };

  /// Deserializes surface creation from a JSON map.
  factory A2UICreateSurface.fromJson(Map<String, dynamic> json) =>
      A2UICreateSurface(
        surfaceId: json['surfaceId'] as String,
        catalogId: json['catalogId'] as String,
        sendDataModel: json['sendDataModel'] as bool? ?? false,
      );
}

/// Supplies or updates the flat component node list for an A2UI surface.
class A2UIUpdateComponents {
  /// Target surface identifier.
  final String surfaceId;

  /// Flat list of component definitions. Each component has `id`, `type`, and `properties`.
  final List<Map<String, dynamic>> components;

  A2UIUpdateComponents({
    required this.surfaceId,
    required this.components,
  }) {
    if (surfaceId.trim().isEmpty) {
      throw ArgumentError('surfaceId cannot be empty.');
    }
  }

  /// Serializes component updates to a JSON map.
  Map<String, dynamic> toJson() => {
        'surfaceId': surfaceId,
        'components': components,
      };

  /// Deserializes component updates from a JSON map.
  factory A2UIUpdateComponents.fromJson(Map<String, dynamic> json) =>
      A2UIUpdateComponents(
        surfaceId: json['surfaceId'] as String,
        components: (json['components'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
}

/// Supplies runtime data values bound via JSON Pointers (`@path`) in component properties.
class A2UIUpdateDataModel {
  /// Target surface identifier.
  final String surfaceId;

  /// Key-value dictionary containing runtime data values.
  final Map<String, dynamic> value;

  A2UIUpdateDataModel({
    required this.surfaceId,
    required this.value,
  }) {
    if (surfaceId.trim().isEmpty) {
      throw ArgumentError('surfaceId cannot be empty.');
    }
  }

  /// Serializes data model updates to a JSON map.
  Map<String, dynamic> toJson() => {
        'surfaceId': surfaceId,
        'value': value,
      };

  /// Deserializes data model updates from a JSON map.
  factory A2UIUpdateDataModel.fromJson(Map<String, dynamic> json) =>
      A2UIUpdateDataModel(
        surfaceId: json['surfaceId'] as String,
        value: Map<String, dynamic>.from(json['value'] as Map),
      );
}
