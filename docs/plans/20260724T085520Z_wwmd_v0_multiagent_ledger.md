# WWMD v0 Root-Owned Implementation Ledger

Status: active
Author: root agent
Created: 2026-07-24T08:55:20Z
Controlling plan: /Users/jmajor/.codex/attachments/675a9623-9408-4fc6-a7a9-99df61c99853/pasted-text.txt
Design document: docs/WWMD_AI_ENGINEERING_OBSERVABILITY_DESIGN.md

## Operating contract

The root agent is the sole author and implementer. The three parallel analysts
performed read-only inspection only; their reports were reconciled by the root
before the design document was written. WWMD neither reads, migrates, nor
changes predecessor historical activity databases.

## Gate 0 baseline

| Item | Evidence |
|---|---|
| Task identity | Renamed to WWMD. |
| GitHub destination | Public repository https://github.com/iamh2o/wwmd created after GitHub identity verification. |
| WWMD repository | /Users/jmajor/projects/iamh2o/wwmd; main at bf62d05; clean immediately after clone. |
| Independence boundary | No predecessor source files, checkout, or historical database were imported or altered. |
| Missing source contract | codex-overview-calls-2026-07-24.csv and a proven stable local Codex live source were unavailable. No inferred mapping is allowed. |
| Baseline sweeps | Repository and source manifest, instruction, status, test, architecture, storage, privacy, correlation, metrics, and UX inspection were completed read-only. |

## Root reconciliation before authoring

| Reconciled term | Frozen meaning and owner |
|---|---|
| WWMD | Independent, MIT-licensed application with its own database identity and no predecessor-data migration. |
| Agent | Persistent per-user macOS process that owns all collection, mutation, and database writes. |
| App | Menu-bar and viewer process that requests control/query operations over authenticated native XPC. |
| Ledger | Immutable normalized TelemetryEventV1 records in the new WWMD SQLite database. |
| Projection | Rebuildable typed table derived only from ledger events and projection checkpoints. |
| Adapter | Statically linked, opt-in, in-process source reader that validates and redacts before offering events to the core. |
| Activity metadata | Safe session/app/project metadata only; no window titles, idle inference, keystrokes, or content. |
| Correlation | Evidence-scored association, never a causal assertion. |
| Recommendation | Versioned deterministic rule result with supporting observations and user controls. |

## Control rows

