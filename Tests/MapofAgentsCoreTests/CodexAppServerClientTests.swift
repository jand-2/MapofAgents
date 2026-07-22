import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func turnStartUsesLongRunningRequestTimeout() {
    #expect(AppServerMethod.initialize.timeoutSeconds == 6)
    #expect(AppServerMethod.listTurns.timeoutSeconds == 20)
    #expect(AppServerMethod.startTurn.timeoutSeconds == 60)
}

@Test
func appServerMethodsDeclareReplaySafetyCentrally() {
    let replayableMethods = Set(
        AppServerMethod.allCases.filter { $0.replaySafety == .replayableRead }
    )
    #expect(replayableMethods == Set([
        .accountRead,
        .readDirectory,
        .readFile,
        .listModels,
        .listPlugins,
        .listSkills,
        .listThreads,
        .listLoadedThreads,
        .readThread,
        .searchThreads,
        .listTurns,
    ]))
    #expect(AppServerMethod.startThread.replaySafety == .nonReplayableWrite)
    #expect(AppServerMethod.startTurn.replaySafety == .nonReplayableWrite)
    #expect(AppServerMethod.forkThread.replaySafety == .nonReplayableWrite)
}

@Test
func ambiguousWriteErrorExplainsThatTheRequestWasNotReplayed() {
    let message = CodexAppServerError.ambiguousWrite(method: AppServerMethod.startTurn.rawValue)
        .localizedDescription

    #expect(message.contains("not replayed"))
    #expect(message.contains(AppServerMethod.startTurn.rawValue))
    #expect(message.contains("refreshed"))
}

