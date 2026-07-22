import Foundation

public struct AppServerAccessToken: Equatable, Sendable {
    public var value: String
    public var expiresAt: Date?

    public init(value: String, expiresAt: Date? = nil) {
        self.value = value
        self.expiresAt = expiresAt
    }
}

public protocol AppServerAccessTokenProviding: Sendable {
    func accessToken() async throws -> AppServerAccessToken?
}

enum AppServerAccessTokenExpiryPolicy {
    static func delay(until expiresAt: Date, now: Date = Date()) -> TimeInterval {
        max(0, expiresAt.timeIntervalSince(now))
    }

    static func applies(
        expectedConnectionID: AppServerConnectionID,
        currentConnectionID: AppServerConnectionID?
    ) -> Bool {
        expectedConnectionID == currentConnectionID
    }
}

enum AppServerRelayConnectionPhase: Equatable, Sendable {
    case stopped
    case disconnected
    case connecting
    case connected
}

struct AppServerRelayConnectionSnapshot: Equatable, Sendable {
    var phase: AppServerRelayConnectionPhase
    var connectionID: AppServerConnectionID?
    var hasWebSocket: Bool
}

public struct AppServerRelayEndpoint: Codable, Identifiable, Hashable, Sendable {
    public var id: HostID
    public var name: String
    public var url: URL
    public var bearerToken: String?
    public var credentialReference: String?

    public init(
        id: HostID,
        name: String,
        url: URL,
        bearerToken: String? = nil,
        credentialReference: String? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.bearerToken = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.credentialReference = credentialReference?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? (self.bearerToken == nil ? nil : Self.defaultCredentialReference(for: id))
    }

