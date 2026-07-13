import Foundation

public enum AppServerSessionTimeoutContext: Sendable {
    case localDaemonProxy
    case localStdio
    case remote(String)
}

public enum AppServerSessionInboundEvent: Sendable {
    case notification(CodexServerNotification)
    case diagnostic(String)
}

/// Transport-independent JSON-RPC session state shared by stdio/proxy and
/// WebSocket clients. It is the sole owner of request IDs, pending
/// continuations, timeout policy, response parsing, and connection-generation
/// matching. Transports only frame and send the resulting JSON value.
public actor AppServerSession {
    public typealias Sender = @Sendable (JSONValue, AppServerConnectionID) async throws -> Void

    private struct PendingRequest {
        var connectionID: AppServerConnectionID
        var method: AppServerMethod
        var continuation: CheckedContinuation<JSONValue, Error>
        var timeoutTask: Task<Void, Never>
    }

    private var nextRequestID = 1
    private var pending: [Int: PendingRequest] = [:]

    public init() {}

    public func request(
        _ call: AppServerCall,
        connectionID: AppServerConnectionID,
        timeoutContext: AppServerSessionTimeoutContext,
        timeoutOverride: Duration? = nil,
        send: @escaping Sender
    ) async throws -> JSONValue {
        let requestID = nextRequestID
        nextRequestID += 1
        let message: JSONValue = .object([
            "id": .number(Double(requestID)),
            "method": .string(call.method.rawValue),
            "params": call.params,
        ])
        let timeout = timeoutOverride ?? .seconds(call.method.timeoutSeconds)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    await self?.timeoutRequest(
                        id: requestID,
                        connectionID: connectionID,
                        context: timeoutContext
                    )
                }
                pending[requestID] = PendingRequest(
                    connectionID: connectionID,
                    method: call.method,
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )

                Task { [weak self] in
                    do {
                        try await send(message, connectionID)
                    } catch {
                        await self?.failRequest(
                            id: requestID,
                            connectionID: connectionID,
                            error: error
                        )
                    }
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.failRequest(
                    id: requestID,
                    connectionID: connectionID,
                    error: CancellationError()
                )
            }
        }
    }

    public func receive(
        _ data: Data,
        connectionID: AppServerConnectionID
    ) -> AppServerSessionInboundEvent? {
        switch Self.parseInboundMessage(data) {
        case .serverRequest(var notification), .notification(var notification):
            notification.connectionID = connectionID
            return .notification(notification)
        case .response(let id, let result, let error):
            guard let request = pending[id], request.connectionID == connectionID else {
                return nil
            }
            pending[id] = nil
            request.timeoutTask.cancel()
            if let error {
                request.continuation.resume(
                    throwing: CodexAppServerError.server(error.appServerReadableDescription)
                )
            } else {
                request.continuation.resume(returning: result ?? .null)
            }
            return nil
        case .invalid(let diagnostic):
            return .diagnostic(diagnostic)
        }
    }

    public func failPending(
        connectionID: AppServerConnectionID? = nil,
        error: CodexAppServerError = .disconnected
    ) {
        let requestIDs = pending.compactMap { requestID, request in
            connectionID == nil || request.connectionID == connectionID ? requestID : nil
        }
        for requestID in requestIDs {
            guard let request = pending.removeValue(forKey: requestID) else { continue }
            request.timeoutTask.cancel()
            request.continuation.resume(
                throwing: Self.requestFailure(error, method: request.method)
            )
        }
    }

    func pendingRequestCount(connectionID: AppServerConnectionID? = nil) -> Int {
        pending.values.count { request in
            connectionID == nil || request.connectionID == connectionID
        }
    }

    private func timeoutRequest(
        id: Int,
        connectionID: AppServerConnectionID,
        context: AppServerSessionTimeoutContext
    ) {
        guard let request = pending[id], request.connectionID == connectionID else { return }
        pending[id] = nil
        request.timeoutTask.cancel()
        request.continuation.resume(
            throwing: Self.timeoutError(method: request.method, context: context)
        )
    }

    private func failRequest(
        id: Int,
        connectionID: AppServerConnectionID,
        error: Error
    ) {
        guard let request = pending[id], request.connectionID == connectionID else { return }
        pending[id] = nil
        request.timeoutTask.cancel()
        request.continuation.resume(
            throwing: Self.requestFailure(error, method: request.method)
        )
    }

    private static func timeoutError(
        method: AppServerMethod,
        context: AppServerSessionTimeoutContext
    ) -> CodexAppServerError {
        if method.replaySafety == .nonReplayableWrite {
            return .ambiguousWrite(method: method.rawValue)
        }
        switch context {
        case .localDaemonProxy:
            return .daemonProxyRequestTimedOut(method: method.rawValue)
        case .localStdio:
            return .transport(
                "Timed out waiting for \(method.rawValue) response from Codex App Server."
            )
        case .remote(let name):
            return .transport(
                "Timed out waiting for \(method.rawValue) response from \(name)."
            )
        }
    }

    private static func requestFailure(_ error: Error, method: AppServerMethod) -> Error {
        guard method.replaySafety == .nonReplayableWrite else { return error }
        if let appServerError = error as? CodexAppServerError {
            switch appServerError {
            case .server,
                 .unsupportedPlatform,
                 .codexNotInstalled,
                 .launchFailed,
                 .daemonProxyHandshakeFailed,
                 .staleServerRequest:
                return error
            case .disconnected,
                 .invalidResponse,
                 .daemonProxyRequestTimedOut,
                 .ambiguousWrite,
                 .transport:
                return CodexAppServerError.ambiguousWrite(method: method.rawValue)
            }
        }

        // A transport may fail after writing only part of a frame. Without an
        // acknowledgement there is no safe way to distinguish that from a
        // committed operation whose response was lost.
        return CodexAppServerError.ambiguousWrite(method: method.rawValue)
    }

    enum InboundMessage: Sendable {
        case serverRequest(CodexServerNotification)
        case response(id: Int, result: JSONValue?, error: JSONValue?)
        case notification(CodexServerNotification)
        case invalid(String)
    }

    nonisolated static func parseInboundMessage(_ data: Data) -> InboundMessage {
        guard
            let value = try? JSONDecoder().decode(JSONValue.self, from: data),
            let object = value.objectValue
        else {
            let preview = String(data: data, encoding: .utf8)?.trimmedForAppServerDisplay
                ?? "<non-UTF8 payload>"
            return .invalid("Invalid JSON-RPC frame from Codex App Server: \(preview)")
        }

        if let requestID = JSONRPCRequestID(object["id"]),
           let method = object["method"]?.stringValue {
            return .serverRequest(
                CodexServerNotification(
                    method: method,
                    params: object["params"],
                    requestID: requestID
                )
            )
        }

        if let rawID = object["id"] {
            guard let id = rawID.intValue else {
                return .invalid(
                    "Unsupported JSON-RPC response id from Codex App Server: \(rawID.appServerReadableDescription)"
                )
            }
            return .response(id: id, result: object["result"], error: object["error"])
        }

        guard let method = object["method"]?.stringValue else {
            return .invalid("Codex App Server message had neither method nor response id.")
        }
        return .notification(
            CodexServerNotification(method: method, params: object["params"])
        )
    }
}

private extension String {
    var trimmedForAppServerDisplay: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 220 else { return trimmed }
        return String(trimmed.prefix(217)) + "..."
    }
}

private extension JSONValue {
    var appServerReadableDescription: String {
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
