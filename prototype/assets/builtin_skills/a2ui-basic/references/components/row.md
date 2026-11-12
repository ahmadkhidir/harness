# Row

```json
{
  "id": "header",
  "component": "Row",
  "children": ["icon_status", "title_text"],
  "spacing": 8,
  "alignment": "center"
}
```

| Property | Type | Notes |
|---|---|---|
| `children` | list of component IDs | Horizontal order |
| `spacing` | number | Default `8` |
| `alignment` | string | `start`, `center`, `end`, `spaceBetween` |

Rows are for short horizontal groups. For long content, use Column or List.
