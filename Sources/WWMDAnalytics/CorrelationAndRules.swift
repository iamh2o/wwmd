import Foundation
import WWMDCore

public enum WorkUnitKind: String, Codable, CaseIterable, Sendable {
    case feature
    case bug
    case investigation
    case refactor
    case review
    case documentation
    case maintenance
    case uncategorized
}

public struct WorkUnit: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: WorkUnitKind
    public let repositoryID: String?
    public let worktreeID: String?
    public let branch: String?
    public let startedAt: Date
    public let endedAt: Date?
    public let userConfirmed: Bool

    public init(
        id: String,
        kind: WorkUnitKind,
        repositoryID: String? = nil,
        worktreeID: String? = nil,
        branch: String? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        userConfirmed: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.repositoryID = repositoryID
        self.worktreeID = worktreeID
        self.branch = branch
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.userConfirmed = userConfirmed
    }
}

public enum AssociationState: String, Codable, Sendable {
    case automatic
    case ambiguous
    case unassociated
    case userConfirmed = "user_confirmed"
}

public struct AssociationCandidate: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let eventID: UUID
    public let workUnitID: String
    public let score: Double
    public let evidence: [String]
    public let ruleVersion: Int

    public init(eventID: UUID, workUnitID: String, score: Double, evidence: [String], ruleVersion: Int = 1) {
        self.id = "\(eventID.uuidString):\(workUnitID):v\(ruleVersion)"
        self.eventID = eventID
        self.workUnitID = workUnitID
        self.score = score
        self.evidence = evidence
        self.ruleVersion = ruleVersion
    }
}

public struct AssociationResolution: Codable, Equatable, Sendable {
    public let state: AssociationState
    public let selected: AssociationCandidate?
    public let candidates: [AssociationCandidate]

    public init(state: AssociationState, selected: AssociationCandidate?, candidates: [AssociationCandidate]) {
        self.state = state
        self.selected = selected
        self.candidates = candidates
    }
}

public enum CorrelationEngine {
    public static let ruleVersion = 1

    public static func resolve(event: TelemetryEvent, workUnits: [WorkUnit]) -> AssociationResolution {
        let candidates = workUnits.compactMap { candidate(event: event, workUnit: $0) }
            .sorted {
                if $0.score == $1.score {
                    return $0.workUnitID < $1.workUnitID
                }
                return $0.score > $1.score
            }

        guard let best = candidates.first else {
            return AssociationResolution(state: .unassociated, selected: nil, candidates: [])
        }
        let nextScore = candidates.dropFirst().first?.score ?? 0
        if best.score >= 0.70 && best.score - nextScore >= 0.20 {
            return AssociationResolution(state: .automatic, selected: best, candidates: candidates)
        }
        return AssociationResolution(state: .ambiguous, selected: nil, candidates: candidates)
    }

    private static func candidate(event: TelemetryEvent, workUnit: WorkUnit) -> AssociationCandidate? {
        var score = 0.0
        var evidence: [String] = []

        let repositoryMatches = event.repositoryID != nil && event.repositoryID == workUnit.repositoryID
        let worktreeMatches = event.worktreeID != nil && event.worktreeID == workUnit.worktreeID
        if repositoryMatches || worktreeMatches {
            score += 0.40
            if repositoryMatches {
                evidence.append("repository_exact")
            }
            if worktreeMatches {
                evidence.append("worktree_exact")
            }
        }
        if let eventBranch = event.branch, eventBranch == workUnit.branch {
            score += 0.25
            evidence.append("branch_exact")
        }
        if let declared = event.workUnitID, declared == workUnit.id {
            score += 0.20
            evidence.append("declared_work_unit")
        }
        if overlaps(event: event, workUnit: workUnit) {
            score += 0.10
            evidence.append("temporal_overlap")
        }
        if event.kind == .gitCommit || event.kind == .validationResult {
            if repositoryMatches {
                score += 0.05
                evidence.append("commit_or_validation_adjacency")
            }
        }

        guard score >= 0.40 else { return nil }
        return AssociationCandidate(
            eventID: event.eventID,
            workUnitID: workUnit.id,
            score: min(score, 1.0),
            evidence: evidence,
            ruleVersion: ruleVersion
        )
    }

