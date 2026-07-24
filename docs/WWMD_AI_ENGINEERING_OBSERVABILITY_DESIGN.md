# WWMD: Local-First AI Engineering Observability Design

Status: implementation design frozen for v0
Authoring date: 2026-07-24
Author: root agent
Audience: WWMD maintainers, security reviewers, and the implementation owner
Source reference: Daylily-Informatics/well-whaddya-know origin/main at 61e1991, inspected read-only

## Reconciliation record

This document is the root-owned reconciliation of four independent, read-only
evidence reviews. It defines an independent application named WWMD. It does
not extend, open, migrate, or copy the WWK historical activity database.

| Term | One meaning in this document | Owner | Boundary |
|---|---|---|---|
| WWMD app | Native menu-bar, preferences, and drill-down viewer process. | App process | Calls the agent only through versioned native XPC. |
| WWMD agent | Persistent per-user collector and sole mutable database owner. | Agent process | Hosts the Mach XPC service; never exposes HTTP or a Unix socket. |
| Core | Validation, identity, privacy gate, canonical model, and domain rules. | Core module | Has no source discovery and no UI. |
| Adapter | Opt-in, statically linked in-process source reader. | Agent | May emit only validated, redacted source offers. |
| Ledger | Immutable canonical TelemetryEventV1 rows. | Storage module | The sole source for rebuildable derived state. |
| Projection | Typed table derived from the ledger with a versioned checkpoint. | Projection module | May be discarded and rebuilt; never becomes source truth. |
| Work unit | Local feature, bug, investigation, refactor, review, documentation, maintenance, or uncategorized session. | Correlation module | Associations remain evidence-scored, not causal. |
| Recommendation | Deterministic, versioned rule result. | Recommendation module | Evidence-linked, dismissible, snoozable, non-interruptive by default. |
| Content | Prompts, responses, source text, titles, command arguments, logs, environment values, clipboard, screenshots, and keystrokes. | Privacy gate | Excluded from v0 persistence. |

The v0 scope is one signed macOS user, one local database, four concrete
source families, deterministic projections and rules, and local export. The
word value means measured or explicitly estimated engineering evidence; it
never means employee ranking, causation, or a judgment of a person.

## 1. Title, status, authoring date, and intended audience

This is the implementation-ready architecture for WWMD, a local-first macOS
application that helps one engineer inspect the observable relationship between
AI-assisted activity and engineering work. It is frozen for v0 planning, with
one explicit exception: a Codex CSV field mapping remains blocked until a real
source contract is supplied.

## 2. Executive decision

WWMD will be a Swift-native macOS 13+ menu-bar application with a persistent
per-user agent, a signed read-only CLI, native XPC for control and queries, and
one SQLite database in WAL mode. A single TelemetryStore actor in the agent
serializes every write. It persists immutable, versioned TelemetryEventV1
records; typed projections and recommendation records are rebuilt
deterministically from that ledger.

The v0 adapters are static and opt-in: a schema-gated Codex CSV importer,
metadata-only user-selected Git repositories, safe activity/session metadata,
an explicit build/test wrapper, and user annotations. There are no dynamic
plugins, network listener, cloud upload, background model calls, source
content collection, or window-title capture.

Native XPC replaces WWK's length-framed JSON Unix-domain socket because WWMD
needs an explicit macOS peer identity boundary. SQLite/WAL remains the storage
base because it fits a small local durable ledger better than a second
analytics database or custom log. The principal trade-off is giving up
unbounded source discovery and generic integrations for privacy, testability,
and a smaller failure surface.

## 3. Repository evidence and current WWK architecture

WWMD takes only the sound architectural lessons from WWK. The records below
refer to the read-only source pin, not to the user's dirty local checkout.

| Evidence | Demonstrated source fact | WWMD decision |
|---|---|---|
| Package.swift:1-155 | WWK is a Swift package targeting Swift 6 and macOS 13+, divided into storage, sensor, model, timeline, IPC, reporting, agent, CLI, and menu-bar products. | Keep modular Swift and macOS 13+; use new WWMD module names and no copied source. |
| Sources/WellWhaddyaKnowApp/WellWhaddyaKnowApp.swift and Info.plist:21-24 | WWK is a menu-bar-first LSUIElement app. | Retain a menu-bar-first interaction pattern with a normal viewer rather than a consumer dashboard. |
| Sources/WellWhaddyaKnowAgent/Agent.swift and main.swift | WWK has a separate agent lifecycle. | Keep a persistent agent, but give it exclusive mutation ownership and explicit lifecycle states. |
| Sources/Shared/XPCProtocol/IPCProtocol.swift and Sources/WellWhaddyaKnowAgent/IPCServer.swift | WWK calls its IPC XPC, but implementation is a length-framed JSON Unix socket with file mode 0600. | Do not inherit this trust model; use native Mach XPC and signed-peer validation. |
| Sources/Storage/DatabaseConnection.swift:41-93 | WWK configures SQLite foreign keys, WAL, NORMAL synchronous mode, busy timeout, cache, and mmap. | Reuse the SQLite/WAL pattern only; specify WWMD-owned transactional migrations and serialized writer. |
| Sources/Storage/Schema.swift and SchemaManager.swift | WWK has a v1 schema with raw activity/system/user edit tables and one-at-a-time non-transactional migration behavior. | Replace with a generic immutable envelope plus typed projections and one transaction per migration. |
| Sources/Storage/EventWriter.swift | WWK handles only app/title-oriented deduplication and uses interpolated SQL. | Use prepared statements, source and global idempotency keys, and quarantine. |
| Sources/Timeline | WWK demonstrates pure deterministic replay but has time-only ordering and divergent range-reader semantics. | Preserve pure replay, add total ordering, one query contract, projection checkpoints, and rebuild tests. |
| Sources/Sensors/SessionStateSensor.swift | A session polling seam exists, but inspection found no start call from the agent lifecycle. | Do not rely on latent polling seams; lifecycle ownership and health state must be tested. |
| WWK docs and app privacy assets | Documentation says XPC/privacy coverage in places where source evidence shows UDS and incomplete target coverage. | Treat code and release artifacts as truth; test signed release behavior and privacy paths end to end. |

WWK has no proven Codex, Git, build/test, correlation, metric, or
recommendation adapter. Therefore WWMD is an independent successor rather than
a database migration. Its source reference establishes useful patterns and
anti-patterns, not compatibility obligations.

## 4. Problem statement

Engineers can observe token and cost totals, but those totals do not answer
whether AI activity was associated with a validated engineering outcome, where
the evidence is incomplete, or where an interaction pattern is repeatedly
unproductive. WWMD must make that evidence visible without silently collecting
content or turning a personal local tool into surveillance software.

## 5. Product definition

WWMD is an offline, single-user observability tool for the question:

> What engineering value am I receiving from AI-assisted work?

It correlates selected local metadata sources, persists a privacy-filtered
append-only ledger, calculates deterministic summaries, and presents
evidence-backed recommendations. Token and cost values are inputs, not the
product's organizing principle.

## 6. Goals

1. Persist local, schema-versioned, idempotent telemetry with deterministic recovery.
2. Associate AI and engineering metadata using evidence and explicit uncertainty.
3. Show measured, derived, estimated, and user-supplied values distinctly.
4. Keep collection visible, opt-in, reversible, and content-minimizing.
5. Operate offline with low idle resource use and no busy polling.
6. Give the user high-signal daily, session, repository, work-unit, and data-quality views.
7. Export redacted data through durable non-proprietary formats.
8. Preserve a narrow adapter seam for future proven sources without adopting a plugin runtime.

## 7. Non-goals

V0 does not require cloud services, accounts, multi-user collaboration,
enterprise administration, a marketplace, arbitrary executable plugins,
machine-learning recommendations, embeddings, vector storage, a generalized
workflow engine, GraphQL, Kafka, Kubernetes, Postgres, browser extension,
dozens of adapters, perfect attribution, employee scoring, or a code-content
index.

Claude Code, Cursor, Gemini CLI, Augment, GitHub, Linear, Slack, remote CI,
package-manager, editor, and additional test-framework integrations are later
work. No v0 metric may imply data from those sources.

## 8. Constraints and assumptions

| Constraint or assumption | Design consequence |
|---|---|
| macOS 13+ and Swift 6 source baseline | Use Swift concurrency, SwiftUI/AppKit where appropriate, Apple signing, and native XPC. |
| Local-first, offline, one person | No service account, background uploader, external telemetry, or distributed coordination. |
| No actual Codex CSV contract was supplied | Importer is a hard schema gate; no guessed column names, types, or cost mapping. |
| No stable local live Codex source is proven | Live Codex collection is deferred, not implemented through file discovery or scraping. |
| User must explicitly select repositories | Store a security-scoped bookmark and query only selected roots. No broad filesystem scan or Full Disk Access. |
| Activity metadata is content-adjacent | V0 excludes window titles; idle state is unavailable instead of inferred. |
| Credentials may someday be unavoidable | Use Keychain only for credential value; never in environment capture, logs, exports, or ledger. |
| Performance targets are design targets | Measure idle CPU below 1%, ordinary RSS below 150 MB, queue depth, and responsiveness in release proof. |
| WWK historical data has a different privacy posture | No WWK data is imported or read. User can annotate new work in WWMD instead. |

## 9. Recommended architecture

WWMD has five concrete modules: Core, Storage, Adapters, Analytics, and
Application Interface. The agent hosts Core, Storage, Adapters, and Analytics.
The app and CLI are XPC clients with separate read-only/mutation capability
sets. The agent is the only process able to open the database read-write.

