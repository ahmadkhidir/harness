---
name: a2ui-basic
description: Build interactive UI as A2UI surfaces — cards, forms, dashboards, buttons, and lists — instead of plain text. Use when the user asks to show, render, or build UI, even if they never say A2UI. Not for text-only answers.
metadata:
  lock: true
---

# A2UI Basic

## Delivery shape

A2UI travels inside the normal `<system_call>` envelope. Emit one complete block per delivery:

```text
<system_call>{"command": "send_ui_message", "parameters": {"message": {"a2ui": [ ...messages... ]}}}</system_call>
```

Read it outermost first:

1. `<system_call>` and `</system_call>`. Without them the output is chat text and the user sees raw JSON instead of a surface.
2. `"command": "send_ui_message"`.
3. `"parameters": {"message": ...}`. `message` is the only parameter.
4. `{"a2ui": [ ... ]}`, the ordered A2UI v1 messages described in `references/messages.md`.

A reply with text and no surface uses the same envelope with a string message:

```text
<system_call>{"command": "send_ui_message", "parameters": {"message": "<your markdown reply>"}}</system_call>
```

Every delivery is pure A2UI: no companion `text` field, no prose outside the surface, and every visible word inside a `Text` component.

## Workflow

1. Read `references/components/index.md` and pick the components the surface needs. Read only the component files you use.
2. Read `references/messages.md` before your first surface. It carries the message fields and the data binding syntax.
3. Create the surface once with `createSurface`, including its initial `components` and `dataModel`.
4. Change it later with `updateComponents` (upsert by component ID) and `updateDataModel` (RFC 6901 path).
5. If a delivery returns a validation error, fix the named components and re-emit the whole delivery. Do not fall back to plain text.
6. Remove the surface with `deleteSurface` when it is no longer needed.

## Minimal surface

```text
<system_call>
{"command": "send_ui_message", "parameters": {"message": {"a2ui": [
  {"version": "1.0", "createSurface": {
    "surfaceId": "summary",
    "catalogId": "basic/v1",
    "components": [
      {"id": "root", "component": "Column", "children": ["title", "body", "ok"]},
      {"id": "title", "component": "Text", "text": "Deploy complete", "variant": "title"},
      {"id": "body", "component": "Text", "text": "Version ${/version} is live."},
      {"id": "ok", "component": "Button", "label": "View logs", "action": "view_logs"}
    ],
    "dataModel": {"version": "2.4.0"}
  }}
]}}}
</system_call>
```

Longer payloads: `references/examples/card.md`, `references/examples/form.md`, `references/examples/list.md`.

## References

| File | Read it when |
|---|---|
| `references/messages.md` | Before your first surface; message fields, data paths, ordering. |
| `references/components/index.md` | When choosing components for a surface. |
| `references/components/<name>.md` | Before using that component; exact properties. |
| `references/examples/card.md` | For a card or status layout. |
| `references/examples/form.md` | For a stateful form with inputs. |
| `references/examples/list.md` | For a list bound to array data. |

## Gotchas

- The root component must be `"id": "root"`. A surface without it does not render.
- Component properties are validated. An unrecognized or misspelled property fails the whole delivery, so copy field names from the component reference instead of inventing them.
- A delivery batch is atomic: if one message fails validation, nothing renders. Read the error, fix the named component, and re-emit.
- Stateful inputs (`CheckBox`, `ChoicePicker`, `Slider`, `DateTimeInput`, `TextField`) must bind `value` to a JSON Pointer path such as `{"@path": "/form/name"}`. A literal `value` is rejected.
- The first turn that creates a `surfaceId` anchors the surface in the chat. Later updates mutate that surface in place and add no chat item, so create once and update forever.
- An action string is a plain ID with no `platform:` prefix. The tap reaches the model as a user event, and the model can then call a platform command if needed.
- Values typed into inputs live in the data model in memory. They survive a session reload only when you persist them with `updateDataModel`.
