# OBDMVP

A SwiftUI application for iOS 18+ and macOS 15+ for connecting to Wi-Fi or Bluetooth LE ELM327-style OBD-II adapters and performing **OBD-II** operations.

## Scope

Included:
- Wi-Fi TCP and Bluetooth LE connection to ELM-style adapter
- Adapter initialization (AT commands)
- Standard OBD-II PID polling
- Live dashboard
- Live charts with Swift Charts
- Generic stored DTC read
- Generic DTC clear
- VIN read
- CSV export
- Persistent app settings with `UserDefaults`
- Session sample persistence (last captured samples)
- Text logs
- Nissan CONSULT diagnostic sessions over the existing serialized adapter connection
- Nissan petrol/diesel ECU profiles and supported-register discovery
- ECU identification, trouble-code read/clear, and live ECU data with CSV logging
- Real-adapter Nissan sessions with no simulated readings

Future Features:
- OEM-specific special functions
- Security access / seed-key
- Coding / configuration writing
- Immobilizer / key functions
- Flashing / reprogramming
- Actuator tests

The interface has five destinations: Connect, Live, Diagnostics, Nissan, and Tools. Charts, Activity logs, and Settings are available in Tools. Native Liquid Glass action bars are used on iOS 26 and macOS 26, with solid controls on iOS 18–25 and macOS 15. Scrolling content uses solid surfaces for readable diagnostic data.

## Requirements

- iOS 18+ (iPhone/iPad) or macOS 15 Sequoia+
- Xcode with the iOS 26 / macOS 26 SDKs or newer to compile the native Liquid Glass APIs (deployment remains iOS 18+ / macOS 15+)
- Theos and a jailbroken iOS 18+ device for IPA packaging
- A Wi-Fi or Bluetooth LE ELM327-compatible OBD-II adapter

## Native iOS and macOS Builds

Open `OBDMVP.xcodeproj`, select `OBDMVP-iOS` or `OBDMVP-macOS`, and choose your device. Set your development team for signed device builds. The macOS target is a native SwiftUI application with outgoing network and Bluetooth sandbox permissions.

The checked-in Xcode project is generated from `project.yml`. After adding or removing source files, regenerate it with XcodeGen:

```sh
xcodegen generate
xcodebuild -project OBDMVP.xcodeproj -scheme OBDMVP-macOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project OBDMVP.xcodeproj -scheme OBDMVP-iOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

For the existing jailbroken iOS packaging workflow, run `make package` with `THEOS` configured. The Makefile now targets iOS 18. Native Xcode builds use generated platform-specific app metadata; `Resources/Info.plist` remains the Theos iOS packaging metadata.

The Nissan screen also includes EconTool-derived petrol CAN work-support discovery, capability-gated idle-air learning and fuel-trim reset, and a separate read-only CVT information session. Wi-Fi connections explicitly select the Wi-Fi interface and discard callbacks from replaced sockets. See [the EconTool investigation](NissanDiagnostics/docs/ECONTOOL.md) for source evidence, protocol differences, and the unimplemented Consult functions. These additions require vehicle validation; capability discovery alone does not establish the prerequisites for a learning procedure.

The generic OBD dashboard exports CSV through the system share interface. Nissan CSV export uses the system file save dialog. Grant local network and Bluetooth access when prompted.

## Tests and CI

Run the deterministic parser, queue, persistence, CSV, and Nissan protocol tests from the repository root:

```sh
swift test --enable-code-coverage
```

The native validation workflow runs these tests and builds both Xcode targets on macOS 15. This compiles the iOS Simulator application without requiring a simulator runtime. The release workflow builds the Theos IPA using the runner's installed iPhoneOS SDK and checks that it is version 18 or newer.

The current validation passes 49 tests with 83.33% line coverage across the tested core targets. Coverage excludes the app UI and platform transport implementations.

The redesign has been inspected on an iPhone simulator and native macOS. See `NissanDiagnostics/docs/ui-redesign` for the design contract and rendered evidence, including remaining untested hardware-dependent states. Hardware testing remains necessary for adapter connections, ECU responses, Bluetooth permissions, and file export.

## Nissan Diagnostics

The Nissan tab integrates the diagnostic core from `NissanDiagnostics` into the base app. Use Connect & prepare for standard OBD-II, or expand Using Nissan diagnostics? and choose Connect for Nissan. The Nissan screen performs its own engine/CVT initialization. Choose the petrol or diesel ECU profile. Live sessions use CAN 11-bit, 500 kbit/s with request header `7E0`; verify vehicle compatibility before starting. Nissan sessions require a connected adapter; there is no demo mode.

OEM commands require a compatible ECU, protocol, and adapter. Software builds and deterministic tests do not verify ECU compatibility or vehicle behavior; vehicle testing is still required. The bundled source application's example data and incomplete OEM operations do not establish universal Nissan support.

## Project Structure

```text
OBDMVP/
├── control
├── Makefile
├── README.md
└── AGENTS.md

	Resources/
	└── AppIcon**x**.png
	└── Info.plist

	Src/
	├── App/
	├── Models/
	├── Networking/
	├── Services/
	├── Utilities/
	├── ViewModels/
	├── Views/

```

If your Wi-Fi adapter behaves badly on local networking, you may need targeted ATS adjustments. Do not loosen ATS broadly unless you actually need it.

## First Test Flow

1. Join the adapter Wi-Fi network or pair a compatible Bluetooth LE adapter.
2. Open the app.
3. Choose Wi-Fi or Bluetooth LE on the Connection screen.
4. For Wi-Fi, confirm host and port. For Bluetooth LE, scan and select an adapter.
5. Tap **Connect**.
6. Tap **Initialize Adapter**.
7. Tap **Read VIN**.
8. Start live polling.
9. Open Charts from Live, or Tools → Charts.
10. Read DTCs.
11. Export CSV.

## Persistence

The app persists:
- connection settings
- recent live samples
- VIN
- Nissan petrol/diesel profile

Nissan sessions keep the most recent 5,000 timestamped CSV records in memory; export them before ending or restarting a session. Logs are kept in memory only.

## Known Caveats

Cheap ELM clones can be unreliable. Common issues:
- wrong IP or port
- delayed responses causing timeouts
- noisy text responses
- false claims of protocol support
- odd multi-frame behavior

## Next Suggested Improvements

- Complete the Future Features Checklist
- supported PID capability map from `0100`
- multi-frame response parsing
- DTC description lookup
- multiple-chart dashboard
- session management and file import/export
- adapter compatibility profiles
- better error handling and user feedback
- more robust connection management and retries
- support for more OBD protocols and non-ELM adapters
- security access and coding functions
- support for more adapter types (Bluetooth, USB)
- better logging and log export
- Further accessibility and device testing