| ID | Area | Requirement | Status | Category | Gate | Owner | Evidence | Root cause | Terminal note |
|---|---|---|---|---|---|---|---|---|---|
| G0-001 | Repository | Create and baseline public WWMD repository | SUCCESS | feature_implementation | Gate 0 | root | public iamh2o/wwmd; bf62d05 | — | Repository, README, and MIT license exist. |
| G0-002 | Repository boundary | Preserve WWMD independence from predecessor source and historical data | SUCCESS | active_product_contract | Gate 0 | root | Independence boundary recorded above | — | No predecessor files or historical data were imported or altered. |
| G0-003 | Data contract | Locate requested Codex CSV or reliable live source | BLOCKED | active_product_contract | Gate 0 | root | Attachment/workspace inspection found neither contract | Actual header/schema and stable local live source are unavailable | ADP-CODEX-CSV cannot map or import until an actual schema is supplied; live adapter is deferred. |
| G1-001 | Architecture | Reconcile analyst evidence, terminology, ownership, boundaries, schemas, trust model, and v0 scope | SUCCESS | feature_implementation | Gate 1 | root | Reconciliation table above; root review of four read-only reports | — | One terminology and ownership model is frozen. |
| G1-002 | Design | Write one root-authored implementation design | SUCCESS | feature_implementation | Gate 1 | root | docs/WWMD_AI_ENGINEERING_OBSERVABILITY_DESIGN.md, sections 1-41 | — | The document freezes one architecture and records source evidence, boundaries, schemas, privacy, reliability, and V0 scope. |
| G1-003 | Design | Complete single-owner requirement consistency review | SUCCESS | contract_test | Gate 1 | root | Heading sweep confirms sections 1-41; Mermaid fence sweep; required-boundary sweep; post-implementation review below | — | Root reconciled terminology, ownership, schema, trust, scope, and unavailable data requirements without contradictions. |
| FND-001 | Core | Versioned domain types, validation, provenance, redaction, and canonical event envelope | SUCCESS | feature_implementation | Gate 2 | root | Sources/WWMDCore/TelemetryEvent.swift; TelemetryEventTests (5 passing) | — | Closed event kinds, per-field provenance, bounded opaque identifiers, sensitivity, secret/content rejection, idempotency key, identity, and checkpoint contracts are implemented. |
| FND-002 | Storage | Serialized SQLite ledger writer, idempotency, integrity, retention, and backup primitives | SUCCESS | feature_implementation | Gate 2 | root | TelemetryStore actor; persistence/migration/pause/export/backup/purge tests; swift test -> 43 passed | — | Single-writer ledger, idempotency, integrity, durable pause, scoped purge, and local backup primitive are implemented. |
| MIG-001 | Storage | Atomic migrations and deterministic projection rebuild/checkpointing | SUCCESS | feature_implementation | Gate 2 | root | v1-to-v4 fixture migration, projection checkpoint, deterministic ProjectionEngine rebuild; swift test -> 43 passed | Exact Date equality failed after SQLite REAL round trip; assertion was changed to semantic fields plus 1 ms timestamp tolerance | Atomic migration, projection checkpoint, and deterministic replay now pass full suite. |
| IPC-001 | Process | Versioned native XPC contract and agent/app ownership boundary | IN_PROGRESS | feature_implementation | Gate 2 | root | NativeXPCServer/NativeXPCClient, same-user delegate check, typed health/summary/evidence/recommendation/pause/deletion dispatch, and XPC service tests; swift test -> 43 passed | Release Team ID/entitlement/Mach-service configuration is unavailable, so a signed cross-process proof cannot run | Native listener/client requires explicit code-signing requirements; safe query, pause, and two-phase deletion RPCs are implemented and direct database CLI access is removed. |
| ADP-CODEX-CSV | Collection | Exact Codex CSV importer | BLOCKED | active_product_contract | Gate 3 | root | G0-003 | No actual CSV schema is present | Hard-fail by contract; no generic or inferred mapping will be implemented. |
| ADP-GIT | Collection | User-selected repository metadata adapter | IN_PROGRESS | feature_implementation | Gate 3 | root | Explicit-root GitMetadataReader, hashed repository ID, aggregate-only offer, atomic commit checkpoint, and opt-in-before-read test; swift test -> 34 passed | Security-scoped bookmark persistence and scheduled source lifecycle are not implemented | Selected exact root is canonicalized and must match Git toplevel; no discovery, path persistence, filename capture, or source content capture exists. |
| ADP-ACTIVITY | Collection | Safe activity/session metadata adapter without title capture or idle inference | IN_PROGRESS | feature_implementation | Gate 3 | root | SafeActivityAdapter, agent recordSafeActivity entrypoint, and negative title/idle privacy test | A real user-approved activity notification source and UI consent flow are not implemented | Only caller-supplied state, app bundle ID, and optional repository ID can form an offer. |
| ADP-BUILD | Collection | Explicit build/test wrapper metadata adapter | IN_PROGRESS | feature_implementation | Gate 3 | root | ExplicitValidationRunner, agent runExplicitValidation entrypoint, and opt-in-before-execution/no-argument-or-output tests | No app/XPC command-launch consent UI exists | Command invocation happens only after exact opt-in; arguments and output remain ephemeral. |
| ADP-ANNOTATION | Collection | User annotations and association corrections | IN_PROGRESS | feature_implementation | Gate 3 | root | Typed outcome, association-correction, and recommendation-control contracts plus runtime entrypoints | Native annotation/correction controls and persisted work-unit views are not implemented | Annotation payloads are closed enums/opaque IDs and user-sensitive by design; raw free-text annotation is excluded. |
| COR-001 | Value | Deterministic association model with evidence, confidence, competitors, and correction | IN_PROGRESS | feature_implementation | Gate 4 | root | Sources/WWMDAnalytics/CorrelationAndRules.swift; clear-winner, user-correction override, and deterministic rebuild tests | Typed association projection persistence and native correction view remain unimplemented | Candidate/evidence/score/ambiguity foundation and ledger-derived user correction are implemented. |
| MET-001 | Value | Computable measured/derived/estimated metric catalog and projections | IN_PROGRESS | feature_implementation | Gate 4 | root | MetricCalculator and ProjectionEngine; token/cache/context/thread/correlation formula and sample-floor tests | Price-table metrics and typed metric-window persistence remain unimplemented | Measured/derived availability semantics and explicit data-gap outcomes are implemented. |
| REC-001 | Value | Versioned deterministic recommendations, controls, and audit trail | IN_PROGRESS | feature_implementation | Gate 4 | root | RecommendationEngine: data quality, context pressure, long thread, repeated validation; ledger-derived dismiss/snooze test | Native evidence view and persisted materialized recommendation state remain unimplemented | Versioned deterministic proposals, scope keys, and audit events drive active recommendations. |
| EXP-001 | Value | Privacy-safe NDJSON, CSV-summary, and SQLite backup export | SUCCESS | feature_implementation | Gate 4 | root | TelemetryStore.export/backup; safe-profile, backup, managed-output registry, and purge tests; swift test -> 43 passed | — | Agent-owned safe NDJSON, CSV summary, consistent SQLite backup, checksummed receipts, managed-output registration, and no-overwrite behavior are implemented. |
| UX-001 | Native product | Collection health, pause, summaries, drill-down, and association correction views | IN_PROGRESS | feature_implementation | Gate 5 | root | Sources/WWMDApp/main.swift explicit Mach-service/designated-requirement form, off-main authenticated health check, durable pause control, named `wwmd-main` Window, and `Open WWMD` action; swift test -> 43 passed | Release Team ID/entitlement/Mach-service configuration is unavailable, and projected summaries/drill-down/correction views are not implemented | The app never opens the database: it enables health/pause only after an explicit configured native XPC connection succeeds, and otherwise reports configuration or connection failure. |
| CLI-001 | Native product | Read-only local query and export CLI | IN_PROGRESS | feature_implementation | Gate 5 | root | NativeXPCClient and `wwmd health/summary/evidence/recommendations` safe JSON commands; no direct DB access; swift test -> 43 passed | Signed service integration and XPC-mediated export are not wired to a production agent | Functional bounded read-only health/summary/evidence/recommendation surface is implemented behind authenticated XPC configuration. |
| PRIV-001 | Privacy | Persistent consent/pause, inclusion/exclusion, retention, redaction, and provenance | IN_PROGRESS | feature_implementation | Gate 5 | root | Core PrivacyGate opaque-metadata/secret tests; Store collection/adapter state, scoped purge, checksum-guarded managed deletion; runtime opt-in-before-read/run checks | Repository allowlist/bookmarks, native deletion UI, and source-adapter consent views are not complete | Persistent global pause, explicit adapter opt-in state, core redaction rejection, provenance, retention primitive, and a bounded agent-mediated deletion path are implemented. |
| DEL-001 | Privacy | Complete local deletion including WAL/SHM/backups/exports selected by user | IN_PROGRESS | feature_implementation | Gate 5 | root | Storage v4 managed-output/deletion-receipt tables; two-phase XPC deletion request; agent-owned 60-second nonce; stale/missing/changed output tests; swift test -> 43 passed | Complete database/WAL/SHM removal must run only after the agent stops, and signed native selection/confirmation UI is not configured | Explicit bounded event deletion and exact registered export/backup deletion are agent-owned, checksum-guarded, revision-bound, and receipt-backed. No raw path or default-all deletion is accepted. |
| SEC-001 | Release proof | XPC peer trust, codesigning configuration, and injection resistance | OPEN | contract_test | Gate 6 | root | Planned signed-build/XPC tests | — | — |
| REL-001 | Release proof | Crash, disk, clock, sleep/wake, adapter, and source rotation recovery proof | OPEN | contract_test | Gate 6 | root | Planned fault-injection tests | — | — |
| PERF-001 | Release proof | 24-hour soak and measured idle CPU/RSS/backpressure evidence | OPEN | contract_test | Gate 6 | root | Planned benchmark receipt | — | — |
| FINAL-001 | Release proof | Terminal ledger reconciliation and release documentation | OPEN | contract_test | Gate 6 | root | Final review | — | — |

