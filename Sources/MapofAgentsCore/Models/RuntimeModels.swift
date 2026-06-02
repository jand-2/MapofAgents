import Foundation

public struct AgentHost: Codable, Identifiable, Hashable, Sendable {
    public var id: HostID
    public var name: String
    public var platform: HostPlatform
    public var codexHome: String?
    public var endpointDescription: String
    public var status: HostStatus
    public var lastSeenAt: Date?

    public init(
        id: HostID,
        name: String,
        platform: HostPlatform,
        codexHome: String? = nil,
        endpointDescription: String,
        status: HostStatus,
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.codexHome = codexHome
        self.endpointDescription = endpointDescription
        self.status = status
        self.lastSeenAt = lastSeenAt
    }
}

public struct CodexModelOption: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var displayName: String
    public var description: String
    public var defaultReasoningEffort: String
    public var supportedReasoningEfforts: [String]
    public var isDefault: Bool

    public init(
        id: String,
        displayName: String,
        description: String = "",
        defaultReasoningEffort: String = "medium",
        supportedReasoningEfforts: [String] = ["low", "medium", "high", "xhigh"],
        isDefault: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.defaultReasoningEffort = defaultReasoningEffort
        self.supportedReasoningEfforts = supportedReasoningEfforts
        self.isDefault = isDefault
    }
}

public enum CodexApprovalPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case onRequest = "on-request"
    case onFailure = "on-failure"
    case untrusted
    case never

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .onRequest:
            return "On Request"
        case .onFailure:
            return "On Failure"
        case .untrusted:
            return "Untrusted"
        case .never:
            return "Never"
        }
    }
}

public enum CodexSandboxMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case dangerFullAccess = "danger-full-access"
    case workspaceWrite = "workspace-write"
    case readOnly = "read-only"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dangerFullAccess:
            return "Full Access"
        case .workspaceWrite:
            return "Workspace Write"
        case .readOnly:
            return "Read Only"
        }
    }

    public func sandboxPolicy(cwd: String) -> JSONValue {
        switch self {
        case .dangerFullAccess:
            return .object(["type": .string("dangerFullAccess")])
        case .readOnly:
            return .object([
                "type": .string("readOnly"),
                "networkAccess": .bool(true),
            ])
        case .workspaceWrite:
            return .object([
                "type": .string("workspaceWrite"),
                "writableRoots": .array([.string(cwd)]),
                "networkAccess": .bool(true),
                "excludeTmpdirEnvVar": .bool(false),
                "excludeSlashTmp": .bool(false),
            ])
        }
    }
}

public struct CodexThreadPermissions: Codable, Hashable, Sendable {
    public var approvalPolicy: CodexApprovalPolicy
    public var sandboxMode: CodexSandboxMode

    public init(
        approvalPolicy: CodexApprovalPolicy = .onRequest,
        sandboxMode: CodexSandboxMode = .dangerFullAccess
    ) {
        self.approvalPolicy = approvalPolicy
        self.sandboxMode = sandboxMode
    }

    /// Historical app-server workflows expect the full-access sandbox default.
    /// New-thread UI warns for this mode and confirms it on remote targets.
    public static let `default` = CodexThreadPermissions()

    public func threadParams() -> [String: JSONValue] {
        [
            "approvalPolicy": .string(approvalPolicy.rawValue),
            "sandbox": .string(sandboxMode.rawValue),
        ]
    }

    public func turnParams(cwd: String) -> [String: JSONValue] {
        [
            "approvalPolicy": .string(approvalPolicy.rawValue),
            "sandboxPolicy": sandboxMode.sandboxPolicy(cwd: cwd),
        ]
    }
}

public enum ChatInputAttachmentKind: String, Codable, CaseIterable, Sendable {
    case file
    case image

    public var displayName: String {
        switch self {
        case .file:
            return "File"
        case .image:
            return "Image"
        }
    }
}

public struct ChatInputAttachment: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: ChatInputAttachmentKind
    public var name: String
    public var mimeType: String?
    public var sourcePath: String?
    public var data: Data?
    public var byteCount: Int?

    public init(
        id: String = UUID().uuidString,
        kind: ChatInputAttachmentKind,
        name: String,
        mimeType: String? = nil,
        sourcePath: String? = nil,
        data: Data? = nil,
        byteCount: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.mimeType = mimeType
        self.sourcePath = sourcePath
        self.data = data
        self.byteCount = byteCount ?? data?.count
    }
}

