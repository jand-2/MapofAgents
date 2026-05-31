import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func threadTranscriptPrependsOlderPageAndKeepsNextCursor() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let current = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(id: "m2", role: .assistant, text: "two", createdAt: Date(timeIntervalSince1970: 20)),
            ThreadMessage(id: "m3", role: .assistant, text: "three", createdAt: Date(timeIntervalSince1970: 30)),
        ],
        nextCursor: "older-2"
    )
    let older = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(id: "m1", role: .assistant, text: "one", createdAt: Date(timeIntervalSince1970: 10)),
            ThreadMessage(id: "m2", role: .assistant, text: "two duplicate", createdAt: Date(timeIntervalSince1970: 20)),
        ],
        nextCursor: "older-3"
    )

    let merged = current.prependingOlderPage(older)

    #expect(merged.messages.map(\.id) == ["m1", "m2", "m3"])
    #expect(merged.nextCursor == "older-3")
}

@Test
func threadTranscriptSortsPagedDescendingResultsChronologically() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let transcript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(id: "new", role: .assistant, text: "new", createdAt: Date(timeIntervalSince1970: 30)),
            ThreadMessage(id: "old", role: .assistant, text: "old", createdAt: Date(timeIntervalSince1970: 10)),
        ],
        nextCursor: "older"
    )

    let sorted = transcript.sortedChronologically()

    #expect(sorted.messages.map(\.id) == ["old", "new"])
    #expect(sorted.nextCursor == "older")
}

@Test
func threadTranscriptPrependsOlderPageWhenOnlyOlderPageHasTimeline() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let olderMessages = [
        ThreadMessage(id: "m1", role: .user, text: "one", createdAt: Date(timeIntervalSince1970: 10)),
    ]
    let current = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(id: "m2", role: .assistant, text: "two", createdAt: Date(timeIntervalSince1970: 20)),
        ]
    )
    let older = ThreadTranscript(
        threadRef: threadRef,
        messages: olderMessages,
        nextCursor: "older-2",
        turnTimeline: ThreadTurnTimeline.fromTranscript(ThreadTranscript(threadRef: threadRef, messages: olderMessages))
    )

    let merged = current.prependingOlderPage(older)

    #expect(merged.messages.map(\.id) == ["m1", "m2"])
    #expect(merged.turnTimeline?.turns.flatMap { $0.items.map(\.id) } == ["m1", "m2"])
}

@Test
func threadTranscriptPrependsOlderPageWhenOnlyCurrentPageHasTimeline() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let currentMessages = [
        ThreadMessage(id: "m2", role: .assistant, text: "two", createdAt: Date(timeIntervalSince1970: 20)),
    ]
    let current = ThreadTranscript(
        threadRef: threadRef,
        messages: currentMessages,
        turnTimeline: ThreadTurnTimeline.fromTranscript(ThreadTranscript(threadRef: threadRef, messages: currentMessages))
    )
    let older = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(id: "m1", role: .user, text: "one", createdAt: Date(timeIntervalSince1970: 10)),
        ],
        nextCursor: "older-2"
    )

    let merged = current.prependingOlderPage(older)

    #expect(merged.messages.map(\.id) == ["m1", "m2"])
    #expect(merged.turnTimeline?.turns.flatMap { $0.items.map(\.id) } == ["m1", "m2"])
}

@Test
func threadTranscriptPrimaryArtifactsPreferTurnTimelineItems() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let legacyAttachment = ThreadMessageAttachment(
        id: "legacy-file",
        kind: .file,
        sourceHostID: threadRef.hostID,
        sourcePath: "/tmp/legacy.txt",
        title: "legacy.txt"
    )
    let duplicateLegacyAttachment = ThreadMessageAttachment(
        id: "legacy-image-copy",
        kind: .image,
        sourceHostID: threadRef.hostID,
        sourcePath: "/tmp/.codex/generated_images/thread-1/output.png",
        title: "output.png"
    )
    let timelineAttachment = ThreadMessageAttachment(
        id: "timeline-image",
        kind: .image,
        sourceHostID: threadRef.hostID,
        sourcePath: "/tmp/.codex/generated_images/thread-1/output.png",
        title: "output.png"
    )
    let transcript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(
                id: "assistant-1",
                role: .assistant,
                text: "legacy",
                createdAt: Date(timeIntervalSince1970: 10),
                attachments: [legacyAttachment, duplicateLegacyAttachment]
            ),
        ],
        turnTimeline: ThreadTurnTimeline(
            threadRef: threadRef,
            turns: [
                ThreadTurn(
                    id: "turn-1",
                    status: .complete,
                    startedAt: Date(timeIntervalSince1970: 10),
                    completedAt: Date(timeIntervalSince1970: 11),
                    items: [
                        ThreadTurnItem(
                            id: "artifact-1",
                            kind: .imageArtifact,
                            message: ThreadMessage(id: "artifact-1", role: .assistant, text: "Generated image", createdAt: Date(timeIntervalSince1970: 11)),
                            attachments: [timelineAttachment]
                        ),
                    ]
                ),
            ]
        )
    )

    let attachments = transcript.primaryArtifactAttachments

    #expect(attachments.map(\.id) == ["timeline-image", "legacy-file"])
    #expect(attachments.first?.kind == .image)
}