    private static func overlaps(event: TelemetryEvent, workUnit: WorkUnit) -> Bool {
        guard let occurredAt = event.occurredAt else { return false }
        let end = workUnit.endedAt ?? Date.distantFuture
        return occurredAt >= workUnit.startedAt && occurredAt <= end
    }
}

public enum MetricAvailability: String, Codable, Sendable {
    case available
    case insufficientEvidence = "insufficient_evidence"
    case unavailable
}

public struct MetricValue: Codable, Equatable, Sendable {
    public let name: String
    public let value: Double?
    public let unit: String
    public let evidenceCount: Int
    public let availability: MetricAvailability
    public let explanation: String

    public init(
        name: String,
        value: Double?,
        unit: String,
        evidenceCount: Int,
        availability: MetricAvailability,
        explanation: String
    ) {
        self.name = name
        self.value = value
        self.unit = unit
        self.evidenceCount = evidenceCount
        self.availability = availability
        self.explanation = explanation
    }
}

public enum MetricCalculator {
    public static func aiTurnCount(events: [TelemetryEvent]) -> MetricValue {
        let count = events.filter { $0.kind == .aiTurn }.count
        return MetricValue(
            name: "ai.turn.count",
            value: Double(count),
            unit: "turn",
            evidenceCount: count,
            availability: .available,
            explanation: "Measured count of canonical ai.turn events."
        )
    }

    public static func tokenSum(events: [TelemetryEvent], key: String, metricName: String) -> MetricValue {
        let values = events
            .filter { $0.kind == .aiTurn }
            .compactMap { number(named: key, in: $0.payload) }
        guard !values.isEmpty else {
            return unavailable(metricName, unit: "token", explanation: "The contracted token field is absent.")
        }
        return MetricValue(
            name: metricName,
            value: values.reduce(0, +),
            unit: "token",
            evidenceCount: values.count,
            availability: .available,
            explanation: "Measured sum of \(key) from canonical ai.turn events."
        )
    }

    public static func cacheReadRatio(events: [TelemetryEvent]) -> MetricValue {
        let pairs = events
            .filter { $0.kind == .aiTurn }
            .compactMap { event -> (Double, Double)? in
                guard
                    let input = number(named: "input_tokens", in: event.payload),
                    let cached = number(named: "cached_input_tokens", in: event.payload),
                    input > 0
                else {
                    return nil
                }
                return (input, cached)
            }
        guard pairs.count >= 20 else {
            return MetricValue(
                name: "ai.cache_read_ratio",
                value: nil,
                unit: "ratio",
                evidenceCount: pairs.count,
                availability: .insufficientEvidence,
                explanation: "Requires at least 20 turns with measured input and cached-input tokens."
            )
        }
        let inputs = pairs.reduce(0) { $0 + $1.0 }
        let cached = pairs.reduce(0) { $0 + $1.1 }
        return MetricValue(
            name: "ai.cache_read_ratio",
            value: cached / inputs,
            unit: "ratio",
            evidenceCount: pairs.count,
            availability: .available,
            explanation: "Measured cached-input tokens divided by measured input tokens."
        )
    }

    public static func validationFailureRate(events: [TelemetryEvent]) -> MetricValue {
        let states = events
            .filter { $0.kind == .validationResult }
            .compactMap { string(named: "aggregate_status", in: $0.payload) }
        guard states.count >= 5 else {
            return MetricValue(
                name: "validation.failure_rate",
                value: nil,
                unit: "ratio",
                evidenceCount: states.count,
                availability: .insufficientEvidence,
                explanation: "Requires at least five completed explicit validation results."
            )
        }
        let failed = states.filter { $0 == "failed" }.count
        return MetricValue(
            name: "validation.failure_rate",
            value: Double(failed) / Double(states.count),
            unit: "ratio",
            evidenceCount: states.count,
            availability: .available,
            explanation: "Failed explicit validation results divided by completed explicit validation results."
        )
    }

