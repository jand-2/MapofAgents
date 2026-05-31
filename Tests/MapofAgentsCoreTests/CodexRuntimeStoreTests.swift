import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func codexRuntimeStoreParsesSubagentChildSessionMeta() {
    let parentID = "019e6d32-4207-7082-8567-62aea77ebede"
    let childID = "019e6d46-46e1-70b0-8fa7-3735711a819d"
    let line = """
    {"type":"session_meta","payload":{"id":"\(childID)","cwd":"/Users/example/testdocs","thread_source":"subagent","agent_nickname":"Hubble","agent_role":"worker","source":{"subagent":{"thread_spawn":{"parent_thread_id":"\(parentID)","depth":1,"agent_nickname":"Hubble","agent_role":"worker"}}}}}
    """

    let threadRef = CodexRuntimeStore.subagentChildThreadRef(
        fromSessionMetaLine: line,
        parentThreadID: parentID,
        hostID: HostID(rawValue: "local")
    )

    #expect(threadRef?.threadID == childID)
    #expect(threadRef?.hostID == HostID(rawValue: "local"))
    #expect(threadRef?.cwd == "/Users/example/testdocs")
    #expect(threadRef?.name == "Hubble")
}

@Test
func codexRuntimeStoreIgnoresSubagentSessionMetaForOtherParent() {
    let line = """
    {"type":"session_meta","payload":{"id":"019e6d46-46e1-70b0-8fa7-3735711a819d","cwd":"/tmp","thread_source":"subagent","source":{"subagent":{"thread_spawn":{"parent_thread_id":"019e6d32-4207-7082-8567-62aea77ebede","depth":1}}}}}
    """

    let threadRef = CodexRuntimeStore.subagentChildThreadRef(
        fromSessionMetaLine: line,
        parentThreadID: "019e6d32-ffff-7082-8567-62aea77ebede",
        hostID: HostID(rawValue: "local")
    )

    #expect(threadRef == nil)
}

@Test
func codexRuntimeStoreFindsInterruptibleRunningTurnID() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let result: JSONValue = .object([
        "data": .array([
            .object([
                "id": .string("turn-complete"),
                "status": .string("completed"),
            ]),
            .object([
                "id": .string("turn-running"),
                "status": .string("in_progress"),
            ]),
        ]),
    ])

    #expect(CodexRuntimeStore.interruptibleTurnID(fromTurnsListResult: result, threadRef: threadRef) == "turn-running")
}

@Test
func codexRuntimeStoreIgnoresSyntheticTranscriptTurnIDForInterrupt() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let result: JSONValue = .object([
        "data": .array([
            .object([
                "id": .string("\(threadRef.qualifiedID)-turn-1"),
                "status": .string("running"),
            ]),
        ]),
    ])

    #expect(CodexRuntimeStore.interruptibleTurnID(fromTurnsListResult: result, threadRef: threadRef) == nil)
}
