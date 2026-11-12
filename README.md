# Harness

**The agent that runs the tools, not only the chat.**

Harness is a mobile-first agent runtime built in Flutter. It runs autonomous, multi-turn tool loops against local or cloud models, gives the agent a sandboxed workspace and loadable skills, and renders interactive A2UI surfaces directly in the conversation.

It is aimed at developers and AI power users who want an agent that can inspect files, search the web, schedule work, and act on the device — not another chat bubble with no hands.

**[Application](https://github.com/ahmadkhidir/harness)** · **[Specification](https://github.com/ahmadkhidir/harness-docs)**

---

## Why Harness

Mobile AI today is mostly a text box. Desktop harnesses can run tools, but they are tied to a laptop. Harness closes that gap on Android and iOS:

- **Real tool loops.** The model emits `<system_call>` blocks; the engine routes them, runs independent calls in parallel, and returns observations until the turn is done.
- **Bring your own model.** Switch between Gemini, Claude, OpenAI, any OpenAI-compatible endpoint, or an on-device LiteRT model at runtime.
- **Device-local context.** The agent reads and writes inside a sandboxed workspace, searches it with `grep` and `glob`, and loads skills on demand from local storage.
- **No reasoning leak.** Internal scratchpad text never reaches the chat. Only explicit `send_ui_message` deliveries are mounted in the UI.
- **More than text.** A2UI messages render as native Flutter widgets: cards, lists, forms, pickers, media, and stateful controls that post actions back to the model.

---

## Quick Start

### Prerequisites

- Flutter **3.47.x** stable / Dart **3.13.x**
- [FVM](https://fvm.app/) (recommended; the project is pinned through it)
- Android Studio with an Android SDK/emulator, or Xcode with an iOS simulator
- A provider API key, or a model downloaded for on-device inference

### Run it

```bash
git clone --recurse-submodules <repository-url>
cd harness/prototype

cp .env.example .env            # Windows: Copy-Item .env.example .env
fvm flutter pub get
fvm flutter run --dart-define-from-file=.env
```

`HF_TOKEN` in `.env` is only needed to download gated Hugging Face models for on-device inference. Cloud providers are configured inside the app.

On first launch:

1. Open **Settings** from the home overflow menu.
2. Pick a provider, enter an API key, and choose a model.
3. Review the storage root and any mounted workspaces.
4. Return to chat and give the agent a task.

---

## What You Get

### Core loop and providers

- Multi-turn execution with parallel command dispatch and cancellation.
- `ModelProvider` adapters for Gemini, Claude, OpenAI, OpenAI-compatible APIs, and on-device LiteRT models.
- Per-provider model, endpoint, temperature, and output-token settings.
- API keys stored in the platform keystore via `flutter_secure_storage`.

### Skills

- Skills are folders with a `SKILL.md` plus optional references and assets.
- `load_skill` and `load_skill_file` load guidance transiently, so context is spent only when a task needs it.
- A built-in `a2ui-basic` skill teaches the model the A2UI component set and message format.

### Sandboxed workspace

- One virtual mount table: `primary/` maps to `<HarnessRoot>/storage/`, and users can mount external folders under their own tags.
- Commands: `read_file`, `write_file`, `grep`, `glob`, `list_directory`.
- Paths are canonicalized and jailed; traversal attempts come back to the agent as security errors.
- Physical host paths are never exposed to the model.

### Sessions and memory

- Each session lives in `<HarnessRoot>/sessions/<session_id>/`.
- `turns.json` is the UI/audit source of truth.
- `context.txt` is a line-oriented transcript (`USER:`, `AGENT:`, `SUMMARY:`) that can be compacted to a bounded budget.
- Session switching, renaming, deletion, and compaction indicators in the Sessions screen.

### A2UI surfaces

- Standard A2UI `basic/v1` messages render as native widgets.
- A surface is anchored to the turn that created it and updates in place; later messages mutate the same surface instead of adding chat noise.
- Components include text, cards, rows/columns, lists, tabs, modals, buttons, text fields, checkboxes, choice pickers, sliders, date/time inputs, images, audio, and video.

### Platform actions

- `set_alarm`, `schedule_notification`, `open_url`, `copy_to_clipboard`.
- A2UI user actions are routed back to the model as the next user request.

### External bridges

- `web_search` and `web_fetch` with DuckDuckGo, Tavily, or Brave.
- `execute_script` through an external runner. Scripts never execute inside the mobile app process.
- `download_media` for network media ingestion.
- `http_request` gated by a user-managed host allowlist.

### Timers

- `schedule_timer`, `cancel_timer`, `list_timers`.
- Scheduled prompts run as agent turns and can notify the user; the timer strip keeps pending work visible above the composer.

---

## How It Works

```text
┌─────────────────────────────────────────────────────────────┐
│ Flutter UI (flutter_bloc)                                   │
│ Chat · Sessions · Settings · Workspace                      │
└───────────────────────────┬─────────────────────────────────┘
                            │ events / state
┌───────────────────────────▼─────────────────────────────────┐
│ Harness Engine                                              │
│ context assembly → provider → <system_call> parse → route   │
└───────┬───────────────────────────────────────────┬─────────┘
        │ local modules                             │ bridges
┌───────▼──────────────┐                  ┌─────────▼─────────┐
│ Skills · Storage     │                  │ Web · Runner      │
│ Session · A2UI       │                  │ Transfer          │
│ Platform · Timers    │                  │                   │
└───────┬──────────────┘                  └─────────┬─────────┘
        │                                           │
┌───────▼───────────────────────────────────────────▼─────────┐
│ Persistence                                                 │
│ SQLite · secure keystore · <HarnessRoot> on disk            │
└─────────────────────────────────────────────────────────────┘
```

The model never calls Dart functions directly. It emits structured calls:

```xml
<system_call>
  <command>read_file</command>
  <parameters>{"path": "primary/notes.md"}</parameters>
</system_call>
```

The engine validates, routes, runs independent calls concurrently, and feeds observations back into the next model turn. Visible output is a separate, explicit `send_ui_message` delivery containing Markdown or A2UI — which is what keeps intermediate reasoning out of the UI.

### On-device filesystem

```text
<HarnessRoot>/
  data/models/          downloaded on-device model weights
  storage/              primary/ sandbox and user files
  skills/               SKILL.md packages, including a2ui-basic
  sessions/<id>/
    turns.json          UI and audit log
    context.txt         line-oriented model transcript
```

The default root is chosen by the user or supplied by the platform (`~/Harness` on desktop, the app documents area on iOS, a user-selected folder on Android).

---

## Repository Layout

```text
.
├── docs/                       product specification (git submodule, read-only for code work)
│   └── Harness/                overview, architecture, features, schema, screens, NFRs, branding
└── prototype/                  Flutter application
    ├── lib/
    │   ├── core/               engine, protocol parsing, models, routes, filesystem
    │   ├── data/               SQLite, secure storage, sessions, skills, timers
    │   ├── modules/            skills, storage, platform actions, A2UI, web, runner, transfer, timers
    │   ├── presentation/       blocs, screens, widgets, theme
    │   ├── providers/          model provider adapters
    │   └── main.dart
    ├── assets/
    │   ├── branding/           generated marks, lockups, app icon masters
    │   ├── fonts/              Geist Sans / Geist Mono (SIL OFL)
    │   └── builtin_skills/     seeded a2ui-basic package
    ├── test/                   unit, widget, and acceptance tests by feature
    └── tool/                   branding asset generation
```

---

## Configuration

Settings are stored in SQLite and the platform keystore. The main areas are:

| Area | What it controls |
|---|---|
| **Provider** | Active model provider, API key, model name, custom endpoint, temperature, max output tokens |
| **On-device** | LiteRT model download, selection, partial-download resume, deletion |
| **Filesystem** | Harness root directory, mounted workspaces and their virtual tags |
| **Web search** | DuckDuckGo (no key), Tavily, or Brave, with provider keys |
| **External runner** | Base URL for remote script execution |
| **Allowed hosts** | Hosts approved for `http_request` |

The `HF_TOKEN` used for model downloads is supplied at build/run time:

```bash
fvm flutter run --dart-define-from-file=.env
# or
fvm flutter run --dart-define=HF_TOKEN=hf_...
```

---

## Development

```bash
cd prototype

fvm flutter analyze
fvm flutter test --dart-define-from-file=.env
fvm flutter build apk --debug
fvm flutter build apk --release
fvm flutter build ios --release
```

The test suite reads `.env`; without it, the Hugging Face token test fails by design. At the time of writing, the full suite is 368 tests.

Android and iOS are the supported targets. Desktop and web builds are useful for UI preview and fast iteration, but SQLite-backed session persistence is not wired for web, so the Sessions screen reports an unsupported operation there.

### Rebuilding brand assets

The mark, lockups, and every platform icon are generated from one deterministic script:

```bash
cd prototype
pwsh -File tool/generate_branding_assets.ps1
```

The generated files are committed so a normal build does not require PowerShell.

---

## Design

The interface follows [`docs/Harness/branding.md`](https://github.com/ahmadkhidir/harness-docs/blob/main/Harness/branding.md):

- **Signal Teal** for work the harness is performing, **Graphite** for everything structural.
- **Geist Sans** for interface text and **Geist Mono** for commands, observations, and paths.
- The **reed mark**: a closed frame holding parallel threads, with one thread raised as the active line.
- **Lucide** iconography on a 24px grid.
- Dark and light palettes with the same semantic roles; the app follows the system appearance.
- Empty states use the mark rather than mascots or decorative gradients.

The Flutter implementation lives in `prototype/lib/presentation/theme/`:

- `harness_colors.dart` — semantic color ramps and light/dark palettes
- `harness_tokens.dart` — spacing, sizing, radius, motion, shadows, type scale
- `app_theme.dart` — Material component theme
- `brand_mark.dart` — image-backed mark, wordmark, and lockup widgets
- `harness_icons.dart` — intent-based Lucide icon aliases

---

## Documentation

The specification is the source of truth and lives under `docs/Harness/`:

| Document | Contents |
|---|---|
| [Overview](https://github.com/ahmadkhidir/harness-docs/blob/main/Harness/overview.md) | Product definition, scope, assumptions, KPIs |
| [Architecture](https://github.com/ahmadkhidir/harness-docs/blob/main/Harness/architecture.md) | Components, data flow, storage layout, security model |
| [Features](https://github.com/ahmadkhidir/harness-docs/blob/main/Harness/features.md) | Capability inventory and priorities |
| [Schema](https://github.com/ahmadkhidir/harness-docs/blob/main/Harness/schema.md) | Entities, JSON schemas, `context.txt` protocol |
| [NFRs](https://github.com/ahmadkhidir/harness-docs/blob/main/Harness/nfr.md) | Performance, reliability, security, accessibility targets |
| [Screens](https://github.com/ahmadkhidir/harness-docs/blob/main/Harness/screens.md) | Screen inventory and navigation |
| [Branding](https://github.com/ahmadkhidir/harness-docs/blob/main/Harness/branding.md) | Identity, palette, typography, components |

---

## Status and Limits

Harness is a prototype, not a shipped product. Current constraints:

- Android and iOS are the real targets; web and desktop are development conveniences.
- `execute_script` requires a separately deployed runner service.
- On-device models are bounded by phone RAM, thermals, and download size.
- Mobile background limits can pause long turns when the app is not in the foreground.
- A2UI is opt-in and only renders when the model or a skill explicitly delivers it.
- There is no remote skill store or cross-device session sync yet.

---

## Contributing

- Read the relevant specification before changing behavior.
- Work feature by feature; do not scaffold future features speculatively.
- Keep the layered boundaries: `core/`, `data/`, `modules/`, `providers/`, `presentation/`.
- Run `fvm flutter analyze` and the test suite before opening a change.
- Commit with conventional messages, for example `feat(engine): ...` or `fix(storage): ...`.
