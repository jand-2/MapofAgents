import MapofAgentsCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@MainActor
@Observable
final class ThreadComposerSession {
    struct Submission: Identifiable {
        var id: UUID
        var generation: UInt64
        var text: String
        var attachments: [ChatInputAttachment]
    }

    private(set) var threadIdentity: String
    private(set) var isSubmitting = false
    var draft = ""
    var pendingAttachments: [ChatInputAttachment] = []
    var isFileImporterPresented = false
    var attachmentError: String?

    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var activeSubmissionID: UUID?

    init(threadIdentity: String) {
        self.threadIdentity = threadIdentity
    }

    func reset(for threadIdentity: String) {
        generation &+= 1
        self.threadIdentity = threadIdentity
        activeSubmissionID = nil
        isSubmitting = false
        draft = ""
        pendingAttachments = []
        isFileImporterPresented = false
        attachmentError = nil
    }

    func beginSubmission(isAwaitingResponse: Bool) -> Submission? {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard (!text.isEmpty || !attachments.isEmpty),
              !isAwaitingResponse,
              !isSubmitting else {
            return nil
        }

        let submission = Submission(
            id: UUID(),
            generation: generation,
            text: text,
            attachments: attachments
        )
        activeSubmissionID = submission.id
        draft = ""
        pendingAttachments = []
        attachmentError = nil
        isSubmitting = true
        return submission
    }

    func complete(_ submission: Submission, didSend: Bool) {
        guard submission.generation == generation,
              submission.id == activeSubmissionID else {
            return
        }
        activeSubmissionID = nil
        isSubmitting = false
        guard !didSend else { return }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft = submission.text
        }
        if pendingAttachments.isEmpty {
            pendingAttachments = submission.attachments
        }
    }

    func sendUnavailableReason(isAwaitingResponse: Bool) -> String? {
        if isAwaitingResponse {
            return "This thread is still running. Wait for the current turn to finish."
        }
        if isSubmitting {
            return "This message is still being sent."
        }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           pendingAttachments.isEmpty {
            return "Type a message or attach a file before sending."
        }
        return nil
    }

    func append(_ attachments: [ChatInputAttachment]) {
        pendingAttachments.append(contentsOf: attachments)
        attachmentError = nil
    }

    func removeAttachment(id: String) {
        pendingAttachments.removeAll { $0.id == id }
    }
}

struct ThreadPopoverComposerView: View {
    var node: CanvasNode
    @Bindable var runtimeStore: CodexRuntimeStore
    var threadIdentity: String
    var threadMentionCandidates: [MentionCandidate]
    var isAwaitingResponse: Bool
    var runStatus: ThreadRunStatus
    var canStopTurn: Bool
    var isStoppingTurn: Bool
    var isFullScreen: Bool
    var initiallyFocused: Bool
    var onStopTurn: () -> Void
    var onSend: (String, [ChatInputAttachment]) async -> Bool

    @State private var session: ThreadComposerSession

    init(
        node: CanvasNode,
        runtimeStore: CodexRuntimeStore,
        threadIdentity: String,
        threadMentionCandidates: [MentionCandidate],
        isAwaitingResponse: Bool,
        runStatus: ThreadRunStatus,
        canStopTurn: Bool,
        isStoppingTurn: Bool,
        isFullScreen: Bool,
        initiallyFocused: Bool = false,
        onStopTurn: @escaping () -> Void,
        onSend: @escaping (String, [ChatInputAttachment]) async -> Bool
    ) {
        self.node = node
        self.runtimeStore = runtimeStore
        self.threadIdentity = threadIdentity
        self.threadMentionCandidates = threadMentionCandidates
        self.isAwaitingResponse = isAwaitingResponse
        self.runStatus = runStatus
        self.canStopTurn = canStopTurn
        self.isStoppingTurn = isStoppingTurn
        self.isFullScreen = isFullScreen
        self.initiallyFocused = initiallyFocused
        self.onStopTurn = onStopTurn
        self.onSend = onSend
        _session = State(initialValue: ThreadComposerSession(threadIdentity: threadIdentity))
    }

