import Foundation

public struct GrokACPInitialization: Sendable, Hashable {
    public var protocolVersion: Int
    public var supportsLoadSession: Bool
    public var supportsSessionResume: Bool
    public var supportsSessionList: Bool
    public var supportsSessionFork: Bool
    public var modelOptions: [AgentModelOption]
    public var agentVersion: String?

    public init(
        protocolVersion: Int,
        supportsLoadSession: Bool,
        supportsSessionResume: Bool,
        supportsSessionList: Bool,
        supportsSessionFork: Bool,
        modelOptions: [AgentModelOption],
        agentVersion: String?
    ) {
        self.protocolVersion = protocolVersion
        self.supportsLoadSession = supportsLoadSession
        self.supportsSessionResume = supportsSessionResume
        self.supportsSessionList = supportsSessionList
        self.supportsSessionFork = supportsSessionFork
        self.modelOptions = modelOptions
        self.agentVersion = agentVersion
    }
}

public struct GrokACPPermissionRequest: Sendable, Hashable {
    public struct Option: Sendable, Hashable {
        public var id: String
        public var name: String
        public var kind: String

        public init(id: String, name: String, kind: String) {
            self.id = id
            self.name = name
            self.kind = kind
        }
    }

    public var requestID: JSONRPCRequestID
    public var sessionID: String
    public var toolCall: JSONValue
    public var options: [Option]

    public init(
        requestID: JSONRPCRequestID,
        sessionID: String,
        toolCall: JSONValue,
        options: [Option]
    ) {
        self.requestID = requestID
        self.sessionID = sessionID
        self.toolCall = toolCall
        self.options = options
    }
}

public enum GrokACPError: LocalizedError, Sendable {
    case unsupportedPlatform
    case processExited(String)
    case invalidResponse(String)
    case requestFailed(code: Int?, message: String)
    case requestTimedOut(String)
    case authenticationRequired
    case unsupportedCapability(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "Grok ACP is available in the macOS app."
        case .processExited(let detail):
            return detail.isEmpty ? "The Grok ACP process exited." : "The Grok ACP process exited. \(detail)"
        case .invalidResponse(let detail):
            return "Grok ACP returned an invalid response. \(detail)"
        case .requestFailed(_, let message):
            return "Grok ACP request failed. \(message)"
        case .requestTimedOut(let method):
            return "Grok ACP did not answer \(method) before the request timed out."
        case .authenticationRequired:
            return "Grok ACP could not use the cached sign-in. Sign in again, then refresh providers."
        case .unsupportedCapability(let capability):
            return "This Grok CLI does not advertise \(capability)."
        }
    }
}

#if os(macOS)
@MainActor
public final class GrokACPConnection {
    public typealias NotificationHandler = @MainActor (String, JSONValue) -> Void
    public typealias PermissionHandler = @MainActor (GrokACPPermissionRequest) -> Void

    public var onNotification: NotificationHandler?
    public var onPermissionRequest: PermissionHandler?

    private let executableURL: URL
    private let modelID: String?
    private let reasoningEffort: String?
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var nextRequestID = 1
    private struct PendingRequest {
        var method: String
        var continuation: CheckedContinuation<JSONValue, Error>
        var timeoutTask: Task<Void, Never>?
    }

    private var pendingRequests: [Int: PendingRequest] = [:]
    private var isClosed = false

    public private(set) var initialization: GrokACPInitialization?

    public init(
        executableURL: URL,
        modelID: String? = nil,
        reasoningEffort: String? = nil
    ) {
        self.executableURL = executableURL
        self.modelID = modelID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.reasoningEffort = reasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public func start() async throws -> GrokACPInitialization {
        guard !process.isRunning else {
            guard let initialization else {
                throw GrokACPError.invalidResponse("Initialization is still in progress.")
            }
            return initialization
        }

        process.executableURL = executableURL
        var arguments = ["--no-auto-update"]
        if let modelID {
            arguments += ["--model", modelID]
        }
        if let reasoningEffort {
            arguments += ["--effort", reasoningEffort]
        }
        arguments += ["agent", "stdio"]
        process.arguments = arguments
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in
                self?.receiveStdout(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in
                self?.receiveStderr(data)
            }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor [weak self] in
                self?.processDidExit(status: status)
            }
        }

