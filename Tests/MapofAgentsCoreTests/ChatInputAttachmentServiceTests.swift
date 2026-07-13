import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func chatInputAttachmentsBuildTextAndLocalImageInputItems() {
    let attachments = [
        ResolvedChatInputAttachment(
            id: "image",
            kind: .image,
            name: "screen.png",
            mimeType: "image/png",
            path: "/tmp/screen.png",
            byteCount: 12
        ),
        ResolvedChatInputAttachment(
            id: "file",
            kind: .file,
            name: "notes.pdf",
            mimeType: "application/pdf",
            path: "/tmp/notes.pdf",
            byteCount: 34
        ),
    ]

    let items = ChatInputAttachmentService.inputItems(
        text: "Please use this context.",
        attachments: attachments
    )

    #expect(items.count == 2)
    #expect(items.first?["type"]?.stringValue == "text")
    #expect(items.first?["text"]?.stringValue?.contains("Attached supplemental files:") == true)
    #expect(items.first?["text"]?.stringValue?.contains("/tmp/notes.pdf") == true)
    #expect(items.last?["type"]?.stringValue == "localImage")
    #expect(items.last?["path"]?.stringValue == "/tmp/screen.png")
}

@Test
func chatInputAttachmentDirectoriesUseOwnedStagingRoots() throws {
    #expect(
        throws: ChatInputAttachmentError.self
    ) {
        try ChatInputAttachmentService.remoteAttachmentDirectory(
            cwd: #"\Users\bad"#,
            threadID: "abc",
            stagingID: "batch-1"
        )
    }
    #expect(
        try ChatInputAttachmentService.remoteAttachmentDirectory(
            cwd: #"C:\Users\User\Desktop"#,
            hostID: HostID(rawValue: "remote-a"),
            threadID: "abc",
            stagingID: "batch-1"
        )
        == #"C:\Users\User\AppData\Local\MapofAgents\attachment-staging\hosts\remote-a\threads\abc\batches\batch-1"#
    )
    #expect(
        throws: ChatInputAttachmentError.self
    ) {
        try ChatInputAttachmentService.remoteAttachmentDirectory(
            cwd: #"C:\Users\..\Desktop"#,
            threadID: "abc",
            stagingID: "batch-1"
        )
    }
    #expect(
        try ChatInputAttachmentService.remoteAttachmentDirectory(
            cwd: "/Users/example/project",
            threadID: "abc",
            stagingID: "batch-1"
        )
        == "/Users/example/Library/Application Support/mapofagents/attachment-staging/hosts/remote/threads/abc/batches/batch-1"
    )
    #expect(throws: ChatInputAttachmentError.self) {
        try ChatInputAttachmentService.remoteAttachmentDirectory(
            cwd: "/workspace/project",
            threadID: "abc",
            stagingID: "batch-1"
        )
    }
    #expect(
        ChatInputAttachmentService.remoteAttachmentDirectory(
            stagingRoot: "/var/lib/mapofagents/attachment-staging",
            hostID: HostID(rawValue: "remote-a"),
            threadID: "abc",
            stagingID: "batch-1"
        )
        == "/var/lib/mapofagents/attachment-staging/hosts/remote-a/threads/abc/batches/batch-1"
    )

    let stagingRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-attachment-staging-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: stagingRoot) }
    let threadRef = ThreadRef(
        hostID: HostID(rawValue: "local"),
        threadID: "thread-1",
        cwd: "/Users/example/project"
    )
    let directory = try ChatInputAttachmentService.localAttachmentDirectory(
        for: threadRef,
        stagingRoot: stagingRoot,
        stagingID: "batch-1"
    )

    #expect(directory.path == stagingRoot
        .appendingPathComponent("hosts/local/threads/thread-1/batches/batch-1", isDirectory: true)
        .path)
    #expect(directory.path.contains(threadRef.cwd) == false)
    let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    #expect(permissions.intValue & 0o777 == 0o700)
}