@Test
func appServerSessionTimesOutWritesAsAmbiguousWithoutReplaying() async {
    let session = AppServerSession()
    let connectionID = AppServerConnectionID()
    let recorder = AppServerSentMessageRecorder()

    do {
        _ = try await session.request(
            AppServerCall(.startThread),
            connectionID: connectionID,
            timeoutContext: .localStdio,
            timeoutOverride: .milliseconds(20)
        ) { message, _ in
            await recorder.record(message)
        }
        Issue.record("Expected an unconfirmed write to time out")
    } catch let error as CodexAppServerError {
        guard case .ambiguousWrite(let method) = error else {
            Issue.record("Unexpected App Server error: \(error)")
            return
        }
        #expect(method == AppServerMethod.startThread.rawValue)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await recorder.count == 1)
    #expect(await session.pendingRequestCount() == 0)
}

@Test
func appServerSessionClassifiesDisconnectAfterWriteAsAmbiguousWithoutResend() async {
    let session = AppServerSession()
    let connectionID = AppServerConnectionID()
    let recorder = AppServerSentMessageRecorder()
    let request = Task {
        try await session.request(
            AppServerCall(.forkThread),
            connectionID: connectionID,
            timeoutContext: .remote("example host")
        ) { message, _ in
            await recorder.record(message)
        }
    }

    await recorder.waitForCount(1)
    await session.failPending(connectionID: connectionID)

    do {
        _ = try await request.value
        Issue.record("Expected the unacknowledged write to fail")
    } catch let error as CodexAppServerError {
        guard case .ambiguousWrite(let method) = error else {
            Issue.record("Unexpected App Server error: \(error)")
            return
        }
        #expect(method == AppServerMethod.forkThread.rawValue)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await recorder.count == 1)
    #expect(await session.pendingRequestCount() == 0)
}

#if os(macOS)
@Test
func appServerSessionClassifiesBrokenProcessPipeAsAmbiguousWithoutSIGPIPE() async {
    let session = AppServerSession()
    let connectionID = AppServerConnectionID()
    let pipe = Pipe()
    try? pipe.fileHandleForReading.close()
    defer { try? pipe.fileHandleForWriting.close() }

    do {
        _ = try await session.request(
            AppServerCall(.startTurn),
            connectionID: connectionID,
            timeoutContext: .localStdio
        ) { message, _ in
            let data = try JSONEncoder().encode(message)
            try CodexAppServerClient.writePipeData(data, to: pipe.fileHandleForWriting)
        }
        Issue.record("Expected the closed process pipe write to fail")
    } catch let error as CodexAppServerError {
        guard case .ambiguousWrite(let method) = error else {
            Issue.record("Unexpected App Server error: \(error)")
            return
        }
        #expect(method == AppServerMethod.startTurn.rawValue)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await session.pendingRequestCount() == 0)
}
#endif

@Test
func appServerSessionIgnoresResponsesFromStaleConnectionGenerations() async throws {
    let session = AppServerSession()
    let recorder = AppServerSentMessageRecorder()
    let oldConnectionID = AppServerConnectionID()
    let newConnectionID = AppServerConnectionID()

    let oldRequest = Task {
        try await session.request(
            AppServerCall(.listThreads),
            connectionID: oldConnectionID,
            timeoutContext: .localStdio
        ) { message, _ in
            await recorder.record(message)
        }
    }
    await recorder.waitForCount(1)
    await session.failPending(connectionID: oldConnectionID)
    do {
        _ = try await oldRequest.value
        Issue.record("Expected the old connection request to fail")
    } catch let error as CodexAppServerError {
        guard case .disconnected = error else {
            Issue.record("Unexpected old-connection error: \(error)")
            return
        }
    }

    let newRequest = Task {
        try await session.request(
            AppServerCall(.listModels),
            connectionID: newConnectionID,
            timeoutContext: .localStdio
        ) { message, _ in
            await recorder.record(message)
        }
    }
    await recorder.waitForCount(2)
    let requestID = try #require(await recorder.lastRequestID)
    let response = try JSONEncoder().encode(JSONValue.object([
        "id": .number(Double(requestID)),
        "result": .object(["generation": .string("new")]),
    ]))

    _ = await session.receive(response, connectionID: oldConnectionID)
    #expect(await session.pendingRequestCount(connectionID: newConnectionID) == 1)

    _ = await session.receive(response, connectionID: newConnectionID)
    #expect(try await newRequest.value["generation"]?.stringValue == "new")
    #expect(await session.pendingRequestCount() == 0)
}

@Test
func appServerSessionScopesServerRequestsToTheirConnection() async throws {
    let session = AppServerSession()
    let connectionID = AppServerConnectionID()
    let request = Data(#"{"id":"approval-1","method":"item/commandExecution/requestApproval","params":{}}"#.utf8)

    let event = await session.receive(request, connectionID: connectionID)
    guard case .notification(let notification) = event else {
        Issue.record("Expected a typed server request notification")
        return
    }

    #expect(notification.requestID == .string("approval-1"))
    #expect(notification.connectionID == connectionID)
}

@Test
func remoteAmbiguousWritesReconcileWithReadsOnly() {
    let turnCalls = AppServerWebSocketWorkflowRelay.reconciliationCalls(
        after: .startTurn,
        params: .object(["threadId": .string("thread-1")])
    )
    #expect(turnCalls.map(\.method) == [.readThread, .listTurns])

    let threadCalls = AppServerWebSocketWorkflowRelay.reconciliationCalls(
        after: .startThread,
        params: .object([:])
    )
    #expect(threadCalls.map(\.method) == [.listThreads])

    let forkCalls = AppServerWebSocketWorkflowRelay.reconciliationCalls(
        after: .forkThread,
        params: .object(["threadId": .string("thread-1")])
    )
    #expect(forkCalls.map(\.method) == [.listThreads])
    #expect((turnCalls + threadCalls + forkCalls).allSatisfy {
        $0.method.replaySafety == .replayableRead
    })
}

@Test
func remoteThreadStartReconciliationNeverClaimsAnUncorrelatedCatalogEntry() {
    let observations = [AppServerReconciliationObservation(
        call: AppServerCall(.listThreads),
        result: .object([
            "data": .array([
                .object(["id": .string("thread-existing"), "cwd": .string("/tmp/existing")]),
                .object(["id": .string("thread-created"), "cwd": .string("/tmp/new")]),
            ]),
        ])
    )]

    let response = AppServerWebSocketWorkflowRelay.reconciledResponse(
        after: .startThread,
        params: .object([:]),
        observations: observations
    )

    #expect(response == nil)
}

@Test
func remoteThreadStartReconciliationStaysAmbiguousWhenConcurrentCreatesCannotBeCorrelated() {
    let observations = [AppServerReconciliationObservation(
        call: AppServerCall(.listThreads),
        result: .object([
            "data": .array([
                .object(["id": .string("thread-a")]),
                .object(["id": .string("thread-b")]),
            ]),
        ])
    )]

    let response = AppServerWebSocketWorkflowRelay.reconciledResponse(
        after: .forkThread,
        params: .object(["threadId": .string("source")]),
        observations: observations
    )

    #expect(response == nil)
}

@Test
func remoteTurnStartReconciliationRefreshesButNeverClaimsAnUncorrelatedTurn() {
    let observations = [AppServerReconciliationObservation(
        call: AppServerCall(.listTurns),
        result: .object([
            "data": .array([
                .object(["id": .string("turn-existing"), "status": .string("completed")]),
                .object(["id": .string("turn-new"), "status": .string("running")]),
            ]),
        ])
    )]

    let response = AppServerWebSocketWorkflowRelay.reconciledResponse(
        after: .startTurn,
        params: .object(["threadId": .string("thread-1")]),
        observations: observations
    )

    #expect(response == nil)
}

@Test
func remoteFileWriteReconciliationRequiresTheExactPersistedBytes() {
    let expected = Data("expected".utf8)
    let readCall = AppServerCall(.readFile, params: .object(["path": .string("/tmp/value")]))
    let matching = AppServerReconciliationObservation(
        call: readCall,
        result: .object(["dataBase64": .string(expected.base64EncodedString())])
    )
    let mismatching = AppServerReconciliationObservation(
        call: readCall,
        result: .object(["dataBase64": .string(Data("other".utf8).base64EncodedString())])
    )
    let params: JSONValue = .object([
        "path": .string("/tmp/value"),
        "dataBase64": .string(expected.base64EncodedString()),
    ])

    #expect(AppServerWebSocketWorkflowRelay.reconciledResponse(
        after: .writeFile,
        params: params,
        observations: [matching]
    ) != nil)
    #expect(AppServerWebSocketWorkflowRelay.reconciledResponse(
        after: .writeFile,
        params: params,
        observations: [mismatching]
    ) == nil)
}