    public static func correlationCoverage(events: [TelemetryEvent], associatedEventIDs: Set<UUID>) -> MetricValue {
        let eligible = events.filter { $0.kind == .aiTurn || $0.kind == .validationResult }
        guard eligible.count >= 20 else {
            return MetricValue(
                name: "data.correlation_coverage",
                value: nil,
                unit: "ratio",
                evidenceCount: eligible.count,
                availability: .insufficientEvidence,
                explanation: "Requires at least 20 eligible AI or validation events."
            )
        }
        let covered = eligible.filter { associatedEventIDs.contains($0.eventID) || $0.workUnitID != nil }.count
        return MetricValue(
            name: "data.correlation_coverage",
            value: Double(covered) / Double(eligible.count),
            unit: "ratio",
            evidenceCount: eligible.count,
            availability: .available,
            explanation: "Eligible events with an evidence association divided by eligible events."
        )
    }

    public static func contextUtilizationMean(events: [TelemetryEvent]) -> MetricValue {
        let values = events
            .filter { $0.kind == .aiTurn }
            .compactMap { number(named: "context_utilization", in: $0.payload) }
            .filter { (0.0...1.0).contains($0) }
        guard values.count >= 10 else {
            return MetricValue(
                name: "ai.context_utilization.mean",
                value: nil,
                unit: "ratio",
                evidenceCount: values.count,
                availability: .insufficientEvidence,
                explanation: "Requires at least ten directly measured context-utilization values."
            )
        }
        return MetricValue(
            name: "ai.context_utilization.mean",
            value: values.reduce(0, +) / Double(values.count),
            unit: "ratio",
            evidenceCount: values.count,
            availability: .available,
            explanation: "Arithmetic mean of directly measured context utilization across AI turns."
        )
    }

    public static func longestThreadTurnCount(events: [TelemetryEvent]) -> MetricValue {
        let counts = Dictionary(grouping: events.filter { $0.kind == .aiTurn && $0.threadID != nil }) {
            $0.threadID ?? ""
        }.mapValues(\.count)
        guard counts.count >= 5, let longest = counts.values.max() else {
            return MetricValue(
                name: "ai.longest_thread_turns",
                value: nil,
                unit: "turn",
                evidenceCount: counts.count,
                availability: .insufficientEvidence,
                explanation: "Requires at least five threads with opaque thread identifiers."
            )
        }
        return MetricValue(
            name: "ai.longest_thread_turns",
            value: Double(longest),
            unit: "turn",
            evidenceCount: counts.count,
            availability: .available,
            explanation: "Largest measured AI-turn count among observed threads."
        )
    }

    private static func unavailable(_ name: String, unit: String, explanation: String) -> MetricValue {
        MetricValue(
            name: name,
            value: nil,
            unit: unit,
            evidenceCount: 0,
            availability: .unavailable,
            explanation: explanation
        )
    }

    private static func number(named key: String, in payload: [String: JSONValue]) -> Double? {
        guard case .number(let value) = payload[key] else { return nil }
        return value
    }

    private static func string(named key: String, in payload: [String: JSONValue]) -> String? {
        guard case .string(let value) = payload[key] else { return nil }
        return value
    }
}

public enum RecommendationSeverity: String, Codable, Sendable {
    case info
    case attention
}

