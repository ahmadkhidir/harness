/// A2UI `basic/v1` Component Catalog Specification & JSON Pointer Resolver.
///
/// Implements FEAT-006:
/// - Baked into the app binary as compile-time constants for instant $O(1)$ zero-I/O retrieval.
/// - Conforms to the standard Agent-to-User Interface specification (`a2ui-project/a2ui`).
/// - Defines standard components: `Card`, `Column`, `Row`, `Text`, `Icon`, `Button`, `Divider`.
/// - Supports runtime dynamic data bindings using RFC 6901 JSON Pointers (`@path: /path/to/value`).
library;

/// Detailed schema documentation and usage guidelines returned when `load_a2ui_catalog(catalog: "basic/v1")` is invoked.
const String kBasicV1CatalogDocumentation = '''
A2UI Catalog: basic/v1
Specification Version: 1.0

Description:
Declarative UI component catalog for mobile Flutter client rendering. When interactive controls, cards, confirmation dialogues, or structured status displays are needed, emit a `send_a2ui` system call with `createSurface`, `updateComponents`, and optional `updateDataModel`.

Supported Components:
1. Card
   - Properties:
     - child: string (ID of child component, e.g. "col_root")
     - elevation: number (default 1)
     - padding: number (default 12)
2. Column
   - Properties:
     - children: list of strings (IDs of child components, e.g. ["t_title", "div_1", "r_actions"])
     - spacing: number (default 8)
     - crossAxisAlignment: "start" | "center" | "end" | "stretch" (default "start")
     - mainAxisAlignment: "start" | "center" | "end" | "spaceBetween" (default "start")
3. Row
   - Properties:
     - children: list of strings (IDs of child components)
     - spacing: number (default 8)
     - crossAxisAlignment: "start" | "center" | "end" (default "center")
     - mainAxisAlignment: "start" | "center" | "end" | "spaceBetween" (default "start")
4. Text
   - Properties:
     - text: string OR object {"@path": "/pointer"} for dynamic data binding
     - style: "headline" | "title" | "body" | "caption" | "label" (default "body")
     - fontWeight: "bold" | "normal" | "medium" | "w600" (default "normal")
     - color: "primary" | "secondary" | "error" | "success" | "warning" | "onSurface" | hex code "#RRGGBB"
5. Icon
   - Properties:
     - icon: string (e.g. "check", "warning", "info", "star", "flight", "close", "settings", "check_circle", "schedule", "error", "event")
     - size: number (default 24)
     - color: "primary" | "secondary" | "error" | "success" | "warning" | hex code "#RRGGBB"
6. Button
   - Properties:
     - label: string OR object {"@path": "/pointer"}
     - action: string (event action ID sent on tap, e.g. "confirm_booking", "cancel")
     - style: "filled" | "outlined" | "text" (default "filled")
     - icon: string (optional icon name)
7. Divider
   - Properties:
     - thickness: number (default 1)
     - color: string (optional)

Data Model Binding:
Properties supporting dynamic binding resolve values via JSON Pointers against `updateDataModel`:
- Map syntax: {"text": {"@path": "/status"}}
- String syntax: {"text": "@path: /status"}
If data model is {"status": "Active"}, the property dynamically resolves to "Active".

Example `send_a2ui` Dispatch:
```xml
<system_call>
{
  "command": "send_a2ui",
  "parameters": {
    "text": "Here is your flight confirmation card:",
    "messages": [
      {
        "version": "1.0",
        "createSurface": {
          "surfaceId": "flight_card_01",
          "catalogId": "basic/v1"
        }
      },
      {
        "version": "1.0",
        "updateDataModel": {
          "surfaceId": "flight_card_01",
          "value": {
            "flightCode": "LH 402",
            "status": "Confirmed",
            "departure": "10:45 AM"
          }
        }
      },
      {
        "version": "1.0",
        "updateComponents": {
          "surfaceId": "flight_card_01",
          "components": [
            {
              "id": "root",
              "type": "Card",
              "properties": {"child": "col_main", "elevation": 2}
            },
            {
              "id": "col_main",
              "type": "Column",
              "properties": {"children": ["header_row", "div_sep", "time_text", "btn_confirm"]}
            },
            {
              "id": "header_row",
              "type": "Row",
              "properties": {"children": ["flight_icon", "code_text"]}
            },
            {
              "id": "flight_icon",
              "type": "Icon",
              "properties": {"icon": "flight", "color": "primary"}
            },
            {
              "id": "code_text",
              "type": "Text",
              "properties": {"text": {"@path": "/flightCode"}, "style": "title", "fontWeight": "bold"}
            },
            {
              "id": "div_sep",
              "type": "Divider",
              "properties": {"thickness": 1}
            },
            {
              "id": "time_text",
              "type": "Text",
              "properties": {"text": {"@path": "/departure"}, "style": "body"}
            },
            {
              "id": "btn_confirm",
              "type": "Button",
              "properties": {"label": "Check In", "action": "check_in_flight", "style": "filled"}
            }
          ]
        }
      }
    ]
  }
}
</system_call>
```
''';

/// Resolves RFC 6901 JSON Pointers against a given [dataModel] dictionary.
class JsonPointerResolver {
  /// Resolves an arbitrary property value which may be a literal String, int, or dynamic `@path` pointer.
  static dynamic resolve(dynamic value, Map<String, dynamic> dataModel) {
    if (value == null) return null;

    if (value is Map) {
      if (value.containsKey('@path')) {
        final path = value['@path']?.toString() ?? '';
        return resolvePointer(path, dataModel);
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
}
