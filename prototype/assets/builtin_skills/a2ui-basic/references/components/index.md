# Basic v1 Components

Load only the component reference you need.

| Component | File | Use |
|---|---|---|
| Text | `text.md` | Headings, body copy, labels |
| Image | `image.md` | Remote or stored images |
| Icon | `icon.md` | Small symbolic glyph |
| Video | `video.md` | Video playback |
| AudioPlayer | `audio-player.md` | Audio playback |
| Row | `row.md` | Horizontal group |
| Column | `column.md` | Vertical group |
| List | `list.md` | Scrollable or dynamic list |
| Card | `card.md` | Elevated container |
| Tabs | `tabs.md` | Tabbed sections |
| Modal | `modal.md` | Dialog content |
| Divider | `divider.md` | Visual separator |
| Button | `button.md` | User action |
| TextField | `text-field.md` | Text input |
| CheckBox | `check-box.md` | Boolean input |
| ChoicePicker | `choice-picker.md` | Select one option |
| Slider | `slider.md` | Numeric range |
| DateTimeInput | `date-time-input.md` | Date/time input |

Every component is a flat object with `id` and `component`. Container children are referenced by ID.

The root component must use `"id": "root"`.
