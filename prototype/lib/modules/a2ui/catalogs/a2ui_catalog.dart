/// Extensible catalog definition and catalog registry for Agent-to-User Interface (A2UI).
///
/// Implements FEAT-006:
/// - Allows modular registration of UI catalogs (e.g. `basic/v1`, custom domain catalogs).
/// - Fast O(1) resolution by catalog URI ID or friendly alias.
/// - Allows third-party modules or updates to easily plug new catalogs into the harness.
library;

/// Contract for an A2UI Component Catalog.
abstract class A2UICatalog {
  /// The canonical URI identifier for this catalog.
  ///
  /// Example: `https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json`
  String get catalogId;

  /// Friendly aliases mapped to this catalog (e.g. `['basic/v1']`).
  List<String> get aliases;

  /// Human-readable title of the catalog.
  String get title;

  /// Brief description of the catalog's capabilities.
  String get description;

  /// Markdown / text documentation returned to the agent when loaded via `load_a2ui_catalog`.
  String get documentation;
}

/// Central registry managing available A2UI catalogs.
///
/// Modular and easily extensible:
/// ```dart
/// A2UICatalogRegistry.instance.register(MyCustomCatalog());
/// ```
class A2UICatalogRegistry {
  static final A2UICatalogRegistry _instance = A2UICatalogRegistry._internal();

  /// Global singleton instance.
  static A2UICatalogRegistry get instance => _instance;

  final Map<String, A2UICatalog> _catalogs = {};

  A2UICatalogRegistry._internal();

  /// Registers an [A2UICatalog] under its canonical [catalogId] and all its [aliases].
  void register(A2UICatalog catalog) {
    _catalogs[catalog.catalogId] = catalog;
    for (final alias in catalog.aliases) {
      _catalogs[alias] = catalog;
    }
  }

  /// Retrieves a catalog by its canonical ID or alias. Returns null if not found.
  A2UICatalog? get(String idOrAlias) {
    return _catalogs[idOrAlias.trim()];
  }

  /// Returns true if a catalog with the given ID or alias is registered.
  bool contains(String idOrAlias) {
    return _catalogs.containsKey(idOrAlias.trim());
  }

  /// Returns a deduplicated list of all registered catalogs.
  List<A2UICatalog> get allCatalogs {
    return _catalogs.values.toSet().toList();
  }

  /// Clears custom registrations and resets the registry (useful for unit tests).
  void reset() {
    _catalogs.clear();
  }
}
