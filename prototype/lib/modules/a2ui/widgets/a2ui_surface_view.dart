import 'package:flutter/material.dart';
import '../catalogs/basic_v1_catalog.dart';

/// Renders a declarative Agent-to-User Interface (A2UI) surface compiled into native Flutter widgets.
///
/// Implements FEAT-006:
/// - Compiles declarative A2UI message streams into native Flutter widget trees.
/// - Supports standard `basic/v1` components: `Card`, `Column`, `Row`, `Text`, `Icon`, `Button`, `Divider`.
/// - Resolves runtime dynamic data model values bound via JSON Pointers (`@path: /field`).
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

    try {
      final messages = payload!['messages'];
      if (messages == null || messages is! List || messages.isEmpty) {
        return _buildFallback(context, 'Missing or empty A2UI messages list.');
      }

      String? surfaceId;
      String? catalogId;
      final componentsMap = <String, Map<String, dynamic>>{};
      final dataModel = <String, dynamic>{};

      for (final msgItem in messages) {
        if (msgItem is! Map) continue;
        final map = Map<String, dynamic>.from(msgItem);

        if (map.containsKey('createSurface')) {
          final create = Map<String, dynamic>.from(map['createSurface'] as Map);
          surfaceId = create['surfaceId'] as String?;
          catalogId = create['catalogId'] as String?;
        }

        if (map.containsKey('updateDataModel')) {
          final dm = Map<String, dynamic>.from(map['updateDataModel'] as Map);
          if (dm['value'] != null && dm['value'] is Map) {
            dataModel.addAll(Map<String, dynamic>.from(dm['value'] as Map));
          }
        }

        if (map.containsKey('updateComponents')) {
          final uc = Map<String, dynamic>.from(map['updateComponents'] as Map);
          final comps = uc['components'];
          if (comps != null && comps is List) {
            for (final c in comps) {
              if (c is Map) {
                final cMap = Map<String, dynamic>.from(c);
                final id = cMap['id']?.toString();
                if (id != null && id.isNotEmpty) {
                  componentsMap[id] = cMap;
                }
              }
            }
          }
        }
      }

      if (componentsMap.isEmpty) {
        return _buildFallback(context, 'No components defined for surface "$surfaceId".');
      }

      final rootId = _findRootComponentId(componentsMap);
      if (rootId == null || !componentsMap.containsKey(rootId)) {
        return _buildFallback(context, 'Cannot resolve root component for surface "$surfaceId".');
      }

      return _ComponentBuilder(
        componentId: rootId,
        componentsMap: componentsMap,
        dataModel: dataModel,
        catalogId: catalogId ?? 'basic/v1',
        onAction: onAction,
      );
    } catch (e) {
      return _buildFallback(context, 'Error compiling A2UI surface: $e');
    }
  }

  /// Identifies the root component ID from the components catalog.
  static String? _findRootComponentId(Map<String, Map<String, dynamic>> componentsMap) {
    if (componentsMap.containsKey('root')) {
      return 'root';
    }

    final allChildIds = <String>{};
    for (final comp in componentsMap.values) {
      final props = comp['properties'];
      if (props is Map) {
        if (props.containsKey('child') && props['child'] != null) {
          allChildIds.add(props['child'].toString());
        }
        if (props.containsKey('children') && props['children'] is List) {
          for (final ch in props['children'] as List) {
            allChildIds.add(ch.toString());
          }
        }
      }
    }

    for (final id in componentsMap.keys) {
      if (!allChildIds.contains(id)) {
        return id;
      }
    }

    return componentsMap.keys.first;
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

class _ComponentBuilder extends StatelessWidget {
  final String componentId;
  final Map<String, Map<String, dynamic>> componentsMap;
  final Map<String, dynamic> dataModel;
  final String catalogId;
  final void Function(String action, Map<String, dynamic> dataModel)? onAction;

  const _ComponentBuilder({
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

    final type = comp['type']?.toString() ?? '';
    final props = comp['properties'] != null && comp['properties'] is Map
        ? Map<String, dynamic>.from(comp['properties'] as Map)
        : <String, dynamic>{};

    switch (type) {
      case 'Card':
        return _buildCard(context, props);
      case 'Column':
        return _buildColumn(context, props);
      case 'Row':
        return _buildRow(context, props);
      case 'Text':
        return _buildText(context, props);
      case 'Icon':
        return _buildIcon(context, props);
      case 'Button':
        return _buildButton(context, props);
      case 'Divider':
        return _buildDivider(context, props);
      default:
        return _buildUnknown(context, type);
    }
  }

  Widget _buildCard(BuildContext context, Map<String, dynamic> props) {
    final theme = Theme.of(context);
    final childId = props['child']?.toString();
    final elevation = (props['elevation'] as num?)?.toDouble() ?? 1.0;
    final padding = (props['padding'] as num?)?.toDouble() ?? 12.0;

    return Card(
      elevation: elevation,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 0.8,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: childId != null ? _child(childId) : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildColumn(BuildContext context, Map<String, dynamic> props) {
    final childrenIds = (props['children'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];
    final spacing = (props['spacing'] as num?)?.toDouble() ?? 8.0;
    final crossAxis = _parseCrossAxisAlignment(props['crossAxisAlignment']?.toString());
    final mainAxis = _parseMainAxisAlignment(props['mainAxisAlignment']?.toString());

    final widgets = <Widget>[];
    for (int i = 0; i < childrenIds.length; i++) {
      widgets.add(_child(childrenIds[i]));
      if (i < childrenIds.length - 1 && spacing > 0) {
        widgets.add(SizedBox(height: spacing));
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxis,
      mainAxisAlignment: mainAxis,
      children: widgets,
    );
  }

  Widget _buildRow(BuildContext context, Map<String, dynamic> props) {
    final childrenIds = (props['children'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];
    final spacing = (props['spacing'] as num?)?.toDouble() ?? 8.0;
    final crossAxis = _parseRowCrossAxisAlignment(props['crossAxisAlignment']?.toString());
    final mainAxis = _parseMainAxisAlignment(props['mainAxisAlignment']?.toString());

    final widgets = <Widget>[];
    for (int i = 0; i < childrenIds.length; i++) {
      widgets.add(_child(childrenIds[i]));
      if (i < childrenIds.length - 1 && spacing > 0) {
        widgets.add(SizedBox(width: spacing));
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxis,
      mainAxisAlignment: mainAxis,
      children: widgets,
    );
  }

  Widget _buildText(BuildContext context, Map<String, dynamic> props) {
    final theme = Theme.of(context);
    final rawValue = JsonPointerResolver.resolve(props['text'], dataModel);
    final text = rawValue?.toString() ?? '';

    final styleKey = props['style']?.toString().toLowerCase();
    TextStyle baseStyle;
    switch (styleKey) {
      case 'headline':
        baseStyle = theme.textTheme.headlineSmall ?? const TextStyle();
        break;
      case 'title':
        baseStyle = theme.textTheme.titleMedium ?? const TextStyle();
        break;
      case 'caption':
        baseStyle = theme.textTheme.bodySmall ?? const TextStyle();
        break;
      case 'label':
        baseStyle = theme.textTheme.labelMedium ?? const TextStyle();
        break;
      case 'body':
      default:
        baseStyle = theme.textTheme.bodyMedium ?? const TextStyle();
        break;
    }

    final fontWeight = _parseFontWeight(props['fontWeight']?.toString());
    final color = _parseColor(props['color']?.toString(), theme);

    return Text(
      text,
      style: baseStyle.copyWith(
        fontWeight: fontWeight ?? baseStyle.fontWeight,
        color: color ?? baseStyle.color,
      ),
    );
  }

  Widget _buildIcon(BuildContext context, Map<String, dynamic> props) {
    final theme = Theme.of(context);
    final iconName = props['icon']?.toString() ?? 'info';
    final size = (props['size'] as num?)?.toDouble() ?? 24.0;
    final color = _parseColor(props['color']?.toString(), theme) ??
        theme.colorScheme.primary;

    final iconData = _resolveIconData(iconName);
    return Icon(iconData, size: size, color: color);
  }

  Widget _buildButton(BuildContext context, Map<String, dynamic> props) {
    final rawLabel = JsonPointerResolver.resolve(props['label'], dataModel);
    final label = rawLabel?.toString() ?? 'Action';
    final action = props['action']?.toString() ?? 'action';
    final style = props['style']?.toString().toLowerCase() ?? 'filled';
    final iconName = props['icon']?.toString();

    Widget labelWidget = Text(label);

    void handlePress() {
      if (onAction != null) {
        onAction!(action, dataModel);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Action "$action" triggered.'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }

    if (iconName != null) {
      final icon = Icon(_resolveIconData(iconName), size: 18);
      switch (style) {
        case 'outlined':
          return OutlinedButton.icon(
            icon: icon,
            label: labelWidget,
            onPressed: handlePress,
          );
        case 'text':
          return TextButton.icon(
            icon: icon,
            label: labelWidget,
            onPressed: handlePress,
          );
        case 'filled':
        default:
          return FilledButton.icon(
            icon: icon,
            label: labelWidget,
            onPressed: handlePress,
          );
      }
    }

    switch (style) {
      case 'outlined':
        return OutlinedButton(onPressed: handlePress, child: labelWidget);
      case 'text':
        return TextButton(onPressed: handlePress, child: labelWidget);
      case 'filled':
      default:
        return FilledButton(onPressed: handlePress, child: labelWidget);
    }
  }

  Widget _buildDivider(BuildContext context, Map<String, dynamic> props) {
    final theme = Theme.of(context);
    final thickness = (props['thickness'] as num?)?.toDouble() ?? 1.0;
    final color = _parseColor(props['color']?.toString(), theme);

    return Divider(thickness: thickness, color: color);
  }

  Widget _buildUnknown(BuildContext context, String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Unknown component "$type"',
        style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
      ),
    );
  }

  Widget _child(String id) {
    return _ComponentBuilder(
      componentId: id,
      componentsMap: componentsMap,
      dataModel: dataModel,
      catalogId: catalogId,
      onAction: onAction,
    );
  }

  static CrossAxisAlignment _parseCrossAxisAlignment(String? val) {
    switch (val?.toLowerCase()) {
      case 'center':
        return CrossAxisAlignment.center;
      case 'end':
        return CrossAxisAlignment.end;
      case 'stretch':
        return CrossAxisAlignment.stretch;
      case 'start':
      default:
        return CrossAxisAlignment.start;
    }
  }

  static CrossAxisAlignment _parseRowCrossAxisAlignment(String? val) {
    switch (val?.toLowerCase()) {
      case 'start':
        return CrossAxisAlignment.start;
      case 'end':
        return CrossAxisAlignment.end;
      case 'center':
      default:
        return CrossAxisAlignment.center;
    }
  }

  static MainAxisAlignment _parseMainAxisAlignment(String? val) {
    switch (val?.toLowerCase()) {
      case 'center':
        return MainAxisAlignment.center;
      case 'end':
        return MainAxisAlignment.end;
      case 'spacebetween':
      case 'space_between':
        return MainAxisAlignment.spaceBetween;
      case 'start':
      default:
        return MainAxisAlignment.start;
    }
  }

  static FontWeight? _parseFontWeight(String? val) {
    switch (val?.toLowerCase()) {
      case 'bold':
        return FontWeight.bold;
      case 'w600':
      case 'medium':
        return FontWeight.w600;
      case 'normal':
        return FontWeight.normal;
      default:
        return null;
    }
  }

  static Color? _parseColor(String? colorStr, ThemeData theme) {
    if (colorStr == null || colorStr.trim().isEmpty) return null;
    final clean = colorStr.trim().toLowerCase();

    switch (clean) {
      case 'primary':
        return theme.colorScheme.primary;
      case 'secondary':
        return theme.colorScheme.secondary;
      case 'error':
        return theme.colorScheme.error;
      case 'success':
        return Colors.green.shade700;
      case 'warning':
        return Colors.orange.shade800;
      case 'onsurface':
      case 'on_surface':
        return theme.colorScheme.onSurface;
      default:
        if (clean.startsWith('#')) {
          final hex = clean.substring(1);
          if (hex.length == 6) {
            final val = int.tryParse('FF$hex', radix: 16);
            if (val != null) return Color(val);
          } else if (hex.length == 8) {
            final val = int.tryParse(hex, radix: 16);
            if (val != null) return Color(val);
          }
        }
        return null;
    }
  }

  static IconData _resolveIconData(String name) {
    switch (name.toLowerCase()) {
      case 'check':
      case 'check_circle':
      case 'done':
        return Icons.check_circle_outline;
      case 'warning':
      case 'alert':
        return Icons.warning_amber_rounded;
      case 'error':
        return Icons.error_outline;
      case 'info':
        return Icons.info_outline;
      case 'star':
        return Icons.star_outline;
      case 'flight':
        return Icons.flight;
      case 'close':
      case 'cancel':
        return Icons.close;
      case 'settings':
        return Icons.settings;
      case 'schedule':
      case 'time':
      case 'clock':
        return Icons.schedule;
      case 'event':
      case 'calendar':
        return Icons.event;
      case 'location':
      case 'location_on':
        return Icons.location_on_outlined;
      case 'person':
      case 'user':
        return Icons.person_outline;
      case 'phone':
        return Icons.phone;
      case 'email':
      case 'mail':
        return Icons.email_outlined;
      case 'attach_money':
      case 'money':
        return Icons.attach_money;
      case 'directions_car':
      case 'car':
        return Icons.directions_car;
      default:
        return Icons.widgets_outlined;
    }
  }
}
