import MapofAgentsCore
import Testing
@testable import MapofAgentsUI

@MainActor
@Test
func transcriptMergeDeduplicatesVersionedWorkflowPayloadAgainstLocalMessage() {
    let visibleText = "Ask the planner to review this."
    let payload = WorkflowPromptEnvelope.encode(
        userText: visibleText,
        workflowContext: workflowMergeContext
    )

    let merged = TranscriptSessionStore.merging(
        transcript(messages: [
            ThreadMessage(id: "local-1", role: .user, text: visibleText),
        ]),
        with: transcript(messages: [
            ThreadMessage(id: "server-1", role: .user, text: payload),
        ])
    )

    #expect(merged.messages.map(\.id) == ["server-1"])
}

@MainActor
@Test
func transcriptMergeDeduplicatesLegacyWorkflowPayloadAgainstLocalMessage() {
    let visibleText = "Ask the planner to review this."
    let payload = "\(visibleText)\n\n\(workflowMergeContext)"

    let merged = TranscriptSessionStore.merging(
        transcript(messages: [
            ThreadMessage(id: "local-1", role: .user, text: visibleText),
        ]),
        with: transcript(messages: [
            ThreadMessage(id: "server-1", role: .user, text: payload),
        ])
    )

    #expect(merged.messages.map(\.id) == ["server-1"])
}

@MainActor
@Test
func transcriptMergeDoesNotDeduplicateUserAuthoredWorkflowHeadings() {
    let localText = "Please preserve this message."
    let serverText = """
    \(localText)

    Workflow chat references:
    - This heading and list are user-authored.
    """

    let merged = TranscriptSessionStore.merging(
        transcript(messages: [
            ThreadMessage(id: "local-1", role: .user, text: localText),
        ]),
        with: transcript(messages: [
            ThreadMessage(id: "server-1", role: .user, text: serverText),
        ])
    )

    #expect(merged.messages.count == 2)
    #expect(Set(merged.messages.map(\.id)) == Set(["local-1", "server-1"]))
}

@MainActor
@Test
func transcriptMergeDeduplicatesEscapedCopiedPayloadWithoutHidingIt() {
    let copiedPayload = WorkflowPromptEnvelope.encode(
        userText: "This generated payload is now the user's quoted example.",
        workflowContext: workflowMergeContext
    )
    let escapedServerText = WorkflowPromptEnvelope.escapingReservedEnvelope(in: copiedPayload)
    let routedServerText = WorkflowPromptEnvelope.encode(
        userText: escapedServerText,
        workflowContext: workflowMergeContext
    )

    let merged = TranscriptSessionStore.merging(
        transcript(messages: [
            ThreadMessage(id: "local-1", role: .user, text: escapedServerText),
        ]),
        with: transcript(messages: [
            ThreadMessage(id: "server-1", role: .user, text: routedServerText),
        ])
    )

    #expect(merged.messages.map(\.id) == ["server-1"])
    #expect(
        WorkflowPromptEnvelope.presentation(for: merged.messages[0].text).visibleText
            == copiedPayload
    )
}

private func transcript(messages: [ThreadMessage]) -> ThreadTranscript {
    ThreadTranscript(
        threadRef: ThreadRef(
            hostID: HostID(rawValue: "example-host"),
            threadID: "example-thread",
            cwd: "/Users/example/project"
        ),
        messages: messages
    )
}

private let workflowMergeContext = """
Workflow chat references:
- title="Planner"; provider="codex"

Workflow folder references:
- none

Workflow route map:
- hostID="example-host"; route=same-host Codex App Server

Provider relay usage:
- When a route is `mapofagents provider relay`, send only the intended target message.
- Treat `success=true` as delivered.

You are running as provider="codex"; hostID="example-host"; threadID="example-thread". Only use these references because the user inserted explicit workflow mention tokens.
"""