@Test
func threadTranscriptPrimaryArtifactsFallBackToLegacyMessageAttachments() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let attachment = ThreadMessageAttachment(
        id: "legacy-file",
        kind: .file,
        sourceHostID: threadRef.hostID,
        sourcePath: "/tmp/legacy.txt",
        title: "legacy.txt"
    )
    let transcript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(id: "assistant-1", role: .assistant, text: "legacy", createdAt: Date(timeIntervalSince1970: 10), attachments: [attachment]),
        ]
    )

    #expect(transcript.primaryArtifactAttachments.map(\.id) == ["legacy-file"])
}

@Test
func transcriptParserDiscoversThreadIDsInMessages() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "019e4c62-90e7-7db1-bafc-d996faee690e", cwd: "/tmp")
    let transcript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(
                role: .assistant,
                text: "Created session 019e4c6a-9fe3-7383-82e5-4aca4c1888f4 and ignored the current 019e4c62-90e7-7db1-bafc-d996faee690e."
            ),
        ]
    )

    #expect(ThreadTranscriptParser.discoveredThreadIDs(in: transcript) == ["019e4c6a-9fe3-7383-82e5-4aca4c1888f4"])
}

@Test
func transcriptParserKeepsAppServerCommandExecutionTools() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let result: JSONValue = .object([
        "data": .array([
            .object([
                "items": .array([
                    .object([
                        "type": .string("commandExecution"),
                        "id": .string("tool-1"),
                        "command": .string("date"),
                        "aggregatedOutput": .string("Thu May 21 12:31:46 PDT 2026"),
                    ]),
                ]),
            ]),
        ]),
    ])

    let transcript = ThreadTranscriptParser.transcript(from: result, threadRef: threadRef)

    #expect(transcript.messages.count == 1)
    #expect(transcript.messages[0].id == "tool-1")
    #expect(transcript.messages[0].role == .tool)
    #expect(transcript.messages[0].text.contains("date"))
    #expect(transcript.messages[0].text.contains("Output:"))
}

@Test
func transcriptParserUsesAppServerMessageTimestamps() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let result: JSONValue = .object([
        "data": .array([
            .object([
                "timestamp": .number(1_700_000_000),
                "items": .array([
                    .object([
                        "type": .string("agentMessage"),
                        "id": .string("message-1"),
                        "createdAt": .number(1_800_000_000),
                        "text": .string("hello"),
                    ]),
                ]),
            ]),
        ]),
    ])

    let transcript = ThreadTranscriptParser.transcript(from: result, threadRef: threadRef)

    #expect(transcript.messages[0].createdAt == Date(timeIntervalSince1970: 1_800_000_000))
}

@Test
func transcriptParserSortsAppServerTurnTimelineChronologically() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let result: JSONValue = .object([
        "data": .array([
            .object([
                "id": .string("turn-new"),
                "startedAt": .number(30),
                "items": .array([
                    .object([
                        "type": .string("agentMessage"),
                        "id": .string("new"),
                        "createdAt": .number(30),
                        "text": .string("new"),
                    ]),
                ]),
            ]),
            .object([
                "id": .string("turn-old"),
                "startedAt": .number(10),
                "items": .array([
                    .object([
                        "type": .string("agentMessage"),
                        "id": .string("old"),
                        "createdAt": .number(10),
                        "text": .string("old"),
                    ]),
                ]),
            ]),
        ]),
        "nextCursor": .string("older"),
    ])

    let transcript = ThreadTranscriptParser.transcript(from: result, threadRef: threadRef)

    #expect(transcript.messages.map(\.id) == ["old", "new"])
    #expect(transcript.turnTimeline?.turns.map(\.id) == ["turn-old", "turn-new"])
    #expect(transcript.turnTimeline?.turns.flatMap { $0.items.map(\.id) } == ["old", "new"])
}

