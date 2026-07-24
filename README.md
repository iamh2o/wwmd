# WWMD

WWMD is an in-development, local-first macOS application for examining the
observable engineering evidence around AI-assisted work. It is designed to
answer “what engineering value am I receiving?” rather than to be a token-only
dashboard.

It is an independent application and database. It does not read, migrate, or
retain historical activity or window-title data from another application.

## Quick start

For macOS/Swift/Git prerequisites, exact setup commands, local database health
verification and development-app startup, follow the
[quickstart](docs/QUICKSTART.md).

## Current foundation

- Swift 6 / macOS 13+ modular package with a menu-bar/viewer that explicitly
  opens one local database file and owns its in-process runtime. The package
  also contains Core, SQLite storage, adapters, analytics, and a future IPC
  contract module.
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
- V0 is single-process local mode: the app acquires an exclusive lease for the
  exact database path, owns the runtime, and makes bounded health, pause, and
  explicit date-range summary/recommendation calls in-process. It starts no
  Mach service, socket, daemon, or network listener. The `wwmd` CLI never
  opens the database. Native XPC code is deferred to a future signed release,
  not a requirement for current use.
- No prompt/response text, source contents, window titles, shell arguments,
  logs, environment values, clipboard, screenshots, keylogging, browser
  history, cloud upload, or background LLM analytics.

Security-scoped source bookmarks and scheduling, projected data/adapter-
consent/deletion views, the stopped-app database/WAL/SHM deletion operation, a
real Codex CSV/live-source contract, native XPC packaging for a later release,
and release performance/security proof remain in progress.

## Build

~~~text
swift test
swift run WWMDApp
swift run wwmd --version
~~~

The optional closed-app health diagnostic requires an explicit database path:

~~~text
swift run wwmdd --database /absolute/path/to/wwmd.sqlite --health
~~~

For normal use, run `swift run WWMDApp`, enter an absolute database file path,
and choose **Open selected database**. Do not run `wwmdd` against that same
database while the app is open: both supported entrypoints acquire the same
exclusive local lease.

## Install a local macOS app bundle

For a normal user-local application bundle, build and install WWMD explicitly:

~~~sh
scripts/package-macos-app.sh --install-dir "$HOME/Applications"
open "$HOME/Applications/WWMD.app"
~~~

The installer refuses to overwrite an existing `WWMD.app`. This is an ad-hoc
signed local build for this Mac, not a Developer ID-signed or notarized public
release. It installs no launch agent, XPC service, socket, or daemon.

## Design and ledger

- [Architecture design](docs/WWMD_AI_ENGINEERING_OBSERVABILITY_DESIGN.md)
- [Root-owned implementation ledger](docs/plans/20260724T085520Z_wwmd_v0_multiagent_ledger.md)
- [Foundation threat model](docs/wwmd-threat-model.md)

The ledger is the current source of truth for implementation state and explicit
blocks. In particular, the Codex data contract remains blocked until actual
source evidence is supplied.

## License

MIT. See [LICENSE](LICENSE).
