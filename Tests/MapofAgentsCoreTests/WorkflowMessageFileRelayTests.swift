#if os(macOS)
import Foundation
import Testing
@testable import MapofAgentsCore

@MainActor
@Test
func workflowMessageRelayClaimsAndCompletesAProviderRequest() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-workflow-relay-test-\(UUID().uuidString)", isDirectory: true)
    let relay = WorkflowMessageFileRelay(
        rootDirectoryURL: root,
        pollInterval: .milliseconds(5)
    )
    let probe = WorkflowMessageRelayProbe()
    let task = try relay.start { request in
        probe.requests.append(request)
        return WorkflowMessageRelayResult(
            requestID: request.requestID,
            success: true,
            detail: "Delivered",
            reply: "Hello from Grok"
        )
    }
    defer {
        task.cancel()
        try? FileManager.default.removeItem(at: root)
    }

    let helpResult = try BoundedProcessRunner.runBlocking(
        executableURL: relay.helperExecutableURL,
        arguments: ["--help"],
        timeout: 5,
        maxOutputBytes: 32 * 1_024
    )
    #expect(helpResult.terminationStatus == 0)
    #expect(helpResult.stdout.stringValue.contains("--source-provider"))
    #expect(helpResult.stdout.stringValue.contains("--target-thread"))

    let request = WorkflowMessageRelayRequest(
        sourceProvider: .codex,
        sourceHostID: HostID(rawValue: "local"),
        sourceThreadID: "source-thread",
        targetProvider: .grok,
        targetHostID: HostID(rawValue: "local"),
        targetThreadID: "target-thread",
        message: "Say hello"
    )
    let pendingURL = relay.pendingDirectoryURL
        .appendingPathComponent("\(request.requestID).json")
    let encodedRequest = try JSONEncoder().encode(request)
    let requestJSON = try #require(String(data: encodedRequest, encoding: .utf8))
    #expect(requestJSON.contains("\"sourceHostID\":\"local\""))
    #expect(requestJSON.contains("\"targetHostID\":\"local\""))
    try MapofAgentsPrivateFile.write(encodedRequest, to: pendingURL)

    let result = try await waitForWorkflowRelayResult(
        requestID: request.requestID,
        in: relay.resultsDirectoryURL
    )
    #expect(result.success)
    #expect(result.reply == "Hello from Grok")
    #expect(probe.requests == [request])
    let claimedURL = relay.claimedDirectoryURL
        .appendingPathComponent("\(request.requestID).json")
    try await waitForWorkflowRelayClaimRemoval(at: claimedURL)
    #expect(!FileManager.default.fileExists(atPath: pendingURL.path))
    #expect(!FileManager.default.fileExists(atPath: claimedURL.path))

    let attributes = try FileManager.default.attributesOfItem(atPath: relay.helperExecutableURL.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    #expect(permissions.intValue & 0o777 == 0o700)
}

@MainActor
@Test
func workflowMessageRelayDoesNotReplayAnAbandonedClaim() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-workflow-relay-claim-test-\(UUID().uuidString)", isDirectory: true)
    let relay = WorkflowMessageFileRelay(
        rootDirectoryURL: root,
        pollInterval: .milliseconds(5)
    )
    let probe = WorkflowMessageRelayProbe()
    let firstTask = try relay.start { request in
        probe.requests.append(request)
        return WorkflowMessageRelayResult(
            requestID: request.requestID,
            success: true,
            detail: "Unexpected delivery"
        )
    }
    firstTask.cancel()
    defer { try? FileManager.default.removeItem(at: root) }

    let request = WorkflowMessageRelayRequest(
        sourceProvider: .codex,
        sourceHostID: HostID(rawValue: "local"),
        sourceThreadID: "source-thread",
        targetProvider: .grok,
        targetHostID: HostID(rawValue: "local"),
        targetThreadID: "target-thread",
        message: "Do not replay me"
    )
    let claimedURL = relay.claimedDirectoryURL
        .appendingPathComponent("\(request.requestID).json")
    try MapofAgentsPrivateFile.write(JSONEncoder().encode(request), to: claimedURL)

    let secondTask = try relay.start { relayedRequest in
        probe.requests.append(relayedRequest)
        return WorkflowMessageRelayResult(
            requestID: relayedRequest.requestID,
            success: true,
            detail: "Unexpected delivery"
        )
    }
    defer { secondTask.cancel() }

    let result = try await waitForWorkflowRelayResult(
        requestID: request.requestID,
        in: relay.resultsDirectoryURL
    )
    #expect(!result.success)
    #expect(result.detail.contains("did not replay"))
    #expect(probe.requests.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: claimedURL.path))
}

@MainActor
private final class WorkflowMessageRelayProbe {
    var requests: [WorkflowMessageRelayRequest] = []
}

private func waitForWorkflowRelayResult(
    requestID: String,
    in resultsDirectoryURL: URL
) async throws -> WorkflowMessageRelayResult {
    let resultURL = resultsDirectoryURL.appendingPathComponent("\(requestID).json")
    for _ in 0..<200 {
        if FileManager.default.fileExists(atPath: resultURL.path) {
            let data = try MapofAgentsPrivateFile.read(resultURL, maximumBytes: 1_048_576)
            return try JSONDecoder().decode(WorkflowMessageRelayResult.self, from: data)
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    throw WorkflowMessageRelayTestError.timedOut
}

private func waitForWorkflowRelayClaimRemoval(at claimedURL: URL) async throws {
    for _ in 0..<200 {
        if !FileManager.default.fileExists(atPath: claimedURL.path) {
            return
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    throw WorkflowMessageRelayTestError.timedOut
}

private enum WorkflowMessageRelayTestError: Error {
    case timedOut
}
#endif
