# A2UI v1 Messages

All A2UI messages are JSON objects. They are sent inside the `a2ui` array of a `send_ui_message` delivery, wrapped in `<system_call>` tags:

```text
<system_call>{"command": "send_ui_message", "parameters": {"message": {"a2ui": [ ...messages... ]}}}</system_call>
```

Keep the `<system_call>` wrapper and the `command` and `parameters` envelope. A bare `{"a2ui": [ ... ]}` object, or a `message` object without `command` and `parameters`, is not a delivery; it is shown to the user as chat text.

An A2UI delivery is pure A2UI: do not include a companion `text` field and do not write explanation text outside the surface. Every user-visible word belongs in a `Text` component. Use the plain string form of `message` only for a text-only reply.

Stateful inputs (`CheckBox`, `ChoicePicker`, `Slider`, `DateTimeInput`, `TextField`) must bind `value` to a JSON Pointer path. The renderer updates that path immediately when the user interacts and sends the current data model with the action. A literal `value` is rejected during validation.

## createSurface

Creates a new surface. The `surfaceId` must be unique for the lifetime of the conversation.

```json
{
  "version": "1.0",
  "createSurface": {
    "surfaceId": "main",
    "catalogId": "basic/v1",
    "components": [ ...optional initial components... ],
    "dataModel": { ...optional initial data... }
  }
}
```

Do not call `createSurface` again for an existing surface. Use `updateComponents` to change it. The turn that creates a surface anchors it in the chat; later updates for the same `surfaceId` mutate that anchored surface in place and add no new chat item.

## updateComponents

Adds or updates components inside an existing surface. Sending a component with an existing `id` updates it in place.

```json
{
  "version": "1.0",
  "updateComponents": {
    "surfaceId": "main",
    "components": [
      { "id": "title", "component": "Text", "text": "Updated title" }
    ]
  }
}
```

Components may be sent incrementally. A component may reference a child that has not arrived yet; the renderer omits the unresolved node until the child appears.

## updateDataModel

Updates the surface data model at a JSON Pointer path. If `path` is omitted, the root is replaced. A `null` value removes the key at the path.

```json
{
  "version": "1.0",
  "updateDataModel": {
    "surfaceId": "main",
    "path": "/status",
    "value": "done"
  }
}
```

Components bind to data with `{"@path": "/status"}` or `"${/status}"`.

## deleteSurface

Removes a surface and all of its components and data.

```json
{
  "version": "1.0",
  "deleteSurface": {
    "surfaceId": "main"
  }
}
```

## Ordering

Messages are applied in order. A surface must be created before it can be updated or deleted. Updates to the same surface are incremental; do not resend the full tree unless you are intentionally replacing components.
