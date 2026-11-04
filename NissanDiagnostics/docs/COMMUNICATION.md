# Nissan communication reconstruction

Target: NDSIII Lite 1.44, package `com.nissandatascan.ndatascaniiilite`, APK SHA-256 `db45043c991ac2f1e7e90865e378b63a55ad3972bc58d50da2d18baff7217f22`.

Requested vehicle: 2008 Skyline. The implemented default is the Android app's ordinary petrol ECM path. Actual engine, ECM family, adapter, and vehicle replies still need validation. The family byte does not establish petrol versus diesel; fuel profile is explicit configuration.

## What was observed

The application sends ELM ASCII commands terminated with carriage return, sets header `7E0` using `ATSH7E0`, and selects `ATSP6`. ELM protocol 6 is ISO 15765-4 CAN with 11-bit identifiers at 500 kbit/s (Elm Electronics ELM327 datasheet: https://elmelectronics.com/wp-content/uploads/2020/05/ELM327DSL.pdf). ELM handles CAN/ISO-TP formatting and flow control; this Swift layer does not send raw CAN frames.

The recovered application protocol combines Nissan-specific register definitions with diagnostic services `10`, `21`, `22`, `17`/`19`, and `14`. Calling this the observed NDSIII/Nissan enhanced diagnostic path is more precise than claiming a complete clone of the proprietary CONSULT-III tool. Dealer-interface transport, other control modules, security access, and complete CONSULT-III behavior were not established.

| Operation | Request | Decoded positive response |
|---|---|---|
| Initial session | `1081`, then `10C0` | `50 81`, then `50 C0` |
| ECU identity | `2183`, fallback `21FE` | `61 83` / `61 FE`, five ASCII ID bytes, family byte |
| Before DTC read or clear | `10C0` | `50 C0` |
| Ordinary petrol DTC read | `17FF00` | `57`, count, count × three-byte records |
| Petrol family `A0` DTC read | `19020F` | `59 02`, availability byte, four-byte records |
| Diesel family `05` DTC read | `19022F` | same `59 02` framing |
| Diesel family `70` DTC read | `19020F` | same `59 02` framing |
| Other diesel DTC read | `1902FF` | same `59 02` framing |
| Ordinary petrol clear | `14FF00` | `54` |
| Other paths above clear | `14FFFFFF` | `54` |
| Numeric live data | `22` + two-byte DID | `62`, matching DID, one/two-byte big-endian raw value |
| Supported DID bitmap | e.g. `221100` | `62 11 00`, four bitmap bytes; MSB first represents `1101` through `1120` |

A DTC read/clear waits for the current request to finish, up to three seconds. Session receive timeout is 700 ms. DTC read, clear, and individual logging reads use 500 ms. Initial ELM/session setup and identity reads use two seconds. Android receives until an expected ASCII byte count or timeout; the Apple TCP adapter instead waits for the ELM prompt, under the same operation deadline. This difference requires adapter testing.

`14` is invoked only by an explicit `clearTroubleCodes()` call. A clear is sent once, its reply is validated, and no automatic retry or automatic post-clear reread is performed. A timeout means the outcome is unknown; it is not evidence the ECU failed to clear. No vehicle clear was executed during this investigation.

## Logging behavior

Android `p4` issues one selected register read at a time, in list order. `l3` decodes the response, advances/wraps the selection index, and calls `p4` again. There is no simultaneous CAN PID burst in this path. Numeric conversion is `unsignedRaw * scale + offset`; switch parameters use a distinct bit table. CSV/file writing is separate from acquiring ECU data.

The Swift `readCycle(parameters:)` reproduces numeric sequential acquisition and attaches ECU errors to individual samples. `NissanDataLogger.stream` repeats cycles with a bounded newest-cycle buffer. Its default inter-cycle delay is zero, matching response-driven polling; a caller may request a slower cadence. Cancel the consumer before invoking DTC actions. An ECU error is retained with a timestamp rather than silently recorded as a valid zero. Transport errors end the stream.

`read(register:)` supports additional explicitly defined numeric DIDs. `supportedRegisters(base:)` decodes a 32-register support bitmap. The nine-value petrol catalog is a recovered subset, not the complete Android numeric/switch catalog. Five unambiguous diesel counterparts are included; unsupported mappings fail instead of using petrol scaling.

The petrol RPM factor in the APK is literally `12.5`; this unusual factor is preserved, not corrected by assumption. Throttle is sensor voltage, not percent. Both require comparison with real vehicle replies.

## Swift usage

```swift
let client = DiagnosticClient(transport: adapter, profile: .petrol)
try await client.initialize()
let ecu = try await client.identifyECU()
let codes = try await client.readTroubleCodes()

// Explicit action only; do not invoke automatically on connect or while logging.
try await client.clearTroubleCodes()

let supported = try await client.supportedRegisters(base: 0x1100)
let stream = try await NissanDataLogger(client: client).stream(
    parameters: [.rpm, .coolant, .battery])
for try await cycle in stream {
    // Consume successful values and sample errors; cancellation ends polling.
}
await client.close()
```

`ELMTransport.exchange(_:timeout:)` must honor the deadline in a production adapter. A default forwarding implementation preserves compatibility with older/mock transports; the included TCP transport and transcript wrapper forward the timeout explicitly. `prepareDataLogging()` enters `10C0`; the app invokes it before dashboard polling.

## Evidence and limitations

REA/JADX 0.7.1 successfully examined the shipped APK after provider configuration. Complete initial method results are in `communication-evidence.json`; `communication-evidence-index.json` records additional method identities and limitations. Java generation for `m4` fell back to smali and is marked as such. All observations are static, not vehicle execution.

| Finding | Method / decoded smali location | REA Evidence |
|---|---|---|
| DTC request family selection | `MainActivity.m4`, line 37666 | `ev_b63abbcb89b9d18b0a140c1654535de55b908573b976412ca09076700b5a7f33` |
| Clear request selection | `MainActivity.l4`, line 36217 | `ev_644f77f53fe3b8216c3ffa3b8445b54c2ff20691f8cd3eb5066c4b6d230da628` |
| Clear starts session | `MainActivity.T1`, line 8468 | `ev_3161dc7eb7a97ba6997d38d44ad152c377465eda9fa41f765311550961b2e69a` |
| Clear session/result handlers | `D2` / `q2`, lines 1447 / 48407 | `ev_486823ec3dc8ce3a1978e14a9b0b364376a6e4591f7f73a0d3c91ba7644dc2e4`, `ev_f97e2ac5dcd621d4b7d20bd69002feb97ac31e058d1c9a7ac70604c073f0e925` |
| Sequential logging requests | `MainActivity.p4` | `ev_b0b45283ec87504a41ee675ecb7935a29fc4d65d62db4fd351454c93698f47aa` |
| Numeric response conversion | `MainActivity.l3`, line 35122 | `ev_5a8f3ef9d74aad0ba036b4ca6cd8f7390d9495b0365e6dc85783aa437f2227df` |
| DTC record parsing | `v2` / `w2`, lines 50115 / 51151 | `ev_8ba1ceb187996812ae5f2b1decc0d3fa3de66f13b0b798a3fb95ff2a0f6506cb`, `ev_8ad6d77fa755e50461d1001c96a05d6da28606f8ebadab2c4b54e8df408800e3` |
| CR-terminated transport dispatch | `MainActivity.r0`, line 48512 | `ev_59fdbda89e09ae333fd9446d0f5c1fba16f01992214c2e9377703d8d7593caea` |

Direct decoded-smali corroboration: `b4` line 20722 (DTC read entry), `K2` line 3533 (read-session response), `m2` line 36980 (supported bitmap), `MainActivity$l.run` lines 58–132 (idle wait), and `i2/a$c` (receive-count timeout). Petrol table is `e0`, diesel `f0`; changing fuel profile is necessary even where DIDs overlap.

The clone deliberately rejects malformed, mismatched, or ambiguous replies; the Android implementation often only searches for ASCII service substrings and swallows parser errors. This is an intentional difference. Raw UDS DTC record bytes are retained, including the third DTC byte and status, even though Android displays a shortened P/C/B/U code.

Remaining: real ELM/ECM transcript validation on the 2008 Skyline; all remaining live/switch parameter definitions; session keep-alive/recovery timing (no keep-alive behavior established in this bounded trace); Bluetooth/BLE adapter-specific transport; additional modules. No claim of complete CONSULT-III compatibility is made.