## Required design consistency review

Before implementation begins, the root must verify that the design:

1. uses one name for each process, data object, and boundary;
2. gives every durable field provenance, sensitivity, and measurement class;
3. assigns exactly one component as database writer;
4. does not retain predecessor window-title data or create a migration path;
5. does not promise a Codex mapping without a real CSV schema;
6. uses native XPC rather than an inherited Unix socket or network listener;
7. keeps v0 local, offline, single-user, deterministic, and non-plugin-based;
8. keeps every recommendation evidence-linked, calibrated, and non-causal;
9. keeps privacy controls pre-persistence and deletion end-to-end; and
10. identifies every unavailable or deferred data-dependent metric rather than fabricating it.

## Current status

Working rows: 16 (12 IN_PROGRESS, 4 OPEN)
Terminal rows: 11 (9 SUCCESS, 2 BLOCKED)
Objective complete: no. Foundation/export, bounded XPC query, managed deletion, and app health/pause foundations are complete; collection lifecycle, signed runtime proof, projected data/correction/deletion views, XPC export, full database deletion lifecycle, and release proof remain.

## Active implementation slice: managed deletion

This root-owned slice closes the code-ready portion of `DEL-001` without
claiming a signed release configuration or external-source contract.

| Boundary | Frozen responsibility |
|---|---|
| App / signed CLI | May request a preview or confirm an agent-issued deletion nonce; never opens the database or supplies a raw deletion path. |
| Native XPC | Validates destructive capability and request shape. Preview and confirmation are separate calls. |
| Agent runtime | Owns an in-memory, short-lived nonce, rejects stale previews, and maps safe XPC data to one storage request. |
| TelemetryStore | Is the only database/file mutation owner. It deletes only outputs it previously registered and only events in an explicit bounded scope. |
| Managed output registry | Records newly generated export/backup paths internally; XPC responses expose only output ID, kind, filename, size, and time. Existing legacy receipts without a registered path are not inferred into delete targets. |

