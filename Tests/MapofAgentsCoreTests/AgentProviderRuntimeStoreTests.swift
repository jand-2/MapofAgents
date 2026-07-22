import Foundation
@testable import MapofAgentsCore
import Testing

@Test
func legacyThreadReferencesDecodeAsCodexWithoutChangingTheirSavedKey() throws {
    let data = Data(#"{"hostID":"local","threadID":"thread-1","cwd":"/tmp/project","name":"Example"}"#.utf8)
    let threadRef = try JSONDecoder().decode(ThreadRef.self, from: data)

    #expect(threadRef.provider == .codex)
    #expect(threadRef.qualifiedID == "local::thread-1")

    let grokRef = ThreadRef(
        provider: .grok,
        hostID: HostID(rawValue: "local"),
        threadID: "thread-1",
        cwd: "/tmp/project"
    )
    #expect(grokRef.qualifiedID == "grok::local::thread-1")
}

@Test
func legacyModelOptionsDecodeAsCodex() throws {
    let data = Data(#"{"id":"catalog-model","displayName":"Catalog Model"}"#.utf8)
    let model = try JSONDecoder().decode(AgentModelOption.self, from: data)

    #expect(model.provider == .codex)
    #expect(model.id == "catalog-model")
    #expect(model.supportedReasoningEfforts.isEmpty)
}

@Test
func providerModelParserUsesCLIOutputWithoutEmbeddedModelNames() {
    let models = AgentProviderRuntimeStore.modelOptions(
        from: """
        Available models
        * vendor-live-a\tVendor Live A (default)
        - vendor-live-b\tVendor Live B
        """,
        provider: .gemini
    )

    #expect(models.map(\.id) == ["vendor-live-a", "vendor-live-b"])
    #expect(models.allSatisfy { $0.provider == .gemini })
    #expect(models.first?.isDefault == true)
}

@Test
func grokModelParserIgnoresCatalogHeadingsAndStatusText() {
    let models = AgentProviderRuntimeStore.modelOptions(
        from: """
        Default model: vendor-live-a

        Available models:
          * vendor-live-a (default)
          * vendor-live-b
        """,
        provider: .grok
    )

    #expect(models.map(\.id) == ["vendor-live-a", "vendor-live-b"])
    #expect(models.first?.isDefault == true)
}

@Test
func grokBrowserSignInUsesExplicitOAuth() {
    #expect(
        ProviderCLIAuthenticationLauncher.authenticationArguments(for: .grok)
            == ["login", "--oauth"]
    )
}

#if os(macOS)
@Test
func grokACPHandshakeBuildsLiveModelsAndCapabilities() throws {
    let response: JSONValue = .object([
        "protocolVersion": .number(1),
        "agentCapabilities": .object([
            "loadSession": .bool(true),
            "sessionCapabilities": .object([:]),
        ]),
        "_meta": .object([
            "agentVersion": .string("test-version"),
            "modelState": .object([
                "currentModelId": .string("live-model"),
                "availableModels": .array([
                    .object([
                        "modelId": .string("live-model"),
                        "name": .string("Live Model"),
                        "description": .string("Discovered from ACP"),
                        "_meta": .object([
                            "reasoningEffort": .string("medium"),
                            "reasoningEfforts": .array([
                                .object([
                                    "id": .string("low"),
                                    "default": .bool(false),
                                ]),
                                .object([
                                    "id": .string("medium"),
                                    "default": .bool(true),
                                ]),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
        ]),
    ])

    let initialization = try GrokACPConnection.parseInitialization(response)

    #expect(initialization.protocolVersion == 1)
    #expect(initialization.supportsLoadSession)
    #expect(!initialization.supportsSessionFork)
    #expect(initialization.agentVersion == "test-version")
    #expect(initialization.modelOptions.map(\.id) == ["live-model"])
    #expect(initialization.modelOptions.first?.supportedReasoningEfforts == ["low", "medium"])
    #expect(initialization.modelOptions.first?.defaultReasoningEffort == "medium")
}

@Test
func grokACPPermissionRequestPreservesOneTimeChoices() throws {
    let request = try #require(
        GrokACPConnection.permissionRequest(
            id: .string("permission-1"),
            params: .object([
                "sessionId": .string("session-1"),
                "toolCall": .object([
                    "toolCallId": .string("tool-1"),
                    "title": .string("Run tests"),
                ]),
                "options": .array([
                    .object([
                        "optionId": .string("allow-once"),
                        "name": .string("Allow once"),
                        "kind": .string("allow_once"),
                    ]),
                    .object([
                        "optionId": .string("deny-once"),
                        "name": .string("Deny"),
                        "kind": .string("reject_once"),
                    ]),
                ]),
            ])
        )
    )

    #expect(request.sessionID == "session-1")
    #expect(request.toolCall["title"]?.stringValue == "Run tests")
    #expect(request.options.map(\.kind) == ["allow_once", "reject_once"])
}
#endif

@Test
func grokForkUsesRealForkFlagsWithoutAutomaticApproval() {
    let arguments = AgentProviderRuntimeStore.grokForkArguments(
        prompt: "Continue safely",
        cwd: "/tmp/example-project",
        sourceSessionID: "source-session",
        forkSessionID: "fork-session",
        model: "catalog-model",
        reasoningEffort: "medium"
    )

    #expect(arguments.contains("--fork-session"))
    #expect(arguments.contains("--resume"))
    #expect(arguments.contains("source-session"))
    #expect(arguments.contains("--session-id"))
    #expect(arguments.contains("fork-session"))
    #expect(arguments.contains("--permission-mode"))
    #expect(arguments.contains("dontAsk"))
    #expect(!arguments.contains("--always-approve"))
    #expect(!arguments.contains("--yolo"))
}

@Test
func providerTranscriptMetadataDecodesWhenAbsentOrPresent() throws {
    let legacy = Data(
        #"{"threadRef":{"provider":"grok","hostID":"local","threadID":"thread-1","cwd":"/tmp/project"},"messages":[],"lastUpdatedAt":0}"#.utf8
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let legacyTranscript = try decoder.decode(ThreadTranscript.self, from: legacy)
    #expect(legacyTranscript.providerMetadata == nil)

    let threadRef = ThreadRef(
        provider: .grok,
        hostID: HostID(rawValue: "local"),
        threadID: "thread-2",
        cwd: "/tmp/project"
    )
    let transcript = ThreadTranscript(
        threadRef: threadRef,
        providerMetadata: ProviderThreadMetadata(
            sessionID: "thread-2",
            generatedTitle: "Generated title",
            isSessionMaterialized: true,
            modelID: "catalog-model",
            reasoningEffort: "medium"
        )
    )
    let decoded = try JSONDecoder().decode(
        ThreadTranscript.self,
        from: JSONEncoder().encode(transcript)
    )
    #expect(decoded.providerMetadata?.generatedTitle == "Generated title")
    #expect(decoded.providerMetadata?.modelID == "catalog-model")
}

@Test
func grokTranscriptNormalizationRestoresHistoryHiddenByAnIncompleteTimeline() throws {
    let threadRef = ThreadRef(
        provider: .grok,
        hostID: HostID(rawValue: "local"),
        threadID: "session-1",
        cwd: "/tmp/project"
    )
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    let messages = [
        ThreadMessage(id: "user-1", role: .user, text: "First", createdAt: start),
        ThreadMessage(id: "assistant-1", role: .assistant, text: "First reply", createdAt: start.addingTimeInterval(1)),
        ThreadMessage(id: "user-2", role: .user, text: "Second", createdAt: start.addingTimeInterval(2)),
        ThreadMessage(id: "assistant-2", role: .assistant, text: "Second reply", createdAt: start.addingTimeInterval(3)),
    ]
    let incompleteTimeline = ThreadTurnTimeline(
        threadRef: threadRef,
        turns: [
            ThreadTurn(
                id: "turn-2",
                status: .complete,
                startedAt: messages[2].createdAt,
                completedAt: messages[3].createdAt,
                items: [
                    ThreadTurnItem(id: messages[2].id, kind: .userMessage, message: messages[2]),
                    ThreadTurnItem(id: messages[3].id, kind: .assistantMessage, message: messages[3]),
                ]
            ),
        ]
    )
    let transcript = ThreadTranscript(
        threadRef: threadRef,
        messages: messages,
        turnTimeline: incompleteTimeline
    )

    let normalized = AgentProviderRuntimeStore.normalizedGrokTranscript(transcript)

    #expect(normalized.messages.map(\.id) == messages.map(\.id))
    #expect(normalized.turnTimeline?.turns.count == 2)
    #expect(normalized.turnTimeline?.turns.flatMap(\.items).map { $0.message.id } == messages.map(\.id))
}

@Test
func progressTurnItemsRemainProgressWhenTimelineIsReconciled() {
    let threadRef = ThreadRef(
        provider: .grok,
        hostID: HostID(rawValue: "local"),
        threadID: "session-1",
        cwd: "/tmp/project"
    )
    let message = ThreadMessage(id: "progress-1", role: .assistant, text: "Checking the weather")
    let transcript = ThreadTranscript(
        threadRef: threadRef,
        messages: [message],
        turnTimeline: ThreadTurnTimeline(
            threadRef: threadRef,
            turns: [
                ThreadTurn(
                    id: "turn-1",
                    status: .running,
                    startedAt: message.createdAt,
                    items: [ThreadTurnItem(id: message.id, kind: .progress, message: message)]
                ),
            ]
        )
    )

    #expect(transcript.sortedChronologically().turnTimeline?.turns[0].items[0].kind == .progress)
}

@Test
@MainActor
func successfulGrokModelsExitStillRequiresSignInWhenCLIReportsNoCredentials() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-grok-auth-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let repository = LocalControlRoomStore(
        paths: ApplicationPaths(applicationSupportDirectory: directory)
    )
    let client = AgentProviderCLIClient(
        resolveExecutable: { provider in
            provider == .grok ? URL(fileURLWithPath: "/tmp/grok") : nil
        },
        run: { _, _, _, _ in
            BoundedProcessResult(
                terminationStatus: 0,
                stdout: BoundedProcessOutput(
                    data: Data(
                        """
                        You are not authenticated.
                        Default model: stale-catalog-model
                        Available models:
                          * stale-catalog-model (default)
                        """.utf8
                    )
                ),
                stderr: BoundedProcessOutput(
                    data: Data("WARN No auth credentials for cli-chat-proxy".utf8)
                )
            )
        },
        launchAuthentication: { _, _ in }
    )
    let store = AgentProviderRuntimeStore(repository: repository, client: client)

    await store.refresh(.grok)

    #expect(store.statusByProvider[.grok]?.state == .signInRequired)
    #expect(store.models(for: .grok).isEmpty)
}

@Test
@MainActor
func graphStoreKeepsProviderIdentityImmutableForOtherwiseMatchingThreads() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-provider-identity-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let repository = LocalControlRoomStore(
        paths: ApplicationPaths(applicationSupportDirectory: directory)
    )
    let graphStore = GraphStore(repository: repository)
    let hostID = HostID(rawValue: "local")
    let codexRef = ThreadRef(
        provider: .codex,
        hostID: hostID,
        threadID: "shared-thread",
        cwd: "/tmp/project"
    )
    let grokRef = ThreadRef(
        provider: .grok,
        hostID: hostID,
        threadID: "shared-thread",
        cwd: "/tmp/project"
    )

    await graphStore.addThreadNode(
        threadRef: codexRef,
        model: "catalog-codex",
        reasoningEffort: ""
    )
    await graphStore.addThreadNode(
        threadRef: grokRef,
        model: "catalog-grok",
        reasoningEffort: ""
    )

    #expect(graphStore.workflowThreadRefs.count == 2)
    await graphStore.updateThreadRunStatus(for: grokRef, status: .running)
    let codexNode = try #require(graphStore.graph.nodes.values.first {
        $0.metadata.threadRef?.matches(codexRef) == true
    })
    let grokNode = try #require(graphStore.graph.nodes.values.first {
        $0.metadata.threadRef?.matches(grokRef) == true
    })
    #expect(codexNode.metadata.runStatus == .idle)
    #expect(grokNode.metadata.runStatus == .running)

    graphStore.selectThread(codexRef)
    #expect(graphStore.selectedNode?.metadata.threadRef?.provider == .codex)

    let grokMention = try #require(
        graphStore.workflowThreadMentionCandidates(excluding: codexRef).first
    )
    #expect(grokMention.subtitle.hasPrefix("Grok · "))
    #expect(grokMention.insertionText.contains("agent-thread://grok/"))
}

@Test
@MainActor
func externalProviderStoreCreatesAndResumesProviderLockedThreads() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-provider-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let repository = LocalControlRoomStore(
        paths: ApplicationPaths(applicationSupportDirectory: directory)
    )
    let probe = AgentProviderCLIProbe()
    let client = AgentProviderCLIClient(
        resolveExecutable: { provider in
            provider == .grok ? URL(fileURLWithPath: "/tmp/grok") : nil
        },
        run: { executableURL, arguments, currentDirectoryURL, timeout in
            await probe.run(
                executableURL: executableURL,
                arguments: arguments,
                currentDirectoryURL: currentDirectoryURL,
                timeout: timeout
            )
        },
        launchAuthentication: { _, _ in }
    )
    let store = AgentProviderRuntimeStore(repository: repository, client: client)

    await store.refresh(.grok)
    #expect(store.models(for: .grok).map(\.id) == ["vendor-live-a"])

    let outcome = try await store.createThread(
        provider: .grok,
        hostID: HostID(rawValue: "local"),
        cwd: "/tmp/project",
        name: "Grok example"
    )
    #expect(outcome.threadRef.provider == .grok)

    try await store.sendMessage(
        "First prompt",
        to: outcome.threadRef,
        model: "vendor-live-a",
        reasoningEffort: nil
    )
    try await store.sendMessage(
        "Follow-up prompt",
        to: outcome.threadRef,
        model: "vendor-live-a",
        reasoningEffort: nil
    )

    let transcript = try await store.loadTranscript(for: outcome.threadRef)
    #expect(transcript.messages.map(\.role) == [.user, .assistant, .user, .assistant])
    #expect(transcript.messages.last?.text == "Provider response")

    let calls = await probe.calls
    #expect(calls[1].arguments.contains("--session-id"))
    #expect(calls[1].arguments.contains(outcome.threadRef.threadID))
    #expect(calls[2].arguments.contains("--resume"))
    #expect(calls[2].arguments.contains(outcome.threadRef.threadID))
    #expect(calls[1].arguments.contains("vendor-live-a"))
}

private actor AgentProviderCLIProbe {
    struct Call: Sendable {
        var arguments: [String]
        var currentDirectoryURL: URL?
        var timeout: TimeInterval
    }

    private(set) var calls: [Call] = []

    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        timeout: TimeInterval
    ) -> BoundedProcessResult {
        calls.append(
            Call(
                arguments: arguments,
                currentDirectoryURL: currentDirectoryURL,
                timeout: timeout
            )
        )
        let output = arguments == ["models"]
            ? "Default model: vendor-live-a\n\nAvailable models:\n  * vendor-live-a (default)\n"
            : "Provider response\n"
        return BoundedProcessResult(
            terminationStatus: 0,
            stdout: BoundedProcessOutput(data: Data(output.utf8)),
            stderr: BoundedProcessOutput(data: Data())
        )
    }
}
