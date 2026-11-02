import 'a2ui_catalog.dart';

/// Full official A2UI Basic Catalog Specification and JSON Pointer Resolver.
///
/// Implements FEAT-006:
/// - Conforms to the official standard A2UI specification (`a2ui-project/a2ui` Basic Catalog v1.0).
/// - Canonical ID: `https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json`
/// - Friendly alias: `basic/v1`
/// - Defines all 18 basic components:
///   `Text`, `Image`, `Icon`, `Video`, `AudioPlayer`, `Row`, `Column`, `List`, `Card`,
///   `Tabs`, `Modal`, `Divider`, `Button`, `TextField`, `CheckBox`, `ChoicePicker`, `Slider`, `DateTimeInput`.
/// - Defines all 14 catalog functions:
///   `required`, `regex`, `length`, `numeric`, `email`, `formatString`, `formatNumber`,
///   `formatCurrency`, `formatDate`, `pluralize`, `openUrl`, `and`, `or`, `not`.
/// - Supports runtime dynamic data bindings using RFC 6901 JSON Pointers (`{"@path": "/path"}` or `"${/path}"`).
class BasicV1Catalog implements A2UICatalog {
  static const String canonicalId =
      'https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json';
  static const String shortAlias = 'basic/v1';

  @override
  String get catalogId => canonicalId;

  @override
  List<String> get aliases => const [shortAlias, canonicalId];

  @override
  String get title => 'A2UI Basic Catalog';

  @override
  String get description =>
      'Unified catalog of basic A2UI components and functions for mobile and web surfaces.';

  @override
  String get documentation => kBasicV1CatalogDocumentation;

  /// Ensures this catalog is registered in [A2UICatalogRegistry].
  static void register() {
    A2UICatalogRegistry.instance.register(BasicV1Catalog());
  }
}