@Test
func appServerTurnTimelineKeepsUserPromptBeforeToolRowsWhenUserTimestampFallsBack() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let result: JSONValue = .object([
        "data": .array([
            .object([
                "id": .string("turn-1"),
                "startedAt": .number(20),
                "completedAt": .number(30),
                "items": .array([
                    .object([
                        "type": .string("commandExecution"),
                        "id": .string("tool-1"),
                        "createdAt": .number(21),
                        "command": .string("date"),
                        "aggregatedOutput": .string("Wed May 27"),
                    ]),
                    .object([
                        "type": .string("userMessage"),
                        "id": .string("user-1"),
                        "content": .array([
                            .object([
                                "type": .string("input_text"),
                                "text": .string("what is the date"),
                            ]),
                        ]),
                    ]),
                    .object([
                        "type": .string("agentMessage"),
                        "id": .string("answer-1"),
                        "createdAt": .number(30),
                        "text": .string("Wednesday"),
                    ]),
                ]),
            ]),
        ]),
    ])

    let transcript = ThreadTranscriptParser.transcript(from: result, threadRef: threadRef)

    #expect(transcript.messages.map(\.id) == ["tool-1", "user-1", "answer-1"])
    #expect(transcript.turnTimeline?.turns.first?.items.map(\.id) == ["user-1", "tool-1", "answer-1"])
    #expect(transcript.turnTimeline?.turns.first?.startedAt == Date(timeIntervalSince1970: 20))
    #expect(transcript.turnTimeline?.turns.first?.completedAt == Date(timeIntervalSince1970: 30))
}

@Test
func transcriptParserDoesNotAttachEmptyAppServerItemIDToEveryMessage() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let result: JSONValue = .object([
        "data": .array([
            .object([
                "id": .string("turn-1"),
                "startedAt": .number(10),
                "items": .array([
                    .object([
                        "type": .string("agentMessage"),
                        "id": .string(""),
                        "createdAt": .number(10),
                        "text": .string("first"),
                    ]),
                ]),
            ]),
            .object([
                "id": .string("turn-2"),
                "startedAt": .number(11),
                "items": .array([
                    .object([
                        "type": .string("agentMessage"),
                        "id": .string("message-2"),
                        "createdAt": .number(11),
                        "text": .string("second"),
                    ]),
                ]),
            ]),
        ]),
    ])

    let transcript = ThreadTranscriptParser.transcript(from: result, threadRef: threadRef)

    #expect(transcript.messages.count == 2)
    #expect(transcript.messages.allSatisfy { !$0.id.isEmpty })
    #expect(transcript.turnTimeline?.turns.first?.items.map(\.id).contains("message-2") == false)
    #expect(transcript.turnTimeline?.turns.flatMap { $0.items.map(\.id) }.filter { $0 == "message-2" }.count == 1)
}

@Test
func transcriptParserKeepsObjectShapedAppServerReasoningSummaries() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let result: JSONValue = .object([
        "data": .array([
            .object([
                "items": .array([
                    .object([
                        "type": .string("reasoning"),
                        "id": .string("reasoning-1"),
                        "summary": .array([
                            .object(["summary_text": .string("Checked the inputs.")]),
                            .object(["text": .string("Chose the direct path.")]),
                        ]),
                    ]),
                ]),
            ]),
        ]),
    ])

    let transcript = ThreadTranscriptParser.transcript(from: result, threadRef: threadRef)

    #expect(transcript.messages.map(\.role) == [.reasoning])
    #expect(transcript.messages.first?.text == "Checked the inputs.\nChose the direct path.")
}

@Test
func transcriptParserKeepsRolloutFunctionCallTools() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let events: [JSONValue] = [
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("message"),
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_text"),
                        "text": .string("what time is it"),
                    ]),
                ]),
            ]),
        ]),
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("function_call"),
                "name": .string("exec_command"),
                "arguments": .string("{\"cmd\":\"date\"}"),
                "call_id": .string("call-date"),
            ]),
        ]),
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("function_call_output"),
                "call_id": .string("call-date"),
                "output": .string("Thu May 21 12:31:46 PDT 2026"),
            ]),
        ]),
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("message"),
                "role": .string("assistant"),
                "content": .array([
                    .object([
                        "type": .string("output_text"),
                        "text": .string("Thu May 21 12:31:46 PDT 2026"),
                    ]),
                ]),
            ]),
        ]),
    ]

    let transcript = ThreadTranscriptParser.transcript(fromRolloutEvents: events, threadRef: threadRef)

    #expect(transcript.messages.map(\.role) == [.user, .tool, .assistant])
    #expect(transcript.messages[1].id == "call-date")
    #expect(transcript.messages[1].text.contains("exec_command"))
    #expect(transcript.messages[1].text.contains("\"cmd\" : \"date\""))
    #expect(transcript.messages[1].text.contains("Output:"))
    #expect(transcript.messages[1].text.contains("Thu May 21 12:31:46 PDT 2026"))
}

@Test
func transcriptParserUsesStableIDsForGenericToolItemsWithoutServerIDs() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let events: [JSONValue] = [
        .object([
            "timestamp": .string("2026-05-27T17:42:23.913Z"),
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("message"),
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_text"),
                        "text": .string("what's the weather in seattle"),
                    ]),
                ]),
            ]),
        ]),
        .object([
            "timestamp": .string("2026-05-27T17:42:26.802Z"),
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("web_search_call"),
                "status": .string("completed"),
                "action": .object([
                    "type": .string("search"),
                    "queries": .array([
                        .string("weather: Seattle, WA"),
                    ]),
                ]),
            ]),
        ]),
        .object([
            "timestamp": .string("2026-05-27T17:42:27.507Z"),
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("message"),
                "role": .string("assistant"),
                "content": .array([
                    .object([
                        "type": .string("output_text"),
                        "text": .string("Seattle is sunny."),
                    ]),
                ]),
            ]),
        ]),
    ]

    let firstParse = ThreadTranscriptParser.transcript(fromRolloutEvents: events, threadRef: threadRef)
    let secondParse = ThreadTranscriptParser.transcript(fromRolloutEvents: events, threadRef: threadRef)

    #expect(firstParse.messages.map(\.role) == [.user, .tool, .assistant])
    #expect(firstParse.messages[1].id == secondParse.messages[1].id)
    #expect(firstParse.messages[1].text.contains("web search call"))
}