public struct ResolvedChatInputAttachment: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: ChatInputAttachmentKind
    public var name: String
    public var mimeType: String?
    public var path: String
    public var byteCount: Int?

    public init(
        id: String,
        kind: ChatInputAttachmentKind,
        name: String,
        mimeType: String?,
        path: String,
        byteCount: Int?
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.mimeType = mimeType
        self.path = path
        self.byteCount = byteCount
    }
}

public struct AgentRun: Codable, Identifiable, Hashable, Sendable {
    public var id: RunID
    public var workspaceID: WorkspaceID
    public var hostID: HostID
    public var cwd: String
    public var status: ThreadRunStatus
    public var threadRef: ThreadRef?
    public var currentTurnID: String?
    public var model: String
    public var reasoningEffort: String
    public var updatedAt: Date

    public init(
        id: RunID = .fresh(),
        workspaceID: WorkspaceID,
        hostID: HostID,
        cwd: String,
        status: ThreadRunStatus = .idle,
        threadRef: ThreadRef? = nil,
        currentTurnID: String? = nil,
        model: String,
        reasoningEffort: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.hostID = hostID
        self.cwd = cwd
        self.status = status
        self.threadRef = threadRef
        self.currentTurnID = currentTurnID
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.updatedAt = updatedAt
    }
}

public enum ThreadMessageRole: String, Codable, CaseIterable, Sendable {
    case user
    case assistant
    case reasoning
    case tool
    case system
}

public enum ThreadMessageAttachmentKind: String, Codable, CaseIterable, Sendable {
    case image
    case file
    case diff
}

public enum ThreadMessageAttachmentChangeType: String, Codable, CaseIterable, Sendable {
    case added
    case modified
    case deleted
    case renamed
    case unknown
}

public struct ThreadMessageAttachment: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: ThreadMessageAttachmentKind
    public var sourceHostID: HostID
    public var sourcePath: String?
    public var cachedPath: String?
    public var mimeType: String?
    public var title: String?
    public var status: String?
    public var revisedPrompt: String?
    public var byteCount: Int?
    public var createdAt: Date?
    public var changeType: ThreadMessageAttachmentChangeType?
    public var diffText: String?
    public var language: String?
    public var isTrustedForAutoHydration: Bool

    public init(
        id: String = UUID().uuidString,
        kind: ThreadMessageAttachmentKind,
        sourceHostID: HostID,
        sourcePath: String? = nil,
        cachedPath: String? = nil,
        mimeType: String? = nil,
        title: String? = nil,
        status: String? = nil,
        revisedPrompt: String? = nil,
        byteCount: Int? = nil,
        createdAt: Date? = nil,
        changeType: ThreadMessageAttachmentChangeType? = nil,
        diffText: String? = nil,
        language: String? = nil,
        isTrustedForAutoHydration: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.sourceHostID = sourceHostID
        self.sourcePath = sourcePath
        self.cachedPath = cachedPath
        self.mimeType = mimeType
        self.title = title
        self.status = status
        self.revisedPrompt = revisedPrompt
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.changeType = changeType
        self.diffText = diffText
        self.language = language
        self.isTrustedForAutoHydration = isTrustedForAutoHydration
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case sourceHostID
        case sourcePath
        case cachedPath
        case mimeType
        case title
        case status
        case revisedPrompt
        case byteCount
        case createdAt
        case changeType
        case diffText
        case language
        case isTrustedForAutoHydration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(ThreadMessageAttachmentKind.self, forKey: .kind)
        sourceHostID = try container.decode(HostID.self, forKey: .sourceHostID)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
        cachedPath = try container.decodeIfPresent(String.self, forKey: .cachedPath)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        revisedPrompt = try container.decodeIfPresent(String.self, forKey: .revisedPrompt)
        byteCount = try container.decodeIfPresent(Int.self, forKey: .byteCount)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        changeType = try container.decodeIfPresent(ThreadMessageAttachmentChangeType.self, forKey: .changeType)
        diffText = try container.decodeIfPresent(String.self, forKey: .diffText)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        isTrustedForAutoHydration = try container.decodeIfPresent(Bool.self, forKey: .isTrustedForAutoHydration) ?? (kind != .file)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(sourceHostID, forKey: .sourceHostID)
        try container.encodeIfPresent(sourcePath, forKey: .sourcePath)
        try container.encodeIfPresent(cachedPath, forKey: .cachedPath)
        try container.encodeIfPresent(mimeType, forKey: .mimeType)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(revisedPrompt, forKey: .revisedPrompt)
        try container.encodeIfPresent(byteCount, forKey: .byteCount)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(changeType, forKey: .changeType)
        try container.encodeIfPresent(diffText, forKey: .diffText)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encode(isTrustedForAutoHydration, forKey: .isTrustedForAutoHydration)
    }
}

