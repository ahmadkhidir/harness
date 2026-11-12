# ChoicePicker

```json
{
  "id": "role_choice",
  "component": "ChoicePicker",
  "label": "Choose a role",
  "options": [
    { "label": "Backend", "value": "backend" },
    { "label": "Frontend", "value": "frontend" }
  ],
  "value": { "@path": "/form/role" },
  "onChange": "role_changed"
}
```

| Property | Type | Notes |
|---|---|---|
| `label` | string | Picker label |
| `options` | list | Each entry has `label` and `value` |
| `value` | binding | Selected value. Must be a JSON Pointer binding. |
| `onChange` | string | Action ID |

Use ChoicePicker when the user must select exactly one option from a short list.