| Alternative | Decision | Reason |
|---|---|---|
| SQLite/WAL ledger plus typed projections | Adopt | Single-file local durability, bounded operational complexity, transactions, indexes, and reproducible rebuilds. |
| SQLite plus opaque JSON only | Reject | Common queries and safe export need typed columns and indexes; opaque payloads would make privacy and migration checks fragile. |
| DuckDB, Parquet, Arrow as primary storage | Reject | Adds another storage/execution model for a small always-running app; Arrow is later interchange only. |
| Custom append-only log | Reject | Reimplements transaction, indexing, corruption, and query machinery without a demonstrated benefit. |
| Native Mach XPC | Adopt | Fits signed macOS peers and process isolation without opening a network listener. |
| WWK Unix-domain JSON socket | Reject | File mode alone does not establish peer identity or stable native object contract. |
| Loopback HTTP or GraphQL | Reject | Adds a network-style attack and compatibility surface without a v0 need. |
| Runtime plug-ins | Reject | Trusted first-party adapters do not justify arbitrary code loading and lifecycle complexity. |
| Dynamic source discovery | Reject | Broad discovery creates privacy surprises; each source is explicitly enabled and configured. |

## 10. Architecture diagram

~~~mermaid
flowchart LR
    U["Single user"] --> APP["WWMD.app: menu bar and viewer"]
    U --> CLI["wwmd CLI: signed read-only query/export"]
    APP <-->|"versioned native XPC"| AGENT["wwmdd agent: sole writer"]
    CLI <-->|"versioned native XPC"| AGENT
    AGENT --> CORE["Core: validation, privacy gate, event identity"]
    AGENT --> ADAPTERS["Static opt-in adapters"]
    ADAPTERS --> CORE
    CORE --> STORE["TelemetryStore actor"]
    STORE --> DB[("WWMD SQLite WAL ledger")]
    STORE --> PROJ["Typed projections and checkpoints"]
    PROJ --> ANALYTICS["Correlation, metrics, rules"]
    ANALYTICS --> STORE
    GIT["Selected Git roots"] --> ADAPTERS
    BUILD["Explicit wrapper"] --> ADAPTERS
    ACTIVITY["Safe app/session metadata"] --> ADAPTERS
    CSV["Codex CSV only after contract"] --> ADAPTERS
    ANNO["User annotations"] --> ADAPTERS
~~~

## 11. Component responsibilities

| Component | Owns | Must not do |
|---|---|---|
| WWMD.app | Consent screens, global pause, health display, summaries, drill-down, corrections, retention/deletion/export initiation. | Open DB for mutation, discover sources, or retain extra content. |
| wwmdd agent | Lifecycle, adapter scheduling, bounded queues, one DB writer, native XPC endpoint, recovery and diagnostics. | Expose HTTP/UDS, infer permissions, or silently substitute sources. |
| Core | Envelope validation, UUID generation, local pseudonymization, provenance, sensitivity, redaction state, idempotency. | Read Git, parse CSV, run shell commands, or render UI. |
| Adapter runtime | Opt-in registration, health state, retry/backoff, checkpoints, queue admission. | Bypass Core validation or persist directly. |
| Codex CSV adapter | Verify exact configured schema, stream rows, normalize contracted fields, source-deduplicate, and checkpoint atomically. | Guess columns, derive unstated price, or inspect live files. |
| Git adapter | Read metadata from one user-selected root and known worktrees. | Read file contents, scan arbitrary roots, or infer identity from titles. |
| Activity adapter | Produce app/session/project metadata when consented. | Capture titles, idle, keys, clipboard, screen, or browser history. |
| Build adapter | Accept category, timing, aggregate status, and optional declared repository/work unit. | Record command arguments, logs, or environment variables. |
| Annotation adapter | Record user labels, corrections, outcomes, dismissal, and snooze actions. | Alter immutable prior events. |
| TelemetryStore actor | Migrations, prepared statements, atomic batches, checkpoints, retention, projections, backup/export staging. | Accept unvalidated payloads or allow concurrent mutable DB access. |
| Projection engine | Deterministically project ledger rows in total sequence order. | Treat a projection as immutable source truth. |
| Correlation/analytics/rules | Associate evidence, calculate formulas, emit versioned summaries/recommendations. | Claim causation or make unsourced judgments. |

## 12. Process and lifecycle model

WWMD.app uses macOS service-management support to register the signed per-user
agent. The app shows whether the agent is running, paused, recovering, or
unavailable. The agent starts with collection disabled until the user enables
each adapter. It opens and migrates the database, verifies its signing and XPC
policy, restores durable settings, replays incomplete projections, then opens
the XPC endpoint. An adapter starts only after consent, configuration, and
source contract validate.

The agent reacts to safe source notifications where available. It otherwise
uses a bounded adaptive interval only for explicitly selected metadata sources;
no 1-second global polling loop is allowed. Sleep, wake, timezone, and clock
changes create diagnostic events and trigger checkpoint-safe reconciliation
instead of synthetic activity.

~~~mermaid
flowchart TD
    A["Launch signed agent"] --> B["Open DB and verify integrity"]
    B --> C{"Migration needed?"}
    C -->|yes| D["Atomic migration or fail closed"]
    C -->|no| E["Restore durable settings"]
    D --> E
    E --> F["Replay incomplete projections"]
    F --> G["Validate XPC signing policy"]
    G --> H["Publish XPC service"]
    H --> I["Start only enabled adapters"]
    I --> J{"Global pause?"}
    J -->|yes| K["Adapters retain health, emit no source reads"]
    J -->|no| L["Bounded ingestion and projection loop"]
    L --> M["Graceful checkpoint on termination"]
~~~

The app may be unavailable while the agent continues collection; the agent
retains a bounded health history and surfaces the last known state on
reconnection. If the agent is unavailable, the app shows unavailable and
offers restart diagnostics; it never writes directly to the database.

## 13. Event-ingestion flow

1. A user enables a named adapter and sees its declared collection fields,
   sensitivity, retention, and permissions.
2. The adapter verifies its explicit source contract. A missing bookmark,
   invalid schema, revoked permission, or unknown source version moves it to
   blocked health with an actionable reason.
3. It reads incrementally under a bounded queue, builds a source offer, and
   redacts/secrets-filters before the offer leaves adapter memory.
4. Core validates field allowlists, schema, measurement class, sensitivity,
   timestamps, and identity keys. Invalid offers become a minimal quarantined
   diagnostic record without content.
5. TelemetryStore writes canonical event rows and adapter checkpoint in one
   SQLite transaction. Only after commit does the adapter acknowledge its
   checkpointable source progress.
6. The projection engine advances from the durable sequence checkpoint. Rules
   run only over completed projection windows and write derived result events.

~~~mermaid
sequenceDiagram
    participant S as Enabled source
    participant A as Static adapter
    participant C as Core privacy/validation
    participant T as TelemetryStore actor
    participant D as SQLite WAL
    participant P as Projection engine
    S->>A: incremental metadata
    A->>A: contract check plus pre-persist redaction
    A->>C: bounded SourceEventOffer
    C->>C: validate, classify, idempotency key
    C->>T: validated TelemetryEventV1 batch
    T->>D: BEGIN events plus checkpoint COMMIT
    D-->>T: durable commit
    T-->>A: persisted acknowledgement
    T->>P: new sequence range
    P->>D: projection transaction plus checkpoint
~~~

No adapter retries a record that the store acknowledged. A retry after
uncertain source acknowledgement is safe because the canonical idempotency
constraint is deterministic.

## 14. Canonical event model

TelemetryEventV1 is the versioned canonical envelope. It uses UUID values
created locally; it does not use external-object syntax or fabricate an
external identity. Its payload is a constrained typed JSON value, not a free
dump of source data.

| Field | Required | Meaning | Provenance and privacy rule |
|---|---:|---|---|
| event_id | yes | Locally generated UUID. | Measured by Core; public identifier within local DB only. |
| schema_name, schema_version | yes | TelemetryEvent and integer version. | Core-supplied; reject unsupported write versions. |
| sequence | yes after persistence | Monotonic SQLite sequence creating total order. | Store-supplied; never adapter supplied. |
| adapter_id, adapter_version | yes | Stable static adapter identity/version. | Adapter/Core allowlist only. |
| source_native_id | conditional | Native row/event identity when source provides it. | Measured; null rather than guessed. |
| source_cursor | conditional | Opaque source checkpoint or row ordinal. | Adapter-supplied/redacted; not exported unless safe. |
| source_idempotency_key | yes | SHA-256 digest over adapter, source identity, and stable source fields. | Core digest; no raw content. |
| event_kind | yes | Closed V1 kind such as ai.turn, git.commit, validation.result. | Adapter/Core allowlist. |
| occurred_at | yes when known | RFC 3339 instant emitted by source. | Measured; null only for diagnostic kinds. |
| observed_at | yes | Instant WWMD observed source record. | Core measured. |
| persisted_at | yes | Instant durable commit began. | Store measured. |
| monotonic_nanos | optional | Local monotonic sampling point for clock diagnostics. | Core measured; not wall-clock time. |
| local_actor_id, local_device_id | yes | Random locally stored pseudonyms. | Core-supplied; no account identity. |
| project_id, repository_id, worktree_id, branch | optional | Stable local metadata references. | Adapter/correlation with per-field provenance. |
| ai_provider, ai_client, model, thread_id, turn_id | optional | AI metadata only when real contracted fields exist. | Measured source field or null; no inferred aliases. |
| work_unit_id and parent_refs | optional | Local evidence association references. | Derived or user-supplied; no copied external object IDs. |
| payload | yes | Closed typed payload by event kind. | Validated allowlist; content fields forbidden in v0. |
| sensitivity | yes | public-metadata, private-metadata, or user-sensitive. | Most restrictive contributing field wins. |
| redaction_state | yes | passed, redacted, rejected, or quarantined. | Core-supplied. |
| provenance | yes | Per-field source, measurement class, transformation trail. | Core-supplied. |
| confidence | optional | 0.0 to 1.0 only for derived/heuristic fields. | Formula or user-confirmed basis required. |