public struct ThreadMessage: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var role: ThreadMessageRole
    public var text: String
    public var createdAt: Date
    public var attachments: [ThreadMessageAttachment]

    public init(
        id: String = UUID().uuidString,
        role: ThreadMessageRole,
        text: String,
        createdAt: Date = Date(),
        attachments: [ThreadMessageAttachment] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case createdAt
        case attachments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(ThreadMessageRole.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        attachments = try container.decodeIfPresent([ThreadMessageAttachment].self, forKey: .attachments) ?? []
    }
}

public struct ThreadTranscript: Codable, Hashable, Sendable {
    public var threadRef: ThreadRef
    public var messages: [ThreadMessage]
    public var nextCursor: String?
    public var lastUpdatedAt: Date
    public var turnTimeline: ThreadTurnTimeline?

    public init(
        threadRef: ThreadRef,
        messages: [ThreadMessage] = [],
        nextCursor: String? = nil,
        lastUpdatedAt: Date = Date(),
        turnTimeline: ThreadTurnTimeline? = nil
    ) {
        self.threadRef = threadRef
        self.messages = messages
        self.nextCursor = nextCursor
        self.lastUpdatedAt = lastUpdatedAt
        self.turnTimeline = turnTimeline
    }

    public func sortedChronologically() -> ThreadTranscript {
        var copy = self
        copy.messages = messages.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.createdAt == rhs.element.createdAt {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.createdAt < rhs.element.createdAt
            }
            .map(\.element)
        if let turnTimeline {
            copy.turnTimeline = turnTimeline.reconciled(with: copy)
        }
        return copy
    }

    public func prependingOlderPage(_ olderPage: ThreadTranscript) -> ThreadTranscript {
        var copy = self
        var seen = Set<String>()
        copy.messages = (olderPage.messages + messages)
            .filter { message in
                seen.insert(message.id).inserted
            }
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.createdAt == rhs.element.createdAt {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.createdAt < rhs.element.createdAt
            }
            .map(\.element)
        copy.nextCursor = olderPage.nextCursor
        if let olderTimeline = olderPage.turnTimeline, let currentTimeline = turnTimeline {
            var seen = Set<String>()
            copy.turnTimeline = ThreadTurnTimeline(
                threadRef: threadRef,
                turns: (olderTimeline.turns + currentTimeline.turns)
                    .filter { seen.insert($0.id).inserted }
            ).reconciled(with: copy)
        } else if let olderTimeline = olderPage.turnTimeline {
            copy.turnTimeline = olderTimeline.reconciled(with: copy)
        } else if let currentTimeline = turnTimeline {
            copy.turnTimeline = currentTimeline.reconciled(with: copy)
        } else {
            copy.turnTimeline = nil
        }
        copy.lastUpdatedAt = Date()
        return copy
    }

    public var primaryArtifactAttachments: [ThreadMessageAttachment] {
        let timelineAttachments = turnTimeline?.turns
            .flatMap(\.items)
            .flatMap(\.effectiveAttachments) ?? []
        let legacyAttachments = messages.flatMap(\.attachments)

        guard !timelineAttachments.isEmpty else {
            return deduplicatedArtifactAttachments(legacyAttachments)
        }

        let merged = deduplicatedArtifactAttachments(timelineAttachments + legacyAttachments)
        return merged
    }

    private func deduplicatedArtifactAttachments(_ attachments: [ThreadMessageAttachment]) -> [ThreadMessageAttachment] {
        var seen = Set<String>()
        return attachments.filter { attachment in
            seen.insert(artifactAttachmentKey(attachment)).inserted
        }
    }

