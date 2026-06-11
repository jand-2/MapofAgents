import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func codexAutomationStoreLoadsHeartbeatAutomationsByThreadID() throws {
    let root = try temporaryCodexHome()
    try writeAutomation(
        root: root,
        id: "example-heartbeat",
        body: """
        version = 1
        id = "example-heartbeat"
        kind = "heartbeat"
        name = "Example heartbeat"
        prompt = "Keep this thread moving."
        status = "ACTIVE"
        rrule = "FREQ=MINUTELY;INTERVAL=30"
        target_thread_id = "thread-123"
        created_at = "2026-06-11T09:00:00Z"
        updated_at = "2026-06-11T09:10:00Z"
        """
    )

    let store = CodexAutomationStore(codexHome: root)
    let automations = try store.loadAutomationsByThreadID()
    let automation = try #require(automations["thread-123"])

    #expect(automation.id == "example-heartbeat")
    #expect(automation.isHeartbeat)
    #expect(automation.isActive)
    #expect(automation.runsInDisplayName == "Chat")
    #expect(automation.intervalDisplayName == "Every 30 minutes")
}

@Test
func codexAutomationScheduleComputesNextMinutelyRunFromAnchor() throws {
    let root = try temporaryCodexHome()
    try writeAutomation(
        root: root,
        id: "example-heartbeat",
        body: """
        version = 1
        id = "example-heartbeat"
        kind = "heartbeat"
        name = "Example heartbeat"
        prompt = "Keep this thread moving."
        status = "ACTIVE"
        rrule = "FREQ=MINUTELY;INTERVAL=30"
        target_thread_id = "thread-123"
        created_at = "2026-06-11T09:00:00Z"
        """
    )

    let automation = try #require(CodexAutomationStore(codexHome: root).loadAutomations().first)
    let reference = try #require(ISO8601DateFormatter().date(from: "2026-06-11T10:10:00Z"))
    let expected = try #require(ISO8601DateFormatter().date(from: "2026-06-11T10:30:00Z"))

    #expect(automation.nextRun(after: reference, calendar: utcCalendar) == expected)
}

@Test
func codexAutomationScheduleAcceptsPrefixedRRule() {
    let schedule = CodexAutomationSchedule(rrule: "RRULE:FREQ=WEEKLY;BYHOUR=10;BYMINUTE=30;BYDAY=TH")
    #expect(schedule.displayName == "Weekly")
}

@Test
func codexAutomationStoreSavesEditableFieldsWithoutDroppingIdentity() throws {
    let root = try temporaryCodexHome()
    try writeAutomation(
        root: root,
        id: "example-heartbeat",
        body: """
        version = 1
        id = "example-heartbeat"
        kind = "heartbeat"
        name = "Example heartbeat"
        prompt = "Keep this thread moving."
        status = "ACTIVE"
        rrule = "FREQ=MINUTELY;INTERVAL=30"
        target_thread_id = "thread-123"
        created_at = "2026-06-11T09:00:00Z"
        updated_at = "2026-06-11T09:10:00Z"
        """
    )

    let store = CodexAutomationStore(codexHome: root)
    let saved = try store.save(CodexAutomationEdit(
        id: "example-heartbeat",
        name: "Updated heartbeat",
        prompt: "Line one\nLine two",
        status: "paused",
        rrule: "FREQ=HOURLY;INTERVAL=2"
    ))

    #expect(saved.id == "example-heartbeat")
    #expect(saved.kind == "heartbeat")
    #expect(saved.name == "Updated heartbeat")
    #expect(saved.prompt == "Line one\nLine two")
    #expect(saved.status == "PAUSED")
    #expect(saved.rrule == "FREQ=HOURLY;INTERVAL=2")
    #expect(saved.targetThreadID == "thread-123")
    #expect(saved.nextRun(after: Date(), calendar: utcCalendar) == nil)
}

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private func temporaryCodexHome() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-automation-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func writeAutomation(root: URL, id: String, body: String) throws {
    let directory = root
        .appendingPathComponent("automations", isDirectory: true)
        .appendingPathComponent(id, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("automation.toml", isDirectory: false)
    try body.write(to: file, atomically: true, encoding: .utf8)
}