    public init?(machine: SupervisorMachine) {
        guard machine.status == .connected,
              let url = URL(string: machine.endpointDescription),
              Self.isAppServerWebSocketURL(url),
              Self.endpointStructureError(url) == nil else {
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
        if let structureError = endpointStructureError(url) {
            return structureError
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

    static func endpointStructureError(_ url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "The Codex App Server endpoint is malformed."
        }
        if components.user != nil || components.password != nil {
            return "WebSocket endpoint credentials must be supplied through the protected bearer-token field, not URL user-info."
        }
        if components.query != nil {
            return "WebSocket endpoint query parameters are not supported; supply credentials through the protected bearer-token field."
        }
        if components.fragment != nil {
            return "WebSocket endpoint fragments are not supported."
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
        case credentialReference
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(HostID.self, forKey: .id)
        let decodedToken = try container.decodeIfPresent(String.self, forKey: .bearerToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let token = decodedToken == Self.redactedBearerTokenPlaceholder ? nil : decodedToken
        self.init(
            id: id,
            name: try container.decode(String.self, forKey: .name),
            url: try container.decode(URL.self, forKey: .url),
            bearerToken: token,
            credentialReference: try container.decodeIfPresent(String.self, forKey: .credentialReference)
                ?? (token == nil ? nil : Self.defaultCredentialReference(for: id))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(credentialReference, forKey: .credentialReference)
    }

    private static let redactedBearerTokenPlaceholder = "__redacted__"

    public static func defaultCredentialReference(for id: HostID) -> String {
        "relay:\(id.rawValue)"
    }

    public func resolvingBearerToken(_ token: String?) -> AppServerRelayEndpoint {
        AppServerRelayEndpoint(
            id: id,
            name: name,
            url: url,
            bearerToken: token,
            credentialReference: credentialReference
        )
    }
}

public struct AppServerTranscriptLoadResult: Sendable {
    public var transcript: ThreadTranscript
    public var rolloutPath: String?

    public init(transcript: ThreadTranscript, rolloutPath: String?) {
        self.transcript = transcript
        self.rolloutPath = rolloutPath
    }
}

public struct AppServerWriteReconciliation: Sendable {
    public var hostID: HostID
    public var method: AppServerMethod
    public var confirmedCommitted: Bool
    public var affectedThreadRefs: [ThreadRef]
    public var observedCatalogEntries: [ThreadCatalogEntry]
    public var transcript: ThreadTranscript?

    public init(
        hostID: HostID,
        method: AppServerMethod,
        confirmedCommitted: Bool,
        affectedThreadRefs: [ThreadRef] = [],
        observedCatalogEntries: [ThreadCatalogEntry] = [],
        transcript: ThreadTranscript? = nil
    ) {
        self.hostID = hostID
        self.method = method
        self.confirmedCommitted = confirmedCommitted
        self.affectedThreadRefs = affectedThreadRefs
        self.observedCatalogEntries = observedCatalogEntries
        self.transcript = transcript
    }
}

struct AppServerReconciliationObservation: Sendable {
    var call: AppServerCall
    var result: JSONValue
}

public actor AppServerWebSocketWorkflowRelay {
    private enum ConnectionState: Equatable {
        case stopped
        case disconnected
        case connecting(AppServerConnectionID)
        case connected(AppServerConnectionID)

        var connectionID: AppServerConnectionID? {
            switch self {
            case .connecting(let connectionID), .connected(let connectionID):
                return connectionID
            case .stopped, .disconnected:
                return nil
            }
        }

        var isStarted: Bool {
            self != .stopped
        }

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    private let endpoint: AppServerRelayEndpoint
    private let supervisor: WorkflowSupervisor
    private let accessTokenProvider: (any AppServerAccessTokenProviding)?
    private let attachmentStagingRoot: String?
    private let webSocketTaskFactory: @Sendable (URLRequest) -> URLSessionWebSocketTask
    private let session = AppServerSession()
    private var connectionState: ConnectionState = .stopped
    private var connectionTask: Task<Bool, Never>?
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var accessTokenExpiryTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
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
    private let onWriteReconciled: (@Sendable (AppServerWriteReconciliation) -> Void)?

    private var connectionID: AppServerConnectionID? {
        connectionState.connectionID
    }

    private var isStarted: Bool {
        connectionState.isStarted
    }

    private var isConnected: Bool {
        connectionState.isConnected
    }

    public init(
        endpoint: AppServerRelayEndpoint,
        supervisor: WorkflowSupervisor,
        accessTokenProvider: (any AppServerAccessTokenProviding)? = nil,
        attachmentStagingRoot: String? = nil,
        webSocketTaskFactory: @escaping @Sendable (URLRequest) -> URLSessionWebSocketTask = {
            URLSession.shared.webSocketTask(with: $0)
        },
        reportsConnectionFailures: Bool = true,
        onAttentionRequest: (@Sendable (RuntimeAttentionRequest) -> Void)? = nil,
        onAttentionResolved: (@Sendable (HostID, String) -> Void)? = nil,
        onNotification: (@Sendable (HostID, CodexServerNotification) -> Void)? = nil,
        onDisconnected: (@Sendable (HostID) -> Void)? = nil,
        onWriteReconciled: (@Sendable (AppServerWriteReconciliation) -> Void)? = nil
    ) {
        self.endpoint = endpoint
        self.supervisor = supervisor
        self.accessTokenProvider = accessTokenProvider
        self.attachmentStagingRoot = attachmentStagingRoot?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        self.webSocketTaskFactory = webSocketTaskFactory
        self.reportsConnectionFailures = reportsConnectionFailures
        self.onAttentionRequest = onAttentionRequest
        self.onAttentionResolved = onAttentionResolved
        self.onNotification = onNotification
        self.onDisconnected = onDisconnected
        self.onWriteReconciled = onWriteReconciled
    }

    public func start() async -> Bool {
        if !isStarted {
            connectionState = .disconnected
        }
        return await connectIfNeeded()
    }

    private func connectIfNeeded() async -> Bool {
        guard isStarted else { return false }
        if isConnected {
            return true
        }
        if let connectionTask {
            let expectedConnectionID = connectionID
            let didConnect = await connectionTask.value
            guard isStarted,
                  self.connectionID == expectedConnectionID,
                  !Task.isCancelled else {
                return false
            }
            return didConnect && isConnected
        }

        reconnectTask?.cancel()
        reconnectTask = nil
        let connectionID = AppServerConnectionID()
        connectionState = .connecting(connectionID)
        let task = Task { [weak self] in
            await self?.performConnectionAttempt(connectionID: connectionID) ?? false
        }
        connectionTask = task
        let didConnect = await task.value
        let attemptIsCurrent = isCurrentConnectionAttempt(connectionID)
        if self.connectionID == connectionID || self.connectionID == nil {
            connectionTask = nil
        }
        return didConnect && attemptIsCurrent && isConnected
    }

    private func performConnectionAttempt(connectionID: AppServerConnectionID) async -> Bool {
        guard isStarted, self.connectionID == connectionID, !Task.isCancelled else {
            return false
        }

        closeSocket(connectionID: nil, invalidateConnection: false)

        await supervisor.upsertMachine(
            SupervisorMachine(
                id: endpoint.id,
                name: endpoint.name,
                endpointDescription: endpoint.url.absoluteString,
                status: .connecting
            )
        )

        guard isCurrentConnectionAttempt(connectionID) else {
            return false
        }

        let didConnect = await connectWebSocket(connectionID: connectionID)
        return didConnect && isCurrentConnectionAttempt(connectionID) && isConnected
    }

    private func connectWebSocket(connectionID: AppServerConnectionID) async -> Bool {
        guard isCurrentConnectionAttempt(connectionID) else { return false }
        let accessToken: AppServerAccessToken?
        do {
            accessToken = try await accessTokenProvider?.accessToken()
                ?? endpoint.bearerToken.map { AppServerAccessToken(value: $0) }
        } catch {
            guard isCurrentConnectionAttempt(connectionID) else { return false }
            await markFailed(error, connectionID: connectionID)
            return false
        }
        guard isCurrentConnectionAttempt(connectionID) else { return false }
        let bearerToken = accessToken?.value
        if let securityError = AppServerRelayEndpoint.connectionSecurityError(
            url: endpoint.url,
            bearerToken: bearerToken
        ) {
            await markFailed(CodexAppServerError.transport(securityError), connectionID: connectionID)
            return false
        }

        var urlRequest = URLRequest(url: endpoint.url)
        if let bearerToken, !bearerToken.isEmpty {
            urlRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        guard isCurrentConnectionAttempt(connectionID) else { return false }
        let task = webSocketTaskFactory(urlRequest)
        guard isCurrentConnectionAttempt(connectionID) else {
            task.cancel(with: .goingAway, reason: nil)
            return false
        }
        webSocketTask = task
        task.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop(webSocketTask: task, connectionID: connectionID)
        }

        do {
            let initializeResult = try await request(
                method: .initialize,
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

            guard isCurrentConnectionAttempt(connectionID) else {
                closeSocket(connectionID: connectionID)
                return false
            }

            guard AppServerEndpointVerifier.isTrustedInitializeResult(initializeResult) else {
                throw CodexAppServerError.invalidResponse
            }

            try await notify(method: "initialized")
            guard isCurrentConnectionAttempt(connectionID) else {
                closeSocket(connectionID: connectionID)
                return false
            }
            connectionState = .connected(connectionID)
            reconnectAttempts = 0
            lastFailureMessageValue = nil
            await supervisor.upsertMachine(machine(from: initializeResult, status: .connected))
            guard isCurrentConnectionAttempt(connectionID), isConnected else {
                closeSocket(connectionID: connectionID)
                return false
            }
            startPingLoop(connectionID: connectionID)
            scheduleAccessTokenExpiry(accessToken?.expiresAt, connectionID: connectionID)
            await subscribeDesiredThreads()
            guard isCurrentConnectionAttempt(connectionID), isConnected else {
                closeSocket(connectionID: connectionID)
                return false
            }
            return true
        } catch {
            guard isCurrentConnectionAttempt(connectionID) else { return false }
            await markFailed(error, connectionID: connectionID)
            return false
        }
    }

    public func stop(markDisconnected: Bool = true) async {
        let activeConnectionID = connectionID
        connectionState = .stopped
        connectionTask?.cancel()
        connectionTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTask?.cancel()
        pingTask = nil
        accessTokenExpiryTask?.cancel()
        accessTokenExpiryTask = nil
        subscriptionRetryTasks.values.forEach { $0.cancel() }
        subscriptionRetryTasks.removeAll()
        pendingSubscriptionThreadIDs.removeAll()
        subscribedThreadIDs.removeAll()
        subscriptionAttempts.removeAll()
        closeSocket(connectionID: activeConnectionID)
        if markDisconnected {
            onDisconnected?(endpoint.id)
        }
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

    func connectionLifecycleSnapshot() -> AppServerRelayConnectionSnapshot {
        let phase: AppServerRelayConnectionPhase = switch connectionState {
        case .stopped: .stopped
        case .disconnected: .disconnected
        case .connecting: .connecting
        case .connected: .connected
        }
        return AppServerRelayConnectionSnapshot(
            phase: phase,
            connectionID: connectionID,
            hasWebSocket: webSocketTask != nil
        )
    }

    private func isCurrentConnectionAttempt(_ expectedConnectionID: AppServerConnectionID) -> Bool {
        isStarted && connectionID == expectedConnectionID && !Task.isCancelled
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
        permissions: AgentThreadPermissions = .default,
        initialPrompt: String
    ) async throws -> ThreadCreationOutcome {
        try await ensureConnected()
        return try await createThreadUsingRequest(
            cwd: cwd,
            name: name,
            model: model,
            reasoningEffort: reasoningEffort,
            permissions: permissions,
            initialPrompt: initialPrompt
        ) { [weak self] method, params in
            guard let self else { throw CodexAppServerError.disconnected }
            return try await self.request(method: method, params: params)
        }
    }

    func createThreadUsingRequest(
        cwd: String,
        name: String,
        model: String,
        reasoningEffort: String,
        permissions: AgentThreadPermissions = .default,
        initialPrompt: String,
        request: @escaping @Sendable (AppServerMethod, JSONValue) async throws -> JSONValue
    ) async throws -> ThreadCreationOutcome {
        let result = try await request(
            .startThread,
            .object(CodexRuntimeStore.threadStartParams(cwd: cwd, model: model, permissions: permissions))
        )

        guard
            let thread = result["thread"],
            let threadID = thread["id"]?.stringValue,
            let threadCwd = thread["cwd"]?.stringValue
        else {
            throw CodexAppServerError.invalidResponse
        }

        var threadRef = ThreadRef(
            hostID: endpoint.id,
            threadID: threadID,
            cwd: threadCwd
        )
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

    public func listModels() async throws -> [AgentModelOption] {
        try await ensureConnected()
        let result = try await request(
            method: .listModels,
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
        async let skillsResult = optionalRequest(method: .listSkills, params: catalogParams)
        async let pluginsResult = optionalRequest(method: .listPlugins, params: catalogParams)
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
            method: .listThreads,
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
            method: .searchThreads,
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
            method: .readThread,
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

        let result = try await request(
            method: .listTurns,
            params: .object(params)
        )
        return AppServerTranscriptLoadResult(
            transcript: ThreadTranscriptParser.transcript(from: result, threadRef: threadRef).sortedChronologically(),
            rolloutPath: threadReadResult?["thread"]?["path"]?.stringValue ?? threadReadResult?["path"]?.stringValue
        )
    }

    private func readThread(threadID: String, cwdHint: String?) async throws -> ThreadRef? {
        let result = try await request(
            method: .readThread,
            params: .object([
                "threadId": .string(threadID),
            ])
        )
        return CodexRuntimeStore.threadRef(from: result["thread"] ?? result, hostID: endpoint.id, cwdHint: cwdHint)
    }

    private func findThreadInList(threadID: String, limit: Int) async throws -> ThreadRef? {
        let result = try await request(
            method: .listThreads,
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
            method: .readFile,
            params: .object([
                "path": .string(path),
            ])
        )
        return try CodexAppServerClient.fileData(fromReadFileResponse: result)
    }

    public func createDirectory(path: String, recursive: Bool = true) async throws {
        try await ensureConnected()
        _ = try await request(
            method: .createDirectory,
            params: .object([
                "path": .string(path),
                "recursive": .bool(recursive),
            ])
        )
    }

    public func writeFile(path: String, data: Data) async throws {
        try await ensureConnected()
        _ = try await request(
            method: .writeFile,
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
            method: .interruptTurn,
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
        permissions: AgentThreadPermissions? = nil,
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

        _ = try await request(method: .resumeThread, params: .object(resumeParams))

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

        _ = try await request(method: .startTurn, params: .object(params))
    }

    private func interruptibleTurnID(for threadRef: ThreadRef) async throws -> String {
        let result = try await request(
            method: .listTurns,
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
        let directory: String
        if let attachmentStagingRoot {
            directory = ChatInputAttachmentService.remoteAttachmentDirectory(
                stagingRoot: attachmentStagingRoot,
                hostID: endpoint.id,
                threadID: threadRef.threadID
            )
        } else {
            directory = try ChatInputAttachmentService.remoteAttachmentDirectory(
                cwd: threadRef.cwd,
                hostID: endpoint.id,
                threadID: threadRef.threadID
            )
        }
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
            method: .archiveThread,
            params: .object([
                "threadId": .string(threadRef.threadID),
            ])
        )
    }

    public func respondToServerRequest(
        id: JSONRPCRequestID,
        result: JSONValue,
        connectionID expectedConnectionID: AppServerConnectionID
    ) async throws {
        guard isStarted,
              isConnected,
              connectionID == expectedConnectionID else {
            throw CodexAppServerError.staleServerRequest
        }
        try await send(.object([
            "id": id.jsonValue,
            "result": result,
        ]), connectionID: expectedConnectionID)
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

        let result = try await request(method: .forkThread, params: .object(params))
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

    private func receiveLoop(
        webSocketTask: URLSessionWebSocketTask,
        connectionID: AppServerConnectionID
    ) async {
        do {
            while !Task.isCancelled {
                let message = try await webSocketTask.receive()
                await handle(message, connectionID: connectionID)
            }
        } catch {
            guard isStarted, self.connectionID == connectionID else { return }
            await markFailed(error, connectionID: connectionID)
        }
    }

    private func startPingLoop(connectionID: AppServerConnectionID) {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await self?.sendPing(connectionID: connectionID)
            }
        }
    }

    private func scheduleAccessTokenExpiry(
        _ expiresAt: Date?,
        connectionID: AppServerConnectionID
    ) {
        accessTokenExpiryTask?.cancel()
        accessTokenExpiryTask = nil
        guard let expiresAt else { return }

        let delay = AppServerAccessTokenExpiryPolicy.delay(until: expiresAt)
        accessTokenExpiryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.rotateExpiredAccessToken(connectionID: connectionID)
        }
    }

    private func rotateExpiredAccessToken(connectionID: AppServerConnectionID) async {
        guard isStarted,
              AppServerAccessTokenExpiryPolicy.applies(
                expectedConnectionID: connectionID,
                currentConnectionID: self.connectionID
              ) else { return }

        accessTokenExpiryTask = nil
        closeSocket(connectionID: connectionID)
        connectionTask?.cancel()
        connectionTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTask?.cancel()
        pingTask = nil
        pendingSubscriptionThreadIDs.removeAll()
        subscribedThreadIDs.removeAll()
        onDisconnected?(endpoint.id)
        _ = await connectIfNeeded()
    }

    private func sendPing(connectionID: AppServerConnectionID) {
        guard isStarted,
              isConnected,
              self.connectionID == connectionID,
              let webSocketTask else { return }
        webSocketTask.sendPing { [weak self] error in
            guard let error else { return }
            Task {
                await self?.markFailed(error, connectionID: connectionID)
            }
        }
    }

    private func request(
        method: AppServerMethod,
        params: JSONValue = .object([:]),
        mayReplayRead: Bool = true
    ) async throws -> JSONValue {
        guard let connectionID else {
            throw CodexAppServerError.disconnected
        }
        do {
            return try await session.request(
                AppServerCall(method, params: params),
                connectionID: connectionID,
                timeoutContext: .remote(endpoint.name)
            ) { [weak self] message, expectedConnectionID in
                guard let self else { throw CodexAppServerError.disconnected }
                try await self.send(message, connectionID: expectedConnectionID)
            }
        } catch let error as CodexAppServerError {
            if case .ambiguousWrite = error, method != .initialize {
                if let reconciledResponse = await reconcileAmbiguousWrite(
                    method: method,
                    params: params
                ) {
                    return reconciledResponse
                }
            }
            if method.replaySafety == .replayableRead,
               mayReplayRead,
               Self.isRetryableReadFailure(error) {
                guard await connectIfNeeded(), isConnected else { throw error }
                return try await request(
                    method: method,
                    params: params,
                    mayReplayRead: false
                )
            }
            throw error
        }
    }

    private nonisolated static func isRetryableReadFailure(_ error: CodexAppServerError) -> Bool {
        switch error {
        case .disconnected,
             .invalidResponse,
             .daemonProxyRequestTimedOut,
             .transport:
            return true
        case .ambiguousWrite,
             .unsupportedPlatform,
             .codexNotInstalled,
             .launchFailed,
             .daemonProxyHandshakeFailed,
             .staleServerRequest,
             .server:
            return false
        }
    }

    private func reconcileAmbiguousWrite(
        method: AppServerMethod,
        params: JSONValue
    ) async -> JSONValue? {
        guard await connectIfNeeded(), isConnected else { return nil }
        var observations: [AppServerReconciliationObservation] = []
        for call in Self.reconciliationCalls(after: method, params: params) {
            guard let result = try? await request(method: call.method, params: call.params) else {
                continue
            }
            observations.append(AppServerReconciliationObservation(call: call, result: result))
        }

        let reconciledResponse = Self.reconciledResponse(
            after: method,
            params: params,
            observations: observations
        )
        onWriteReconciled?(
            reconciliationSnapshot(
                method: method,
                params: params,
                observations: observations,
                reconciledResponse: reconciledResponse
            )
        )
        return reconciledResponse
    }

    nonisolated static func reconciliationCalls(
        after method: AppServerMethod,
        params: JSONValue
    ) -> [AppServerCall] {
        switch method {
        case .startThread, .forkThread:
            return [AppServerCall(
                .listThreads,
                params: .object(["limit": .number(200), "archived": .bool(false)])
            )]
        case .archiveThread:
            return [false, true].map { archived in
                AppServerCall(
                    .listThreads,
                    params: .object(["limit": .number(200), "archived": .bool(archived)])
                )
            }
        case .startTurn, .interruptTurn:
            guard let threadID = params["threadId"]?.stringValue else { return [] }
            return [
                AppServerCall(.readThread, params: .object(["threadId": .string(threadID)])),
                AppServerCall(.listTurns, params: turnListParams(threadID: threadID)),
            ]
        case .setThreadName:
            guard let threadID = params["threadId"]?.stringValue else { return [] }
            return [AppServerCall(.readThread, params: .object(["threadId": .string(threadID)]))]
        case .resumeThread:
            return [AppServerCall(.listLoadedThreads, params: .object(["limit": .number(200)]))]
        case .createDirectory:
            guard let path = params["path"]?.stringValue else { return [] }
            return [AppServerCall(.readDirectory, params: .object(["path": .string(path)]))]
        case .writeFile:
            guard let path = params["path"]?.stringValue else { return [] }
            return [AppServerCall(.readFile, params: .object(["path": .string(path)]))]
        case .unsubscribeThread:
            return []
        case .initialize,
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
             .listTurns:
            return []
        }
    }

    nonisolated static func reconciledResponse(
        after method: AppServerMethod,
        params: JSONValue,
        observations: [AppServerReconciliationObservation]
    ) -> JSONValue? {
        switch method {
        case .startThread, .forkThread:
            // A catalog delta has no request correlation. Another Codex client
            // can create exactly one thread while our response is in flight,
            // so binding that thread to this request would corrupt the graph.
            return nil
        case .startTurn:
            // Turn lists likewise do not identify which client submitted a
            // turn. Publish the refreshed transcript, but keep the write
            // ambiguous until the protocol offers an idempotency key.
            return nil
        case .archiveThread:
            guard let threadID = params["threadId"]?.stringValue else { return nil }
            let archivedIDs = observations
                .filter { $0.call.method == .listThreads && $0.call.params["archived"]?.boolValue == true }
                .flatMap { values(in: $0.result) }
                .compactMap(identifier(in:))
            return archivedIDs.contains(threadID) ? .object([:]) : nil
        case .setThreadName:
            guard let expectedName = params["name"]?.stringValue,
                  let result = observations.first(where: { $0.call.method == .readThread })?.result else {
                return nil
            }
            let thread = result["thread"] ?? result
            return thread["name"]?.stringValue == expectedName ? .object([:]) : nil
        case .resumeThread:
            guard let threadID = params["threadId"]?.stringValue,
                  let result = observations.first(where: { $0.call.method == .listLoadedThreads })?.result else {
                return nil
            }
            return ThreadCatalogEntry.loadedThreadIDs(from: result).contains(threadID) ? .object([:]) : nil
        case .interruptTurn:
            guard let turnID = params["turnId"]?.stringValue else { return nil }
            let turn = observations
                .filter { $0.call.method == .listTurns }
                .flatMap { values(in: $0.result) }
                .first { identifier(in: $0) == turnID }
            guard let turn, turnIsTerminal(turn) else { return nil }
            return .object([:])
        case .createDirectory:
            return observations.contains(where: { $0.call.method == .readDirectory }) ? .object([:]) : nil
        case .writeFile:
            guard let expectedBase64 = params["dataBase64"]?.stringValue,
                  let expected = Data(base64Encoded: expectedBase64),
                  let readResult = observations.first(where: { $0.call.method == .readFile })?.result,
                  let actual = try? CodexAppServerClient.fileData(fromReadFileResponse: readResult) else {
                return nil
            }
            return actual == expected ? .object([:]) : nil
        case .unsubscribeThread,
             .initialize,
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
             .listTurns:
            return nil
        }
    }

    private func reconciliationSnapshot(
        method: AppServerMethod,
        params: JSONValue,
        observations: [AppServerReconciliationObservation],
        reconciledResponse: JSONValue?
    ) -> AppServerWriteReconciliation {
        let catalogEntries = observations
            .filter { $0.call.method == .listThreads }
            .flatMap { Self.values(in: $0.result) }
            .compactMap {
                ThreadCatalogEntry.appServerThread(
                    from: $0,
                    hostID: endpoint.id,
                    hostName: endpoint.name
                )
            }

        var affectedThreadRefs: [ThreadRef] = []
        if let thread = reconciledResponse?["thread"],
           let threadRef = CodexRuntimeStore.threadRef(
                from: thread,
                hostID: endpoint.id,
                cwdHint: params["cwd"]?.stringValue
           ) {
            affectedThreadRefs.append(threadRef)
        } else if let threadID = params["threadId"]?.stringValue {
            let readResult = observations.first(where: { $0.call.method == .readThread })?.result
            let threadRef = readResult.flatMap {
                CodexRuntimeStore.threadRef(
                    from: $0["thread"] ?? $0,
                    hostID: endpoint.id,
                    cwdHint: params["cwd"]?.stringValue
                )
            } ?? desiredThreads[threadID] ?? ThreadRef(
                hostID: endpoint.id,
                threadID: threadID,
                cwd: params["cwd"]?.stringValue ?? "",
                name: nil
            )
            affectedThreadRefs.append(threadRef)
        }

        let transcript: ThreadTranscript?
        if let threadRef = affectedThreadRefs.first,
           let turnsResult = observations.first(where: { $0.call.method == .listTurns })?.result {
            transcript = ThreadTranscriptParser.transcript(
                from: turnsResult,
                threadRef: threadRef
            ).sortedChronologically()
        } else {
            transcript = nil
        }

        return AppServerWriteReconciliation(
            hostID: endpoint.id,
            method: method,
            confirmedCommitted: reconciledResponse != nil,
            affectedThreadRefs: affectedThreadRefs,
            observedCatalogEntries: catalogEntries,
            transcript: transcript
        )
    }

    private nonisolated static func turnListParams(threadID: String) -> JSONValue {
        .object([
            "threadId": .string(threadID),
            "limit": .number(100),
            "sortDirection": .string("desc"),
            "itemsView": .string("full"),
        ])
    }

    private nonisolated static func values(in result: JSONValue) -> [JSONValue] {
        result["data"]?.arrayValue
            ?? result["threads"]?.arrayValue
            ?? result["turns"]?.arrayValue
            ?? []
    }

    private nonisolated static func identifier(in value: JSONValue) -> String? {
        value["id"]?.stringValue
            ?? value["threadId"]?.stringValue
            ?? value["turnId"]?.stringValue
            ?? value["thread"]?["id"]?.stringValue
            ?? value["turn"]?["id"]?.stringValue
    }

    private nonisolated static func turnIsTerminal(_ value: JSONValue) -> Bool {
        let turn = value["turn"] ?? value
        if turn["completedAt"] != nil || turn["completed_at"] != nil {
            return true
        }
        guard let status = turn["status"]?.stringValue?.lowercased() else { return false }
        return ["complete", "completed", "cancelled", "canceled", "failed", "interrupted"].contains(status)
    }

    private func optionalRequest(
        method: AppServerMethod,
        params: JSONValue = .object([:])
    ) async -> JSONValue? {
        precondition(
            method.replaySafety == .replayableRead,
            "optionalRequest may only retry protocol-declared reads"
        )
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
                method: .readDirectory,
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
        guard let connectionID else {
            throw CodexAppServerError.disconnected
        }
        try await send(.object(body), connectionID: connectionID)
    }

    private func send(_ value: JSONValue, connectionID: AppServerConnectionID) async throws {
        guard self.connectionID == connectionID, let webSocketTask else {
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
        let didConnect = await connectIfNeeded()
        guard didConnect, isConnected else {
            throw CodexAppServerError.disconnected
        }
    }

    private func handle(
        _ message: URLSessionWebSocketTask.Message,
        connectionID: AppServerConnectionID
    ) async {
        guard self.connectionID == connectionID else { return }
        let data: Data
        switch message {
        case .data(let messageData):
            data = messageData
        case .string(let text):
            data = Data(text.utf8)
        @unknown default:
            return
        }

        switch await session.receive(data, connectionID: connectionID) {
        case .notification(let notification):
            handleNotification(notification)
        case .diagnostic:
            break
        case nil:
            break
        }
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
                method: .resumeThread,
                params: .object([
                    "threadId": .string(threadRef.threadID),
                    "cwd": .string(threadRef.cwd),
                ])
            )

            guard desiredThreads[threadRef.threadID] == threadRef else {
                _ = try? await request(
                    method: .unsubscribeThread,
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
            method: .unsubscribeThread,
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

    private func closeSocket(
        connectionID expectedConnectionID: AppServerConnectionID?,
        invalidateConnection: Bool = true
    ) {
        if let expectedConnectionID, connectionID != expectedConnectionID {
            return
        }
        receiveTask?.cancel()
        receiveTask = nil
        accessTokenExpiryTask?.cancel()
        accessTokenExpiryTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        if let expectedConnectionID {
            Task {
                await session.failPending(connectionID: expectedConnectionID)
            }
        }
        if invalidateConnection {
            connectionState = isStarted ? .disconnected : .stopped
        }
    }

    private func markFailed(_ error: Error, connectionID: AppServerConnectionID) async {
        guard isStarted, self.connectionID == connectionID else { return }
        closeSocket(connectionID: connectionID)
        lastFailureMessageValue = error.localizedDescription
        pingTask?.cancel()
        pingTask = nil
        pendingSubscriptionThreadIDs.removeAll()
        subscribedThreadIDs.removeAll()
        onDisconnected?(endpoint.id)
        if reportsConnectionFailures {
            await supervisor.updateMachineFailure(endpoint.id, message: error.localizedDescription)
            guard isStarted, self.connectionID == nil, !Task.isCancelled else { return }
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
        _ = await connectIfNeeded()
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
