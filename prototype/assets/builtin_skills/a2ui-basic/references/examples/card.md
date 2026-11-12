# Example: Status Card

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
            "surfaceId": "status_card",
            "catalogId": "basic/v1",
            "components": [
              { "id": "root", "component": "Card", "child": "body" },
              { "id": "body", "component": "Column", "children": ["header", "divider", "detail", "action"] },
              { "id": "header", "component": "Row", "children": ["icon", "title"], "alignment": "center" },
              { "id": "icon", "component": "Icon", "icon": "check_circle", "color": "success" },
              { "id": "title", "component": "Text", "text": "Deployment complete", "variant": "title" },
              { "id": "divider", "component": "Divider" },
              { "id": "detail", "component": "Text", "text": "Version ${/version} is live." },
              { "id": "action", "component": "Button", "label": "View logs", "action": "view_logs" }
            ],
            "dataModel": { "version": "2.4.0" }
          }
        }
      ]
    }
  }
}
</system_call>
```
