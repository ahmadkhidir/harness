# Modal

```json
{
  "id": "confirm_modal",
  "component": "Modal",
  "trigger": "open_button",
  "content": "modal_body",
  "title": "Confirm action"
}
```

| Property | Type | Notes |
|---|---|---|
| `trigger` | component ID | Component that opens the modal |
| `content` | component ID | Modal body |
| `title` | string | Optional heading |

Modal is a single-child container for both `trigger` and `content`. It is omitted until both referenced components exist.
