public struct WorkflowPromptContextSummary: Equatable, Sendable {
    public var chatReferenceCount: Int
    public var folderReferenceCount: Int
    public var routeCount: Int
    public var rawText: String

    public init(
        chatReferenceCount: Int,
        folderReferenceCount: Int,
        routeCount: Int,
        rawText: String
    ) {
        self.chatReferenceCount = chatReferenceCount
        self.folderReferenceCount = folderReferenceCount
        self.routeCount = routeCount
        self.rawText = rawText
    }
}

public struct WorkflowPromptPresentation: Equatable, Sendable {
    public var visibleText: String
    public var executionPayload: String
    public var workflowContext: WorkflowPromptContextSummary?

    public init(
        visibleText: String,
        executionPayload: String,
        workflowContext: WorkflowPromptContextSummary? = nil
    ) {
        self.visibleText = visibleText
        self.executionPayload = executionPayload
        self.workflowContext = workflowContext
    }
}

/// Wraps MapofAgents-generated workflow routing instructions so transcript
/// presentation can distinguish them from text authored by the user.
public enum WorkflowPromptEnvelope {
    public static let version = 1

    private static let openingTag = "<mapofagents-workflow-context version=\"\(version)\">"
    private static let closingTag = "</mapofagents-workflow-context>"
    private static let userEscapeOpeningTag = "<mapofagents-user-authored-workflow-payload version=\"\(version)\">"
    private static let userEscapeClosingTag = "</mapofagents-user-authored-workflow-payload>"
    private static let chatHeader = "Workflow chat references:"
    private static let folderHeader = "Workflow folder references:"
    private static let routeHeader = "Workflow route map:"
    private static let relayHeader = "Provider relay usage:"
    private static let relaySignature = "When a route is `mapofagents provider relay`"
    private static let sourceSignature = "Only use these references because the user inserted explicit workflow mention tokens."
    private static let preRelayLegacySourcePrefix = "You are running as hostID=\""
    private static let preRelayLegacyPrivacySignature =
        "Ask before using paths, endpoints, SSH details, or identity files; those values are intentionally not included here."

    public static func encode(userText: String, workflowContext: String) -> String {
        guard !workflowContext.isEmpty else { return userText }
        return userText
            + "\n\n"
            + openingTag
            + "\n"
            + workflowContext
            + "\n"
            + closingTag
    }

    /// Protects user-authored text that happens to be a complete, valid
    /// MapofAgents workflow payload. The explicit wrapper prevents transcript
    /// presentation from mistaking copied execution scaffolding for hidden
    /// generated context while preserving the user's text verbatim in the UI.
    ///
    /// Call this only at user-input boundaries. MapofAgents-generated workflow
    /// envelopes must remain unescaped so their context can be presented
    /// compactly.
    public static func escapingReservedEnvelope(in userText: String) -> String {
        if decodeUserEscape(userText) != nil {
            return userText
        }
        guard decodedWorkflowPayload(userText) != nil else {
            return userText
        }

        return userEscapeOpeningTag
            + "\n"
            + userText
            + "\n"
            + userEscapeClosingTag
    }

    public static func presentation(for executionPayload: String) -> WorkflowPromptPresentation {
        if let userAuthoredText = decodeUserEscape(executionPayload) {
            return WorkflowPromptPresentation(
                visibleText: userAuthoredText,
                executionPayload: executionPayload
            )
        }

        if let decoded = decodeVersioned(executionPayload) ?? decodeLegacy(executionPayload) {
            return WorkflowPromptPresentation(
                visibleText: decodeUserEscape(decoded.userText) ?? decoded.userText,
                executionPayload: executionPayload,
                workflowContext: decoded.summary
            )
        }

        return WorkflowPromptPresentation(
            visibleText: executionPayload,
            executionPayload: executionPayload
        )
    }

    private static func decodedWorkflowPayload(
        _ executionPayload: String
    ) -> (userText: String, summary: WorkflowPromptContextSummary)? {
        decodeVersioned(executionPayload) ?? decodeLegacy(executionPayload)
    }

    private static func decodeUserEscape(_ executionPayload: String) -> String? {
        let openingDelimiter = "\(userEscapeOpeningTag)\n"
        let closingDelimiter = "\n\(userEscapeClosingTag)"
        guard executionPayload.hasPrefix(openingDelimiter),
              executionPayload.hasSuffix(closingDelimiter) else {
            return nil
        }

        let contentStart = executionPayload.index(
            executionPayload.startIndex,
            offsetBy: openingDelimiter.count
        )
        let contentEnd = executionPayload.index(
            executionPayload.endIndex,
            offsetBy: -closingDelimiter.count
        )
        guard contentStart <= contentEnd else { return nil }

        let userAuthoredText = String(executionPayload[contentStart..<contentEnd])
        guard decodedWorkflowPayload(userAuthoredText) != nil else {
            return nil
        }
        return userAuthoredText
    }

