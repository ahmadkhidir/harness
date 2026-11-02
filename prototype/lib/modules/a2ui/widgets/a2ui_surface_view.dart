import 'package:flutter/material.dart';
import '../a2ui_validator.dart';
import '../catalogs/basic_v1_catalog.dart';
import 'a2ui_component_registry.dart';

/// Renders a declarative Agent-to-User Interface (A2UI) surface compiled into native Flutter widgets.
///
/// Implements FEAT-006:
/// - Compiles declarative A2UI message streams into native Flutter widget trees.
/// - Supports all 18 official `basic/v1` components via [A2UIComponentRegistry].
/// - Resolves runtime dynamic data model values bound via JSON Pointers (`@path: /field` or `${/field}`).
/// - Gracefully captures malformed syntax and renders a fallback notice without crashing the UI isolate.
class A2UISurfaceView extends StatelessWidget {
  final Map<String, dynamic>? payload;
  final void Function(String action, Map<String, dynamic> dataModel)? onAction;

  const A2UISurfaceView({
    super.key,
    required this.payload,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    if (payload == null) {
      return _buildFallback(context, 'No A2UI payload provided.');
    }

    final validation = A2UIValidator.validate(payload);
    if (!validation.isValid) {
      return _buildFallback(context, validation.errorMessage ?? 'Invalid A2UI payload.');
    }

    try {
      return _ComponentNode(
        componentId: validation.rootComponentId!,
        componentsMap: validation.componentsMap,
        dataModel: validation.dataModel,
        catalogId: validation.catalogId ?? 'basic/v1',
        onAction: onAction,
      );
    } catch (e) {
      return _buildFallback(context, 'Error compiling A2UI surface: $e');
    }
  }

  Widget _buildFallback(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'A2UI notice: $message',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Recursive node that renders an A2UI component by dispatching to [A2UIComponentRegistry].
class _ComponentNode extends StatelessWidget {
  final String componentId;
  final Map<String, Map<String, dynamic>> componentsMap;
  final Map<String, dynamic> dataModel;
  final String catalogId;
  final void Function(String action, Map<String, dynamic> dataModel)? onAction;

  const _ComponentNode({
    required this.componentId,
    required this.componentsMap,
    required this.dataModel,
    required this.catalogId,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final comp = componentsMap[componentId];
    if (comp == null) {
      return const SizedBox.shrink();
    }

    final componentType = comp['component']?.toString() ?? comp['type']?.toString() ?? '';

    // Merge direct properties and nested properties map
    final properties = <String, dynamic>{};
    if (comp['properties'] is Map) {
      properties.addAll(Map<String, dynamic>.from(comp['properties'] as Map));
    }
    // Also copy top-level properties (ignoring metadata keys)
    for (final entry in comp.entries) {
      if (entry.key != 'id' && entry.key != 'component' && entry.key != 'type' && entry.key != 'properties') {
        properties[entry.key] = entry.value;
      }
    }

    final builder = A2UIComponentRegistry.instance.getBuilder(componentType);
    if (builder == null) {
      return _buildUnknown(context, componentType);
    }

    final componentContext = A2UIComponentContext(
      id: componentId,
      componentType: componentType,
      properties: properties,
      componentsMap: componentsMap,
      dataModel: dataModel,
      onAction: onAction,
      buildChild: (childId, {scopedDataModel}) => _ComponentNode(
        componentId: childId,
        componentsMap: componentsMap,
        dataModel: scopedDataModel ?? dataModel,
        catalogId: catalogId,
        onAction: onAction,
      ),
      buildChildren: (childIds, {scopedDataModel}) => childIds
          .map((cid) => _ComponentNode(
                componentId: cid,
                componentsMap: componentsMap,
                dataModel: scopedDataModel ?? dataModel,
                catalogId: catalogId,
                onAction: onAction,
              ))
          .toList(),
      resolveBinding: (val) => JsonPointerResolver.resolve(val, dataModel),
    );

    return builder(context, componentContext);
  }

  Widget _buildUnknown(BuildContext context, String type) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        'Unknown component "$type"',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
