import Foundation
import Observation

@MainActor
@Observable
public final class CodexRuntimeStore {
    public private(set) var connectionState: HostStatus = .disconnected
    public private(set) var statusMessage: String = "Not connected"
    public private(set) var localHost: AgentHost
    public private(set) var accountLabel: String = "Unknown account"
    public private(set) var models: [CodexModelOption] = []
    public private(set) var threadSummaries: [ThreadRef] = []
    public private(set) var mentionCandidates: [MentionCandidate] = []
    public private(set) var workflowEvents: [WorkflowEvent] = []
    public private(set) var latestNotifications: [CodexServerNotification] = []
    public private(set) var runtimeDiagnostics: [RuntimeDiagnosticStep] = []
    public private(set) var pendingAttentionRequests: [RuntimeAttentionRequest] = []
    public private(set) var liveAssistantTextByThreadID: [String: String] = [:]
    public private(set) var threadRuntimeStates: [String: ThreadRuntimeState] = [:]

    private let client: CodexAppServerClient
    private let mentionCatalogSession: MentionCatalogSession
    private var isConnectingRuntime = false
    private var mentionCatalogPublicationGeneration = MentionCatalogPublicationGeneration()

    public init(
        client: CodexAppServerClient = CodexAppServerClient(),
        mentionCatalogSession: MentionCatalogSession = MentionCatalogSession()
    ) {
        self.client = client
        self.mentionCatalogSession = mentionCatalogSession
        #if os(macOS)
        let codexPath = LocalCodexDiscovery.findCodexExecutable()
        self.localHost = AgentHost(
            id: HostID(rawValue: "local"),
            name: ProcessInfo.processInfo.hostName,
            platform: .macOS,
            codexHome: nil,
            endpointDescription: codexPath == nil ? "codex not found" : "stdio app-server",
            status: codexPath == nil ? .unavailable : .disconnected
        )
        #else
        self.localHost = AgentHost(
            id: HostID(rawValue: "ios-client"),
            name: "This iPhone",
            platform: .iOS,
            codexHome: nil,
            endpointDescription: "remote control surface",
            status: .disconnected
        )
        statusMessage = "Connect to a remote machine"
        #endif

        Task {
            await client.setNotificationHandler { [weak self] notification in
                Task { @MainActor in
                    self?.record(notification)
                }
            }
        }
    }

    public var defaultModel: CodexModelOption {
        models.first(where: \.isDefault)
            ?? models.first
            ?? CodexModelOption(id: "gpt-5.5", displayName: "gpt-5.5", defaultReasoningEffort: "high", supportedReasoningEfforts: ["low", "medium", "high", "xhigh"], isDefault: true)
    }

    public func connect() async {
        #if !os(macOS)
        connectionState = .disconnected
        localHost.status = .disconnected
        statusMessage = "Connect to a remote machine"
        return
        #else
        if await client.isInitializedAndRunning() {
            connectionState = .connected
            localHost.status = .connected
            localHost.lastSeenAt = Date()
            statusMessage = "Connected via \(await client.currentLaunchDescription())"
            return
        }

        if isConnectingRuntime {
            await waitForActiveConnectionAttempt()
            return
        }

        isConnectingRuntime = true
        defer {
            isConnectingRuntime = false
        }

        connectionState = .connecting
        statusMessage = "Starting codex app-server"

        do {
            try await connectOnce()
        } catch {
            guard Self.shouldRetryConnectionWithFallback(after: error) else {
                applyConnectionFailure(error)
                return
            }

            statusMessage = "Retrying with stdio app-server"
            do {
                try await connectOnce()
            } catch {
                applyConnectionFailure(error)
            }
        }
        #endif
    }