@Test
@MainActor
func supervisorConsumesRemoteWriteReconciliationIntoObservableRuntimeState() {
    let hostID = HostID(rawValue: "remote-test")
    let threadRef = ThreadRef(hostID: hostID, threadID: "thread-1", cwd: "/tmp/project", name: "Example")
    let transcript = ThreadTranscript(
        threadRef: threadRef,
        turnTimeline: ThreadTurnTimeline(
            threadRef: threadRef,
            turns: [ThreadTurn(
                id: "turn-new",
                status: .running,
                startedAt: Date(),
                items: []
            )]
        )
    )
    let entry = ThreadCatalogEntry(threadRef: threadRef, hostName: "Remote")
    let reconciliation = AppServerWriteReconciliation(
        hostID: hostID,
        method: .startTurn,
        confirmedCommitted: false,
        affectedThreadRefs: [threadRef],
        observedCatalogEntries: [entry],
        transcript: transcript
    )
    let store = WorkflowSupervisorStore()

    store.applyWriteReconciliation(reconciliation)

    #expect(store.lastWriteReconciliations[hostID]?.confirmedCommitted == false)
    #expect(store.reconciledThreadCatalogEntries[entry.id] == entry)
    #expect(store.threadRuntimeStates[threadRef.qualifiedID]?.activeTurnID == "turn-new")
    #expect(store.threadRuntimeStates[threadRef.qualifiedID]?.status == .running)
}

