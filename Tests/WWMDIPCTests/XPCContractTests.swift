import XCTest
@testable import WWMDIPC

final class XPCContractTests: XCTestCase {
    func testQueryCapabilityCannotRequestDeletion() {
        let request = XPCRequestEnvelope(kind: .requestDeletion, capability: .query)
        XCTAssertThrowsError(try XPCContractValidator.validate(request)) { error in
            XCTAssertEqual(error as? XPCContractError, .capabilityDoesNotPermitKind)
        }
    }

    func testSummaryQueryHasBoundedWindow() throws {
        let now = Date()
        try XPCContractValidator.validate(
            SummaryQuery(from: now.addingTimeInterval(-86_400), to: now, metricNames: ["ai.turn.count"])
        )
        XCTAssertThrowsError(
            try XPCContractValidator.validate(
                SummaryQuery(
                    from: now.addingTimeInterval(-367 * 86_400),
                    to: now,
                    metricNames: []
                )
            )
        )
    }

    func testDeletionPreviewRequiresAnExplicitScopeAndConfirmationRequiresOnlyANonce() throws {
        let envelope = XPCRequestEnvelope(kind: .requestDeletion, capability: .destructiveDelete)
        XCTAssertThrowsError(
            try XPCContractValidator.validate(
                XPCDeletionRequest(envelope: envelope, phase: .preview)
            )
        ) { error in
            XCTAssertEqual(error as? XPCContractError, .invalidDeletionRequest)
        }

        let now = Date()
        let scope = XPCDeletionScope(
            eventScope: XPCDeletionEventScope(
                from: now.addingTimeInterval(-60),
                to: now,
                includeUserSensitiveEvents: true
            ),
            managedOutputIDs: []
        )
        try XPCContractValidator.validate(
            XPCDeletionRequest(envelope: envelope, phase: .preview, scope: scope)
        )

        XCTAssertThrowsError(
            try XPCContractValidator.validate(
                XPCDeletionRequest(
                    envelope: envelope,
                    phase: .confirm,
                    scope: scope,
                    confirmationNonce: UUID()
                )
            )
        ) { error in
            XCTAssertEqual(error as? XPCContractError, .invalidDeletionRequest)
        }
    }

    func testDeletionScopeRejectsDuplicateManagedOutputIDs() {
        let outputID = UUID()
        XCTAssertThrowsError(
            try XPCContractValidator.validate(
                XPCDeletionScope(eventScope: nil, managedOutputIDs: [outputID, outputID])
            )
        ) { error in
            XCTAssertEqual(error as? XPCContractError, .duplicateManagedOutputID)
        }
    }

    func testDeletionScopeHasABoundedManagedOutputSelection() {
        let ids = (0...XPCContractValidator.maximumDeletionManagedOutputs).map { _ in UUID() }
        XCTAssertThrowsError(
            try XPCContractValidator.validate(
                XPCDeletionScope(eventScope: nil, managedOutputIDs: ids)
            )
        ) { error in
            XCTAssertEqual(error as? XPCContractError, .deletionSelectionLimitExceeded)
        }
    }

    func testNativeClientRejectsMissingSigningConfiguration() {
        XCTAssertThrowsError(
            try NativeXPCClient(machServiceName: "", agentCodeSigningRequirement: "identifier example")
        ) { error in
            XCTAssertEqual(error as? NativeXPCClientError, .emptyMachServiceName)
        }
        XCTAssertThrowsError(
            try NativeXPCClient(machServiceName: "com.example.wwmd", agentCodeSigningRequirement: "")
        ) { error in
            XCTAssertEqual(error as? NativeXPCClientError, .emptyCodeSigningRequirement)
        }
    }
}
