import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func relayStopDuringDelayedAccessTokenCannotCreateStaleSocket() async throws {
    let provider = DelayedRelayAccessTokenProvider()
    let socketFactory = RelayWebSocketTaskFactoryRecorder()
    let relay = AppServerWebSocketWorkflowRelay(
        endpoint: try relayLifecycleTestEndpoint(),
        supervisor: WorkflowSupervisor(),
        accessTokenProvider: provider,
        webSocketTaskFactory: { socketFactory.makeTask(for: $0) }
    )

    let startTask = Task { await relay.start() }
    #expect(await waitForRelayAccessTokenRequests(1, provider: provider))

    await relay.stop()
    let stoppedBeforeToken = await relay.connectionLifecycleSnapshot()
    #expect(stoppedBeforeToken.phase == .stopped)
    #expect(stoppedBeforeToken.connectionID == nil)
    #expect(!stoppedBeforeToken.hasWebSocket)

    await provider.resolveRequest(
        0,
        token: AppServerAccessToken(value: "stale-token")
    )
    #expect(await startTask.value == false)

    let stoppedAfterToken = await relay.connectionLifecycleSnapshot()
    #expect(socketFactory.createdTaskCount == 0)
    #expect(stoppedAfterToken.phase == .stopped)
    #expect(stoppedAfterToken.connectionID == nil)
    #expect(!stoppedAfterToken.hasWebSocket)
}

@Test
func relayReplacementRejectsDelayedTokenFromPreviousGeneration() async throws {
    let provider = DelayedRelayAccessTokenProvider()
    let socketFactory = RelayWebSocketTaskFactoryRecorder()
    let relay = AppServerWebSocketWorkflowRelay(
        endpoint: try relayLifecycleTestEndpoint(),
        supervisor: WorkflowSupervisor(),
        accessTokenProvider: provider,
        webSocketTaskFactory: { socketFactory.makeTask(for: $0) }
    )

    let originalStart = Task { await relay.start() }
    #expect(await waitForRelayAccessTokenRequests(1, provider: provider))
    let originalConnectionID = try #require(
        await relay.connectionLifecycleSnapshot().connectionID
    )

    await relay.stop(markDisconnected: false)
    let replacementStart = Task { await relay.start() }
    #expect(await waitForRelayAccessTokenRequests(2, provider: provider))
    let replacementBeforeOldToken = await relay.connectionLifecycleSnapshot()
    let replacementConnectionID = try #require(replacementBeforeOldToken.connectionID)
    #expect(replacementConnectionID != originalConnectionID)
    #expect(replacementBeforeOldToken.phase == .connecting)
    #expect(!replacementBeforeOldToken.hasWebSocket)

    await provider.resolveRequest(
        0,
        token: AppServerAccessToken(value: "superseded-token")
    )
    #expect(await originalStart.value == false)

    let replacementAfterOldToken = await relay.connectionLifecycleSnapshot()
    #expect(socketFactory.createdTaskCount == 0)
    #expect(replacementAfterOldToken.phase == .connecting)
    #expect(replacementAfterOldToken.connectionID == replacementConnectionID)
    #expect(!replacementAfterOldToken.hasWebSocket)

    await relay.stop(markDisconnected: false)
    await provider.resolveRequest(
        1,
        token: AppServerAccessToken(value: "replacement-token")
    )
    #expect(await replacementStart.value == false)
    let stopped = await relay.connectionLifecycleSnapshot()
    #expect(socketFactory.createdTaskCount == 0)
    #expect(stopped.phase == .stopped)
    #expect(stopped.connectionID == nil)
    #expect(!stopped.hasWebSocket)
}

private func relayLifecycleTestEndpoint() throws -> AppServerRelayEndpoint {
    AppServerRelayEndpoint(
        id: HostID(rawValue: "delayed-token-host"),
        name: "Delayed Token Host",
        url: try #require(URL(string: "wss://example-host.local:18945"))
    )
}

private func waitForRelayAccessTokenRequests(
    _ expectedCount: Int,
    provider: DelayedRelayAccessTokenProvider
) async -> Bool {
    for _ in 0..<2_000 {
        if await provider.startedRequestCount >= expectedCount {
            return true
        }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return false
}

private actor DelayedRelayAccessTokenProvider: AppServerAccessTokenProviding {
    private var nextRequestID = 0
    private var continuations: [Int: CheckedContinuation<AppServerAccessToken?, Error>] = [:]

    var startedRequestCount: Int {
        nextRequestID
    }

    func accessToken() async throws -> AppServerAccessToken? {
        try await withCheckedThrowingContinuation { continuation in
            let requestID = nextRequestID
            nextRequestID += 1
            continuations[requestID] = continuation
        }
    }

    func resolveRequest(_ requestID: Int, token: AppServerAccessToken?) {
        continuations.removeValue(forKey: requestID)?.resume(returning: token)
    }
}

private final class RelayWebSocketTaskFactoryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var createdTaskCountValue = 0

    var createdTaskCount: Int {
        lock.withLock { createdTaskCountValue }
    }

    func makeTask(for request: URLRequest) -> URLSessionWebSocketTask {
        lock.withLock {
            createdTaskCountValue += 1
        }
        return URLSession.shared.webSocketTask(with: request)
    }
}