@Test
@MainActor
func daemonProxyErrorsAreExplicitlyFallbackEligible() {
    #expect(CodexAppServerError.daemonProxyHandshakeFailed("bad upgrade").isStdioFallbackEligible)
    #expect(CodexAppServerError.daemonProxyRequestTimedOut(method: "initialize").isStdioFallbackEligible)
    #expect(!CodexAppServerError.transport("Timed out waiting for initialize response from Codex App Server.").isStdioFallbackEligible)
    #expect(CodexRuntimeStore.shouldRetryConnectionWithFallback(after: CodexAppServerError.daemonProxyHandshakeFailed("bad upgrade")))
    #expect(CodexRuntimeStore.shouldRetryConnectionWithFallback(after: CodexAppServerError.ambiguousWrite(method: "initialize")))
    #expect(!CodexRuntimeStore.shouldRetryConnectionWithFallback(after: CodexAppServerError.ambiguousWrite(method: "turn/start")))
}

@Test
@MainActor
func loadedThreadCatalogStopsResolvingAfterConnectionFailure() async {
    let hostID = HostID(rawValue: "local")
    let ids = ["one", "two", "three"]
    var isConnected = true
    var attemptedIDs: [String] = []

    let entries = await CodexRuntimeStore.resolveLoadedThreadCatalogEntries(
        ids: ids,
        hostID: hostID,
        hostName: "This Mac",
        connectionIsAvailable: { isConnected },
        load: { threadID in
            attemptedIDs.append(threadID)
            isConnected = false
            throw CodexAppServerError.disconnected
        }
    )

    #expect(attemptedIDs == ["one"])
    #expect(entries.map(\.threadRef.threadID) == ids)
    #expect(entries.allSatisfy { $0.loadedStatus == .running })
}

@Test
func jsonValueRejectsFractionalIntegerIDs() {
    #expect(JSONValue.number(7).intValue == 7)
    #expect(JSONValue.number(7.25).intValue == nil)
    #expect(JSONRPCRequestID(JSONValue.number(7)) == .int(7))
    #expect(JSONRPCRequestID(JSONValue.number(7.25)) == nil)
}

@Test
func endpointVerifierRejectsGenericCapabilitiesOnlyInitializeResults() {
    let genericResult: JSONValue = .object([
        "capabilities": .object([:]),
    ])
    let codexNamedResult: JSONValue = .object([
        "serverInfo": .object([
            "name": .string("Codex App Server"),
        ]),
        "capabilities": .object([:]),
    ])
    let platformResult: JSONValue = .object([
        "platformFamily": .string("macOS"),
        "capabilities": .object([:]),
    ])

    #expect(AppServerEndpointVerifier.isTrustedInitializeResult(genericResult) == false)
    #expect(AppServerEndpointVerifier.isTrustedInitializeResult(codexNamedResult))
    #expect(AppServerEndpointVerifier.isTrustedInitializeResult(platformResult))
}

@Test
func endpointVerifierTrustsWindowsCodexRuntimeIdentityWithoutCapabilities() {
    let windowsCodexResult: JSONValue = .object([
        "userAgent": .string("mapofagents-ssh-verify/0.135.0 (Windows 10.0.26200; x86_64)"),
        "codexHome": .string("C:\\Users\\User\\.codex"),
        "platformFamily": .string("windows"),
        "platformOs": .string("windows"),
    ])
    let platformOnlyResult: JSONValue = .object([
        "platformFamily": .string("windows"),
    ])

    #expect(AppServerEndpointVerifier.isTrustedInitializeResult(windowsCodexResult))
    #expect(AppServerEndpointVerifier.isTrustedInitializeResult(platformOnlyResult) == false)
}