    private func artifactAttachmentKey(_ attachment: ThreadMessageAttachment) -> String {
        [
            attachment.kind.rawValue,
            attachment.sourceHostID.rawValue,
            attachment.sourcePath ?? attachment.cachedPath ?? attachment.id,
            attachment.diffText ?? "",
        ].joined(separator: "::")
    }
}

public enum WorkflowEventKind: String, Codable, CaseIterable, Sendable {
    case turnStarted
    case turnCompleted
    case threadCreated
    case needsInput
    case failed
}

public struct WorkflowEvent: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: WorkflowEventKind
    public var hostID: HostID?
    public var threadID: String?
    public var turnID: String?
    public var method: String
    public var summary: String
    public var createdAt: Date
    public var childHostID: HostID?
    public var childThreadID: String?
    public var childCWD: String?
    public var childTitle: String?
    public var childThreadKind: CodexThreadNodeKind?

    public init(
        id: String? = nil,
        kind: WorkflowEventKind,
        hostID: HostID? = nil,
        threadID: String?,
        turnID: String? = nil,
        method: String,
        summary: String,
        createdAt: Date = Date(),
        childHostID: HostID? = nil,
        childThreadID: String? = nil,
        childCWD: String? = nil,
        childTitle: String? = nil,
        childThreadKind: CodexThreadNodeKind? = nil
    ) {
        self.kind = kind
        self.hostID = hostID
        self.threadID = threadID
        self.turnID = turnID
        self.method = method
        self.summary = summary
        self.createdAt = createdAt
        self.childHostID = childHostID
        self.childThreadID = childThreadID
        self.childCWD = childCWD
        self.childTitle = childTitle
        self.childThreadKind = childThreadKind
        if let id {
            self.id = id
        } else if kind == .threadCreated, let childHostID, let childThreadID {
            self.id = Self.threadCreatedID(
                sourceHostID: hostID,
                sourceThreadID: threadID,
                childHostID: childHostID,
                childThreadID: childThreadID
            )
        } else {
            self.id = Self.stableID(
                kind: kind,
                hostID: hostID,
                threadID: threadID,
                turnID: turnID,
                method: method,
                summary: summary
            )
        }
    }

    public var threadQualifiedID: String? {
        guard let hostID, let threadID else {
            return nil
        }
        return ThreadRef.qualifiedID(hostID: hostID, threadID: threadID)
    }

    public var childThreadRef: ThreadRef? {
        guard let childHostID, let childThreadID else {
            return nil
        }
        return ThreadRef(
            hostID: childHostID,
            threadID: childThreadID,
            cwd: childCWD ?? "",
            name: childTitle
        )
    }

    public var dedupeKey: String {
        semanticDedupeKey ?? id
    }

    public var semanticDedupeKey: String? {
        if kind == .threadCreated, let childHostID, let childThreadID {
            return Self.threadCreatedID(
                sourceHostID: hostID,
                sourceThreadID: threadID,
                childHostID: childHostID,
                childThreadID: childThreadID
            )
        }
        let stable = Self.stableID(
            kind: kind,
            hostID: hostID,
            threadID: threadID,
            turnID: turnID,
            method: method,
            summary: summary
        )
        if turnID?.isEmpty == false {
            return stable
        }
        if id != stable {
            return "workflow-event-explicit-\(Self.safeIDComponent(id))"
        }
        return nil
    }

    public static func stableID(
        kind: WorkflowEventKind,
        hostID: HostID?,
        threadID: String?,
        turnID: String?,
        method: String,
        summary: String
    ) -> String {
        [
            "workflow-event",
            kind.rawValue,
            hostID?.rawValue ?? "unknown-host",
            threadID ?? "unknown-thread",
            turnID ?? (summary.isEmpty ? nil : summary) ?? "unknown-turn",
            method,
        ]
            .map(Self.safeIDComponent)
            .joined(separator: "-")
    }

    public static func threadCreatedID(
        sourceHostID: HostID?,
        sourceThreadID: String?,
        childHostID: HostID,
        childThreadID: String
    ) -> String {
        [
            "workflow-event",
            WorkflowEventKind.threadCreated.rawValue,
            sourceHostID?.rawValue ?? "unknown-source-host",
            sourceThreadID ?? "unknown-source-thread",
            childHostID.rawValue,
            childThreadID,
        ]
            .map(Self.safeIDComponent)
            .joined(separator: "-")
    }

    private static func safeIDComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let compact = value.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let result = String(compact)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "none" : String(result.prefix(96))
    }
}