Event ordering is ascending occurred_at when present, then observed_at, then
sequence. Sequence is authoritative whenever clocks disagree. A late arrival
retains its historical occurred_at but projects at ledger sequence; bounded
affected windows are recomputed. Unknown fields are rejected at adapter ingress
in V0 rather than silently retained. Malformed input produces a quarantine
reason code, adapter/version/cursor digest, and counts only; it never persists
the original raw line or content.

Corrections are new immutable annotation events that supersede a derived
association by reference. Source deletion or rotation creates an adapter health
event and leaves previously persisted privacy-filtered records intact until
retention expires. An adapter upgrade requires an explicit source schema
compatibility declaration and a new adapter version; replay stays idempotent.

## 15. Representative event examples

These are shape examples, not a Codex CSV mapping. Any unavailable field is
null or omitted according to the event schema; none is fabricated.

~~~json
{
  "event_id": "1b23d85c-1f17-4d6a-9b5a-12dbbf015aab",
  "schema_name": "TelemetryEvent",
  "schema_version": 1,
  "sequence": 42,
  "adapter_id": "codex.csv",
  "adapter_version": "1",
  "source_native_id": "opaque-row-123",
  "source_idempotency_key": "sha256:8a7c...",
  "event_kind": "ai.turn",
  "occurred_at": "2026-07-24T08:00:00Z",
  "observed_at": "2026-07-24T08:05:00Z",
  "payload": {
    "input_tokens": 1200,
    "cached_input_tokens": 300,
    "output_tokens": 450,
    "reasoning_tokens": 200,
    "model": "only-if-contracted",
    "client": "only-if-contracted"
  },
  "sensitivity": "private-metadata",
  "redaction_state": "passed",
  "provenance": {"payload.input_tokens": "measured:codex.csv"}
}
~~~

~~~json
{
  "event_id": "00e5e850-a775-4dd8-8b09-dc840af038cb",
  "schema_name": "TelemetryEvent",
  "schema_version": 1,
  "sequence": 71,
  "adapter_id": "git.local",
  "adapter_version": "1",
  "event_kind": "git.commit",
  "occurred_at": "2026-07-24T09:20:10Z",
  "payload": {
    "repository_id": "repo:3f7090a0",
    "branch": "main",
    "commit_oid": "2ce0d7d",
    "parent_count": 1,
    "changed_file_count": 4,
    "insertions": 30,
    "deletions": 12
  },
  "sensitivity": "private-metadata",
  "redaction_state": "passed",
  "provenance": {"payload.commit_oid": "measured:git"}
}
~~~

~~~json
{
  "event_id": "8e43c7fc-65fc-4103-ab3c-9f3e7d34e430",
  "schema_name": "TelemetryEvent",
  "schema_version": 1,
  "sequence": 85,
  "adapter_id": "build.wrapper",
  "adapter_version": "1",
  "event_kind": "validation.result",
  "occurred_at": "2026-07-24T09:31:00Z",
  "payload": {
    "category": "test",
    "started_at": "2026-07-24T09:29:32Z",
    "duration_ms": 88000,
    "aggregate_status": "passed",
    "repository_id": "repo:3f7090a0"
  },
  "sensitivity": "private-metadata",
  "redaction_state": "passed",
  "provenance": {"payload.aggregate_status": "measured:build.wrapper"}
}
~~~

~~~json
{
  "event_id": "7dc4d81a-e2db-46dd-8698-d33b1a5b2a1c",
  "schema_name": "TelemetryEvent",
  "schema_version": 1,
  "sequence": 93,
  "adapter_id": "activity.safe",
  "adapter_version": "1",
  "event_kind": "activity.session",
  "occurred_at": "2026-07-24T09:40:00Z",
  "payload": {
    "session_state": "started",
    "application_bundle_id": "com.example.editor",
    "repository_id": "repo:3f7090a0"
  },
  "sensitivity": "private-metadata",
  "redaction_state": "passed",
  "provenance": {"payload.application_bundle_id": "measured:activity.safe"}
}
~~~

~~~json
{
  "event_id": "508f2198-9d93-4481-9aa8-da3bf8e5df17",
  "schema_name": "TelemetryEvent",
  "schema_version": 1,
  "sequence": 101,
  "adapter_id": "annotation.local",
  "adapter_version": "1",
  "event_kind": "work_unit.outcome_declared",
  "occurred_at": "2026-07-24T10:00:00Z",
  "payload": {
    "work_unit_id": "wu:94f77a",
    "kind": "feature",
    "outcome": "completed",
    "repository_id": "repo:3f7090a0"
  },
  "sensitivity": "user-sensitive",
  "redaction_state": "passed",
  "provenance": {"payload.outcome": "user-supplied:annotation.local"}
}
~~~

~~~json
{
  "event_id": "6aa3ea10-bd03-4f94-91e0-c463de1f875b",
  "schema_name": "TelemetryEvent",
  "schema_version": 1,
  "sequence": 110,
  "adapter_id": "recommendation.engine",
  "adapter_version": "1",
  "event_kind": "recommendation.emitted",
  "payload": {
    "rule_id": "data.correlation_gap",
    "rule_version": 1,
    "severity": "info",
    "evidence_grade": "B",
    "work_unit_id": "wu:94f77a",
    "observation_ids": ["metric:correlation_coverage:2026-07-24"]
  },
  "sensitivity": "private-metadata",
  "redaction_state": "passed",
  "provenance": {"payload.rule_id": "derived:recommendation.engine"}
}
~~~

~~~json
{
  "event_id": "b20dd6e6-6920-4dfb-af02-c1fa5afbd946",
  "schema_name": "TelemetryEvent",
  "schema_version": 1,
  "sequence": 112,
  "adapter_id": "annotation.local",
  "adapter_version": "1",
  "event_kind": "recommendation.dismissed",
  "payload": {
    "recommendation_event_id": "6aa3ea10-bd03-4f94-91e0-c463de1f875b",
    "reason_code": "not_useful",
    "snooze_until": null
  },
  "sensitivity": "user-sensitive",
  "redaction_state": "passed",
  "provenance": {"payload.reason_code": "user-supplied:annotation.local"}
}
~~~

## 16. Storage architecture

WWMD stores its database in the signed application's App Group container,
protected by normal macOS per-user access controls and app sandbox
entitlements. The agent opens it read-write; all other process access is XPC
mediated. SQLite is configured with foreign keys enabled, WAL journal mode,
bounded busy timeout, explicit transaction scopes, and a journal-size policy.
The synchronous setting, cache, mmap, and checkpoint threshold are release
configuration values measured under test, not copied blindly from WWK.

Raw canonical events are immutable. Corrections, deletion requests, adapter
state changes, and recommendation actions are new events. Retention removes
expired data only under a transaction and records aggregate deletion receipts,
never a new copy of data being removed.

The initial retention default is 90 days for canonical source events and 365
days for derived aggregate summaries, configurable per collection class. This
is user-visible, not hidden. A shortened interval is applied prospectively and
starts a reviewable purge job. A longer interval requires explicit confirmation.
SQLite incremental vacuum/checkpoint maintenance runs only while idle and
never blocks ingestion.

## 17. Schema, indexes, projections, and migrations

The physical schema is deliberately small:

| Table | Purpose | Key constraints |
|---|---|---|
| schema_migrations | Applied migration ID, checksum, application version, time. | Migration ID primary key; one transaction per migration. |
| telemetry_events | Immutable envelope with constrained payload and typed index columns. | event_id unique; adapter/source idempotency unique; sequence INTEGER PRIMARY KEY. |
| adapter_state | Opt-in, health, source contract version, cursor, retry state, last success/error code. | One row per adapter/configuration scope; no source content. |
| quarantine_receipts | Digest, reason code, adapter/version, count, first/last seen. | No raw line/payload storage. |
| projection_checkpoints | Projection name/version, last sequence, rebuild generation. | One active checkpoint per projection/version. |
| work_units | Typed local work-unit state reconstructed from annotations/correlations. | Local ID, latest state sequence. |
| associations | Candidate and confirmed links with evidence, score, rule version, correction state. | Unique association key/version. |
| metric_windows | Typed measures by window/dimension, coverage, and price table version. | Unique metric/window/dimension/version. |
| recommendations | Current rule result state with cooldown, dismissal/snooze sequence references. | Unique rule/scope/rule-version/open-window. |
| export_receipts | Managed export manifest, filters, redaction profile, checksum, destination label. | No export contents stored. |
| backup_receipts | Managed backup path label/checksum/creation time. | Supports explicit deletion discovery. |

Indexes include event kind plus occurred time, adapter plus cursor, repository
plus occurred time, work unit plus sequence, source idempotency, checkpoint,
active recommendation, and retention expiry. Index additions are separate
migrations with bounded execution documentation.

Each migration contains an ID, checksum, preflight, SQL transaction, postflight
integrity query, and compatible app version range. Failure rolls back before
the agent publishes XPC; no partial migration is exposed. A forward-incompatible
database makes the agent unavailable with a backup-first remediation path. A
projection schema change increments its projection version, creates a new
checkpoint, rebuilds from the immutable ledger, validates row counts/hashes,
then atomically marks the checkpoint active.

~~~mermaid
flowchart LR
    E["Immutable events in sequence order"] --> V["Validation and integrity scan"]
    V --> P1["Repository and session projections"]
    V --> P2["Work-unit and association projections"]
    P1 --> M["Metric windows"]
    P2 --> M
    M --> R["Versioned rule evaluation"]
    R --> RE["Recommendation events and state"]
    CP["Projection checkpoints"] --> P1
    CP --> P2
    CP --> M
    CP --> R
    E -->|"rebuild after change"| V