/// Official documentation string returned to the model upon calling `load_a2ui_catalog`.
const String kBasicV1CatalogDocumentation = '''
# A2UI Catalog: basic/v1
Catalog ID: https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json
Alias: basic/v1
Protocol Version: 1.0

Description:
Unified declarative UI component catalog for mobile Flutter client rendering. When interactive controls, cards, forms, media players, lists, or structured status displays are needed, emit a `send_a2ui` system call.

## Catalog Guidelines
1. String Concatenation & Formatting: A2UI does not support binary operators like '+' or formatting symbols. To concatenate strings or dynamically inject data bindings into text, use `formatString("\${expression}")` or placeholder syntax:
   `"text": "Hello \${/user/name}"` or `{"@path": "/user/name"}`.
2. Strict Hierarchy: You must strictly adhere to requested component nesting. Place child components inside container `children` or `child` arrays using their IDs.
3. Supported Message Types:
   - `createSurface`: defines `surfaceId`, `catalogId`, and optional initial `components` and `dataModel`.
   - `updateComponents`: updates or supplies `components` list.
   - `updateDataModel`: updates or supplies key-value values for JSON Pointer binding.

## Supported Components (18 Components)
1. Text
   - component: "Text"
   - text: string or dynamic binding (e.g. "Hello \${/name}" or {"@path": "/name"})
   - variant: "headline" | "title" | "body" | "caption" | "label" (default "body")
   - fontWeight: "normal" | "medium" | "bold"
   - color: "primary" | "secondary" | "error" | "success" | "warning" | hex code
2. Image
   - component: "Image"
   - url: string (HTTPS image URL) or dynamic binding
   - description: string (accessibility text)
   - fit: "cover" | "contain" | "fill" | "none"
   - aspectRatio: number
3. Icon
   - component: "Icon"
   - icon: string (e.g. "check", "warning", "info", "star", "flight", "close", "settings", "search", "send", "refresh", "menu")
   - color: "primary" | "secondary" | "error" | "success" | "warning" | hex code
   - size: number (default 24)
4. Video
   - component: "Video"
   - url: string (video URL)
   - autoPlay: boolean
   - controls: boolean
5. AudioPlayer
   - component: "AudioPlayer"
   - url: string (audio URL)
   - title: string
6. Row
   - component: "Row"
   - children: list of strings (IDs of child components)
   - spacing: number (default 8)
   - alignment: "start" | "center" | "end" | "spaceBetween"
7. Column
   - component: "Column"
   - children: list of strings (IDs of child components)
   - spacing: number (default 8)
   - alignment: "start" | "center" | "end" | "stretch"
8. List
   - component: "List"
   - children: list of strings (child IDs) OR dynamic template object: `{"path": "/items", "componentId": "templateItem"}`
   - direction: "vertical" | "horizontal"
9. Card
   - component: "Card"
   - child: string (ID of root child component)
   - elevation: number (default 1)
   - padding: number (default 12)
10. Tabs
    - component: "Tabs"
    - tabs: list of objects `[{"label": "Overview", "child": "tab1_content"}, {"label": "Details", "child": "tab2_content"}]`
11. Modal
    - component: "Modal"
    - trigger: string (ID of component that triggers modal)
    - content: string (ID of modal content component)
    - title: string
12. Divider
    - component: "Divider"
    - thickness: number (default 1)
    - color: string
13. Button
    - component: "Button"
    - label: string or dynamic binding
    - action: string (event action ID sent on tap, e.g. "submit_order")
    - style: "filled" | "outlined" | "text" (default "filled")
    - icon: string (optional icon name)
    - disabled: boolean
14. TextField
    - component: "TextField"
    - label: string
    - placeholder: string
    - value: string or dynamic binding `{"@path": "/form/name"}`
    - variant: "text" | "number" | "password" | "multiline"
    - onChange: string (action ID or bound path)
15. CheckBox
    - component: "CheckBox"
    - label: string
    - value: boolean or dynamic binding
    - onChange: string (action ID)
16. ChoicePicker
    - component: "ChoicePicker"
    - label: string
    - options: list of `{"label": "Option A", "value": "a"}`
    - value: string
    - onChange: string (action ID)
17. Slider
    - component: "Slider"
    - label: string
    - value: number or dynamic binding
    - min: number (default 0)
    - max: number (default 100)
    - step: number (default 1)
18. DateTimeInput
    - component: "DateTimeInput"
    - label: string
    - variant: "date" | "time" | "datetime"
    - value: string

## Supported Catalog Functions (14 Functions)
- `formatString`: interpolates \${/path} in string templates.
- `formatNumber`: formats numbers with decimal places.
- `formatCurrency`: formats currency with symbol.
- `formatDate`: formats timestamp to standard date.
- `pluralize`: returns singular or plural string depending on count.
- `required`, `regex`, `length`, `numeric`, `email`: validation checks on input fields.
- `openUrl`: opens a URL in system browser.
- `and`, `or`, `not`: boolean logic combinators.

## Example `send_a2ui` Dispatch

Emit `<system_call>` directly (do NOT wrap it in markdown code fences):

<system_call>
{
  "command": "send_a2ui",
  "parameters": {
    "text": "Here is your requested card:",
    "messages": [
      {
        "version": "1.0",
        "createSurface": {
          "surfaceId": "main",
          "catalogId": "basic/v1",
          "components": [
            {
              "id": "root",
              "component": "Card",
              "child": "col_main"
            },
            {
              "id": "col_main",
              "component": "Column",
              "children": ["header_row", "div_sep", "details_text", "action_btn"]
            },
            {
              "id": "header_row",
              "component": "Row",
              "children": ["icon_status", "title_text"]
            },
            {
              "id": "icon_status",
              "component": "Icon",
              "icon": "check_circle",
              "color": "success"
            },
            {
              "id": "title_text",
              "component": "Text",
              "text": "\${/country/name} Ranking",
              "variant": "title"
            },
            {
              "id": "div_sep",
              "component": "Divider"
            },
            {
              "id": "details_text",
              "component": "Text",
              "text": "GDP per capita: \${/country/gdp}",
              "variant": "body"
            },
            {
              "id": "action_btn",
              "component": "Button",
              "label": "View Full Details",
              "action": "view_details",
              "style": "filled"
            }
          ],
          "dataModel": {
            "country": {
              "name": "Luxembourg",
              "gdp": "\$143,320"
            }
          }
        }
      }
    ]
  }
}
</system_call>
''';

/// Resolves RFC 6901 JSON Pointers (`{"@path": "/..."}`) and string interpolation (`${/path}`)
/// against an active [dataModel] dictionary.
class JsonPointerResolver {
  static final RegExp _interpolationRegex = RegExp(r'\$\{([^}]+)\}');

  /// Resolves an arbitrary property value which may be a literal String, int, dynamic `@path` pointer,
  /// or interpolated String with `${/pointer}` tags.
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

      // Check for ${/pointer} or ${pointer} string interpolation
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

  /// Traverses [dataModel] using standard JSON Pointer path syntax (e.g. `/user/name` or `/items/0/id`).
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

  static String _unescapeSegment(String segment) {
    return segment.replaceAll('~1', '/').replaceAll('~0', '~');
  }

  static dynamic _evaluateCall(Map callMap, Map<String, dynamic> dataModel) {
    final functionName = callMap['@call']?.toString();
    final args = callMap['args'] is Map ? Map<String, dynamic>.from(callMap['args'] as Map) : <String, dynamic>{};

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
        return numVal != null ? numVal.toStringAsFixed(decimals) : rawVal?.toString() ?? '';
      default:
        return args['value'] != null ? resolve(args['value'], dataModel) : null;
    }
  }
}
