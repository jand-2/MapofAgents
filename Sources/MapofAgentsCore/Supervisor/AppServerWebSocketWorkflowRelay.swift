import Foundation

public struct AppServerRelayEndpoint: Codable, Identifiable, Hashable, Sendable {
    public var id: HostID
    public var name: String
    public var url: URL
    public var bearerToken: String?

    public init(id: HostID, name: String, url: URL, bearerToken: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.bearerToken = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public init?(machine: SupervisorMachine) {
        guard machine.status == .connected,
              let url = URL(string: machine.endpointDescription),
              Self.isAppServerWebSocketURL(url) else {
            return nil
        }

        self.init(id: machine.id, name: machine.name, url: url)
    }

    public static func isAppServerWebSocketURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "ws" || scheme == "wss"
    }

    public var connectionSecurityError: String? {
        Self.connectionSecurityError(url: url, bearerToken: bearerToken)
    }

    public static func connectionSecurityError(url: URL, bearerToken: String?) -> String? {
        guard isAppServerWebSocketURL(url) else {
            return "Codex App Server endpoints must use ws:// or wss://."
        }

        let token = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let scheme = url.scheme?.lowercased()
        let isLoopback = isLoopbackWebSocketURL(url)

        if scheme == "ws", !isLoopback {
            if token != nil {
                return "Bearer-token App Server endpoints must use wss:// unless they are loopback."
            }
            return "Remote App Server endpoints must use wss:// with a bearer token, or loopback ws://."
        }

        if !isLoopback, token == nil {
            return "Remote App Server endpoints require a bearer token."
        }

        return nil
    }

