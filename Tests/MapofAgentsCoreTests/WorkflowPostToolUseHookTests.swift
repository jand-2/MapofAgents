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

@Test
func workflowEventHookWritesMinimalPrivateNormalizedEventByDefault() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-event-hook-minimal-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let eventFile = directory.appendingPathComponent("hook-events.jsonl")
    let hookScript = try repositoryRoot().appendingPathComponent("script/mapofagents-hook-event.sh")
    let payload = #"{"threadID":"thread-1","turnID":"turn-1","hostID":"local","password":"must-not-persist"}"#
    let result = try runEventHookScript(
        hookScript,
        eventName: "turn-ended",
        eventFile: eventFile,
        payload: payload
    )
    let event = try parsedSingleJSONObject(from: eventFile)
    let attributes = try FileManager.default.attributesOfItem(atPath: eventFile.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)

    #expect(result.terminationStatus == 0)
    #expect(event["source"] as? String == "codex-hook")
    #expect(event["type"] as? String == "turn.completed")
    #expect(event["method"] as? String == "turn/completed")
    #expect(event["hostID"] as? String == "local")
    #expect(event["threadID"] as? String == "thread-1")
    #expect(event["turnID"] as? String == "turn-1")
    #expect(event["raw"] == nil)
    #expect(event["event"] == nil)
    #expect(event["cwd"] == nil)
    #expect(permissions.intValue & 0o777 == 0o600)
}

@Test
func workflowEventHookRedactsDefaultEnvelopeFreeTextAndPaths() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-event-hook-envelope-redaction-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let eventFile = directory.appendingPathComponent("hook-events.jsonl")
    let hookScript = try repositoryRoot().appendingPathComponent("script/mapofagents-hook-event.sh")
    let payload = """
    {
      "sourceThreadID": "source-thread",
      "childThreadID": "child-thread",
      "childCWD": "https://example-user:path-password@example.test/project?token=path-token",
      "childTitle": "password=title-password"
    }
    """
    let result = try runEventHookScript(
        hookScript,
        eventName: "thread.created",
        eventFile: eventFile,
        payload: payload,
        environmentOverrides: [
            "MAPOFAGENTS_HOOK_SUMMARY": "Authorization: Bearer summary-bearer",
        ]
    )
    let contents = try String(contentsOf: eventFile, encoding: .utf8)
    let event = try parsedSingleJSONObject(from: eventFile)

    #expect(result.terminationStatus == 0)
    #expect(event["raw"] == nil)
    #expect(contents.contains("summary-bearer") == false)
    #expect(contents.contains("path-password") == false)
    #expect(contents.contains("path-token") == false)
    #expect(contents.contains("title-password") == false)
    #expect(contents.contains("[REDACTED]"))
}

@Test
func workflowEventHookRawCaptureIsExplicitRedactedAndBounded() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-event-hook-raw-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let eventFile = directory.appendingPathComponent("hook-events.jsonl")
    let hookScript = try repositoryRoot().appendingPathComponent("script/mapofagents-hook-event.sh")
    let payload = """
    {
      "threadID": "thread-1",
      "password": "hook-password-value",
      "command": "curl -H 'Authorization: Bearer hook-bearer-value'",
      "output": "\(String(repeating: "x", count: 4_000))"
    }
    """
    let result = try runEventHookScript(
        hookScript,
        eventName: "turn-ended",
        eventFile: eventFile,
        payload: payload,
        environmentOverrides: [
            "MAPOFAGENTS_HOOK_CAPTURE_RAW": "1",
            "MAPOFAGENTS_HOOK_RAW_MAX_BYTES": "256",
        ]
    )
    let contents = try String(contentsOf: eventFile, encoding: .utf8)
    let event = try parsedSingleJSONObject(from: eventFile)

    #expect(result.terminationStatus == 0)
    #expect(event["raw"] != nil)
    #expect(event["rawTruncated"] as? Bool == true)
    #expect(contents.contains("hook-password-value") == false)
    #expect(contents.contains("hook-bearer-value") == false)
    #expect(contents.utf8.count < 4_096)
}