public struct WorkflowNotificationPreferences: Codable, Hashable, Sendable {
    public var notifyOnCompleted: Bool
    public var notifyOnNeedsInput: Bool
    public var notifyOnFailed: Bool

    public init(
        notifyOnCompleted: Bool = false,
        notifyOnNeedsInput: Bool = true,
        notifyOnFailed: Bool = true
    ) {
        self.notifyOnCompleted = notifyOnCompleted
        self.notifyOnNeedsInput = notifyOnNeedsInput
        self.notifyOnFailed = notifyOnFailed
    }

    public static let standard = WorkflowNotificationPreferences()
}

public enum MentionKind: String, Codable, CaseIterable, Sendable {
    case skill
    case plugin
    case file
    case folder
    case thread
}

public struct MentionCandidate: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: MentionKind
    public var trigger: String
    public var label: String
    public var title: String
    public var subtitle: String
    public var insertionText: String

    public init(
        id: String,
        kind: MentionKind,
        trigger: String,
        label: String,
        title: String,
        subtitle: String,
        insertionText: String
    ) {
        self.id = id
        self.kind = kind
        self.trigger = trigger
        self.label = label
        self.title = title
        self.subtitle = subtitle
        self.insertionText = insertionText
    }
}

public enum RuntimeDiagnosticStatus: String, Codable, Sendable {
    case pending
    case running
    case passed
    case warning
    case failed
}

public enum RuntimeDiagnosticAction: String, Codable, CaseIterable, Sendable {
    case installCodexCLI
    case updateCodexCLI
    case startAppServer
    case restartAppServer
}

public struct RuntimeDiagnosticStep: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var status: RuntimeDiagnosticStatus
    public var detail: String
    public var evidence: String
    public var action: RuntimeDiagnosticAction?

    public init(
        id: String,
        title: String,
        status: RuntimeDiagnosticStatus = .pending,
        detail: String = "",
        evidence: String = "",
        action: RuntimeDiagnosticAction? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.evidence = evidence
        self.action = action
    }
}

public struct RuntimeAttentionRequest: Codable, Identifiable, Hashable, Sendable {
    public struct TypedResponseOption: Codable, Identifiable, Hashable, Sendable {
        public var label: String
        public var value: String

        public var id: String { value }

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public var id: String
    public var hostID: HostID?
    public var requestID: JSONRPCRequestID?
    public var method: String
    public var threadID: String?
    public var turnID: String?
    public var summary: String
    public var requestParams: JSONValue?
    public var createdAt: Date

    public init(
        id: String,
        hostID: HostID? = nil,
        requestID: JSONRPCRequestID? = nil,
        method: String,
        threadID: String?,
        turnID: String? = nil,
        summary: String,
        requestParams: JSONValue? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.hostID = hostID
        self.requestID = requestID
        self.method = method
        self.threadID = threadID
        self.turnID = turnID
        self.summary = summary
        self.requestParams = requestParams
        self.createdAt = createdAt
    }

    public static func appServerRequest(
        from notification: CodexServerNotification,
        hostID: HostID
    ) -> RuntimeAttentionRequest? {
        AppServerNotificationNormalizer.attentionRequest(from: notification, hostID: hostID)
    }

    public static func resolvedRequestID(from notification: CodexServerNotification) -> String? {
        AppServerNotificationNormalizer.resolvedRequestID(from: notification)
    }

    public func appServerApprovalResult(allow: Bool) -> JSONValue {
        if method == "item/permissions/requestApproval" {
            guard allow else {
                return .object([
                    "permissions": .object([:]),
                    "scope": .string("turn"),
                ])
            }

            return .object([
                "permissions": requestedPermissions(),
                "scope": .string("session"),
            ])
        }

        return .object([
            "decision": .string(allow ? "accept" : "decline"),
        ])
    }

    public func appServerTextResponseResult(_ text: String) -> JSONValue {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if method.contains("requestUserInput") {
            let questions = requestParams?["questions"]?.arrayValue ?? []
            var answers: [String: JSONValue] = [:]
            for question in questions {
                guard let id = question["id"]?.stringValue else { continue }
                answers[id] = .object(["answers": .array([.string(trimmed)])])
            }
            if answers.isEmpty {
                answers["response"] = .object(["answers": .array([.string(trimmed)])])
            }
            return .object(["answers": .object(answers)])
        }

        if method.contains("elicitation/request") {
            return .object([
                "action": .string("accept"),
                "content": elicitationContent(from: trimmed),
            ])
        }

        return .object(["response": .string(trimmed)])
    }