public struct RecommendationProposal: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let ruleID: String
    public let ruleVersion: Int
    public let scopeKey: String
    public let severity: RecommendationSeverity
    public let evidenceGrade: String
    public let title: String
    public let explanation: String
    public let observationMetricNames: [String]

    public init(
        ruleID: String,
        ruleVersion: Int,
        scopeKey: String,
        severity: RecommendationSeverity,
        evidenceGrade: String,
        title: String,
        explanation: String,
        observationMetricNames: [String]
    ) {
        self.id = "\(ruleID):v\(ruleVersion):\(scopeKey)"
        self.ruleID = ruleID
        self.ruleVersion = ruleVersion
        self.scopeKey = scopeKey
        self.severity = severity
        self.evidenceGrade = evidenceGrade
        self.title = title
        self.explanation = explanation
        self.observationMetricNames = observationMetricNames
    }
}

public enum RecommendationEngine {
    public static let ruleVersion = 1

    public static func dataQualityGap(coverage: MetricValue) -> RecommendationProposal? {
        guard coverage.availability == .available, let value = coverage.value, value < 0.70 else {
            return nil
        }
        return RecommendationProposal(
            ruleID: "data.correlation_gap",
            ruleVersion: ruleVersion,
            scopeKey: "global",
            severity: .info,
            evidenceGrade: value >= 0.50 ? "B" : "C",
            title: "Outcome correlation is incomplete",
            explanation: "Only \(Int((value * 100).rounded()))% of eligible local events have repository or work-unit evidence.",
            observationMetricNames: [coverage.name]
        )
    }

    public static func repeatedValidationFailure(
        events: [TelemetryEvent],
        workUnitID: String
    ) -> RecommendationProposal? {
        let scoped = events.filter { $0.workUnitID == workUnitID }
        let validationStates = scoped
            .filter { $0.kind == .validationResult }
            .compactMap { event -> String? in
                guard case .string(let status) = event.payload["aggregate_status"] else { return nil }
                return status
            }
        guard validationStates.filter({ $0 == "failed" }).count >= 3,
              validationStates.contains("passed"),
              scoped.contains(where: { $0.kind == .aiTurn })
        else {
            return nil
        }
        return RecommendationProposal(
            ruleID: "validation.repeated_failure_after_ai",
            ruleVersion: ruleVersion,
            scopeKey: workUnitID,
            severity: .attention,
            evidenceGrade: "B",
            title: "Repeated validation failures in this work unit",
            explanation: "Three or more validations failed before a passing local result. This is an association, not a causal claim.",
            observationMetricNames: ["validation.failure_rate"]
        )
    }

    public static func sustainedContextPressure(contextUtilization: MetricValue) -> RecommendationProposal? {
        guard contextUtilization.availability == .available,
              let value = contextUtilization.value,
              value >= 0.80
        else {
            return nil
        }
        return RecommendationProposal(
            ruleID: "ai.sustained_context_pressure",
            ruleVersion: ruleVersion,
            scopeKey: "global",
            severity: .info,
            evidenceGrade: contextUtilization.evidenceCount >= 20 ? "B" : "C",
            title: "Context utilization is persistently high",
            explanation: "The mean directly measured context utilization is \(Int((value * 100).rounded()))% across \(contextUtilization.evidenceCount) AI turns. This is a capacity signal, not a quality or causal claim.",
            observationMetricNames: [contextUtilization.name]
        )
    }

    public static func unusuallyLongThread(events: [TelemetryEvent]) -> RecommendationProposal? {
        let counts = Dictionary(grouping: events.filter { $0.kind == .aiTurn && $0.threadID != nil }) {
            $0.threadID ?? ""
        }.mapValues(\.count)
        guard counts.count >= 5 else { return nil }
        let orderedCounts = counts.values.sorted()
        let median = Double(orderedCounts[orderedCounts.count / 2])
        guard let longest = counts.max(by: { $0.value < $1.value }),
              longest.value >= 20,
              Double(longest.value) >= median * 2
        else {
            return nil
        }
        return RecommendationProposal(
            ruleID: "ai.unusually_long_thread",
            ruleVersion: ruleVersion,
            scopeKey: longest.key,
            severity: .info,
            evidenceGrade: counts.count >= 10 ? "B" : "C",
            title: "One AI thread is unusually long",
            explanation: "This thread has \(longest.value) measured turns, at least twice the median \(Int(median)) turns across \(counts.count) observed threads. This is a review cue, not a quality or causal claim.",
            observationMetricNames: ["ai.longest_thread_turns"]
        )
    }