@Test
func transcriptParserKeepsRepeatedGenericToolIDsUnique() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let toolPayload: JSONValue = .object([
        "type": .string("web_search_call"),
        "status": .string("completed"),
        "action": .object([
            "type": .string("search"),
            "queries": .array([
                .string("weather: Seattle, WA"),
            ]),
        ]),
    ])
    let events: [JSONValue] = [
        .object([
            "timestamp": .string("2026-05-27T17:42:26.802Z"),
            "type": .string("response_item"),
            "payload": toolPayload,
        ]),
        .object([
            "timestamp": .string("2026-05-27T17:43:26.802Z"),
            "type": .string("response_item"),
            "payload": toolPayload,
        ]),
    ]

    let transcript = ThreadTranscriptParser.transcript(fromRolloutEvents: events, threadRef: threadRef)

    #expect(transcript.messages.count == 2)
    #expect(transcript.messages[0].id != transcript.messages[1].id)
}

@Test
func transcriptMergeUsesRolloutTimestampForMatchingToolOrder() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let appServerTranscript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(id: "date-answer", role: .assistant, text: "Today is Wednesday.", createdAt: Date(timeIntervalSince1970: 100)),
            ThreadMessage(id: "call-date", role: .tool, text: "/bin/zsh -lc date", createdAt: Date(timeIntervalSince1970: 101)),
            ThreadMessage(id: "weather-user", role: .user, text: "what's the weather", createdAt: Date(timeIntervalSince1970: 110)),
            ThreadMessage(id: "weather-answer", role: .assistant, text: "Sunny.", createdAt: Date(timeIntervalSince1970: 120)),
        ]
    )
    let rolloutTranscript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(id: "call-date", role: .tool, text: "exec_command", createdAt: Date(timeIntervalSince1970: 115)),
        ]
    )

    let merged = ThreadTranscriptParser.transcriptByAddingImageAttachments(
        from: rolloutTranscript,
        to: appServerTranscript,
        appendMissingMessages: false
    )

    #expect(merged.messages.map(\.id) == ["date-answer", "weather-user", "call-date", "weather-answer"])
    #expect(merged.messages.first { $0.id == "call-date" }?.text == "/bin/zsh -lc date")
}

@Test
func transcriptMergeUsesRolloutTimestampsForMatchingAssistantTextWhenIDsDiffer() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let finalAttachment = ThreadMessageAttachment(
        kind: .file,
        sourceHostID: threadRef.hostID,
        sourcePath: "/tmp/report.pdf",
        title: "report.pdf"
    )
    let appServerTranscript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(id: "app-user", role: .user, text: "finish the report", createdAt: Date(timeIntervalSince1970: 100)),
            ThreadMessage(id: "app-progress", role: .assistant, text: "I am collecting the worker transcripts now.", createdAt: Date(timeIntervalSince1970: 100)),
            ThreadMessage(
                id: "app-final",
                role: .assistant,
                text: "Completed the grading pass and wrote the final PDF.",
                createdAt: Date(timeIntervalSince1970: 100),
                attachments: [finalAttachment]
            ),
        ],
        turnTimeline: ThreadTurnTimeline.fromTranscript(
            ThreadTranscript(
                threadRef: threadRef,
                messages: [
                    ThreadMessage(id: "app-user", role: .user, text: "finish the report", createdAt: Date(timeIntervalSince1970: 100)),
                    ThreadMessage(id: "app-progress", role: .assistant, text: "I am collecting the worker transcripts now.", createdAt: Date(timeIntervalSince1970: 100)),
                    ThreadMessage(
                        id: "app-final",
                        role: .assistant,
                        text: "Completed the grading pass and wrote the final PDF.",
                        createdAt: Date(timeIntervalSince1970: 100),
                        attachments: [finalAttachment]
                    ),
                ]
            )
        )
    )
    let rolloutTranscript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(id: "rollout-user", role: .user, text: "finish the report", createdAt: Date(timeIntervalSince1970: 10)),
            ThreadMessage(id: "rollout-progress", role: .assistant, text: "I am collecting the worker transcripts now.", createdAt: Date(timeIntervalSince1970: 20)),
            ThreadMessage(id: "rollout-final", role: .assistant, text: "Completed the grading pass and wrote the final PDF.", createdAt: Date(timeIntervalSince1970: 30)),
        ]
    )

    let merged = ThreadTranscriptParser.transcriptByAddingImageAttachments(
        from: rolloutTranscript,
        to: appServerTranscript,
        appendMissingMessages: false
    )

    #expect(merged.messages.map(\.id) == ["app-user", "app-progress", "app-final"])
    #expect(merged.messages.first { $0.id == "app-user" }?.createdAt.timeIntervalSince1970 == 10)
    #expect(merged.messages.first { $0.id == "app-progress" }?.createdAt.timeIntervalSince1970 == 20)
    #expect(merged.messages.first { $0.id == "app-final" }?.createdAt.timeIntervalSince1970 == 30)
    #expect(merged.turnTimeline?.turns.flatMap { $0.items.map(\.id) } == ["app-user", "app-progress", "app-final"])
}