    private func waitForActiveConnectionAttempt() async {
        while isConnectingRuntime, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func connectOnce() async throws {
        do {
            let initializeResult = try await client.request(AppServerCall(
                .initialize,
                params: .object([
                    "clientInfo": .object([
                        "name": .string("mapofagents"),
                        "title": .string("mapofagents"),
                        "version": .string("0.1.0"),
                    ]),
                    "capabilities": .object([
                        "experimentalApi": .bool(true),
                    ]),
                ])
            ))

            try await client.notify(method: "initialized")
            await client.markInitialized()
            let launchDescription = await client.currentLaunchDescription()
            updateHost(fromInitializeResult: initializeResult, launchDescription: launchDescription)
        } catch {
            guard Self.isAlreadyInitialized(error) else {
                throw error
            }
            await client.markInitialized()
            localHost.endpointDescription = await client.currentLaunchDescription()
        }

        async let accountTask: Void = refreshAccountDirect()
        async let modelsTask: Void = refreshModelsDirect()
        _ = try await (accountTask, modelsTask)

        let launchDescription = await client.currentLaunchDescription()
        connectionState = .connected
        statusMessage = "Connected via \(launchDescription)"
        localHost.status = .connected
        localHost.lastSeenAt = Date()

        Task {
            try? await refreshThreads()
        }

        Task {
            await refreshMentionCandidates()
        }
    }

    private static func isAlreadyInitialized(_ error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains("already initialized")
    }

    private func applyConnectionFailure(_ error: Error) {
        let hadSuccessfulConnection = localHost.lastSeenAt != nil
        connectionState = hadSuccessfulConnection ? .disconnected : .unavailable
        localHost.status = hadSuccessfulConnection ? .disconnected : .unavailable
        statusMessage = error.localizedDescription
    }

    public func refreshModels() async throws {
        let result = try await runtimeRead(
            method: .listModels,
            params: .object([
                "limit": .number(100),
                "includeHidden": .bool(false),
            ])
        )

        let values = result["data"]?.arrayValue ?? []
        models = values.compactMap(Self.modelOption)
    }

    private func refreshModelsDirect() async throws {
        let result = try await client.request(AppServerCall(
            .listModels,
            params: .object([
                "limit": .number(100),
                "includeHidden": .bool(false),
            ])
        ))

        let values = result["data"]?.arrayValue ?? []
        models = values.compactMap(Self.modelOption)
    }

    public func refreshThreads() async throws {
        let entries = try await threadCatalogEntries(limit: 20, archived: false)
        threadSummaries = entries.map(\.threadRef)
    }

    public func threadCatalogEntries(limit: Int = 100, archived: Bool = false) async throws -> [ThreadCatalogEntry] {
        let result = try await runtimeRead(
            method: .listThreads,
            params: .object([
                "limit": .number(Double(limit)),
                "archived": .bool(archived),
            ])
        )

        let hostID = localHost.id
        return (result["data"]?.arrayValue ?? []).compactMap { value in
            ThreadCatalogEntry.appServerThread(
                from: value,
                hostID: hostID,
                hostName: localHost.name
            )?.applying(runtimeState: threadRuntimeStates[ThreadRef.qualifiedID(
                hostID: hostID,
                threadID: value["id"]?.stringValue ?? value["threadId"]?.stringValue ?? ""
            )])
        }
    }

    public func searchThreadCatalog(query: String, limit: Int = 50) async throws -> [ThreadCatalogEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let result = try await runtimeRead(
            method: .searchThreads,
            params: .object(Self.threadSearchParams(query: trimmed, limit: limit))
        )

        return (result["data"]?.arrayValue ?? result["threads"]?.arrayValue ?? []).compactMap { value in
            ThreadCatalogEntry.appServerSearchResult(from: value, hostID: localHost.id, hostName: localHost.name)
        }
    }

    public func loadedThreadCatalogEntries(limit: Int = 100) async -> [ThreadCatalogEntry] {
        guard let result = try? await runtimeRead(
            method: .listLoadedThreads,
            params: .object(["limit": .number(Double(limit))])
        ) else {
            return []
        }

        let ids = Array(ThreadCatalogEntry.loadedThreadIDs(from: result).prefix(limit))
        var entries: [ThreadCatalogEntry] = []
        for threadID in ids {
            if let entry = try? await readThreadCatalogEntry(threadID: threadID, cwdHint: nil) {
                entries.append(entry)
            } else {
                let threadRef = ThreadRef(hostID: localHost.id, threadID: threadID, cwd: "", name: nil)
                entries.append(
                    ThreadCatalogEntry(
                        threadRef: threadRef,
                        hostName: localHost.name,
                        title: "Codex thread",
                        source: "loaded",
                        loadedStatus: .running,
                        lastActivityAt: Date()
                    )
                )
            }
        }
        return entries
    }

    public func resolveThread(threadID: String, cwdHint: String? = nil) async -> ThreadRef? {
        if let known = threadSummaries.first(where: { $0.threadID.caseInsensitiveCompare(threadID) == .orderedSame }) {
            return known
        }

        if let thread = try? await readThread(threadID: threadID, cwdHint: cwdHint) {
            return thread
        }

        if let thread = try? await findThreadInList(threadID: threadID, limit: 200) {
            return thread
        }

        return nil
    }

    public func refreshMentionCandidates(cwd: String? = nil) async {
        let generation = mentionCatalogPublicationGeneration.begin()
        let candidates = await loadMentionCandidates(cwd: cwd)
        guard !Task.isCancelled,
              mentionCatalogPublicationGeneration.accepts(generation) else {
            return
        }
        mentionCandidates = candidates
    }

    public func loadMentionCandidates(cwd: String? = nil) async -> [MentionCandidate] {
        let key = MentionCatalogSession.Key(
            scope: "\(localHost.id.rawValue)|\(connectionState.rawValue)",
            rootPath: cwd
        )
        return await mentionCatalogSession.candidates(for: key) { [weak self] in
            guard let self else { return [MapofAgentsWorkflowBridgeSkill.mentionCandidate] }
            async let skillsResult = self.optionalRuntimeRequest(
                method: .listSkills,
                params: Self.catalogParams(cwd: cwd)
            )
            async let pluginsResult = self.optionalRuntimeRequest(
                method: .listPlugins,
                params: Self.catalogParams(cwd: cwd)
            )
            async let filesResult = Self.fileMentionCandidates(rootPath: cwd)

            let skillValue = await skillsResult
            let pluginValue = await pluginsResult
            let fileValue = await filesResult
            guard !Task.isCancelled else { return [] }
            return Self.catalogMentionCandidates(
                skillsResult: skillValue,
                pluginsResult: pluginValue,
                fileCandidates: fileValue
            )
        }
    }

    public func refreshAccount() async throws {
        let result = try await runtimeRead(
            method: .accountRead,
            params: .object([
                "refreshToken": .bool(false),
            ])
        )

        applyAccountResult(result)
    }

    private func refreshAccountDirect() async throws {
        let result = try await client.request(AppServerCall(
            .accountRead,
            params: .object([
                "refreshToken": .bool(false),
            ])
        ))

        applyAccountResult(result)
    }

    private func applyAccountResult(_ result: JSONValue) {
        if let account = result["account"]?.objectValue {
            accountLabel = account["email"]?.stringValue
                ?? account["planType"]?.stringValue
                ?? "Authenticated"
        } else if result["requiresOpenaiAuth"]?.boolValue == true {
            accountLabel = "Sign in required"
        } else {
            accountLabel = "No account"
        }
    }

    private func readThread(threadID: String, cwdHint: String?) async throws -> ThreadRef? {
        guard let entry = try await readThreadCatalogEntry(threadID: threadID, cwdHint: cwdHint) else {
            return nil
        }
        return entry.threadRef
    }

    private func readThreadCatalogEntry(threadID: String, cwdHint: String?) async throws -> ThreadCatalogEntry? {
        let result = try await runtimeRead(
            method: .readThread,
            params: .object([
                "threadId": .string(threadID),
            ])
        )
        let threadValue = result["thread"] ?? result
        if let entry = ThreadCatalogEntry.appServerThread(from: threadValue, hostID: localHost.id, hostName: localHost.name) {
            return entry
        }
        guard let threadRef = Self.threadRef(from: threadValue, hostID: localHost.id, cwdHint: cwdHint) else {
            return nil
        }
        return ThreadCatalogEntry(threadRef: threadRef, hostName: localHost.name, source: "loaded")
    }

    private func findThreadInList(threadID: String, limit: Int) async throws -> ThreadRef? {
        let result = try await runtimeRead(
            method: .listThreads,
            params: .object([
                "limit": .number(Double(limit)),
                "archived": .bool(false),
            ])
        )

        return (result["data"]?.arrayValue ?? [])
            .compactMap { Self.threadRef(from: $0, hostID: localHost.id, cwdHint: nil) }
            .first { $0.threadID.caseInsensitiveCompare(threadID) == .orderedSame }
    }

    public func runDiagnostics() async {
        runtimeDiagnostics = [
            RuntimeDiagnosticStep(id: "codex", title: "Find Codex executable", status: .running),
            RuntimeDiagnosticStep(id: "connect", title: "Connect runtime", status: .pending),
            RuntimeDiagnosticStep(id: "account", title: "Read account", status: .pending),
            RuntimeDiagnosticStep(id: "models", title: "List models", status: .pending),
            RuntimeDiagnosticStep(id: "threads", title: "List threads", status: .pending),
        ]

        if let codexPath = LocalCodexDiscovery.findCodexExecutable() {
            updateDiagnostic("codex", status: .passed, detail: codexPath)
        } else {
            updateDiagnostic("codex", status: .failed, detail: "codex not found")
            return
        }

        updateDiagnostic("connect", status: .running)
        if connectionState != .connected {
            await connect()
        }

        guard connectionState == .connected else {
            updateDiagnostic("connect", status: .failed, detail: statusMessage)
            return
        }
        updateDiagnostic("connect", status: .passed, detail: localHost.endpointDescription)

        do {
            updateDiagnostic("account", status: .running)
            try await refreshAccount()
            updateDiagnostic("account", status: .passed, detail: accountLabel)

            updateDiagnostic("models", status: .running)
            try await refreshModels()
            updateDiagnostic("models", status: .passed, detail: "\(models.count) models")

            updateDiagnostic("threads", status: .running)
            try await refreshThreads()
            updateDiagnostic("threads", status: .passed, detail: "\(threadSummaries.count) threads sampled")

            statusMessage = "Runtime diagnostic passed via \(localHost.endpointDescription)"
        } catch {
            statusMessage = error.localizedDescription
            if runtimeDiagnostics.contains(where: { $0.status == .running }) {
                for step in runtimeDiagnostics where step.status == .running {
                    updateDiagnostic(step.id, status: .failed, detail: error.localizedDescription)
                }
            }
        }
    }

    public func createThread(
        cwd: String,
        name: String,
        model: String,
        reasoningEffort: String,
        permissions: CodexThreadPermissions = .default,
        initialPrompt: String = ""
    ) async throws -> ThreadCreationOutcome {
        try await createThreadUsingRequest(
            cwd: cwd,
            name: name,
            model: model,
            reasoningEffort: reasoningEffort,
            permissions: permissions,
            initialPrompt: initialPrompt
        ) { [weak self] method, params in
            guard let self else { throw CodexAppServerError.disconnected }
            return try await self.runtimeRequest(method: method, params: params)
        }
    }

    func createThreadUsingRequest(
        cwd: String,
        name: String,
        model: String,
        reasoningEffort: String,
        permissions: CodexThreadPermissions = .default,
        initialPrompt: String = "",
        request: @escaping (AppServerMethod, JSONValue) async throws -> JSONValue
    ) async throws -> ThreadCreationOutcome {
        let result = try await request(
            .startThread,
            .object(Self.threadStartParams(cwd: cwd, model: model, permissions: permissions))
        )

        guard
            let thread = result["thread"],
            let threadID = thread["id"]?.stringValue,
            let threadCwd = thread["cwd"]?.stringValue
        else {
            throw CodexAppServerError.invalidResponse
        }

        var threadRef = ThreadRef(hostID: localHost.id, threadID: threadID, cwd: threadCwd)
        publishCreatedThread(threadRef)
        var warnings: [String] = []

        if !name.isEmpty {
            do {
                _ = try await request(
                    .setThreadName,
                    .object([
                    "threadId": .string(threadID),
                    "name": .string(name),
                    ])
                )
                threadRef.name = name
                publishCreatedThread(threadRef)
            } catch {
                warnings.append("Thread created, but its name could not be saved: \(error.localizedDescription)")
            }
        }

        let trimmedPrompt = initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            do {
                try await sendMessage(
                    trimmedPrompt,
                    to: threadRef,
                    model: model,
                    reasoningEffort: reasoningEffort,
                    permissions: permissions
                )
            } catch {
                warnings.append("Thread created, but the initial prompt could not be sent: \(error.localizedDescription)")
            }
        }

        return ThreadCreationOutcome(
            threadRef: threadRef,
            warning: warnings.isEmpty ? nil : warnings.joined(separator: " ")
        )
    }

