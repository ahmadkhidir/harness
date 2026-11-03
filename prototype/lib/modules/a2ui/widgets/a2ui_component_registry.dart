import 'package:flutter/material.dart';
import '../catalogs/basic_v1_catalog.dart';
import 'a2ui_audio_player.dart';
import 'a2ui_media_source.dart';
import 'a2ui_video_player.dart';

/// Context provided to an [A2UIComponentBuilder] when instantiating a Flutter widget.
class A2UIComponentContext {
  /// Unique identifier of the component (e.g. "root", "t_title").
  final String id;

  /// Discriminator type of the component (e.g. "Text", "Card", "Row").
  final String componentType;

  /// Flattened component properties (combining root keys and nested "properties" map).
  final Map<String, dynamic> properties;

  /// Full dictionary of all surface components indexed by their IDs.
  final Map<String, Map<String, dynamic>> componentsMap;

  /// Runtime active data model for JSON pointer dynamic bindings.
  final Map<String, dynamic> dataModel;

  /// Optional action callback for interactive component dispatches (buttons, inputs).
  final void Function(String action, Map<String, dynamic> dataModel)? onAction;

  /// Helper to build a child component by its ID.
  final Widget Function(String childId, {Map<String, dynamic>? scopedDataModel}) buildChild;

  /// Helper to build a list of child components by their IDs.
  final List<Widget> Function(List<String> childIds, {Map<String, dynamic>? scopedDataModel}) buildChildren;

  /// Helper resolving JSON Pointer bindings against the active data model.
  final dynamic Function(dynamic value) resolveBinding;

  const A2UIComponentContext({
    required this.id,
    required this.componentType,
    required this.properties,
    required this.componentsMap,
    required this.dataModel,
    this.onAction,
    required this.buildChild,
    required this.buildChildren,
    required this.resolveBinding,
  });
}

/// Builder function signature for compiling an A2UI component into a Flutter [Widget].
typedef A2UIComponentBuilder = Widget Function(
  BuildContext context,
  A2UIComponentContext ctx,
);

/// Extensible component registry for Agent-to-User Interface (A2UI) widgets.
///
/// Implements FEAT-006:
/// - Provides a modular, easily updateable registry for A2UI component renderers.
/// - Pre-registers native Flutter builders for all 18 official A2UI Basic Catalog components.
/// - Allows developers or plugins to register custom component builders via `A2UIComponentRegistry.instance.register(...)`.
class A2UIComponentRegistry {
  static final A2UIComponentRegistry _instance = A2UIComponentRegistry._internal();

  /// Global singleton instance.
  static A2UIComponentRegistry get instance => _instance;

  final Map<String, A2UIComponentBuilder> _builders = {};

  A2UIComponentRegistry._internal() {
    _registerDefaultBuilders();
  }

  /// Registers a custom or overridden [builder] for [componentType].
  void register(String componentType, A2UIComponentBuilder builder) {
    _builders[componentType.toLowerCase()] = builder;
  }

  /// Registers multiple builders at once.
  void registerAll(Map<String, A2UIComponentBuilder> builders) {
    for (final entry in builders.entries) {
      register(entry.key, entry.value);
    }
  }

  /// Retrieves the registered builder for [componentType], case-insensitively.
  A2UIComponentBuilder? getBuilder(String componentType) {
    return _builders[componentType.toLowerCase()];
  }

  /// Checks if a builder exists for [componentType].
  bool hasBuilder(String componentType) {
    return _builders.containsKey(componentType.toLowerCase());
  }

  /// Clears custom registrations and re-initializes defaults.
  void reset() {
    _builders.clear();
    _registerDefaultBuilders();
  }

  /// Pre-registers the official 18 Basic Catalog v1.0 components.
  void _registerDefaultBuilders() {
    register('Card', _buildCard);
    register('Column', _buildColumn);
    register('Row', _buildRow);
    register('Text', _buildText);
    register('Icon', _buildIcon);
    register('Button', _buildButton);
    register('Divider', _buildDivider);
    register('Image', _buildImage);
    register('Video', _buildVideo);
    register('AudioPlayer', _buildAudioPlayer);
    register('List', _buildList);
    register('Tabs', _buildTabs);
    register('Modal', _buildModal);
    register('TextField', _buildTextField);
    register('CheckBox', _buildCheckBox);
    register('ChoicePicker', _buildChoicePicker);
    register('Slider', _buildSlider);
    register('DateTimeInput', _buildDateTimeInput);
  }

