import Foundation
import Observation

public enum AgentProviderRuntimeState: String, Codable, Sendable {
    case unavailable
    case installed
    case signInRequired
    case ready
    case failed
}

public struct AgentProviderRuntimeStatus: Codable, Hashable, Sendable {
    public var provider: AgentProvider
    public var state: AgentProviderRuntimeState
    public var executablePath: String?
    public var message: String

    public init(
        provider: AgentProvider,
        state: AgentProviderRuntimeState,
        executablePath: String? = nil,
        message: String
    ) {
        self.provider = provider
        self.state = state
        self.executablePath = executablePath
        self.message = message
    }
}

public enum AgentProviderRuntimeError: LocalizedError, Sendable {
    case unsupportedProvider(AgentProvider)
    case executableNotFound(AgentProvider)
    case signInRequired(AgentProvider)
    case modelCatalogUnavailable(AgentProvider, String)
    case threadProviderMismatch(expected: AgentProvider, actual: AgentProvider)
    case operationAlreadyRunning
    case emptyResponse(AgentProvider)
    case commandFailed(AgentProvider, String)
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let provider):
            return "\(provider.displayName) is not handled by the external CLI runtime."
        case .executableNotFound(let provider):
            return "\(provider.displayName) CLI was not found. Install \(provider.executableName), then refresh providers."
        case .signInRequired(let provider):
            return "Sign in to \(provider.displayName) with the official \(provider.executableName) CLI, then refresh providers."
        case .modelCatalogUnavailable(let provider, let detail):
            return "\(provider.displayName) did not return an available model catalog. \(detail)"
        case .threadProviderMismatch(let expected, let actual):
            return "This thread belongs to \(actual.displayName), so it cannot be opened with \(expected.displayName)."
        case .operationAlreadyRunning:
            return "This provider thread already has a turn in progress."
        case .emptyResponse(let provider):
            return "\(provider.displayName) completed without returning an assistant response."
        case .commandFailed(let provider, let detail):
            return "\(provider.displayName) CLI failed. \(detail)"
        case .unsupportedPlatform:
            return "External provider CLIs are available in the macOS app."
        }
    }
}

public struct AgentProviderCLIClient: Sendable {
    public var prefersGrokACP: Bool
    public var resolveExecutable: @Sendable (AgentProvider) -> URL?
    public var run: @Sendable (
        _ executableURL: URL,
        _ arguments: [String],
        _ currentDirectoryURL: URL?,
        _ timeout: TimeInterval
    ) async throws -> BoundedProcessResult
    public var launchAuthentication: @Sendable (AgentProvider, URL) throws -> Void

    public init(
        prefersGrokACP: Bool = false,
        resolveExecutable: @escaping @Sendable (AgentProvider) -> URL?,
        run: @escaping @Sendable (
            _ executableURL: URL,
            _ arguments: [String],
            _ currentDirectoryURL: URL?,
            _ timeout: TimeInterval
        ) async throws -> BoundedProcessResult,
        launchAuthentication: @escaping @Sendable (AgentProvider, URL) throws -> Void
    ) {
        self.prefersGrokACP = prefersGrokACP
        self.resolveExecutable = resolveExecutable
        self.run = run
        self.launchAuthentication = launchAuthentication
    }

    public static let live = AgentProviderCLIClient(
        prefersGrokACP: true,
        resolveExecutable: LocalAgentProviderDiscovery.executableURL(for:),
        run: { executableURL, arguments, currentDirectoryURL, timeout in
            try await BoundedProcessRunner.run(
                executableURL: executableURL,
                arguments: arguments,
                currentDirectoryURL: currentDirectoryURL,
                timeout: timeout,
                maxOutputBytes: 4 * 1_048_576
            )
        },
        launchAuthentication: ProviderCLIAuthenticationLauncher.launch(provider:executableURL:)
    )
}

public enum LocalAgentProviderDiscovery {
    public static func executableURL(for provider: AgentProvider) -> URL? {
        #if os(macOS)
        if provider == .codex {
            return LocalCodexDiscovery.findCodexExecutable().map(URL.init(fileURLWithPath:))
        }

        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates: [URL]
        switch provider {
        case .codex:
            candidates = []
        case .gemini:
            candidates = [
                home.appendingPathComponent(".local/bin/agy"),
            ]
        case .grok:
            candidates = [
                home.appendingPathComponent(".grok/bin/grok"),
                home.appendingPathComponent(".local/bin/grok"),
                URL(fileURLWithPath: "/opt/homebrew/bin/grok"),
                URL(fileURLWithPath: "/usr/local/bin/grok"),
            ]
        }

        if let candidate = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
            return candidate
        }

        let result = try? BoundedProcessRunner.runBlocking(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["which", provider.executableName],
            timeout: 5,
            maxOutputBytes: 16 * 1_024
        )
        guard result?.terminationStatus == 0 else { return nil }
        let path = result?.stdout.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
        #else
        return nil
        #endif
    }
}