    private static func decodeVersioned(
        _ executionPayload: String
    ) -> (userText: String, summary: WorkflowPromptContextSummary)? {
        let openingDelimiter = "\n\n\(openingTag)\n"
        let closingDelimiter = "\n\(closingTag)"
        guard executionPayload.hasSuffix(closingDelimiter),
              let openingRange = executionPayload.range(
                of: openingDelimiter,
                options: .backwards
              ) else {
            return nil
        }

        let contextStart = openingRange.upperBound
        let contextEnd = executionPayload.index(
            executionPayload.endIndex,
            offsetBy: -closingDelimiter.count
        )
        guard contextStart <= contextEnd else { return nil }

        let context = String(executionPayload[contextStart..<contextEnd])
        guard let summary = summarize(context) else { return nil }

        return (
            userText: String(executionPayload[..<openingRange.lowerBound]),
            summary: summary
        )
    }

    private static func decodeLegacy(
        _ executionPayload: String
    ) -> (userText: String, summary: WorkflowPromptContextSummary)? {
        let legacyDelimiter = "\n\n\(chatHeader)\n"
        guard let openingRange = executionPayload.range(
            of: legacyDelimiter,
            options: .backwards
        ) else {
            return nil
        }

        let context = chatHeader + "\n" + executionPayload[openingRange.upperBound...]
        guard let summary = summarize(String(context))
            ?? summarizePreRelayLegacy(String(context)) else {
            return nil
        }

        return (
            userText: String(executionPayload[..<openingRange.lowerBound]),
            summary: summary
        )
    }

    private static func summarize(_ context: String) -> WorkflowPromptContextSummary? {
        let lines = context.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)

        guard let chatIndex = lines.firstIndex(of: chatHeader),
              let folderIndex = lines.firstIndex(of: folderHeader),
              let routeIndex = lines.firstIndex(of: routeHeader),
              let relayIndex = lines.firstIndex(of: relayHeader),
              chatIndex < folderIndex,
              folderIndex < routeIndex,
              routeIndex < relayIndex else {
            return nil
        }

        let relayLines = lines[lines.index(after: relayIndex)...]
        let hasRelaySignature = relayLines.contains(where: {
            $0.hasPrefix("- \(relaySignature)")
        })
        let hasSourceSignature = relayLines.contains(where: {
            $0.hasPrefix("You are running as provider=")
                && $0.contains(sourceSignature)
        })
        guard hasRelaySignature, hasSourceSignature else {
            return nil
        }

        let chatReferenceCount = referenceCount(
            in: lines,
            after: chatIndex,
            before: folderIndex
        )
        let folderReferenceCount = referenceCount(
            in: lines,
            after: folderIndex,
            before: routeIndex
        )
        let routeCount = referenceCount(
            in: lines,
            after: routeIndex,
            before: relayIndex
        )
        guard chatReferenceCount + folderReferenceCount > 0, routeCount > 0 else {
            return nil
        }

        return WorkflowPromptContextSummary(
            chatReferenceCount: chatReferenceCount,
            folderReferenceCount: folderReferenceCount,
            routeCount: routeCount,
            rawText: context
        )
    }

    /// Recognizes the complete workflow context emitted before the provider
    /// relay section was introduced. Requiring both historical signatures and
    /// the full ordered section shape keeps ordinary user-authored headings
    /// visible while cleaning transcripts already stored by older releases.
    private static func summarizePreRelayLegacy(
        _ context: String
    ) -> WorkflowPromptContextSummary? {
        let lines = context.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)

        guard let chatIndex = lines.firstIndex(of: chatHeader),
              let folderIndex = lines.firstIndex(of: folderHeader),
              let routeIndex = lines.firstIndex(of: routeHeader),
              let sourceIndex = lines.firstIndex(where: { line in
                  line.hasPrefix(preRelayLegacySourcePrefix)
                      && line.contains(sourceSignature)
                      && line.contains(preRelayLegacyPrivacySignature)
              }),
              chatIndex < folderIndex,
              folderIndex < routeIndex,
              routeIndex < sourceIndex,
              lines[lines.index(after: sourceIndex)...].allSatisfy(\.isEmpty) else {
            return nil
        }

        let chatReferenceCount = referenceCount(
            in: lines,
            after: chatIndex,
            before: folderIndex
        )
        let folderReferenceCount = referenceCount(
            in: lines,
            after: folderIndex,
            before: routeIndex
        )
        let routeCount = referenceCount(
            in: lines,
            after: routeIndex,
            before: sourceIndex
        )
        guard chatReferenceCount + folderReferenceCount > 0, routeCount > 0 else {
            return nil
        }

        return WorkflowPromptContextSummary(
            chatReferenceCount: chatReferenceCount,
            folderReferenceCount: folderReferenceCount,
            routeCount: routeCount,
            rawText: context
        )
    }

    private static func referenceCount(
        in lines: [String],
        after startIndex: Int,
        before endIndex: Int
    ) -> Int {
        let firstIndex = lines.index(after: startIndex)
        guard firstIndex < endIndex else { return 0 }
        return lines[firstIndex..<endIndex].count { line in
            line.hasPrefix("- ") && line != "- none"
        }
    }
}
