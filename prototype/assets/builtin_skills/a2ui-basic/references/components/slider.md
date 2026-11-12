# Slider

```json
{
  "id": "budget_slider",
  "component": "Slider",
  "label": "Monthly budget",
  "value": { "@path": "/form/budget" },
  "min": 0,
  "max": 5000,
  "step": 100
}
```

| Property | Type | Notes |
|---|---|---|
| `label` | string | Slider label |
| `value` | binding | Current value. Must be a JSON Pointer binding. |
| `min` | number | Default `0` |
| `max` | number | Default `100` |
| `step` | number | Default `1` |
| `onChange` | string | Action ID sent when the drag ends |

Use Slider for approximate numeric choices, not for precise data entry.
