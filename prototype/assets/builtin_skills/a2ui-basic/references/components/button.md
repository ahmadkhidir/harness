# Button

```json
{
  "id": "view_details",
  "component": "Button",
  "label": "View details",
  "action": "view_details",
  "style": "filled",
  "icon": "open_in_new",
  "disabled": false
}
```

| Property | Type | Notes |
|---|---|---|
| `label` | string or binding | Button text |
| `action` | string | Action ID sent when tapped |
| `style` | string | `filled`, `outlined`, `text` |
| `icon` | string | Optional icon name |
| `disabled` | boolean | Default `false` |

Use a clear verb for the label. The `action` is what the app routes when the user taps.
