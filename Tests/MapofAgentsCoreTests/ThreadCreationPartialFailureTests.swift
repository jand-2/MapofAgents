import Foundation
import Testing
@testable import MapofAgentsCore

@MainActor
@Test
func localThreadCreationReturnsConfirmedThreadWhenNamingFails() async throws {
    let store = CodexRuntimeStore()
    var methods: [AppServerMethod] = []

    let outcome = try await store.createThreadUsingRequest(
        cwd: "/Users/example/project",
        name: "Example thread",
        model: "example-model",
        reasoningEffort: "medium"
    ) { method, _ in
        methods.append(method)
        if method == .startThread {
            return confirmedThreadStartResult(id: "local-thread")
        }
        throw CodexAppServerError.server("name unavailable")
    }

    #expect(methods == [.startThread, .setThreadName])
    #expect(outcome.threadRef.threadID == "local-thread")
    #expect(outcome.threadRef.name == nil)
    #expect(outcome.warning?.contains("Thread created") == true)
    #expect(store.threadSummaries.contains { $0.threadID == "local-thread" })
}

@Test
func remoteThreadCreationReturnsConfirmedThreadWhenNamingFails() async throws {
    let recorder = ThreadCreationMethodRecorder()
    let relay = AppServerWebSocketWorkflowRelay(
        endpoint: AppServerRelayEndpoint(
            id: HostID(rawValue: "remote-host"),
            name: "Remote Host",
            url: try #require(URL(string: "wss://example-host.local:18945")),
            bearerToken: "test-only-bearer"
        ),
        supervisor: WorkflowSupervisor()
    )

    let outcome = try await relay.createThreadUsingRequest(
        cwd: "/Users/example/project",
        name: "Example thread",
        model: "example-model",
        reasoningEffort: "medium",
        initialPrompt: ""
    ) { method, _ in
        await recorder.append(method)
        if method == .startThread {
            return confirmedThreadStartResult(id: "remote-thread")
        }
        throw CodexAppServerError.server("name unavailable")
    }

    #expect(await recorder.methods == [.startThread, .setThreadName])
    #expect(outcome.threadRef.hostID == HostID(rawValue: "remote-host"))
    #expect(outcome.threadRef.threadID == "remote-thread")
    #expect(outcome.threadRef.name == nil)
    #expect(outcome.warning?.contains("Thread created") == true)
}

private func confirmedThreadStartResult(id: String) -> JSONValue {
    .object([
        "thread": .object([
            "id": .string(id),
            "cwd": .string("/Users/example/project"),
        ]),
    ])
}

private actor ThreadCreationMethodRecorder {
    private(set) var methods: [AppServerMethod] = []

    func append(_ method: AppServerMethod) {
        methods.append(method)
    }
}