@Test
func workflowEventHookRedactsPEMBlocksBeforeAnyOutputTruncation() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-event-hook-long-pem-redaction-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let eventFile = directory.appendingPathComponent("hook-events.jsonl")
    let hookScript = try repositoryRoot().appendingPathComponent("script/mapofagents-hook-event.sh")
    let beginMarker = "-----BEGIN " + "EXAMPLE PRIVATE KEY-----"
    let endMarker = "-----END " + "EXAMPLE PRIVATE KEY-----"
    let identifiableMaterial = "test-only-key-material-"
    let oversizedPEM = beginMarker
        + String(repeating: identifiableMaterial, count: 1_000)
        + endMarker
    let payloadData = try JSONSerialization.data(
        withJSONObject: ["threadID": "thread-1", "output": oversizedPEM],
        options: [.sortedKeys]
    )
    let payload = try #require(String(data: payloadData, encoding: .utf8))
    let result = try runEventHookScript(
        hookScript,
        eventName: "turn-ended",
        eventFile: eventFile,
        payload: payload,
        environmentOverrides: [
            "MAPOFAGENTS_HOOK_CAPTURE_RAW": "1",
            "MAPOFAGENTS_HOOK_RAW_MAX_BYTES": "32768",
            "MAPOFAGENTS_HOOK_SUMMARY": oversizedPEM,
        ]
    )
    let contents = try String(contentsOf: eventFile, encoding: .utf8)

    #expect(result.terminationStatus == 0)
    #expect(contents.contains(beginMarker) == false)
    #expect(contents.contains(endMarker) == false)
    #expect(contents.contains(identifiableMaterial) == false)
    #expect(contents.contains("[REDACTED PRIVATE KEY]"))
}

@Test
func workflowEventHookCapsAndRotatesPrivateJSONLFiles() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-event-hook-rotation-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let eventFile = directory.appendingPathComponent("hook-events.jsonl")
    let hookScript = try repositoryRoot().appendingPathComponent("script/mapofagents-hook-event.sh")
    for index in 0..<8 {
        let result = try runEventHookScript(
            hookScript,
            eventName: "turn-ended",
            eventFile: eventFile,
            payload: #"{"threadID":"thread-1"}"#,
            environmentOverrides: [
                "MAPOFAGENTS_HOOK_EVENT_ID": "event-\(index)",
                "MAPOFAGENTS_HOOK_SUMMARY": String(repeating: "s", count: 1_200),
                "MAPOFAGENTS_HOOK_EVENT_MAX_BYTES": "4096",
                "MAPOFAGENTS_HOOK_EVENT_ROTATIONS": "2",
            ]
        )
        #expect(result.terminationStatus == 0)
    }

    let firstRotation = URL(fileURLWithPath: eventFile.path + ".1")
    let secondRotation = URL(fileURLWithPath: eventFile.path + ".2")
    let thirdRotation = URL(fileURLWithPath: eventFile.path + ".3")
    #expect(FileManager.default.fileExists(atPath: firstRotation.path))
    #expect(FileManager.default.fileExists(atPath: secondRotation.path))
    #expect(FileManager.default.fileExists(atPath: thirdRotation.path) == false)

    for url in [eventFile, firstRotation, secondRotation] {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = try #require(attributes[.size] as? NSNumber)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(size.intValue <= 4_096)
        #expect(permissions.intValue & 0o777 == 0o600)
    }
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

private func runEventHookScript(
    _ hookScript: URL,
    eventName: String,
    eventFile: URL,
    payload: String,
    environmentOverrides: [String: String] = [:]
) throws -> HookScriptResult {
    let process = Process()
    process.executableURL = hookScript
    process.arguments = [eventName]
    var environment = ProcessInfo.processInfo.environment
    environment["MAPOFAGENTS_HOOK_EVENT_FILE"] = eventFile.path
    environment["MAPOFAGENTS_HOST_ID"] = "local"
    environment["CODEX_THREAD_ID"] = "thread-1"
    environment["CODEX_TURN_ID"] = "turn-1"
    environment["MAPOFAGENTS_HOOK_CAPTURE_RAW"] = nil
    for (key, value) in environmentOverrides {
        environment[key] = value
    }
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

private func parsedSingleJSONObject(from eventFile: URL) throws -> [String: Any] {
    let contents = try String(contentsOf: eventFile, encoding: .utf8)
    let lines = contents.split(separator: "\n")
    #expect(lines.count == 1)
    let data = try #require(lines.first?.data(using: .utf8))
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
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
