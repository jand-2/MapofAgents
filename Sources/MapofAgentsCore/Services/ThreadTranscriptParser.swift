import Foundation

public enum ThreadTranscriptParser {
    public static func discoveredThreadIDs(in transcript: ThreadTranscript, excluding excludedIDs: Set<String> = []) -> [String] {
        let text = transcript.messages
            .map(\.text)
            .joined(separator: "\n")

        return discoveredThreadIDs(in: text, excluding: excludedIDs.union([transcript.threadRef.threadID]))
    }

    public static func discoveredThreadIDs(in text: String, excluding excludedIDs: Set<String> = []) -> [String] {
        let normalizedExcludedIDs = Set(excludedIDs.map { $0.lowercased() })
        let pattern = #"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<String>()
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else {
                return nil
            }

            let threadID = String(text[swiftRange]).lowercased()
            guard !normalizedExcludedIDs.contains(threadID), seen.insert(threadID).inserted else {
                return nil
            }
            return threadID
        }
    }

    public static func transcript(from result: JSONValue, threadRef: ThreadRef) -> ThreadTranscript {
        var messages: [ThreadMessage] = []

        for turn in result["data"]?.arrayValue ?? [] {
            for item in turn["items"]?.arrayValue ?? [] {
                guard let type = item["type"]?.stringValue else { continue }
                let createdAt = messageDate(from: item, fallback: turn)
                switch type {
                case "userMessage":
                    let text = (item["content"]?.arrayValue ?? [])
                        .compactMap(Self.contentText)
                        .joined(separator: "\n")
                    if !text.isEmpty {
                        messages.append(ThreadMessage(id: messageID(from: item), role: .user, text: text, createdAt: createdAt))
                    }
                case "agentMessage":
                    if let text = item["text"]?.stringValue, !text.isEmpty {
                        let id = messageID(from: item)
                        messages.append(
                            ThreadMessage(
                                id: id,
                                role: .assistant,
                                text: text,
                                createdAt: createdAt
                            )
                        )
                    }
                case "reasoning":
                    let text = (item["summary"]?.arrayValue ?? [])
                        .compactMap(Self.contentText)
                        .joined(separator: "\n")
                    if !text.isEmpty {
                        messages.append(ThreadMessage(id: messageID(from: item), role: .reasoning, text: text, createdAt: createdAt))
                    }
                case "commandExecution":
                    let command = item["command"]?.stringValue ?? "Command"
                    let output = item["aggregatedOutput"]?.stringValue ?? ""
                    let id = messageID(from: item)
                    messages.append(
                        ThreadMessage(
                            id: id,
                            role: .tool,
                            text: toolMessageText(name: command, arguments: nil, output: output),
                            createdAt: createdAt,
                            attachments: artifactAttachments(in: item, output: output, threadRef: threadRef, createdAt: createdAt, idPrefix: id)
                        )
                    )
                case "fileChange", "file_change":
                    let id = messageID(from: item, fallbackPrefix: "file-change")
                    let output = formattedOutput(from: item)
                        ?? formattedArguments(from: item)
                        ?? prettyJSONString(item)
                    messages.append(
                        ThreadMessage(
                            id: id,
                            role: .tool,
                            text: toolMessageText(name: "file_change", arguments: nil, output: output),
                            createdAt: createdAt,
                            attachments: artifactAttachments(in: item, output: output, threadRef: threadRef, createdAt: createdAt, idPrefix: id)
                        )
                    )
                case "mcpToolCall":
                    let name = toolName(from: item, fallback: "MCP tool")
                    let arguments = formattedArguments(from: item)
                    let output = formattedOutput(from: item)
                    let id = messageID(from: item)
                    let attachments = artifactAttachments(in: item, output: output, threadRef: threadRef, createdAt: createdAt, idPrefix: id)
                    messages.append(
                        ThreadMessage(
                            id: id,
                            role: .tool,
                            text: toolMessageText(name: name, arguments: arguments, output: output),
                            createdAt: createdAt,
                            attachments: attachments
                        )
                    )
                case "imageGeneration":
                    let id = messageID(from: item)
                    let revisedPrompt = item["revisedPrompt"]?.stringValue ?? item["revised_prompt"]?.stringValue
                    let sourcePath = item["savedPath"]?.stringValue ?? item["saved_path"]?.stringValue
                    let status = normalizedImageGenerationStatus(
                        item["status"]?.stringValue,
                        sourcePath: sourcePath
                    )
                    messages.append(
                        ThreadMessage(
                            id: id,
                            role: .tool,
                            text: imageGenerationMessageText(id: id, status: status, revisedPrompt: revisedPrompt, sourcePath: sourcePath),
                            createdAt: createdAt,
                            attachments: imageAttachment(
                                id: id,
                                sourceHostID: threadRef.hostID,
                                sourcePath: sourcePath,
                                title: "Generated image",
                                status: status,
                                revisedPrompt: revisedPrompt,
                                createdAt: createdAt
                            ).map { [$0] } ?? []
                        )
                    )
                case "imageView":
                    let id = messageID(from: item)
                    let sourcePath = item["path"]?.stringValue
                    messages.append(
                        ThreadMessage(
                            id: id,
                            role: .tool,
                            text: imageViewMessageText(path: sourcePath),
                            createdAt: createdAt,
                            attachments: imageAttachment(
                                id: id,
                                sourceHostID: threadRef.hostID,
                                sourcePath: sourcePath,
                                title: "Image",
                                createdAt: createdAt
                            ).map { [$0] } ?? []
                        )
                    )
                default:
                    continue
                }
            }
        }

        let uniqueMessages = messagesWithUniqueIDs(messages)
        return ThreadTranscript(
            threadRef: threadRef,
            messages: uniqueMessages,
            nextCursor: result["nextCursor"]?.stringValue,
            lastUpdatedAt: Date(),
            turnTimeline: ThreadTurnTimeline.fromAppServerResult(result, threadRef: threadRef, messages: uniqueMessages)
        ).sortedChronologically()
    }

    public static func transcript(fromRolloutData data: Data, threadRef: ThreadRef) -> ThreadTranscript {
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let events = text
            .split(separator: "\n")
            .compactMap { line -> JSONValue? in
                try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
            }

        return transcript(fromRolloutEvents: events, threadRef: threadRef)
    }

    public static func transcript(fromRolloutEvents events: [JSONValue], threadRef: ThreadRef) -> ThreadTranscript {
        var messages: [ThreadMessage] = []
        var toolMessageIndexByCallID: [String: Int] = [:]

        for event in events {
            guard let payload = event["payload"] else {
                continue
            }

            if event["type"]?.stringValue == "event_msg",
               payload["type"]?.stringValue == "patch_apply_end" {
                let callID = payload["call_id"]?.stringValue ?? payload["callId"]?.stringValue
                let id = callID ?? messageID(from: payload, fallbackPrefix: "patch-apply")
                let createdAt = messageDate(from: payload, fallback: event)
                let output = formattedOutput(from: payload)
                let attachments = artifactAttachments(in: payload, output: output, threadRef: threadRef, createdAt: createdAt, idPrefix: id)

                if let callID, let index = toolMessageIndexByCallID[callID] {
                    if let output, !output.isEmpty {
                        messages[index].text = appendToolOutput(output, to: messages[index].text)
                    }
                    messages[index].attachments.append(contentsOf: attachments)
                    messages[index].attachments = deduplicatedAttachments(messages[index].attachments)
                } else if let output, !output.isEmpty || !attachments.isEmpty {
                    messages.append(
                        ThreadMessage(
                            id: id,
                            role: .tool,
                            text: toolMessageText(name: "apply_patch", arguments: nil, output: output),
                            createdAt: createdAt,
                            attachments: attachments
                        )
                    )
                    if let callID {
                        toolMessageIndexByCallID[callID] = messages.count - 1
                    }
                }
                continue
            }

            guard event["type"]?.stringValue == "response_item" else {
                continue
            }

            guard let type = payload["type"]?.stringValue else { continue }
            let createdAt = messageDate(from: payload, fallback: event)
            switch type {
            case "message":
                guard let role = payload["role"]?.stringValue,
                      let messageRole = messageRole(from: role) else {
                    continue
                }

                let text = (payload["content"]?.arrayValue ?? [])
                    .compactMap(Self.contentText)
                    .joined(separator: "\n")
                guard !text.isEmpty else { continue }
                let id = messageID(from: payload, fallbackPrefix: "message")
                messages.append(
                    ThreadMessage(
                        id: id,
                        role: messageRole,
                        text: text,
                        createdAt: createdAt
                    )
                )

            case "reasoning":
                let text = (payload["summary"]?.arrayValue ?? [])
                    .compactMap(Self.contentText)
                    .joined(separator: "\n")
                guard !text.isEmpty else { continue }
                messages.append(
                    ThreadMessage(
                        id: messageID(from: payload, fallbackPrefix: "reasoning"),
                        role: .reasoning,
                        text: text,
                        createdAt: createdAt
                    )
                )

            case "function_call":
                let name = payload["name"]?.stringValue ?? "Tool call"
                let arguments = formattedArguments(from: payload)
                let callID = payload["call_id"]?.stringValue ?? payload["callId"]?.stringValue
                let id = callID ?? messageID(from: payload, fallbackPrefix: "tool-call")
                let attachments = artifactAttachments(in: payload, output: nil, threadRef: threadRef, createdAt: createdAt, idPrefix: id)
                let message = ThreadMessage(
                    id: id,
                    role: .tool,
                    text: toolMessageText(name: name, arguments: arguments, output: nil),
                    createdAt: createdAt,
                    attachments: attachments
                )
                messages.append(message)
                if let callID {
                    toolMessageIndexByCallID[callID] = messages.count - 1
                }

            case "function_call_output", "custom_tool_call_output", "tool_search_output":
                let callID = payload["call_id"]?.stringValue ?? payload["callId"]?.stringValue
                let output = formattedOutput(from: payload) ?? formattedArguments(from: payload)
                guard let output, !output.isEmpty else { continue }

                if let callID, let index = toolMessageIndexByCallID[callID] {
                    messages[index].text = appendToolOutput(output, to: messages[index].text)
                    let artifactOutput = [messages[index].text, output].joined(separator: "\n\n")
                    messages[index].attachments.append(
                        contentsOf: artifactAttachments(
                            in: payload,
                            output: artifactOutput,
                            threadRef: threadRef,
                            createdAt: createdAt,
                            idPrefix: callID
                        )
                    )
                    messages[index].attachments = deduplicatedAttachments(messages[index].attachments)
                } else {
                    let id = callID ?? messageID(from: payload, fallbackPrefix: "tool-output")
                    messages.append(
                        ThreadMessage(
                            id: id,
                            role: .tool,
                            text: toolMessageText(name: "Tool output", arguments: nil, output: output),
                            createdAt: createdAt,
                            attachments: artifactAttachments(in: payload, output: output, threadRef: threadRef, createdAt: createdAt, idPrefix: id)
                        )
                    )
                }

            case "image_generation_call":
                let id = messageID(from: payload, fallbackPrefix: "image-generation")
                let revisedPrompt = payload["revised_prompt"]?.stringValue ?? payload["revisedPrompt"]?.stringValue
                let status = normalizedImageGenerationStatus(payload["status"]?.stringValue, sourcePath: nil)
                messages.append(
                    ThreadMessage(
                        id: id,
                        role: .tool,
                        text: imageGenerationMessageText(id: id, status: status, revisedPrompt: revisedPrompt, sourcePath: nil),
                        createdAt: createdAt
                    )
                )

            default:
                guard isGenericToolItem(type) else { continue }
                let name = toolName(from: payload, fallback: displayName(forToolType: type))
                let arguments = formattedArguments(from: payload)
                let output = formattedOutput(from: payload)
                let callID = payload["call_id"]?.stringValue ?? payload["callId"]?.stringValue
                let id = messageID(from: payload, fallbackPrefix: "tool")
                let attachments = artifactAttachments(in: payload, output: output, threadRef: threadRef, createdAt: createdAt, idPrefix: id)
                messages.append(
                    ThreadMessage(
                        id: id,
                        role: .tool,
                        text: toolMessageText(name: name, arguments: arguments, output: output),
                        createdAt: createdAt,
                        attachments: attachments
                    )
                )
                if let callID {
                    toolMessageIndexByCallID[callID] = messages.count - 1
                }
            }
        }

        return ThreadTranscript(
            threadRef: threadRef,
            messages: messagesWithUniqueIDs(messages),
            lastUpdatedAt: Date()
        )
    }

    public static func transcriptByAddingImageAttachments(
        from source: ThreadTranscript,
        to target: ThreadTranscript,
        appendMissingMessages: Bool = true
    ) -> ThreadTranscript {
        var merged = target
        var timeline = merged.turnTimeline ?? ThreadTurnTimeline.fromTranscript(merged)
        var indexByMessageID: [String: Int] = [:]
        for (index, message) in merged.messages.enumerated() {
            indexByMessageID[message.id] = index
        }
        var indexesByMessageSemanticKey: [String: [Int]] = [:]
        for (index, message) in merged.messages.enumerated() {
            guard let key = messageSemanticTimestampKey(message) else { continue }
            indexesByMessageSemanticKey[key, default: []].append(index)
        }
        var usedSemanticMatchIndexes = Set<Int>()
        var matchedIndexBySourceMessageID: [String: Int] = [:]
        var existingAttachmentKeys = Set(merged.primaryArtifactAttachments.map(attachmentSemanticKey))
        let targetPageRange = messageDateRange(merged.messages)

        for sourceMessage in source.messages {
            if let index = indexByMessageID[sourceMessage.id] {
                // App Server tool rows can carry the parent turn timestamp. Rollout
                // events preserve the actual item order/timestamp, so let matching
                // rollout messages correct display ordering without replacing the
                // richer App Server text.
                merged.messages[index].createdAt = sourceMessage.createdAt
                matchedIndexBySourceMessageID[sourceMessage.id] = index
            } else if let index = semanticTimestampMatchIndex(
                for: sourceMessage,
                in: indexesByMessageSemanticKey,
                usedIndexes: usedSemanticMatchIndexes
            ) {
                usedSemanticMatchIndexes.insert(index)
                merged.messages[index].createdAt = sourceMessage.createdAt
                matchedIndexBySourceMessageID[sourceMessage.id] = index
            } else if !appendMissingMessages,
                      sourceMessage.role == .tool,
                      isMessage(sourceMessage, inside: targetPageRange),
                      !merged.messages.contains(where: { $0.role == .tool && $0.text == sourceMessage.text }) {
                var message = sourceMessage
                message.attachments = []
                merged.messages.append(message)
                indexByMessageID[message.id] = merged.messages.count - 1
                matchedIndexBySourceMessageID[sourceMessage.id] = merged.messages.count - 1
            }
        }

        for candidate in artifactMergeCandidates(from: source) {
            if let index = matchedIndexBySourceMessageID[candidate.message.id] ?? indexByMessageID[candidate.itemID] {
                let attachments = uniqueAttachments(candidate.attachments, existingKeys: &existingAttachmentKeys)
                guard !attachments.isEmpty else { continue }
                addArtifactAttachments(
                    attachments,
                    itemID: candidate.itemID,
                    message: merged.messages[index],
                    to: &timeline
                )
            } else if appendMissingMessages {
                var message = candidate.message
                message.attachments = []
                let attachments = uniqueAttachments(candidate.attachments, existingKeys: &existingAttachmentKeys)
                guard !attachments.isEmpty else { continue }
                merged.messages.append(message)
                indexByMessageID[message.id] = merged.messages.count - 1
                addArtifactAttachments(
                    attachments,
                    itemID: candidate.itemID,
                    message: message,
                    to: &timeline
                )
            } else if candidate.message.role == .tool,
                      isMessage(candidate.message, inside: targetPageRange),
                      !merged.messages.contains(where: { $0.role == .tool && $0.text == candidate.message.text }) {
                var message = candidate.message
                message.attachments = []
                let attachments = uniqueAttachments(candidate.attachments, existingKeys: &existingAttachmentKeys)
                guard !attachments.isEmpty else { continue }
                merged.messages.append(message)
                indexByMessageID[message.id] = merged.messages.count - 1
                addArtifactAttachments(
                    attachments,
                    itemID: candidate.itemID,
                    message: message,
                    to: &timeline
                )
            } else if isMessage(candidate.message, inside: targetPageRange) {
                let attachments = uniqueAttachments(
                    candidate.attachments.filter { $0.kind != .image },
                    existingKeys: &existingAttachmentKeys
                )
                guard !attachments.isEmpty else { continue }
                var message = candidate.message
                message.attachments = []
                merged.messages.append(message)
                indexByMessageID[message.id] = merged.messages.count - 1
                addArtifactAttachments(
                    attachments,
                    itemID: candidate.itemID,
                    message: message,
                    to: &timeline
                )
            }
        }

        merged.turnTimeline = timeline
        return merged.sortedChronologically()
    }

    private struct ArtifactMergeCandidate {
        var itemID: String
        var message: ThreadMessage
        var attachments: [ThreadMessageAttachment]
    }

    private static func artifactMergeCandidates(from transcript: ThreadTranscript) -> [ArtifactMergeCandidate] {
        var candidates: [ArtifactMergeCandidate] = []
        var seen = Set<String>()

        for turn in transcript.turnTimeline?.turns ?? [] {
            for item in turn.items {
                let attachments = item.effectiveAttachments
                guard !attachments.isEmpty else { continue }
                let key = artifactCandidateKey(itemID: item.id, messageID: item.message.id, attachments: attachments)
                guard seen.insert(key).inserted else { continue }
                candidates.append(
                    ArtifactMergeCandidate(
                        itemID: item.id,
                        message: item.message,
                        attachments: attachments
                    )
                )
            }
        }

        for message in transcript.messages {
            guard !message.attachments.isEmpty else { continue }
            let key = artifactCandidateKey(itemID: message.id, messageID: message.id, attachments: message.attachments)
            guard seen.insert(key).inserted else { continue }
            candidates.append(
                ArtifactMergeCandidate(
                    itemID: message.id,
                    message: message,
                    attachments: message.attachments
                )
            )
        }

        return candidates
    }

    private static func artifactCandidateKey(
        itemID: String,
        messageID: String,
        attachments: [ThreadMessageAttachment]
    ) -> String {
        [
            itemID,
            messageID,
            attachments.map(attachmentSemanticKey).joined(separator: "|"),
        ].joined(separator: "::")
    }

    private static func uniqueAttachments(
        _ attachments: [ThreadMessageAttachment],
        existingKeys: inout Set<String>
    ) -> [ThreadMessageAttachment] {
        attachments.filter { attachment in
            existingKeys.insert(attachmentSemanticKey(attachment)).inserted
        }
    }

    private static func addArtifactAttachments(
        _ attachments: [ThreadMessageAttachment],
        itemID: String,
        message: ThreadMessage,
        to timeline: inout ThreadTurnTimeline
    ) {
        guard !attachments.isEmpty else { return }
        var message = message
        message.attachments = []

        for turnIndex in timeline.turns.indices {
            if let itemIndex = timeline.turns[turnIndex].items.firstIndex(where: {
                $0.id == itemID || $0.id == message.id || $0.message.id == message.id
            }) {
                var item = timeline.turns[turnIndex].items[itemIndex]
                item.message = message
                item.attachments = deduplicatedAttachments(item.effectiveAttachments + attachments)
                item.kind = artifactItemKind(for: item.effectiveAttachments, fallback: item.kind)
                timeline.turns[turnIndex].items[itemIndex] = item
                return
            }
        }

        let item = ThreadTurnItem(
            id: itemID,
            kind: artifactItemKind(for: attachments, fallback: messageItemKind(message)),
            message: message,
            attachments: attachments
        )
        if let index = nearestTurnIndex(in: timeline.turns, containing: message.createdAt) {
            timeline.turns[index].items.append(item)
            timeline.turns[index].startedAt = min(timeline.turns[index].startedAt, message.createdAt)
            timeline.turns[index].completedAt = timeline.turns[index].completedAt.map {
                max($0, message.createdAt)
            } ?? message.createdAt
        } else {
            timeline.turns.append(
                ThreadTurn(
                    id: "\(timeline.threadRef.qualifiedID)-turn-\(timeline.turns.count + 1)",
                    status: .complete,
                    startedAt: message.createdAt,
                    completedAt: message.createdAt,
                    items: [item]
                )
            )
        }
    }

    private static func nearestTurnIndex(in turns: [ThreadTurn], containing date: Date) -> Int? {
        guard !turns.isEmpty else {
            return nil
        }

        if let containingIndex = turns.firstIndex(where: { turn in
            let end = turn.completedAt ?? turn.startedAt
            return turn.startedAt <= date && date <= end
        }) {
            return containingIndex
        }

        return turns.indices.min { lhs, rhs in
            let lhsDistance = abs(turns[lhs].startedAt.timeIntervalSince(date))
            let rhsDistance = abs(turns[rhs].startedAt.timeIntervalSince(date))
            return lhsDistance < rhsDistance
        }
    }

    private static func artifactItemKind(
        for attachments: [ThreadMessageAttachment],
        fallback: ThreadTurnItemKind
    ) -> ThreadTurnItemKind {
        if attachments.contains(where: { $0.kind == .image }) {
            return .imageArtifact
        }
        if attachments.contains(where: { $0.kind == .diff }) {
            return .diffArtifact
        }
        if attachments.contains(where: { $0.kind == .file }) {
            return .fileArtifact
        }
        return fallback
    }

    private static func messageItemKind(_ message: ThreadMessage) -> ThreadTurnItemKind {
        if let attachment = message.attachments.first {
            return artifactItemKind(for: [attachment], fallback: .artifact)
        }

        switch message.role {
        case .user:
            return .userMessage
        case .assistant:
            return .assistantMessage
        case .reasoning:
            return .reasoning
        case .tool:
            return .tool
        case .system:
            return .system
        }
    }

    private static func semanticTimestampMatchIndex(
        for sourceMessage: ThreadMessage,
        in indexesByMessageSemanticKey: [String: [Int]],
        usedIndexes: Set<Int>
    ) -> Int? {
        guard let key = messageSemanticTimestampKey(sourceMessage),
              let indexes = indexesByMessageSemanticKey[key]
        else {
            return nil
        }
        return indexes.first { !usedIndexes.contains($0) }
    }

    private static func messageSemanticTimestampKey(_ message: ThreadMessage) -> String? {
        guard message.role == .assistant || message.role == .user else {
            return nil
        }

        let normalizedText = message.text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return nil
        }
        return "\(message.role.rawValue)::\(normalizedText)"
    }

    private static func messageDateRange(_ messages: [ThreadMessage]) -> ClosedRange<Date>? {
        guard let minDate = messages.map(\.createdAt).min(),
              let maxDate = messages.map(\.createdAt).max()
        else {
            return nil
        }
        return minDate...maxDate
    }

    private static func isMessage(_ message: ThreadMessage, inside range: ClosedRange<Date>?) -> Bool {
        guard let range else {
            return false
        }
        return range.contains(message.createdAt)
    }

    private static func messageRole(from role: String) -> ThreadMessageRole? {
        switch role {
        case "user":
            return .user
        case "assistant":
            return .assistant
        case "system":
            return .system
        default:
            return nil
        }
    }

    private static func messageID(from value: JSONValue, fallbackPrefix: String = "item") -> String {
        nonEmptyString(value["id"])
            ?? nonEmptyString(value["call_id"])
            ?? nonEmptyString(value["callId"])
            ?? "\(fallbackPrefix)-\(stableHash(for: value))"
    }

    private static func nonEmptyString(_ value: JSONValue?) -> String? {
        guard let string = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty
        else {
            return nil
        }
        return string
    }

    private static func messagesWithUniqueIDs(_ messages: [ThreadMessage]) -> [ThreadMessage] {
        var seen: [String: Int] = [:]
        return messages.map { message in
            let count = (seen[message.id] ?? 0) + 1
            seen[message.id] = count
            guard count > 1 else {
                return message
            }
            var copy = message
            copy.id = "\(message.id)-\(count)"
            return copy
        }
    }

    private static func stableHash(for value: JSONValue) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in canonicalString(from: value).utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func canonicalString(from value: JSONValue) -> String {
        switch value {
        case .object(let object):
            let body = object.keys.sorted().map { key in
                "\(key):\(canonicalString(from: object[key] ?? .null))"
            }
                .joined(separator: ",")
            return "{\(body)}"
        case .array(let array):
            return "[\(array.map(canonicalString).joined(separator: ","))]"
        case .string(let string):
            return "s:\(string)"
        case .number(let number):
            return "n:\(number)"
        case .bool(let bool):
            return "b:\(bool)"
        case .null:
            return "null"
        }
    }

    private static func messageDate(from value: JSONValue, fallback: JSONValue? = nil) -> Date {
        date(from: value) ?? fallback.flatMap(date(from:)) ?? Date()
    }

    private static func date(from value: JSONValue) -> Date? {
        for key in [
            "createdAt",
            "created_at",
            "timestamp",
            "time",
            "updatedAt",
            "updated_at",
            "completedAt",
            "completed_at",
            "startedAt",
            "started_at",
        ] {
            guard let candidate = value[key] else { continue }
            if let date = parseDate(candidate) {
                return date
            }
        }
        return nil
    }

    private static func parseDate(_ value: JSONValue) -> Date? {
        if let string = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty {
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

    private static func contentText(from value: JSONValue) -> String? {
        value["text"]?.stringValue
            ?? value["input_text"]?.stringValue
            ?? value["output_text"]?.stringValue
            ?? value["summary_text"]?.stringValue
            ?? value.stringValue
    }

    private static func toolName(from value: JSONValue, fallback: String) -> String {
        let serverName = value["serverName"]?.stringValue
            ?? value["server_name"]?.stringValue
            ?? value["server"]?.stringValue
        let toolName = value["toolName"]?.stringValue
            ?? value["tool_name"]?.stringValue
            ?? value["tool"]?.stringValue
            ?? value["name"]?.stringValue
            ?? value["command"]?.stringValue
        if let serverName, let toolName {
            return "\(serverName).\(toolName)"
        }
        return toolName ?? fallback
    }

    private static func formattedArguments(from value: JSONValue) -> String? {
        formattedValue(
            value["arguments"]
                ?? value["args"]
                ?? value["input"]
                ?? value["params"]
                ?? value["action"]
        )
    }

    private static func formattedOutput(from value: JSONValue) -> String? {
        formattedValue(
            value["output"]
                ?? value["aggregatedOutput"]
                ?? value["aggregated_output"]
                ?? value["result"]
                ?? value["stdout"]
                ?? value["stderr"]
        )
    }

    private static func formattedValue(_ value: JSONValue?) -> String? {
        guard let value else { return nil }

        if let string = value.stringValue {
            guard !string.isEmpty else { return nil }
            if let data = string.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(JSONValue.self, from: data),
               let pretty = prettyJSONString(decoded) {
                return pretty
            }
            return string
        }

        return prettyJSONString(value)
    }

    private static func prettyJSONString(_ value: JSONValue) -> String? {
        guard let data = try? JSONEncoder.pretty.encode(value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func imageGenerationMessageText(
        id: String,
        status: String?,
        revisedPrompt: String?,
        sourcePath: String?
    ) -> String {
        var sections = ["Generated image"]
        if let status, !status.isEmpty {
            sections.append("Status: \(status)")
        }
        if let revisedPrompt, !revisedPrompt.isEmpty {
            sections.append("Prompt:\n\(revisedPrompt)")
        }
        if let sourcePath, !sourcePath.isEmpty {
            sections.append("Saved to:\n\(sourcePath)")
        } else {
            sections.append("Image id: \(id)")
        }
        return sections.joined(separator: "\n\n")
    }

    private static func normalizedImageGenerationStatus(_ status: String?, sourcePath: String?) -> String? {
        if normalizedImagePath(sourcePath) != nil {
            return "completed"
        }

        guard let status, !status.isEmpty else {
            return status
        }

        let lowercased = status.lowercased()
        if lowercased == "generating" || lowercased == "in_progress" || lowercased == "running" {
            return "generating"
        }
        return status
    }

    private static func imageViewMessageText(path: String?) -> String {
        guard let path, !path.isEmpty else {
            return "Image"
        }
        return "Image\n\nPath:\n\(path)"
    }

    private struct FileArtifactCandidate {
        var path: String
        var title: String?
        var status: String?
        var changeType: ThreadMessageAttachmentChangeType
        var diffText: String?
        var sourceHostID: HostID?
        var isTrustedForAutoHydration: Bool = true
    }

    private static func artifactAttachments(
        in value: JSONValue,
        output: String?,
        threadRef: ThreadRef,
        createdAt: Date,
        idPrefix: String
    ) -> [ThreadMessageAttachment] {
        let artifactText = artifactEvidenceText(in: value, output: output)
        var attachments = fileAttachments(in: value, output: artifactText, threadRef: threadRef, createdAt: createdAt, idPrefix: idPrefix)
        if let diffAttachment = diffAttachment(in: artifactText, threadRef: threadRef, createdAt: createdAt, idPrefix: idPrefix) {
            attachments.append(diffAttachment)
        }
        return deduplicatedAttachments(attachments)
    }

    private static func artifactEvidenceText(in value: JSONValue, output: String?) -> String? {
        var sections: [String] = []
        if let output, !output.isEmpty {
            sections.append(output)
        }
        if let patchText = patchText(fromToolInputIn: value) {
            sections.append(patchText)
        }
        if let commandText = commandText(fromToolInputIn: value) {
            sections.append(commandText)
        }
        return sections.isEmpty ? nil : sections.joined(separator: "\n\n")
    }

    private static func fileAttachments(
        in value: JSONValue,
        output: String?,
        threadRef: ThreadRef,
        createdAt: Date,
        idPrefix: String
    ) -> [ThreadMessageAttachment] {
        var candidates: [FileArtifactCandidate] = []
        collectStructuredFileCandidates(in: value, candidates: &candidates)

        return fileAttachments(
            from: candidates,
            threadRef: threadRef,
            createdAt: createdAt,
            idPrefix: idPrefix
        )
    }

    private static func fileAttachments(
        from candidates: [FileArtifactCandidate],
        threadRef: ThreadRef,
        createdAt: Date,
        idPrefix: String
    ) -> [ThreadMessageAttachment] {
        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let key = candidate.path
            guard seen.insert(key).inserted else { return nil }
            return ThreadMessageAttachment(
                id: "\(idPrefix)-file-\(sanitizeID(candidate.path))",
                kind: .file,
                sourceHostID: candidate.sourceHostID ?? threadRef.hostID,
                sourcePath: candidate.path,
                mimeType: TranscriptAssetCache.mimeType(forPath: candidate.path),
                title: candidate.title ?? fileName(forPath: candidate.path),
                status: candidate.status,
                createdAt: createdAt,
                changeType: candidate.changeType,
                diffText: candidate.diffText,
                language: TranscriptAssetCache.language(forPath: candidate.path),
                isTrustedForAutoHydration: candidate.isTrustedForAutoHydration
            )
        }
    }

    private static func collectStructuredFileCandidates(
        in value: JSONValue,
        candidates: inout [FileArtifactCandidate]
    ) {
        guard case .object(let object) = value else {
            return
        }
        if let patchCandidates = patchApplyChangeCandidates(in: object) {
            candidates.append(contentsOf: patchCandidates)
        }
        if let fileChangeCandidates = fileChangeCandidates(in: object) {
            candidates.append(contentsOf: fileChangeCandidates)
        }
    }

    private static func patchApplyChangeCandidates(in object: [String: JSONValue]) -> [FileArtifactCandidate]? {
        guard object["type"]?.stringValue == "patch_apply_end",
              case .object(let changes)? = object["changes"]
        else {
            return nil
        }

        let status = object["success"]?.boolValue == false ? "failed" : "completed"
        return changes.compactMap { path, change in
            guard let normalizedPath = normalizedFileArtifactPath(path) else {
                return nil
            }
            return FileArtifactCandidate(
                path: normalizedPath,
                title: fileName(forPath: normalizedPath),
                status: status,
                changeType: patchChangeType(from: change),
                diffText: structuredDiffText(from: change),
                isTrustedForAutoHydration: false
            )
        }
    }

    private static func fileChangeCandidates(in object: [String: JSONValue]) -> [FileArtifactCandidate]? {
        let typeText = [
            object["type"]?.stringValue,
            object["kind"]?.stringValue,
            object["event"]?.stringValue,
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        guard typeText.contains("filechange")
                || typeText.contains("file_change")
                || typeText.contains("file change")
        else {
            return nil
        }

        let changesValue = object["changes"]
            ?? object["files"]
            ?? object["fileChanges"]
            ?? object["file_changes"]
        let status = object["status"]?.stringValue ?? "completed"
        switch changesValue {
        case .object(let changes)?:
            return changes.compactMap { path, change in
                guard let normalizedPath = normalizedFileArtifactPath(path) else {
                    return nil
                }
                return FileArtifactCandidate(
                    path: normalizedPath,
                    title: fileName(forPath: normalizedPath),
                    status: status,
                    changeType: patchChangeType(from: change),
                    diffText: structuredDiffText(from: change),
                    isTrustedForAutoHydration: false
                )
            }
        case .array(let changes)?:
            return changes.compactMap { change in
                guard case .object(let changeObject) = change,
                      let rawPath = changeObject["path"]?.stringValue
                        ?? changeObject["filePath"]?.stringValue
                        ?? changeObject["file_path"]?.stringValue,
                      let normalizedPath = normalizedFileArtifactPath(rawPath)
                else {
                    return nil
                }
                return FileArtifactCandidate(
                    path: normalizedPath,
                    title: changeObject["title"]?.stringValue ?? changeObject["name"]?.stringValue ?? fileName(forPath: normalizedPath),
                    status: changeObject["status"]?.stringValue ?? status,
                    changeType: changeType(in: changeObject, key: "path", fallback: patchChangeType(from: change)),
                    diffText: structuredDiffText(from: change),
                    isTrustedForAutoHydration: false
                )
            }
        case .string?, .number?, .bool?, .null?, nil:
            return nil
        }
    }

    private static func structuredDiffText(from value: JSONValue) -> String? {
        guard case .object(let object) = value else {
            return nil
        }
        let candidates = [
            object["diff"]?.stringValue,
            object["unifiedDiff"]?.stringValue,
            object["unified_diff"]?.stringValue,
            object["patch"]?.stringValue,
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func patchChangeType(from value: JSONValue) -> ThreadMessageAttachmentChangeType {
        let changeText: String
        if case .object(let object) = value {
            changeText = [
                object["type"]?.stringValue,
                object["changeType"]?.stringValue,
                object["change_type"]?.stringValue,
                object["operation"]?.stringValue,
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        } else {
            changeText = value.stringValue?.lowercased() ?? ""
        }

        let changeType = changeType(fromEvidenceText: changeText)
        return changeType == .unknown ? .modified : changeType
    }

    private static func patchText(fromToolInputIn value: JSONValue) -> String? {
        guard let inputText = toolInputString(in: value),
              inputText.contains("*** Begin Patch"),
              inputText.contains("*** End Patch")
        else {
            return nil
        }
        return inputText
    }

    private static func commandText(fromToolInputIn value: JSONValue) -> String? {
        guard let inputText = toolInputString(in: value) else {
            return nil
        }

        if let decoded = jsonObjectStringValue(inputText, key: "cmd") {
            return decoded
        }

        guard inputText.range(of: #"\bscp\b"#, options: [.regularExpression, .caseInsensitive]) != nil else {
            return nil
        }
        return inputText
    }

    private static func toolInputString(in value: JSONValue) -> String? {
        value["input"]?.stringValue
            ?? value["arguments"]?.stringValue
            ?? value["args"]?.stringValue
            ?? value["params"]?.stringValue
    }

    private static func jsonObjectStringValue(_ text: String, key: String) -> String? {
        guard let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let object) = decoded
        else {
            return nil
        }
        return object[key]?.stringValue
    }

    private static func normalizedFileArtifactPath(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.count <= 1_024,
              !value.contains("\n"),
              !value.contains("\r")
        else {
            return nil
        }

        if value.hasPrefix("file://"),
           let url = URL(string: value),
           url.isFileURL {
            value = url.path
        }

        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "`\"'.,;:)]}"))
        let extensionText = pathExtension(forPath: value)
        let hasPlausibleExtension = !extensionText.isEmpty && isPlausiblePathExtension(extensionText)
        let isKnownExtensionless = isKnownExtensionlessArtifactPath(value)
        guard !isLikelyImagePath(value),
              !value.lowercased().hasPrefix("http://"),
              !value.lowercased().hasPrefix("https://"),
              (hasPathSeparator(value) || isPlainRelativeArtifactPath(value)),
              hasPlausibleExtension || isKnownExtensionless
        else {
            return nil
        }
        return value
    }

    private static func diffAttachment(
        in output: String?,
        threadRef: ThreadRef,
        createdAt: Date,
        idPrefix: String
    ) -> ThreadMessageAttachment? {
        guard let output,
              let diff = unifiedDiffText(in: output)
        else {
            return nil
        }

        let maxCharacters = 180_000
        let diffText: String
        let status: String
        if diff.count > maxCharacters {
            diffText = String(diff.prefix(maxCharacters)) + "\n\n... diff truncated for preview ..."
            status = "truncated"
        } else {
            diffText = diff
            status = "completed"
        }

        let title = diffTitle(in: diffText) ?? "Code diff"
        let sourcePath = diffSourcePath(in: diffText)
        return ThreadMessageAttachment(
            id: "\(idPrefix)-diff-\(sanitizeID(title))",
            kind: .diff,
            sourceHostID: threadRef.hostID,
            sourcePath: sourcePath,
            mimeType: "text/x-diff",
            title: title,
            status: status,
            createdAt: createdAt,
            changeType: diffChangeType(in: diffText),
            diffText: diffText,
            language: "diff"
        )
    }

    private static func unifiedDiffText(in text: String) -> String? {
        if let range = text.range(of: "diff --git") {
            return String(text[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if text.contains("\n--- "),
           text.contains("\n+++ "),
           text.contains("\n@@") {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let range = text.range(of: "*** Begin Patch") {
            let patch = String(text[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard patch.contains("*** End Patch") else {
                return nil
            }
            guard patch.contains("*** Add File:")
                    || patch.contains("*** Update File:")
                    || patch.contains("*** Delete File:")
            else {
                return nil
            }
            return patch
        }

        return nil
    }

    private static func diffTitle(in diff: String) -> String? {
        if let path = firstMatch(in: diff, pattern: #"(?m)^\*\*\* (?:Add|Update|Delete) File:\s*(.+)$"#) {
            return fileName(forPath: path)
        }
        if let path = firstMatch(in: diff, pattern: #"(?m)^\+\+\+ [ab]/(.+)$"#) {
            return fileName(forPath: path)
        }
        if let path = firstMatch(in: diff, pattern: #"(?m)^diff --git a/(.+?) b/"#) {
            return fileName(forPath: path)
        }
        return nil
    }

    private static func diffSourcePath(in diff: String) -> String? {
        firstMatch(in: diff, pattern: #"(?m)^\*\*\* (?:Add|Update|Delete) File:\s*(.+)$"#)
            ?? firstMatch(in: diff, pattern: #"(?m)^\+\+\+ [ab]/(.+)$"#)
            ?? firstMatch(in: diff, pattern: #"(?m)^diff --git a/(.+?) b/"#)
    }

    private static func diffChangeType(in diff: String) -> ThreadMessageAttachmentChangeType {
        let lowercased = diff.lowercased()
        if lowercased.contains("*** add file:") || lowercased.contains("new file mode") || lowercased.contains("--- /dev/null") {
            return .added
        }
        if lowercased.contains("*** delete file:") || lowercased.contains("deleted file mode") || lowercased.contains("+++ /dev/null") {
            return .deleted
        }
        if lowercased.contains("rename from") || lowercased.contains("rename to") {
            return .renamed
        }
        return .modified
    }

    private static func changeType(
        in object: [String: JSONValue],
        key: String,
        fallback: ThreadMessageAttachmentChangeType
    ) -> ThreadMessageAttachmentChangeType {
        let evidence = [
            object["changeType"]?.stringValue,
            object["change_type"]?.stringValue,
            object["action"]?.stringValue,
            object["operation"]?.stringValue,
            key,
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        let changeType = changeType(fromEvidenceText: evidence)
        return changeType == .unknown ? fallback : changeType
    }

    private static func changeType(fromEvidenceText text: String) -> ThreadMessageAttachmentChangeType {
        if text.contains("add") || text.contains("create") || text.contains("new") {
            return .added
        }
        if text.contains("delete") || text.contains("remove") {
            return .deleted
        }
        if text.contains("rename") || text.contains("move") {
            return .renamed
        }
        if text.contains("update") || text.contains("modify") || text.contains("write") || text.contains("save") {
            return .modified
        }
        return .unknown
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func deduplicatedAttachments(_ attachments: [ThreadMessageAttachment]) -> [ThreadMessageAttachment] {
        var seen = Set<String>()
        return attachments.filter { attachment in
            let key = [
                attachment.kind.rawValue,
                attachment.sourcePath ?? "",
                attachment.diffText.map { String($0.prefix(120)) } ?? "",
                attachment.id,
            ].joined(separator: "|")
            guard seen.insert(key).inserted else {
                return false
            }
            return true
        }
    }

    private static func attachmentSemanticKey(_ attachment: ThreadMessageAttachment) -> String {
        [
            attachment.kind.rawValue,
            attachment.sourceHostID.rawValue,
            attachment.sourcePath ?? "",
            attachment.diffText.map { String($0.prefix(200)) } ?? "",
        ].joined(separator: "|")
    }

    private static func imageAttachment(
        id: String,
        sourceHostID: HostID,
        sourcePath: String?,
        title: String?,
        status: String? = nil,
        revisedPrompt: String? = nil,
        createdAt: Date? = nil
    ) -> ThreadMessageAttachment? {
        guard let sourcePath = normalizedImagePath(sourcePath) else {
            return nil
        }
        return ThreadMessageAttachment(
            id: "\(id)-image",
            kind: .image,
            sourceHostID: sourceHostID,
            sourcePath: sourcePath,
            mimeType: mimeType(forPath: sourcePath),
            title: title,
            status: status,
            revisedPrompt: revisedPrompt,
            createdAt: createdAt
        )
    }

    private static func normalizedImagePath(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        if value.hasPrefix("file://"),
           let url = URL(string: value),
           url.isFileURL {
            value = url.path
        }

        let lowercased = value.lowercased()
        guard !lowercased.hasPrefix("http://"),
              !lowercased.hasPrefix("https://"),
              isLikelyImagePath(value) else {
            return nil
        }
        return value
    }

    private static func isLikelyImagePath(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return lowercased.hasSuffix(".png")
            || lowercased.hasSuffix(".jpg")
            || lowercased.hasSuffix(".jpeg")
            || lowercased.hasSuffix(".webp")
            || lowercased.hasSuffix(".gif")
            || lowercased.hasSuffix(".heic")
    }

    private static func mimeType(forPath path: String) -> String? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        case "heic":
            return "image/heic"
        default:
            return nil
        }
    }

    private static func hasPathSeparator(_ path: String) -> Bool {
        path.contains("/") || path.contains("\\")
    }

    private static func fileName(forPath path: String) -> String {
        path
            .split(whereSeparator: { $0 == "/" || $0 == "\\" })
            .last
            .map(String.init) ?? path
    }

    private static func pathExtension(forPath path: String) -> String {
        let name = fileName(forPath: path)
        guard let dotIndex = name.lastIndex(of: "."),
              dotIndex < name.index(before: name.endIndex)
        else {
            return ""
        }
        return String(name[name.index(after: dotIndex)...]).lowercased()
    }

    private static func isPlausiblePathExtension(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 16 else {
            return false
        }

        return value.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber)
        }
    }

    private static func isPlainRelativeArtifactPath(_ value: String) -> Bool {
        !value.contains(" ")
            && !value.contains("\t")
            && !value.contains(":")
            && !value.contains("\\")
            && !value.contains("/")
    }

    private static func isKnownExtensionlessArtifactPath(_ path: String) -> Bool {
        let name = fileName(forPath: path).lowercased()
        return [
            "makefile",
            "dockerfile",
            "containerfile",
            "license",
            "readme",
            "gemfile",
            "rakefile",
            "procfile",
        ].contains(name)
    }

    private static func sanitizeID(_ value: String) -> String {
        let sanitized = value.map { character in
            if character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_") {
                return character
            }
            return "_"
        }
        let result = String(sanitized)
        return result.isEmpty ? "artifact" : result
    }

    private static func toolMessageText(name: String, arguments: String?, output: String?) -> String {
        var sections = [name]
        if let arguments, !arguments.isEmpty {
            sections.append("Input:\n\(arguments)")
        }
        if let output, !output.isEmpty {
            sections.append("Output:\n\(output)")
        }
        return sections.joined(separator: "\n\n")
    }

    private static func appendToolOutput(_ output: String, to text: String) -> String {
        if text.contains("\n\nOutput:\n") {
            return text.hasSuffix("\n") ? text + output : text + "\n" + output
        }
        return text + "\n\nOutput:\n" + output
    }

    private static func isGenericToolItem(_ type: String) -> Bool {
        let lowercased = type.lowercased()
        return lowercased.contains("tool")
            || lowercased.contains("function")
            || lowercased.contains("web_search")
            || lowercased.contains("image_generation")
            || lowercased.contains("execution")
            || lowercased.contains("filechange")
            || lowercased.contains("file_change")
    }

    private static func displayName(forToolType type: String) -> String {
        type
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "Call", with: " call")
            .replacingOccurrences(of: "Output", with: " output")
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