    public static func active(
        proposals: [RecommendationProposal],
        controlEvents: [TelemetryEvent],
        at date: Date = Date()
    ) -> [RecommendationProposal] {
        var latestDisposition: [String: (kind: String, snoozeUntil: Date?)] = [:]
        let formatter = ISO8601DateFormatter()
        for event in controlEvents.sorted(by: { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt {
                return (lhs.occurredAt ?? lhs.observedAt) < (rhs.occurredAt ?? rhs.observedAt)
            }
            return (lhs.sequence ?? 0) < (rhs.sequence ?? 0)
        }) where event.kind == .recommendationDismissed {
            guard case .string(let recommendationID) = event.payload["recommendation_id"],
                  case .string(let disposition) = event.payload["disposition"]
            else {
                continue
            }
            let snoozeUntil: Date?
            if case .string(let rawSnooze) = event.payload["snooze_until"] {
                snoozeUntil = formatter.date(from: rawSnooze)
            } else {
                snoozeUntil = nil
            }
            latestDisposition[recommendationID] = (disposition, snoozeUntil)
        }
        return proposals.filter { proposal in
            guard let disposition = latestDisposition[proposal.id] else {
                return true
            }
            switch disposition.kind {
            case "dismissed":
                return false
            case "snoozed":
                return disposition.snoozeUntil.map { $0 <= date } ?? false
            default:
                return true
            }
        }
    }
}

public struct ProjectedAssociation: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let resolution: AssociationResolution

    public init(eventID: UUID, resolution: AssociationResolution) {
        self.id = eventID
        self.resolution = resolution
    }
}

public struct ProjectionSnapshot: Codable, Equatable, Sendable {
    public let projectionName: String
    public let projectionVersion: Int
    public let processedThroughSequence: Int64
    public let associations: [ProjectedAssociation]
    public let metrics: [MetricValue]
    public let recommendations: [RecommendationProposal]

    public init(
        projectionName: String,
        projectionVersion: Int,
        processedThroughSequence: Int64,
        associations: [ProjectedAssociation],
        metrics: [MetricValue],
        recommendations: [RecommendationProposal]
    ) {
        self.projectionName = projectionName
        self.projectionVersion = projectionVersion
        self.processedThroughSequence = processedThroughSequence
        self.associations = associations
        self.metrics = metrics
        self.recommendations = recommendations
    }
}

public enum ProjectionEngine {
    public static let projectionName = "v0.summary"
    public static let projectionVersion = 1

