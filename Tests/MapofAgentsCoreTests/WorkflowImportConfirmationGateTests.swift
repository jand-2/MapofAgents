import Foundation
import Testing
@testable import MapofAgentsCore

@Test
@MainActor
func workflowImportWaitsForExplicitDestructiveConfirmation() async {
    let gate = WorkflowImportConfirmationGate()
    let hostID = HostID(rawValue: "remote-mac")
    let requestTask = Task {
        await gate.requestApproval(sourceHostID: hostID, sourceName: "Example Mac")
    }

    await Task.yield()
    #expect(gate.pendingRequest?.sourceHostID == hostID)
    #expect(gate.pendingRequest?.sourceName == "Example Mac")

    gate.approve()
    #expect(await requestTask.value)
    #expect(gate.pendingRequest == nil)
}

@Test
@MainActor
func workflowImportCancellationBlocksReplacementAndReusesDecisionForRouteRetries() async {
    let gate = WorkflowImportConfirmationGate()
    let hostID = HostID(rawValue: "remote-mac")
    let authorizationID = UUID()
    let requestTask = Task {
        await gate.requestApproval(
            authorizationID: authorizationID,
            sourceHostID: hostID,
            sourceName: "Example Mac"
        )
    }

    await Task.yield()
    gate.cancel()
    #expect(await requestTask.value == false)

    let retryWasApproved = await gate.requestApproval(
        authorizationID: authorizationID,
        sourceHostID: hostID,
        sourceName: "Example Mac"
    )
    #expect(retryWasApproved == false)
    #expect(gate.pendingRequest == nil)

    let separateImportTask = Task {
        await gate.requestApproval(
            authorizationID: UUID(),
            sourceHostID: hostID,
            sourceName: "Example Mac"
        )
    }
    await Task.yield()
    #expect(gate.pendingRequest != nil)
    gate.cancel()
    #expect(await separateImportTask.value == false)
}
