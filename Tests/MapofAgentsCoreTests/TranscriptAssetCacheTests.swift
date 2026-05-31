import Foundation
import Testing
@testable import MapofAgentsCore

@MainActor
@Test
func transcriptAssetCacheCachesFileArtifactsAndPreservesSourceHost() async throws {
    let hostID = HostID(rawValue: "remote-windows")
    let threadRef = ThreadRef(hostID: hostID, threadID: "thread-artifacts", cwd: "C:\\Users\\User\\Desktop")
    let attachment = ThreadMessageAttachment(
        id: "file-1",
        kind: .file,
        sourceHostID: hostID,
        sourcePath: "C:\\Users\\User\\Desktop\\hello.txt",
        title: "hello.txt"
    )
    let transcript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(role: .tool, text: "Saved to:\nC:\\Users\\User\\Desktop\\hello.txt", attachments: [attachment]),
        ]
    )

    let resolved = await TranscriptAssetCache.resolveArtifacts(in: transcript) { candidate in
        #expect(candidate.sourceHostID == hostID)
        return Data("hello from windows".utf8)
    }

    let resolvedAttachment = try #require(resolved.messages.first?.attachments.first)
    #expect(resolvedAttachment.kind == .file)
    #expect(resolvedAttachment.sourceHostID == hostID)
    #expect(resolvedAttachment.status == "completed")
    #expect(resolvedAttachment.byteCount == "hello from windows".utf8.count)
    #expect(resolvedAttachment.cachedPath != nil)

    if let cachedPath = resolvedAttachment.cachedPath {
        #expect(FileManager.default.fileExists(atPath: cachedPath))
        try? FileManager.default.removeItem(atPath: cachedPath)
    }
}

@MainActor
@Test
func transcriptAssetCacheCachesTimelineArtifactItems() async throws {
    let hostID = HostID(rawValue: "local")
    let threadRef = ThreadRef(hostID: hostID, threadID: "thread-timeline-artifact", cwd: "/tmp")
    let attachment = ThreadMessageAttachment(
        id: "timeline-image",
        kind: .image,
        sourceHostID: hostID,
        sourcePath: "/tmp/.codex/generated_images/thread-timeline-artifact/output.png",
        title: "output.png"
    )
    let transcript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(id: "assistant-1", role: .assistant, text: "Generated image"),
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
                            id: "timeline-image-item",
                            kind: .imageArtifact,
                            message: ThreadMessage(id: "assistant-1", role: .assistant, text: "Generated image", createdAt: Date(timeIntervalSince1970: 11)),
                            attachments: [attachment]
                        ),
                    ]
                ),
            ]
        )
    )

    let resolved = await TranscriptAssetCache.resolveArtifacts(in: transcript) { candidate in
        #expect(candidate.id == "timeline-image")
        return Data("image bytes".utf8)
    }

    let resolvedAttachment = try #require(resolved.turnTimeline?.turns.first?.items.first?.attachments.first)
    #expect(resolved.messages.first?.attachments.isEmpty == true)
    #expect(resolvedAttachment.status == "completed")
    #expect(resolvedAttachment.byteCount == "image bytes".utf8.count)
    #expect(resolvedAttachment.cachedPath != nil)

    if let cachedPath = resolvedAttachment.cachedPath {
        #expect(FileManager.default.fileExists(atPath: cachedPath))
        try? FileManager.default.removeItem(atPath: cachedPath)
    }
}