~~~

Database open validates SQLite quick_check and foreign-key consistency. A
corrupt database is preserved read-only. A managed backup is attempted only if
the source is readable, then the user can rebuild a new database from an
independently verified ledger backup. If no valid ledger exists, WWMD reports
loss honestly; it cannot invent repair.

## 18. Adapter contract

Adapters conform to one static internal contract:

~~~text
AdapterDescriptor: id, version, collection description, field allowlist,
  sensitivity ceiling, configuration schema, source contract versions.
AdapterRun: validateConfiguration -> acquireIncrementalBatch(cursor, limit)
  -> redactAndNormalize -> offer(events, nextCursor) -> acknowledge(commit).
AdapterHealth: disabled, blocked, starting, healthy, paused, degraded,
  incompatible, failed; reason code, retry time, and last durable sequence.
~~~

Every batch is bounded by record count, byte count, and wall-clock budget. The
agent owns queue admission and cancellation. An adapter retries transient
errors with capped exponential backoff and jitter; permission, schema,
integrity, and privacy-policy failures are non-retryable until configuration
changes. An adapter crash marks only that adapter degraded and cannot take down
the store or other adapters.

The Codex CSV adapter is intentionally incomplete in V0: it accepts a
user-selected file only after the exact header list, types, source identifier
rule, timestamp semantics, and allowed fields are versioned in configuration.
It streams with a durable byte/row checkpoint and import fingerprint, commits
records and checkpoint atomically, and rolls back an incomplete batch. Without
that contract it reports blocked; it never offers generic CSV mode.

The Git adapter accepts a user-selected repository bookmark and reads only Git
metadata required by documented event kinds: repository identity, worktree path
digest, branch, commit ancestry, commit identifiers, change counts, and
repository lifecycle state. It does not read tracked file content. The build
adapter is a command wrapper explicitly invoked by the user or configured tool;
it records category, start/end, duration, aggregate exit state, and declared
repository/work unit, never arguments, logs, or environment variables.
Activity collection uses safe app/session metadata only and records explicit
unavailable when it cannot determine an attribute safely.

## 19. Correlation and outcome-attribution model

The correlation engine produces a collection of candidates, never an
unexplained single truth. V0 work units originate from user annotations,
explicit build-wrapper declarations, selected repository/worktree/branch
metadata, or a deterministic session boundary. Allowed kinds are feature, bug,
investigation, refactor, review, documentation, maintenance, and uncategorized
session.

For every association, WWMD stores matching rule version, evidence atoms,
score, confidence grade, competing candidates, automatic/user-confirmed state,
and any later correction. Scores are a reproducible weighted evidence sum, not
a learned model:

~~~text
score = 0.40 repository or worktree exact match
      + 0.25 branch exact match
      + 0.20 declared work-unit or source-native ID match
      + 0.10 bounded temporal overlap
      + 0.05 commit or validation adjacency
~~~

Missing evidence contributes zero, not an inferred match. A candidate becomes
automatic only at score at least 0.70 and at least 0.20 above the next
candidate. Scores 0.40 through 0.69 remain ambiguous; below 0.40 no
association is created. A user correction emits a higher-priority immutable
annotation and disables automatic replacement for that relation. Displayed
confidence also reflects data coverage, so a high matching score cannot
overstate a sparse source window.

~~~mermaid
flowchart TD
    A["AI turn metadata"] --> E["Evidence atoms"]
    G["Git/worktree/branch metadata"] --> E
    B["Build/test result"] --> E
    U["User annotation or correction"] --> E
    E --> C["Candidate work units"]
    C --> S["Versioned deterministic score"]
    S --> D{"Clear winner?"}
    D -->|yes| L["Automatic association with evidence"]
    D -->|no| Q["Ambiguous candidates or no association"]
    U -->|"overrides"| L
    U -->|"overrides"| Q
~~~

Local-only outcomes can measure commits, local passing validation, user-declared
completion, and time to first locally observed passing validation. Merged
branch, pull request, closed issue, deployment, and business impact require
later GitHub, issue-tracker, CI, or user-supplied evidence. WWMD labels them
unavailable in V0 rather than estimating them.

## 20. Metric catalog

Every metric record has a canonical name, metric version, time window,
dimensions, source event IDs/counts, coverage, formula, measurement class,
missing-data behavior, uncertainty, and recommendation eligibility. It updates
after relevant projection batches, subject to a one-minute coalescing window;
daily/week views use closed calendar windows in the user's current timezone.
Cost records additionally contain the local price-table version and effective
date.

