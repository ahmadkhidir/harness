# Card

```json
{
  "id": "root",
  "component": "Card",
  "child": "card_body",
  "elevation": 1,
  "padding": 12
}
```

| Property | Type | Notes |
|---|---|---|
| `child` | component ID | Required single child |
| `elevation` | number | Default `1` |
| `padding` | number | Default `12` |

Card is a single-child container. If its child is not present yet, the card is omitted until the child arrives. The root of a surface is usually a Card whose child is a Column.
