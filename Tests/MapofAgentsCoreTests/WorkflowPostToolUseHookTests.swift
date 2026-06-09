import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func postToolUseHookEmitsFolderCreatedForSuccessfulPeerMkdir() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-post-tool-use-hook-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let eventFile = directory.appendingPathComponent("hook-events.jsonl")
    let repoRoot = try repositoryRoot()
    let hookScript = repoRoot.appendingPathComponent("script/mapofagents-post-tool-use-hook.py")
    let payload = """
    {
      "toolName": "Bash",
      "threadId": "thread-1",
      "turnId": "turn-1",
      "hostId": "local",
      "input": {
        "cmd": "mkdir -p '/Users/example/projects/new-root' && ls -ld '/Users/example/projects/new-root'",
        "cwd": "/Users/example/projects/current"
      },
      "result": {
        "exitCode": 0,
        "output": "drwxr-xr-x 2 example staff 64 Jun 9 11:35 /Users/example/projects/new-root"
      }
    }
    """

    let result = try runHookScript(hookScript, eventFile: eventFile, payload: payload)
    let event = try parsedSingleHookEvent(from: eventFile)

    #expect(result.terminationStatus == 0)
    #expect(event.kind == .folderCreated)
    #expect(event.childFolderPath == "/Users/example/projects/new-root")
    #expect(event.childTitle == "new-root")
    #expect(event.hostID == HostID(rawValue: "local"))
    #expect(event.threadID == "thread-1")

    try? FileManager.default.removeItem(at: directory)
}

@Test
func postToolUseHookUnderstandsCodexPostToolUseSchema() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-post-tool-use-hook-real-schema-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let eventFile = directory.appendingPathComponent("hook-events.jsonl")
    let repoRoot = try repositoryRoot()
    let hookScript = repoRoot.appendingPathComponent("script/mapofagents-post-tool-use-hook.py")
    let payload = """
    {
      "session_id": "thread-1",
      "turn_id": "turn-1",
      "cwd": "/Users/example/projects/current",
      "hook_event_name": "PostToolUse",
      "model": "gpt-5.5",
      "permission_mode": "default",
      "tool_name": "Bash",
      "tool_input": {
        "command": "mkdir -p '/Users/example/projects/new-root' && ls -ld '/Users/example/projects/new-root'"
      },
      "tool_response": "drwxr-xr-x 2 example staff 64 Jun 9 11:35 /Users/example/projects/new-root",
      "tool_use_id": "call-1",
      "transcript_path": null
    }
    """

    let result = try runHookScript(hookScript, eventFile: eventFile, payload: payload)
    let event = try parsedSingleHookEvent(from: eventFile)

    #expect(result.terminationStatus == 0)
    #expect(event.kind == .folderCreated)
    #expect(event.childFolderPath == "/Users/example/projects/new-root")
    #expect(event.childTitle == "new-root")
    #expect(event.threadID == "thread-1")
    #expect(event.turnID == "turn-1")

    try? FileManager.default.removeItem(at: directory)
}

@Test
func postToolUseHookIgnoresDescendantMkdir() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-post-tool-use-hook-descendant-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let eventFile = directory.appendingPathComponent("hook-events.jsonl")
    let repoRoot = try repositoryRoot()
    let hookScript = repoRoot.appendingPathComponent("script/mapofagents-post-tool-use-hook.py")
    let payload = """
    {
      "toolName": "Bash",
      "threadId": "thread-1",
      "turnId": "turn-1",
      "hostId": "local",
      "input": {
        "cmd": "mkdir -p '/Users/example/projects/current/generated'",
        "cwd": "/Users/example/projects/current"
      },
      "result": {
        "exitCode": 0
      }
    }
    """

    let result = try runHookScript(hookScript, eventFile: eventFile, payload: payload)

    #expect(result.terminationStatus == 0)
    #expect(FileManager.default.fileExists(atPath: eventFile.path) == false)

    try? FileManager.default.removeItem(at: directory)
}

@Test
func postToolUseHookIgnoresFailedMkdir() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-post-tool-use-hook-failed-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let eventFile = directory.appendingPathComponent("hook-events.jsonl")
    let repoRoot = try repositoryRoot()
    let hookScript = repoRoot.appendingPathComponent("script/mapofagents-post-tool-use-hook.py")
    let payload = """
    {
      "toolName": "Bash",
      "threadId": "thread-1",
      "turnId": "turn-1",
      "hostId": "local",
      "input": {
        "cmd": "mkdir -p '/Users/example/projects/new-root'",
        "cwd": "/Users/example/projects/current"
      },
      "result": {
        "exitCode": 1
      }
    }
    """

    let result = try runHookScript(hookScript, eventFile: eventFile, payload: payload)

    #expect(result.terminationStatus == 0)
    #expect(FileManager.default.fileExists(atPath: eventFile.path) == false)

    try? FileManager.default.removeItem(at: directory)
}

private struct HookScriptResult {
    var terminationStatus: Int32
    var output: String
}

private func runHookScript(
    _ hookScript: URL,
    eventFile: URL,
    payload: String
) throws -> HookScriptResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [hookScript.path]
    var environment = ProcessInfo.processInfo.environment
    environment["MAPOFAGENTS_HOOK_EVENT_FILE"] = eventFile.path
    process.environment = environment

    let input = Pipe()
    let output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = output

    try process.run()
    input.fileHandleForWriting.write(Data(payload.utf8))
    try input.fileHandleForWriting.close()
    process.waitUntilExit()

    let data = output.fileHandleForReading.readDataToEndOfFile()
    return HookScriptResult(
        terminationStatus: process.terminationStatus,
        output: String(data: data, encoding: .utf8) ?? ""
    )
}

private func parsedSingleHookEvent(from eventFile: URL) throws -> WorkflowEvent {
    let contents = try String(contentsOf: eventFile, encoding: .utf8)
    let lines = contents.split(separator: "\n").map(String.init)
    #expect(lines.count == 1)
    return try #require(
        WorkflowHookEventParser.workflowEvent(
            from: lines[0],
            defaultHostID: HostID(rawValue: "local"),
            receivedAt: Date(timeIntervalSince1970: 1_781_030_100)
        )
    )
}

private func repositoryRoot() throws -> URL {
    var url = URL(fileURLWithPath: #filePath)
    while url.pathComponents.count > 1 {
        let packageURL = url.appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: packageURL.path) {
            return url
        }
        url.deleteLastPathComponent()
    }
    throw CocoaError(.fileNoSuchFile)
}