    private func publishCreatedThread(_ threadRef: ThreadRef) {
        if let index = threadSummaries.firstIndex(where: {
            $0.hostID == threadRef.hostID && $0.threadID == threadRef.threadID
        }) {
            threadSummaries[index] = threadRef
        } else {
            threadSummaries.insert(threadRef, at: 0)
        }
    }

    public func loadTranscript(for threadRef: ThreadRef) async throws -> ThreadTranscript {
        try await loadTranscriptPage(for: threadRef, cursor: nil)
    }

    public func loadOlderTranscriptPage(for threadRef: ThreadRef, cursor: String) async throws -> ThreadTranscript {
        try await loadTranscriptPage(for: threadRef, cursor: cursor)
    }

    public func localRolloutTranscript(for threadRef: ThreadRef) async -> ThreadTranscript? {
        guard threadRef.hostID == localHost.id else {
            return nil
        }
        let codexHome = localHost.codexHome ?? "\(NSHomeDirectory())/.codex"
        return await Self.localRolloutTranscript(
            threadID: threadRef.threadID,
            codexHome: codexHome,
            threadRef: threadRef
        )
    }

    public func localSubagentChildren(for parentThreadRef: ThreadRef) async -> [ThreadRef] {
        guard parentThreadRef.hostID == localHost.id else {
            return []
        }
        let codexHome = localHost.codexHome ?? "\(NSHomeDirectory())/.codex"
        return await Self.localSubagentChildren(
            parentThreadID: parentThreadRef.threadID,
            codexHome: codexHome,
            hostID: parentThreadRef.hostID
        )
    }

    private func loadTranscriptPage(for threadRef: ThreadRef, cursor: String?) async throws -> ThreadTranscript {
        let threadReadResult = try? await runtimeRead(
            method: .readThread,
            params: .object([
                "threadId": .string(threadRef.threadID),
            ])
        )
        var params: [String: JSONValue] = [
            "threadId": .string(threadRef.threadID),
            "limit": .number(40),
            "sortDirection": .string("desc"),
            "itemsView": .string("full"),
        ]
        if let cursor, !cursor.isEmpty {
            params["cursor"] = .string(cursor)
        }

        let result = try await runtimeRead(
            method: .listTurns,
            params: .object(params)
        )

        let appServerTranscript = ThreadTranscriptParser.transcript(from: result, threadRef: threadRef)
            .sortedChronologically()
        let transcriptToResolve: ThreadTranscript
        if let rolloutPath = threadReadResult?["thread"]?["path"]?.stringValue ?? threadReadResult?["path"]?.stringValue,
           let rolloutTranscript = await Self.localRolloutTranscript(path: rolloutPath, threadRef: threadRef),
           !rolloutTranscript.messages.isEmpty {
            transcriptToResolve = ThreadTranscriptParser.transcriptByAddingImageAttachments(
                from: rolloutTranscript,
                to: appServerTranscript,
                appendMissingMessages: false
            )
        } else {
            transcriptToResolve = appServerTranscript
        }

        let resolvedTranscript = await resolveLocalImageAttachments(in: transcriptToResolve)
        liveAssistantTextByThreadID[threadRef.threadID] = nil
        upsertRuntimeState(hostID: threadRef.hostID, threadID: threadRef.threadID) { state in
            if cursor == nil {
                state.reconcileAfterLatestTranscriptRead(resolvedTranscript)
            } else {
                state.prepareForTranscriptRead()
            }
        }
        return resolvedTranscript
    }

    public func sendMessage(
        _ text: String,
        to threadRef: ThreadRef,
        model: String?,
        reasoningEffort: String?,
        permissions: CodexThreadPermissions? = nil,
        attachments: [ChatInputAttachment] = []
    ) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else {
            return
        }

