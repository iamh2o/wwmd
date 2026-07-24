# WWMD macOS App Packaging Ledger

Status: complete
Created: 2026-07-24T12:41:30Z
Owner: root

## Gate 0 inventory

| Item | Evidence |
|---|---|
| Requested outcome | User requested a normal installed macOS app and approved packaging work. |
| Install destination | `/Users/jmajor/Applications/WWMD.app` did not exist before packaging. |
| Runtime contract | V0 is a single-process local menu-bar app; no XPC, socket, daemon, or service installation is part of this package. |
| Distribution boundary | The local bundle is ad-hoc signed for this Mac only. Developer ID signing, notarization, and public distribution remain out of scope. |

## Execution rows

| ID | Requirement | Status | Evidence | Terminal note |
|---|---|---|---|---|
| DIST-001 | Reproducibly package `WWMDApp` as a macOS `.app` | SUCCESS | `Packaging/Info.plist`; `scripts/package-macos-app.sh`; `swift build -c release --product WWMDApp`; `plutil -lint`; `codesign --verify --deep --strict` | Release executable built, bundle metadata validated, and ad-hoc signature verified. |
| DIST-002 | Install the app without overwriting an existing bundle | SUCCESS | Target absence verified before install; installer refusal guard; `/Users/jmajor/Applications/WWMD.app`; installed process PID 4993 | Installed without replacing an existing bundle and launched through `open`. |
| DIST-003 | Preserve V0 process/trust boundary in installed package | SUCCESS | `LSUIElement` menu-bar app; no launch agent, Mach service, or socket configuration | Package contains only the WWMD executable and metadata. |

## Completion criteria

1. Release executable builds successfully.
2. Bundle has valid plist and ad-hoc code signature.
3. Bundle is installed at the explicit user-local destination without replacing an existing app.
4. `open` launches the bundle and the WWMD process is observable.
5. README documents the local package boundary and command.

## Result

All packaging rows are terminal. The installed local application is
`/Users/jmajor/Applications/WWMD.app`. It is intentionally an ad-hoc signed
local build; Developer ID signing, notarization, App Store distribution, and
automatic update delivery are separate future release work.