@Test
func endpointVerifierUntrustedInitializeErrorListsResponseKeys() {
    let result: JSONValue = .object([
        "unexpected": .string("shape"),
        "platformFamily": .string("windows"),
    ])
    let error = AppServerEndpointVerificationError.untrustedInitializeResult(
        keys: AppServerEndpointVerifier.initializeResultKeys(result)
    )

    #expect(error.localizedDescription.contains("platformFamily"))
    #expect(error.localizedDescription.contains("unexpected"))
}

@Test
func appServerRelayEndpointRejectsInsecureRemotePolicies() throws {
    let loopback = try #require(URL(string: "ws://127.0.0.1:18945"))
    let remoteCleartext = try #require(URL(string: "ws://mac.lan:18945"))
    let remoteSecure = try #require(URL(string: "wss://mac.example.test:18945"))

    #expect(AppServerRelayEndpoint.connectionSecurityError(url: loopback, bearerToken: nil) == nil)
    #expect(AppServerRelayEndpoint.connectionSecurityError(url: loopback, bearerToken: "secret") == nil)
    #expect(AppServerRelayEndpoint.connectionSecurityError(url: remoteSecure, bearerToken: "secret") == nil)

    #expect(AppServerRelayEndpoint.connectionSecurityError(url: remoteCleartext, bearerToken: nil) != nil)
    #expect(AppServerRelayEndpoint.connectionSecurityError(url: remoteCleartext, bearerToken: "secret") != nil)
    #expect(AppServerRelayEndpoint.connectionSecurityError(url: remoteSecure, bearerToken: nil) != nil)
}

@Test
func appServerRelayEndpointRejectsEmbeddedURLCredentialsAndMetadata() throws {
    let userInfo = try #require(URL(string: "wss://example-user:example-password@example.test/socket"))
    let query = try #require(URL(string: "wss://example.test/socket?access_token=example"))
    let fragment = try #require(URL(string: "wss://example.test/socket#example-fragment"))

    #expect(AppServerRelayEndpoint.connectionSecurityError(url: userInfo, bearerToken: "separate-token") != nil)
    #expect(AppServerRelayEndpoint.connectionSecurityError(url: query, bearerToken: "separate-token") != nil)
    #expect(AppServerRelayEndpoint.connectionSecurityError(url: fragment, bearerToken: "separate-token") != nil)

    let machine = SupervisorMachine(
        id: HostID(rawValue: "unsafe-endpoint"),
        name: "Unsafe endpoint",
        endpointDescription: userInfo.absoluteString,
        status: .connected
    )
    #expect(AppServerRelayEndpoint(machine: machine) == nil)
}

#if os(macOS)
@Test
func appServerClientRecordsInvalidJSONDiagnostics() async {
    let client = CodexAppServerClient()

    await client.ingestTestLine(Data("{not json".utf8))

    let diagnostics = await client.currentProtocolDiagnostics()
    #expect(diagnostics.first?.contains("Invalid JSON-RPC frame") == true)
}

@Test
func appServerClientRecordsUnsupportedResponseIDDiagnostics() async {
    let client = CodexAppServerClient()

    await client.ingestTestLine(Data(#"{"id":1.5,"result":null}"#.utf8))

    let diagnostics = await client.currentProtocolDiagnostics()
    #expect(diagnostics.first?.contains("Unsupported JSON-RPC response id") == true)
}
#endif

private actor AppServerSentMessageRecorder {
    private var messages: [JSONValue] = []

    var count: Int { messages.count }

    var lastRequestID: Int? {
        messages.last?["id"]?.intValue
    }

    func record(_ message: JSONValue) {
        messages.append(message)
    }

    func waitForCount(_ expectedCount: Int) async {
        while messages.count < expectedCount {
            await Task.yield()
        }
    }
}