@Test
func transcriptMergeKeepsRolloutOnlyToolRowsWhenAppServerIsPrimary() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let appServerTranscript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(id: "user-1", role: .user, text: "what's the date", createdAt: Date(timeIntervalSince1970: 10)),
            ThreadMessage(id: "answer-1", role: .assistant, text: "`Wed May 27 09:52:11 PDT 2026`", createdAt: Date(timeIntervalSince1970: 30)),
        ]
    )
    let rolloutTranscript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(
                id: "call-date",
                role: .tool,
                text: """
                exec_command
                Input:
                {"cmd":"date"}

                Output:
                Wed May 27 09:52:11 PDT 2026
                """,
                createdAt: Date(timeIntervalSince1970: 20)
            ),
        ]
    )

    let merged = ThreadTranscriptParser.transcriptByAddingImageAttachments(
        from: rolloutTranscript,
        to: appServerTranscript,
        appendMissingMessages: false
    )

    #expect(merged.messages.map(\.id) == ["user-1", "call-date", "answer-1"])
    #expect(merged.messages[1].role == .tool)
}

@Test
func transcriptMergeReconcilesTurnTimelineAfterAddingRolloutOnlyToolRows() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let appServerMessages = [
        ThreadMessage(id: "user-1", role: .user, text: "date", createdAt: Date(timeIntervalSince1970: 10)),
        ThreadMessage(id: "answer-1", role: .assistant, text: "Wednesday", createdAt: Date(timeIntervalSince1970: 30)),
    ]
    let appServerTranscript = ThreadTranscript(
        threadRef: threadRef,
        messages: appServerMessages,
        turnTimeline: ThreadTurnTimeline.fromTranscript(ThreadTranscript(threadRef: threadRef, messages: appServerMessages))
    )
    let rolloutTranscript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(id: "call-date", role: .tool, text: "exec_command", createdAt: Date(timeIntervalSince1970: 20)),
        ]
    )

    let merged = ThreadTranscriptParser.transcriptByAddingImageAttachments(
        from: rolloutTranscript,
        to: appServerTranscript,
        appendMissingMessages: false
    )

    #expect(merged.messages.map(\.id) == ["user-1", "call-date", "answer-1"])
    #expect(merged.turnTimeline?.turns.flatMap { $0.items.map(\.id) } == ["user-1", "call-date", "answer-1"])
}

@Test
func transcriptMergeDoesNotAppendRolloutOnlyToolRowsOutsideCurrentPageWindow() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let appServerTranscript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(id: "page-user", role: .user, text: "current page", createdAt: Date(timeIntervalSince1970: 100)),
            ThreadMessage(id: "page-answer", role: .assistant, text: "done", createdAt: Date(timeIntervalSince1970: 120)),
        ]
    )
    let rolloutTranscript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(id: "old-tool", role: .tool, text: "old command", createdAt: Date(timeIntervalSince1970: 10)),
            ThreadMessage(id: "page-tool", role: .tool, text: "page command", createdAt: Date(timeIntervalSince1970: 110)),
        ]
    )

    let merged = ThreadTranscriptParser.transcriptByAddingImageAttachments(
        from: rolloutTranscript,
        to: appServerTranscript,
        appendMissingMessages: false
    )

    #expect(merged.messages.map(\.id) == ["page-user", "page-tool", "page-answer"])
}

@Test
func transcriptParserUsesRolloutEventTimestamps() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let events: [JSONValue] = [
        .object([
            "timestamp": .string("2026-05-21T21:39:31.167Z"),
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("message"),
                "role": .string("assistant"),
                "content": .array([
                    .object([
                        "type": .string("output_text"),
                        "text": .string("hi"),
                    ]),
                ]),
            ]),
        ]),
    ]

    let transcript = ThreadTranscriptParser.transcript(fromRolloutEvents: events, threadRef: threadRef)

    #expect(transcript.messages[0].createdAt.timeIntervalSince1970 == 1_779_399_571.167)
}