  // --- 1. Card ---
  /// Visible placeholder for structurally incomplete components.
  static Widget _buildInvalid(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildCard(BuildContext context, A2UIComponentContext ctx) {
    final theme = Theme.of(context);
    final childId = ctx.properties['child']?.toString();
    final elevation = (ctx.properties['elevation'] as num?)?.toDouble() ?? 1.0;
    final padding = (ctx.properties['padding'] as num?)?.toDouble() ?? 12.0;

    if (childId == null || childId.trim().isEmpty) {
      return _buildInvalid(context, 'Card requires a "child" component ID.');
    }

    return Card(
      elevation: elevation,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: ctx.buildChild(childId),
      ),
    );
  }

  // --- 2. Column ---
  static Widget _buildColumn(BuildContext context, A2UIComponentContext ctx) {
    final childrenIds = _extractStringList(ctx.properties['children']);
    final spacing = (ctx.properties['spacing'] as num?)?.toDouble() ?? 8.0;

    final crossAlign = _parseCrossAxisAlignment(ctx.properties['crossAxisAlignment'] ?? ctx.properties['alignment']);
    final mainAlign = _parseMainAxisAlignment(ctx.properties['mainAxisAlignment']);

    if (childrenIds.isEmpty) {
      return _buildInvalid(context, 'Column requires "children" IDs.');
    }

    final childrenWidgets = ctx.buildChildren(childrenIds);
    if (spacing <= 0 || childrenWidgets.length <= 1) {
      return Column(
        crossAxisAlignment: crossAlign,
        mainAxisAlignment: mainAlign,
        mainAxisSize: MainAxisSize.min,
        children: childrenWidgets,
      );
    }

    final spaced = <Widget>[];
    for (int i = 0; i < childrenWidgets.length; i++) {
      spaced.add(childrenWidgets[i]);
      if (i < childrenWidgets.length - 1 && spacing > 0) {
        spaced.add(SizedBox(height: spacing));
      }
    }

    return Column(
      crossAxisAlignment: crossAlign,
      mainAxisAlignment: mainAlign,
      mainAxisSize: MainAxisSize.min,
      children: spaced,
    );
  }

