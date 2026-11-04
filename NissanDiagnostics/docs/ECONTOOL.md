# EconTool 4.11 investigation and OBDMVP integration

## Artifact and evidence boundary

Input: `com.scobasoft.econtool_4.11.xapk_Decompiler.com.zip` (a supplied decompiler export, not a verified original APK).
SHA-256: `f4688bb44ef46b59796d0e3cc07dccf55d932592a03bebaa4ced343616765dd2`.
REA extraction Evidence: `ev_6b4aa68d55f1070f80dd53bf8439b3cc8c056fcb89fa60cfa0af70f87e9a9b60`.
REA safely materialized 6,379 regular files. Nested archives were not recursively extracted. Subsequent observations below are ordinary static Java/smali/resource inspection, not additional REA method Evidence or runtime execution. The supplied export's correspondence to an authentic store release was not verified. File hashes for the cited evidence are in `econtool-evidence-index.json`.

No Android target or connected vehicle was executed. Protocol behavior and compatibility need real adapter/vehicle validation. No proprietary source, translations, or resource assets were copied into the application; Swift implementations reconstruct the observed protocol behavior.

## Findings and implementation

All paths below are relative to the archive extraction root.

| Question | Static evidence | Applied behavior / limits |
|---|---|---|
| Which Consult interfaces work with ELM327? | `resources/res/values/strings.xml:129`, also 4, 13, 74, 131, 134–137 | EconTool describes NC1 as RX/TX, NC2 as K-Line and NC3 as CAN. It lists ELM support for NC2 engine/ABS/SRS and NC3 engine/CVT. OBDMVP implements bounded CAN paths; it does not claim NC1 or K-Line support. |
| How does Wi-Fi route to the adapter? | `sources/defpackage/pg1.java:134–143`, `rg1.java:80–105`, `ti.java:24–30` | Explicit Wi-Fi selection; EconTool binds a local IPv4 in its expected subnet. OBDMVP uses Network.framework's required Wi-Fi interface, retaining configurable host/port instead of imposing that subnet. |
| How are writes and errors handled? | `sources/defpackage/ml0.java:239–271`, `pg1.java:48–78`, 112–159 | CR termination, socket cleanup on errors. OBDMVP additionally handles EOF, serializes lifecycle operations and rejects stale socket callbacks. These guards are design improvements. EconTool's reconnect loop is not reproduced: reconnection must reinitialize the ECU session, and writes must not be replayed. No TCP_NODELAY trick was established. |
| How are engine responses filtered? | `sources/defpackage/g71.java:565–574` | `ATCRA7E8` added to existing ECM initialization. |
| How are service capabilities discovered? | `sources/defpackage/jk0.java:1763–1820`, `smali/jk0.smali:13451–14300` | Active-test masks `3000`, `3020`, `3040`, `3060`; learning `3100`; correction `3B00`. Replies contain service+40, matching base, four MSB-first bitmap bytes. Only function bits 1–31 are enumerated. All pages must validate before authorizing a learning. |
| Why do some source commands end in 0401? | `sources/defpackage/jk0.java:1151–1200` | NC3 strips that NC2 suffix. The source also appends ELM expected-response counts to selected single-frame requests. OBDMVP keeps prompt framing and does not add counts to potentially multi-frame reads. |
| Which work-support actions are named? | `sources/defpackage/gk0.java:147–173` | Learning03 idle air,04 closed throttle,06 fuel trims; correction01 ignition timing and02 idle RPM. UI reports capability IDs; only learning03/06 have executable controls. Active tests/corrections are not executed. |
| How is learning performed? | `sources/defpackage/gk0.java:279–419`; `smali/gk0.smali` literal31/32/72 and20s/120s constants; `resources/res/values/strings.xml:210` | NC3 starts `31{id}00` once;03 waits20s with `3E01`;06 skips wait; requests `32{id}00`, then `31{id}01`; completion `71{id}02`. OBDMVP validates replies, only repeats stop polling on NRC78, bounds the operation, closes on failure/cancellation, and never repeats the start. UI closes after completion and requests ignition off >=10s. Preconditions must come from the vehicle service procedure; the artifact does not establish universal temperature/load limits. |
| Why is closed-throttle execution omitted? | `sources/defpackage/gk0.java:338–351` | Source declares04 successful unconditionally. That does not establish a completion response; exposing success would be misleading. Capability remains visible. |
| How does CVT connection differ? | `sources/defpackage/uk0.java:258–328`; `smali/uk0.smali:1978–2158` | Separate7E1/7E9 address/filter, `ATFCSH7E1`, `ATFCSD300000`, `ATFCSM1`, `10C0`. `ATST32/ATAT2` has one slower `ATST64/ATAT0` fallback on a2101 NO DATA reply. OBDMVP accepts confirmed6101 record variants only. |
| What CVT information can be read? | `sources/defpackage/rk0.java:373–457`, `wk0.java:55–102`, `uk0.java:189–240`; `smali/wk0.smali:2975–3151` |2183 identity (31036- prefix),2102 six calibration IDs,2103 unsigned32-bit deterioration,2110 CVT-A byte8, CVT-B word0, HCOUNT word4/6, HHCOUNT word24/6. No counter reset. HCOUNT units not established; no oil-life percentage inferred. |

## Integration choices

The Nissan screen selects engine or read-only CVT before starting, reusing the existing exclusive Wi-Fi/BLE adapter reservation. Work-support discovery is petrol CAN only; diesel rejects it. Logging stops before service operations. Capability results are session-local and cleared before rediscovery and on initialization/identity changes/close. UI requires explicit confirmation before learning; merely selecting a module or reading support never starts it.

Unknown replies fail closed. A lost acknowledgment does not establish whether an ECU write occurred. Learning errors invalidate the session and do not retry its start. Normalized ELM framing, strict service/record validation, full-width CVT counters, and generation checks are OBDMVP design decisions rather than claims about EconTool runtime.

## Checklist and residual scope

- Wi-Fi implementation: answered within the recovered socket path; applied and covered by fake-socket tests. Real routing/adapter timing untested.
- Nissan diagnostics/Consult architecture: answered for the inspected NC2/NC3 engine and NC3 CVT paths; CAN CVT information and ECM filtering implemented.
- Service specialities/work support: partially implemented. Capability discovery and verified03/06 learning are implemented;04 result semantics unresolved. Active-test and correction execution, NC2 K-Line, NC1 RX/TX, diesel routines, CVT adaptation/reset, and register-based CVT variant2 remain outside the implemented subset.
- Full EconTool parity: not claimed. The complete parameter catalog and every module/routine were not reconstructed.
- Runtime validation: unresolved; no ECU, adapter, Android runtime, or interactive Apple UI test was performed.

Validation on 2026-11-02: 68 tests passed (24 OBDCore and 44 NissanCore); macOS and generic iOS Simulator Xcode builds passed; Theos IPA packaging passed. The coverage export reports 654/675 NissanCore source lines covered (96.89%); this is not whole-application or UI coverage. Tests exercise synthesized protocol transcripts, not captured vehicle traffic. Xcode reports an outdated CoreSimulator service; interactive simulator validation was not performed. The configured review-agent model was unavailable, so review was performed directly instead.
