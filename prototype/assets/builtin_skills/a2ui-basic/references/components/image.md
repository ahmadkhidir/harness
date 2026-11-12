# Image

```json
{
  "id": "cover",
  "component": "Image",
  "url": "https://example.com/cover.jpg",
  "description": "Cover image",
  "fit": "cover",
  "aspectRatio": 1.5
}
```

| Property | Type | Notes |
|---|---|---|
| `url` | string or binding | HTTPS URL or registered storage path |
| `description` | string | Accessibility text |
| `fit` | string | `cover`, `contain`, `fill`, `none` |
| `aspectRatio` | number | Width divided by height |

If the URL is unresolved, omit the Image rather than showing a broken box.