@MainActor
@Test
func transcriptAssetCacheMarksLargeFileArtifactsWithoutCaching() async throws {
    let hostID = HostID(rawValue: "local")
    let threadRef = ThreadRef(hostID: hostID, threadID: "thread-large-artifact", cwd: "/tmp")
    let attachment = ThreadMessageAttachment(
        id: "file-large",
        kind: .file,
        sourceHostID: hostID,
        sourcePath: "/tmp/large.log",
        title: "large.log"
    )
    let transcript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(role: .tool, text: "Saved to:\n/tmp/large.log", attachments: [attachment]),
        ]
    )

    let resolved = await TranscriptAssetCache.resolveArtifacts(in: transcript) { _ in
        Data(repeating: 0, count: TranscriptAssetCache.maxCachedArtifactBytes + 1)
    }

    let resolvedAttachment = try #require(resolved.messages.first?.attachments.first)
    #expect(resolvedAttachment.status == "too-large")
    #expect(resolvedAttachment.cachedPath == nil)
    #expect(resolvedAttachment.byteCount == TranscriptAssetCache.maxCachedArtifactBytes + 1)
}

@MainActor
@Test
func transcriptAssetCacheMarksLargeImagesWithoutCaching() async throws {
    let hostID = HostID(rawValue: "local")
    let threadRef = ThreadRef(hostID: hostID, threadID: "thread-large-image", cwd: "/tmp")
    let attachment = ThreadMessageAttachment(
        id: "image-large",
        kind: .image,
        sourceHostID: hostID,
        sourcePath: "/tmp/large.png",
        title: "large.png"
    )
    let transcript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(role: .tool, text: "Generated image", attachments: [attachment]),
        ]
    )

    let resolved = await TranscriptAssetCache.resolveArtifacts(in: transcript) { _ in
        Data(repeating: 0, count: TranscriptAssetCache.maxCachedImageBytes + 1)
    }

    let resolvedAttachment = try #require(resolved.messages.first?.attachments.first)
    #expect(resolvedAttachment.status == "too-large")
    #expect(resolvedAttachment.cachedPath == nil)
    #expect(resolvedAttachment.byteCount == TranscriptAssetCache.maxCachedImageBytes + 1)
}

@MainActor
@Test
func transcriptAssetCacheDoesNotReadUntrustedHeuristicFileArtifacts() async throws {
    let hostID = HostID(rawValue: "local")
    let threadRef = ThreadRef(hostID: hostID, threadID: "thread-sensitive-artifact", cwd: "/tmp")
    let events: [JSONValue] = [
        .object([
            "type": .string("response_item"),
            "payload": .object([
                "type": .string("function_call_output"),
                "call_id": .string("call-sensitive"),
                "output": .string("""
                Saved to:
                /Users/example/.ssh/credentials.json
                """),
            ]),
        ]),
    ]
    let transcript = ThreadTranscriptParser.transcript(fromRolloutEvents: events, threadRef: threadRef)
    var didRead = false

    let resolved = await TranscriptAssetCache.resolveArtifacts(in: transcript) { _ in
        didRead = true
        return Data("secret".utf8)
    }

    #expect(resolved.messages.first?.attachments.isEmpty == true)
    #expect(didRead == false)
}

@MainActor
@Test
func transcriptAssetCacheSkipsKnownOversizedArtifactsBeforeReading() async throws {
    let hostID = HostID(rawValue: "local")
    let threadRef = ThreadRef(hostID: hostID, threadID: "thread-known-large", cwd: "/tmp")
    let attachment = ThreadMessageAttachment(
        id: "known-large",
        kind: .image,
        sourceHostID: hostID,
        sourcePath: "/tmp/known-large.png",
        title: "known-large.png",
        byteCount: TranscriptAssetCache.maxCachedImageBytes + 1
    )
    let transcript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(role: .tool, text: "Generated image", attachments: [attachment]),
        ]
    )
    var didRead = false

    let resolved = await TranscriptAssetCache.resolveArtifacts(in: transcript) { _ in
        didRead = true
        return Data()
    }

    let resolvedAttachment = try #require(resolved.messages.first?.attachments.first)
    #expect(resolvedAttachment.status == "too-large")
    #expect(resolvedAttachment.byteCount == TranscriptAssetCache.maxCachedImageBytes + 1)
    #expect(resolvedAttachment.cachedPath == nil)
    #expect(didRead == false)
}

