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