        let resolvedAttachments = try prepareLocalAttachments(attachments, for: threadRef)
        let inputItems = ChatInputAttachmentService.inputItems(
            text: text,
            attachments: resolvedAttachments
        )
        guard !inputItems.isEmpty else { return }

        try await resumeThread(threadRef, permissions: permissions)

        var params: [String: JSONValue] = [
            "threadId": .string(threadRef.threadID),
            "input": .array(inputItems),
        ]

        if let model, !model.isEmpty {
            params["model"] = .string(model)
        }

        if let reasoningEffort, !reasoningEffort.isEmpty {
            params["effort"] = .string(reasoningEffort)
        }

        if let permissions {
            params.merge(permissions.turnParams(cwd: threadRef.cwd)) { _, new in new }
        }

        let result = try await runtimeRequest(method: .startTurn, params: .object(params))
        let turnID = Self.turnID(fromAppServerValue: result)
        upsertRuntimeState(hostID: threadRef.hostID, threadID: threadRef.threadID) { state in
            state.status = .running
            state.activeFlags.insert(.running)
            state.liveAssistantText = ""
            state.lastActivityAt = Date()
            if let turnID {
                state.activeTurnID = turnID
            }
        }
    }

    public func interruptThread(_ threadRef: ThreadRef) async throws -> String {
        guard threadRef.hostID == localHost.id else {
            throw CodexAppServerError.server("This thread belongs to \(threadRef.hostID.rawValue), not the connected local Codex runtime.")
        }

        let turnID = try await interruptibleTurnID(for: threadRef)
        _ = try await runtimeRequest(
            method: .interruptTurn,
            params: .object([
                "threadId": .string(threadRef.threadID),
                "turnId": .string(turnID),
            ])
        )
        upsertRuntimeState(hostID: threadRef.hostID, threadID: threadRef.threadID) { state in
            state.status = .complete
            state.activeFlags.remove(.running)
            state.liveAssistantText = ""
            state.currentActivitySummary = "Turn stopped"
        }
        return turnID
    }

    private func prepareLocalAttachments(
        _ attachments: [ChatInputAttachment],
        for threadRef: ThreadRef
    ) throws -> [ResolvedChatInputAttachment] {
        guard !attachments.isEmpty else { return [] }
        let directory = try ChatInputAttachmentService.localAttachmentDirectory(for: threadRef)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return try attachments.map { attachment in
            let name = ChatInputAttachmentService.sanitizedFileName(attachment.name)
            let data = try ChatInputAttachmentService.attachmentData(attachment)
            let destination = directory.appendingPathComponent(name, isDirectory: false)
            try data.write(to: destination, options: .atomic)
            let mimeType = attachment.mimeType ?? ChatInputAttachmentService.inferredMimeType(forFileName: name)
            return ResolvedChatInputAttachment(
                id: attachment.id,
                kind: attachment.kind,
                name: name,
                mimeType: mimeType,
                path: destination.path,
                byteCount: data.count
            )
        }
    }

    @discardableResult
    private func resumeThread(_ threadRef: ThreadRef, permissions: CodexThreadPermissions? = nil) async throws -> JSONValue {
        guard threadRef.hostID == localHost.id else {
            throw CodexAppServerError.server("This thread belongs to \(threadRef.hostID.rawValue), not the connected local Codex runtime.")
        }

        var params: [String: JSONValue] = [
            "threadId": .string(threadRef.threadID),
            "cwd": .string(threadRef.cwd),
        ]
        if let permissions {
            params.merge(permissions.threadParams()) { _, new in new }
        }

        return try await runtimeRequest(
            method: .resumeThread,
            params: .object(params)
        )
    }

    private func interruptibleTurnID(for threadRef: ThreadRef) async throws -> String {
        let stateTurnID = threadRuntimeStates[threadRef.qualifiedID]?.activeTurnID
        if let stateTurnID,
           !Self.isSyntheticTranscriptTurnID(stateTurnID, threadRef: threadRef) {
            return stateTurnID
        }

        let result = try await runtimeRead(
            method: .listTurns,
            params: .object([
                "threadId": .string(threadRef.threadID),
                "limit": .number(5),
                "sortDirection": .string("desc"),
                "itemsView": .string("full"),
            ])
        )
        if let turnID = Self.interruptibleTurnID(fromTurnsListResult: result, threadRef: threadRef) {
            return turnID
        }

        throw CodexAppServerError.server("No running turn id was available for \(threadRef.threadID). Refresh the thread and try stopping it again.")
    }

    private nonisolated static func localRolloutTranscript(path: String, threadRef: ThreadRef) async -> ThreadTranscript? {
        await Task.detached(priority: .utility) {
            let url = URL(fileURLWithPath: path)
            guard url.isFileURL,
                  let data = try? Data(contentsOf: url) else {
                return nil
            }
            return ThreadTranscriptParser.transcript(fromRolloutData: data, threadRef: threadRef)
        }.value
    }

    private nonisolated static func localRolloutTranscript(
        threadID: String,
        codexHome: String,
        threadRef: ThreadRef
    ) async -> ThreadTranscript? {
        await Task.detached(priority: .utility) {
            let sessionsURL = URL(fileURLWithPath: codexHome, isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(
                at: sessionsURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return nil
            }

            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension == "jsonl",
                      url.lastPathComponent.localizedCaseInsensitiveContains(threadID)
                else {
                    continue
                }
                guard let data = try? Data(contentsOf: url) else {
                    continue
                }
                return ThreadTranscriptParser.transcript(fromRolloutData: data, threadRef: threadRef)
            }

            return nil
        }.value
    }

    private nonisolated static func localSubagentChildren(
        parentThreadID: String,
        codexHome: String,
        hostID: HostID
    ) async -> [ThreadRef] {
        await Task.detached(priority: .utility) {
            let sessionsURL = URL(fileURLWithPath: codexHome, isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(
                at: sessionsURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            var threadRefs: [ThreadRef] = []
            var seenThreadIDs = Set<String>()
            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension == "jsonl",
                      let firstLine = firstRolloutLine(at: url),
                      let threadRef = subagentChildThreadRef(
                        fromSessionMetaLine: firstLine,
                        parentThreadID: parentThreadID,
                        hostID: hostID
                      )
                else {
                    continue
                }

                let normalized = threadRef.threadID.lowercased()
                guard seenThreadIDs.insert(normalized).inserted else {
                    continue
                }
                threadRefs.append(threadRef)
            }

            return threadRefs.sorted { lhs, rhs in
                lhs.threadID < rhs.threadID
            }
        }.value
    }

    nonisolated static func subagentChildThreadRef(
        fromSessionMetaLine line: String,
        parentThreadID: String,
        hostID: HostID
    ) -> ThreadRef? {
        guard let data = line.data(using: .utf8),
              let event = try? JSONDecoder().decode(JSONValue.self, from: data),
              event["type"]?.stringValue == "session_meta",
              let payload = event["payload"],
              let childThreadID = payload["id"]?.stringValue,
              childThreadID.caseInsensitiveCompare(parentThreadID) != .orderedSame,
              let threadSpawn = payload["source"]?["subagent"]?["thread_spawn"],
              let recordedParentThreadID = threadSpawn["parent_thread_id"]?.stringValue,
              recordedParentThreadID.caseInsensitiveCompare(parentThreadID) == .orderedSame
        else {
            return nil
        }

        let cwd = payload["cwd"]?.stringValue ?? ""
        let nickname = threadSpawn["agent_nickname"]?.stringValue ?? payload["agent_nickname"]?.stringValue
        let role = threadSpawn["agent_role"]?.stringValue ?? payload["agent_role"]?.stringValue
        let name = nickname ?? role
        return ThreadRef(hostID: hostID, threadID: childThreadID, cwd: cwd, name: name)
    }

    private nonisolated static func firstRolloutLine(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? handle.close()
        }

        guard let data = try? handle.read(upToCount: 64 * 1024),
              !data.isEmpty
        else {
            return nil
        }

        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)
    }

    private func resolveLocalImageAttachments(in transcript: ThreadTranscript) async -> ThreadTranscript {
        await TranscriptAssetCache.resolveArtifacts(in: transcript) { [client] attachment in
            guard attachment.sourceHostID == transcript.threadRef.hostID else {
                return nil
            }

            guard let sourcePath = TranscriptAssetCache.sourceReadPath(for: attachment, in: transcript.threadRef) else {
                return nil
            }

            if let data = try await Self.localFileData(
                path: sourcePath,
                maxBytes: TranscriptAssetCache.maxCachedBytes(for: attachment)
            ) {
                return data
            }

            return try await client.readFile(path: sourcePath)
        }
    }

    private nonisolated static func localFileData(path: String, maxBytes: Int?) async throws -> Data? {
        try await Task.detached(priority: .utility) {
            let url = URL(fileURLWithPath: path)
            guard url.isFileURL else { return nil }

            if let maxBytes,
               let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileSizeKey]),
               let size = values.fileSize ?? values.totalFileSize,
               size > maxBytes {
                throw TranscriptAssetCache.ArtifactTooLargeError(byteCount: size)
            }

            let data = try Data(contentsOf: url)
            if let maxBytes, data.count > maxBytes {
                throw TranscriptAssetCache.ArtifactTooLargeError(byteCount: data.count)
            }
            return data
        }.value
    }

    public func archiveThread(_ threadRef: ThreadRef) async throws {
        guard threadRef.hostID == localHost.id else {
            throw CodexAppServerError.server("Archive is only available for threads on the connected local Codex runtime.")
        }

        _ = try await runtimeRequest(
            method: .archiveThread,
            params: .object([
                "threadId": .string(threadRef.threadID),
            ])
        )
        threadSummaries.removeAll {
            $0.hostID == threadRef.hostID && $0.threadID == threadRef.threadID
        }
    }

    public func forkThread(_ threadRef: ThreadRef, model: String?) async throws -> ThreadRef {
        guard threadRef.hostID == localHost.id else {
            throw CodexAppServerError.server("Fork is only available for threads on the connected local Codex runtime.")
        }

        var params: [String: JSONValue] = [
            "threadId": .string(threadRef.threadID),
            "cwd": .string(threadRef.cwd),
        ]
        if let model, !model.isEmpty {
            params["model"] = .string(model)
        }

        let result = try await runtimeRequest(method: .forkThread, params: .object(params))
        guard
            let thread = result["thread"],
            let threadID = thread["id"]?.stringValue,
            let cwd = thread["cwd"]?.stringValue ?? result["cwd"]?.stringValue
        else {
            throw CodexAppServerError.invalidResponse
        }

        let threadRef = ThreadRef(
            hostID: localHost.id,
            threadID: threadID,
            cwd: cwd,
            name: thread["name"]?.stringValue
        )
        threadSummaries.insert(threadRef, at: 0)
        return threadRef
    }

    public func restoreWorkflowEvents(_ events: [WorkflowEvent]) {
        workflowEvents = Array(events.sorted { $0.createdAt > $1.createdAt }.prefix(80))
    }

    public func recordWorkflowEvent(_ event: WorkflowEvent) {
        reduceRuntimeState(event: event)
        appendWorkflowEvent(event)
    }

    public func respondToAttentionRequest(_ request: RuntimeAttentionRequest, allow: Bool) async throws {
        guard request.supportsApprovalDecision else {
            throw CodexAppServerError.server("This request needs a typed response and cannot be answered with Allow/Deny.")
        }
        guard let requestID = request.requestID,
              let connectionID = request.connectionID else {
            throw CodexAppServerError.staleServerRequest
        }

        try await client.respondToServerRequest(
            id: requestID,
            result: request.appServerApprovalResult(allow: allow),
            connectionID: connectionID
        )
        completeAttentionRequest(request)
    }

    public func respondToAttentionRequest(_ request: RuntimeAttentionRequest, text: String) async throws {
        guard request.supportsTypedResponse else {
            throw CodexAppServerError.server("This request cannot be answered with typed input.")
        }
        guard let requestID = request.requestID,
              let connectionID = request.connectionID else {
            throw CodexAppServerError.staleServerRequest
        }

        try await client.respondToServerRequest(
            id: requestID,
            result: request.appServerTextResponseResult(text),
            connectionID: connectionID
        )
        completeAttentionRequest(request)
    }

    public func declineTypedAttentionRequest(_ request: RuntimeAttentionRequest) async throws {
        guard request.supportsTypedResponse else {
            throw CodexAppServerError.server("This request does not support typed responses.")
        }
        guard let requestID = request.requestID,
              let connectionID = request.connectionID else {
            throw CodexAppServerError.staleServerRequest
        }

        try await client.respondToServerRequest(
            id: requestID,
            result: request.appServerTextDeclineResult(),
            connectionID: connectionID
        )
        completeAttentionRequest(request)
    }

    private func record(_ notification: CodexServerNotification) {
        latestNotifications.insert(notification, at: 0)
        if latestNotifications.count > 20 {
            latestNotifications.removeLast()
        }

        reduceRuntimeState(notification: notification)

        if notification.method == "item/agentMessage/delta",
           let params = notification.params,
           let threadID = params["threadId"]?.stringValue,
           let delta = params["delta"]?.stringValue {
            liveAssistantTextByThreadID[threadID, default: ""] += delta
        }

        if notification.method == "turn/started",
           let threadID = notification.params?["threadId"]?.stringValue {
            liveAssistantTextByThreadID[threadID] = ""
            appendWorkflowEvent(
                .turnStarted,
                notification: notification,
                summary: "Turn started"
            )
        }

        if notification.method == "turn/completed",
           let threadID = notification.params?["threadId"]?.stringValue {
            liveAssistantTextByThreadID[threadID] = nil
            appendWorkflowEvent(
                .turnCompleted,
                notification: notification,
                summary: "Turn completed"
            )
        }

        if Self.isTurnFailureNotification(notification.method) {
            appendWorkflowEvent(
                .failed,
                notification: notification,
                summary: Self.attentionSummary(method: notification.method, params: notification.params)
            )
        }

        if let resolvedID = RuntimeAttentionRequest.resolvedRequestID(from: notification) {
            completeAttentionRequest(id: resolvedID)
        }

        if notification.method.contains("requestApproval")
            || notification.method.contains("requestUserInput")
            || notification.method.contains("elicitation/request") {
            guard let request = RuntimeAttentionRequest.appServerRequest(from: notification, hostID: localHost.id) else {
                return
            }
            applyAttentionRequest(request)
            appendWorkflowEvent(
                .needsInput,
                notification: notification,
                summary: request.summary
            )
        }
    }

    private func appendWorkflowEvent(_ kind: WorkflowEventKind, notification: CodexServerNotification, summary: String) {
        let params = notification.params
        let threadID = params?["threadId"]?.stringValue
            ?? params?["threadID"]?.stringValue
            ?? params?["thread_id"]?.stringValue
        let turnID = params?["turnId"]?.stringValue
            ?? params?["turnID"]?.stringValue
            ?? params?["turn_id"]?.stringValue
            ?? params?["turn"]?["id"]?.stringValue
            ?? params?["id"]?.stringValue

        let event = WorkflowEvent(
            kind: kind,
            hostID: localHost.id,
            threadID: threadID,
            turnID: turnID,
            method: notification.method,
            summary: summary
        )
        appendWorkflowEvent(event)
    }

    private func appendWorkflowEvent(_ event: WorkflowEvent) {
        reduceRuntimeState(event: event)
        if workflowEvents.contains(where: { existing in
            existing.dedupeKey == event.dedupeKey
        }) {
            return
        }

        workflowEvents.insert(event, at: 0)
        if workflowEvents.count > 80 {
            workflowEvents.removeLast()
        }
    }

    private func reduceRuntimeState(notification: CodexServerNotification) {
        guard let threadID = Self.threadID(from: notification.params) else {
            return
        }

        if notification.method == "item/agentMessage/delta",
           let delta = notification.params?["delta"]?.stringValue {
            upsertRuntimeState(hostID: localHost.id, threadID: threadID) { state in
                state.appendAssistantDelta(delta)
            }
            return
        }

        if notification.method.contains("item/") {
            let itemID = notification.params?["itemId"]?.stringValue
                ?? notification.params?["itemID"]?.stringValue
                ?? notification.params?["item_id"]?.stringValue
                ?? notification.params?["item"]?["id"]?.stringValue
            if let itemID {
                upsertRuntimeState(hostID: localHost.id, threadID: threadID) { state in
                    state.recordItemActivity(method: notification.method, itemID: itemID)
                }
            }
        }

        if let event = WorkflowEvent.appServerEvent(from: notification, hostID: localHost.id) {
            reduceRuntimeState(event: event)
        }
    }

    private func reduceRuntimeState(event: WorkflowEvent) {
        guard let threadID = event.threadID else { return }
        let hostID = event.hostID ?? localHost.id
        upsertRuntimeState(hostID: hostID, threadID: threadID) { state in
            state.apply(event: event, markUnread: event.kind != .turnStarted)
        }
    }

    private func upsertRuntimeState(
        hostID: HostID,
        threadID: String,
        update: (inout ThreadRuntimeState) -> Void
    ) {
        guard !threadID.isEmpty else { return }
        let key = ThreadRef.qualifiedID(hostID: hostID, threadID: threadID)
        var state = threadRuntimeStates[key] ?? ThreadRuntimeState(hostID: hostID, threadID: threadID)
        update(&state)
        threadRuntimeStates[key] = state
    }

    private func resolveAttentionRequest(id requestID: String) {
        for key in threadRuntimeStates.keys {
            guard var state = threadRuntimeStates[key] else { continue }
            state.resolveAttentionRequest(requestID)
            threadRuntimeStates[key] = state
        }
    }

    func applyAttentionRequest(_ request: RuntimeAttentionRequest) {
        if !pendingAttentionRequests.contains(where: { $0.id == request.id }) {
            pendingAttentionRequests.insert(request, at: 0)
        }
        upsertRuntimeState(hostID: request.hostID ?? localHost.id, threadID: request.threadID ?? "") { state in
            state.applyAttentionRequest(request)
        }
    }

    func completeAttentionRequest(_ request: RuntimeAttentionRequest) {
        pendingAttentionRequests.removeAll { $0.id == request.id }
        resolveAttentionRequest(id: request.id)
        if let requestID = request.requestID?.stringValue {
            resolveAttentionRequest(id: requestID)
        }
    }

    func completeAttentionRequest(id resolvedID: String) {
        pendingAttentionRequests.removeAll { request in
            request.requestID?.stringValue == resolvedID || request.id == resolvedID
        }
        resolveAttentionRequest(id: resolvedID)
    }

    private func updateHost(fromInitializeResult result: JSONValue, launchDescription: String) {
        localHost.codexHome = result["codexHome"]?.stringValue
        let platform = result["platformFamily"]?.stringValue ?? result["platformOs"]?.stringValue ?? "macOS"
        localHost.platform = Self.hostPlatform(from: platform)
        localHost.endpointDescription = launchDescription
    }

    private static func hostPlatform(from value: String) -> HostPlatform {
        let lowercased = value.lowercased()
        if lowercased.contains("mac") || lowercased.contains("darwin") { return .macOS }
        if lowercased.contains("windows") { return .windows }
        if lowercased.contains("linux") { return .linux }
        if lowercased.contains("ipad") { return .iPadOS }
        if lowercased.contains("ios") { return .iOS }
        return .unknown
    }

    private nonisolated static func modelOption(from value: JSONValue) -> CodexModelOption? {
        guard let id = value["id"]?.stringValue ?? value["model"]?.stringValue else {
            return nil
        }

        let efforts = (value["supportedReasoningEfforts"]?.arrayValue ?? [])
            .compactMap { effort in
                effort["reasoningEffort"]?.stringValue
                    ?? effort["effort"]?.stringValue
                    ?? effort["value"]?.stringValue
                    ?? effort.stringValue
            }

        return CodexModelOption(
            id: id,
            displayName: value["displayName"]?.stringValue ?? id,
            description: value["description"]?.stringValue ?? "",
            defaultReasoningEffort: value["defaultReasoningEffort"]?.stringValue ?? "medium",
            supportedReasoningEfforts: efforts.isEmpty ? ["low", "medium", "high", "xhigh"] : efforts,
            isDefault: value["isDefault"]?.boolValue ?? false
        )
    }

    public nonisolated static func modelOptions(from result: JSONValue) -> [CodexModelOption] {
        (result["data"]?.arrayValue ?? []).compactMap(Self.modelOption)
    }

    public nonisolated static func threadSearchParams(query: String, limit: Int) -> [String: JSONValue] {
        [
            "searchTerm": .string(query.trimmingCharacters(in: .whitespacesAndNewlines)),
            "limit": .number(Double(limit)),
        ]
    }

    nonisolated static func threadStartParams(
        cwd: String,
        model: String,
        permissions: CodexThreadPermissions
    ) -> [String: JSONValue] {
        var params: [String: JSONValue] = [
            "cwd": .string(cwd),
            "model": .string(model),
            "experimentalRawEvents": .bool(false),
        ]
        params.merge(permissions.threadParams()) { _, new in new }
        return params
    }

    nonisolated static func turnID(fromAppServerValue value: JSONValue) -> String? {
        AppServerNotificationNormalizer.turnID(from: value)
    }

    nonisolated static func interruptibleTurnID(
        fromTurnsListResult result: JSONValue,
        threadRef: ThreadRef
    ) -> String? {
        let turns = result["data"]?.arrayValue
            ?? result["turns"]?.arrayValue
            ?? result["items"]?.arrayValue
            ?? []

        if let runningTurn = turns.first(where: Self.isInterruptibleTurn),
           let turnID = turnID(fromAppServerValue: runningTurn),
           !isSyntheticTranscriptTurnID(turnID, threadRef: threadRef) {
            return turnID
        }

        return nil
    }

    private nonisolated static func isInterruptibleTurn(_ turn: JSONValue) -> Bool {
        let status = turn["status"]?.stringValue?.lowercased()
        if let status {
            return ["active", "inprogress", "in_progress", "running"].contains(status)
        }
        return turn["completedAt"] == nil
            && turn["completed_at"] == nil
            && turn["error"] == nil
            && turnID(fromAppServerValue: turn) != nil
    }

    private nonisolated static func isSyntheticTranscriptTurnID(_ turnID: String, threadRef: ThreadRef) -> Bool {
        turnID.hasPrefix("\(threadRef.qualifiedID)-turn-")
    }

    nonisolated static func threadRef(from value: JSONValue, hostID: HostID, cwdHint: String?) -> ThreadRef? {
        guard let threadID = value["id"]?.stringValue ?? value["threadId"]?.stringValue ?? value["threadID"]?.stringValue else {
            return nil
        }

        guard let cwd = value["cwd"]?.stringValue ?? value["workingDirectory"]?.stringValue ?? cwdHint else {
            return nil
        }

        let name = value["name"]?.stringValue
            ?? value["title"]?.stringValue
            ?? value["preview"]?.stringValue
        return ThreadRef(hostID: hostID, threadID: threadID, cwd: cwd, name: name)
    }

    nonisolated static func skillMentionCandidates(from result: JSONValue) -> [MentionCandidate] {
        let groupedSkills = (result["data"]?.arrayValue ?? []).flatMap { $0["skills"]?.arrayValue ?? [] }
        let directSkills = result["skills"]?.arrayValue ?? []

        return (groupedSkills + directSkills).compactMap { skill in
            guard
                skill["enabled"]?.boolValue != false,
                let name = skill["name"]?.stringValue,
                let path = skill["path"]?.stringValue
            else {
                return nil
            }

            let interface = skill["interface"]
            let displayName = interface?["displayName"]?.stringValue ?? name
            let description = interface?["shortDescription"]?.stringValue
                ?? skill["description"]?.stringValue
                ?? path
            let title = "$\(name)"

            return MentionCandidate(
                id: "skill:\(path)",
                kind: .skill,
                trigger: "$",
                label: title,
                title: title,
                subtitle: displayName == name ? description : "\(displayName) - \(description)",
                insertionText: "[$\(name)](\(path))"
            )
        }
    }

    nonisolated static func pluginMentionCandidates(from result: JSONValue) -> [MentionCandidate] {
        let marketplaces = result["marketplaces"]?.arrayValue ?? []

        return marketplaces.flatMap { marketplace in
            let marketplaceName = marketplace["name"]?.stringValue ?? "local"
            return (marketplace["plugins"]?.arrayValue ?? []).compactMap { plugin -> MentionCandidate? in
                guard
                    plugin["enabled"]?.boolValue != false,
                    plugin["installed"]?.boolValue != false
                else {
                    return nil
                }

                guard let name = plugin["name"]?.stringValue ?? Self.pluginName(from: plugin["id"]?.stringValue) else {
                    return nil
                }

                let id = plugin["id"]?.stringValue ?? "\(name)@\(marketplaceName)"
                let interface = plugin["interface"]
                let displayName = interface?["displayName"]?.stringValue ?? name
                let description = interface?["shortDescription"]?.stringValue ?? marketplaceName
                let title = "@\(name)"

                return MentionCandidate(
                    id: "plugin:\(id)",
                    kind: .plugin,
                    trigger: "@",
                    label: title,
                    title: title,
                    subtitle: displayName == name ? description : "\(displayName) - \(description)",
                    insertionText: "[@\(name)](plugin://\(id))"
                )
            }
        }
    }

    public nonisolated static func fileMentionCandidates(rootPath: String?, limit: Int = 120) async -> [MentionCandidate] {
        guard let rootPath, !rootPath.isEmpty else {
            return []
        }

        let scanTask = Task.detached(priority: .utility) {
            fileMentionCandidates(rootPath: rootPath, limit: limit)
        }
        return await withTaskCancellationHandler {
            await scanTask.value
        } onCancel: {
            scanTask.cancel()
        }
    }

    nonisolated static func fileMentionCandidates(rootPath: String, limit: Int = 120) -> [MentionCandidate] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var candidates: [MentionCandidate] = []
        for case let url as URL in enumerator {
            guard !Task.isCancelled else { return [] }
            let name = url.lastPathComponent
            let resourceValues = try? url.resourceValues(forKeys: keys)
            let isDirectory = resourceValues?.isDirectory == true
            let isRegularFile = resourceValues?.isRegularFile == true

            if isDirectory, ignoredMentionDirectoryNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }

            guard isDirectory || isRegularFile else {
                continue
            }

            let path = url.standardizedFileURL.path
            let relativePath = relativePath(for: path, rootPath: rootURL.path)
            let displayName = isDirectory ? "\(name)/" : name

            candidates.append(
                MentionCandidate(
                    id: "file:\(path)",
                    kind: .file,
                    trigger: "@",
                    label: "@\(relativePath)",
                    title: "@\(displayName)",
                    subtitle: relativePath,
                    insertionText: "[@\(displayName)](\(markdownTarget(for: path)))"
                )
            )

            if candidates.count >= limit {
                break
            }
        }

        return candidates.sorted {
            $0.subtitle.localizedStandardCompare($1.subtitle) == .orderedAscending
        }
    }

    private func runtimeRequest(
        method: AppServerMethod,
        params: JSONValue = .object([:])
    ) async throws -> JSONValue {
        let call = AppServerCall(method, params: params)
        try await ensureConnectedRuntime()

        do {
            return try await client.request(call)
        } catch {
            if method.replaySafety == .nonReplayableWrite,
               Self.isAmbiguousWriteFailure(error) {
                await reconcileAfterAmbiguousWrite(method: method, params: params)
                throw CodexAppServerError.ambiguousWrite(method: method.rawValue)
            }

            guard case CodexAppServerError.disconnected = error else { throw error }
            connectionState = .connecting
            localHost.status = .connecting
            statusMessage = "Restoring codex app-server connection"

            await connect()
            guard connectionState == .connected else {
                throw CodexAppServerError.disconnected
            }
            return try await client.request(call)
        }
    }

    private static func isAmbiguousWriteFailure(_ error: Error) -> Bool {
        guard let appServerError = error as? CodexAppServerError else {
            // Once request serialization has succeeded, an untyped error comes
            // from the process pipe and may represent a partial write.
            return true
        }
        switch appServerError {
        case .disconnected,
             .invalidResponse,
             .daemonProxyRequestTimedOut,
             .ambiguousWrite,
             .transport:
            return true
        case .unsupportedPlatform,
             .codexNotInstalled,
             .launchFailed,
             .daemonProxyHandshakeFailed,
             .staleServerRequest,
             .server:
            return false
        }
    }

    private func reconcileAfterAmbiguousWrite(
        method: AppServerMethod,
        params: JSONValue
    ) async {
        statusMessage = "Refreshing runtime state after an unconfirmed \(method.rawValue) request"
        await connect()
        guard connectionState == .connected else { return }

        try? await refreshThreads()
        guard method == .startTurn,
              let threadID = params["threadId"]?.stringValue,
              let threadRef = threadSummaries.first(where: { $0.threadID == threadID }) else {
            return
        }
        _ = try? await loadTranscript(for: threadRef)
    }

    private func runtimeRead(
        method: AppServerMethod,
        params: JSONValue = .object([:])
    ) async throws -> JSONValue {
        precondition(
            method.replaySafety == .replayableRead,
            "runtimeRead only accepts protocol-declared read methods"
        )
        return try await runtimeRequest(method: method, params: params)
    }

    private func ensureConnectedRuntime() async throws {
        if await client.isInitializedAndRunning() {
            connectionState = .connected
            localHost.status = .connected
            localHost.lastSeenAt = Date()
            return
        }

        await connect()
        guard connectionState == .connected else {
            throw CodexAppServerError.disconnected
        }
    }

    private func optionalRuntimeRequest(
        method: AppServerMethod,
        params: JSONValue = .object([:])
    ) async -> JSONValue? {
        do {
            return try await runtimeRead(method: method, params: params)
        } catch {
            guard params != .object([:]) else {
                return nil
            }
            return try? await runtimeRead(method: method)
        }
    }

    private nonisolated static func pluginName(from id: String?) -> String? {
        guard let id else { return nil }
        return id.split(separator: "@").first.map(String.init)
    }

    private nonisolated static func uniquedMentionCandidates(_ candidates: [MentionCandidate]) -> [MentionCandidate] {
        var seen: Set<String> = []
        var unique: [MentionCandidate] = []
        for candidate in candidates where seen.insert(candidate.id).inserted {
            unique.append(candidate)
        }
        return unique
    }

    private nonisolated static let ignoredMentionDirectoryNames: Set<String> = [
        ".build",
        ".git",
        ".swiftpm",
        "DerivedData",
        "dist",
        "node_modules",
    ]

    private nonisolated static func relativePath(for path: String, rootPath: String) -> String {
        guard path.hasPrefix(rootPath) else {
            return path
        }

        var relativePath = String(path.dropFirst(rootPath.count))
        if relativePath.hasPrefix("/") {
            relativePath.removeFirst()
        }
        return relativePath
    }

    private nonisolated static func markdownTarget(for path: String) -> String {
        let needsAngleBrackets = path.unicodeScalars.contains { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar)
                || scalar.value == 40
                || scalar.value == 41
        }
        guard needsAngleBrackets else {
            return path
        }
        return "<\(path.replacingOccurrences(of: ">", with: "%3E"))>"
    }

    public nonisolated static func catalogParams(cwd: String?) -> JSONValue {
        JSONValue.objectFrom(
            ("cwds", cwd.map { .array([.string($0)]) })
        )
    }

    public nonisolated static func catalogMentionCandidates(
        skillsResult: JSONValue?,
        pluginsResult: JSONValue?,
        fileCandidates: [MentionCandidate]
    ) -> [MentionCandidate] {
        let candidates = uniquedMentionCandidates(
            [MapofAgentsWorkflowBridgeSkill.mentionCandidate]
                + (skillsResult.map(skillMentionCandidates) ?? [])
                + (pluginsResult.map(pluginMentionCandidates) ?? [])
                + fileCandidates
        )
        return candidates.sorted {
            if $0.kind == $1.kind {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.kind.sortPriority < $1.kind.sortPriority
        }
    }

    public nonisolated static func fileMentionCandidate(
        path: String,
        rootPath: String,
        displayName: String,
        relativePath: String
    ) -> MentionCandidate {
        MentionCandidate(
            id: "file:\(path)",
            kind: .file,
            trigger: "@",
            label: "@\(relativePath)",
            title: "@\(displayName)",
            subtitle: relativePath,
            insertionText: "[@\(displayName)](\(markdownTarget(for: path)))"
        )
    }

    private func updateDiagnostic(_ id: String, status: RuntimeDiagnosticStatus, detail: String = "") {
        guard let index = runtimeDiagnostics.firstIndex(where: { $0.id == id }) else { return }
        runtimeDiagnostics[index].status = status
        runtimeDiagnostics[index].detail = detail
    }

    private static func attentionSummary(method: String, params: JSONValue?) -> String {
        if let command = params?["command"]?.stringValue {
            return command
        }
        if let prompt = params?["prompt"]?.stringValue {
            return prompt
        }
        if let tool = params?["tool"]?.stringValue {
            return tool
        }
        return method
    }

    private static func threadID(from params: JSONValue?) -> String? {
        params?["threadId"]?.stringValue
            ?? params?["threadID"]?.stringValue
            ?? params?["thread_id"]?.stringValue
    }

    static func shouldRetryConnectionWithFallback(after error: Error) -> Bool {
        if let appServerError = error as? CodexAppServerError {
            return appServerError.isStdioFallbackEligible
        }

        let message = error.localizedDescription.lowercased()
        return message.contains("timed out")
            && message.contains("codex app server")
    }

    private static func isTurnFailureNotification(_ method: String) -> Bool {
        let lowercased = method.lowercased()
        return lowercased.hasPrefix("turn/")
            && (lowercased.contains("fail") || lowercased.contains("error"))
    }
}

private extension MentionKind {
    var sortPriority: Int {
        switch self {
        case .skill:
            return 0
        case .plugin:
            return 1
        case .folder:
            return 2
        case .file:
            return 3
        case .thread:
            return 4
        }
    }
}
