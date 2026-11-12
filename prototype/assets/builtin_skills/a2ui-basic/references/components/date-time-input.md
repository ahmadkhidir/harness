# DateTimeInput

```json
{
  "id": "start_date",
  "component": "DateTimeInput",
  "label": "Start date",
  "variant": "date",
  "value": { "@path": "/form/startDate" }
}
```

| Property | Type | Notes |
|---|---|---|
| `label` | string | Field label |
| `variant` | string | `date`, `time`, `datetime` |
| `value` | binding | ISO date/time string. Must be a JSON Pointer binding. |
| `onChange` | string | Action ID sent after a date is picked |

Use DateTimeInput when the user must choose a date or time.