    public func appServerTextDeclineResult() -> JSONValue {
        if method.contains("requestUserInput") {
            return .object(["answers": .object([:])])
        }
        if method.contains("elicitation/request") {
            return .object([
                "action": .string("decline"),
                "content": .null,
            ])
        }
        return appServerApprovalResult(allow: false)
    }

    public var supportsApprovalDecision: Bool {
        method == "item/commandExecution/requestApproval"
            || method == "item/fileChange/requestApproval"
            || method == "item/permissions/requestApproval"
    }

    public var supportsTypedResponse: Bool {
        method.contains("requestUserInput") || method.contains("elicitation/request")
    }

    public var promptText: String {
        if let questions = requestParams?["questions"]?.arrayValue, let first = questions.first {
            return first["question"]?.stringValue
                ?? first["header"]?.stringValue
                ?? summary
        }
        if let message = requestParams?["message"]?.stringValue {
            return message
        }
        return summary
    }

    public func targetThreadRef(defaultHostID: HostID) -> ThreadRef? {
        guard let threadID else { return nil }
        return ThreadRef(
            hostID: hostID ?? defaultHostID,
            threadID: threadID,
            cwd: requestParams?["cwd"]?.stringValue
                ?? requestParams?["workingDirectory"]?.stringValue
                ?? requestParams?["working_directory"]?.stringValue
                ?? "",
            name: nil
        )
    }

    public var typedResponseOptions: [String] {
        typedResponseChoices.map(\.value)
    }

    public var typedResponseChoices: [TypedResponseOption] {
        if let options = requestParams?["questions"]?.arrayValue?.first?["options"]?.arrayValue {
            return options.compactMap { option in
                guard let label = option["label"]?.stringValue ?? option.stringValue else { return nil }
                let value = option["value"]?.stringValue ?? option["id"]?.stringValue ?? label
                return TypedResponseOption(label: label, value: value)
            }
        }

        guard method.contains("elicitation/request"),
              let schema = elicitationSchema,
              let properties = schema["properties"]?.objectValue else {
            return []
        }

        let enumFields = properties.values.compactMap { property -> [TypedResponseOption]? in
            choices(from: property)
        }
        return enumFields.count == 1 ? enumFields[0] : []
    }

    public var initialTypedResponseValue: String {
        let responseChoices = typedResponseChoices
        guard !responseChoices.isEmpty else {
            return ""
        }

        guard method.contains("elicitation/request"),
              let schema = elicitationSchema,
              let properties = schema["properties"]?.objectValue else {
            return responseChoices[0].value
        }

        let enumFields = properties.values.compactMap { property -> (field: JSONValue, choices: [TypedResponseOption])? in
            guard let choices = choices(from: property) else {
                return nil
            }
            return (property, choices)
        }
        guard enumFields.count == 1 else {
            return responseChoices[0].value
        }

        if let defaultString = enumFields[0].field["default"]?.stringValue,
           let value = choiceValue(matching: defaultString, in: enumFields[0].choices) {
            return value
        }

        return responseChoices[0].value
    }

    private func requestedPermissions() -> JSONValue {
        let value = requestParams?["permissions"]
            ?? requestParams?["requestedPermissions"]
            ?? requestParams?["requested_permissions"]
            ?? requestParams?["additionalPermissions"]
            ?? requestParams?["additional_permissions"]

        if value?.objectValue != nil {
            return value ?? .object([:])
        }
        return .object([:])
    }

    private var elicitationSchema: JSONValue? {
        requestParams?["requestedSchema"]
            ?? requestParams?["requested_schema"]
            ?? requestParams?["schema"]
            ?? requestParams?["request"]?["requestedSchema"]
            ?? requestParams?["request"]?["requested_schema"]
    }

