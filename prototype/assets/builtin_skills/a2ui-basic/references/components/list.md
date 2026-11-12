# List

Static children:

```json
{
  "id": "results",
  "component": "List",
  "children": ["item_1", "item_2"],
  "direction": "vertical"
}
```

Dynamic template:

```json
{
  "id": "results",
  "component": "List",
  "children": {
    "path": "/items",
    "componentId": "result_item"
  }
}
```

| Property | Type | Notes |
|---|---|---|
| `children` | list or template | Static IDs or `{path, componentId}` |
| `direction` | string | `vertical` or `horizontal` |

For dynamic lists, provide an array in the data model and a template component that renders one item. Use a scoped data model with relative paths inside the template.
