# Text

```json
{
  "id": "title",
  "component": "Text",
  "text": "Hello ${/user/name}",
  "variant": "title",
  "fontWeight": "bold",
  "color": "primary"
}
```

| Property | Type | Notes |
|---|---|---|
| `text` | string or binding | Literal, `{"@path": "/path"}`, or `${/path}` interpolation |
| `variant` | string | `headline`, `title`, `body`, `caption`, `label` |
| `fontWeight` | string | `normal`, `medium`, `bold` |
| `color` | string | `primary`, `secondary`, `error`, `success`, `warning`, or hex |

Use Text for all readable copy. Do not use it as a container.