    public static func rebuild(events: [TelemetryEvent], workUnits: [WorkUnit]) -> ProjectionSnapshot {
        let orderedEvents = events.sorted(by: orderedBefore)
        let automaticAssociations = orderedEvents.map { event in
            ProjectedAssociation(eventID: event.eventID, resolution: CorrelationEngine.resolve(event: event, workUnits: workUnits))
        }
        let projectedAssociations = applyUserCorrections(
            automaticAssociations: automaticAssociations,
            controlEvents: orderedEvents
        )
        let associatedIDs = Set(
            projectedAssociations.compactMap { association in
                association.resolution.selected?.eventID
            }
        )
        let metrics = [
            MetricCalculator.aiTurnCount(events: orderedEvents),
            MetricCalculator.tokenSum(events: orderedEvents, key: "input_tokens", metricName: "ai.input_tokens"),
            MetricCalculator.tokenSum(events: orderedEvents, key: "cached_input_tokens", metricName: "ai.cached_input_tokens"),
            MetricCalculator.tokenSum(events: orderedEvents, key: "output_tokens", metricName: "ai.output_tokens"),
            MetricCalculator.tokenSum(events: orderedEvents, key: "reasoning_tokens", metricName: "ai.reasoning_tokens"),
            MetricCalculator.cacheReadRatio(events: orderedEvents),
            MetricCalculator.validationFailureRate(events: orderedEvents),
            MetricCalculator.correlationCoverage(events: orderedEvents, associatedEventIDs: associatedIDs),
            MetricCalculator.contextUtilizationMean(events: orderedEvents),
            MetricCalculator.longestThreadTurnCount(events: orderedEvents)
        ]
        let coverage = metrics.first { $0.name == "data.correlation_coverage" }
        let contextUtilization = metrics.first { $0.name == "ai.context_utilization.mean" }
        var recommendations = coverage.flatMap(RecommendationEngine.dataQualityGap).map { [$0] } ?? []
        if let contextUtilization,
           let recommendation = RecommendationEngine.sustainedContextPressure(contextUtilization: contextUtilization) {
            recommendations.append(recommendation)
        }
        if let recommendation = RecommendationEngine.unusuallyLongThread(events: orderedEvents) {
            recommendations.append(recommendation)
        }
        let workUnitIDs = Set(workUnits.map(\.id)).union(orderedEvents.compactMap(\.workUnitID))
        for workUnitID in workUnitIDs.sorted() {
            if let recommendation = RecommendationEngine.repeatedValidationFailure(events: orderedEvents, workUnitID: workUnitID) {
                recommendations.append(recommendation)
            }
        }
        recommendations = RecommendationEngine.active(
            proposals: recommendations,
            controlEvents: orderedEvents
        )
        let lastSequence = orderedEvents.compactMap(\.sequence).max() ?? 0
        return ProjectionSnapshot(
            projectionName: projectionName,
            projectionVersion: projectionVersion,
            processedThroughSequence: lastSequence,
            associations: projectedAssociations,
            metrics: metrics,
            recommendations: recommendations.sorted { $0.id < $1.id }
        )
    }

    private static func orderedBefore(_ lhs: TelemetryEvent, _ rhs: TelemetryEvent) -> Bool {
        let leftSequence = lhs.sequence ?? Int64.max
        let rightSequence = rhs.sequence ?? Int64.max
        if leftSequence != rightSequence {
            return leftSequence < rightSequence
        }
        if lhs.observedAt != rhs.observedAt {
            return lhs.observedAt < rhs.observedAt
        }
        return lhs.eventID.uuidString < rhs.eventID.uuidString
    }

    private static func applyUserCorrections(
        automaticAssociations: [ProjectedAssociation],
        controlEvents: [TelemetryEvent]
    ) -> [ProjectedAssociation] {
        var resolutions = Dictionary(uniqueKeysWithValues: automaticAssociations.map { ($0.id, $0.resolution) })
        for event in controlEvents where event.kind == .associationCorrected {
            guard case .string(let eventIDText) = event.payload["event_id"],
                  let eventID = UUID(uuidString: eventIDText),
                  resolutions[eventID] != nil,
                  case .string(let correction) = event.payload["correction"]
            else {
                continue
            }
            switch correction {
            case "associate":
                guard case .string(let workUnitID) = event.payload["work_unit_id"] else {
                    continue
                }
                resolutions[eventID] = AssociationResolution(
                    state: .userConfirmed,
                    selected: AssociationCandidate(
                        eventID: eventID,
                        workUnitID: workUnitID,
                        score: 1,
                        evidence: ["user_correction"],
                        ruleVersion: CorrelationEngine.ruleVersion
                    ),
                    candidates: []
                )
            case "clear":
                resolutions[eventID] = AssociationResolution(
                    state: .unassociated,
                    selected: nil,
                    candidates: []
                )
            default:
                continue
            }
        }
        return automaticAssociations.map { association in
            ProjectedAssociation(
                eventID: association.id,
                resolution: resolutions[association.id] ?? association.resolution
            )
        }
    }
}