@Test
func transcriptParserKeepsAppServerImageGenerationAttachments() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "windows-1"), threadID: "thread-1", cwd: "C:\\Users\\User\\Desktop")
    let result: JSONValue = .object([
        "data": .array([
            .object([
                "items": .array([
                    .object([
                        "type": .string("imageGeneration"),
                        "id": .string("ig-pirate"),
                        "status": .string("completed"),
                        "revisedPrompt": .string("A pirate ship at sunset"),
                        "result": .string("Zm9v"),
                        "savedPath": .string("C:\\Users\\User\\.codex\\generated_images\\thread-1\\ig-pirate.png"),
                    ]),
                ]),
            ]),
        ]),
    ])

    let transcript = ThreadTranscriptParser.transcript(from: result, threadRef: threadRef)

    #expect(transcript.messages.count == 1)
    #expect(transcript.messages[0].id == "ig-pirate")
    #expect(transcript.messages[0].text.contains("Generated image"))
    #expect(transcript.messages[0].text.contains("Status: completed"))
    #expect(transcript.messages[0].attachments.count == 1)
    #expect(transcript.messages[0].attachments[0].kind == .image)
    #expect(transcript.messages[0].attachments[0].sourceHostID == threadRef.hostID)
    #expect(transcript.messages[0].attachments[0].sourcePath == "C:\\Users\\User\\.codex\\generated_images\\thread-1\\ig-pirate.png")
    #expect(transcript.messages[0].attachments[0].mimeType == "image/png")
    #expect(transcript.messages[0].attachments[0].status == "completed")
}

@Test
func transcriptParserMergesAppServerImageAttachmentsIntoRolloutTranscript() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let appServerResult: JSONValue = .object([
        "data": .array([
            .object([
                "items": .array([
                    .object([
                        "type": .string("imageGeneration"),
                        "id": .string("ig-ship"),
                        "status": .string("completed"),
                        "revisedPrompt": .string("A pirate ship"),
                        "result": .string("Zm9v"),
                        "savedPath": .string("/Users/example/.codex/generated_images/thread-1/ig-ship.png"),
                    ]),
                ]),
            ]),
        ]),
    ])
    let rolloutEvents: [JSONValue] = [
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("image_generation_call"),
                "id": .string("ig-ship"),
                "status": .string("completed"),
                "revised_prompt": .string("A pirate ship"),
                "result": .string("Zm9v"),
            ]),
        ]),
    ]

    let appServerTranscript = ThreadTranscriptParser.transcript(from: appServerResult, threadRef: threadRef)
    let rolloutTranscript = ThreadTranscriptParser.transcript(fromRolloutEvents: rolloutEvents, threadRef: threadRef)
    let merged = ThreadTranscriptParser.transcriptByAddingImageAttachments(from: appServerTranscript, to: rolloutTranscript)

    #expect(rolloutTranscript.messages[0].attachments.isEmpty)
    #expect(merged.messages.count == 1)
    #expect(merged.messages[0].id == "ig-ship")
    #expect(merged.messages[0].attachments.isEmpty)
    #expect(merged.primaryArtifactAttachments.count == 1)
    #expect(merged.primaryArtifactAttachments[0].sourcePath == "/Users/example/.codex/generated_images/thread-1/ig-ship.png")
}

@Test
func transcriptParserDoesNotPromotePlainSavedFileOutputToArtifact() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let events: [JSONValue] = [
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("function_call_output"),
                "call_id": .string("call-save"),
                "output": .string("""
                Saved to:
                /tmp/mapofagents/report.md
                """),
            ]),
        ]),
    ]

    let transcript = ThreadTranscriptParser.transcript(fromRolloutEvents: events, threadRef: threadRef)

    #expect(transcript.messages.count == 1)
    #expect(transcript.messages[0].attachments.isEmpty)
}

@Test
func transcriptParserDoesNotPromoteAssistantMarkdownFileLinksToArtifacts() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/Users/example")
    let events: [JSONValue] = [
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("message"),
                "role": .string("assistant"),
                "id": .string("message-pdf"),
                "content": .array([
                    .object([
                        "type": .string("output_text"),
                        "text": .string("""
                        Created the SOP PDF here:

                        [codex_app_sop.pdf](/Users/example/output/pdf/codex_app_sop.pdf)
                        """),
                    ]),
                ]),
            ]),
        ]),
    ]

    let transcript = ThreadTranscriptParser.transcript(fromRolloutEvents: events, threadRef: threadRef)

    #expect(transcript.messages.flatMap(\.attachments).isEmpty)
}