    public static func isLoopbackWebSocketURL(_ url: URL) -> Bool {
        guard isAppServerWebSocketURL(url),
              let host = url.host()?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
              !host.isEmpty else {
            return false
        }
        let normalized = host.lowercased()
        return normalized == "localhost" || normalized == "127.0.0.1" || normalized == "::1"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case bearerToken
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedToken = try container.decodeIfPresent(String.self, forKey: .bearerToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let token = decodedToken == Self.redactedBearerTokenPlaceholder ? nil : decodedToken
        self.init(
            id: try container.decode(HostID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            url: try container.decode(URL.self, forKey: .url),
            bearerToken: token
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        if bearerToken?.isEmpty == false {
            try container.encode(Self.redactedBearerTokenPlaceholder, forKey: .bearerToken)
        }
    }

    private static let redactedBearerTokenPlaceholder = "__redacted__"
}

public struct AppServerTranscriptLoadResult: Sendable {
    public var transcript: ThreadTranscript
    public var rolloutPath: String?

    public init(transcript: ThreadTranscript, rolloutPath: String?) {
        self.transcript = transcript
        self.rolloutPath = rolloutPath
    }
}

public actor AppServerWebSocketWorkflowRelay {
    private let endpoint: AppServerRelayEndpoint
    private let supervisor: WorkflowSupervisor
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var isStarted = false
    private var isConnected = false
    private var desiredThreads: [String: ThreadRef] = [:]
    private var workflowDesiredThreads: [String: ThreadRef] = [:]
    private var subscriptionOwners: [String: [String: ThreadRef]] = [:]
    private var subscribedThreadIDs: Set<String> = []
    private var pendingSubscriptionThreadIDs: Set<String> = []
    private var subscriptionAttempts: [String: Int] = [:]
    private var subscriptionRetryTasks: [String: Task<Void, Never>] = [:]
    private let maxSubscriptionAttempts = 6
    private var reconnectAttempts = 0
    private var lastFailureMessageValue: String?
    private var reportsConnectionFailures: Bool
    private let onAttentionRequest: (@Sendable (RuntimeAttentionRequest) -> Void)?
    private let onAttentionResolved: (@Sendable (HostID, String) -> Void)?
    private let onNotification: (@Sendable (HostID, CodexServerNotification) -> Void)?
    private let onDisconnected: (@Sendable (HostID) -> Void)?

    public init(
        endpoint: AppServerRelayEndpoint,
        supervisor: WorkflowSupervisor,
        reportsConnectionFailures: Bool = true,
        onAttentionRequest: (@Sendable (RuntimeAttentionRequest) -> Void)? = nil,
        onAttentionResolved: (@Sendable (HostID, String) -> Void)? = nil,
        onNotification: (@Sendable (HostID, CodexServerNotification) -> Void)? = nil,
        onDisconnected: (@Sendable (HostID) -> Void)? = nil
    ) {
        self.endpoint = endpoint
        self.supervisor = supervisor
        self.reportsConnectionFailures = reportsConnectionFailures
        self.onAttentionRequest = onAttentionRequest
        self.onAttentionResolved = onAttentionResolved
        self.onNotification = onNotification
        self.onDisconnected = onDisconnected
    }

    public func start() async -> Bool {
        guard !isStarted else { return isConnected }
        isStarted = true

        await supervisor.upsertMachine(
            SupervisorMachine(
                id: endpoint.id,
                name: endpoint.name,
                endpointDescription: endpoint.url.absoluteString,
                status: .connecting
            )
        )

        return await connectWebSocket()
    }

    private func connectWebSocket() async -> Bool {
        if let securityError = endpoint.connectionSecurityError {
            await markFailed(CodexAppServerError.transport(securityError))
            return false
        }

        var urlRequest = URLRequest(url: endpoint.url)
        if let bearerToken = endpoint.bearerToken, !bearerToken.isEmpty {
            urlRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        let task = URLSession.shared.webSocketTask(with: urlRequest)
        webSocketTask = task
        task.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        do {
            let initializeResult = try await request(
                method: "initialize",
                params: .object([
                    "clientInfo": .object([
                        "name": .string("mapofagents-supervisor"),
                        "title": .string("mapofagents supervisor"),
                        "version": .string("0.1.0"),
                    ]),
                    "capabilities": .object([
                        "experimentalApi": .bool(true),
                    ]),
                ])
            )

            guard AppServerEndpointVerifier.isTrustedInitializeResult(initializeResult) else {
                throw CodexAppServerError.invalidResponse
            }

            try await notify(method: "initialized")
            isConnected = true
            reconnectAttempts = 0
            lastFailureMessageValue = nil
            await supervisor.upsertMachine(machine(from: initializeResult, status: .connected))
            startPingLoop()
            await subscribeDesiredThreads()
            return true
        } catch {
            closeWebSocketAfterFailedHandshake()
            await markFailed(error)
            return false
        }
    }

    public func stop(markDisconnected: Bool = true) async {
        isStarted = false
        isConnected = false
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTask?.cancel()
        pingTask = nil
        subscriptionRetryTasks.values.forEach { $0.cancel() }
        subscriptionRetryTasks.removeAll()
        pendingSubscriptionThreadIDs.removeAll()
        subscribedThreadIDs.removeAll()
        subscriptionAttempts.removeAll()
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        failPendingRequests()
        onDisconnected?(endpoint.id)
        if markDisconnected {
            await supervisor.updateMachineStatus(endpoint.id, status: .disconnected)
        }
    }

    func lastFailureMessage() -> String? {
        lastFailureMessageValue
    }

    func setReportsConnectionFailures(_ reportsConnectionFailures: Bool) {
        self.reportsConnectionFailures = reportsConnectionFailures
    }

    public func updateWorkflowThreads(_ threadRefs: [ThreadRef]) async {
        var nextThreads: [String: ThreadRef] = [:]
        for threadRef in threadRefs where threadRef.hostID == endpoint.id {
            nextThreads[threadRef.threadID] = threadRef
        }

        workflowDesiredThreads = nextThreads
        let previousThreadIDs = Set(desiredThreads.keys)
        rebuildDesiredThreads()
        let removedThreadIDs = previousThreadIDs.subtracting(desiredThreads.keys)

        for threadID in removedThreadIDs {
            await unsubscribe(threadID: threadID)
        }

        guard isStarted, isConnected else { return }
        await subscribeDesiredThreads()
    }

    public func retainThreadSubscription(_ threadRef: ThreadRef, owner: String) async {
        guard threadRef.hostID == endpoint.id else { return }
        let previousThreadIDs = Set(desiredThreads.keys)
        var owners = subscriptionOwners[threadRef.threadID] ?? [:]
        owners[owner] = threadRef
        subscriptionOwners[threadRef.threadID] = owners
        rebuildDesiredThreads()

        if !previousThreadIDs.contains(threadRef.threadID), isStarted, isConnected {
            await subscribeIfNeeded(to: threadRef)
        }
    }

    public func releaseThreadSubscription(threadID: String, owner: String) async {
        var owners = subscriptionOwners[threadID] ?? [:]
        owners.removeValue(forKey: owner)
        subscriptionOwners[threadID] = owners.isEmpty ? nil : owners

        let previousThreadIDs = Set(desiredThreads.keys)
        rebuildDesiredThreads()
        if previousThreadIDs.contains(threadID), desiredThreads[threadID] == nil {
            await unsubscribe(threadID: threadID)
        }
    }

    private func rebuildDesiredThreads() {
        var nextThreads = workflowDesiredThreads
        for (threadID, owners) in subscriptionOwners {
            if let threadRef = owners.values.sorted(by: { $0.qualifiedID < $1.qualifiedID }).first {
                nextThreads[threadID] = nextThreads[threadID] ?? threadRef
            }
        }
        desiredThreads = nextThreads
    }

    public func createThread(
        cwd: String,
        name: String,
        model: String,
        reasoningEffort: String,
        permissions: CodexThreadPermissions = .default,
        initialPrompt: String
    ) async throws -> ThreadRef {
        try await ensureConnected()
        let result = try await request(
            method: "thread/start",
            params: .object(CodexRuntimeStore.threadStartParams(cwd: cwd, model: model, permissions: permissions))
        )

        guard
            let thread = result["thread"],
            let threadID = thread["id"]?.stringValue,
            let threadCwd = thread["cwd"]?.stringValue
        else {
            throw CodexAppServerError.invalidResponse
        }

        if !name.isEmpty {
            _ = try await request(
                method: "thread/name/set",
                params: .object([
                    "threadId": .string(threadID),
                    "name": .string(name),
                ])
            )
        }

        let threadRef = ThreadRef(
            hostID: endpoint.id,
            threadID: threadID,
            cwd: threadCwd,
            name: name.isEmpty ? nil : name
        )

        let trimmedPrompt = initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            try await sendMessage(
                trimmedPrompt,
                to: threadRef,
                model: model,
                reasoningEffort: reasoningEffort,
                permissions: permissions
            )
        }

        return threadRef
    }

    public func listModels() async throws -> [CodexModelOption] {
        try await ensureConnected()
        let result = try await request(
            method: "model/list",
            params: .object([
                "limit": .number(100),
                "includeHidden": .bool(false),
            ])
        )
        return CodexRuntimeStore.modelOptions(from: result)
    }

    public func mentionCandidates(cwd: String?) async -> [MentionCandidate] {
        do {
            try await ensureConnected()
        } catch {
            return []
        }

        let catalogParams = CodexRuntimeStore.catalogParams(cwd: cwd)
        async let skillsResult = optionalRequest(method: "skills/list", params: catalogParams)
        async let pluginsResult = optionalRequest(method: "plugin/list", params: catalogParams)
        async let filesResult = remoteFileMentionCandidates(rootPath: cwd)

        return await CodexRuntimeStore.catalogMentionCandidates(
            skillsResult: skillsResult,
            pluginsResult: pluginsResult,
            fileCandidates: filesResult
        )
    }

    public func threadCatalogEntries(limit: Int = 100, archived: Bool = false) async throws -> [ThreadCatalogEntry] {
        try await ensureConnected()
        let result = try await request(
            method: "thread/list",
            params: .object([
                "limit": .number(Double(limit)),
                "archived": .bool(archived),
            ])
        )

        return (result["data"]?.arrayValue ?? []).compactMap { value in
            ThreadCatalogEntry.appServerThread(
                from: value,
                hostID: endpoint.id,
                hostName: endpoint.name
            )
        }
    }

    public func searchThreadCatalog(query: String, limit: Int = 50) async throws -> [ThreadCatalogEntry] {
        try await ensureConnected()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let result = try await request(
            method: "thread/search",
            params: .object(CodexRuntimeStore.threadSearchParams(query: trimmed, limit: limit))
        )

        return (result["data"]?.arrayValue ?? result["threads"]?.arrayValue ?? []).compactMap { value in
            ThreadCatalogEntry.appServerSearchResult(
                from: value,
                hostID: endpoint.id,
                hostName: endpoint.name
            )
        }
    }

    public func loadedThreadCatalogEntries(limit: Int = 100) async -> [ThreadCatalogEntry] {
        do {
            try await ensureConnected()
        } catch {
            return []
        }

        guard let result = try? await request(
            method: "thread/loaded/list",
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
                entries.append(
                    ThreadCatalogEntry(
                        threadRef: ThreadRef(hostID: endpoint.id, threadID: threadID, cwd: "", name: nil),
                        hostName: endpoint.name,
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

    private func readThreadCatalogEntry(threadID: String, cwdHint: String?) async throws -> ThreadCatalogEntry? {
        let result = try await request(
            method: "thread/read",
            params: .object([
                "threadId": .string(threadID),
            ])
        )
        let threadValue = result["thread"] ?? result
        if let entry = ThreadCatalogEntry.appServerThread(
            from: threadValue,
            hostID: endpoint.id,
            hostName: endpoint.name
        ) {
            return entry
        }
        guard let threadRef = CodexRuntimeStore.threadRef(from: threadValue, hostID: endpoint.id, cwdHint: cwdHint) else {
            return nil
        }
        return ThreadCatalogEntry(
            threadRef: threadRef,
            hostName: endpoint.name,
            source: "loaded"
        )
    }

    public func loadTranscript(for threadRef: ThreadRef) async throws -> ThreadTranscript {
        try await loadTranscriptWithRolloutPath(for: threadRef).transcript
    }

    public func loadOlderTranscriptPageWithRolloutPath(
        for threadRef: ThreadRef,
        cursor: String
    ) async throws -> AppServerTranscriptLoadResult {
        try await loadTranscriptWithRolloutPath(for: threadRef, cursor: cursor)
    }

    public func resolveThread(threadID: String, cwdHint: String? = nil) async -> ThreadRef? {
        do {
            try await ensureConnected()
        } catch {
            return nil
        }

        if let thread = try? await readThread(threadID: threadID, cwdHint: cwdHint) {
            return thread
        }

        if let thread = try? await findThreadInList(threadID: threadID, limit: 200) {
            return thread
        }

        return nil
    }

    public func loadTranscriptWithRolloutPath(
        for threadRef: ThreadRef,
        cursor: String? = nil
    ) async throws -> AppServerTranscriptLoadResult {
        try await ensureConnected()
        let threadReadResult = try? await request(
            method: "thread/read",
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

        let result = try await request(
            method: "thread/turns/list",
            params: .object(params)
        )
        return AppServerTranscriptLoadResult(
            transcript: ThreadTranscriptParser.transcript(from: result, threadRef: threadRef).sortedChronologically(),
            rolloutPath: threadReadResult?["thread"]?["path"]?.stringValue ?? threadReadResult?["path"]?.stringValue
        )
    }

    private func readThread(threadID: String, cwdHint: String?) async throws -> ThreadRef? {
        let result = try await request(
            method: "thread/read",
            params: .object([
                "threadId": .string(threadID),
            ])
        )
        return CodexRuntimeStore.threadRef(from: result["thread"] ?? result, hostID: endpoint.id, cwdHint: cwdHint)
    }

    private func findThreadInList(threadID: String, limit: Int) async throws -> ThreadRef? {
        let result = try await request(
            method: "thread/list",
            params: .object([
                "limit": .number(Double(limit)),
                "archived": .bool(false),
            ])
        )

        return (result["data"]?.arrayValue ?? [])
            .compactMap { CodexRuntimeStore.threadRef(from: $0, hostID: endpoint.id, cwdHint: nil) }
            .first { $0.threadID.caseInsensitiveCompare(threadID) == .orderedSame }
    }

    public func readFile(path: String) async throws -> Data {
        try await ensureConnected()
        let result = try await request(
            method: "fs/readFile",
            params: .object([
                "path": .string(path),
            ])
        )
        return try CodexAppServerClient.fileData(fromReadFileResponse: result)
    }

    public func createDirectory(path: String, recursive: Bool = true) async throws {
        try await ensureConnected()
        _ = try await request(
            method: "fs/createDirectory",
            params: .object([
                "path": .string(path),
                "recursive": .bool(recursive),
            ])
        )
    }

    public func writeFile(path: String, data: Data) async throws {
        try await ensureConnected()
        _ = try await request(
            method: "fs/writeFile",
            params: .object([
                "path": .string(path),
                "dataBase64": .string(data.base64EncodedString()),
            ])
        )
    }

    public func interruptThread(_ threadRef: ThreadRef, activeTurnID: String?) async throws -> String {
        try await ensureConnected()
        let turnID: String
        if let activeTurnID,
           !Self.isSyntheticTranscriptTurnID(activeTurnID, threadRef: threadRef) {
            turnID = activeTurnID
        } else {
            turnID = try await interruptibleTurnID(for: threadRef)
        }

        _ = try await request(
            method: "turn/interrupt",
            params: .object([
                "threadId": .string(threadRef.threadID),
                "turnId": .string(turnID),
            ])
        )
        return turnID
    }

    public func sendMessage(
        _ text: String,
        to threadRef: ThreadRef,
        model: String?,
        reasoningEffort: String?,
        permissions: CodexThreadPermissions? = nil,
        attachments: [ChatInputAttachment] = []
    ) async throws {
        try await ensureConnected()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else {
            return
        }

        let resolvedAttachments = try await prepareRemoteAttachments(attachments, for: threadRef)
        let inputItems = ChatInputAttachmentService.inputItems(
            text: text,
            attachments: resolvedAttachments
        )
        guard !inputItems.isEmpty else { return }

        var resumeParams: [String: JSONValue] = [
            "threadId": .string(threadRef.threadID),
            "cwd": .string(threadRef.cwd),
        ]
        if let permissions {
            resumeParams.merge(permissions.threadParams()) { _, new in new }
        }

        _ = try? await request(method: "thread/resume", params: .object(resumeParams))

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

        _ = try await request(method: "turn/start", params: .object(params))
    }

    private func interruptibleTurnID(for threadRef: ThreadRef) async throws -> String {
        let result = try await request(
            method: "thread/turns/list",
            params: .object([
                "threadId": .string(threadRef.threadID),
                "limit": .number(5),
                "sortDirection": .string("desc"),
                "itemsView": .string("full"),
            ])
        )
        if let turnID = CodexRuntimeStore.interruptibleTurnID(fromTurnsListResult: result, threadRef: threadRef) {
            return turnID
        }

        throw CodexAppServerError.server("No running turn id was available for \(threadRef.threadID). Refresh the thread and try stopping it again.")
    }

    private static func isSyntheticTranscriptTurnID(_ turnID: String, threadRef: ThreadRef) -> Bool {
        turnID.hasPrefix("\(threadRef.qualifiedID)-turn-")
    }

    private func prepareRemoteAttachments(
        _ attachments: [ChatInputAttachment],
        for threadRef: ThreadRef
    ) async throws -> [ResolvedChatInputAttachment] {
        guard !attachments.isEmpty else { return [] }
        let directory = ChatInputAttachmentService.remoteAttachmentDirectory(
            cwd: threadRef.cwd,
            threadID: threadRef.threadID
        )
        try await createDirectory(path: directory)

        var resolved: [ResolvedChatInputAttachment] = []
        for attachment in attachments {
            let name = ChatInputAttachmentService.sanitizedFileName(attachment.name)
            let data = try ChatInputAttachmentService.attachmentData(attachment)
            let path = ChatInputAttachmentService.joinedPath(directory: directory, fileName: name)
            try await writeFile(path: path, data: data)
            let mimeType = attachment.mimeType ?? ChatInputAttachmentService.inferredMimeType(forFileName: name)
            resolved.append(
                ResolvedChatInputAttachment(
                    id: attachment.id,
                    kind: attachment.kind,
                    name: name,
                    mimeType: mimeType,
                    path: path,
                    byteCount: data.count
                )
            )
        }
        return resolved
    }

    public func archiveThread(_ threadRef: ThreadRef) async throws {
        try await ensureConnected()
        _ = try await request(
            method: "thread/archive",
            params: .object([
                "threadId": .string(threadRef.threadID),
            ])
        )
    }

    public func respondToServerRequest(id: JSONRPCRequestID, result: JSONValue) async throws {
        try await ensureConnected()
        try await send(.object([
            "id": id.jsonValue,
            "result": result,
        ]))
    }

    public func forkThread(_ threadRef: ThreadRef, model: String?) async throws -> ThreadRef {
        try await ensureConnected()
        var params: [String: JSONValue] = [
            "threadId": .string(threadRef.threadID),
            "cwd": .string(threadRef.cwd),
        ]
        if let model, !model.isEmpty {
            params["model"] = .string(model)
        }

        let result = try await request(method: "thread/fork", params: .object(params))
        guard
            let thread = result["thread"],
            let threadID = thread["id"]?.stringValue,
            let cwd = thread["cwd"]?.stringValue ?? result["cwd"]?.stringValue
        else {
            throw CodexAppServerError.invalidResponse
        }

        return ThreadRef(
            hostID: endpoint.id,
            threadID: threadID,
            cwd: cwd,
            name: thread["name"]?.stringValue ?? threadRef.name
        )
    }

    private func receiveLoop() async {
        do {
            while !Task.isCancelled {
                guard let webSocketTask else {
                    return
                }
                let message = try await webSocketTask.receive()
                try handle(message)
            }
        } catch {
            guard isStarted else { return }
            await markFailed(error)
        }
    }

    private func startPingLoop() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await self?.sendPing()
            }
        }
    }

    private func sendPing() {
        guard isStarted, isConnected, let webSocketTask else { return }
        webSocketTask.sendPing { [weak self] error in
            guard let error else { return }
            Task {
                await self?.markFailed(error)
            }
        }
    }

    private func request(method: String, params: JSONValue = .object([:])) async throws -> JSONValue {
        let requestID = nextRequestID
        nextRequestID += 1

        let message: JSONValue = .object([
            "id": .number(Double(requestID)),
            "method": .string(method),
            "params": params,
        ])

        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(CodexAppServerClient.timeoutSeconds(for: method) ?? 20))
            await self?.timeoutRequest(id: requestID, method: method)
        }

        defer {
            timeoutTask.cancel()
        }

        return try await withCheckedThrowingContinuation { continuation in
            pending[requestID] = continuation
            Task { [weak self] in
                do {
                    try await self?.send(message)
                } catch {
                    await self?.failRequest(id: requestID, error: error)
                }
            }
        }
    }

    private func optionalRequest(method: String, params: JSONValue = .object([:])) async -> JSONValue? {
        do {
            return try await request(method: method, params: params)
        } catch {
            guard params != .object([:]) else {
                return nil
            }
            return try? await request(method: method)
        }
    }

    private func remoteFileMentionCandidates(rootPath: String?, limit: Int = 120) async -> [MentionCandidate] {
        guard let rootPath, !rootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        var candidates: [MentionCandidate] = []
        var queue: [(path: String, relativePath: String)] = [(rootPath, "")]
        var visited = Set<String>()

        while !queue.isEmpty, candidates.count < limit {
            let current = queue.removeFirst()
            guard visited.insert(current.path).inserted else { continue }

            guard let result = try? await request(
                method: "fs/readDirectory",
                params: .object(["path": .string(current.path)])
            ) else {
                continue
            }

            let entries = (result["entries"]?.arrayValue ?? [])
                .compactMap(RemoteDirectoryEntry.init(value:))
                .sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }

            for entry in entries where candidates.count < limit {
                guard !entry.fileName.hasPrefix(".") else { continue }
                if entry.isDirectory, Self.ignoredMentionDirectoryNames.contains(entry.fileName) {
                    continue
                }
                guard entry.isDirectory || entry.isFile else { continue }

                let path = Self.joinPath(current.path, entry.fileName)
                let relativePath = current.relativePath.isEmpty
                    ? entry.fileName
                    : "\(current.relativePath)/\(entry.fileName)"
                let displayName = entry.isDirectory ? "\(entry.fileName)/" : entry.fileName
                candidates.append(
                    CodexRuntimeStore.fileMentionCandidate(
                        path: path,
                        rootPath: rootPath,
                        displayName: displayName,
                        relativePath: relativePath
                    )
                )

                if entry.isDirectory {
                    queue.append((path, relativePath))
                }
            }
        }

        return candidates
    }

    private func notify(method: String, params: JSONValue? = nil) async throws {
        var body: [String: JSONValue] = ["method": .string(method)]
        if let params {
            body["params"] = params
        }
        try await send(.object(body))
    }

    private func send(_ value: JSONValue) async throws {
        guard let webSocketTask else {
            throw CodexAppServerError.disconnected
        }
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CodexAppServerError.invalidResponse
        }
        try await webSocketTask.send(.string(text))
    }

    private func ensureConnected() async throws {
        guard isStarted else {
            throw CodexAppServerError.disconnected
        }
        if isConnected {
            return
        }
        await reconnect()
        guard isConnected else {
            throw CodexAppServerError.disconnected
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) throws {
        let data: Data
        switch message {
        case .data(let messageData):
            data = messageData
        case .string(let text):
            data = Data(text.utf8)
        @unknown default:
            return
        }

        guard
            let value = try? JSONDecoder().decode(JSONValue.self, from: data),
            let object = value.objectValue
        else {
            return
        }

        if let requestID = JSONRPCRequestID(object["id"]), let method = object["method"]?.stringValue {
            let notification = CodexServerNotification(
                method: method,
                params: object["params"],
                requestID: requestID
            )
            handleNotification(notification)
            return
        }

        if let id = object["id"]?.intValue {
            let continuation = pending.removeValue(forKey: id)
            if let error = object["error"] {
                continuation?.resume(throwing: CodexAppServerError.server(error.readableDescription))
            } else {
                continuation?.resume(returning: object["result"] ?? .null)
            }
            return
        }

        guard let method = object["method"]?.stringValue else {
            return
        }

        handleNotification(
            CodexServerNotification(
                method: method,
                params: object["params"]
            )
        )
    }

    private func handleNotification(_ notification: CodexServerNotification) {
        onNotification?(endpoint.id, notification)
        handleSubscriptionSignal(notification)
        handleAttentionSignal(notification)
        ingest(notification)
    }

    private func handleAttentionSignal(_ notification: CodexServerNotification) {
        if let resolvedID = RuntimeAttentionRequest.resolvedRequestID(from: notification) {
            onAttentionResolved?(endpoint.id, resolvedID)
            return
        }

        guard let request = RuntimeAttentionRequest.appServerRequest(from: notification, hostID: endpoint.id) else {
            return
        }
        onAttentionRequest?(request)
    }

    private func ingest(_ notification: CodexServerNotification) {
        guard let event = WorkflowEvent.appServerEvent(from: notification, hostID: endpoint.id) else {
            return
        }

        Task {
            await supervisor.ingest(event, from: endpoint.id)
        }
    }

    private func subscribeDesiredThreads() async {
        for threadRef in desiredThreads.values.sorted(by: { $0.threadID < $1.threadID }) {
            await subscribeIfNeeded(to: threadRef)
        }
    }

    private func subscribeIfNeeded(to threadRef: ThreadRef) async {
        guard isStarted, isConnected else { return }
        guard desiredThreads[threadRef.threadID] == threadRef else { return }
        guard !subscribedThreadIDs.contains(threadRef.threadID) else { return }
        guard !pendingSubscriptionThreadIDs.contains(threadRef.threadID) else { return }

        pendingSubscriptionThreadIDs.insert(threadRef.threadID)
        defer {
            pendingSubscriptionThreadIDs.remove(threadRef.threadID)
        }

        do {
            _ = try await request(
                method: "thread/resume",
                params: .object([
                    "threadId": .string(threadRef.threadID),
                    "cwd": .string(threadRef.cwd),
                ])
            )

            guard desiredThreads[threadRef.threadID] == threadRef else {
                _ = try? await request(
                    method: "thread/unsubscribe",
                    params: .object(["threadId": .string(threadRef.threadID)])
                )
                return
            }

            subscribedThreadIDs.insert(threadRef.threadID)
            subscriptionAttempts[threadRef.threadID] = 0
            subscriptionRetryTasks[threadRef.threadID]?.cancel()
            subscriptionRetryTasks[threadRef.threadID] = nil
        } catch {
            subscribedThreadIDs.remove(threadRef.threadID)
            scheduleSubscriptionRetry(for: threadRef.threadID, after: error)
        }
    }

    private func unsubscribe(threadID: String) async {
        subscriptionRetryTasks[threadID]?.cancel()
        subscriptionRetryTasks[threadID] = nil
        subscriptionAttempts[threadID] = nil
        pendingSubscriptionThreadIDs.remove(threadID)

        let wasSubscribed = subscribedThreadIDs.remove(threadID) != nil
        guard isConnected, wasSubscribed else { return }

        _ = try? await request(
            method: "thread/unsubscribe",
            params: .object(["threadId": .string(threadID)])
        )
    }

    private func handleSubscriptionSignal(_ notification: CodexServerNotification) {
        guard
            let threadID = Self.threadID(from: notification.params),
            desiredThreads[threadID] != nil,
            !subscribedThreadIDs.contains(threadID),
            !pendingSubscriptionThreadIDs.contains(threadID)
        else {
            return
        }

        switch notification.method {
        case "thread/started", "thread/status/changed", "thread/name/updated":
            scheduleSubscriptionPrompt(for: threadID)
        default:
            return
        }
    }

    private func scheduleSubscriptionPrompt(for threadID: String) {
        guard isStarted, isConnected, desiredThreads[threadID] != nil else { return }
        guard subscriptionRetryTasks[threadID] == nil else { return }

        subscriptionRetryTasks[threadID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            await self?.retrySubscription(threadID: threadID)
        }
    }

    private func scheduleSubscriptionRetry(for threadID: String, after error: Error) {
        guard isStarted, isConnected, desiredThreads[threadID] != nil else { return }
        guard shouldRetrySubscription(after: error) else { return }

        let attempts = (subscriptionAttempts[threadID] ?? 0) + 1
        subscriptionAttempts[threadID] = attempts
        guard attempts <= maxSubscriptionAttempts else { return }
        guard subscriptionRetryTasks[threadID] == nil else { return }

        let delaySeconds = min(12, max(2, attempts * 2))
        subscriptionRetryTasks[threadID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            await self?.retrySubscription(threadID: threadID)
        }
    }

    private func retrySubscription(threadID: String) async {
        subscriptionRetryTasks[threadID] = nil
        guard let threadRef = desiredThreads[threadID] else { return }
        await subscribeIfNeeded(to: threadRef)
    }

    private func shouldRetrySubscription(after error: Error) -> Bool {
        guard let appServerError = error as? CodexAppServerError else {
            return false
        }

        switch appServerError {
        case .server(let message):
            let lowercased = message.lowercased()
            return lowercased.contains("no rollout found")
                || lowercased.contains("thread not found")
                || lowercased.contains("not found")
        case .disconnected, .transport:
            return true
        default:
            return false
        }
    }

    private func timeoutRequest(id: Int, method: String) {
        guard let continuation = pending.removeValue(forKey: id) else {
            return
        }
        continuation.resume(
            throwing: CodexAppServerError.transport("Timed out waiting for \(method) response from remote Codex App Server.")
        )
    }

    private func failRequest(id: Int, error: Error) {
        guard let continuation = pending.removeValue(forKey: id) else {
            return
        }
        continuation.resume(throwing: error)
    }

    private func closeWebSocketAfterFailedHandshake() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        failPendingRequests()
    }

    private func markFailed(_ error: Error) async {
        guard isStarted else { return }
        isConnected = false
        lastFailureMessageValue = error.localizedDescription
        pingTask?.cancel()
        pingTask = nil
        pendingSubscriptionThreadIDs.removeAll()
        subscribedThreadIDs.removeAll()
        failPendingRequests()
        onDisconnected?(endpoint.id)
        if reportsConnectionFailures {
            await supervisor.updateMachineFailure(endpoint.id, message: error.localizedDescription)
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard isStarted, reconnectTask == nil else { return }
        reconnectAttempts += 1
        let delay = min(30, max(2, reconnectAttempts * 2))

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await self?.reconnect()
        }
    }

    private func reconnect() async {
        reconnectTask = nil
        guard isStarted else { return }

        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        failPendingRequests()
        pendingSubscriptionThreadIDs.removeAll()
        subscribedThreadIDs.removeAll()

        await supervisor.upsertMachine(
            SupervisorMachine(
                id: endpoint.id,
                name: endpoint.name,
                endpointDescription: endpoint.url.absoluteString,
                status: .connecting
            )
        )
        _ = await connectWebSocket()
    }

    private func failPendingRequests() {
        pending.values.forEach { $0.resume(throwing: CodexAppServerError.disconnected) }
        pending.removeAll()
    }

    private static func threadID(from params: JSONValue?) -> String? {
        AppServerNotificationNormalizer.threadID(from: params)
    }

    private static func joinPath(_ parent: String, _ child: String) -> String {
        if parent.hasSuffix("/") || parent.hasSuffix("\\") {
            return parent + child
        }
        if parent.contains("\\") || parent.contains(":") {
            return parent + "\\" + child
        }
        return parent + "/" + child
    }

    private func machine(from initializeResult: JSONValue, status: SupervisorMachineStatus) -> SupervisorMachine {
        let platform = SupervisorHostPlatformResolver.platform(
            from: initializeResult["platformFamily"]?.stringValue
                ?? initializeResult["platformOs"]?.stringValue
        )

        return SupervisorMachine(
            id: endpoint.id,
            name: endpoint.name,
            endpointDescription: endpoint.url.absoluteString,
            status: status,
            platform: platform,
            codexHome: initializeResult["codexHome"]?.stringValue
        )
    }

    private static let ignoredMentionDirectoryNames: Set<String> = [
        ".build",
        ".git",
        ".swiftpm",
        "DerivedData",
        "dist",
        "node_modules",
    ]
}

private struct RemoteDirectoryEntry {
    var fileName: String
    var isDirectory: Bool
    var isFile: Bool

    init?(value: JSONValue) {
        guard let fileName = value["fileName"]?.stringValue ?? value["file_name"]?.stringValue else {
            return nil
        }
        self.fileName = fileName
        self.isDirectory = value["isDirectory"]?.boolValue ?? value["is_directory"]?.boolValue ?? false
        self.isFile = value["isFile"]?.boolValue ?? value["is_file"]?.boolValue ?? false
    }
}

private extension JSONValue {
    var readableDescription: String {
        switch self {
        case .object(let object):
            return object["message"]?.stringValue ?? String(describing: object)
        case .array(let array):
            return String(describing: array)
        case .string(let string):
            return string
        case .number(let number):
            return String(number)
        case .bool(let bool):
            return String(bool)
        case .null:
            return "Unknown App Server error"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