    private func elicitationContent(from text: String) -> JSONValue {
        guard let schema = elicitationSchema,
              let properties = schema["properties"]?.objectValue else {
            return .object(["response": .string(text)])
        }

        let provided = Self.parseJSONObject(from: text)
        let required = Set((schema["required"]?.arrayValue ?? []).compactMap(\.stringValue))
        let sortedKeys = properties.keys.sorted { lhs, rhs in
            if required.contains(lhs) != required.contains(rhs) {
                return required.contains(lhs)
            }
            return lhs < rhs
        }
        let singleFieldKey = sortedKeys.count == 1 ? sortedKeys.first : nil
        var content: [String: JSONValue] = [:]

        for key in sortedKeys {
            guard let field = properties[key] else { continue }
            let providedValue = provided?[key]
            let rawText = singleFieldKey == key ? text : nil
            content[key] = coercedElicitationValue(field: field, providedValue: providedValue, rawText: rawText)
        }

        return .object(content)
    }

    private func coercedElicitationValue(field: JSONValue, providedValue: JSONValue?, rawText: String?) -> JSONValue {
        let trimmed = rawText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let choices = choices(from: field), !choices.isEmpty {
            if let providedValue, providedValue != .null {
                if let providedString = providedValue.stringValue,
                   let value = choiceValue(matching: providedString, in: choices) {
                    return .string(value)
                }
                return providedValue
            }

            if let trimmed,
               let value = choiceValue(matching: trimmed, in: choices) {
                return .string(value)
            }

            if let defaultValue = field["default"] {
                if let defaultString = defaultValue.stringValue,
                   let value = choiceValue(matching: defaultString, in: choices) {
                    return .string(value)
                }
                return defaultValue
            }

            return .string(choices[0].value)
        }

        if let providedValue, providedValue != .null {
            return providedValue
        }

        let type = field["type"]?.stringValue?.lowercased()
        switch type {
        case "boolean":
            if let trimmed, let bool = Self.parseBoolean(trimmed) {
                return .bool(bool)
            }
            return field["default"] ?? .bool(false)
        case "integer":
            if let trimmed, let number = Double(trimmed) {
                return .number(Double(Int(number)))
            }
            return field["default"] ?? .number(0)
        case "number":
            if let trimmed, let number = Double(trimmed) {
                return .number(number)
            }
            return field["default"] ?? .number(0)
        default:
            if let trimmed, !trimmed.isEmpty {
                return .string(trimmed)
            }
            return field["default"] ?? .string("")
        }
    }

    private func choices(from field: JSONValue) -> [TypedResponseOption]? {
        let type = field["type"]?.stringValue?.lowercased()
        guard type != "array" else {
            return nil
        }

        if let values = field["enum"]?.arrayValue?.compactMap(\.stringValue), !values.isEmpty {
            return values.map { TypedResponseOption(label: $0, value: $0) }
        }

        let variants = field["oneOf"]?.arrayValue ?? field["anyOf"]?.arrayValue ?? []
        let options = variants.compactMap { variant -> TypedResponseOption? in
            guard let value = variant["const"]?.stringValue ?? variant["enum"]?.arrayValue?.first?.stringValue else {
                return nil
            }
            let label = variant["title"]?.stringValue
                ?? variant["label"]?.stringValue
                ?? variant["description"]?.stringValue
                ?? value
            return TypedResponseOption(label: label, value: value)
        }
        return options.isEmpty ? nil : options
    }

    private func choiceValue(matching text: String, in choices: [TypedResponseOption]) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return choices.first {
            $0.value.caseInsensitiveCompare(trimmed) == .orderedSame
                || $0.label.caseInsensitiveCompare(trimmed) == .orderedSame
        }?.value
    }

    private static func parseJSONObject(from text: String) -> [String: JSONValue]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return nil
        }
        return value.objectValue
    }

    private static func parseBoolean(_ text: String) -> Bool? {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "y", "1", "allow", "approved", "approve", "accept":
            return true
        case "false", "no", "n", "0", "deny", "decline", "reject":
            return false
        default:
            return nil
        }
    }

    private static func isAttentionMethod(_ method: String) -> Bool {
        AppServerNotificationNormalizer.isAttentionMethod(method)
    }

    private static func threadID(from params: JSONValue?) -> String? {
        AppServerNotificationNormalizer.threadID(from: params)
    }

    private static func turnID(from params: JSONValue?) -> String? {
        AppServerNotificationNormalizer.turnID(from: params)
    }

    private static func attentionSummary(method: String, params: JSONValue?) -> String {
        AppServerNotificationNormalizer.attentionSummary(method: method, params: params)
    }
}