@Test
func transcriptParserPromotesAppServerFileChangeItemsToArtifacts() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp/project")
    let result: JSONValue = .object([
        "data": .array([
            .object([
                "items": .array([
                    .object([
                        "type": .string("fileChange"),
                        "id": .string("file-change-1"),
                        "status": .string("completed"),
                        "changes": .array([
                            .object([
                                "path": .string("Sources/App.swift"),
                                "kind": .string("modify"),
                                "diff": .string("""
                                diff --git a/Sources/App.swift b/Sources/App.swift
                                --- a/Sources/App.swift
                                +++ b/Sources/App.swift
                                @@ -1 +1 @@
                                -let title = "Old"
                                +let title = "New"
                                """),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
        ]),
    ])

    let transcript = ThreadTranscriptParser.transcript(from: result, threadRef: threadRef)
    let attachment = transcript.messages.flatMap(\.attachments).first

    #expect(transcript.messages.count == 1)
    #expect(attachment?.kind == .file)
    #expect(attachment?.sourceHostID == threadRef.hostID)
    #expect(attachment?.sourcePath == "Sources/App.swift")
    #expect(attachment?.changeType == .modified)
    #expect(attachment?.diffText?.contains("+let title") == true)
    #expect(attachment?.isTrustedForAutoHydration == false)
}

@Test
func transcriptParserDoesNotPromoteNestedToolResultFileChangeToArtifact() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp/project")
    let result: JSONValue = .object([
        "data": .array([
            .object([
                "items": .array([
                    .object([
                        "type": .string("mcpToolCall"),
                        "id": .string("mcp-1"),
                        "server": .string("server"),
                        "tool": .string("tool"),
                        "status": .string("completed"),
                        "arguments": .object([:]),
                        "result": .object([
                            "content": .array([
                                .object([
                                    "type": .string("fileChange"),
                                    "changes": .array([
                                        .object([
                                            "path": .string("Sources/App.swift"),
                                            "kind": .string("modify"),
                                        ]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
        ]),
    ])

    let transcript = ThreadTranscriptParser.transcript(from: result, threadRef: threadRef)

    #expect(transcript.messages.flatMap(\.attachments).isEmpty)
}

@Test
func transcriptMergeKeepsRolloutOnlyPatchArtifactsWhenAppServerIsPrimary() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp/project")
    let appServerTranscript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(id: "assistant-1", role: .assistant, text: "Done.", createdAt: Date(timeIntervalSince1970: 10)),
        ]
    )
    let rolloutEvents: [JSONValue] = [
        .object([
            "timestamp": .number(10),
            "type": .string("event_msg"),
            "payload": .object([
                "type": .string("patch_apply_end"),
                "call_id": .string("call-patch"),
                "stdout": .string("""
                Success. Updated the following files:
                M Sources/App.swift
                """),
                "success": .bool(true),
                "changes": .object([
                    "Sources/App.swift": .object([
                        "type": .string("modified"),
                    ]),
                ]),
            ]),
        ]),
    ]
    let rolloutTranscript = ThreadTranscriptParser.transcript(fromRolloutEvents: rolloutEvents, threadRef: threadRef)

    let merged = ThreadTranscriptParser.transcriptByAddingImageAttachments(
        from: rolloutTranscript,
        to: appServerTranscript,
        appendMissingMessages: false
    )

    #expect(merged.messages.count == 2)
    #expect(merged.messages.flatMap(\.attachments).isEmpty)
    #expect(merged.primaryArtifactAttachments.contains { $0.kind == .file && $0.sourcePath == "Sources/App.swift" })
}

@Test
func transcriptParserPromotesApplyPatchResultsToArtifacts() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp/project")
    let events: [JSONValue] = [
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("custom_tool_call"),
                "call_id": .string("call-patch"),
                "name": .string("apply_patch"),
                "input": .string("""
                *** Begin Patch
                *** Add File: hello.txt
                +hello
                *** End Patch
                """),
            ]),
        ]),
        .object([
            "type": .string("event_msg"),
            "payload": .object([
                "type": .string("patch_apply_end"),
                "call_id": .string("call-patch"),
                "stdout": .string("""
                Success. Updated the following files:
                A hello.txt
                """),
                "success": .bool(true),
                "changes": .object([
                    "/tmp/project/hello.txt": .object([
                        "type": .string("add"),
                        "content": .string("hello\n"),
                    ]),
                ]),
            ]),
        ]),
    ]

    let transcript = ThreadTranscriptParser.transcript(fromRolloutEvents: events, threadRef: threadRef)
    let attachments = transcript.messages.flatMap(\.attachments)

    #expect(attachments.contains { $0.kind == .diff && $0.sourcePath == "hello.txt" && $0.changeType == .added })
    #expect(attachments.contains {
        $0.kind == .file
            && $0.sourcePath == "/tmp/project/hello.txt"
            && $0.changeType == .added
            && !$0.isTrustedForAutoHydration
    })
}

@Test
func transcriptParserDoesNotPromoteSuccessfulSCPDestinationToFileArtifact() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp/project")
    let events: [JSONValue] = [
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("function_call"),
                "name": .string("exec_command"),
                "call_id": .string("call-scp"),
                "arguments": .string("""
                {"cmd":"scp hello.txt 'User@100.64.0.12:C:/Users/User/Desktop/hello.txt'","workdir":"/tmp/project"}
                """),
            ]),
        ]),
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("function_call_output"),
                "call_id": .string("call-scp"),
                "output": .string("""
                Chunk ID: be36f7
                Wall time: 0.1650 seconds
                Process exited with code 0
                Original token count: 0
                Output:
                """),
            ]),
        ]),
    ]

    let transcript = ThreadTranscriptParser.transcript(fromRolloutEvents: events, threadRef: threadRef)
    let attachments = transcript.messages.flatMap(\.attachments)

    #expect(attachments.isEmpty)
}

@Test
func transcriptParserSeparatesMultipleToolOutputFragments() throws {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let events: [JSONValue] = [
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("function_call"),
                "name": .string("exec_command"),
                "call_id": .string("call-fragments"),
                "arguments": .string("{\"cmd\":\"printf\"}"),
            ]),
        ]),
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("function_call_output"),
                "call_id": .string("call-fragments"),
                "output": .string("first"),
            ]),
        ]),
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("function_call_output"),
                "call_id": .string("call-fragments"),
                "output": .string("second"),
            ]),
        ]),
    ]

    let transcript = ThreadTranscriptParser.transcript(fromRolloutEvents: events, threadRef: threadRef)
    let toolText = try #require(transcript.messages.first?.text)

    #expect(toolText.contains("Output:\nfirst\nsecond"))
}