        do {
            try process.run()
            let response = try await request(
                method: "initialize",
                params: .object([
                    "protocolVersion": .number(1),
                    "clientCapabilities": .object([
                        "fs": .object([
                            "readTextFile": .bool(false),
                            "writeTextFile": .bool(false),
                        ]),
                        "terminal": .bool(false),
                    ]),
                    "clientInfo": .object([
                        "name": .string("MapofAgents"),
                        "title": .string("MapofAgents"),
                        "version": .string("1"),
                    ]),
                ])
            )
            let initialization = try Self.parseInitialization(response)
            self.initialization = initialization

            let authMethods = response["authMethods"]?.arrayValue ?? []
            if authMethods.contains(where: { $0["id"]?.stringValue == "cached_token" }) {
                do {
                    _ = try await request(
                        method: "authenticate",
                        params: .object([
                            "methodId": .string("cached_token"),
                            "_meta": .object(["headless": .bool(true)]),
                        ])
                    )
                } catch {
                    throw GrokACPError.authenticationRequired
                }
            } else if !authMethods.isEmpty {
                throw GrokACPError.authenticationRequired
            }

            return initialization
        } catch {
            shutdown()
            throw error
        }
    }

    public func createSession(cwd: String) async throws -> (sessionID: String, response: JSONValue) {
        let response = try await request(
            method: "session/new",
            params: .object([
                "cwd": .string(cwd),
                "mcpServers": .array([]),
            ])
        )
        guard let sessionID = response["sessionId"]?.stringValue, !sessionID.isEmpty else {
            throw GrokACPError.invalidResponse("session/new did not return a session ID.")
        }
        return (sessionID, response)
    }

    public func loadSession(sessionID: String, cwd: String) async throws -> JSONValue {
        guard initialization?.supportsLoadSession == true else {
            throw GrokACPError.unsupportedCapability("session loading")
        }
        return try await request(
            method: "session/load",
            params: .object([
                "sessionId": .string(sessionID),
                "cwd": .string(cwd),
                "mcpServers": .array([]),
            ])
        )
    }

    public func prompt(sessionID: String, content: [JSONValue]) async throws -> JSONValue {
        try await request(
            method: "session/prompt",
            params: .object([
                "sessionId": .string(sessionID),
                "prompt": .array(content),
            ])
        )
    }

    public func cancel(sessionID: String) throws {
        try send(
            .object([
                "jsonrpc": .string("2.0"),
                "method": .string("session/cancel"),
                "params": .object(["sessionId": .string(sessionID)]),
            ])
        )
    }

    public func respondToPermission(requestID: JSONRPCRequestID, optionID: String?) throws {
        let outcome: JSONValue
        if let optionID {
            outcome = .object([
                "outcome": .string("selected"),
                "optionId": .string(optionID),
            ])
        } else {
            outcome = .object(["outcome": .string("cancelled")])
        }
        try send(
            .object([
                "jsonrpc": .string("2.0"),
                "id": requestID.jsonValue,
                "result": .object(["outcome": outcome]),
            ])
        )
    }

    public func shutdown() {
        guard !isClosed else { return }
        isClosed = true
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
        finishPendingRequests(with: GrokACPError.processExited(stderrText))
        try? stdinPipe.fileHandleForWriting.close()
    }

    private func request(method: String, params: JSONValue) async throws -> JSONValue {
        guard !isClosed else {
            throw GrokACPError.processExited(stderrText)
        }
        let id = nextRequestID
        nextRequestID += 1
        let timeout: Duration = method == "session/prompt" ? .seconds(30 * 60) : .seconds(30)
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = PendingRequest(
                method: method,
                continuation: continuation,
                timeoutTask: nil
            )
            let timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.timeOutRequest(id: id)
            }
            pendingRequests[id]?.timeoutTask = timeoutTask
            do {
                try send(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": .number(Double(id)),
                        "method": .string(method),
                        "params": params,
                    ])
                )
            } catch {
                pendingRequests.removeValue(forKey: id)?.timeoutTask?.cancel()
                continuation.resume(throwing: error)
            }
        }
    }

    private func send(_ value: JSONValue) throws {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        try stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func receiveStdout(_ data: Data) {
        guard !data.isEmpty else { return }
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = Data(stdoutBuffer[..<newline])
            stdoutBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            do {
                let value = try JSONDecoder().decode(JSONValue.self, from: line)
                handleEnvelope(value)
            } catch {
                finishPendingRequests(with: GrokACPError.invalidResponse(error.localizedDescription))
            }
        }
    }

    private func receiveStderr(_ data: Data) {
        guard !data.isEmpty else { return }
        let remaining = max(0, 64 * 1_024 - stderrBuffer.count)
        if remaining > 0 {
            stderrBuffer.append(data.prefix(remaining))
        }
    }

    private func handleEnvelope(_ envelope: JSONValue) {
        if let requestID = JSONRPCRequestID(envelope["id"]),
           let method = envelope["method"]?.stringValue {
            if method == "session/request_permission",
               let permission = Self.permissionRequest(id: requestID, params: envelope["params"]) {
                onPermissionRequest?(permission)
            } else {
                try? send(
                    .object([
                        "jsonrpc": .string("2.0"),
                        "id": requestID.jsonValue,
                        "error": .object([
                            "code": .number(-32601),
                            "message": .string("MapofAgents does not support \(method)."),
                        ]),
                    ])
                )
            }
            return
        }

        if let method = envelope["method"]?.stringValue {
            onNotification?(method, envelope["params"] ?? .null)
            return
        }

        guard let id = envelope["id"]?.intValue,
              let pending = pendingRequests.removeValue(forKey: id) else {
            return
        }
        pending.timeoutTask?.cancel()
        if let error = envelope["error"] {
            pending.continuation.resume(
                throwing: GrokACPError.requestFailed(
                    code: error["code"]?.intValue,
                    message: error["message"]?.stringValue ?? "Unknown JSON-RPC error"
                )
            )
        } else if let result = envelope["result"] {
            pending.continuation.resume(returning: result)
        } else {
            pending.continuation.resume(throwing: GrokACPError.invalidResponse("Missing result."))
        }
    }

    private func timeOutRequest(id: Int) {
        guard let pending = pendingRequests.removeValue(forKey: id) else { return }
        pending.continuation.resume(throwing: GrokACPError.requestTimedOut(pending.method))
    }

    private func processDidExit(status: Int32) {
        guard !isClosed else { return }
        isClosed = true
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        let detail = stderrText.isEmpty ? "Exit status \(status)." : stderrText
        finishPendingRequests(with: GrokACPError.processExited(detail))
    }

    private func finishPendingRequests(with error: Error) {
        let requests = pendingRequests.values
        pendingRequests.removeAll()
        for request in requests {
            request.timeoutTask?.cancel()
            request.continuation.resume(throwing: error)
        }
    }

    private var stderrText: String {
        String(data: stderrBuffer, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    nonisolated static func parseInitialization(_ response: JSONValue) throws -> GrokACPInitialization {
        let version = response["protocolVersion"]?.intValue ?? 0
        guard version == 1 else {
            throw GrokACPError.unsupportedCapability("ACP protocol version \(version)")
        }
        let capabilities = response["agentCapabilities"]
        let sessionCapabilities = capabilities?["sessionCapabilities"]
        let metadata = response["_meta"]
        let modelState = metadata?["modelState"]
        let currentModelID = modelState?["currentModelId"]?.stringValue
        let models = (modelState?["availableModels"]?.arrayValue ?? []).compactMap { value -> AgentModelOption? in
            guard let id = value["modelId"]?.stringValue, !id.isEmpty else { return nil }
            let details = value["_meta"]
            let efforts = (details?["reasoningEfforts"]?.arrayValue ?? []).compactMap {
                $0["id"]?.stringValue ?? $0["value"]?.stringValue
            }
            let defaultEffort = (details?["reasoningEfforts"]?.arrayValue ?? []).first {
                $0["default"]?.boolValue == true
            }?["id"]?.stringValue ?? details?["reasoningEffort"]?.stringValue ?? ""
            return AgentModelOption(
                id: id,
                provider: .grok,
                displayName: value["name"]?.stringValue ?? id,
                description: value["description"]?.stringValue ?? "",
                defaultReasoningEffort: defaultEffort,
                supportedReasoningEfforts: efforts,
                isDefault: id == currentModelID
            )
        }
        return GrokACPInitialization(
            protocolVersion: version,
            supportsLoadSession: capabilities?["loadSession"]?.boolValue == true,
            supportsSessionResume: sessionCapabilities?["resume"] != nil,
            supportsSessionList: sessionCapabilities?["list"] != nil,
            supportsSessionFork: sessionCapabilities?["fork"] != nil,
            modelOptions: models,
            agentVersion: metadata?["agentVersion"]?.stringValue
        )
    }

    nonisolated static func permissionRequest(
        id: JSONRPCRequestID,
        params: JSONValue?
    ) -> GrokACPPermissionRequest? {
        guard let params,
              let sessionID = params["sessionId"]?.stringValue,
              let toolCall = params["toolCall"] else {
            return nil
        }
        let options = (params["options"]?.arrayValue ?? []).compactMap { value -> GrokACPPermissionRequest.Option? in
            guard let optionID = value["optionId"]?.stringValue,
                  let name = value["name"]?.stringValue,
                  let kind = value["kind"]?.stringValue else {
                return nil
            }
            return GrokACPPermissionRequest.Option(id: optionID, name: name, kind: kind)
        }
        return GrokACPPermissionRequest(
            requestID: id,
            sessionID: sessionID,
            toolCall: toolCall,
            options: options
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
#endif