public enum ProviderCLIAuthenticationLauncher {
    public static func launch(provider: AgentProvider, executableURL: URL) throws {
        #if os(macOS)
        guard provider != .codex else {
            throw AgentProviderRuntimeError.unsupportedProvider(provider)
        }

        let arguments = authenticationArguments(for: provider)
        let command = ([executableURL.path] + arguments)
            .map(shellQuoted)
            .joined(separator: " ")
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mapofagents-\(provider.rawValue)-sign-in-\(UUID().uuidString).command")
        let script = "#!/bin/sh\n\(command)\nstatus=$?\nprintf '\\nYou can close this window.\\n'\nexit $status\n"
        try script.data(using: .utf8)?.write(to: scriptURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: scriptURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", scriptURL.path]
        try process.run()
        #else
        throw AgentProviderRuntimeError.unsupportedPlatform
        #endif
    }

    static func authenticationArguments(for provider: AgentProvider) -> [String] {
        switch provider {
        case .codex, .gemini:
            return []
        case .grok:
            return ["login", "--oauth"]
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

public enum ProviderCLIInstallationLauncher {
    public static func launch(provider: AgentProvider) throws {
        #if os(macOS)
        let installerURL: String
        switch provider {
        case .codex:
            throw AgentProviderRuntimeError.unsupportedProvider(provider)
        case .gemini:
            installerURL = "https://antigravity.google/cli/install.sh"
        case .grok:
            installerURL = "https://x.ai/cli/install.sh"
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mapofagents-\(provider.rawValue)-install-\(UUID().uuidString).command")
        let installerPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("mapofagents-\(provider.rawValue)-installer-\(UUID().uuidString).sh")
        let script = """
        #!/bin/sh
        set -e
        /usr/bin/curl -fsSL '\(installerURL)' -o '\(installerPath.path)'
        /bin/bash '\(installerPath.path)'
        status=$?
        /bin/rm -f '\(installerPath.path)'
        printf '\nInstallation finished. You can close this window.\n'
        exit $status
        """
        try script.data(using: .utf8)?.write(to: scriptURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: scriptURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", scriptURL.path]
        try process.run()
        #else
        throw AgentProviderRuntimeError.unsupportedPlatform
        #endif
    }
}

@MainActor
@Observable
public final class AgentProviderRuntimeStore {
    public private(set) var modelsByProvider: [AgentProvider: [AgentModelOption]] = [:]
    public private(set) var statusByProvider: [AgentProvider: AgentProviderRuntimeStatus] = [:]
    public private(set) var runningThreadKeys: Set<String> = []
    public private(set) var pendingAttentionRequests: [RuntimeAttentionRequest] = []
    public private(set) var liveAssistantTextByThreadKey: [String: String] = [:]
    public private(set) var runStatusByThreadKey: [String: ThreadRunStatus] = [:]
    public private(set) var lastActivityByThreadKey: [String: Date] = [:]

    @ObservationIgnored private let repository: any ControlRoomStore
    @ObservationIgnored private let client: AgentProviderCLIClient
    @ObservationIgnored private var activeTranscripts: [String: ThreadTranscript] = [:]
    #if os(macOS)
    @ObservationIgnored private var grokConnections: [String: GrokACPConnection] = [:]
    @ObservationIgnored private var grokTurns: [String: ActiveGrokTurn] = [:]
    @ObservationIgnored private var grokPermissions: [String: PendingGrokPermission] = [:]
    @ObservationIgnored private var hydratingGrokThreadKeys: Set<String> = []
    @ObservationIgnored private var grokLiveTextFlushTasks: [String: Task<Void, Never>] = [:]
    #endif

    public init(
        repository: any ControlRoomStore,
        client: AgentProviderCLIClient = .live
    ) {
        self.repository = repository
        self.client = client

        for provider in [AgentProvider.gemini, .grok] {
            let executableURL = client.resolveExecutable(provider)
            statusByProvider[provider] = AgentProviderRuntimeStatus(
                provider: provider,
                state: executableURL == nil ? .unavailable : .installed,
                executablePath: executableURL?.path,
                message: executableURL == nil
                    ? "\(provider.executableName) is not installed"
                    : "Refresh to verify sign-in and models"
            )
        }
    }

    public func models(for provider: AgentProvider) -> [AgentModelOption] {
        modelsByProvider[provider] ?? []
    }

    public func refreshAll() async {
        for provider in [AgentProvider.gemini, .grok] {
            await refresh(provider)
        }
    }

    public func refresh(_ provider: AgentProvider) async {
        guard provider != .codex else { return }
        guard let executableURL = client.resolveExecutable(provider) else {
            modelsByProvider[provider] = []
            statusByProvider[provider] = AgentProviderRuntimeStatus(
                provider: provider,
                state: .unavailable,
                message: "\(provider.executableName) is not installed"
            )
            return
        }

        statusByProvider[provider] = AgentProviderRuntimeStatus(
            provider: provider,
            state: .installed,
            executablePath: executableURL.path,
            message: "Reading the live model catalog…"
        )

        do {
            #if os(macOS)
            if provider == .grok, client.prefersGrokACP {
                let connection = GrokACPConnection(executableURL: executableURL)
                defer { connection.shutdown() }
                let initialization = try await connection.start()
                guard !initialization.modelOptions.isEmpty else {
                    throw AgentProviderRuntimeError.modelCatalogUnavailable(
                        provider,
                        "The ACP handshake returned no model identifiers."
                    )
                }
                modelsByProvider[provider] = initialization.modelOptions
                let version = initialization.agentVersion.map { " · CLI \($0)" } ?? ""
                statusByProvider[provider] = AgentProviderRuntimeStatus(
                    provider: provider,
                    state: .ready,
                    executablePath: executableURL.path,
                    message: "\(initialization.modelOptions.count) models available via ACP\(version)"
                )
                return
            }
            #endif

            let result = try await client.run(executableURL, ["models"], nil, 30)
            if Self.requiresAuthentication(result) {
                modelsByProvider[provider] = []
                statusByProvider[provider] = AgentProviderRuntimeStatus(
                    provider: provider,
                    state: .signInRequired,
                    executablePath: executableURL.path,
                    message: "Sign in with the official \(provider.executableName) CLI"
                )
                return
            }
            guard result.terminationStatus == 0 else {
                let detail = Self.commandFailureDetail(result)
                modelsByProvider[provider] = []
                statusByProvider[provider] = AgentProviderRuntimeStatus(
                    provider: provider,
                    state: .signInRequired,
                    executablePath: executableURL.path,
                    message: detail.isEmpty ? "Sign in with the official CLI" : detail
                )
                return
            }

            let catalogOutput = [result.stdout.stringValue, result.stderr.stringValue]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let models = Self.modelOptions(from: catalogOutput, provider: provider)
            guard !models.isEmpty else {
                throw AgentProviderRuntimeError.modelCatalogUnavailable(
                    provider,
                    "The models command returned no model identifiers."
                )
            }
            modelsByProvider[provider] = models
            statusByProvider[provider] = AgentProviderRuntimeStatus(
                provider: provider,
                state: .ready,
                executablePath: executableURL.path,
                message: "\(models.count) models available"
            )
        } catch GrokACPError.authenticationRequired {
            modelsByProvider[provider] = []
            statusByProvider[provider] = AgentProviderRuntimeStatus(
                provider: provider,
                state: .signInRequired,
                executablePath: executableURL.path,
                message: "Sign in with the official \(provider.executableName) CLI"
            )
        } catch {
            modelsByProvider[provider] = []
            statusByProvider[provider] = AgentProviderRuntimeStatus(
                provider: provider,
                state: .failed,
                executablePath: executableURL.path,
                message: error.localizedDescription
            )
        }
    }

    public func signIn(to provider: AgentProvider) throws {
        guard provider != .codex else {
            throw AgentProviderRuntimeError.unsupportedProvider(provider)
        }
        guard let executableURL = client.resolveExecutable(provider) else {
            throw AgentProviderRuntimeError.executableNotFound(provider)
        }
        try client.launchAuthentication(provider, executableURL)
    }

    public func createThread(
        provider: AgentProvider,
        hostID: HostID,
        cwd: String,
        name: String,
        model: String? = nil,
        reasoningEffort: String? = nil,
        adoptProviderGeneratedTitle: Bool = false
    ) async throws -> ThreadCreationOutcome {
        guard provider != .codex else {
            throw AgentProviderRuntimeError.unsupportedProvider(provider)
        }
        guard client.resolveExecutable(provider) != nil else {
            throw AgentProviderRuntimeError.executableNotFound(provider)
        }
        guard !models(for: provider).isEmpty else {
            throw AgentProviderRuntimeError.signInRequired(provider)
        }

        #if os(macOS)
        if provider == .grok, client.prefersGrokACP {
            return try await createGrokThread(
                hostID: hostID,
                cwd: cwd,
                name: name,
                model: model,
                reasoningEffort: reasoningEffort,
                adoptProviderGeneratedTitle: adoptProviderGeneratedTitle
            )
        }
        #endif

        let threadRef = ThreadRef(
            provider: provider,
            hostID: hostID,
            threadID: UUID().uuidString.lowercased(),
            cwd: cwd,
            name: name
        )
        try await repository.saveTranscript(ThreadTranscript(threadRef: threadRef))
        return ThreadCreationOutcome(threadRef: threadRef)
    }

    public func loadTranscript(for threadRef: ThreadRef) async throws -> ThreadTranscript {
        guard threadRef.provider != .codex else {
            throw AgentProviderRuntimeError.unsupportedProvider(threadRef.provider)
        }
        if let active = activeTranscripts[threadRef.qualifiedID] {
            return active
        }
        let storedTranscript = try await repository.loadTranscript(for: threadRef)
            ?? ThreadTranscript(threadRef: threadRef)
        var transcript = threadRef.provider == .grok
            ? Self.normalizedGrokTranscript(storedTranscript)
            : storedTranscript
        if transcript != storedTranscript {
            try await repository.saveTranscript(transcript)
        }
        #if os(macOS)
        if threadRef.provider == .grok,
           client.prefersGrokACP,
           transcript.providerMetadata?.isSessionMaterialized != false,
           let executableURL = client.resolveExecutable(.grok) {
            _ = try await grokConnection(
                for: threadRef,
                transcript: &transcript,
                executableURL: executableURL
            )
        }
        #endif
        return transcript
    }

    public func sendMessage(
        _ text: String,
        to threadRef: ThreadRef,
        model: String?,
        reasoningEffort: String?,
        attachments: [ChatInputAttachment] = []
    ) async throws {
        let provider = threadRef.provider
        guard provider != .codex else {
            throw AgentProviderRuntimeError.unsupportedProvider(provider)
        }
        guard let executableURL = client.resolveExecutable(provider) else {
            throw AgentProviderRuntimeError.executableNotFound(provider)
        }

        let key = threadRef.qualifiedID
        guard runningThreadKeys.insert(key).inserted else {
            throw AgentProviderRuntimeError.operationAlreadyRunning
        }
        defer { runningThreadKeys.remove(key) }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentLines = attachments.compactMap { attachment -> String? in
            guard let path = attachment.sourcePath, !path.isEmpty else { return nil }
            return "- \(attachment.name): \(path)"
        }
        if attachmentLines.count != attachments.count {
            throw AgentProviderRuntimeError.commandFailed(
                provider,
                "This CLI adapter currently supports file-backed attachments only."
            )
        }
        guard !trimmedText.isEmpty || !attachmentLines.isEmpty else { return }

        #if os(macOS)
        if provider == .grok, client.prefersGrokACP {
            try await sendGrokMessage(
                trimmedText,
                attachmentLines: attachmentLines,
                to: threadRef,
                model: model,
                reasoningEffort: reasoningEffort,
                attachments: attachments,
                executableURL: executableURL
            )
            return
        }
        #endif

        var transcript = try await loadTranscript(for: threadRef)
        let prompt = Self.prompt(
            text: trimmedText,
            attachmentLines: attachmentLines,
            provider: provider,
            previousMessages: transcript.messages
        )
        let arguments = Self.promptArguments(
            provider: provider,
            prompt: prompt,
            threadRef: threadRef,
            model: model,
            reasoningEffort: reasoningEffort,
            isNewSession: transcript.messages.isEmpty
        )
        let result = try await client.run(
            executableURL,
            arguments,
            URL(fileURLWithPath: threadRef.cwd, isDirectory: true),
            30 * 60
        )
        guard result.terminationStatus == 0 else {
            throw AgentProviderRuntimeError.commandFailed(provider, Self.commandFailureDetail(result))
        }

        let assistantText = Self.assistantText(
            from: result.stdout.stringValue,
            provider: provider
        )
        guard !assistantText.isEmpty else {
            throw AgentProviderRuntimeError.emptyResponse(provider)
        }

        let userText = attachmentLines.isEmpty
            ? trimmedText
            : ([trimmedText, "Attached files:", attachmentLines.joined(separator: "\n")]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n"))
        let now = Date()
        transcript.messages.append(ThreadMessage(role: .user, text: userText, createdAt: now))
        transcript.messages.append(ThreadMessage(role: .assistant, text: assistantText, createdAt: now.addingTimeInterval(0.001)))
        transcript.lastUpdatedAt = Date()
        try await repository.saveTranscript(transcript)
    }

    public func forkThread(_ threadRef: ThreadRef, name: String? = nil) async throws -> ThreadRef {
        var transcript = try await loadTranscript(for: threadRef)
        let forkedRef = ThreadRef(
            provider: threadRef.provider,
            hostID: threadRef.hostID,
            threadID: UUID().uuidString.lowercased(),
            cwd: threadRef.cwd,
            name: name ?? threadRef.name
        )
        transcript.threadRef = forkedRef
        if threadRef.provider == .grok {
            let sourceSessionID = transcript.providerMetadata?.sessionID ?? threadRef.threadID
            transcript.providerMetadata = ProviderThreadMetadata(
                sessionID: forkedRef.threadID,
                generatedTitle: transcript.providerMetadata?.generatedTitle,
                forkedFromSessionID: sourceSessionID,
                isSessionMaterialized: false,
                modelID: transcript.providerMetadata?.modelID,
                reasoningEffort: transcript.providerMetadata?.reasoningEffort,
                prefersGeneratedTitle: false
            )
        }
        transcript.lastUpdatedAt = Date()
        try await repository.saveTranscript(transcript)
        return forkedRef
    }

    public func liveAssistantText(for threadRef: ThreadRef) -> String {
        liveAssistantTextByThreadKey[threadRef.qualifiedID] ?? ""
    }

    public func runStatus(for threadRef: ThreadRef) -> ThreadRunStatus? {
        runStatusByThreadKey[threadRef.qualifiedID]
    }

    public func lastActivity(for threadRef: ThreadRef) -> Date? {
        lastActivityByThreadKey[threadRef.qualifiedID]
    }

    public func keepMapofAgentsTitle(for threadRef: ThreadRef) async {
        guard var transcript = try? await repository.loadTranscript(for: threadRef),
              var metadata = transcript.providerMetadata else {
            return
        }
        metadata.prefersGeneratedTitle = false
        transcript.providerMetadata = metadata
        activeTranscripts[threadRef.qualifiedID] = activeTranscripts[threadRef.qualifiedID].map { active in
            var copy = active
            copy.providerMetadata = metadata
            return copy
        }
        try? await repository.saveTranscript(transcript)
    }

    public func interruptThread(_ threadRef: ThreadRef) async throws -> String {
        guard threadRef.provider == .grok else {
            throw AgentProviderRuntimeError.commandFailed(
                threadRef.provider,
                "This provider does not expose turn interruption."
            )
        }
        #if os(macOS)
        guard let connection = grokConnections[threadRef.qualifiedID] else {
            throw AgentProviderRuntimeError.commandFailed(.grok, "No Grok ACP turn is running.")
        }
        let sessionID = activeTranscripts[threadRef.qualifiedID]?.providerMetadata?.sessionID
            ?? threadRef.threadID
        try connection.cancel(sessionID: sessionID)
        let permissionIDs = grokPermissions.compactMap { key, value in
            value.threadKey == threadRef.qualifiedID ? key : nil
        }
        for permissionID in permissionIDs {
            if let permission = grokPermissions.removeValue(forKey: permissionID) {
                try? permission.connection.respondToPermission(
                    requestID: permission.request.requestID,
                    optionID: nil
                )
            }
        }
        pendingAttentionRequests.removeAll { $0.threadID == threadRef.threadID && $0.method == "session/request_permission" }
        return grokTurns[threadRef.qualifiedID]?.turnID ?? "grok-turn"
        #else
        throw AgentProviderRuntimeError.unsupportedPlatform
        #endif
    }

    public func respondToAttentionRequest(_ request: RuntimeAttentionRequest, allow: Bool) async throws {
        #if os(macOS)
        guard request.method == "session/request_permission",
              request.requestParams?["provider"]?.stringValue == AgentProvider.grok.rawValue,
              let pending = grokPermissions[request.id] else {
            throw AgentProviderRuntimeError.commandFailed(.grok, "This Grok permission request is stale.")
        }
        let preferredKind = allow ? "allow_once" : "reject_once"
        let fallbackPrefix = allow ? "allow" : "reject"
        guard let option = pending.request.options.first(where: { $0.kind == preferredKind })
                ?? pending.request.options.first(where: { $0.kind.hasPrefix(fallbackPrefix) }) else {
            throw AgentProviderRuntimeError.commandFailed(.grok, "Grok did not provide a compatible permission option.")
        }
        try pending.connection.respondToPermission(
            requestID: pending.request.requestID,
            optionID: option.id
        )
        grokPermissions.removeValue(forKey: request.id)
        pendingAttentionRequests.removeAll { $0.id == request.id }
        runStatusByThreadKey[pending.threadKey] = .running
        lastActivityByThreadKey[pending.threadKey] = Date()
        if var transcript = activeTranscripts[pending.threadKey],
           var timeline = transcript.turnTimeline,
           let index = timeline.turns.indices.last {
            timeline.turns[index].status = .running
            transcript.turnTimeline = timeline
            activeTranscripts[pending.threadKey] = transcript
        }
        #else
        throw AgentProviderRuntimeError.unsupportedPlatform
        #endif
    }

    public func shutdown() {
        #if os(macOS)
        for task in grokLiveTextFlushTasks.values {
            task.cancel()
        }
        grokLiveTextFlushTasks.removeAll()
        for connection in grokConnections.values {
            connection.shutdown()
        }
        grokConnections.removeAll()
        grokPermissions.removeAll()
        #endif
        pendingAttentionRequests.removeAll { $0.method == "session/request_permission" }
        runningThreadKeys.removeAll()
        liveAssistantTextByThreadKey.removeAll()
        activeTranscripts.removeAll()
    }

    #if os(macOS)
    private func createGrokThread(
        hostID: HostID,
        cwd: String,
        name: String,
        model: String?,
        reasoningEffort: String?,
        adoptProviderGeneratedTitle: Bool
    ) async throws -> ThreadCreationOutcome {
        guard let executableURL = client.resolveExecutable(.grok) else {
            throw AgentProviderRuntimeError.executableNotFound(.grok)
        }
        let connection = GrokACPConnection(
            executableURL: executableURL,
            modelID: model,
            reasoningEffort: reasoningEffort
        )
        do {
            let initialization = try await connection.start()
            let created = try await connection.createSession(cwd: cwd)
            let threadRef = ThreadRef(
                provider: .grok,
                hostID: hostID,
                threadID: created.sessionID,
                cwd: cwd,
                name: name
            )
            configureGrokConnection(connection, for: threadRef)
            grokConnections[threadRef.qualifiedID] = connection

            var metadata = Self.grokMetadata(
                from: created.response,
                fallbackSessionID: created.sessionID
            )
            metadata.modelID = metadata.modelID
                ?? model
                ?? initialization.modelOptions.first(where: \.isDefault)?.id
                ?? initialization.modelOptions.first?.id
            metadata.reasoningEffort = metadata.reasoningEffort ?? reasoningEffort
            metadata.prefersGeneratedTitle = adoptProviderGeneratedTitle
            let transcript = ThreadTranscript(
                threadRef: threadRef,
                providerMetadata: metadata
            )
            try await repository.saveTranscript(transcript)
            return ThreadCreationOutcome(threadRef: threadRef)
        } catch {
            connection.shutdown()
            throw error
        }
    }

    private func sendGrokMessage(
        _ text: String,
        attachmentLines: [String],
        to threadRef: ThreadRef,
        model: String?,
        reasoningEffort: String?,
        attachments: [ChatInputAttachment],
        executableURL: URL
    ) async throws {
        var transcript = try await loadTranscript(for: threadRef)
        if transcript.providerMetadata?.isSessionMaterialized == false,
           transcript.providerMetadata?.forkedFromSessionID != nil {
            try await materializeGrokFork(
                text,
                attachmentLines: attachmentLines,
                transcript: &transcript,
                model: model,
                reasoningEffort: reasoningEffort,
                executableURL: executableURL
            )
            return
        }

        let connection = try await grokConnection(
            for: threadRef,
            transcript: &transcript,
            executableURL: executableURL
        )
        let key = threadRef.qualifiedID
        let sessionID = transcript.providerMetadata?.sessionID ?? threadRef.threadID
        let userText = attachmentLines.isEmpty
            ? text
            : ([text, "Attached files:", attachmentLines.joined(separator: "\n")]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n"))
        let startedAt = Date()
        let turnID = "grok-turn-\(UUID().uuidString.lowercased())"
        let userMessage = ThreadMessage(role: .user, text: userText, createdAt: startedAt)
        var timeline = transcript.turnTimeline ?? ThreadTurnTimeline.fromTranscript(transcript)
        transcript.messages.append(userMessage)
        timeline.turns.append(
            ThreadTurn(
                id: turnID,
                status: .running,
                startedAt: startedAt,
                items: [
                    ThreadTurnItem(
                        id: userMessage.id,
                        kind: .userMessage,
                        message: userMessage
                    ),
                ]
            )
        )
        transcript.turnTimeline = timeline
        transcript.lastUpdatedAt = startedAt
        if transcript.providerMetadata == nil {
            transcript.providerMetadata = ProviderThreadMetadata(sessionID: sessionID)
        }
        var providerMetadata = transcript.providerMetadata ?? ProviderThreadMetadata(sessionID: sessionID)
        providerMetadata.modelID = model ?? providerMetadata.modelID
        providerMetadata.reasoningEffort = reasoningEffort ?? providerMetadata.reasoningEffort
        transcript.providerMetadata = providerMetadata
        activeTranscripts[key] = transcript
        grokTurns[key] = ActiveGrokTurn(turnID: turnID, startedAt: startedAt)
        runStatusByThreadKey[key] = .running
        lastActivityByThreadKey[key] = startedAt
        try await repository.saveTranscript(transcript)

        let content = Self.grokPromptContent(text: text, attachments: attachments)
        do {
            let response = try await connection.prompt(sessionID: sessionID, content: content)
            try? await Task.sleep(for: .milliseconds(350))
            if transcript.providerMetadata?.generatedTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                await refreshGrokSessionMetadata(
                    connection: connection,
                    threadRef: threadRef,
                    sessionID: sessionID
                )
            }
            try await finalizeGrokTurn(
                threadRef: threadRef,
                stopReason: response["stopReason"]?.stringValue ?? "end_turn",
                error: nil
            )
        } catch {
            try? await finalizeGrokTurn(
                threadRef: threadRef,
                stopReason: "failed",
                error: error.localizedDescription
            )
            throw error
        }
    }

    private func grokConnection(
        for threadRef: ThreadRef,
        transcript: inout ThreadTranscript,
        executableURL: URL
    ) async throws -> GrokACPConnection {
        if let existing = grokConnections[threadRef.qualifiedID] {
            return existing
        }

        let connection = GrokACPConnection(
            executableURL: executableURL,
            modelID: transcript.providerMetadata?.modelID,
            reasoningEffort: transcript.providerMetadata?.reasoningEffort
        )
        do {
            _ = try await connection.start()
            configureGrokConnection(connection, for: threadRef)
            let sessionID = transcript.providerMetadata?.sessionID ?? threadRef.threadID
            hydratingGrokThreadKeys.insert(threadRef.qualifiedID)
            defer { hydratingGrokThreadKeys.remove(threadRef.qualifiedID) }
            let response = try await connection.loadSession(sessionID: sessionID, cwd: threadRef.cwd)
            let loadedMetadata = Self.grokMetadata(from: response, fallbackSessionID: sessionID)
            transcript.providerMetadata = Self.merging(
                transcript.providerMetadata,
                with: loadedMetadata
            )
            transcript.lastUpdatedAt = Date()
            try await repository.saveTranscript(transcript)
            grokConnections[threadRef.qualifiedID] = connection
            return connection
        } catch {
            connection.shutdown()
            throw error
        }
    }

    private func configureGrokConnection(_ connection: GrokACPConnection, for threadRef: ThreadRef) {
        connection.onNotification = { [weak self] method, params in
            self?.handleGrokNotification(method: method, params: params, threadRef: threadRef)
        }
        connection.onPermissionRequest = { [weak self, weak connection] request in
            guard let self, let connection else { return }
            self.handleGrokPermissionRequest(request, connection: connection, threadRef: threadRef)
        }
    }

    private func refreshGrokSessionMetadata(
        connection: GrokACPConnection,
        threadRef: ThreadRef,
        sessionID: String
    ) async {
        let key = threadRef.qualifiedID
        hydratingGrokThreadKeys.insert(key)
        defer { hydratingGrokThreadKeys.remove(key) }
        guard let response = try? await connection.loadSession(sessionID: sessionID, cwd: threadRef.cwd),
              var transcript = activeTranscripts[key] else {
            return
        }
        transcript.providerMetadata = Self.merging(
            transcript.providerMetadata,
            with: Self.grokMetadata(from: response, fallbackSessionID: sessionID)
        )
        transcript.lastUpdatedAt = Date()
        activeTranscripts[key] = transcript
    }

    private func handleGrokNotification(
        method: String,
        params: JSONValue,
        threadRef: ThreadRef
    ) {
        let key = threadRef.qualifiedID
        guard !hydratingGrokThreadKeys.contains(key),
              method == "session/update" || method == "_x.ai/session/update",
              let update = params["update"] else {
            return
        }

        let type = update["sessionUpdate"]?.stringValue ?? ""
        if type == "session_info_update" {
            if var transcript = activeTranscripts[key],
               let title = update["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                transcript.providerMetadata = transcript.providerMetadata
                    ?? ProviderThreadMetadata(sessionID: threadRef.threadID)
                transcript.providerMetadata?.generatedTitle = title
                transcript.lastUpdatedAt = Self.grokDate(update["updatedAt"]?.stringValue) ?? Date()
                activeTranscripts[key] = transcript
            }
            return
        }

        guard var transcript = activeTranscripts[key],
              var turn = grokTurns[key],
              var timeline = transcript.turnTimeline,
              let turnIndex = timeline.turns.indices.last else {
            return
        }
        var shouldScheduleLiveTextFlush = false

        switch type {
        case "agent_message_chunk":
            let text = update["content"]?["text"]?.stringValue ?? ""
            if !text.isEmpty, turn.assistantStartedAt == nil {
                turn.assistantStartedAt = Date()
            }
            turn.assistantText += text
            shouldScheduleLiveTextFlush = !text.isEmpty

        case "agent_thought_chunk":
            let text = update["content"]?["text"]?.stringValue ?? ""
            guard !text.isEmpty else { break }
            let messageID = turn.reasoningMessageID ?? "grok-reasoning-\(UUID().uuidString.lowercased())"
            turn.reasoningMessageID = messageID
            Self.upsertGrokMessage(
                id: messageID,
                role: .reasoning,
                appendedText: text,
                kind: .reasoning,
                transcript: &transcript,
                turn: &timeline.turns[turnIndex]
            )

        case "tool_call", "tool_call_update":
            if type == "tool_call" {
                let progressText = turn.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !progressText.isEmpty {
                    let progressMessage = ThreadMessage(
                        id: "grok-progress-\(UUID().uuidString.lowercased())",
                        role: .assistant,
                        text: progressText,
                        createdAt: turn.assistantStartedAt ?? Date()
                    )
                    transcript.messages.append(progressMessage)
                    timeline.turns[turnIndex].items.append(
                        ThreadTurnItem(
                            id: progressMessage.id,
                            kind: .progress,
                            message: progressMessage
                        )
                    )
                    turn.assistantText = ""
                    turn.assistantStartedAt = nil
                    shouldScheduleLiveTextFlush = false
                    grokLiveTextFlushTasks.removeValue(forKey: key)?.cancel()
                    liveAssistantTextByThreadKey.removeValue(forKey: key)
                }
            }
            guard let toolCallID = update["toolCallId"]?.stringValue else { break }
            let messageID = turn.toolMessageIDs[toolCallID]
                ?? "grok-tool-\(toolCallID)"
            turn.toolMessageIDs[toolCallID] = messageID
            let title = update["title"]?.stringValue
                ?? transcript.messages.first(where: { $0.id == messageID })?.text
                    .split(separator: "\n", maxSplits: 1).first.map(String.init)
                ?? "Grok tool"
            let status = update["status"]?.stringValue ?? "in progress"
            let text = "\(title)\nStatus: \(status.replacingOccurrences(of: "_", with: " "))"
            Self.replaceGrokMessage(
                id: messageID,
                role: .tool,
                text: text,
                kind: .tool,
                transcript: &transcript,
                turn: &timeline.turns[turnIndex]
            )

        case "plan":
            let entries = (update["entries"]?.arrayValue ?? []).compactMap { entry in
                entry["content"]?.stringValue ?? entry["title"]?.stringValue
            }
            guard !entries.isEmpty else { break }
            let messageID = turn.planMessageID ?? "grok-plan-\(UUID().uuidString.lowercased())"
            turn.planMessageID = messageID
            Self.replaceGrokMessage(
                id: messageID,
                role: .reasoning,
                text: entries.map { "• \($0)" }.joined(separator: "\n"),
                kind: .reasoning,
                transcript: &transcript,
                turn: &timeline.turns[turnIndex]
            )

        case "turn_completed":
            turn.reportedStopReason = update["stop_reason"]?.stringValue

        default:
            break
        }

        transcript.turnTimeline = timeline
        transcript.lastUpdatedAt = Date()
        activeTranscripts[key] = transcript
        grokTurns[key] = turn
        if shouldScheduleLiveTextFlush {
            scheduleGrokLiveTextFlush(for: key)
        }
    }

    private func scheduleGrokLiveTextFlush(for key: String) {
        guard grokLiveTextFlushTasks[key] == nil else { return }
        grokLiveTextFlushTasks[key] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
            self?.flushGrokLiveText(for: key)
        }
    }

    private func flushGrokLiveText(for key: String) {
        grokLiveTextFlushTasks[key] = nil
        guard let text = grokTurns[key]?.assistantText,
              liveAssistantTextByThreadKey[key] != text else {
            return
        }
        liveAssistantTextByThreadKey[key] = text
    }

    private func handleGrokPermissionRequest(
        _ request: GrokACPPermissionRequest,
        connection: GrokACPConnection,
        threadRef: ThreadRef
    ) {
        let key = threadRef.qualifiedID
        let attentionID = "grok:\(threadRef.threadID):\(request.requestID.stringValue)"
        let toolTitle = request.toolCall["title"]?.stringValue ?? "Grok tool"
        let options = request.options.map { option in
            JSONValue.object([
                "id": .string(option.id),
                "label": .string(option.name),
                "kind": .string(option.kind),
            ])
        }
        let attention = RuntimeAttentionRequest(
            id: attentionID,
            hostID: threadRef.hostID,
            requestID: request.requestID,
            method: "session/request_permission",
            threadID: threadRef.threadID,
            turnID: grokTurns[key]?.turnID,
            summary: "Grok wants permission to run \(toolTitle)",
            requestParams: .object([
                "provider": .string(AgentProvider.grok.rawValue),
                "cwd": .string(threadRef.cwd),
                "toolCall": request.toolCall,
                "options": .array(options),
            ])
        )
        grokPermissions[attentionID] = PendingGrokPermission(
            threadKey: key,
            connection: connection,
            request: request
        )
        pendingAttentionRequests.removeAll { $0.id == attentionID }
        pendingAttentionRequests.append(attention)
        pendingAttentionRequests.sort { $0.createdAt < $1.createdAt }
        runStatusByThreadKey[key] = .needsInput
        lastActivityByThreadKey[key] = attention.createdAt

        if var transcript = activeTranscripts[key],
           var timeline = transcript.turnTimeline,
           let index = timeline.turns.indices.last {
            timeline.turns[index].status = .needsInput
            transcript.turnTimeline = timeline
            transcript.lastUpdatedAt = Date()
            activeTranscripts[key] = transcript
        }
    }

    private func finalizeGrokTurn(
        threadRef: ThreadRef,
        stopReason: String,
        error: String?
    ) async throws {
        let key = threadRef.qualifiedID
        guard var transcript = activeTranscripts[key],
              let turn = grokTurns.removeValue(forKey: key),
              var timeline = transcript.turnTimeline,
              let turnIndex = timeline.turns.indices.last else {
            return
        }
        let completedAt = Date()
        grokLiveTextFlushTasks.removeValue(forKey: key)?.cancel()
        if !turn.assistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let assistantMessage = ThreadMessage(
                role: .assistant,
                text: turn.assistantText,
                createdAt: turn.assistantStartedAt ?? completedAt
            )
            transcript.messages.append(assistantMessage)
            timeline.turns[turnIndex].items.append(
                ThreadTurnItem(
                    id: assistantMessage.id,
                    kind: .assistantMessage,
                    message: assistantMessage
                )
            )
        }
        let resolvedStopReason = turn.reportedStopReason ?? stopReason
        timeline.turns[turnIndex].status = error == nil && resolvedStopReason != "refusal"
            ? .complete
            : .failed
        timeline.turns[turnIndex].completedAt = completedAt
        timeline.turns[turnIndex].durationMilliseconds = max(
            0,
            Int(completedAt.timeIntervalSince(turn.startedAt) * 1_000)
        )
        timeline.turns[turnIndex].error = error
        transcript.turnTimeline = timeline
        transcript.lastUpdatedAt = completedAt
        activeTranscripts[key] = transcript
        runStatusByThreadKey[key] = timeline.turns[turnIndex].status
        lastActivityByThreadKey[key] = completedAt
        liveAssistantTextByThreadKey.removeValue(forKey: key)
        pendingAttentionRequests.removeAll {
            $0.threadID == threadRef.threadID && $0.method == "session/request_permission"
        }
        grokPermissions = grokPermissions.filter { $0.value.threadKey != key }
        try await repository.saveTranscript(transcript)
        activeTranscripts.removeValue(forKey: key)
    }

    private func materializeGrokFork(
        _ text: String,
        attachmentLines: [String],
        transcript: inout ThreadTranscript,
        model: String?,
        reasoningEffort: String?,
        executableURL: URL
    ) async throws {
        guard let sourceSessionID = transcript.providerMetadata?.forkedFromSessionID else {
            throw AgentProviderRuntimeError.commandFailed(.grok, "The Grok fork is missing its source session.")
        }
        let prompt = attachmentLines.isEmpty
            ? text
            : "\(text)\n\nFiles available to this task:\n\(attachmentLines.joined(separator: "\n"))"
        let startedAt = Date()
        let arguments = Self.grokForkArguments(
            prompt: prompt,
            cwd: transcript.threadRef.cwd,
            sourceSessionID: sourceSessionID,
            forkSessionID: transcript.threadRef.threadID,
            model: model,
            reasoningEffort: reasoningEffort
        )
        let result = try await client.run(
            executableURL,
            arguments,
            URL(fileURLWithPath: transcript.threadRef.cwd, isDirectory: true),
            30 * 60
        )
        guard result.terminationStatus == 0 else {
            throw AgentProviderRuntimeError.commandFailed(.grok, Self.commandFailureDetail(result))
        }
        let assistantText = Self.assistantText(from: result.stdout.stringValue, provider: .grok)
        guard !assistantText.isEmpty else {
            throw AgentProviderRuntimeError.emptyResponse(.grok)
        }
        let completedAt = Date()
        let userMessage = ThreadMessage(role: .user, text: prompt, createdAt: startedAt)
        let assistantMessage = ThreadMessage(role: .assistant, text: assistantText, createdAt: completedAt)
        var timeline = transcript.turnTimeline ?? ThreadTurnTimeline.fromTranscript(transcript)
        transcript.messages.append(contentsOf: [userMessage, assistantMessage])
        timeline.turns.append(
            ThreadTurn(
                id: "grok-fork-turn-\(UUID().uuidString.lowercased())",
                status: .complete,
                startedAt: startedAt,
                completedAt: completedAt,
                durationMilliseconds: max(0, Int(completedAt.timeIntervalSince(startedAt) * 1_000)),
                items: [
                    ThreadTurnItem(id: userMessage.id, kind: .userMessage, message: userMessage),
                    ThreadTurnItem(id: assistantMessage.id, kind: .assistantMessage, message: assistantMessage),
                ]
            )
        )
        transcript.turnTimeline = timeline
        var providerMetadata = transcript.providerMetadata
            ?? ProviderThreadMetadata(sessionID: transcript.threadRef.threadID)
        providerMetadata.isSessionMaterialized = true
        providerMetadata.modelID = model ?? providerMetadata.modelID
        providerMetadata.reasoningEffort = reasoningEffort ?? providerMetadata.reasoningEffort
        transcript.providerMetadata = providerMetadata
        transcript.lastUpdatedAt = completedAt
        try await repository.saveTranscript(transcript)
    }

    private static func grokPromptContent(
        text: String,
        attachments: [ChatInputAttachment]
    ) -> [JSONValue] {
        var content: [JSONValue] = []
        if !text.isEmpty {
            content.append(.object([
                "type": .string("text"),
                "text": .string(text),
            ]))
        }
        for attachment in attachments {
            guard let path = attachment.sourcePath, !path.isEmpty else { continue }
            var resource: [String: JSONValue] = [
                "type": .string("resource_link"),
                "name": .string(attachment.name),
                "uri": .string(URL(fileURLWithPath: path).absoluteString),
            ]
            if let mimeType = attachment.mimeType {
                resource["mimeType"] = .string(mimeType)
            }
            if let byteCount = attachment.byteCount {
                resource["size"] = .number(Double(byteCount))
            }
            content.append(.object(resource))
        }
        return content
    }

    private static func grokMetadata(
        from response: JSONValue,
        fallbackSessionID: String
    ) -> ProviderThreadMetadata {
        let detail = response["_meta"]?["x.ai/sessionDetail"]
        let configOptions = response["_meta"]?["x.ai/sessionConfig"]?["options"]?.arrayValue ?? []
        let selectedModel = configOptions.first {
            $0["category"]?.stringValue == "model" && $0["selected"]?.boolValue == true
        }?["id"]?.stringValue
        let selectedEffort = configOptions.first {
            $0["category"]?.stringValue == "mode" && $0["selected"]?.boolValue == true
        }?["id"]?.stringValue
        return ProviderThreadMetadata(
            sessionID: detail?["sessionId"]?.stringValue ?? fallbackSessionID,
            generatedTitle: detail?["title"]?.stringValue,
            isSessionMaterialized: true,
            modelID: detail?["currentModelId"]?.stringValue
                ?? response["models"]?["currentModelId"]?.stringValue
                ?? selectedModel,
            reasoningEffort: selectedEffort
        )
    }

    private static func merging(
        _ current: ProviderThreadMetadata?,
        with loaded: ProviderThreadMetadata
    ) -> ProviderThreadMetadata {
        ProviderThreadMetadata(
            sessionID: loaded.sessionID ?? current?.sessionID,
            generatedTitle: loaded.generatedTitle ?? current?.generatedTitle,
            forkedFromSessionID: current?.forkedFromSessionID,
            isSessionMaterialized: loaded.isSessionMaterialized,
            modelID: loaded.modelID ?? current?.modelID,
            reasoningEffort: loaded.reasoningEffort ?? current?.reasoningEffort,
            prefersGeneratedTitle: current?.prefersGeneratedTitle
        )
    }

    private static func upsertGrokMessage(
        id: String,
        role: ThreadMessageRole,
        appendedText: String,
        kind: ThreadTurnItemKind,
        transcript: inout ThreadTranscript,
        turn: inout ThreadTurn
    ) {
        if let index = transcript.messages.firstIndex(where: { $0.id == id }) {
            transcript.messages[index].text += appendedText
            if let itemIndex = turn.items.firstIndex(where: { $0.message.id == id }) {
                turn.items[itemIndex].message = transcript.messages[index]
            }
            return
        }
        let message = ThreadMessage(id: id, role: role, text: appendedText)
        transcript.messages.append(message)
        turn.items.append(ThreadTurnItem(id: id, kind: kind, message: message))
    }

    private static func replaceGrokMessage(
        id: String,
        role: ThreadMessageRole,
        text: String,
        kind: ThreadTurnItemKind,
        transcript: inout ThreadTranscript,
        turn: inout ThreadTurn
    ) {
        if let index = transcript.messages.firstIndex(where: { $0.id == id }) {
            transcript.messages[index].text = text
            if let itemIndex = turn.items.firstIndex(where: { $0.message.id == id }) {
                turn.items[itemIndex].message = transcript.messages[index]
            }
            return
        }
        let message = ThreadMessage(id: id, role: role, text: text)
        transcript.messages.append(message)
        turn.items.append(ThreadTurnItem(id: id, kind: kind, message: message))
    }

    private static func grokDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    #endif

    nonisolated static func normalizedGrokTranscript(_ transcript: ThreadTranscript) -> ThreadTranscript {
        var normalized = transcript
        normalized.messages = transcript.messages.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.createdAt == rhs.element.createdAt {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.createdAt < rhs.element.createdAt
            }
            .map(\.element)

        guard let timeline = transcript.turnTimeline else {
            return normalized
        }

        let timelineMessageIDs = Set(
            timeline.turns.flatMap(\.items).map { $0.message.id }
        )
        let transcriptMessageIDs = Set(normalized.messages.map(\.id))
        if !transcriptMessageIDs.isSubset(of: timelineMessageIDs) {
            normalized.turnTimeline = ThreadTurnTimeline.fromTranscript(normalized)
        } else {
            normalized.turnTimeline = timeline.reconciled(with: normalized)
        }
        return normalized
    }

    public nonisolated static func modelOptions(
        from output: String,
        provider: AgentProvider
    ) -> [AgentModelOption] {
        let stripped = strippedTerminalOutput(output)

        if let data = stripped.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let jsonModels = modelRecords(in: object),
           !jsonModels.isEmpty {
            return finalizedModels(jsonModels, provider: provider)
        }

        var records: [(id: String, displayName: String, isDefault: Bool)] = []
        var isInGrokModelSection = provider != .grok
        var grokDefaultModelID: String?
        for rawLine in stripped.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let lowercased = line.lowercased()

            if provider == .grok {
                if lowercased.hasPrefix("default model:") {
                    grokDefaultModelID = line
                        .dropFirst("default model:".count)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .split(whereSeparator: \.isWhitespace)
                        .first
                        .map(String.init)
                    continue
                }
                if lowercased.hasPrefix("available models") {
                    isInGrokModelSection = true
                    continue
                }
                guard isInGrokModelSection,
                      let first = line.first,
                      "-*•>✓✔".contains(first)
                else {
                    continue
                }
            }

            if lowercased == "models"
                || lowercased.contains("available models")
                || lowercased.hasPrefix("usage:")
                || lowercased.hasPrefix("error:") {
                continue
            }

            while let first = line.first, "-*•>✓✔".contains(first) {
                line.removeFirst()
                line = line.trimmingCharacters(in: .whitespaces)
            }
            let defaultModel = line.lowercased().contains("default")
            let columns = line.components(separatedBy: "\t").filter { !$0.isEmpty }
            let firstColumn = columns.first ?? line
            let id = firstColumn.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            if ["id", "model", "models"].contains(id.lowercased()) {
                continue
            }
            guard isPlausibleModelID(id) else { continue }
            let displayName = columns.count > 1
                ? columns[1].trimmingCharacters(in: .whitespacesAndNewlines)
                : id
            records.append(
                (
                    id: id,
                    displayName: displayName.isEmpty ? id : displayName,
                    isDefault: defaultModel || id == grokDefaultModelID
                )
            )
        }
        return finalizedModels(records, provider: provider)
    }

    public nonisolated static func assistantText(
        from output: String,
        provider: AgentProvider
    ) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard provider == .grok,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return trimmed
        }
        return firstText(in: object)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
    }

    nonisolated static func grokForkArguments(
        prompt: String,
        cwd: String,
        sourceSessionID: String,
        forkSessionID: String,
        model: String?,
        reasoningEffort: String?
    ) -> [String] {
        var arguments = [
            "--no-auto-update",
            "-p", prompt,
            "--output-format", "json",
            "--cwd", cwd,
            "--resume", sourceSessionID,
            "--fork-session",
            "--session-id", forkSessionID,
            "--permission-mode", "dontAsk",
        ]
        if let model, !model.isEmpty {
            arguments += ["--model", model]
        }
        if let reasoningEffort, !reasoningEffort.isEmpty {
            arguments += ["--effort", reasoningEffort]
        }
        return arguments
    }

    private nonisolated static func finalizedModels(
        _ records: [(id: String, displayName: String, isDefault: Bool)],
        provider: AgentProvider
    ) -> [AgentModelOption] {
        var seen = Set<String>()
        let unique = records.filter { seen.insert($0.id).inserted }
        let hasDeclaredDefault = unique.contains(where: \.isDefault)
        return unique.enumerated().map { index, record in
            AgentModelOption(
                id: record.id,
                provider: provider,
                displayName: record.displayName,
                isDefault: record.isDefault || (!hasDeclaredDefault && index == 0)
            )
        }
    }

    private nonisolated static func modelRecords(
        in object: Any
    ) -> [(id: String, displayName: String, isDefault: Bool)]? {
        let values: [Any]
        if let array = object as? [Any] {
            values = array
        } else if let dictionary = object as? [String: Any],
                  let array = (dictionary["models"] ?? dictionary["data"]) as? [Any] {
            values = array
        } else {
            return nil
        }

        let records = values.compactMap { value -> (String, String, Bool)? in
            if let id = value as? String, isPlausibleModelID(id) {
                return (id, id, false)
            }
            guard let dictionary = value as? [String: Any],
                  let id = (dictionary["id"] ?? dictionary["model"]) as? String,
                  isPlausibleModelID(id) else {
                return nil
            }
            let displayName = (dictionary["displayName"] ?? dictionary["display_name"] ?? dictionary["name"]) as? String ?? id
            let isDefault = dictionary["isDefault"] as? Bool
                ?? dictionary["is_default"] as? Bool
                ?? false
            return (id, displayName, isDefault)
        }
        return records
    }

    private nonisolated static func isPlausibleModelID(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.rangeOfCharacter(from: .letters) != nil else {
            return false
        }
        return value.range(of: "^[A-Za-z0-9][A-Za-z0-9._:/-]*$", options: .regularExpression) != nil
    }

    private nonisolated static func firstText(in object: Any) -> String? {
        if let text = object as? String {
            return text
        }
        if let dictionary = object as? [String: Any] {
            for key in ["result", "output_text", "text", "content", "message"] {
                if let value = dictionary[key], let text = firstText(in: value), !text.isEmpty {
                    return text
                }
            }
            for value in dictionary.values {
                if let text = firstText(in: value), !text.isEmpty {
                    return text
                }
            }
        }
        if let array = object as? [Any] {
            for value in array {
                if let text = firstText(in: value), !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    private nonisolated static func prompt(
        text: String,
        attachmentLines: [String],
        provider: AgentProvider,
        previousMessages: [ThreadMessage]
    ) -> String {
        var current = text
        if !attachmentLines.isEmpty {
            current += "\n\nFiles available to this task:\n\(attachmentLines.joined(separator: "\n"))"
        }
        guard provider == .gemini, !previousMessages.isEmpty else { return current }

        let history = previousMessages.suffix(40).map { message in
            "\(message.role.rawValue.capitalized): \(message.text)"
        }.joined(separator: "\n\n")
        let boundedHistory = String(history.suffix(120_000))
        return "Continue the same MapofAgents thread using this recent transcript as context.\n\n\(boundedHistory)\n\nUser: \(current)"
    }

    private nonisolated static func promptArguments(
        provider: AgentProvider,
        prompt: String,
        threadRef: ThreadRef,
        model: String?,
        reasoningEffort: String?,
        isNewSession: Bool
    ) -> [String] {
        var arguments: [String]
        switch provider {
        case .codex:
            return []
        case .gemini:
            arguments = ["--print", prompt, "--print-timeout", "30m"]
        case .grok:
            arguments = [
                "-p", prompt,
                "--output-format", "plain",
                "--no-auto-update",
                "--cwd", threadRef.cwd,
            ]
            if isNewSession {
                arguments += ["--session-id", threadRef.threadID]
            } else {
                arguments += ["--resume", threadRef.threadID]
            }
        }
        if let model, !model.isEmpty {
            arguments += ["--model", model]
        }
        if let reasoningEffort, !reasoningEffort.isEmpty {
            arguments += ["--effort", reasoningEffort]
        }
        return arguments
    }

    private nonisolated static func commandFailureDetail(_ result: BoundedProcessResult) -> String {
        let stderr = result.stderr.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = result.stdout.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = stderr.isEmpty ? stdout : stderr
        return detail.isEmpty ? "Command exited with status \(result.terminationStatus)." : detail
    }

    private nonisolated static func requiresAuthentication(_ result: BoundedProcessResult) -> Bool {
        let output = strippedTerminalOutput(
            result.stdout.stringValue + "\n" + result.stderr.stringValue
        ).lowercased()
        return [
            "you are not authenticated",
            "no auth credentials",
            "run `grok login` first",
            "run 'grok login' first",
            "authentication required",
            "not logged in",
        ].contains(where: output.contains)
    }

    private nonisolated static func strippedTerminalOutput(_ output: String) -> String {
        output.replacingOccurrences(
            of: "\\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
    }
}

#if os(macOS)
private struct ActiveGrokTurn {
    var turnID: String
    var startedAt: Date
    var assistantText = ""
    var assistantStartedAt: Date?
    var reasoningMessageID: String?
    var planMessageID: String?
    var toolMessageIDs: [String: String] = [:]
    var reportedStopReason: String?
}

private struct PendingGrokPermission {
    var threadKey: String
    var connection: GrokACPConnection
    var request: GrokACPPermissionRequest
}
#endif
