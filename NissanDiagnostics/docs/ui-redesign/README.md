# Guided setup redesign

Demo removed from the base app. Connection uses a single Connect & prepare action, with validated adapter initialization and vehicle response before Ready. Nissan has a separate adapter-only connection path because its engine/CVT sessions perform their own setup. No learning or clear operation runs automatically.

The visual direction uses a numbered preparation rail, restrained petrol-teal accents, monospaced instruments, solid scrolling surfaces, and native glass fixed controls on version26, with iOS18/macOS15 fallbacks.

71 tests and both native builds pass. Theos IPA packaging passes. Phone checks cover light/dark, large text, empty screens, navigation and invalid-host recovery. The full rendered evidence gate is **incomplete**: final desktop capture, full accessibility traversal and hardware-dependent loading/success/partial/permission flows remain untested. The evidence checker is expected to reject these truthful untested entries; no passing observations were invented. See evidence.json for details.

Initial desktop inspection succeeded at900x612pt. After rebuilding, native UI tooling failed with `cgWindowNotFound`; its optional launch API was unavailable. No alternative desktop screenshot was fabricated.