| Metric | Exact formula and class | Dimensions / minimum evidence | Missing data, uncertainty, failure modes | Recommendation eligible |
|---|---|---|---|---|
| ai.turn.count | measured count(ai.turn) | provider, client, model, repo, branch, thread, work unit; source turn ID when available | unavailable without contracted AI events; duplicate keys excluded | data-quality only |
| ai.input_tokens | measured sum(input_tokens) | same plus measured token field | null if absent; never derive from prompt length | no |
| ai.cached_input_tokens | measured sum(cached_input_tokens) | contracted field | null if absent | cache rule if coverage passes |
| ai.uncached_input_tokens | derived input_tokens minus cached_input_tokens | provider/model/window; both values measured | null if either absent; negative value is source error | cache rule |
| ai.output_tokens | measured sum(output_tokens) | contracted field | unavailable if absent | context descriptive |
| ai.reasoning_tokens | measured sum(reasoning_tokens) | token/setting field | unavailable if absent | only comparable cohorts |
| ai.cost | estimated sum of measured token category times locally imported effective price | provider/model/price table/date | unavailable without both price and tokens; stale table flagged | price-quality/comparison only |
| ai.latency_ms | measured source latency, or observed completion minus start only when semantics contract | model/client/thread | unavailable for ambiguous timestamps | descriptive |
| ai.reasoning_setting.distribution | measured grouped count(setting) | real setting field | unavailable if absent | no universal judgment |
| ai.cache_read_ratio | derived cached_input_tokens / input_tokens | provider/model/window; at least 20 measured turns | null denominator/insufficient sample | poor-cache rule |
| ai.context_utilization | measured directly, or derived context_tokens / contracted context_window | thread/model; exact window field | unavailable if window unknown; derived marked | context-pressure rule |
| ai.thread_lifetime | derived last occurred_at minus first occurred_at | durable thread ID | unavailable without real thread ID | long-thread rule |
| ai.context_growth_rate | derived slope(context utilization by ordered turn) | thread/model; at least 5 ordered turns | unavailable if ordering/coverage missing | context-pressure rule |
| workflow.active_engineering_time | measured sum(explicit safe activity session intervals) | repo/session | unavailable rather than inferred from app gaps | descriptive |
| workflow.ai_wait_time | measured/derived only from contracted request timing and declared waiting state | thread/session | unavailable otherwise | no |
| workflow.human_idle_time | unavailable in V0 | none | v0 does not collect or infer idle | no |
| workflow.context_switch_count | measured count(explicit repo/app/session transition) | session/repo | excludes title/idle inference | data-quality/descriptive |
| workflow.repository_switch_count | measured count(repository changed) | session | unavailable without safe repo association | descriptive |
| validation.build_frequency | measured count(validation.result category=build) | repo/work unit/window | wrapper coverage displayed | descriptive |
| validation.build_duration_ms | measured median/sum(duration_ms) | repo/work unit/category | null if duration absent | repeated-failure rule |
| validation.test_frequency and duration | measured equivalent for category=test | repo/work unit/window | wrapper coverage displayed | descriptive |
| validation.failure_rate | derived failed / completed validation results | repo/work unit/category; at least 5 results | incomplete coverage/null below sample floor | repeated-failure rule |
| outcome.time_to_first_pass | derived first passing validation after associated AI event minus AI event time | repo/work unit | ambiguity lowers grade; no causal language | descriptive |
| workflow.repeated_tool_activity | measured count of identical safe tool metadata fingerprint when provided without content | thread/repo | unavailable absent a contracted non-content fingerprint | deferred/data quality |
| workflow.prompt_duplication | unavailable in V0 | none | prompts/fingerprints are not retained | no |
| outcome.cost_per_work_unit | estimated ai.cost / user-confirmed completed work units | kind/repo | null without confirmed outcome and price coverage | descriptive only |
| outcome.cost_per_commit | estimated ai.cost / associated commits | repo/branch/window | ambiguous links lower grade | descriptive only |
| outcome.cost_per_merged_branch, cost_per_pr, cost_per_closed_issue | unavailable in V0 | none | needs GitHub/issue evidence | no |
| outcome.time_to_completed | derived user-declared completion minus work-unit start | work unit | null without declaration; not a productivity rank | descriptive |
| outcome.ai_associated_session_ratio | derived eligible sessions with evidence-linked AI turn / eligible sessions | repo/window | coverage always shown | descriptive |
| outcome.throughput_trend | derived rolling delta(user-confirmed outcomes) | kind/window; at least 8 comparable windows | null below sample floor | no |
| efficiency.high_reasoning_low_output | heuristic rate(high setting and output below user's cohort percentile) | model/task proxy; 30 comparable events | unavailable without actual setting/sample | cautious prompt only |
| efficiency.model_effectiveness | heuristic comparison of cost/latency and validation evidence on comparable user-defined cohorts | model/repo/kind; 30 per cohort | confounding warning; no causal claim | cautious comparison |
| efficiency.estimated_avoidable_inference | estimated excess versus user-selected baseline counterfactual | model/window | not shown without baseline/coverage; range, not fact | no automatic action |
| efficiency.estimated_latency_or_cost_reduction | estimated observed median difference times eligible count | model/window | assumptions and confidence shown | explanation only |
| efficiency.return_on_inference | estimated user-confirmed outcome evidence divided by cost; no dollar value assigned to outcome | work unit/window | unavailable without complete evidence | descriptive only |

Lines of code are not a primary productivity or value metric. If a later
diagnostic shows diff size, it carries a warning that changed lines do not
measure value, quality, or individual performance.

## 21. Recommendation engine

WWMD V0 evaluates deterministic rules after a projection window closes. Every
result carries stable rule_id, rule_version, title, required metric versions,
trigger, observation window, sample size, evidence grade, severity,
explanation, supporting observation IDs, estimate method when applicable,
cooldown, deduplication key, dismissal/snooze state, and data-quality gate.
Rules never emit a result when their required metric reports unavailable,
insufficient coverage, or ambiguous price/source semantics.

| Rule ID | Trigger and evidence floor | User-facing wording and controls | False-positive controls |
|---|---|---|---|
| data.correlation_gap | Fewer than 70% of eligible AI/validation events have repository or work-unit evidence over 7 days; at least 20 events. | “Outcome correlation is incomplete for this scope; add a work unit or enable a selected repository.” Dismiss or snooze. | No fault language; does not infer a missing repo. |
| ai.context_pressure | At least 3 of 5 ordered turns in a real thread have utilization at or above the user's 90th percentile and above 75%; at least 20 historic turns. | “This thread is near your high-context range; consider a fresh thread if the task has changed.” | Requires direct/defensible utilization, cohort, and thread ID. |
| ai.long_lived_thread | Thread lifetime exceeds user's 95th percentile and 6 hours, with at least 20 historic threads. | “This unusually long-lived thread may be easier to navigate if split by task.” | No quality or cost claim. |
| ai.topic_transition | Source offers non-content metadata that explicitly identifies repository/worktree change within a durable thread. | “The linked repository changed in this thread; review association or start a new thread.” | Deferred until metadata is contracted; no title/prompt inference. |
| ai.high_reasoning_low_output | 30 comparable events show setting high/max with output below user cohort 25th percentile and no observed validation advantage. | “For this comparable local cohort, high reasoning had no observed validation advantage.” | Comparability/sample floor required; no universal advice. |
| workflow.repeated_safe_activity | Contracted safe metadata fingerprint repeats above a user-calibrated percentile. | “Repeated metadata-only activity was observed; inspect the evidence before changing workflow.” | Disabled without a content-free contract. |
| ai.poor_cache_reuse | Cache ratio below user's 10th percentile, below 0.10, at least 20 measured turns. | “Cache reuse is low in this evidence window.” | Requires measured cached and input tokens. |
| validation.repeated_failure_after_ai | Three failed validations associated with same work unit after AI activity before a later pass, within 2 hours. | “Three validations failed before success in this work unit; inspect linked outcomes.” | Association grade B or higher; never says AI caused failure. |
| ai.expensive_without_advantage | 30 comparable events per model and price coverage; higher-cost model has no measurable local validation advantage within confidence bounds. | “A lower-cost model had similar observed local validation evidence in this cohort.” | User defines cohorts; costs are estimates; no automatic model change. |
| repo.missing_instructions_or_index | User explicitly records repository instruction/index status and correlation gap persists. | “This repository has weak correlation metadata; consider durable local instructions or an index.” | No filesystem content scan; disabled until declared metadata exists. |
| data.telemetry_gap | Adapter health shows a gap, schema rejection, stale price table, or source coverage below rule requirements. | “A data gap limits conclusions for this period.” | Always emitted before dependent advice; transparency has priority. |

Rule thresholds are configuration data with rule versions, activation dates, and
calibration basis. Changing a threshold creates a new rule version and
re-evaluates only from its activation date unless the user explicitly requests
historical replay under the new version. Recommendations appear in the menu-bar
summary and daily/session-end review, never as default interruptive
notifications. A dismissal holds the deduplication key for 30 days; a snooze
holds it until the user-supplied date; neither changes historic evidence.

~~~mermaid
flowchart LR
    P["Closed projection window"] --> Q["Metric availability and coverage gate"]
    Q -->|insufficient| DQ["Data-quality recommendation only"]
    Q -->|sufficient| R["Versioned deterministic rule"]
    R --> C["Cooldown and deduplication"]
    C --> E["Recommendation emitted with evidence"]
    E --> U["User: open, dismiss, snooze, correct"]
    U --> A["Immutable annotation event"]
    A --> P
~~~

## 22. IPC and query interfaces

The primary internal interface is a versioned native NSXPCConnection to an
agent-hosted Mach service. Native XPC is appropriate because it has macOS
lifecycle and connection semantics rather than WWK's manual socket framing.
The agent sets an explicit native NSXPCListener connection code-signing
requirement before activation, and the client sets the expected agent
requirement before activation. The system rejects unsigned, differently signed,
or mismatched clients before the delegate accepts the connection; the delegate
also requires the same effective macOS user. The requirement must encode the
release Team ID, expected WWMD identifier, and required entitlement. A
development build uses a separately explicit development requirement; it does
not silently relax to any local process.

The trust boundary is app/CLI to agent. The agent applies authorization after
peer validation: Query and Export capabilities are read-only; Control enables
pause/adapter configuration only after user interaction in the app; Destructive
Delete requires an XPC challenge generated by the app with explicit scope.
There is no open socket, HTTP listener, direct database write API, or remote
caller.

| Interface | Capability | Request shape | Response and limits |
|---|---|---|---|
| GetHealthV1 | query | API version | Agent/app/adapters, pause, database/projection state; no raw event payload. |
| QuerySummaryV1 | query | time range, dimensions, metric names, pagination cursor | Typed summary page; 500 rows/2 MiB maximum; cancellation token. |
| QueryEvidenceV1 | query | event/recommendation/work-unit IDs, time/repository/work-unit filter | Redacted typed evidence page; 200 rows/1 MiB maximum. |
| QueryRecommendationsV1 | query | active/all state, time/scope filter, cursor | Typed rule results and evidence references. |
| SetCollectionStateV1 | control | global pause or named adapter state, explicit configuration revision | Durable state receipt; no inferred configuration. |
| ApplyAnnotationV1 | control | typed annotation/correction/dismiss/snooze | Immutable event receipt and resulting projection generation. |
| StartExportV1 | export | format, filters, redaction profile, user-selected destination bookmark | Managed export receipt; cancellation and size cap. |
| RequestDeletionV1 | destructive control | precise data classes, time range, managed outputs inclusion, confirmation nonce | Preview first, then explicit receipt; no wildcard default. |

Every request contains client_api_version and a UUID request_id. Incompatible
major versions fail explicitly; minor versions add optional response fields
only. Query cursors are opaque signed sequence/query snapshots, expire after
10 minutes, and bind to the original filter. Agent work is cooperative
cancellable. Full-range queries have a fixed time range, 30-second CPU budget,
and page boundary; the client cannot request arbitrary SQL.

The signed CLI implements only QuerySummaryV1, QueryEvidenceV1, and
StartExportV1. It never opens the live database directly. If its release
signing requirement cannot be proven, it reports unavailable rather than
falling back to file access.

## 23. Export and interoperability

WWMD's canonical model remains its compact ledger because engineering work
metadata does not always map truthfully to spans. It documents standards
mapping without claiming conformance where semantics do not fit.

| Format or standard | Fit | V0 decision |
|---|---|---|
| JSON Lines | Strong for event/export replay and inspection. | Redacted NDJSON export with envelope schema/version and manifest. |
| CSV | Strong for flat summary/metric tables. | Summary-only CSV; not canonical events and not a generic source importer. |
| SQLite backup | Strong for local recovery and exact query. | Managed consistent backup through SQLite backup API, checksum, manifest. |
| OpenTelemetry Logs | Partial fit for event time, severity, body, attributes, resource. | Documented mapping; no automatic OTLP network exporter. |
| OpenTelemetry Metrics | Partial fit for numeric metric windows/dimensions. | Documented mapping; no canonical OTel store. |
| OpenTelemetry Traces/spans | Weak for long-lived, ambiguous, non-causal work association. | Do not force work units into traces; optional future export only. |
| OpenTelemetry resource attributes | Good for local app/device/adapter version after pseudonymization. | WWMD resource mapping with no user/account name. |
| Semantic conventions | Useful where existing keys fit; insufficient for AI-work provenance/correlation. | Reuse stable matching keys; prefix unavoidable fields wwmd.*. |
| OpenMetrics/Prometheus | Useful aggregate snapshots, poor primary personal ledger. | Future read-only file exporter; no scrape endpoint by default. |
| Arrow | Possible bulk interchange. | Not included until a real consumer needs it. |

An NDJSON export writes a manifest first with filters, schema versions,
redaction profile, time range, source coverage, generated time, and checksum
algorithm. CSV summary exports include formula, unit, evidence grade, and price
table version. A SQLite backup is a consistent snapshot with a manifest.
Export defaults to redacted safe fields; user-sensitive annotations require an
explicit inclusion toggle. Export happens only to a user-selected destination
bookmark. WWMD tracks managed output receipts but cannot erase copies a user
moves outside its managed destination; deletion UI states that limit clearly.

## 24. WWMD user experience

WWMD retains WWK's menu-bar-first posture: a compact state summary opens a
native viewer, with drill-down rather than a flashy separate dashboard. The
menu bar always exposes global pause. It never hides active collection behind
an icon-only state.

~~~text
Menu bar
  [Paused | 2 sources healthy | 1 data gap]
  Today: measured AI turns, validations, evidence grade
  Current session: selected repository, association confidence, no content
  Recommendations: evidence-backed items
  Collection health: adapter status and last durable event
  Pause all / Resume all
  Open WWMD / Export / Privacy and retention / Quit

Viewer navigation
  Today | Current Session | Week | Repositories | Work Units | Threads
  Recommendations | Data Quality | Privacy | Export and Deletion
~~~

| View | Minimum information and interaction |
|---|---|
| Current collection state | Per-adapter opt-in, permission, fields, health, queue, last event, source contract version, and no-data reason. |
| Global pause | Persistent state, exact stopped adapters, last durable sequence, and explicit resume. |
| Today and week | Measured/derived/estimated cards, coverage badge, short formula link, never a token-only dashboard. |
| Current session | Selected repo/work unit, safe activity state, associations/uncertainty, validation outcome. |
| Repository and branch | Event/validation summaries, work-unit associations, data gaps, retention scope. |
| AI thread | Only actual metadata: timing, token/cost measures, context metric, association candidates; no prompt/response text. |
| Work unit | User kind/outcome, candidate evidence, correction control, local outcome limits. |
| Recommendation | Rule version, trigger, evidence table, estimate assumptions, dismissal/snooze/correction. |
| Data quality | Missing adapters/fields, source gaps, stale prices, coverage, blocked metrics. |
| Privacy and retention | Exact collection contract, redaction/secret filtering status, inclusion/exclusion, retention preview. |
| Export and deletion | Redaction profile, scope preview, managed output receipts, complete deletion preview/confirmation. |

Association correction is one action: choose candidate, choose no association,
or declare/create a work unit. The app explains that correction improves local
interpretation, not a score about the user. Every chart/table value exposes
formula, evidence count, and provenance labels.

## 25. Privacy model

Privacy is enforced before persistence. Each adapter descriptor declares its
allowlist and sensitivity ceiling; Core rejects undeclared fields. Redaction
removes keys matching configured secret patterns before serialization and
rejects payloads whose field names are content-like or prohibited. Default
patterns cover common credential names and high-entropy token shapes; this is
defense in depth, never permission to collect text first.

| Collection category | V0 policy |
|---|---|
| Prompts, responses, source contents, window titles, shell arguments, logs, environment values | Never collect or persist. |
| Keylogging, clipboard, screen recording/screenshots, browser history | Never request permission or collect. |
| Active application | Optional safe bundle identifier only, clearly disclosed. |
| Repository/project | Optional, explicit user-selected bookmark and local pseudonym/digest where display does not require name. |
| Git metadata | Optional, allowlisted metadata only; no tracked-file content. |
| Build/test | Explicit wrapper metadata, not command/log/environment. |
| AI metadata | Exact permitted/exported schema fields only; no live source discovery. |
| User annotations | Optional user-sensitive values with clear retention/export toggle. |

Every adapter has an opt-in toggle, collection description, required
permissions, field list, retention class, health, and pause behavior. Global
pause persists and stops new source reads/ingestion; it does not erase existing
data or pretend a gap never occurred. Project/repository inclusion and
exclusion are explicit allowlists; an excluded root fails closed.

Credentials are avoided in V0. If a future contracted source requires one, its
credential is stored in Keychain under a dedicated access group and referenced
by a non-secret identifier; it is never stored in database, config, diagnostic
bundle, CLI output, process arguments, or environment.

## 26. Security and threat model

WWMD has one local-user trust model, not a claim that any process running as
that same user is harmless. The critical boundaries are: selected source file
to adapter; selected Git root to adapter; app/CLI to agent; agent to database;
and agent to export destination. Existing WWK evidence establishes why a file
permission-only Unix socket is inadequate; WWMD's controls below are design
requirements to be implemented and release-tested.

~~~mermaid
flowchart TD
    U["User"] --> A["WWMD app"]
    U --> C["Signed CLI"]
    A --> X["Signed XPC agent"]
    C --> X
    F["Selected CSV or Git metadata"] --> X
    X --> D["Local SQLite ledger"]
    X --> E["Selected export destination"]
    M["Other local process"] --> X
    M --> F
~~~

| Asset | Objective | Principal threat and required protection |
|---|---|---|
| Telemetry metadata and annotations | Confidentiality/integrity | Prevent content capture, use app sandbox/App Group permissions, redacted diagnostics/exports, and validate every adapter field. |
| Ledger/projections | Integrity/availability | Sole writer actor, SQLite transactions, integrity checks, backups, provenance, and signed XPC mutation boundary. |
| Source checkpoints | Integrity | Commit atomically with records; never acknowledge before commit; bind cursor to adapter/version/config. |
| XPC control plane | Integrity/confidentiality | Set explicit native listener/client code-signing requirements before activation, require same effective user, and validate typed request/capability schema. |
| Bookmarks and export receipts | Confidentiality/integrity | Security-scoped bookmark storage; never broad path discovery; display destination and deletion boundary. |
| Future credentials | Confidentiality | Keychain only; never serialize, log, export, or pass through command environment. |
| Availability/performance | Availability | Bounded queue, parser limits, rate/batch budgets, disk reserve, cancellation, and adapter isolation. |

| Threat | Likelihood / impact | Required mitigation and detection |
|---|---|---|
| TM-001 local process impersonates app/CLI to inject or read telemetry | medium / high | Native XPC connection code-signing requirement, same-user delegate check, typed capability allowlist, version checks; log redacted rejection reason/count. |
| TM-002 malicious or malformed CSV causes parser crash, memory exhaustion, or event injection | medium / medium | User-selected bookmark only, exact header/type contract, maximum file/row/field/batch limits, streaming parser, pre-persist schema validation and quarantine; fuzz fixtures and health counters. |
| TM-003 untrusted repository path/symlink broadens read scope | medium / high | Resolve and validate security-scoped bookmark, enforce canonical path under selected root, reject symlink escapes and moved roots; log only path digest/reason. |
| TM-004 source metadata contains a secret or content field | medium / high | Descriptor field allowlist and sensitivity ceiling, pre-persist secret/content filter, reject unrecognized fields, privacy tests with seeded secret shapes; count redaction/rejection only. |
| TM-005 local process tampers with database or managed export | medium / medium | Sandbox/App Group permissions, exclusive writer, checksum/manifest, SQLite integrity check, backup verification; show integrity warning and never silently repair altered data. |
| TM-006 hostile client drives expensive queries or delete paths | low / medium | Signed peer requirement, fixed query schema/page/CPU limits, cancellation, deletion preview/nonce/explicit scope; record rate-limit and rejected-delete receipts. |
| TM-007 adapter bug causes data exfiltration or code execution | low / high | No dynamic plugins, static reviewed adapters, no outbound network code in v0, least permissions and adapter isolation; release binary/supply-chain review. |
| TM-008 diagnostic bundle or export leaks user-sensitive values | medium / high | Separate redaction profiles, default-safe export, explicit annotation inclusion, test fixture secret scan, manifest coverage labels; receipt records profile but not data. |
| TM-009 package/signing substitution weakens client verification | low / high | Release signing, pinned designated requirement, notarization/release proof, fail-closed signed CLI/agent handshake; verify requirement in integration tests. |
| TM-010 disk pressure/intentional event flood degrades machine | medium / medium | Per-adapter queue/byte limits, event-size cap, disk reserve and paused-ingestion state, incremental purge; emit health state and retain no unbounded retry buffer. |

Assumptions affecting the ranking are that WWMD remains local-only, contains no
remote listener, is one user's signed app/agent/CLI set, and no third-party
binary adapter exists. Any team sync, network export, arbitrary extension, or
shared database would require a new threat-model review before implementation.

## 27. Performance and capacity analysis

The goals are under 1% idle CPU and under 150 MB ordinary-operation RSS. They
are acceptance measurements, not present claims. WWMD avoids timer-driven
full scans, processes source batches on a background priority, serializes
writes in one actor, and coalesces projection/rule work. The app queries
precomputed typed summaries, not unbounded event history, for its first paint.

| Budget | Design control | Release measurement |
|---|---|---|
| Idle CPU | No busy polling; notification-first adapters; adaptive bounded reads only when enabled. | 24-hour Instruments/sample receipt with all v0 adapters in ordinary use. |
| RSS | Cap in-memory source queue at 1,000 offers or 8 MiB, whichever comes first; streamed CSV and paged queries. | Peak and median RSS under normal and malformed input fixtures. |
| Write latency | 100-event or 250 ms batch target, one transaction including checkpoint. | p50/p95 durable acknowledgement latency and lock contention. |
| UI latency | Summary projection query only; page evidence lazily. | First-open and filter-change timings in release build. |
| Disk | Retention, checkpoint/vacuum schedule, size caps, early disk-reserve pause. | Database/WAL growth and disk-pressure fault test. |

Planning storage estimate uses D = event_count_per_day times average
persisted_bytes times index_multiplier. At a conservative planning input of
1,000 metadata events/day, 1.5 KiB average payload/envelope, and 1.7 index/WAL
multiplier, steady data is about 2.5 MiB/day, 75 MiB/month, and 0.9 GiB/year
before retention. This is a model, not an observed workload; release proof
must record actual event size distributions and use the user's retention
configuration. A source with unexpectedly large fields is rejected by cap
rather than changing the estimate silently.

## 28. Reliability and crash recovery

The durability invariant is: an event is acknowledged to an adapter only after
the canonical event row and its source checkpoint commit in the same SQLite
transaction. A crash before commit produces no acknowledgement and safe
replay; a crash after commit can replay but unique idempotency keys prevent
duplicates. Projection checkpoints are committed only after their typed output
rows, so a crash either leaves a projection at an earlier durable sequence or
at a complete one.

At startup, the store runs integrity checks, recovers WAL as SQLite directs,
validates migration status, and resumes each projection from its checkpoint.
Safe shutdown first stops admission, cancels/awaits adapters under a deadline,
drains committed offers, flushes an explicit WAL checkpoint when allowed, and
records an agent lifecycle receipt. Forced termination has the same
transactional recovery properties.

Clock change and sleep/wake do not create false duration claims. Events retain
source/observation time and optional monotonic marker; duration calculations
that cross a detected time discontinuity are marked uncertain or unavailable.
Timezone/DST affects display-window grouping, not stored instants. Repository
renames, moved worktrees, rebase, force push, and source rotation are lifecycle
events with stable local identity/provenance; old history is never rewritten.

## 29. Failure-mode analysis

| Failure mode | Detection and containment | User behavior / recovery / loss | Test strategy |
|---|---|---|---|
| Adapter crash | Task supervisor records degraded adapter; other adapters/store remain alive. | Health shows last durable sequence; capped backoff restart; unacknowledged events replay. | Fault-injected throw/crash in each adapter. |
| Malformed source event | Schema/type/size/redaction gate rejects and writes quarantine receipt only. | Adapter health shows count/reason; no raw record retained. | Parser/property fuzz plus negative fixtures. |
| Duplicate import | Unique source/global idempotency key. | Duplicate is acknowledged as already durable; no extra projection. | Same batch/reordered batch replay. |
| Partial CSV import | Batch plus cursor transaction; import fingerprint. | Resume at last durable checkpoint, or explicit restart after contract review. | Kill between batches and compare ledger hash. |
| Source log rotation | Adapter cursor identity mismatch. | Creates source-rotation health event; safely rescans only within explicit source contract. | Fixture rotation and truncation. |
| Incompatible source format | Header/version contract mismatch. | Blocked, clear required contract; no generic fallback. | Unknown header/type tests. |
| Missing/revoked permission | Bookmark/security scope/access error. | Blocked, user reauthorizes or disables; no retry storm. | Revoked bookmark fixture/integration check. |
| Database lock contention | Bounded SQLite busy timeout and sole writer design. | Agent queues within cap, then pauses affected ingestion with health notice. | Contending read/lock fault test. |
| Agent crash during transaction | SQLite rollback/WAL recovery. | No ack before commit; replay safe. | Forced process termination around write phases. |
| Projection failure | Checkpoint remains prior sequence; projection marked failed. | Raw ledger safe; app shows stale summary and repair/rebuild action. | Throw after output before checkpoint and rebuild. |
| Disk full | Disk reserve preflight and SQLite write error classification. | Stop source acknowledgement, pause collection, preserve existing DB; user frees space/resumes. | Mount/fault injected ENOSPC. |
| Database corruption | quick_check/integrity failure. | Preserve broken copy, offer verified backup/rebuild; report irrecoverable loss if none. | Byte corruption fixture and backup restore. |
| System clock change | Compare monotonic/observed time discontinuity. | Mark duration/window uncertainty; no event reorder rewrite. | Forward/backward clock simulation. |
| Sleep/wake | OS lifecycle and elapsed discontinuity. | Resume source checkpoint reads; marked gap if source cannot reconcile. | Suspend/resume integration test. |
| Timezone/DST change | Timezone monitor/display conversion check. | Stored UTC remains; recompute local calendar projections. | DST boundary fixtures. |
| Repository rename/move | Bookmark identity/path validation and Git metadata. | Record lifecycle event; requires reauthorization if scope no longer valid. | Move/rename worktree fixture. |
| Worktree create/delete | Git worktree metadata delta. | Add/remove selected scoped worktree; no file scan. | Worktree lifecycle fixtures. |
| Rebase/force push | Commit ancestry/non-fast-forward metadata. | Record lifecycle; no historic mutation or causal inference. | Rebase/force-push fixture graph. |
| User deletes source telemetry | Adapter detects missing source/cursor. | Persisted ledger remains until retention; health states source unavailable. | Delete source during cursor test. |
| Stale pricing data | Effective-date expiry/value validation. | Cost marked stale/unavailable; data-quality recommendation. | Expired/overlap price table tests. |
| Provider model rename | Contracted model vocabulary/version mismatch. | Preserve raw permitted value, mark comparison unavailable until mapping approved. | Unknown-model fixture. |
| Recommendation regression | Versioned rule fixtures and result diff. | Disable affected rule version; retain old evidence with version label. | Golden tests across rule versions. |
| Excessive event volume | Queue/byte/record caps and rate counters. | Backpressure/pause health; no silent drop after ack. | Flood test with bounded memory assertion. |
| UI unavailable, agent healthy | XPC reconnect/health snapshot. | Menu app reports reconnect; agent continues safely. | Kill/relaunch app integration test. |
| Agent unavailable, UI healthy | XPC interruption handler. | UI disables mutation/query and shows last state; never direct DB fallback. | Kill/relaunch agent integration test. |

## 30. Testing strategy

The test suite uses deterministic fixtures and temporary isolated databases.
No test fixture contains user prompt, response, source-file, command, or
credential content. Every source contract fixture is synthetic and clearly
labeled. Test classes are:

| Area | Required proof |
|---|---|
| Canonical model | Required/forbidden field validation, source/provenance class, sensitivity, version compatibility, total ordering. |
| Adapters | Descriptor allowlist, opt-in state, contract compatibility, bounded batches, checkpoint acknowledgement, health/backoff. |
| Parsers | Fixture replay, malformed row rejection, fuzz/property input, source rotation, partial CSV resumption. |
| Deduplication | Same/reordered/replayed batch yields identical ledger/projection hashes. |
| Storage/migrations | Transaction rollback, compatibility ranges, checksum failure, WAL recovery, integrity check, backup restore. |
| Projection | Full rebuild equals incremental projection, checkpoint crash and replay, late event affected-window rebuild. |
| Correlation | Evidence atoms, candidate ordering, ambiguity threshold, correction priority, no-causation labels. |
| Metrics | Formula unit tests, null/missing behavior, sample floors, price effective date, evidence grade. |
| Recommendations | Golden fixtures by rule version, cooldown/dismiss/snooze, data-quality gates, threshold activation date. |
| Privacy | Prohibited field rejection, secret-pattern redaction, safe export profile, annotation export toggle, deletion receipts. |
| XPC/security | Signed-peer requirement in release integration environment, malformed request rejection, capability boundary, query caps. |
| Recovery | Crash at each transaction phase, disk pressure, permission revocation, clock/DST/sleep/wake, DB corruption. |
| Export | NDJSON manifest/round-trip validation, CSV formula metadata, SQLite backup checksum, re-import only where source contract permits. |
| Performance | Queue memory cap, write/query p95, idle CPU/RSS measurements, 24-hour release-build soak. |

Compatibility tests retain one fixture per supported historical WWMD schema
version and verify that migrations either produce the same expected projection
or fail explicitly when a version is unsupported. WWK schema/database fixtures
are intentionally not compatibility inputs.

## 31. Operational diagnostics

WWMD is observable without collecting sensitive content. The agent emits
structured local records with timestamp, subsystem, event ID or digest,
adapter ID/version, health transition, error code, sequence range, queue depth,
duration bucket, database/projection generation, and redaction outcome.
Messages never interpolate titles, prompts, source lines, command arguments,
environment, token values, raw JSON, or credentials.

Internal health metrics include adapter state/last durable sequence, ingestion
accepted/rejected/quarantined counts, batch latency buckets, queue depth,
deduplication count, migration/projection generation, replay lag, DB size/WAL
size/free-space class, export/backup receipt count, price-table age, and rule
coverage. These are local only; they are not sent to an external collector.

The user can create a diagnostic bundle containing app/agent version, signing
verification result, sanitized configuration shape, health timeline, schema and
migration IDs, projection checkpoints, integrity result, and redacted logs.
The preview lists every included field. The bundle excludes ledger payloads,
bookmarks, source paths, user annotations by default, secrets, and managed
exports. It is written only after the user selects a destination.

## 32. Compatibility and migration from current WWK

There is no data migration from WWK. WWMD uses a new application identity,
App Group container, database filename, preferences domain, agent service
name, and export manifest schema. It neither opens nor scans the WWK database,
does not read its historical activity/window-title data, and does not reuse its
Unix socket.

The intentional compatibility boundary is conceptual: WWMD reuses the
appropriate Swift modularity, menu-bar posture, separate agent idea, SQLite/WAL
durability lesson, and deterministic projection idea. It replaces source
capture, IPC trust, write serialization, migration, idempotency, lifecycle,
and deletion gaps that are unsuitable for the new privacy and observability
requirements.

## 33. V0 boundary

V0 is the smallest complete vertical slice:

| Included | Explicitly excluded/deferred |
|---|---|
| New local WWMD ledger, migrations, projections, health, retention, backup/export. | WWK database migration, WWK window-title read, remote service, account, cloud analytics. |
| Signed agent/app/CLI architecture and no network listener. | Direct live DB access by CLI/app, HTTP/GraphQL, generic socket API. |
| User-selected Git metadata adapter, annotation/correction adapter, build/test wrapper, safe activity metadata if permissions prove safe. | Filesystem content indexing, broad discovery, idle inference, window titles, browser metadata. |
| Contract-gated historical Codex CSV import implementation only after real schema exists. | Generic CSV importer and any live Codex discovery/scraping. |
| Deterministic association, metric windows, coverage grading, data-quality/context/long-thread/repeated-validation rules when source fields exist. | ML rules, embeddings, causal attribution, universal behavioral recommendations. |
| Menu-bar summary, native drill-down, clear privacy/retention/export/deletion UI. | Team dashboards, employee analytics, notifications by default. |
| Redacted NDJSON, CSV summary, SQLite backup. | OTLP shipping, Prometheus scrape server, Arrow. |

An adapter or metric is unavailable rather than approximated when its required
source contract or field is absent. This is intentional product behavior.

## 34. V1 boundary

V1 may add proven local AI-client adapters, GitHub-equivalent outcome evidence,
issue-tracker evidence, stronger explicit build/test adapters, optional
standards-compliant read-only metric file export, richer work-unit correlation,
and user-calibrated rules. Each addition must first declare collection fields,
privacy/retention, source version, idempotency, trust boundaries, metric
availability changes, and migration/rebuild effects. V1 does not imply a
plugin marketplace or cloud service.

## 35. V2 boundary

V2 may consider explicit-consent team aggregation, cross-device support, more
sophisticated attribution, optional local statistical/ML models, and an
extension SDK only after multiple real adapters prove a stable API. These
possibilities require separate consent, security, identity, encryption,
retention, and threat-model decisions. They must not distort the V0 local
single-user architecture.

## 36. Rejected alternatives and trade-offs

| Rejected alternative | Why it is rejected | Trade-off accepted by WWMD |
|---|---|---|
| Inherit WWK's activity/window-title database | It has a different privacy model and lacks canonical source/provenance/idempotency contracts. | No historical continuity; users start a new privacy-safe ledger. |
| Preserve WWK Unix socket IPC | It lacks a sufficient peer identity story for an agent that accepts mutations. | Higher initial macOS signing/XPC test effort. |
| Direct multi-process SQLite writes | Makes lock/retry/order semantics ambiguous and complicates crash recovery. | Agent is a required local process for mutations. |
| Store all source rows/raw JSON | Retains unknown content and makes privacy/rebuild/schema safety weaker. | Some provider-specific data is unavailable by design. |
| Infer activity from titles, idle, filesystem, browser, or screen state | It creates covert/content-adjacent collection and unreliable analytics. | Certain workflow metrics stay unavailable in V0. |
| Generic CSV or live-source discovery | It would guess contracts and expand access without user knowledge. | Codex import stays blocked until source truth exists. |
| Cloud/OTLP collector or Prometheus endpoint | Contradicts offline privacy posture and expands attack surface. | Interoperability is file export/documented mapping first. |
| ML recommendation engine | Lacks explainability and needs more data/content than V0 can safely retain. | Rules are narrower but reproducible and user-calibrated. |
| Dynamic executable plugin system | Adds arbitrary-code, compatibility, lifecycle, and permission surface before need is proven. | New adapters require a source change/review. |
| Cost-per-line productivity dashboard | Lines do not measure engineering value and invites ranking. | Cost is shown only with observable outcome evidence and caveats. |

## 37. Risks and mitigations

| Risk | Consequence | Mitigation and decision gate |
|---|---|---|
| Codex CSV remains absent or ambiguous | V0 cannot calculate AI-token/cost/context metrics from Codex. | Keep adapter and dependent rules blocked; do not manufacture a mapping. |
| XPC signing validation is difficult in development/release packaging | Agent control plane could be misconfigured. | Fail closed, test a signed release artifact, and do not call SEC-001 complete without proof. |
| Activity API requires broader permission than safe metadata supports | Privacy posture could drift. | Omit or keep adapter disabled; no Full Disk Access shortcut. |
| User annotations may contain sensitive text | Local data/export risk. | Classify user-sensitive, short retention option, redacted default exports, deletion preview. |
| Local metadata does not prove value/causality | Misleading advice. | Evidence grades, explicit unavailable states, user correction, non-causal wording, minimum samples. |
| SQLite file is corrupted or disk fills | Data loss/collection interruption. | Integrity checks, managed backup, reserve/pause, repair/rebuild path, fault tests. |
| Repository move/rebase produces false continuity | Incorrect association/history. | Stable metadata plus lifecycle events; no rewrite; display ambiguity. |
| Projection/rule version drift changes history silently | Inconsistent conclusions. | Version all rules/projections, checkpoint/rebuild, activation dates, golden tests. |
| Scope expands into integrations/plugins before core is reliable | Privacy and delivery risk. | Ledger gate and V0 exclusion; require a new design decision before expansion. |

## 38. Open questions requiring product decisions

1. What exact header, types, time semantics, stable ID rule, and licensing
   provenance does the requested Codex CSV have? This is the sole blocker for
   ADP-CODEX-CSV and all source-dependent Codex metrics.
2. Is there a stable, documented, user-authorized local Codex Desktop or CLI
   source that can be read without scraping, broad file access, or content
   collection? Until proven, the live adapter is not a V0 item.
3. Which safe activity signals are actually available under minimal macOS
   permission and acceptable to the user? The default remains bundle ID/session
   state only; title and idle capture are excluded.
4. Who provides and approves manually imported local price tables, and what
   expiry period should mark a cost estimate stale?
5. What installation/distribution channel supplies the production Team ID,
   App Group, Mach service entitlement, notarization, and signing requirement
   used by SEC-001? A development-only build cannot prove production XPC trust.
6. Should managed exports/backups be stored only inside the App Group unless a
   user explicitly chooses another destination, or should a user-selected
   external default be supported?

## 39. Design decisions frozen for implementation planning

1. WWMD is a new local application identity and ledger; no WWK database or
   historical activity migration exists.
2. Swift/macOS 13+, menu-bar app, persistent per-user agent, signed read-only
   CLI, and a versioned native XPC Mach service are the process topology.
3. TelemetryStore actor in the agent is the only mutable database writer.
4. SQLite/WAL immutable TelemetryEventV1 ledger plus typed projections and
   transactional checkpoints is the only V0 storage system.
5. One exact source contract per static adapter; no runtime plugin, discovery,
   generic CSV reader, HTTP listener, or GraphQL.
6. Collection is opt-in; global pause is durable; pre-persistence redaction,
   secret filtering, provenance, retention, export, and deletion are core
   contracts.
7. V0 excludes window titles, source/prompt/response text, arguments, logs,
   environment, clipboard, screenshots, keystrokes, browser history, idle
   inference, cloud upload, and background LLM analytics.
8. Correlation is deterministic evidence scoring with candidates, confidence,
   ambiguity, and user correction; it never claims causation.
9. Recommendations are deterministic, versioned, coverage-gated, local,
   non-interruptive by default, and calibrated to the user's data.
10. Codex CSV remains explicitly blocked until actual schema evidence is
    supplied; no fallback source or inferred mapping is allowed.

## 40. Acceptance criteria

The V0 release is not accepted until all of the following are proven with
source, test, and release-build evidence:

1. Every accepted event passes schema, provenance, sensitivity, forbidden-field,
   and idempotency validation before persistence.
2. All agent writes, source checkpoints, migrations, and projection checkpoints
   are atomic and recover correctly across forced crash tests.
3. The app/CLI cannot mutate the database directly and untrusted/signed-wrong
   XPC peers are rejected.
4. Each enabled adapter visibly states its fields, permission, scope, health,
   pause behavior, source version, and data quality.
5. No prohibited content class is persisted, logged, exported by default, or
   accepted in diagnostics; negative privacy tests pass.
6. Every derived metric/recommendation exposes formula, input coverage, version,
   evidence, uncertainty, and missing-data state.
7. Every association has candidates/evidence/confidence or explicit
   user-confirmed correction; no UI uses causal language.
8. Retention, scoped deletion, managed-backup/export deletion, and safe export
   manifests work end to end, with stated limits for user-moved copies.
9. CSV import fails closed without the actual contract and resumes idempotently
   after an interrupted contracted import.
10. The release build completes recovery, fault, signed-XPC, 24-hour soak, idle
    CPU/RSS, database-growth, and documentation proof; targets are reported as
    measured values rather than promised numbers.

## 41. One-page implementation-planning handoff

**Build target.** Deliver one privacy-safe local vertical slice: user enables
one safe source, the agent validates/redacts an event, atomically writes it
with a checkpoint, projections produce a typed summary, the app/CLI reads it
through authenticated XPC, and the user can inspect provenance/export/delete
scope. This has value even while Codex input remains blocked.

**Non-negotiable boundaries.** One writer actor; native signed XPC; no direct
DB client writes; immutable ledger; static opt-in adapters; no content;
explicit unavailable states; deterministic correlation/rules; no network; new
WWMD database only.

**Dependency truth.** ADP-CODEX-CSV is blocked on an actual CSV contract.
Live Codex collection is deferred on absence of a proven stable local source.
Cost stays unavailable without a versioned local price table. Production XPC
trust stays unproven until release signing/distribution configuration exists.

**Required evidence.** Implementation planning must retain the control ledger,
map every code change to one frozen decision, add focused tests first for
privacy/durability/idempotency, and terminalize rows only with command/test or
release evidence. A blocked data contract is a correct terminal state, not a
reason to invent fallback behavior.

**Reference standards.** Native XPC semantics: https://developer.apple.com/documentation/foundation/nsxpcconnection
SQLite WAL: https://www.sqlite.org/wal.html
OpenTelemetry log model: https://opentelemetry.io/docs/specs/otel/logs/data-model/
OpenTelemetry metric model: https://opentelemetry.io/docs/specs/otel/metrics/data-model/
OpenTelemetry semantic conventions: https://opentelemetry.io/docs/concepts/semantic-conventions/
OpenMetrics: https://prometheus.io/docs/specs/om/open_metrics_spec/

## Root consistency review result

The root reviewed all 41 sections against the supplied brief and the control
ledger. Terminology, component ownership, process boundaries, schemas, trust
boundaries, and V0 scope are consistent: the agent alone writes, native XPC is
the sole control/query path, the ledger is immutable, projections are
rebuildable, adapters are opt-in/static/pre-persistence-redacted, and Codex
data remains blocked rather than inferred. No section makes V0 depend on
window titles, WWK data, content capture, a cloud service, plugins, a network
listener, or machine learning. Metrics and rules that require absent data are
explicitly unavailable or deferred. The remaining open questions are product
or release-configuration decisions, not hidden architecture contradictions.