@Test
func transcriptAssetCacheResolvesRelativeArtifactPathsAgainstThreadCWD() {
    let macThread = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp/project")
    let windowsThread = ThreadRef(hostID: HostID(rawValue: "windows"), threadID: "thread-2", cwd: "C:\\Users\\User\\Desktop")
    let rootThread = ThreadRef(hostID: HostID(rawValue: "root"), threadID: "thread-3", cwd: "/")

    let relativeFile = ThreadMessageAttachment(
        kind: .file,
        sourceHostID: macThread.hostID,
        sourcePath: "Sources/App.swift"
    )
    let absoluteFile = ThreadMessageAttachment(
        kind: .file,
        sourceHostID: macThread.hostID,
        sourcePath: "/var/tmp/App.swift"
    )
    let windowsRelativeFile = ThreadMessageAttachment(
        kind: .file,
        sourceHostID: windowsThread.hostID,
        sourcePath: "notes\\todo.txt"
    )

    #expect(TranscriptAssetCache.sourceReadPath(for: relativeFile, in: macThread) == "/tmp/project/Sources/App.swift")
    #expect(TranscriptAssetCache.sourceReadPath(for: absoluteFile, in: macThread) == nil)
    #expect(TranscriptAssetCache.sourceReadPath(for: windowsRelativeFile, in: windowsThread) == "C:\\Users\\User\\Desktop\\notes\\todo.txt")
    #expect(TranscriptAssetCache.sourceReadPath(for: relativeFile, in: rootThread) == nil)
}

@Test
func transcriptAssetCacheRejectsSymlinkEscapesFromThreadCWD() throws {
    let baseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-artifact-cache-\(UUID().uuidString)", isDirectory: true)
    let projectURL = baseURL.appendingPathComponent("project", isDirectory: true)
    let outsideURL = baseURL.appendingPathComponent("outside", isDirectory: true)
    let linkURL = projectURL.appendingPathComponent("linked-outside", isDirectory: true)
    let secretURL = outsideURL.appendingPathComponent("secret.txt")

    defer {
        try? FileManager.default.removeItem(at: baseURL)
    }

    try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
    try Data("secret".utf8).write(to: secretURL)
    try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: outsideURL)

    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-symlink", cwd: projectURL.path)
    let attachment = ThreadMessageAttachment(
        kind: .file,
        sourceHostID: threadRef.hostID,
        sourcePath: "linked-outside/secret.txt"
    )

    #expect(TranscriptAssetCache.sourceReadPath(for: attachment, in: threadRef) == nil)
}

@Test
func transcriptAssetCacheAllowsThreadScopedGeneratedArtifactsOutsideCWD() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp/project")
    let generatedImage = ThreadMessageAttachment(
        kind: .image,
        sourceHostID: threadRef.hostID,
        sourcePath: "/Users/example/.codex/generated_images/thread-1/ig-ship.png"
    )

    #expect(
        TranscriptAssetCache.sourceReadPath(for: generatedImage, in: threadRef)
        == "/Users/example/.codex/generated_images/thread-1/ig-ship.png"
    )
}

@Test
func legacyDecodedFileArtifactsDefaultToUntrustedAutoHydration() throws {
    let fileData = Data("""
    {
      "id": "legacy-file",
      "kind": "file",
      "sourceHostID": "local",
      "sourcePath": "Sources/App.swift"
    }
    """.utf8)
    let imageData = Data("""
    {
      "id": "legacy-image",
      "kind": "image",
      "sourceHostID": "local",
      "sourcePath": "/tmp/.codex/generated_images/thread-1/output.png"
    }
    """.utf8)

    let fileAttachment = try JSONDecoder().decode(ThreadMessageAttachment.self, from: fileData)
    let imageAttachment = try JSONDecoder().decode(ThreadMessageAttachment.self, from: imageData)

    #expect(fileAttachment.isTrustedForAutoHydration == false)
    #expect(imageAttachment.isTrustedForAutoHydration == true)
}