  // --- 3. Row ---
  static Widget _buildRow(BuildContext context, A2UIComponentContext ctx) {
    final childrenIds = _extractStringList(ctx.properties['children']);
    final spacing = (ctx.properties['spacing'] as num?)?.toDouble() ?? 8.0;

    if (childrenIds.isEmpty) {
      return _buildInvalid(context, 'Row requires "children" IDs.');
    }

    final crossAlign = _parseRowCrossAxisAlignment(ctx.properties['crossAxisAlignment']);
    final mainAlign = _parseMainAxisAlignment(ctx.properties['mainAxisAlignment'] ?? ctx.properties['alignment']);

    final childrenWidgets = ctx.buildChildren(childrenIds);
    if (childrenWidgets.isEmpty) {
      return const SizedBox.shrink();
    }

    final spaced = <Widget>[];
    for (int i = 0; i < childrenWidgets.length; i++) {
      spaced.add(childrenWidgets[i]);
      if (i < childrenWidgets.length - 1 && spacing > 0) {
        spaced.add(SizedBox(width: spacing));
      }
    }

    final row = Row(
      crossAxisAlignment: crossAlign,
      mainAxisAlignment: mainAlign,
      mainAxisSize: MainAxisSize.min,
      children: spaced,
    );

    // Component translation: Wrap Row in horizontal SingleChildScrollView so multi-item rows never overflow constraints
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: row,
    );
  }

  // --- 4. Text ---
  static Widget _buildText(BuildContext context, A2UIComponentContext ctx) {
    final theme = Theme.of(context);
    final rawText = ctx.properties['text'];
    final resolvedText = ctx.resolveBinding(rawText)?.toString() ?? '';

    final variant = ctx.properties['variant']?.toString() ?? ctx.properties['style']?.toString() ?? 'body';
    final weight = ctx.properties['fontWeight']?.toString();
    final colorStr = ctx.properties['color']?.toString();

    TextStyle style;
    switch (variant) {
      case 'headline':
        style = theme.textTheme.headlineSmall ?? const TextStyle();
        break;
      case 'title':
        style = theme.textTheme.titleMedium ?? const TextStyle();
        break;
      case 'caption':
        style = theme.textTheme.bodySmall ?? const TextStyle();
        break;
      case 'label':
        style = theme.textTheme.labelMedium ?? const TextStyle();
        break;
      case 'body':
      default:
        style = theme.textTheme.bodyMedium ?? const TextStyle();
        break;
    }

    FontWeight? fontWeight;
    if (weight != null) {
      switch (weight) {
        case 'bold':
          fontWeight = FontWeight.bold;
          break;
        case 'medium':
        case 'w600':
          fontWeight = FontWeight.w600;
          break;
        case 'normal':
          fontWeight = FontWeight.normal;
          break;
      }
    }

    Color? color = _resolveColor(colorStr, theme);

    return Text(
      resolvedText,
      style: style.copyWith(
        fontWeight: fontWeight ?? style.fontWeight,
        color: color ?? style.color,
      ),
    );
  }

  // --- 5. Icon ---
  static Widget _buildIcon(BuildContext context, A2UIComponentContext ctx) {
    final theme = Theme.of(context);
    final iconName = ctx.properties['icon']?.toString() ?? 'info';
    final size = (ctx.properties['size'] as num?)?.toDouble() ?? 24.0;
    final colorStr = ctx.properties['color']?.toString();

    final iconData = _resolveIconData(iconName);
    final color = _resolveColor(colorStr, theme) ?? theme.colorScheme.primary;

    return Icon(iconData, size: size, color: color);
  }

  // --- 6. Button ---
  static Widget _buildButton(BuildContext context, A2UIComponentContext ctx) {
    final rawLabel = ctx.properties['label'];
    var label = ctx.resolveBinding(rawLabel)?.toString();
    if (label == null || label.trim().isEmpty) {
      label = 'Action';
    }
    final action = ctx.properties['action']?.toString() ?? 'default_action';
    final style = ctx.properties['style']?.toString() ?? 'filled';
    final iconName = ctx.properties['icon']?.toString();
    final disabled = ctx.properties['disabled'] == true;

    // A2UI buttons may carry action-specific values in either a `parameters`
    // or `payload` map. Merge them over the surface data model so the event
    // router receives a single flat parameter dictionary (FEAT-007).
    final actionParameters = <String, dynamic>{};
    for (final key in const ['parameters', 'payload']) {
      final value = ctx.properties[key];
      if (value is Map) {
        actionParameters.addAll(Map<String, dynamic>.from(value));
      }
    }

    VoidCallback? onPressed = disabled
        ? null
        : () {
            final payload = Map<String, dynamic>.from(ctx.dataModel)
              ..addAll(actionParameters);
            ctx.onAction?.call(action, payload);
          };

    Widget content = iconName != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_resolveIconData(iconName), size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          )
        : Text(label);

    switch (style) {
      case 'outlined':
        return OutlinedButton(onPressed: onPressed, child: content);
      case 'text':
        return TextButton(onPressed: onPressed, child: content);
      case 'filled':
      default:
        return FilledButton(onPressed: onPressed, child: content);
    }
  }

  // --- 7. Divider ---
  static Widget _buildDivider(BuildContext context, A2UIComponentContext ctx) {
    final thickness = (ctx.properties['thickness'] as num?)?.toDouble() ?? 1.0;
    final colorStr = ctx.properties['color']?.toString();
    final color = _resolveColor(colorStr, Theme.of(context));

    return Divider(
      thickness: thickness,
      color: color,
      height: thickness * 2 + 8,
    );
  }

  // --- 8. Image ---
  static Widget _buildImage(BuildContext context, A2UIComponentContext ctx) {
    final theme = Theme.of(context);
    final rawUrl = ctx.properties['url'];
    final resolvedUrl = ctx.resolveBinding(rawUrl)?.toString() ?? '';
    final description = ctx.properties['description']?.toString();
    final fitStr = ctx.properties['fit']?.toString() ?? 'cover';
    final aspectRatio = (ctx.properties['aspectRatio'] as num?)?.toDouble();

    BoxFit fit;
    switch (fitStr) {
      case 'contain':
        fit = BoxFit.contain;
        break;
      case 'fill':
        fit = BoxFit.fill;
        break;
      case 'cover':
      default:
        fit = BoxFit.cover;
        break;
    }

    Widget brokenImage() => Container(
          height: 120,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Center(
            child: Icon(
              Icons.broken_image,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );

    Widget imageWidget;
    final media = A2UIMediaSource.resolve(resolvedUrl);
    if (media.isEmpty) {
      imageWidget = brokenImage();
    } else if (media.isLocal) {
      imageWidget = Image.file(
        media.file!,
        semanticLabel: description,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => brokenImage(),
      );
    } else {
      imageWidget = Image.network(
        media.networkUrl!,
        semanticLabel: description,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => brokenImage(),
      );
    }

    if (aspectRatio != null && aspectRatio > 0) {
      imageWidget = AspectRatio(aspectRatio: aspectRatio, child: imageWidget);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: imageWidget,
    );
  }

  // --- 9. Video ---
  static Widget _buildVideo(BuildContext context, A2UIComponentContext ctx) {
    final rawUrl = ctx.properties['url'];
    final resolvedUrl = ctx.resolveBinding(rawUrl)?.toString() ?? '';
    final autoPlay = ctx.properties['autoPlay'] == true;
    final controls = ctx.properties['controls'] != false;
    final aspectRatio = (ctx.properties['aspectRatio'] as num?)?.toDouble();

    return A2UIVideoPlayer(
      url: resolvedUrl,
      autoPlay: autoPlay,
      controls: controls,
      aspectRatio: aspectRatio,
    );
  }

  // --- 10. AudioPlayer ---
  static Widget _buildAudioPlayer(BuildContext context, A2UIComponentContext ctx) {
    final rawUrl = ctx.properties['url'];
    final resolvedUrl = ctx.resolveBinding(rawUrl)?.toString() ?? '';
    final rawTitle = ctx.properties['title'];
    final resolvedTitle = ctx.resolveBinding(rawTitle)?.toString() ?? 'Audio Track';
    final autoPlay = ctx.properties['autoPlay'] == true;

    return A2UIAudioPlayer(
      url: resolvedUrl,
      title: resolvedTitle,
      autoPlay: autoPlay,
    );
  }

  // --- 11. List ---
  static Widget _buildList(BuildContext context, A2UIComponentContext ctx) {
    final childrenProp = ctx.properties['children'];
    final direction = ctx.properties['direction']?.toString() ?? 'vertical';
    final isHorizontal = direction == 'horizontal';

    if (childrenProp == null ||
        (childrenProp is List && childrenProp.isEmpty)) {
      return _buildInvalid(context, 'List requires "children" or a template.');
    }

    // Case A: Dynamic list using template binding: `{"path": "/breeds", "componentId": "breedTemplate"}`
    if (childrenProp is Map && childrenProp['path'] != null && childrenProp['componentId'] != null) {
      final path = childrenProp['path'].toString();
      final templateId = childrenProp['componentId'].toString();
      final rawList = JsonPointerResolver.resolvePointer(path, ctx.dataModel);

      if (rawList is List && rawList.isNotEmpty) {
        final items = <Widget>[];
        for (final item in rawList) {
          final scopedModel = Map<String, dynamic>.from(ctx.dataModel);
          if (item is Map) {
            scopedModel.addAll(Map<String, dynamic>.from(item));
          }
          items.add(ctx.buildChild(templateId, scopedDataModel: scopedModel));
        }

        if (isHorizontal) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: items.map((w) => Padding(padding: const EdgeInsets.only(right: 8), child: w)).toList(),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: items.map((w) => Padding(padding: const EdgeInsets.only(bottom: 8), child: w)).toList(),
        );
      }
    }

    // Case B: Static list of IDs
    final childrenIds = _extractStringList(childrenProp);
    final widgets = ctx.buildChildren(childrenIds);

    if (isHorizontal) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: widgets.map((w) => Padding(padding: const EdgeInsets.only(right: 8), child: w)).toList(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: widgets.map((w) => Padding(padding: const EdgeInsets.only(bottom: 8), child: w)).toList(),
    );
  }

  // --- 12. Tabs ---
  static Widget _buildTabs(BuildContext context, A2UIComponentContext ctx) {
    final theme = Theme.of(context);
    final rawTabs = ctx.properties['tabs'];
    if (rawTabs is! List || rawTabs.isEmpty) {
      return const SizedBox.shrink();
    }

    return _StatefulTabsWidget(
      tabsData: rawTabs,
      buildChild: ctx.buildChild,
      theme: theme,
    );
  }

  // --- 13. Modal ---
  static Widget _buildModal(BuildContext context, A2UIComponentContext ctx) {
    final triggerId = ctx.properties['trigger']?.toString();
    final contentId = ctx.properties['content']?.toString();
    final title = ctx.properties['title']?.toString() ?? 'Details';

    final triggerWidget = triggerId != null ? ctx.buildChild(triggerId) : const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        if (contentId != null) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (bContext) => ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(bContext).size.height * 0.85,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(bContext).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      ctx.buildChild(contentId),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      },
      child: triggerWidget,
    );
  }

  // --- 14. TextField ---
  static Widget _buildTextField(BuildContext context, A2UIComponentContext ctx) {
    final label = ctx.properties['label']?.toString() ?? '';
    final placeholder = ctx.properties['placeholder']?.toString();
    final rawValue = ctx.properties['value'];
    final initialValue = ctx.resolveBinding(rawValue)?.toString() ?? '';
    final variant = ctx.properties['variant']?.toString() ?? 'text';
    final isPassword = variant == 'password';
    final isNumber = variant == 'number';
    final isMultiline = variant == 'multiline';

    return TextField(
      controller: TextEditingController(text: initialValue),
      obscureText: isPassword,
      keyboardType: isNumber
          ? TextInputType.number
          : (isMultiline ? TextInputType.multiline : TextInputType.text),
      maxLines: isMultiline ? 3 : 1,
      decoration: InputDecoration(
        labelText: label.isNotEmpty ? label : null,
        hintText: placeholder,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (val) {
        final action = ctx.properties['onChange']?.toString();
        if (action != null) {
          final updatedModel = Map<String, dynamic>.from(ctx.dataModel)..[action] = val;
          ctx.onAction?.call(action, updatedModel);
        }
      },
    );
  }

  // --- 15. CheckBox ---
  static Widget _buildCheckBox(BuildContext context, A2UIComponentContext ctx) {
    final label = ctx.properties['label']?.toString() ?? '';
    final rawValue = ctx.properties['value'];
    final resolvedVal = ctx.resolveBinding(rawValue);
    final isChecked = resolvedVal == true || resolvedVal == 'true';

    return CheckboxListTile(
      title: Text(label),
      value: isChecked,
      dense: true,
      contentPadding: EdgeInsets.zero,
      onChanged: (val) {
        final action = ctx.properties['onChange']?.toString() ?? 'toggle_check';
        final updated = Map<String, dynamic>.from(ctx.dataModel)..[action] = val;
        ctx.onAction?.call(action, updated);
      },
    );
  }

  // --- 16. ChoicePicker ---
  static Widget _buildChoicePicker(BuildContext context, A2UIComponentContext ctx) {
    final label = ctx.properties['label']?.toString() ?? '';
    final rawOptions = ctx.properties['options'];
    final rawValue = ctx.properties['value'];
    final selectedValue = ctx.resolveBinding(rawValue)?.toString();

    final options = <Map<String, String>>[];
    if (rawOptions is List) {
      for (final opt in rawOptions) {
        if (opt is Map) {
          options.add({
            'label': opt['label']?.toString() ?? '',
            'value': opt['value']?.toString() ?? '',
          });
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
        Wrap(
          spacing: 8,
          children: options.map((opt) {
            final isSelected = opt['value'] == selectedValue;
            return ChoiceChip(
              label: Text(opt['label']!),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  final action = ctx.properties['onChange']?.toString() ?? 'select_choice';
                  final updated = Map<String, dynamic>.from(ctx.dataModel)..[action] = opt['value'];
                  ctx.onAction?.call(action, updated);
                }
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  // --- 17. Slider ---
  static Widget _buildSlider(BuildContext context, A2UIComponentContext ctx) {
    final label = ctx.properties['label']?.toString() ?? '';
    final rawValue = ctx.properties['value'];
    final numVal = (ctx.resolveBinding(rawValue) as num?)?.toDouble() ?? 0.0;
    final min = (ctx.properties['min'] as num?)?.toDouble() ?? 0.0;
    final max = (ctx.properties['max'] as num?)?.toDouble() ?? 100.0;
    final step = (ctx.properties['step'] as num?)?.toDouble() ?? 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty)
          Text('$label: ${numVal.toStringAsFixed(1)}', style: Theme.of(context).textTheme.labelMedium),
        Slider(
          value: numVal.clamp(min, max),
          min: min,
          max: max,
          divisions: max > min && step > 0 ? ((max - min) / step).round() : null,
          onChanged: (val) {
            final action = ctx.properties['onChange']?.toString() ?? 'slider_change';
            final updated = Map<String, dynamic>.from(ctx.dataModel)..[action] = val;
            ctx.onAction?.call(action, updated);
          },
        ),
      ],
    );
  }

  // --- 18. DateTimeInput ---
  static Widget _buildDateTimeInput(BuildContext context, A2UIComponentContext ctx) {
    final label = ctx.properties['label']?.toString() ?? 'Select Date';
    final rawValue = ctx.properties['value'];
    final dateStr = ctx.resolveBinding(rawValue)?.toString() ?? 'Tap to select';

    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today, size: 18),
      label: Text('$label: $dateStr'),
      onPressed: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: now,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (picked != null) {
          final action = ctx.properties['onChange']?.toString() ?? 'date_selected';
          final formatted = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
          final updated = Map<String, dynamic>.from(ctx.dataModel)..[action] = formatted;
          ctx.onAction?.call(action, updated);
        }
      },
    );
  }

  // --- Helpers ---
  static List<String> _extractStringList(dynamic value) {
    if (value is! List) return const [];
    return value.where((e) => e != null).map((e) => e.toString()).toList();
  }

  static CrossAxisAlignment _parseCrossAxisAlignment(dynamic val) {
    switch (val?.toString()) {
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

  static CrossAxisAlignment _parseRowCrossAxisAlignment(dynamic val) {
    switch (val?.toString()) {
      case 'start':
        return CrossAxisAlignment.start;
      case 'end':
        return CrossAxisAlignment.end;
      case 'stretch':
        return CrossAxisAlignment.stretch;
      case 'center':
      default:
        return CrossAxisAlignment.center;
    }
  }

  static MainAxisAlignment _parseMainAxisAlignment(dynamic val) {
    switch (val?.toString()) {
      case 'center':
        return MainAxisAlignment.center;
      case 'end':
        return MainAxisAlignment.end;
      case 'spaceBetween':
        return MainAxisAlignment.spaceBetween;
      case 'spaceAround':
        return MainAxisAlignment.spaceAround;
      case 'spaceEvenly':
        return MainAxisAlignment.spaceEvenly;
      case 'start':
      default:
        return MainAxisAlignment.start;
    }
  }

  static Color? _resolveColor(String? colorStr, ThemeData theme) {
    if (colorStr == null) return null;
    switch (colorStr) {
      case 'primary':
        return theme.colorScheme.primary;
      case 'secondary':
        return theme.colorScheme.secondary;
      case 'error':
        return theme.colorScheme.error;
      case 'success':
        return Colors.green.shade600;
      case 'warning':
        return Colors.amber.shade700;
      case 'onSurface':
        return theme.colorScheme.onSurface;
      default:
        if (colorStr.startsWith('#')) {
          final hex = colorStr.replaceAll('#', '');
          if (hex.length == 6) {
            final val = int.tryParse('FF$hex', radix: 16);
            if (val != null) return Color(val);
          }
        }
        return null;
    }
  }

  static IconData _resolveIconData(String name) {
    switch (name) {
      case 'check':
        return Icons.check;
      case 'check_circle':
        return Icons.check_circle_outline;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'error':
        return Icons.error_outline;
      case 'info':
        return Icons.info_outline;
      case 'star':
        return Icons.star;
      case 'flight':
        return Icons.flight;
      case 'close':
        return Icons.close;
      case 'settings':
        return Icons.settings;
      case 'schedule':
        return Icons.schedule;
      case 'event':
        return Icons.event;
      case 'search':
        return Icons.search;
      case 'send':
        return Icons.send;
      case 'refresh':
        return Icons.refresh;
      case 'menu':
        return Icons.menu;
      default:
        return Icons.info_outline;
    }
  }
}

class _StatefulTabsWidget extends StatefulWidget {
  final List tabsData;
  final Widget Function(String childId) buildChild;
  final ThemeData theme;

  const _StatefulTabsWidget({
    required this.tabsData,
    required this.buildChild,
    required this.theme,
  });

  @override
  State<_StatefulTabsWidget> createState() => _StatefulTabsWidgetState();
}

class _StatefulTabsWidgetState extends State<_StatefulTabsWidget> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabsData.whereType<Map>().toList();
    if (tabs.isEmpty) return const SizedBox.shrink();

    final activeTab = tabs[_selectedIndex.clamp(0, tabs.length - 1)];
    final activeChildId = activeTab['child']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(tabs.length, (idx) {
              final label = tabs[idx]['label']?.toString() ?? 'Tab ${idx + 1}';
              final isSelected = idx == _selectedIndex;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (val) {
                    if (val) setState(() => _selectedIndex = idx);
                  },
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
        if (activeChildId != null) widget.buildChild(activeChildId),
      ],
    );
  }
}
