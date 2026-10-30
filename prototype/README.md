# Harness Prototype

A mobile agentic harness built in Flutter that runs autonomous multi-turn tool loops with interchangeable local and cloud LLMs, on-demand skill loading, local storage inspection, and declarative A2UI interactions.

## Specifications

Complete product specifications and architectural designs are located in `../docs/Harness`:

- [Overview](../docs/Harness/overview.md)
- [Architecture](../docs/Harness/architecture.md)
- [Features](../docs/Harness/features.md)
- [Schema & Protocols](../docs/Harness/schema.md)

## Requirements

- **Flutter SDK:** 3.47.x (Channel `stable`)
- **Dart SDK:** 3.13.x
- **FVM (Flutter Version Management):** Configured via `.fvmrc` (`fvm use stable`)

## Getting Started

1. Fetch dependencies:
   ```bash
   fvm flutter pub get
   ```

2. Run tests:
   ```bash
   fvm flutter test
   ```

3. Launch application:
   ```bash
   fvm flutter run
   ```