The request must name either an exact time-bounded event scope or exact managed
output IDs. There is no wildcard/default-all operation. A confirmation is bound
to the preview's ledger sequence and selected output set; any intervening change
requires a new preview. Before a registered file is removed, its current
checksum must still match the one recorded at creation; a changed file is left
untouched and requires a new explicit user decision. WWMD can delete only
still-managed files; user-moved or copied outputs remain outside its deletion
boundary. Full database/WAL/SHM removal remains a separate stopped-agent
operation and is not represented as an agent-side fallback.

## Managed-deletion single-owner consistency review

The root re-reviewed this slice after code, tests, README, design, and threat
model updates. It is consistent with the supplied implementation brief as
follows:

| Review point | Result | Evidence / boundary |
|---|---|---|
| Terminology | PASS | A *managed output* is only an export or backup created and registered by `TelemetryStore`; it is not a user-supplied path or a source bookmark. A *deletion receipt* is an aggregate record, not a copied event or raw scope. |
| Component ownership | PASS | App/signed CLI request; XPC validates; `WWMDAgentRuntime` owns nonce lifetime; `TelemetryStore` alone mutates SQLite and removes files. |
| Process and trust boundary | PARTIAL | `destructive_delete` capability, typed request shape, same-user listener check, and explicit signing requirement exist. A release Team ID/entitlement/Mach-service proof is still unavailable, so `SEC-001` remains open. |
| Schema and privacy | PASS | Schema v4 adds private `managed_outputs` paths plus aggregate `deletion_receipts`; paths/checksums do not cross XPC and receipts store no raw path, output ID, or deleted event. |
| Scope and recovery | PASS | Requests require a bounded time scope and/or exact registered IDs, are capped at 100 outputs, have no wildcard/default-all behavior, bind confirmation to latest ledger sequence, consume the nonce, and reject changed outputs before removal. Missing outputs clear only their registry receipt. |
| V0 boundary | PASS | No network listener, dynamic plugin, source discovery, predecessor data, prompt/content capture, or direct-database app/CLI access was added. |
| Completion boundary | PARTIAL | Native deletion UI, security-scoped path authority, full stopped-agent DB/WAL/SHM removal flow, and release signing proof remain outside this implemented slice. |

## Signed-app XPC single-owner consistency review

The root re-reviewed the native-app connection slice after its code and
documentation were written. It does not widen filesystem, collection, or IPC
authority beyond the frozen V0 boundary.

| Review point | Result | Evidence / boundary |
|---|---|---|
| Configuration | PASS | The app persists only nonempty user-entered Mach-service and code-signing-requirement strings; it never accepts a database path, source path, or inferred service. |
| Process ownership | PASS | `WWMDApp` depends on `WWMDIPC`, not `WWMDStorage`; health and pause use `NativeXPCClient`, while the agent remains the only mutable database owner. |
| UI behavior | PASS | XPC work runs off the main actor; the app exposes health and pause only after a successful authenticated health response, and connection failure clears the live state and disables mutation. |
| Trust boundary | PARTIAL | A configured client still sets the exact peer requirement. The app cannot validate a release Team ID, entitlement, or launchd service until those external values exist; `SEC-001` remains open. |
| V0 scope | PASS | No source enablement, path selection, raw telemetry view, export, deletion confirmation, network listener, or direct-database fallback was added. |

