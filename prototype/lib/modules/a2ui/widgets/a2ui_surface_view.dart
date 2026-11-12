import 'package:flutter/material.dart';
import '../a2ui_surface_store.dart';
import '../json_pointer_resolver.dart';
import 'a2ui_component_registry.dart';

/// Renders a live [A2UISurfaceState] as native Flutter widgets.
///
/// The surface is supplied by the session-level surface store, so updates to
/// the same `surfaceId` rebuild the original widget in place. Components whose
/// referenced children have not arrived yet are omitted from the widget tree;
/// they remain in the surface state and appear when a later update resolves
/// them.
class A2UISurfaceView extends StatefulWidget {
  /// Live surface state to render.
  final A2UISurfaceState? surface;

  /// Callback invoked when an interactive component fires an action.
  final void Function(
    String componentId,
    String action,
    Map<String, dynamic> dataModel,
  )? onAction;

  /// Callback invoked for in-progress value changes that must update the live
  /// data model without starting a model turn.
  final void Function(String path, dynamic value)? onValueChanged;

  /// True while the model is executing a turn.
  final bool isModelExecuting;

  const A2UISurfaceView({
    super.key,
    required this.surface,
    this.onAction,
    this.onValueChanged,
    this.isModelExecuting = false,
  });

  @override
  State<A2UISurfaceView> createState() => _A2UISurfaceViewState();
}

class _A2UISurfaceViewState extends State<A2UISurfaceView> {
  /// Component IDs whose action is waiting for the model to respond.
  final Set<String> _pendingComponentIds = <String>{};

  @override
  void didUpdateWidget(covariant A2UISurfaceView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A different surface owns a different pending set.
    if (oldWidget.surface?.surfaceId != widget.surface?.surfaceId) {
      _pendingComponentIds.clear();
      return;
    }

    // The model turn finished, so no button should remain stuck in its pending
    // state even if the response did not update the surface.
    if (oldWidget.isModelExecuting && !widget.isModelExecuting) {
      _pendingComponentIds.clear();
    }
  }

  void _handleComponentAction(
    String componentId,
    String action,
    Map<String, dynamic> dataModel,
  ) {
    if (action.trim().isEmpty) return;
    if (!_pendingComponentIds.contains(componentId)) {
      setState(() => _pendingComponentIds.add(componentId));
    }
    widget.onAction?.call(componentId, action, dataModel);
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.surface;
    if (current == null || current.isDeleted) return const SizedBox.shrink();

    final rootId = current.rootId;
    if (rootId == null) return const SizedBox.shrink();

    try {
      return _ComponentNode(
        componentId: rootId,
        componentsMap: current.components,
        dataModel: current.dataModel,
        catalogId: current.catalogId,
        pendingComponentIds: _pendingComponentIds,
        onComponentAction: _handleComponentAction,
        onValueChanged: widget.onValueChanged,
      );
    } catch (e) {
      debugPrint('A2UI render error for surface "${current.surfaceId}": $e');
      return const SizedBox.shrink();
    }
  }
}

/// Recursive node that renders an A2UI component by dispatching to [A2UIComponentRegistry].
class _ComponentNode extends StatelessWidget {
  final String componentId;
  final Map<String, Map<String, dynamic>> componentsMap;
  final Map<String, dynamic> dataModel;
  final String catalogId;
  final Set<String> pendingComponentIds;
  final void Function(
    String componentId,
    String action,
    Map<String, dynamic> dataModel,
  ) onComponentAction;
  final void Function(String path, dynamic value)? onValueChanged;

  const _ComponentNode({
    required this.componentId,
    required this.componentsMap,
    required this.dataModel,
    required this.catalogId,
    required this.pendingComponentIds,
    required this.onComponentAction,
    this.onValueChanged,
  });

  @override
  Widget build(BuildContext context) {
    final comp = componentsMap[componentId];
    if (comp == null) {
      return const SizedBox.shrink();
    }

    final componentType =
        comp['component']?.toString() ?? comp['type']?.toString() ?? '';

    // Merge direct properties and nested properties map
    final properties = <String, dynamic>{};
    if (comp['properties'] is Map) {
      properties.addAll(Map<String, dynamic>.from(comp['properties'] as Map));
    }
    // Also copy top-level properties (ignoring metadata keys)
    for (final entry in comp.entries) {
      if (entry.key != 'id' &&
          entry.key != 'component' &&
          entry.key != 'type' &&
          entry.key != 'properties') {
        properties[entry.key] = entry.value;
      }
    }

    // A container whose required child has not arrived yet is omitted entirely
    // rather than rendered as an empty shell. Multi-child containers filter
    // unresolved children instead.
    if (_hasMissingRequiredChild(componentType, properties)) {
      return const SizedBox.shrink();
    }

    final builder = A2UIComponentRegistry.instance.getBuilder(componentType);
    if (builder == null) {
      return _buildUnknown(componentType);
    }

    final componentContext = A2UIComponentContext(
      id: componentId,
      componentType: componentType,
      properties: properties,
      componentsMap: componentsMap,
      dataModel: dataModel,
      isPending: pendingComponentIds.contains(componentId),
      onAction: (action, updatedModel) =>
          onComponentAction(componentId, action, updatedModel),
      onValueChanged: onValueChanged,
      buildChild: (childId, {scopedDataModel}) {
        if (!componentsMap.containsKey(childId)) {
          return const SizedBox.shrink();
        }
        return _ComponentNode(
          componentId: childId,
          componentsMap: componentsMap,
          dataModel: scopedDataModel ?? dataModel,
          catalogId: catalogId,
          pendingComponentIds: pendingComponentIds,
          onComponentAction: onComponentAction,
          onValueChanged: onValueChanged,
        );
      },
      buildChildren: (childIds, {scopedDataModel}) => childIds
          .where(componentsMap.containsKey)
          .map((cid) => _ComponentNode(
                componentId: cid,
                componentsMap: componentsMap,
                dataModel: scopedDataModel ?? dataModel,
                catalogId: catalogId,
                pendingComponentIds: pendingComponentIds,
                onComponentAction: onComponentAction,
                onValueChanged: onValueChanged,
              ))
          .toList(),
      resolveBinding: (val) => JsonPointerResolver.resolve(val, dataModel),
    );

    return builder(context, componentContext);
  }

  /// True when a single-child container references a component that does not
  /// exist yet. Such a container is omitted until the child arrives.
  bool _hasMissingRequiredChild(
    String componentType,
    Map<String, dynamic> properties,
  ) {
    bool missing(String key) {
      final value = properties[key];
      return value is String &&
          value.trim().isNotEmpty &&
          !componentsMap.containsKey(value.trim());
    }

    switch (componentType) {
      case 'Card':
        return missing('child');
      case 'Modal':
        return missing('trigger') || missing('content');
      case 'Tabs':
        final tabs = properties['tabs'];
        if (tabs is List) {
          for (final tab in tabs) {
            if (tab is Map) {
              final child = tab['child'];
              if (child is String &&
                  child.trim().isNotEmpty &&
                  !componentsMap.containsKey(child.trim())) {
                return true;
              }
            }
          }
        }
        return false;
      default:
        return false;
    }
  }

  Widget _buildUnknown(String type) {
    // Unknown types are rejected by the surface store before rendering. This
    // guard only handles stale persisted surfaces; omit the node rather than
    // showing an error inside the user's interface.
    debugPrint('A2UI: omitting unknown component "$type".');
    return const SizedBox.shrink();
  }
}
