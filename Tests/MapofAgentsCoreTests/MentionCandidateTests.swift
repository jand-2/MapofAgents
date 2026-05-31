import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func skillMentionCandidatesUseCodexMarkdownLinks() {
    let result: JSONValue = .object([
        "data": .array([
            .object([
                "cwd": .string("/tmp/project"),
                "skills": .array([
                    .object([
                        "name": .string("codex-app-server-patterns"),
                        "path": .string("/Users/example/.codex/skills/codex-app-server-patterns/SKILL.md"),
                        "description": .string("Build on the official Codex runtime."),
                        "enabled": .bool(true),
                        "interface": .object([
                            "displayName": .string("Codex App Server Patterns"),
                            "shortDescription": .string("Design custom app-server clients."),
                        ]),
                    ]),
                ]),
            ]),
        ]),
    ])

    let candidates = CodexRuntimeStore.skillMentionCandidates(from: result)

    #expect(candidates.count == 1)
    #expect(candidates.first?.trigger == "$")
    #expect(candidates.first?.title == "$codex-app-server-patterns")
    #expect(candidates.first?.insertionText == "[$codex-app-server-patterns](/Users/example/.codex/skills/codex-app-server-patterns/SKILL.md)")
}

@Test
func bundledWorkflowBridgeSkillUsesMapofAgentsURI() {
    let candidate = MapofAgentsWorkflowBridgeSkill.mentionCandidate

    #expect(candidate.kind == .skill)
    #expect(candidate.trigger == "$")
    #expect(candidate.title == "$mapofagents-workflow-bridge")
    #expect(candidate.insertionText == "[$mapofagents-workflow-bridge](mapofagents-skill://workflow-bridge)")
    #expect(MapofAgentsWorkflowBridgeSkill.instructions.contains("Workflow route map"))
    #expect(MapofAgentsWorkflowBridgeSkill.instructions.contains("Contract version: \(MapofAgentsWorkflowBridgeSkill.contractVersion)"))
    #expect(MapofAgentsWorkflowBridgeSkill.instructions.contains("Workflow folder references"))
    #expect(MapofAgentsWorkflowBridgeSkill.instructions.contains("thread/resume"))
    #expect(MapofAgentsWorkflowBridgeSkill.instructions.contains("turn/start"))
    #expect(MapofAgentsWorkflowBridgeSkill.instructions.contains("You are responsible for chat delivery"))
    #expect(MapofAgentsWorkflowBridgeSkill.instructions.contains("sshFileAccess"))
    #expect(MapofAgentsWorkflowBridgeSkill.instructions.contains("Direct tunnel pattern"))
}

@Test
func pluginMentionCandidatesUsePluginURLsAndSkipUnavailablePlugins() {
    let result: JSONValue = .object([
        "marketplaces": .array([
            .object([
                "name": .string("openai-curated"),
                "plugins": .array([
                    .object([
                        "id": .string("build-macos-apps@openai-curated"),
                        "name": .string("build-macos-apps"),
                        "installed": .bool(true),
                        "enabled": .bool(true),
                        "interface": .object([
                            "displayName": .string("Build macOS Apps"),
                            "shortDescription": .string("Build and debug SwiftUI apps."),
                        ]),
                    ]),
                    .object([
                        "id": .string("disabled@openai-curated"),
                        "name": .string("disabled"),
                        "installed": .bool(true),
                        "enabled": .bool(false),
                    ]),
                    .object([
                        "id": .string("not-installed@openai-curated"),
                        "name": .string("not-installed"),
                        "installed": .bool(false),
                        "enabled": .bool(true),
                    ]),
                ]),
            ]),
        ]),
    ])

    let candidates = CodexRuntimeStore.pluginMentionCandidates(from: result)

    #expect(candidates.count == 1)
    #expect(candidates.first?.trigger == "@")
    #expect(candidates.first?.title == "@build-macos-apps")
    #expect(candidates.first?.insertionText == "[@build-macos-apps](plugin://build-macos-apps@openai-curated)")
}

@Test
func fileMentionCandidatesUseAbsoluteMarkdownLinks() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-mention-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileURL = directory.appendingPathComponent("Package.swift")
    try "let package = Package()".write(to: fileURL, atomically: true, encoding: .utf8)

    let candidates = CodexRuntimeStore.fileMentionCandidates(rootPath: directory.path)

    #expect(candidates.contains { candidate in
        candidate.kind == .file
            && candidate.title == "@Package.swift"
            && candidate.insertionText == "[@Package.swift](\(fileURL.path))"
    })

    try? FileManager.default.removeItem(at: directory)
}
