# Tabs

```json
{
  "id": "details_tabs",
  "component": "Tabs",
  "tabs": [
    { "label": "Overview", "child": "tab_overview" },
    { "label": "History", "child": "tab_history" }
  ]
}
```

| Property | Type | Notes |
|---|---|---|
| `tabs` | list | Each entry has `label` and `child` component ID |

Every tab child must exist before the Tabs component is rendered. If a tab child is missing, the whole Tabs component is omitted until it arrives.
