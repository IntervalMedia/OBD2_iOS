# Validation and remaining checks

2026-10-19: shared communication core and TCP adapter tests pass. Tests cover the petrol/diesel DTC request matrix, entering `10C0` before read/clear, positive/negative clear replies, exactly one clear transmission, numeric conversion, invalid/mismatched replies, supported DID bitmaps, logging cancellation and draining, and loopback TCP framing/deadlines. The loopback ELM emulator exercises initialization → identity → DTC read → clear → logging. It binds to `127.0.0.1`; no vehicle is contacted.

macOS and generic iOS Simulator builds pass with signing disabled. The installed CoreSimulator service reports an Xcode version mismatch, so compiling the simulator target does not establish a successful simulator launch. Native UI automation was unavailable in this session. Hardware and UI end-to-end validation remain outstanding.

LLVM coverage excluding test/generated files: communication core approximately 96% of lines; core plus TCP approximately 95% of lines and 80% of regions before the final multiline-data regression. These percentages do not include the SwiftUI dashboard.

Run from this workspace:

```sh
swift test --package-path NissanDiagnostics --scratch-path /tmp/nissan-swift-build --enable-code-coverage
xcodebuild -project NissanDiagnostics/NissanDiagnostics.xcodeproj -scheme NissanDiagnostics -destination 'platform=macOS' -derivedDataPath /tmp/NissanDiagnosticsBuild CODE_SIGNING_ALLOWED=NO build
xcodebuild -project NissanDiagnostics/NissanDiagnostics.xcodeproj -scheme NissanDiagnostics -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/NissanDiagnosticsIOSBuild CODE_SIGNING_ALLOWED=NO build
```

Open `NissanDiagnostics.xcodeproj` in Xcode, choose the macOS/iOS destination, and set your signing team for installation on a physical iPhone. Demo mode starts enabled. For live monitoring, join the Wi-Fi adapter network, disable demo, and enter its actual host/port. The dashboard defaults to the recovered petrol profile for the requested Skyline. DTC clearing is exposed explicitly in the shared client API; it is never performed automatically by the dashboard.

On the actual Skyline, first capture initialization and read-only identity/DTC/register transcripts, confirm engine/ECM profile and compare decoded values against a trusted scanner. Clearing needs a deliberate user action and a post-clear read to establish the resulting stored codes. A lost clear reply is an unknown outcome and must not cause a blind automatic retry.

The analysis questions are answered statically for read/clear request selection, session setup, response formats, and numeric logging loop. Complete parameter/switch catalog parity, vehicle compatibility, session recovery/keep-alives and non-Wi-Fi transport remain partial or unresolved; see COMMUNICATION.md.
