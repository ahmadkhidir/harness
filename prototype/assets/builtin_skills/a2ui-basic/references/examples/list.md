# Example: Dynamic List

```text
<system_call>
{
  "command": "send_ui_message",
  "parameters": {
    "message": {
      "a2ui": [
        {
          "version": "1.0",
          "createSurface": {
            "surfaceId": "results",
            "catalogId": "basic/v1",
            "components": [
              { "id": "root", "component": "Card", "child": "body" },
              { "id": "body", "component": "Column", "children": ["title", "items"] },
              { "id": "title", "component": "Text", "text": "Results", "variant": "title" },
              { "id": "items", "component": "List", "children": { "path": "/results", "componentId": "row" } },
              { "id": "row", "component": "Row", "children": ["name", "score"], "alignment": "spaceBetween" },
              { "id": "name", "component": "Text", "text": { "@path": "/name" } },
              { "id": "score", "component": "Text", "text": { "@path": "/score" } }
            ],
            "dataModel": {
              "results": [
                { "name": "Alpha", "score": "98" },
                { "name": "Beta", "score": "91" }
              ]
            }
          }
        }
      ]
    }
  }
}
</system_call>
```
