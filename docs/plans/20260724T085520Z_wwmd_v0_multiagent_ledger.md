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
| FND-002 | Storage | Serialized SQLite ledger writer, idempotency, integrity, retention, and backup primitives | SUCCESS | feature_implementation | Gate 2 | root | TelemetryStore actor; persistence/migration/pause/export/backup/purge tests; swift test -> 34 passed | — | Single-writer ledger, idempotency, integrity, durable pause, scoped purge, and local backup primitive are implemented. |
| MIG-001 | Storage | Atomic migrations and deterministic projection rebuild/checkpointing | SUCCESS | feature_implementation | Gate 2 | root | v1-to-latest fixture migration, projection checkpoint, deterministic ProjectionEngine rebuild; swift test -> 34 passed | Exact Date equality failed after SQLite REAL round trip; assertion was changed to semantic fields plus 1 ms timestamp tolerance | Atomic migration, projection checkpoint, and deterministic replay now pass full suite. |
| IPC-001 | Process | Versioned native XPC contract and agent/app ownership boundary | IN_PROGRESS | feature_implementation | Gate 2 | root | NativeXPCServer/NativeXPCClient, same-user delegate check, typed health/summary/evidence/recommendation/pause dispatch, and XPC service tests; swift test -> 34 passed | Release Team ID/entitlement/Mach-service configuration is unavailable, so a signed cross-process proof cannot run | Native listener/client requires explicit code-signing requirements; safe query and pause RPCs are implemented and direct database CLI access is removed. |
| ADP-CODEX-CSV | Collection | Exact Codex CSV importer | BLOCKED | active_product_contract | Gate 3 | root | G0-003 | No actual CSV schema is present | Hard-fail by contract; no generic or inferred mapping will be implemented. |
| ADP-GIT | Collection | User-selected repository metadata adapter | IN_PROGRESS | feature_implementation | Gate 3 | root | Explicit-root GitMetadataReader, hashed repository ID, aggregate-only offer, atomic commit checkpoint, and opt-in-before-read test; swift test -> 34 passed | Security-scoped bookmark persistence and scheduled source lifecycle are not implemented | Selected exact root is canonicalized and must match Git toplevel; no discovery, path persistence, filename capture, or source content capture exists. |
| ADP-ACTIVITY | Collection | Safe activity/session metadata adapter without title capture or idle inference | IN_PROGRESS | feature_implementation | Gate 3 | root | SafeActivityAdapter, agent recordSafeActivity entrypoint, and negative title/idle privacy test | A real user-approved activity notification source and UI consent flow are not implemented | Only caller-supplied state, app bundle ID, and optional repository ID can form an offer. |
| ADP-BUILD | Collection | Explicit build/test wrapper metadata adapter | IN_PROGRESS | feature_implementation | Gate 3 | root | ExplicitValidationRunner, agent runExplicitValidation entrypoint, and opt-in-before-execution/no-argument-or-output tests | No app/XPC command-launch consent UI exists | Command invocation happens only after exact opt-in; arguments and output remain ephemeral. |
| ADP-ANNOTATION | Collection | User annotations and association corrections | IN_PROGRESS | feature_implementation | Gate 3 | root | Typed outcome, association-correction, and recommendation-control contracts plus runtime entrypoints | Native annotation/correction controls and persisted work-unit views are not implemented | Annotation payloads are closed enums/opaque IDs and user-sensitive by design; raw free-text annotation is excluded. |
| COR-001 | Value | Deterministic association model with evidence, confidence, competitors, and correction | IN_PROGRESS | feature_implementation | Gate 4 | root | Sources/WWMDAnalytics/CorrelationAndRules.swift; clear-winner, user-correction override, and deterministic rebuild tests | Typed association projection persistence and native correction view remain unimplemented | Candidate/evidence/score/ambiguity foundation and ledger-derived user correction are implemented. |
| MET-001 | Value | Computable measured/derived/estimated metric catalog and projections | IN_PROGRESS | feature_implementation | Gate 4 | root | MetricCalculator and ProjectionEngine; token/cache/context/thread/correlation formula and sample-floor tests | Price-table metrics and typed metric-window persistence remain unimplemented | Measured/derived availability semantics and explicit data-gap outcomes are implemented. |
| REC-001 | Value | Versioned deterministic recommendations, controls, and audit trail | IN_PROGRESS | feature_implementation | Gate 4 | root | RecommendationEngine: data quality, context pressure, long thread, repeated validation; ledger-derived dismiss/snooze test | Native evidence view and persisted materialized recommendation state remain unimplemented | Versioned deterministic proposals, scope keys, and audit events drive active recommendations. |
| EXP-001 | Value | Privacy-safe NDJSON, CSV-summary, and SQLite backup export | SUCCESS | feature_implementation | Gate 4 | root | TelemetryStore.export/backup; safe-profile, backup, and purge test; swift test -> 34 passed | — | Agent-owned safe NDJSON, CSV summary, consistent SQLite backup, checksummed receipts, and no-overwrite behavior are implemented. |
| UX-001 | Native product | Collection health, pause, summaries, drill-down, and association correction views | IN_PROGRESS | feature_implementation | Gate 5 | root | Sources/WWMDApp/main.swift menu-bar/viewer scaffold; named `wwmd-main` Window and `Open WWMD` action use native `openWindow` | UI is not yet connected to signed agent XPC or real projected summaries | Visible development state/privacy boundary is implemented; the menu-bar action now explicitly opens the main viewer; functional views remain. |
| CLI-001 | Native product | Read-only local query and export CLI | IN_PROGRESS | feature_implementation | Gate 5 | root | NativeXPCClient and `wwmd health/summary/evidence/recommendations` safe JSON commands; no direct DB access; swift test -> 34 passed | Signed service integration and XPC-mediated export are not wired to a production agent | Functional bounded read-only health/summary/evidence/recommendation surface is implemented behind authenticated XPC configuration. |
| PRIV-001 | Privacy | Persistent consent/pause, inclusion/exclusion, retention, redaction, and provenance | IN_PROGRESS | feature_implementation | Gate 5 | root | Core PrivacyGate opaque-metadata/secret tests; Store collection/adapter state and scoped purge; runtime opt-in-before-read/run checks | Repository allowlist/bookmarks, end-to-end deletion UI, and source-adapter consent views are not complete | Persistent global pause, explicit adapter opt-in state, core redaction rejection, provenance, and retention primitive are implemented. |
| DEL-001 | Privacy | Complete local deletion including WAL/SHM/backups/exports selected by user | OPEN | feature_implementation | Gate 5 | root | Planned deletion test | — | — |
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

