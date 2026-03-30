# OBDMVP

A SwiftUI based Application for iOS for connecting to Wi-Fi or Bluetooth LE ELM327-style OBD-II adapters and performing **OBD-II** operations.

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

Future Features:
- Nissan proprietary Consult protocol
- OEM-specific special functions
- Security access / seed-key
- Coding / configuration writing
- Immobilizer / key functions
- Flashing / reprogramming
- Actuator tests

## Requirements

- Theos build system
- Jailbroken iOS 16+ device
- A Wi-Fi or Bluetooth LE ELM327-compatible OBD-II adapter

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
9. Open Charts.
10. Read DTCs.
11. Export CSV.

## Persistence

The app persists:
- connection settings
- recent live samples
- VIN

Logs are kept in-memory only.

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
- unit tests for parsers and persistence
- better error handling and user feedback
- more robust connection management and retries
- support for more OBD protocols and non-ELM adapters
- security access and coding functions
- support for more adapter types (Bluetooth, USB)
- better logging and log export
- UI polish and animations
