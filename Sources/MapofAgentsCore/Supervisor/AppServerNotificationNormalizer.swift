import Foundation

public enum AppServerNotificationNormalizer {
    public static func workflowEvent(from notification: CodexServerNotification, hostID: HostID?) -> WorkflowEvent? {
        let kind: WorkflowEventKind
        let summary: String

        switch notification.method {
        case "turn/started":
            kind = .turnStarted
            summary = "Turn started"
        case "turn/completed":
            kind = .turnCompleted
            summary = "Turn completed"
        default:
            if isTurnFailureNotification(notification.method) {
                kind = .failed
                summary = attentionSummary(method: notification.method, params: notification.params)
            } else if isAttentionMethod(notification.method) {
                kind = .needsInput
                summary = attentionSummary(method: notification.method, params: notification.params)
            } else {
                return nil
            }
        }

        let explicitID: String?
        if kind == .needsInput, let requestID = notification.requestID?.stringValue.nilIfBlank {
            explicitID = WorkflowEvent.stableID(
                kind: kind,
                hostID: hostID,
                threadID: threadID(from: notification.params),
                turnID: "request-\(requestID)",
                method: notification.method,
                summary: summary
            )
        } else {
            explicitID = nil
        }

        return WorkflowEvent(
            id: explicitID,
            kind: kind,
            hostID: hostID,
            threadID: threadID(from: notification.params),
            turnID: turnID(from: notification.params),
            method: notification.method,
            summary: summary,
            createdAt: occurredAt(from: notification.params) ?? Date()
        )
    }

    public static func attentionRequest(
        from notification: CodexServerNotification,
        hostID: HostID
    ) -> RuntimeAttentionRequest? {
        guard isAttentionMethod(notification.method) else {
            return nil
        }

        let requestID = notification.requestID
        let stableID = requestID.map { "\(hostID.rawValue)::\($0.stringValue)" } ?? UUID().uuidString
        return RuntimeAttentionRequest(
            id: stableID,
            hostID: hostID,
            requestID: requestID,
            method: notification.method,
            threadID: threadID(from: notification.params),
            turnID: turnID(from: notification.params),
            summary: attentionSummary(method: notification.method, params: notification.params),
            requestParams: notification.params,
            createdAt: occurredAt(from: notification.params) ?? Date()
        )
    }

    public static func resolvedRequestID(from notification: CodexServerNotification) -> String? {
        guard notification.method == "serverRequest/resolved" else {
            return nil
        }

        guard let params = notification.params else {
            return nil
        }

        for key in ["requestId", "requestID", "request_id", "id"] {
            if let value = params[key]?.stringValue?.nilIfBlank {
                return value
            }
            if let value = params[key]?.intValue {
                return String(value)
            }
        }
        return nil
    }

    public static func threadID(from params: JSONValue?) -> String? {
        params?["threadId"]?.stringValue?.nilIfBlank
            ?? params?["threadID"]?.stringValue?.nilIfBlank
            ?? params?["thread_id"]?.stringValue?.nilIfBlank
            ?? params?["thread"]?["id"]?.stringValue?.nilIfBlank
    }

    public static func turnID(from params: JSONValue?) -> String? {
        params?["turnId"]?.stringValue?.nilIfBlank
            ?? params?["turnID"]?.stringValue?.nilIfBlank
            ?? params?["turn_id"]?.stringValue?.nilIfBlank
            ?? params?["turn"]?["id"]?.stringValue?.nilIfBlank
            ?? params?["turn"]?["turnId"]?.stringValue?.nilIfBlank
            ?? params?["turn"]?["turn_id"]?.stringValue?.nilIfBlank
            ?? params?["id"]?.stringValue?.nilIfBlank
    }

    public static func attentionSummary(method: String, params: JSONValue?) -> String {
        if let command = params?["command"]?.stringValue?.nilIfBlank {
            return command
        }
        if let prompt = params?["prompt"]?.stringValue?.nilIfBlank {
            return prompt
        }
        if let tool = params?["tool"]?.stringValue?.nilIfBlank {
            return tool
        }
        if let message = params?["message"]?.stringValue?.nilIfBlank {
            return message
        }
        if let header = params?["header"]?.stringValue?.nilIfBlank {
            return header
        }
        return method
    }

    public static func isAttentionMethod(_ method: String) -> Bool {
        method.contains("requestApproval")
            || method.contains("requestUserInput")
            || method.contains("elicitation/request")
    }

    public static func isTurnFailureNotification(_ method: String) -> Bool {
        let lowercased = method.lowercased()
        return lowercased.hasPrefix("turn/")
            && (lowercased.contains("fail") || lowercased.contains("error"))
    }

    public static func occurredAt(from params: JSONValue?) -> Date? {
        guard let params else { return nil }
        for candidate in timestampCandidates(from: params) {
            if let date = parseDate(candidate) {
                return date
            }
        }
        return nil
    }

    private static func timestampCandidates(from params: JSONValue) -> [JSONValue] {
        let keys = [
            "timestamp",
            "time",
            "createdAt",
            "created_at",
            "startedAt",
            "started_at",
            "completedAt",
            "completed_at",
            "updatedAt",
            "updated_at",
        ]
        var values: [JSONValue] = keys.compactMap { params[$0] }
        for nestedKey in ["turn", "item", "event", "request"] {
            guard let nested = params[nestedKey] else { continue }
            values.append(contentsOf: keys.compactMap { nested[$0] })
        }
        return values
    }

    private static func parseDate(_ value: JSONValue) -> Date? {
        if let string = value.stringValue?.nilIfBlank {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: string) {
                return date
            }

            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            return standard.date(from: string)
        }

        guard let number = value.doubleValue else {
            return nil
        }

        let seconds = number > 10_000_000_000 ? number / 1_000 : number
        return Date(timeIntervalSince1970: seconds)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