    var body: some View {
        @Bindable var session = session
        VStack(spacing: 10) {
            ThreadComposerMetadataRow(
                model: node.metadata.model,
                reasoningEffort: node.metadata.reasoningEffort
            )

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    attachmentToolbar

                    if !session.pendingAttachments.isEmpty {
                        PendingChatAttachmentTray(
                            attachments: session.pendingAttachments,
                            onRemove: session.removeAttachment
                        )
                    }

                    MentionComposerView(
                        text: $session.draft,
                        runtimeStore: runtimeStore,
                        placeholder: "Message this thread",
                        fileRoot: mentionFileRoot,
                        extraCandidates: threadMentionCandidates,
                        minLines: 3,
                        maxLines: 8,
                        isDisabled: isAwaitingResponse || session.isSubmitting,
                        usesLocalMentionCatalog: usesLocalMentionCatalog,
                        initiallyFocused: initiallyFocused,
                        onSubmit: sendDraft
                    )

                    if let attachmentError = session.attachmentError {
                        Text(attachmentError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }

                VStack(spacing: 8) {
                    if showsStopTurnButton {
                        stopTurnButton
                    }

                    FeedbackButton(
                        unavailableReason: session.sendUnavailableReason(
                            isAwaitingResponse: isAwaitingResponse
                        ),
                        action: sendDraft
                    ) {
                        Image(systemName: "paperplane.fill")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .help(session.sendUnavailableReason(isAwaitingResponse: isAwaitingResponse) ?? "Send")
                    .accessibilityLabel("Send message")
                    .minimumAccessibleHitTarget()
                }
            }
        }
        .padding(14)
        #if os(iOS)
        .padding(.bottom, isFullScreen ? 10 : 0)
        #endif
        .fileImporter(
            isPresented: $session.isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: handleFileImport
        )
        .modifier(ChatAttachmentPasteCommandModifier(onPaste: pasteAttachmentsFromClipboard))
        .onChange(of: threadIdentity) { _, identity in
            session.reset(for: identity)
        }
    }

    private var attachmentToolbar: some View {
        HStack(spacing: 8) {
            Button {
                session.isFileImporterPresented = true
            } label: {
                Image(systemName: "paperclip")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(isAwaitingResponse || session.isSubmitting)
            .help("Attach files")
            .accessibilityLabel("Attach files")
            .minimumAccessibleHitTarget()

            Button(action: pasteAttachmentsFromClipboard) {
                Image(systemName: "doc.on.clipboard")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(isAwaitingResponse || session.isSubmitting)
            .help("Paste screenshot or files")
            .accessibilityLabel("Paste screenshot or files")
            .minimumAccessibleHitTarget()

            if !session.pendingAttachments.isEmpty {
                Text("\(session.pendingAttachments.count) attached")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var stopTurnButton: some View {
        FeedbackButton(unavailableReason: stopTurnUnavailableReason, action: onStopTurn) {
            Image(systemName: isStoppingTurn ? "stop.circle" : "stop.fill")
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.bordered)
        .foregroundStyle(.red)
        .help(stopTurnUnavailableReason ?? "Stop running turn")
        .accessibilityLabel(isStoppingTurn ? "Stopping turn" : "Stop running turn")
        .minimumAccessibleHitTarget()
    }

    private var showsStopTurnButton: Bool {
        runStatus == .running || canStopTurn || isStoppingTurn
    }

    private var stopTurnUnavailableReason: String? {
        if isStoppingTurn {
            return "This turn is already being stopped."
        }
        if canStopTurn || runStatus == .running {
            return nil
        }
        return "This thread does not have a running turn to stop."
    }

    private var mentionFileRoot: String? {
        if let cwd = node.metadata.threadRef?.cwd {
            return cwd
        }
        return node.subtitle.hasPrefix("/") ? node.subtitle : nil
    }

    private var usesLocalMentionCatalog: Bool {
        guard let threadRef = node.metadata.threadRef else { return true }
        return threadRef.hostID == runtimeStore.localHost.id
    }

    private func sendDraft() {
        guard let submission = session.beginSubmission(isAwaitingResponse: isAwaitingResponse) else {
            return
        }
        Task {
            let didSend = await onSend(submission.text, submission.attachments)
            session.complete(submission, didSend: didSend)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            appendFileAttachments(from: urls)
        case .failure(let error):
            session.attachmentError = error.localizedDescription
        }
    }

    private func appendFileAttachments(from urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            do {
                session.append(try await ThreadComposerAttachmentService.attachments(from: urls))
            } catch {
                session.attachmentError = error.localizedDescription
            }
        }
    }

    private func pasteAttachmentsFromClipboard() {
        #if os(macOS)
        var didAttach = false
        if let objects = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] {
            let urls = objects.compactMap { $0 as URL }
            if !urls.isEmpty {
                didAttach = true
                appendFileAttachments(from: urls)
            }
        }

        if let image = NSImage(pasteboard: NSPasteboard.general),
           let data = image.pngDataForChatAttachment {
            session.append([Self.imageAttachment(data: data)])
            didAttach = true
        }
        session.attachmentError = didAttach
            ? nil
            : "Clipboard does not contain a file or screenshot."
        #elseif os(iOS)
        if let image = UIPasteboard.general.image, let data = image.pngData() {
            session.append([Self.imageAttachment(data: data)])
        } else if let url = UIPasteboard.general.url, url.isFileURL {
            appendFileAttachments(from: [url])
        } else {
            session.attachmentError = "Clipboard does not contain a file or screenshot."
        }
        #endif
    }

    private static func imageAttachment(data: Data) -> ChatInputAttachment {
        let name = "screenshot-\(Int(Date().timeIntervalSince1970 * 1000)).png"
        return ChatInputAttachment(
            kind: .image,
            name: name,
            mimeType: "image/png",
            data: data,
            byteCount: data.count
        )
    }
}

private struct ThreadComposerMetadataRow: View {
    var model: String?
    var reasoningEffort: String?

    var body: some View {
        HStack(spacing: 8) {
            if let model {
                Label(model, systemImage: "cpu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let reasoningEffort {
                Label(reasoningEffort, systemImage: "dial.medium")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct PendingChatAttachmentTray: View {
    var attachments: [ChatInputAttachment]
    var onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    PendingChatAttachmentChip(
                        attachment: attachment,
                        onRemove: { onRemove(attachment.id) }
                    )
                }
            }
            .padding(.vertical, 1)
        }
    }
}

private struct PendingChatAttachmentChip: View {
    var attachment: ChatInputAttachment
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: attachment.kind == .image ? "photo" : "doc")
                .foregroundStyle(attachment.kind == .image ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if let byteCount = attachment.byteCount {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove attachment")
            .accessibilityLabel("Remove \(attachment.name)")
            .minimumAccessibleHitTarget()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

private struct ChatAttachmentPasteCommandModifier: ViewModifier {
    var onPaste: () -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onPasteCommand(of: [.fileURL, .image, .png, .jpeg, .tiff]) { _ in
            onPaste()
        }
        #else
        content
        #endif
    }
}

private enum ThreadComposerAttachmentService {
    static func attachments(from urls: [URL]) async throws -> [ChatInputAttachment] {
        try await Task.detached(priority: .utility) {
            try urls.map { url in
                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let data = try ChatInputAttachmentService.attachmentData(
                    at: url,
                    name: url.lastPathComponent
                )
                let mimeType = mimeType(for: url)
                let name = ChatInputAttachmentService.sanitizedFileName(url.lastPathComponent)
                return ChatInputAttachment(
                    kind: ChatInputAttachmentService.kind(forFileName: name, mimeType: mimeType),
                    name: name,
                    mimeType: mimeType,
                    sourcePath: url.isFileURL ? url.path : nil,
                    data: data,
                    byteCount: data.count
                )
            }
        }.value
    }

    nonisolated private static func mimeType(for url: URL) -> String? {
        if let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let type = values.contentType {
            return type.preferredMIMEType
        }
        return ChatInputAttachmentService.inferredMimeType(forFileName: url.lastPathComponent)
    }
}

#if os(macOS)
private extension NSImage {
    var pngDataForChatAttachment: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif
