import Foundation

public struct AppServerEndpointVerification: Hashable, Sendable {
    public var initializeResult: JSONValue

    public init(initializeResult: JSONValue) {
        self.initializeResult = initializeResult
    }

    public var codexHome: String? {
        initializeResult["codexHome"]?.stringValue
    }
}

public enum AppServerEndpointVerifier {
    public static func verify(
        url: URL,
        bearerToken: String?,
        timeout: TimeInterval = 3
    ) async throws -> AppServerEndpointVerification {
        try await withThrowingTaskGroup(of: AppServerEndpointVerification.self) { group in
            group.addTask {
                try await verifyWithoutTimeout(url: url, bearerToken: bearerToken)
            }
            group.addTask {
                try await Task.sleep(for: .milliseconds(Int(timeout * 1_000)))
                throw CodexAppServerError.transport("Timed out verifying Codex App Server.")
            }

            guard let result = try await group.next() else {
                throw CodexAppServerError.invalidResponse
            }
            group.cancelAll()
            return result
        }
    }

    private static func verifyWithoutTimeout(url: URL, bearerToken: String?) async throws -> AppServerEndpointVerification {
        if let securityError = AppServerRelayEndpoint.connectionSecurityError(url: url, bearerToken: bearerToken) {
            throw CodexAppServerError.transport(securityError)
        }

        var request = URLRequest(url: url)
        if let bearerToken = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
        }

        let initialize: JSONValue = .object([
            "id": .number(1),
            "method": .string("initialize"),
            "params": .object([
                "clientInfo": .object([
                    "name": .string("mapofagents-pairing-verifier"),
                    "title": .string("mapofagents pairing verifier"),
                    "version": .string("0.1.0"),
                ]),
                "capabilities": .object([
                    "experimentalApi": .bool(true),
                ]),
            ]),
        ])
        let data = try JSONEncoder().encode(initialize)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CodexAppServerError.invalidResponse
        }
        try await task.send(.string(text))

        let response = try await task.receive()
        let responseData: Data
        switch response {
        case .data(let data):
            responseData = data
        case .string(let text):
            responseData = Data(text.utf8)
        @unknown default:
            throw CodexAppServerError.invalidResponse
        }

        guard
            let value = try? JSONDecoder().decode(JSONValue.self, from: responseData),
            let object = value.objectValue,
            object["id"]?.intValue == 1
        else {
            throw CodexAppServerError.invalidResponse
        }

        if let error = object["error"] {
            throw CodexAppServerError.server(readableDescription(error))
        }

        let result = object["result"] ?? .null
        guard isTrustedInitializeResult(result) else {
            throw CodexAppServerError.invalidResponse
        }

        let initialized: JSONValue = .object(["method": .string("initialized")])
        if let initializedData = try? JSONEncoder().encode(initialized),
           let initializedText = String(data: initializedData, encoding: .utf8) {
            try? await task.send(.string(initializedText))
        }

        return AppServerEndpointVerification(initializeResult: result)
    }

    static func isTrustedInitializeResult(_ result: JSONValue) -> Bool {
        guard result.objectValue != nil else {
            return false
        }
        let hasCodexHome = result["codexHome"]?.stringValue?.nilIfEmpty != nil
        let hasPlatform = result["platformFamily"]?.stringValue?.nilIfEmpty != nil
            || result["platformOs"]?.stringValue?.nilIfEmpty != nil
        let serverName = result["serverName"]?.stringValue
            ?? result["serverInfo"]?["name"]?.stringValue
            ?? result["serverInfo"]?["title"]?.stringValue
        let hasCodexNamedServer = serverName?.localizedCaseInsensitiveContains("codex") == true
        let hasCapabilities = result["capabilities"]?.objectValue != nil
        return (hasCodexHome || hasPlatform || hasCodexNamedServer) && (hasCapabilities || hasCodexNamedServer)
    }

    private static func readableDescription(_ value: JSONValue) -> String {
        if let message = value["message"]?.stringValue {
            return message
        }
        if let string = value.stringValue {
            return string
        }
        return "\(value)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