@Test
func transcriptParserPromotesUnifiedDiffOutputToDiffArtifact() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let diff = """
    diff --git a/Sources/App.swift b/Sources/App.swift
    index 1111111..2222222 100644
    --- a/Sources/App.swift
    +++ b/Sources/App.swift
    @@ -1,3 +1,4 @@
     import SwiftUI
    -let title = "Old"
    +let title = "New"
    +let subtitle = "Artifact"
    """
    let events: [JSONValue] = [
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("function_call_output"),
                "call_id": .string("call-diff"),
                "output": .string(diff),
            ]),
        ]),
    ]

    let transcript = ThreadTranscriptParser.transcript(fromRolloutEvents: events, threadRef: threadRef)

    #expect(transcript.messages.count == 1)
    #expect(transcript.messages[0].attachments.count == 1)
    let attachment = transcript.messages[0].attachments[0]
    #expect(attachment.kind == .diff)
    #expect(attachment.sourceHostID == threadRef.hostID)
    #expect(attachment.sourcePath == "Sources/App.swift")
    #expect(attachment.title == "App.swift")
    #expect(attachment.changeType == .modified)
    #expect(attachment.diffText?.contains("+let subtitle") == true)
}

@Test
func transcriptParserDoesNotPromoteIncidentalFileLookingProse() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let events: [JSONValue] = [
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("message"),
                "role": .string("assistant"),
                "content": .array([
                    .object([
                        "type": .string("output_text"),
                        "text": .string("We may edit /tmp/mapofagents/Example.swift later, but nothing was created yet."),
                    ]),
                ]),
            ]),
        ]),
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("function_call_output"),
                "call_id": .string("call-note"),
                "output": .string("The docs mention /tmp/mapofagents/Example.swift as an example path."),
            ]),
        ]),
    ]

    let transcript = ThreadTranscriptParser.transcript(fromRolloutEvents: events, threadRef: threadRef)

    #expect(transcript.messages.flatMap(\.attachments).isEmpty)
}

@Test
func transcriptParserDoesNotPromoteIncidentalAssistantMarkdownFileLinks() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let events: [JSONValue] = [
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("message"),
                "role": .string("assistant"),
                "id": .string("message-link"),
                "content": .array([
                    .object([
                        "type": .string("output_text"),
                        "text": .string("You can read more in [README.md](/tmp/project/README.md)."),
                    ]),
                ]),
            ]),
        ]),
    ]

    let transcript = ThreadTranscriptParser.transcript(fromRolloutEvents: events, threadRef: threadRef)

    #expect(transcript.messages.flatMap(\.attachments).isEmpty)
}

@Test
func transcriptParserDoesNotPromoteRelativeOrExtensionlessSavedPaths() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let events: [JSONValue] = [
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("function_call_output"),
                "call_id": .string("call-relative"),
                "output": .string("""
                Saved to: Sources/App.swift
                Saved to: docs/README
                Saved to: Makefile
                """),
            ]),
        ]),
    ]

    let transcript = ThreadTranscriptParser.transcript(fromRolloutEvents: events, threadRef: threadRef)
    let attachments = transcript.messages.flatMap(\.attachments)

    #expect(attachments.isEmpty)
}

@Test
func transcriptParserRejectsSavedPathLinesWithTrailingProse() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let events: [JSONValue] = [
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("function_call_output"),
                "call_id": .string("call-prose"),
                "output": .string("Saved to: /tmp/mapofagents/report.md and updated the tests."),
            ]),
        ]),
    ]

    let transcript = ThreadTranscriptParser.transcript(fromRolloutEvents: events, threadRef: threadRef)

    #expect(transcript.messages.flatMap(\.attachments).isEmpty)
}
