# prototype — implementation guidelines

This file is authoritative for all prototype development in `prototype/`. Any agent assigned to an implementation, debugging, refactoring, or testing task in this folder follows these rules.

Specification documents under `docs/Harness/` are strictly **read-only** for prototype tasks. When a specification gap or contradiction is discovered, report it to the user; never alter files in `docs/` during code tasks.

---

## 1. Grounding & Specification References

All prototype code must strictly conform to the specifications and contracts defined in `docs/Harness/`:

| Document | Authority & Scope |
|---|---|
| [`docs/Harness/overview.md`](../docs/Harness/overview.md) | High-level product definition, problem/solution boundaries, KPIs, and non-goals. |
| [`docs/Harness/architecture.md`](../docs/Harness/architecture.md) | Component topology, data architecture, execution flow diagrams, and sandbox security models. |
| [`docs/Harness/features.md`](../docs/Harness/features.md) | Feature inventory (`FEAT-001` through `FEAT-008`), priority matrix, and dependencies. |
| [`docs/Harness/schema.md`](../docs/Harness/schema.md) | JSON Schema 2020-12 data entities, `<system_call>` payloads, and the `context.txt` line protocol. |
| [`docs/Harness/features/FEAT-###.md`](../docs/Harness/features/) | Detailed user stories, model input/output behaviors, and acceptance criteria per feature. |

---

## 2. Core Architectural Principles

1. **Feature-by-Feature Incremental Cadence:**
   - Implement features strictly on-demand as requested by the user.
   - Do not jump ahead or scaffold unrequested future features.
2. **Layered Architecture & Separation of Concerns:**
   - `core/models/`: Pure domain entities and protocol parsers with schema validations and serialization.
   - `core/engine/`: Autonomous turn execution loop, context assembly, and command routing.
   - `modules/`: Modular on-device and external system capabilities (`skills`, `storage`, `session`, `platform_actions`, `a2ui`, `runner`, `web`).
   - `providers/`: Pluggable inference adapters implementing the `ModelProvider` abstraction (`gemini`, `claude`, `openai`, `openai_compatible`, `local_device`).
   - `data/`: Local SQLite persistence (`harness_app.db`) and encrypted keystore (`flutter_secure_storage`).
   - `presentation/`: Reactive state management via `flutter_bloc` (`HarnessSessionBloc`) driving Flutter UI screens and widgets.
3. **Zero Thinking Leakage:**
   - Any intermediate scratchpad text or reasoning monologue emitted while `<system_call>` blocks are processed is internal.
   - Suppress scratchpad text from user-facing chat bubbles. The UI mounts content exclusively from explicit delivery commands: `send_message` (for Markdown text) and `send_a2ui` (for declarative widgets).
4. **Sandboxed Filesystem Security:**
   - File manipulation commands (`grep`, `glob`, `read_file`, `write_file`, `list_directory`) are strictly jailed within `<AppDocuments>/Harness/storage/`.
   - All paths must be canonicalized before access. Any path traversal attempt (`../`) outside the sandbox throws an access-denied `SecurityException` returned as an error observation.
   - Code execution is prohibited from running directly in the mobile app process; script execution must be offloaded to `RunnerProvider`.
5. **Dual-File Session Persistence & Line Protocol:**
   - Every completed turn performs a synchronous dual-write:
     - `turns.json`: Structured, immutable audit log driving the Flutter chat UI.
     - `context.txt`: Line-oriented plaintext transcript (`USER: `, `AGENT: `, `SUMMARY: `) designed for fast `grep` retrieval and background summarization compaction.
   - Guarantee single discrete lines per dialogue turn by sanitizing newlines (`\n` and `\r\n` $\rightarrow$ literal `\n`).

---

## 3. Inline Documentation Standards

- **Docstrings (`///`):** Every public class, enum, method, constructor, and property must have a comprehensive Dart docstring describing its responsibility, parameters, return values, and schema reference.
- **Comments on Non-Obvious Logic:**
  - Clearly annotate non-obvious logic (e.g. URI schema validation, regex patterns, regex newline escapes, JSON pointer `@path` resolution, atomic file rewriting via `.tmp` files).
  - Explain *why* a particular approach was chosen when it addresses a platform, security, or performance constraint.

---

## 4. Environment & Toolchain

- **Flutter SDK:** Pin to Flutter 3.47.x (Channel `stable`) / Dart 3.13.x.
- **FVM:** All CLI operations must use the Flutter Version Management wrapper:
  ```bash
  # Check versions
  fvm flutter --version
  
  # Run static analysis
  fvm flutter analyze
  
  # Execute test suite
  fvm flutter test
  ```

---

## 5. Definition of Done for Feature Work

Before declaring any feature complete:
1. **Tests:** Implement unit and/or widget tests under `test/` verifying happy paths, edge cases, and failure modes described in the feature's acceptance criteria.
2. **Analysis:** Run `fvm flutter analyze` and confirm zero errors or linter warnings.
3. **Execution:** Run `fvm flutter test` and ensure all tests pass cleanly.
4. **Git:** Commit completed feature increments separately with conventional commit messages (e.g. `feat(schema): ...`, `feat(engine): ...`).

