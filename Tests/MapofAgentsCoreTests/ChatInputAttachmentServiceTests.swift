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
func chatInputAttachmentDirectoriesPreserveHostPathStyles() {
    #expect(
        ChatInputAttachmentService.remoteAttachmentDirectory(
            cwd: #"\Users\bad"#,
            threadID: "abc"
        )
        == "/tmp/mapofagents-attachments/abc"
    )
    #expect(
        ChatInputAttachmentService.remoteAttachmentDirectory(
            cwd: #"C:\Users\User\Desktop"#,
            threadID: "abc"
        )
        == #"C:\Users\User\Desktop\.mapofagents\attachments\abc"#
    )
    #expect(
        ChatInputAttachmentService.remoteAttachmentDirectory(
            cwd: "/Users/example/project",
            threadID: "abc"
        )
        == "/Users/example/project/.mapofagents/attachments/abc"
    )
}

@Test
func chatInputAttachmentKindDetectsImages() {
    #expect(ChatInputAttachmentService.kind(forFileName: "clip.png") == .image)
    #expect(ChatInputAttachmentService.kind(forFileName: "clip.bin", mimeType: "image/png") == .image)
    #expect(ChatInputAttachmentService.kind(forFileName: "notes.pdf") == .file)
}
