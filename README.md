# WWMD

WWMD is an in-development, local-first macOS application for examining the
observable engineering evidence around AI-assisted work. It is designed to
answer “what engineering value am I receiving?” rather than to be a token-only
dashboard.

It is an independent application and database. It does not read, migrate, or
retain historical activity or window-title data from another application.

## Quick start

For macOS/Swift/Git prerequisites, exact setup commands, local database health
verification, development-app startup, and the intentional signed-XPC boundary,
follow the [quickstart](docs/QUICKSTART.md).

## Current foundation

- Swift 6 / macOS 13+ modular package with a menu-bar shell, agent executable,
  read-only CLI contract, Core, SQLite storage, adapters, analytics, and IPC
  contract modules.
- Immutable, provenance-carrying TelemetryEventV1 records validated before
  persistence, including bounded opaque metadata identifiers and rejection of
  prohibited content fields/secret-shaped values.
- One SQLite/WAL TelemetryStore actor with prepared statements, source
  idempotency, atomic source checkpoints, migrations, integrity checks, and
  deterministic projection foundations; safe NDJSON/CSV-summary export and
  consistent SQLite backup primitives are agent-owned.
- Explicit metadata-only Git reader, safe activity boundary, build/test runner,
  and typed annotation contracts. Runtime consent is checked before a selected
  repository is read or an explicit validation command is run.
- Codex CSV import deliberately fails closed until a real exact CSV schema is
  provided; no generic/inferred CSV mapping or live-source discovery exists.
- Deterministic correlation, metric availability/sample floors, context/thread
  evidence rules, and recommendation foundations. Ledger-backed user
  correction and dismiss/snooze controls override automatic results without
  claiming causation.
- Native XPC server/client code requires an explicit Mach service and
  code-signing requirement. It supports health, bounded safe summary/evidence/
  recommendation queries, durable global pause control, and a two-phase
  deletion contract for explicit event scopes and registered output IDs; the
  `wwmd` CLI emits safe JSON and never opens the database itself.
- No prompt/response text, source contents, window titles, shell arguments,
  logs, environment values, clipboard, screenshots, keylogging, browser
  history, cloud upload, or background LLM analytics.

Production launchd/Mach-service signing configuration, security-scoped source
bookmarks and scheduling, UI-to-agent connection, native deletion controls and
the stopped-agent database/WAL/SHM deletion operation, a real Codex CSV/live-
source contract, and release performance/security proof remain in progress.
WWMD provides no unsigned XPC or source-discovery fallback.

## Build

~~~text
swift test
swift run WWMDApp
swift run wwmd --version
~~~

The foundation agent health command requires an explicit database path:

~~~text
swift run wwmdd --database /absolute/path/to/wwmd.sqlite --health
~~~

When a signed agent and its exact requirement are configured, the read-only
CLI surface is deliberately explicit:

~~~text
swift run wwmd summary --mach-service <name> --agent-requirement <requirement> --from <RFC3339> --to <RFC3339>
swift run wwmd evidence --mach-service <name> --agent-requirement <requirement> --from <RFC3339> --to <RFC3339> --limit <1-200>
swift run wwmd recommendations --mach-service <name> --agent-requirement <requirement> --from <RFC3339> --to <RFC3339>
~~~

## Design and ledger

- [Architecture design](docs/WWMD_AI_ENGINEERING_OBSERVABILITY_DESIGN.md)
- [Root-owned implementation ledger](docs/plans/20260724T085520Z_wwmd_v0_multiagent_ledger.md)
- [Foundation threat model](docs/wwmd-threat-model.md)

The ledger is the current source of truth for implementation state and explicit
blocks. In particular, the Codex data contract remains blocked until actual
source evidence is supplied.

## License

MIT. See [LICENSE](LICENSE).
