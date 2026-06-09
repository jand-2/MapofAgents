import Foundation

public enum WorkflowHookEventParser {
    public static func workflowEvent(
        from line: String,
        defaultHostID: HostID?,
        receivedAt: Date = Date()
    ) -> WorkflowEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let payload = try? JSONDecoder().decode(JSONValue.self, from: data),
              let object = payload.objectValue
        else {
            return nil
        }
        return workflowEvent(from: object, defaultHostID: defaultHostID, receivedAt: receivedAt)
    }

    public static func workflowEvent(
        from object: [String: JSONValue],
        defaultHostID: HostID?,
        receivedAt: Date = Date()
    ) -> WorkflowEvent? {
        let method = string(in: object, keys: ["method", "notificationMethod", "notification_method"])
        let rawKind = structuredEventKind(in: object)
            ?? string(in: object, keys: ["workflowEventKind", "workflow_event_kind", "kind", "event", "type"])
            ?? method
        guard let kind = workflowEventKind(
            from: rawKind
        ) else {
            return nil
        }
        let isCreationEvent = kind == .threadCreated || kind == .folderCreated

        let hostID = string(
            in: object,
            keys: isCreationEvent
                ? ["sourceHostID", "sourceHostId", "source_host_id", "sourceHost", "hostID", "hostId", "host_id", "host"]
                : ["hostID", "hostId", "host_id", "host"]
        )
            .map(HostID.init(rawValue:))
            ?? defaultHostID
        let threadID = string(
            in: object,
            keys: isCreationEvent
                ? ["sourceThreadID", "sourceThreadId", "source_thread_id", "sourceSessionID", "sourceSessionId", "source_session_id", "threadID", "threadId", "thread_id", "sessionID", "sessionId", "session_id"]
                : ["threadID", "threadId", "thread_id", "sessionID", "sessionId", "session_id"]
        ) ?? object["thread"]?["id"]?.stringValue?.nilIfBlank
        let turnID = string(
            in: object,
            keys: isCreationEvent
                ? ["sourceTurnID", "sourceTurnId", "source_turn_id", "turnID", "turnId", "turn_id", "rolloutID", "rolloutId", "rollout_id"]
                : ["turnID", "turnId", "turn_id", "rolloutID", "rolloutId", "rollout_id"]
        ) ?? object["turn"]?["id"]?.stringValue?.nilIfBlank
        let childHostID = string(in: object, keys: ["childHostID", "childHostId", "child_host_id", "targetHostID", "targetHostId", "target_host_id"])
            .map(HostID.init(rawValue:))
            ?? (isCreationEvent ? hostID : nil)
        let childThreadID = string(in: object, keys: ["childThreadID", "childThreadId", "child_thread_id", "childSessionID", "childSessionId", "child_session_id", "targetThreadID", "targetThreadId", "target_thread_id"])
            ?? object["childThread"]?["id"]?.stringValue?.nilIfBlank
            ?? object["child"]?["threadID"]?.stringValue?.nilIfBlank
            ?? object["child"]?["threadId"]?.stringValue?.nilIfBlank
            ?? object["child"]?["id"]?.stringValue?.nilIfBlank
        let childCWD = string(in: object, keys: ["childCWD", "childCwd", "child_cwd", "childWorkspace", "child_workspace", "cwd"])
            ?? object["childThread"]?["cwd"]?.stringValue?.nilIfBlank
            ?? object["child"]?["cwd"]?.stringValue?.nilIfBlank
        let childFolderPath = string(in: object, keys: ["childFolderPath", "child_folder_path", "folderPath", "folder_path", "path"])
            ?? object["childFolder"]?["path"]?.stringValue?.nilIfBlank
            ?? object["folder"]?["path"]?.stringValue?.nilIfBlank
            ?? object["child"]?["folderPath"]?.stringValue?.nilIfBlank
            ?? object["child"]?["folder_path"]?.stringValue?.nilIfBlank
            ?? (kind == .folderCreated ? childCWD : nil)
        let childTitle = string(in: object, keys: ["childTitle", "child_title", "threadTitle", "thread_title", "name", "title"])
            ?? object["childThread"]?["title"]?.stringValue?.nilIfBlank
            ?? object["child"]?["title"]?.stringValue?.nilIfBlank
            ?? object["childThread"]?["name"]?.stringValue?.nilIfBlank
            ?? object["child"]?["name"]?.stringValue?.nilIfBlank
        let childThreadKind = codexThreadKind(
            from: string(in: object, keys: ["childKind", "child_kind", "childThreadKind", "child_thread_kind", "threadKind", "thread_kind", "kind"])
                ?? object["childThread"]?["kind"]?.stringValue?.nilIfBlank
                ?? object["child"]?["kind"]?.stringValue?.nilIfBlank
        )
        let createdAt = date(
            in: object,
            keys: ["createdAt", "created_at", "timestamp", "time"],
            fallback: receivedAt
        )
        let summary = string(in: object, keys: ["summary", "message"])
            ?? creationSummary(for: kind, title: childTitle, threadID: childThreadID, folderPath: childFolderPath)
            ?? defaultSummary(for: kind, method: method)
        let effectiveMethod = method ?? defaultMethod(for: kind)
        let explicitID = explicitID(
            in: object,
            kind: kind,
            hostID: hostID,
            threadID: threadID,
            turnID: turnID,
            childHostID: childHostID,
            childThreadID: childThreadID,
            childFolderPath: childFolderPath,
            method: effectiveMethod,
            createdAt: createdAt
        )

        return WorkflowEvent(
            id: explicitID,
            kind: kind,
            hostID: hostID,
            threadID: threadID,
            turnID: turnID,
            method: effectiveMethod,
            summary: summary,
            createdAt: createdAt,
            childHostID: childHostID,
            childThreadID: childThreadID,
            childCWD: childCWD,
            childFolderPath: childFolderPath,
            childTitle: childTitle,
            childThreadKind: childThreadKind
        )
    }

    private static func structuredEventKind(in object: [String: JSONValue]) -> String? {
        for key in ["type", "event", "method", "notificationMethod", "notification_method"] {
            guard let value = object[key]?.stringValue?.nilIfBlank else {
                continue
            }
            if let kind = workflowEventKind(from: value),
               kind == .threadCreated || kind == .folderCreated {
                return value
            }
        }
        return nil
    }

    private static func workflowEventKind(from value: String?) -> WorkflowEventKind? {
        guard let value = value?.nilIfBlank else { return nil }
        if let exact = WorkflowEventKind(rawValue: value) {
            return exact
        }

        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        if normalized.contains("fail") || normalized.contains("error") {
            return .failed
        }
        if normalized.contains("approval")
            || normalized.contains("needs-input")
            || normalized.contains("need-input")
            || normalized.contains("request-input")
            || normalized.contains("request-user-input")
            || normalized.contains("elicitation") {
            return .needsInput
        }
        if normalized.contains("complete")
            || normalized.contains("completed")
            || normalized.contains("ended")
            || normalized.contains("turn-ended")
            || normalized.contains("turn-end")
            || normalized.contains("done")
            || normalized.contains("stop") {
            return .turnCompleted
        }
        if normalized.contains("started") || normalized.contains("turn-start") {
            return .turnStarted
        }
        if normalized == "thread-created"
            || normalized == "thread-create"
            || normalized.contains("thread-created")
            || normalized.contains("thread-create") {
            return .threadCreated
        }
        if normalized == "folder-created"
            || normalized == "folder-create"
            || normalized == "workspace-created"
            || normalized == "workspace-create"
            || normalized == "project-created"
            || normalized == "project-create"
            || normalized.contains("folder-created")
            || normalized.contains("folder-create")
            || normalized.contains("workspace-created")
            || normalized.contains("workspace-create")
            || normalized.contains("project-created")
            || normalized.contains("project-create") {
            return .folderCreated
        }
        return nil
    }

    private static func explicitID(
        in object: [String: JSONValue],
        kind: WorkflowEventKind,
        hostID: HostID?,
        threadID: String?,
        turnID: String?,
        childHostID: HostID?,
        childThreadID: String?,
        childFolderPath: String?,
        method: String,
        createdAt: Date
    ) -> String? {
        if let id = string(in: object, keys: ["id", "eventID", "eventId", "event_id"]) {
            return id.hasPrefix("hook-") ? id : "hook-\(id)"
        }

        if kind == .threadCreated, let childHostID, let childThreadID {
            let stableID = WorkflowEvent.threadCreatedID(
                sourceHostID: hostID,
                sourceThreadID: threadID,
                childHostID: childHostID,
                childThreadID: childThreadID
            )
            return "hook-\(stableID)"
        }
        if kind == .folderCreated, let childHostID, let childFolderPath {
            let stableID = WorkflowEvent.folderCreatedID(
                sourceHostID: hostID,
                sourceThreadID: threadID,
                childHostID: childHostID,
                childFolderPath: childFolderPath
            )
            return "hook-\(stableID)"
        }

        guard turnID?.isEmpty != false else {
            return nil
        }

        let timestamp = Int(createdAt.timeIntervalSince1970 * 1_000)
        let host = hostID?.rawValue ?? "unknown-host"
        let thread = threadID ?? "unknown-thread"
        return "hook-\(kind.rawValue)-\(host)-\(thread)-\(method)-\(timestamp)"
    }

    private static func string(in object: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key]?.stringValue?.nilIfBlank {
                return value
            }
            if let value = object[key]?.intValue {
                return String(value)
            }
        }
        return nil
    }

    private static func codexThreadKind(from value: String?) -> CodexThreadNodeKind? {
        guard let value = value?.nilIfBlank else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        if normalized.contains("subagent") || normalized == "agent" {
            return .subagent
        }
        if normalized.contains("thread") {
            return .thread
        }
        return nil
    }

    private static func creationSummary(
        for kind: WorkflowEventKind,
        title: String?,
        threadID: String?,
        folderPath: String?
    ) -> String? {
        switch kind {
        case .threadCreated:
            return threadCreatedSummary(title: title, threadID: threadID)
        case .folderCreated:
            return folderCreatedSummary(title: title, folderPath: folderPath)
        case .turnStarted, .turnCompleted, .needsInput, .failed:
            return nil
        }
    }

    private static func threadCreatedSummary(title: String?, threadID: String?) -> String {
        if let title = title?.nilIfBlank {
            return "Created \(title)"
        }
        if let threadID = threadID?.nilIfBlank {
            return "Created thread \(threadID)"
        }
        return "Created thread"
    }

    private static func folderCreatedSummary(title: String?, folderPath: String?) -> String {
        if let title = title?.nilIfBlank {
            return "Created folder \(title)"
        }
        if let folderName = folderPath?.nilIfBlank.map(folderName(for:)) {
            return "Created folder \(folderName)"
        }
        return "Created folder"
    }

    private static func folderName(for path: String) -> String {
        let separators = CharacterSet(charactersIn: "/\\")
        let components = path
            .trimmingCharacters(in: separators)
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
        return components.last ?? path
    }

    private static func date(in object: [String: JSONValue], keys: [String], fallback: Date) -> Date {
        for key in keys {
            if let seconds = object[key]?.doubleValue, seconds.isFinite {
                return Date(timeIntervalSince1970: normalizedEpochSeconds(seconds))
            }
            guard let value = object[key]?.stringValue?.nilIfBlank else {
                continue
            }
            if let date = iso8601Date(from: value) {
                return date
            }
            if let seconds = Double(value), seconds.isFinite {
                return Date(timeIntervalSince1970: normalizedEpochSeconds(seconds))
            }
        }
        return fallback
    }

    private static func normalizedEpochSeconds(_ value: Double) -> Double {
        value > 10_000_000_000 ? value / 1_000 : value
    }

    private static func iso8601Date(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func defaultMethod(for kind: WorkflowEventKind) -> String {
        switch kind {
        case .turnStarted:
            return "turn/started"
        case .turnCompleted:
            return "turn/completed"
        case .threadCreated:
            return "thread/created"
        case .folderCreated:
            return "folder/created"
        case .needsInput:
            return "hook/needsInput"
        case .failed:
            return "hook/failed"
        }
    }

    private static func defaultSummary(for kind: WorkflowEventKind, method: String?) -> String {
        switch kind {
        case .turnStarted:
            return "Turn started"
        case .turnCompleted:
            return "Turn completed"
        case .threadCreated:
            return "Created thread"
        case .folderCreated:
            return "Created folder"
        case .needsInput:
            return method ?? "Needs input"
        case .failed:
            return method ?? "Turn failed"
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public final class WorkflowHookEventFileBridge: @unchecked Sendable {
    public let eventFileURL: URL
    public let defaultHostID: HostID?
    public let pollInterval: Duration

    public init(
        eventFileURL: URL = WorkflowHookEventFileBridge.defaultEventFileURL(),
        defaultHostID: HostID?,
        pollInterval: Duration = .milliseconds(500)
    ) {
        self.eventFileURL = eventFileURL
        self.defaultHostID = defaultHostID
        self.pollInterval = pollInterval
    }

    public static func defaultEventFileURL(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> URL {
        homeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("mapofagents", isDirectory: true)
            .appendingPathComponent("hook-events.jsonl", isDirectory: false)
    }

    public func start(
        replayExistingEvents: Bool = false,
        onEvents: @escaping @MainActor @Sendable ([WorkflowEvent]) -> Void
    ) -> Task<Void, Never> {
        Task {
            prepareEventFile()
            var offset = replayExistingEvents ? 0 : Self.fileSize(eventFileURL)
            var pendingLine = ""

            while !Task.isCancelled {
                if Self.fileSize(eventFileURL) < offset {
                    offset = replayExistingEvents ? 0 : Self.fileSize(eventFileURL)
                    pendingLine = ""
                }

                if let data = try? Self.readAppendedData(from: eventFileURL, offset: &offset),
                   !data.isEmpty,
                   let text = String(data: data, encoding: .utf8) {
                    let lines = Self.completeLines(from: text, pendingLine: &pendingLine)
                    let events = lines.compactMap {
                        WorkflowHookEventParser.workflowEvent(
                            from: $0,
                            defaultHostID: defaultHostID
                        )
                    }
                    if !events.isEmpty {
                        await MainActor.run {
                            onEvents(events)
                        }
                    }
                }

                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    private func prepareEventFile() {
        let directory = eventFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: eventFileURL.path) {
            FileManager.default.createFile(atPath: eventFileURL.path, contents: nil)
        }
    }

    private static func fileSize(_ url: URL) -> UInt64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else {
            return 0
        }
        return size.uint64Value
    }

    private static func readAppendedData(from url: URL, offset: inout UInt64) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        offset += UInt64(data.count)
        return data
    }

    private static func completeLines(from text: String, pendingLine: inout String) -> [String] {
        let combined = pendingLine + text
        guard !combined.isEmpty else {
            return []
        }

        var parts = combined
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        if combined.hasSuffix("\n") {
            pendingLine = ""
            if parts.last == "" {
                parts.removeLast()
            }
        } else {
            pendingLine = parts.popLast() ?? ""
        }

        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