Working rows: 16 (11 IN_PROGRESS, 5 OPEN)
Terminal rows: 11 (9 SUCCESS, 2 BLOCKED)
Objective complete: no. Foundation/export and bounded XPC query foundations are complete; collection lifecycle, signed runtime proof, functional app views, XPC export, deletion lifecycle, and release proof remain.

## Root single-owner post-implementation consistency review

Reviewed against both supplied briefs on 2026-07-24 after the current code and
documents were written. `PASS` means the current implementation/documentation
matches the requirement; `PARTIAL` identifies a visible, non-terminal ledger
row; `BLOCKED` identifies a missing external contract or release configuration.

| Brief requirement | Result | Reconciliation evidence |
|---|---|---|
| New WWMD identity/database; never read, migrate, or alter predecessor history | PASS | Separate public repository and SQLite schema; README/design/PrivacyGate contain no predecessor migration path. |
| Local-first, offline, single-user, static-code V0; no HTTP/GraphQL/cloud/plugins | PASS | Package target graph, native XPC-only code, and no network dependency/endpoint. |
| App, persistent agent, and read-only CLI with native XPC | PARTIAL | `WWMDAgentRuntime`, `wwmdd`, `wwmd`, and SwiftUI shell exist; production Mach-service/signing and app connection are not configured. |
| SQLite/WAL, one serialized writer, immutable events, atomic migrations/checkpoints, deterministic replay | PASS | `TelemetryStore` actor, WAL settings, v1-to-latest fixture, projection checkpoint, and tests. |
| Exact Codex CSV/live-source mapping only after real source contract | BLOCKED | G0-003/ADP-CODEX-CSV remain blocked; exact-header gate has no inferred mapping. |
| Explicit Git, safe activity, explicit build/test, and typed local annotation adapters | PARTIAL | Git/build/activity/annotation boundaries and opt-in checks exist; bookmarks, user-facing consent, activity source, and scheduler/retry lifecycle remain. |
| Pre-persistence privacy, provenance, sensitivity, no content/title/arguments/log/environment/browser capture | PASS | Closed descriptors, prohibited-field/secret/opaque-ID gate, metadata-only adapters, and regression tests. |
| Persistent global pause and per-adapter opt-in | PARTIAL | Durable store/runtime enforcement and XPC pause control exist; native UI controls are not connected. |
| Evidence-scored correlation, competing candidates, user correction, no causal claims | PARTIAL | Deterministic scoring and ledger-derived correction override exist; typed materialized projection/UI are pending. |
| V0 data-quality, context-pressure, long-thread, and repeated-validation recommendations with controls | PARTIAL | Deterministic, evidence-gated rules plus ledger-derived dismiss/snooze exist; materialized state/evidence UI are pending. |
| Redacted NDJSON/CSV/SQLite backup export; cost only with local effective-dated price source | PARTIAL | Safe exports/backups and receipts exist; XPC CLI export and selected managed paths are pending; cost remains unavailable without a supplied price table. |
| Complete local deletion of DB/WAL/SHM/backups/exports | PARTIAL | Scoped event purge and stopped-agent DB/WAL/SHM helper exist; selected output tracking and end-to-end deletion UX are pending. |
| XPC local-process threat resistance | PARTIAL | Explicit native client/server code-signing requirements and same-user server acceptance exist; Team ID/entitlements/signed cross-process proof are blocked. |
| Crash/disk/clock/sleep/source-rotation recovery and idle/performance targets | PARTIAL | SQLite transactions, integrity check, bounded XPC queries, and baseline unit tests exist; fault-injection and 24-hour/CPU/RSS proof are open. |
| Final acceptance requires terminal ledger rows and objective completion | NOT MET | 16 implementation/release rows remain working; this ledger deliberately does not claim completion. |

Result: no terminology, ownership, process-boundary, schema, trust-boundary, or
V0-scope contradiction was found in the current implementation/design. Missing
work is recorded as `IN_PROGRESS`, `OPEN`, or genuine external `BLOCKED` rather
than being represented as a completed feature.