@Test
func chatInputAttachmentInferenceRejectsSharedAndReservedProfiles() {
    let unsafeWorkingDirectories = [
        "/Users/Shared/project",
        "/Users/Guest/project",
        "/home/shared/project",
        "/home/public/project",
        "/home/nobody/project",
        #"C:\Users\Public\Desktop"#,
        #"C:\Users\Default\Desktop"#,
        #"C:\Users\Default User\Desktop"#,
        #"C:\Users\All Users\Desktop"#,
        #"C:\Users\Guest\Desktop"#,
        #"C:\Users\defaultuser0\Desktop"#,
    ]

    for cwd in unsafeWorkingDirectories {
        #expect(throws: ChatInputAttachmentError.self, "Expected reserved profile rejection for \(cwd)") {
            try ChatInputAttachmentService.remoteAttachmentDirectory(
                cwd: cwd,
                threadID: "thread-1",
                stagingID: "batch-1"
            )
        }
    }

    #expect(
        ChatInputAttachmentService.remoteAttachmentDirectory(
            stagingRoot: "/authenticated/app-support/attachment-staging",
            hostID: HostID(rawValue: "remote-a"),
            threadID: "thread-1",
            stagingID: "batch-1"
        )
        == "/authenticated/app-support/attachment-staging/hosts/remote-a/threads/thread-1/batches/batch-1"
    )
}

@Test
func chatInputAttachmentKindDetectsImages() {
    #expect(ChatInputAttachmentService.kind(forFileName: "clip.png") == .image)
    #expect(ChatInputAttachmentService.kind(forFileName: "clip.bin", mimeType: "image/png") == .image)
    #expect(ChatInputAttachmentService.kind(forFileName: "notes.pdf") == .file)
}

@Test
func chatInputAttachmentSanitizesTraversalAndControlCharacters() {
    #expect(ChatInputAttachmentService.sanitizedFileName("..") == "attachment")
    #expect(ChatInputAttachmentService.sanitizedFileName(".") == "attachment")
    #expect(ChatInputAttachmentService.sanitizedFileName("../secret.txt") == "..-secret.txt")
    #expect(ChatInputAttachmentService.sanitizedFileName("line\nfeed.txt") == "line-feed.txt")
    #expect(ChatInputAttachmentService.sanitizedFileName(String(repeating: "a", count: 300)).count == 180)
}

@Test
func chatInputAttachmentReadsSourceWithSizePreflightAndBoundedRead() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-attachment-read-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let smallURL = directory.appendingPathComponent("small.txt")
    let smallData = Data("hello".utf8)
    try smallData.write(to: smallURL)
    #expect(try ChatInputAttachmentService.attachmentData(at: smallURL, name: "small.txt") == smallData)

    let oversizedURL = directory.appendingPathComponent("oversized.bin")
    FileManager.default.createFile(atPath: oversizedURL.path, contents: nil)
    let handle = try FileHandle(forWritingTo: oversizedURL)
    try handle.truncate(atOffset: UInt64(ChatInputAttachmentService.maxAttachmentBytes + 1))
    try handle.close()

    do {
        _ = try ChatInputAttachmentService.attachmentData(at: oversizedURL, name: "oversized.bin")
        Issue.record("Expected an oversized sparse file to be rejected")
    } catch ChatInputAttachmentError.tooLarge(let name, _, let limit) {
        #expect(name == "oversized.bin")
        #expect(limit == ChatInputAttachmentService.maxAttachmentBytes)
    } catch {
        Issue.record("Expected tooLarge, received \(error)")
    }
}

@Test
func chatInputAttachmentUsesDeclaredByteCountAsEarlyPreflight() {
    let attachment = ChatInputAttachment(
        kind: .file,
        name: "oversized.bin",
        sourcePath: "/path/that/does/not/exist",
        byteCount: ChatInputAttachmentService.maxAttachmentBytes + 1
    )

    do {
        _ = try ChatInputAttachmentService.attachmentData(attachment)
        Issue.record("Expected declared oversized attachment to be rejected")
    } catch ChatInputAttachmentError.tooLarge(let name, _, _) {
        #expect(name == "oversized.bin")
    } catch {
        Issue.record("Expected tooLarge, received \(error)")
    }
}