## Root single-owner post-implementation consistency review

Reviewed against both supplied briefs on 2026-07-24 after the current code and
documents were written, including the managed-deletion and signed-app-XPC
slices. `PASS` means the current implementation/documentation matches the
requirement; `PARTIAL` identifies a visible, non-terminal ledger row; `BLOCKED`
identifies a missing external contract or release configuration.

| Brief requirement | Result | Reconciliation evidence |
|---|---|---|
| New WWMD identity/database; never read, migrate, or alter predecessor history | PASS | Separate public repository and SQLite schema; README/design/PrivacyGate contain no predecessor migration path. |
| Local-first, offline, single-user, static-code V0; no HTTP/GraphQL/cloud/plugins | PASS | Package target graph, native XPC-only code, and no network dependency/endpoint. |
| App, persistent agent, and read-only CLI with native XPC | PARTIAL | `WWMDAgentRuntime`, `wwmdd`, `wwmd`, and SwiftUI app exist; the app can configure and test explicit signed XPC health/pause, but production Mach-service/signing is not available and data views remain incomplete. |
| SQLite/WAL, one serialized writer, immutable events, atomic migrations/checkpoints, deterministic replay | PASS | `TelemetryStore` actor, WAL settings, v1-to-latest fixture, projection checkpoint, and tests. |
| Exact Codex CSV/live-source mapping only after real source contract | BLOCKED | G0-003/ADP-CODEX-CSV remain blocked; exact-header gate has no inferred mapping. |
| Explicit Git, safe activity, explicit build/test, and typed local annotation adapters | PARTIAL | Git/build/activity/annotation boundaries and opt-in checks exist; bookmarks, user-facing consent, activity source, and scheduler/retry lifecycle remain. |
| Pre-persistence privacy, provenance, sensitivity, no content/title/arguments/log/environment/browser capture | PASS | Closed descriptors, prohibited-field/secret/opaque-ID gate, metadata-only adapters, and regression tests. |
| Persistent global pause and per-adapter opt-in | PARTIAL | Durable store/runtime enforcement, XPC pause control, and native signed-XPC pause UI exist; adapter consent/source views remain incomplete. |
| Evidence-scored correlation, competing candidates, user correction, no causal claims | PARTIAL | Deterministic scoring and ledger-derived correction override exist; typed materialized projection/UI are pending. |
| V0 data-quality, context-pressure, long-thread, and repeated-validation recommendations with controls | PARTIAL | Deterministic, evidence-gated rules plus ledger-derived dismiss/snooze exist; materialized state/evidence UI are pending. |
| Redacted NDJSON/CSV/SQLite backup export; cost only with local effective-dated price source | PARTIAL | Safe exports/backups, receipts, and registered-output deletion exist; XPC CLI export and native output selection remain pending; cost remains unavailable without a supplied price table. |
| Complete local deletion of DB/WAL/SHM/backups/exports | PARTIAL | Scoped event deletion plus checksum-guarded registered export/backup deletion are previewed and confirmed through an agent-owned nonce; the stopped-agent DB/WAL/SHM operation and native deletion UI remain pending. |
| XPC local-process threat resistance | PARTIAL | Explicit native client/server code-signing requirements and same-user server acceptance exist; Team ID/entitlements/signed cross-process proof are blocked. |
| Crash/disk/clock/sleep/source-rotation recovery and idle/performance targets | PARTIAL | SQLite transactions, integrity check, bounded XPC queries, and deletion stale/missing/changed-output guards exist; fault-injection and 24-hour/CPU/RSS proof are open. |
| Final acceptance requires terminal ledger rows and objective completion | NOT MET | 16 implementation/release rows remain working; this ledger deliberately does not claim completion. |

Result: no terminology, ownership, process-boundary, schema, trust-boundary, or
V0-scope contradiction was found in the current implementation/design. Missing
work is recorded as `IN_PROGRESS`, `OPEN`, or genuine external `BLOCKED` rather
than being represented as a completed feature.
