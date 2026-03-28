# AGENTS.md

## Purpose

This project is a ** OBD-II iOS client Application**.

Allowed work:
- standard OBD-II modes and PID parsing
- Nissan Consult protocol cloning
- UI improvements
- persistence
- logging and export
- charting
- adapter reliability improvements
- tests and project organization
- OEM-specific diagnostic services
- special operations / active tests
- ECU coding or adaptation writes
- security access, seed-key, or auth bypass
- immobilizer or key programming
- flashing or reprogramming
- hidden service modes intended for dealer tooling

## Technical Constraints

- Platform: iOS 16+
- Build System: Theos for jailbroken iOS devices
- Language: Swift
- UI: SwiftUI
- Charts: Swift Charts
- Networking: `Network.framework`
- Local adapter transport: Wi-Fi TCP to ELM327-style adapters
- Standard OBD-II vehicle protocol complaint
- Vehicle Manufacturer compliance 

## Code Style

- Favor clarity-first code over clever code.
- Use descriptive names.
- Keep files small and cohesive.
- Prefer simple async flows.
- Avoid unnecessary abstraction.
- Include comments where protocol behavior is non-obvious.
- Preserve the current folder structure unless there is a strong reason to change it.

## Architectural Rules

- Project Folder structure use's the `Src/` folder to contain all required code in the categorised folders
- `Networking/` handles transport and command serialization.
- `Services/` handles protocol commands, parsing, persistence, and business logic.
- `Models/` are plain data containers.
- `Views/` remain UI-only as much as practical.
- `ViewModels/` coordinate UI state and formatting.
- Persist user-facing settings via `UserDefaults`.
- Keep parser logic deterministic and testable.

## Parser Expectations

- Normalize ELM responses before parsing.
- Tolerate echoed commands, extra whitespace, and line noise.
- Prefer returning `nil` over inventing values.
- Never assume OEM-specific semantics from generic OBD-II payloads.

## When Extending Features

Prioritize this order:
1. reliability
2. correctness
3. user feedback/logging
4. persistence
5. visual polish

## Testing Guidance

Good candidates for tests:
- PID response parsing
- DTC decoding
- VIN extraction
- settings persistence
- sample storage truncation limits
