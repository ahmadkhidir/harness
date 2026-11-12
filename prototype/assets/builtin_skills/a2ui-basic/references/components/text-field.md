# TextField

```json
{
  "id": "name_field",
  "component": "TextField",
  "label": "Full name",
  "placeholder": "Ahmad Khidir",
  "value": { "@path": "/form/name" },
  "variant": "text",
  "onChange": "name_changed"
}
```

| Property | Type | Notes |
|---|---|---|
| `label` | string | Field label |
| `placeholder` | string | Hint text |
| `value` | binding | Current value. Must be a JSON Pointer binding. |
| `variant` | string | `text`, `number`, `password`, `multiline` |
| `onChange` | string | Action ID sent on submit |

Use labels that describe the expected input. For forms, bind values to the data model.
