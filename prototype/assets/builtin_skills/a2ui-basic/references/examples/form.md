# Example: Simple Form

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
            "surfaceId": "profile_form",
            "catalogId": "basic/v1",
            "components": [
              { "id": "root", "component": "Card", "child": "body" },
              { "id": "body", "component": "Column", "children": ["title", "name", "role", "agree", "submit"] },
              { "id": "title", "component": "Text", "text": "Your profile", "variant": "title" },
              { "id": "name", "component": "TextField", "label": "Full name", "value": { "@path": "/form/name" }, "onChange": "name_changed" },
              { "id": "role", "component": "ChoicePicker", "label": "Role", "options": [ { "label": "Backend", "value": "backend" }, { "label": "Frontend", "value": "frontend" } ], "value": { "@path": "/form/role" }, "onChange": "role_changed" },
              { "id": "agree", "component": "CheckBox", "label": "I agree to the terms", "value": { "@path": "/form/agreed" }, "onChange": "agreement_changed" },
              { "id": "submit", "component": "Button", "label": "Save profile", "action": "save_profile" }
            ],
            "dataModel": {
              "form": { "name": "", "role": "backend", "agreed": false }
            }
          }
        }
      ]
    }
  }
}
</system_call>
```
