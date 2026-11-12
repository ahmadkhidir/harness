# CheckBox

```json
{
  "id": "agree_check",
  "component": "CheckBox",
  "label": "I agree to the terms",
  "value": { "@path": "/form/agreed" },
  "onChange": "agreement_changed"
}
```

| Property | Type | Notes |
|---|---|---|
| `label` | string | Checkbox label |
| `value` | binding | Checked state. Must be a JSON Pointer binding. |
| `onChange` | string | Action ID |

Use CheckBox for independent boolean choices, not for selecting one option from a group.
