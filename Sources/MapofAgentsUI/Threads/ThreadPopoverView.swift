import MapofAgentsCore
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum TranscriptLoadPhase: Hashable {
    case idle
    case connectingHost
    case loadingHistory
    case hydratingArtifacts
    case refreshing
    case loadingOlder

    var title: String {
        switch self {
        case .idle:
            return "Ready"
        case .connectingHost:
            return "Checking host connection"
        case .loadingHistory:
            return "Loading message history"
        case .hydratingArtifacts:
            return "Hydrating artifacts"
        case .refreshing:
            return "Refreshing transcript"
        case .loadingOlder:
            return "Loading older messages"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            return ""
        case .connectingHost:
            return "Waiting on the owning machine or App Server route."
        case .loadingHistory:
            return "Waiting on thread history from Codex App Server."
        case .hydratingArtifacts:
            return "Reading generated files, diffs, or images."
        case .refreshing:
            return "Keeping the last loaded messages visible."
        case .loadingOlder:
            return "Prepending an older transcript page."
        }
    }

    var iconName: String {
        switch self {
        case .idle:
            return "checkmark.circle"
        case .connectingHost:
            return "antenna.radiowaves.left.and.right"
        case .loadingHistory:
            return "text.bubble"
        case .hydratingArtifacts:
            return "shippingbox"
        case .refreshing:
            return "arrow.clockwise"
        case .loadingOlder:
            return "clock.arrow.circlepath"
        }
    }
}

private enum TranscriptRowCategory: String, CaseIterable, Identifiable, Hashable {
    case messages
    case progress
    case thoughts
    case tools
    case artifacts
    case approvals
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .messages:
            return "Messages"
        case .progress:
            return "Progress"
        case .thoughts:
            return "Thoughts"
        case .tools:
            return "Tools"
        case .artifacts:
            return "Artifacts"
        case .approvals:
            return "Approvals"
        case .system:
            return "System"
        }
    }

    var compactTitle: String {
        switch self {
        case .messages:
            return "Msg"
        case .progress:
            return "Progress"
        case .thoughts:
            return "Thought"
        case .tools:
            return "Tool"
        case .artifacts:
            return "Artifact"
        case .approvals:
            return "Approval"
        case .system:
            return "Event"
        }
    }

    var iconName: String {
        switch self {
        case .messages:
            return "bubble.left.and.bubble.right"
        case .progress:
            return "arrow.triangle.2.circlepath"
        case .thoughts:
            return "sparkles"
        case .tools:
            return "wrench.and.screwdriver"
        case .artifacts:
            return "shippingbox"
        case .approvals:
            return "hand.raised"
        case .system:
            return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .messages:
            return .green
        case .progress:
            return .teal
        case .thoughts:
            return .purple
        case .tools:
            return .orange
        case .artifacts:
            return .blue
        case .approvals:
            return .red
        case .system:
            return .secondary
        }
    }

    static func categories(for message: ThreadMessage) -> Set<Self> {
        categories(for: message, itemKind: nil, attachments: message.attachments)
    }

    static func categories(for item: ThreadTurnItem) -> Set<Self> {
        categories(for: item.message, itemKind: item.kind, attachments: item.effectiveAttachments)
    }

    static func primaryCategory(for item: ThreadTurnItem) -> Self {
        if item.kind.isArtifact {
            return .artifacts
        }

        switch item.message.role {
        case .user:
            return .messages
        case .assistant:
            return isProgressLikeAssistantText(item.message.text) ? .progress : .messages
        case .reasoning:
            return .thoughts
        case .tool:
            return .tools
        case .system:
            return .system
        }
    }

    private static func categories(
        for message: ThreadMessage,
        itemKind: ThreadTurnItemKind?,
        attachments: [ThreadMessageAttachment]
    ) -> Set<Self> {
        var categories = Set<Self>()

        if itemKind?.isArtifact == true || !attachments.isEmpty {
            categories.insert(.artifacts)
        }

        if itemKind == .tool || message.role == .tool {
            categories.insert(.tools)
        }

        switch itemKind {
        case .userMessage, .assistantMessage:
            break
        case .reasoning:
            categories.insert(.thoughts)
        case .tool:
            categories.insert(.tools)
        case .artifact, .imageArtifact, .fileArtifact, .diffArtifact:
            categories.insert(.artifacts)
        case .system:
            categories.insert(.system)
        case nil:
            break
        }

        switch message.role {
        case .user:
            categories.insert(.messages)
        case .assistant:
            categories.insert(isProgressLikeAssistantText(message.text) ? .progress : .messages)
        case .reasoning:
            categories.insert(.thoughts)
        case .tool:
            categories.insert(.tools)
        case .system:
            categories.insert(.system)
        }

        if categories.isEmpty {
            categories.insert(.system)
        }
        return categories
    }

    private static func isProgressLikeAssistantText(_ text: String) -> Bool {
        let firstLine = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard !firstLine.isEmpty else { return false }

        let progressVerbs = [
            "add", "adding", "build", "building", "check", "checking", "collect", "collecting",
            "fetch", "fetching", "hydrate", "hydrating", "inspect", "inspecting", "load", "loading",
            "look", "looking", "open", "opening", "patch", "patching", "prepare", "preparing",
            "read", "reading", "review", "reviewing", "run", "running", "scan", "scanning",
            "scope", "scoping", "start", "starting", "test", "testing", "update", "updating",
            "validate", "validating", "verify", "verifying", "wait", "waiting", "wire", "wiring",
            "work", "working"
        ]

        if progressVerbs.contains(where: { firstLine.hasPrefix("\($0) ") }) {
            return true
        }

        let firstPersonPrefixes = [
            "i am ", "i'm ", "i’m ", "i will ", "i'll ", "i’ll ", "i have ", "i've ", "i’ve "
        ]
        for prefix in firstPersonPrefixes where firstLine.hasPrefix(prefix) {
            let remainder = String(firstLine.dropFirst(prefix.count))
            if progressVerbs.contains(where: { remainder.hasPrefix("\($0) ") || remainder.hasPrefix("going to \($0) ") }) {
                return true
            }
        }

        return firstLine.hasPrefix("working on ")
            || firstLine.hasPrefix("waiting on ")
            || firstLine.hasPrefix("now ")
            || firstLine.hasPrefix("next ")
    }
}

private extension ThreadTurnItemKind {
    var isArtifact: Bool {
        switch self {
        case .artifact, .imageArtifact, .fileArtifact, .diffArtifact:
            return true
        case .userMessage, .assistantMessage, .reasoning, .tool, .system:
            return false
        }
    }
}

private extension ThreadMessage {
    var transcriptRowCategories: Set<TranscriptRowCategory> {
        TranscriptRowCategory.categories(for: self)
    }
}

private extension ThreadTurnItem {
    var transcriptRowCategories: Set<TranscriptRowCategory> {
        TranscriptRowCategory.categories(for: self)
    }

    var primaryTranscriptRowCategory: TranscriptRowCategory {
        TranscriptRowCategory.primaryCategory(for: self)
    }

    func matchesTranscriptFilter(_ categories: Set<TranscriptRowCategory>) -> Bool {
        !transcriptRowCategories.isDisjoint(with: categories)
    }
}

struct ThreadPopoverView: View {
    private static let messageBottomAnchorID = "thread-message-list-bottom"

    var node: CanvasNode
    @Bindable var runtimeStore: CodexRuntimeStore
    var transcript: ThreadTranscript?
    var liveAssistantText: String
    var liveStateSummary: ThreadLiveStateSummary? = nil
    var isLoading: Bool
    var isLoadingOlder: Bool
    var loadPhase: TranscriptLoadPhase = .idle
    var isAwaitingResponse: Bool
    var errorMessage: String?
    var threadMentionCandidates: [MentionCandidate] = []
    var attentionRequests: [RuntimeAttentionRequest] = []
    var threadAutomation: CodexAutomationSummary? = nil
    var isMoving = false
    var isFullScreen = false
    var allowsMoving = false
    var canStopTurn = false
    var isStoppingTurn = false
    var onRename: (String) -> Void
    var onMoveChanged: (CGSize) -> Void = { _ in }
    var onMoveEnded: (CGSize) -> Void = { _ in }
    var onStopTurn: () -> Void = {}
    var onRefresh: () -> Void
    var onLoadOlder: () -> Void
    var onUseCachedTranscript: () -> Void = {}
    var onSend: (String, [ChatInputAttachment]) async -> Bool
    var onFocusAttention: (RuntimeAttentionRequest) -> Void = { _ in }
    var onRespondToAttention: (RuntimeAttentionRequest, Bool) -> Void = { _, _ in }
    var onRespondToAttentionWithText: (RuntimeAttentionRequest, String) -> Void = { _, _ in }
    var onDeclineTypedAttention: (RuntimeAttentionRequest) -> Void = { _ in }
    var onOpenAutomation: () -> Void = {}
    var onClose: () -> Void

    @State private var draft = ""
    @State private var isRenaming = false
    @State private var titleDraft = ""
    @State private var pendingOlderAnchorID: String?
    @State private var isArtifactsPresented = false
    @State private var isSubmitting = false
    @State private var pendingAttachments: [ChatInputAttachment] = []
    @State private var isFileImporterPresented = false
    @State private var attachmentError: String?
    @State private var activeRowCategories = Set(TranscriptRowCategory.allCases)
    @State private var currentUserMessageNavigationID: String?
    @State private var manualTranscriptNavigationStartedAt: Date?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            transcriptFilterBar

            Divider()

            messageList

            Divider()

            composer
        }
        .background(popoverBackground)
        .overlay {
            if !isFullScreen {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary, lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(isFullScreen ? 0 : 0.18), radius: 18, x: 0, y: 10)
        .task(id: mentionFileRoot ?? "") {
            guard usesLocalMentionCatalog else { return }
            await runtimeStore.refreshMentionCandidates(cwd: mentionFileRoot)
        }
        .onAppear {
            resetPopoverStateForCurrentThread()
        }
        .onChange(of: threadIdentity) { _, _ in
            resetPopoverStateForCurrentThread()
        }
        .onChange(of: node.title) { _, title in
            guard !isRenaming else { return }
            titleDraft = title
        }
        .sheet(isPresented: $isArtifactsPresented) {
            ThreadArtifactsListView(attachments: threadArtifacts)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                appendFileAttachments(from: urls)
            case .failure(let error):
                attachmentError = error.localizedDescription
            }
        }
        .modifier(ChatAttachmentPasteCommandModifier(onPaste: pasteAttachmentsFromClipboard))
    }

    private var threadIdentity: String {
        node.metadata.threadRef?.qualifiedID ?? node.id.rawValue
    }

    private var popoverBackground: some View {
        Group {
            if isFullScreen {
                Rectangle()
                    .fill(popoverBackgroundStyle)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(popoverBackgroundStyle)
            }
        }
    }

    private var popoverBackgroundStyle: AnyShapeStyle {
        if isMoving {
            return AnyShapeStyle(dragBackgroundColor.opacity(0.98))
        }

        return AnyShapeStyle(.regularMaterial)
    }

    private var dragBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #elseif os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color.black.opacity(0.92)
        #endif
    }

    private var threadKind: CodexThreadNodeKind {
        node.metadata.threadKind ?? .thread
    }

    private var threadKindBadge: some View {
        Label(threadKind.displayName, systemImage: threadKind == .subagent ? "person.2" : "bubble.left")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(threadKind == .subagent ? .purple : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((threadKind == .subagent ? Color.purple : Color.secondary).opacity(0.10), in: Capsule())
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            headerDragArea
                .layoutPriority(1)

            headerControlColumn
        }
        .padding(14)
        #if os(iOS)
        .padding(.top, isFullScreen ? 8 : 0)
        #endif
    }

    private var headerControlColumn: some View {
        VStack(alignment: .trailing, spacing: 8) {
            headerActionBar

            HStack(spacing: 8) {
                if let threadAutomation {
                    Button(action: onOpenAutomation) {
                        Image(systemName: "alarm")
                            .symbolVariant(threadAutomation.isActive ? .fill : .none)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(threadAutomation.isActive ? .orange : .secondary)
                    .help(automationHelp(threadAutomation))
                    .accessibilityLabel("Thread automation")
                    .accessibilityValue(automationHelp(threadAutomation))
                }

                ThreadHeaderRunStatusPill(
                    status: headerRunStatus,
                    isUnread: node.metadata.isUnread == true,
                    updatedAt: liveStateSummary?.updatedAt
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var headerActionBar: some View {
        HStack(spacing: 10) {
            if allowsMoving {
                headerDragHandle
            }

            FeedbackButton(
                unavailableReason: artifactsUnavailableReason,
                action: {
                    isArtifactsPresented = true
                }
            ) {
                Image(systemName: "shippingbox")
            }
            .buttonStyle(.plain)
            .help(artifactsUnavailableReason ?? "Artifacts")
            .accessibilityLabel("Artifacts")

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh")
            .accessibilityLabel("Refresh transcript")

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close")
            .accessibilityLabel("Close chat")
        }
        .foregroundStyle(.secondary)
    }

    private func automationHelp(_ automation: CodexAutomationSummary) -> String {
        let state = automation.isActive ? "active" : "paused"
        return "\(automation.name) automation is \(state)"
    }

    @ViewBuilder
    private var headerDragArea: some View {
        let content = HStack(spacing: 10) {
            Image(systemName: threadKind == .subagent ? "person.2" : "bubble.left.and.bubble.right")
                .foregroundStyle(threadKind == .subagent ? .purple : .blue)
                .frame(width: 26, height: 26)
                .background((threadKind == .subagent ? Color.purple : Color.blue).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if isRenaming {
                        TextField("Thread name", text: $titleDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.headline)
                            .onSubmit(saveRename)
                    } else {
                        Text(node.title)
                            .font(.headline)
                            .lineLimit(1)
                    }

                    Button {
                        if isRenaming {
                            saveRename()
                        } else {
                            titleDraft = node.title
                            isRenaming = true
                        }
                    } label: {
                        Image(systemName: isRenaming ? "checkmark" : "pencil")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help(isRenaming ? "Save name" : "Rename")
                    .accessibilityLabel(isRenaming ? "Save thread name" : "Rename thread")
                }

                Text(node.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let threadID = node.metadata.threadRef?.threadID {
                    HStack(spacing: 6) {
                        threadKindBadge

                        Text(threadID)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .textSelection(.enabled)

                        Button {
                            copyThreadID(threadID)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                        .help("Copy thread id")
                        .accessibilityLabel("Copy thread ID")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        if isRenaming || !allowsMoving {
            content
        } else {
            content.highPriorityGesture(moveGesture)
        }
    }

    private var headerDragHandle: some View {
        ZStack {
            Image(systemName: "line.3.horizontal")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)

            HeaderDragCaptureView(
                onChanged: onMoveChanged,
                onEnded: onMoveEnded
            )
        }
        .frame(width: 28, height: 28)
        .help("Drag chat")
        .accessibilityLabel("Drag chat")
    }

    private var stopTurnUnavailableReason: String? {
        if isStoppingTurn {
            return "Stop request is already in progress."
        }
        if !canStopTurn {
            return "This thread is not currently running or its machine is disconnected."
        }
        return nil
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                onMoveChanged(value.translation)
            }
            .onEnded { value in
                onMoveEnded(value.translation)
            }
    }

    private var transcriptFilterBar: some View {
        TranscriptFilterBar(
            selection: $activeRowCategories,
            rowCounts: transcriptCategoryCounts
        )
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            let navigationEntries = userMessageNavigationEntries

            ZStack(alignment: .leading) {
                ScrollView {
                    let messages = displayMessages
                    let timeline = displayTimeline
                    let filteredMessages = messages.filter { $0.transcriptRowCategories.isDisjoint(with: activeRowCategories) == false }
                    let categoryCounts = transcriptCategoryCounts
                    let canLoadOlder = transcript?.nextCursor?.isEmpty == false
                    let hasLoadedMessages = !messages.isEmpty || timeline?.turns.isEmpty == false
                    let visibleFilterCount = activeRowCategories.reduce(0) { partial, category in
                        partial + (categoryCounts[category] ?? 0)
                    }
                    let hasFilterableContent = categoryCounts.values.contains { $0 > 0 }

                    LazyVStack(alignment: .leading, spacing: 10) {
                        if activeRowCategories.contains(.progress), isLoading, !hasLoadedMessages {
                            LoadingTranscriptRow(phase: loadPhase)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 30)
                        } else if activeRowCategories.contains(.progress), isLoading || isLoadingOlder {
                            LoadingTranscriptRow(phase: isLoadingOlder ? .loadingOlder : loadPhase, compact: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if canLoadOlder {
                            FeedbackButton(
                                unavailableReason: isLoadingOlder ? "Older messages are already loading." : nil,
                                action: {
                                    pendingOlderAnchorID = filteredMessages.first?.id ?? messages.first?.id
                                    onLoadOlder()
                                }
                            ) {
                                OlderMessagesButtonLabel(isLoading: isLoadingOlder)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .center)
                        }

                        if activeRowCategories.contains(.system), let errorMessage {
                            TranscriptErrorBanner(
                                message: errorMessage,
                                hasCachedTranscript: hasLoadedMessages,
                                onRetry: onRefresh,
                                onUseCached: onUseCachedTranscript
                            )
                        }

                        if let timeline, !timeline.turns.isEmpty {
                            ForEach(timeline.turns) { turn in
                                if let navigationMessageID = turn.items.first(where: { $0.message.role == .user })?.message.id {
                                    ThreadUserMessageNavigationTarget(messageID: navigationMessageID) {
                                        ThreadTurnSectionView(turn: turn, activeCategories: activeRowCategories)
                                    }
                                } else {
                                    ThreadTurnSectionView(turn: turn, activeCategories: activeRowCategories)
                                }
                            }
                        } else {
                            ForEach(filteredMessages) { message in
                                if message.role == .user {
                                    ThreadUserMessageNavigationTarget(messageID: message.id) {
                                        ThreadMessageRow(message: message)
                                            .id(message.id)
                                    }
                                } else {
                                    ThreadMessageRow(message: message)
                                        .id(message.id)
                                }
                            }
                        }

                        if activeRowCategories.contains(.messages), !liveAssistantText.isEmpty {
                            ThreadMessageRow(
                                message: ThreadMessage(
                                    role: .assistant,
                                    text: liveAssistantText
                                )
                            )
                            .id("live-assistant")
                        }

                        if activeRowCategories.contains(.approvals), !attentionRequests.isEmpty {
                            ForEach(attentionRequests) { request in
                                VStack(alignment: .leading, spacing: 6) {
                                    TranscriptCategoryPill(category: .approvals, title: "Approval")

                                    AttentionRequestCardView(
                                        request: request,
                                        onFocus: onFocusAttention,
                                        onRespond: onRespondToAttention,
                                        onRespondWithText: onRespondToAttentionWithText,
                                        onDeclineTyped: onDeclineTypedAttention
                                    )
                                }
                                .id("attention-\(request.id)")
                            }
                        }

                        if hasFilterableContent, visibleFilterCount == 0 {
                            FilteredTranscriptEmptyState(selection: $activeRowCategories)
                                .frame(maxWidth: .infinity, minHeight: 180)
                        }

                        if activeRowCategories.contains(.system), transcript?.messages.isEmpty != false, liveAssistantText.isEmpty, !isLoading, !isAwaitingResponse {
                            ContentUnavailableView(
                                "No loaded turns",
                                systemImage: "text.bubble",
                                description: Text("Send the first message or refresh after the thread starts responding.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 220)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(Self.messageBottomAnchorID)
                    }
                    .padding(.top, 14)
                    .padding(.trailing, 14)
                    .padding(.bottom, 14)
                    .padding(.leading, navigationEntries.isEmpty ? 14 : 42)
                }
                .coordinateSpace(name: ThreadUserMessageNavigationLayout.coordinateSpaceName)
                .onPreferenceChange(ThreadUserMessageNavigationAnchorPreferenceKey.self) { positions in
                    updateCurrentUserMessageNavigationID(from: positions, entries: navigationEntries)
                }
                .onChange(of: navigationEntries.map(\.id)) { _, entryIDs in
                    if entryIDs.isEmpty {
                        currentUserMessageNavigationID = nil
                    } else if currentUserMessageNavigationID.map(entryIDs.contains) != true {
                        currentUserMessageNavigationID = entryIDs.first
                    }
                }

                if !navigationEntries.isEmpty {
                    ThreadUserMessageNavigationRail(
                        entries: navigationEntries,
                        currentEntryID: currentUserMessageNavigationID
                    ) { entry in
                        scrollToUserMessage(entry, with: proxy)
                    }
                    .frame(width: 36)
                    .padding(.leading, 2)
                    .padding(.vertical, 10)
                }
            }
            .onChange(of: transcript?.messages.last?.id) { _, id in
                guard let id else { return }
                scrollToMessageEnd(id, with: proxy)
            }
            .onChange(of: messageListRevision) { _, _ in
                scrollToBottom(with: proxy)
            }
            .onChange(of: liveAssistantText) { _, _ in
                scrollToBottom(with: proxy)
            }
            .onChange(of: transcript?.messages.first?.id) { _, _ in
                guard let anchorID = pendingOlderAnchorID else { return }
                pendingOlderAnchorID = nil
                withAnimation(.snappy) {
                    proxy.scrollTo(anchorID, anchor: .top)
                }
            }
            .onChange(of: isAwaitingResponse) { _, isAwaiting in
                guard isAwaiting else { return }
                scrollToBottom(with: proxy)
            }
            .task(id: threadIdentity) {
                scrollToBottom(with: proxy, animated: false)
            }
        }
    }

    private var userMessageNavigationEntries: [ThreadUserMessageNavigationEntry] {
        guard activeRowCategories.contains(.messages) else {
            return []
        }

        if let timeline = displayTimeline, !timeline.turns.isEmpty {
            return timeline.turns
                .compactMap { turn -> (ThreadMessage, [ThreadTurnItem])? in
                    guard let userItem = turn.items.first(where: { $0.message.role == .user }) else {
                        return nil
                    }
                    return (userItem.message, turn.items)
                }
                .enumerated()
                .map { offset, turn in
                    ThreadUserMessageNavigationEntry(
                        userMessage: turn.0,
                        turnItems: turn.1,
                        index: offset + 1
                    )
                }
        }

        var groupedMessages: [(user: ThreadMessage, messages: [ThreadMessage])] = []
        var currentUser: ThreadMessage?
        var currentMessages: [ThreadMessage] = []
        for message in displayMessages {
            if message.role == .user {
                if let currentUser {
                    groupedMessages.append((currentUser, currentMessages))
                }
                currentUser = message
                currentMessages = [message]
            } else if currentUser != nil {
                currentMessages.append(message)
            }
        }
        if let currentUser {
            groupedMessages.append((currentUser, currentMessages))
        }

        return groupedMessages.enumerated().map { offset, group in
            ThreadUserMessageNavigationEntry(
                userMessage: group.user,
                messages: group.messages,
                index: offset + 1
            )
        }
    }

    private var displayMessages: [ThreadMessage] {
        (transcript?.messages ?? []).enumerated()
            .sorted { lhs, rhs in
                if lhs.element.createdAt == rhs.element.createdAt {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.createdAt < rhs.element.createdAt
            }
            .map(\.element)
    }

    private var displayTimeline: ThreadTurnTimeline? {
        guard let threadRef = transcript?.threadRef else {
            return nil
        }
        if let timeline = transcript?.turnTimeline, !timeline.turns.isEmpty {
            return timeline
        }
        return ThreadTurnTimeline.fromTranscript(
            ThreadTranscript(
                threadRef: threadRef,
                messages: displayMessages,
                nextCursor: transcript?.nextCursor
            )
        )
    }

    private var transcriptCategoryCounts: [TranscriptRowCategory: Int] {
        var counts = Dictionary(uniqueKeysWithValues: TranscriptRowCategory.allCases.map { ($0, 0) })

        if errorMessage != nil {
            counts[.system, default: 0] += 1
        }

        counts[.approvals, default: 0] += attentionRequests.count

        if let timeline = displayTimeline, !timeline.turns.isEmpty {
            for turn in timeline.turns {
                if turn.shouldShowTranscriptHeader {
                    counts[.system, default: 0] += 1
                }
                if turn.items.isEmpty {
                    counts[.system, default: 0] += 1
                }
                for item in turn.items {
                    incrementCounts(&counts, for: item.transcriptRowCategories)
                }
            }
        } else {
            for message in displayMessages {
                incrementCounts(&counts, for: message.transcriptRowCategories)
            }
        }

        if !liveAssistantText.isEmpty {
            counts[.messages, default: 0] += 1
        }

        return counts
    }

    private var headerRunStatus: ThreadRunStatus {
        if !attentionRequests.isEmpty || liveStateSummary?.tone == .waiting {
            return .needsInput
        }
        if !liveAssistantText.isEmpty || isAwaitingResponse || liveStateSummary?.tone == .working {
            return .running
        }
        if liveStateSummary?.tone == .failed {
            return .failed
        }
        if liveStateSummary?.tone == .finished {
            return .complete
        }
        return node.metadata.runStatus ?? .idle
    }

    private func incrementCounts(
        _ counts: inout [TranscriptRowCategory: Int],
        for categories: Set<TranscriptRowCategory>
    ) {
        for category in categories {
            counts[category, default: 0] += 1
        }
    }

    private var messageListRevision: String {
        let messages = displayMessages
            .map { message in
                return "\(message.id):\(Int(message.createdAt.timeIntervalSinceReferenceDate * 1000)):\(message.text.count)"
            }
            .joined(separator: "|")
        let artifactRevision = (transcript?.primaryArtifactAttachments ?? [])
            .map { "\($0.id):\($0.status ?? ""):\($0.cachedPath ?? ""):\($0.byteCount ?? 0)" }
            .joined(separator: "|")
        let timeline = displayTimeline?.turns
            .flatMap(\.items)
            .map { item in
                let attachmentRevision = item.effectiveAttachments
                    .map { "\($0.id):\($0.status ?? ""):\($0.cachedPath ?? ""):\($0.byteCount ?? 0)" }
                    .joined(separator: ",")
                return "\(item.id):\(item.kind.rawValue):\(attachmentRevision)"
            }
            .joined(separator: "|") ?? ""
        return "\(threadIdentity)#\(messages)#artifacts:\(artifactRevision)#timeline:\(timeline)#live:\(liveAssistantText.count)#await:\(isAwaitingResponse)"
    }

    private func scrollToMessageEnd(_ messageID: String, with proxy: ScrollViewProxy) {
        guard pendingOlderAnchorID == nil else { return }
        guard !isManualTranscriptNavigationActive else { return }
        withAnimation(.snappy) {
            proxy.scrollTo(messageID, anchor: .bottom)
        }
        scrollToBottom(with: proxy)
    }

    private func scrollToBottom(with proxy: ScrollViewProxy, animated: Bool = true) {
        guard pendingOlderAnchorID == nil else { return }
        guard !isManualTranscriptNavigationActive else { return }
        let action = {
            proxy.scrollTo(Self.messageBottomAnchorID, anchor: .bottom)
        }
        if animated {
            withAnimation(.snappy) {
                action()
            }
        } else {
            action()
        }
    }

    private func scrollToUserMessage(_ entry: ThreadUserMessageNavigationEntry, with proxy: ScrollViewProxy) {
        pendingOlderAnchorID = nil
        currentUserMessageNavigationID = entry.id
        manualTranscriptNavigationStartedAt = Date()
        proxy.scrollTo(entry.scrollAnchorID, anchor: .top)
    }

    private var isManualTranscriptNavigationActive: Bool {
        guard let manualTranscriptNavigationStartedAt else {
            return false
        }
        return Date().timeIntervalSince(manualTranscriptNavigationStartedAt) < 2.0
    }

    private func updateCurrentUserMessageNavigationID(
        from positions: [ThreadUserMessageNavigationAnchorPosition],
        entries: [ThreadUserMessageNavigationEntry]
    ) {
        let entryIDs = entries.map(\.id)
        guard !entryIDs.isEmpty else {
            currentUserMessageNavigationID = nil
            return
        }

        let positionsByID = positions.reduce(into: [String: CGFloat]()) { partial, position in
            partial[position.id] = position.minY
        }
        let orderedPositions = entries.compactMap { entry -> (id: String, minY: CGFloat)? in
            guard let minY = positionsByID[entry.id] else {
                return nil
            }
            return (entry.id, minY)
        }

        guard !orderedPositions.isEmpty else {
            if currentUserMessageNavigationID.map(entryIDs.contains) != true {
                currentUserMessageNavigationID = entryIDs.first
            }
            return
        }

        let topThreshold: CGFloat = 32
        if let activePosition = orderedPositions
            .filter({ $0.minY <= topThreshold })
            .max(by: { lhs, rhs in lhs.minY < rhs.minY }) {
            if currentUserMessageNavigationID != activePosition.id {
                currentUserMessageNavigationID = activePosition.id
            }
        } else if currentUserMessageNavigationID.map(entryIDs.contains) != true {
            currentUserMessageNavigationID = orderedPositions.min { lhs, rhs in lhs.minY < rhs.minY }?.id
                ?? entryIDs.first
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if let model = node.metadata.model {
                    Label(model, systemImage: "cpu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let effort = node.metadata.reasoningEffort {
                    Label(effort, systemImage: "dial.medium")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    composerAttachmentToolbar

                    if !pendingAttachments.isEmpty {
                        pendingAttachmentTray
                    }

                    MentionComposerView(
                        text: $draft,
                        runtimeStore: runtimeStore,
                        placeholder: "Message this thread",
                        fileRoot: mentionFileRoot,
                        extraCandidates: threadMentionCandidates,
                        minLines: 3,
                        maxLines: 8,
                        isDisabled: isAwaitingResponse || isSubmitting,
                        usesLocalMentionCatalog: usesLocalMentionCatalog,
                        onSubmit: sendDraft
                    )

                    if let attachmentError {
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
                        unavailableReason: sendUnavailableReason,
                        action: sendDraft
                    ) {
                        Image(systemName: "paperplane.fill")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .help(sendUnavailableReason ?? "Send")
                }
            }
        }
        .padding(14)
        #if os(iOS)
        .padding(.bottom, isFullScreen ? 10 : 0)
        #endif
    }

    private var showsStopTurnButton: Bool {
        headerRunStatus == .running || canStopTurn || isStoppingTurn
    }

    private var stopTurnButton: some View {
        FeedbackButton(
            unavailableReason: stopTurnUnavailableReason,
            action: onStopTurn
        ) {
            Image(systemName: isStoppingTurn ? "stop.circle" : "stop.fill")
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.bordered)
        .foregroundStyle(.red)
        .help(stopTurnUnavailableReason ?? "Stop running turn")
        .accessibilityLabel(isStoppingTurn ? "Stopping turn" : "Stop running turn")
    }

    private var composerAttachmentToolbar: some View {
        HStack(spacing: 8) {
            Button {
                isFileImporterPresented = true
            } label: {
                Image(systemName: "paperclip")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(isAwaitingResponse || isSubmitting)
            .help("Attach files")
            .accessibilityLabel("Attach files")

            Button {
                pasteAttachmentsFromClipboard()
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .disabled(isAwaitingResponse || isSubmitting)
            .help("Paste screenshot or files")
            .accessibilityLabel("Paste screenshot or files")

            if !pendingAttachments.isEmpty {
                Text("\(pendingAttachments.count) attached")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var pendingAttachmentTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingAttachments) { attachment in
                    PendingChatAttachmentChip(
                        attachment: attachment,
                        onRemove: {
                            pendingAttachments.removeAll { $0.id == attachment.id }
                        }
                    )
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var mentionFileRoot: String? {
        if let cwd = node.metadata.threadRef?.cwd {
            return cwd
        }
        if node.subtitle.hasPrefix("/") {
            return node.subtitle
        }
        return nil
    }

    private var usesLocalMentionCatalog: Bool {
        guard let threadRef = node.metadata.threadRef else {
            return true
        }
        return threadRef.hostID == runtimeStore.localHost.id
    }

    private var threadArtifacts: [ThreadMessageAttachment] {
        (transcript?.primaryArtifactAttachments ?? [])
            .sorted {
                ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
    }

    private var artifactsUnavailableReason: String? {
        threadArtifacts.isEmpty ? "This thread has not produced any artifacts yet." : nil
    }

    private var sendUnavailableReason: String? {
        if isAwaitingResponse {
            return "This thread is still running. Wait for the current turn to finish."
        }
        if isSubmitting {
            return "This message is still being sent."
        }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty {
            return "Type a message or attach a file before sending."
        }
        return nil
    }

    private func saveRename() {
        let name = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            titleDraft = node.title
            isRenaming = false
            return
        }

        onRename(name)
        isRenaming = false
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard (!text.isEmpty || !attachments.isEmpty), !isAwaitingResponse, !isSubmitting else { return }
        let sendingIdentity = threadIdentity
        draft = ""
        pendingAttachments = []
        attachmentError = nil
        isSubmitting = true
        Task {
            let didSend = await onSend(text, attachments)
            await MainActor.run {
                guard sendingIdentity == threadIdentity else { return }
                if !didSend, draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draft = text
                }
                if !didSend, pendingAttachments.isEmpty {
                    pendingAttachments = attachments
                }
                isSubmitting = false
            }
        }
    }

    private func copyThreadID(_ threadID: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(threadID, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = threadID
        #endif
    }

    private func resetPopoverStateForCurrentThread() {
        draft = ""
        isRenaming = false
        titleDraft = node.title
        pendingOlderAnchorID = nil
        isArtifactsPresented = false
        isSubmitting = false
        pendingAttachments = []
        attachmentError = nil
        activeRowCategories = Set(TranscriptRowCategory.allCases)
    }

    private func appendFileAttachments(from urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            do {
                let attachments = try await Self.attachments(from: urls)
                await MainActor.run {
                    pendingAttachments.append(contentsOf: attachments)
                    attachmentError = nil
                }
            } catch {
                await MainActor.run {
                    attachmentError = error.localizedDescription
                }
            }
        }
    }

    private static func attachments(from urls: [URL]) async throws -> [ChatInputAttachment] {
        try await Task.detached(priority: .utility) {
            try urls.map { url in
                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let data = try Data(contentsOf: url)
                try ChatInputAttachmentService.validateSize(data.count, name: url.lastPathComponent)
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
            let name = "screenshot-\(Int(Date().timeIntervalSince1970 * 1000)).png"
            pendingAttachments.append(
                ChatInputAttachment(
                    kind: .image,
                    name: name,
                    mimeType: "image/png",
                    data: data,
                    byteCount: data.count
                )
            )
            didAttach = true
        }

        if !didAttach {
            attachmentError = "Clipboard does not contain a file or screenshot."
        } else {
            attachmentError = nil
        }
        #elseif os(iOS)
        if let image = UIPasteboard.general.image,
           let data = image.pngData() {
            let name = "screenshot-\(Int(Date().timeIntervalSince1970 * 1000)).png"
            pendingAttachments.append(
                ChatInputAttachment(
                    kind: .image,
                    name: name,
                    mimeType: "image/png",
                    data: data,
                    byteCount: data.count
                )
            )
            attachmentError = nil
        } else if let url = UIPasteboard.general.url, url.isFileURL {
            appendFileAttachments(from: [url])
        } else {
            attachmentError = "Clipboard does not contain a file or screenshot."
        }
        #endif
    }
}

private struct OlderMessagesButtonLabel: View {
    var isLoading: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Text(isLoading ? "Loading older messages" : "Show older messages")
                .font(.caption.weight(.semibold))
        }
    }
}

private struct TranscriptFilterBar: View {
    @Binding var selection: Set<TranscriptRowCategory>
    var rowCounts: [TranscriptRowCategory: Int]

    private var allCategories: Set<TranscriptRowCategory> {
        Set(TranscriptRowCategory.allCases)
    }

    private var selectedCategories: [TranscriptRowCategory] {
        TranscriptRowCategory.allCases.filter { selection.contains($0) }
    }

    private var isShowingAll: Bool {
        selection == allCategories
    }

    private var filterSummary: String {
        guard !isShowingAll else {
            return "All rows"
        }
        if selectedCategories.count > 2 {
            return "\(selectedCategories.count) filters"
        }
        return selectedCategories.map(\.compactTitle).joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    selection = allCategories
                } label: {
                    Label("Show all rows", systemImage: "checklist")
                }

                Divider()

                ForEach(TranscriptRowCategory.allCases) { category in
                    Toggle(isOn: binding(for: category)) {
                        Label(menuTitle(for: category), systemImage: category.iconName)
                    }
                }
            } label: {
                Label(filterSummary, systemImage: "line.3.horizontal.decrease.circle")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .menuStyle(.button)
            .controlSize(.small)
            .help("Filter transcript rows")

            if !isShowingAll {
                Text(selectedCategories.map(\.title).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button {
                    selection = allCategories
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Show all transcript rows")
                .accessibilityLabel("Show all transcript rows")
            } else {
                Text("Messages, progress, thoughts, tools, artifacts, approvals, events")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func binding(for category: TranscriptRowCategory) -> Binding<Bool> {
        Binding {
            selection.contains(category)
        } set: { isSelected in
            var next = selection
            if isSelected {
                next.insert(category)
            } else if next.count > 1 {
                next.remove(category)
            }
            selection = next
        }
    }

    private func menuTitle(for category: TranscriptRowCategory) -> String {
        "\(category.title) (\(rowCounts[category] ?? 0))"
    }
}

private struct TranscriptCategoryPill: View {
    var category: TranscriptRowCategory
    var title: String?

    var body: some View {
        Label(title ?? category.compactTitle, systemImage: category.iconName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(category.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(category.tint.opacity(0.11), in: Capsule())
    }
}

private struct FilteredTranscriptEmptyState: View {
    @Binding var selection: Set<TranscriptRowCategory>

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("No rows match the active filters")
                .font(.callout.weight(.semibold))

            Button {
                selection = Set(TranscriptRowCategory.allCases)
            } label: {
                Label("Show All Rows", systemImage: "checklist")
            }
            .controlSize(.small)
        }
        .foregroundStyle(.secondary)
        .padding(18)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ThreadHeaderRunStatusPill: View {
    var status: ThreadRunStatus
    var isUnread: Bool
    var updatedAt: Date?

    var body: some View {
        Label(label, systemImage: iconName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.11), in: Capsule())
            .help(helpText)
            .accessibilityLabel(label)
    }

    private var label: String {
        if isUnread {
            return "unread"
        }
        switch status {
        case .running:
            return "running"
        case .needsInput:
            return "needs input"
        case .failed:
            return "failed"
        case .complete:
            return "complete"
        case .idle:
            return "idle"
        case .unknown:
            return "unknown"
        }
    }

    private var iconName: String {
        if isUnread {
            return "circle.fill"
        }
        switch status {
        case .running:
            return "arrow.triangle.2.circlepath"
        case .needsInput:
            return "exclamationmark.bubble"
        case .failed:
            return "xmark.octagon"
        case .complete:
            return "checkmark.circle"
        case .idle, .unknown:
            return "circle"
        }
    }

    private var color: Color {
        if isUnread {
            return .blue
        }
        switch status {
        case .running:
            return .blue
        case .needsInput:
            return .orange
        case .failed:
            return .red
        case .complete:
            return .green
        case .idle, .unknown:
            return .secondary
        }
    }

    private var helpText: String {
        guard let updatedAt else {
            return label
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "\(label), updated \(formatter.localizedString(for: updatedAt, relativeTo: Date()))"
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

private struct PendingAssistantRow: View {
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                TranscriptCategoryPill(category: .progress, title: "Progress")

                HStack(spacing: 8) {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)

                    Text("Waiting for response")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))

            Spacer(minLength: 40)
        }
    }
}

private struct LoadingTranscriptRow: View {
    var phase: TranscriptLoadPhase
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    TranscriptCategoryPill(category: .progress, title: compact ? "Progress" : nil)

                    Label(phase.title, systemImage: phase.iconName)
                        .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if !phase.detail.isEmpty {
                    Text(phase.detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(compact ? 8 : 10)
        .background(Color.teal.opacity(compact ? 0.07 : 0.09), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TranscriptErrorBanner: View {
    var message: String
    var hasCachedTranscript: Bool
    var onRetry: () -> Void
    var onUseCached: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Transcript unavailable")
                        .font(.caption.weight(.semibold))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 8) {
                Button("Retry", action: onRetry)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)

                if hasCachedTranscript {
                    Button("Use Cached Transcript", action: onUseCached)
                        .controlSize(.small)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ThreadUserMessageNavigationEntry: Identifiable, Hashable {
    var id: String
    var index: Int
    var userPreview: String
    var responsePreview: String?
    var artifactSummary: ArtifactSummary?
    var timestampText: String

    init(userMessage: ThreadMessage, turnItems: [ThreadTurnItem], index: Int) {
        self.id = userMessage.id
        self.index = index
        self.userPreview = Self.previewText(for: userMessage.text, limit: 96)
        self.responsePreview = Self.responsePreview(in: turnItems)
        self.artifactSummary = ArtifactSummary(attachments: Self.deduplicatedAttachments(
            turnItems.flatMap(\.effectiveAttachments)
        ))
        self.timestampText = userMessage.createdAt.formatted(date: .omitted, time: .shortened)
    }

    init(userMessage: ThreadMessage, messages: [ThreadMessage], index: Int) {
        self.id = userMessage.id
        self.index = index
        self.userPreview = Self.previewText(for: userMessage.text, limit: 96)
        self.responsePreview = messages.first {
            $0.role == .assistant && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.map { Self.previewText(for: $0.text, limit: 150) }
        self.artifactSummary = ArtifactSummary(attachments: Self.deduplicatedAttachments(
            messages.flatMap(\.attachments)
        ))
        self.timestampText = userMessage.createdAt.formatted(date: .omitted, time: .shortened)
    }

    var title: String {
        "Message \(index)"
    }

    var scrollAnchorID: String {
        Self.scrollAnchorID(for: id)
    }

    var accessibilityLabel: String {
        "\(title), \(userPreview)"
    }

    static func scrollAnchorID(for messageID: String) -> String {
        "thread-user-message-navigation-\(messageID)"
    }

    private static func responsePreview(in items: [ThreadTurnItem]) -> String? {
        items.first {
            $0.message.role == .assistant && !$0.message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.map { previewText(for: $0.message.text, limit: 150) }
    }

    private static func previewText(for text: String, limit: Int) -> String {
        let collapsed = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !collapsed.isEmpty else {
            return "Empty message"
        }
        guard collapsed.count > limit else {
            return collapsed
        }
        return "\(collapsed.prefix(limit))..."
    }

    private static func deduplicatedAttachments(_ attachments: [ThreadMessageAttachment]) -> [ThreadMessageAttachment] {
        var seen = Set<String>()
        return attachments.filter { attachment in
            seen.insert(artifactKey(attachment)).inserted
        }
    }

    private static func artifactKey(_ attachment: ThreadMessageAttachment) -> String {
        [
            attachment.kind.rawValue,
            attachment.sourceHostID.rawValue,
            attachment.sourcePath ?? attachment.cachedPath ?? attachment.title ?? attachment.id,
            attachment.diffText ?? "",
        ].joined(separator: "::")
    }

    struct ArtifactSummary: Hashable {
        var title: String
        var fileNames: [String]
        var extraCount: Int
        var added: Int
        var removed: Int

        init?(attachments: [ThreadMessageAttachment]) {
            guard !attachments.isEmpty else {
                return nil
            }

            let changedAttachments = attachments.filter { $0.kind == .diff || $0.kind == .file }
            let displayedAttachments = changedAttachments.isEmpty ? attachments : changedAttachments
            let names = displayedAttachments
                .map { attachment in
                    artifactFileName(attachment.sourcePath ?? attachment.cachedPath ?? attachment.title ?? attachment.kind.rawValue)
                }
                .filter { !$0.isEmpty }
            let uniqueNames = names.reduce(into: [String]()) { partial, name in
                if partial.contains(name) == false {
                    partial.append(name)
                }
            }
            let stats = attachments.compactMap { attachment in
                attachment.diffText.map(DiffStats.init(diffText:))
            }

            let count = max(uniqueNames.count, displayedAttachments.count)
            if changedAttachments.isEmpty {
                self.title = "\(attachments.count) artifact\(attachments.count == 1 ? "" : "s")"
            } else {
                self.title = "Edited \(count) file\(count == 1 ? "" : "s")"
            }
            let visibleNames = Array(uniqueNames.prefix(2))
            self.fileNames = visibleNames
            self.extraCount = max(uniqueNames.count - visibleNames.count, 0)
            self.added = stats.reduce(0) { $0 + $1.added }
            self.removed = stats.reduce(0) { $0 + $1.removed }
        }
    }
}

private struct ThreadUserMessageNavigationTarget<Content: View>: View {
    var messageID: String
    private var content: Content

    init(messageID: String, @ViewBuilder content: () -> Content) {
        self.messageID = messageID
        self.content = content()
    }

    var body: some View {
        content
            .id(ThreadUserMessageNavigationEntry.scrollAnchorID(for: messageID))
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ThreadUserMessageNavigationAnchorPreferenceKey.self,
                        value: [
                            ThreadUserMessageNavigationAnchorPosition(
                                id: messageID,
                                minY: proxy.frame(in: .named(ThreadUserMessageNavigationLayout.coordinateSpaceName)).minY
                            )
                        ]
                    )
                }
            }
    }
}

private enum ThreadUserMessageNavigationLayout {
    static let coordinateSpaceName = "thread-user-message-navigation-scroll"
}

private struct ThreadUserMessageNavigationAnchorPosition: Equatable {
    var id: String
    var minY: CGFloat
}

private struct ThreadUserMessageNavigationAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [ThreadUserMessageNavigationAnchorPosition] = []

    static func reduce(
        value: inout [ThreadUserMessageNavigationAnchorPosition],
        nextValue: () -> [ThreadUserMessageNavigationAnchorPosition]
    ) {
        value.append(contentsOf: nextValue())
    }
}

private struct ThreadUserMessageNavigationRail: View {
    var entries: [ThreadUserMessageNavigationEntry]
    var currentEntryID: String?
    var onSelect: (ThreadUserMessageNavigationEntry) -> Void

    @State private var hoveredEntryID: String?

    private let horizontalCenter: CGFloat = 18
    private let verticalPadding: CGFloat = 14
    private let previewHeight: CGFloat = 132

    var body: some View {
        GeometryReader { proxy in
            let height = max(proxy.size.height, 1)

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(.secondary.opacity(0.18))
                    .frame(width: 2, height: max(height - verticalPadding * 2, 1))
                    .position(x: horizontalCenter, y: height / 2)

                ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                    let isHovered = hoveredEntryID == entry.id
                    let isCurrent = currentEntryID == entry.id
                    let y = yPosition(index: offset, count: entries.count, height: height)

                    Capsule()
                        .fill(tickColor(isHovered: isHovered, isCurrent: isCurrent))
                        .frame(
                            width: tickWidth(isHovered: isHovered, isCurrent: isCurrent),
                            height: tickHeight(isHovered: isHovered, isCurrent: isCurrent)
                        )
                        .shadow(color: isCurrent ? Color.primary.opacity(0.18) : .clear, radius: 4)
                        .animation(.snappy, value: isHovered)
                        .animation(.snappy, value: isCurrent)
                        .position(x: horizontalCenter, y: y)
                }

                if let hoveredEntry,
                   let offset = entries.firstIndex(of: hoveredEntry) {
                    ThreadUserMessageNavigationPreview(entry: hoveredEntry)
                        .offset(
                            x: horizontalCenter + 18,
                            y: previewOffsetY(
                                index: offset,
                                count: entries.count,
                                height: height
                            )
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
                        .allowsHitTesting(false)
                }

                railInteractionLayer(height: height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .animation(.snappy, value: hoveredEntryID)
        .animation(.snappy, value: currentEntryID)
    }

    private var hoveredEntry: ThreadUserMessageNavigationEntry? {
        guard let hoveredEntryID else {
            return nil
        }
        return entries.first { $0.id == hoveredEntryID }
    }

    @ViewBuilder
    private func railInteractionLayer(height: CGFloat) -> some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(hoveredEntry?.accessibilityLabel ?? "User message navigation")
            .accessibilityHint("Click to jump to the nearest user message")
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        hoveredEntryID = nearestEntry(toY: value.location.y, height: height)?.id
                    }
                    .onEnded { value in
                        guard let entry = nearestEntry(toY: value.location.y, height: height) else {
                            return
                        }
                        hoveredEntryID = entry.id
                        onSelect(entry)
                    }
            )
            #if os(macOS)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredEntryID = nearestEntry(toY: location.y, height: height)?.id
                case .ended:
                    hoveredEntryID = nil
                }
            }
            #endif
    }

    private func tickColor(isHovered: Bool, isCurrent: Bool) -> Color {
        if isHovered {
            return .accentColor
        }
        if isCurrent {
            return .primary.opacity(0.95)
        }
        return .secondary.opacity(0.58)
    }

    private func tickWidth(isHovered: Bool, isCurrent: Bool) -> CGFloat {
        if isHovered {
            return 20
        }
        if isCurrent {
            return 24
        }
        return 10
    }

    private func tickHeight(isHovered: Bool, isCurrent: Bool) -> CGFloat {
        if isHovered || isCurrent {
            return 4
        }
        return 3
    }

    private func yPosition(index: Int, count: Int, height: CGFloat) -> CGFloat {
        guard count > 1 else {
            return height / 2
        }

        let available = max(height - verticalPadding * 2, 1)
        let fraction = CGFloat(index) / CGFloat(count - 1)
        return verticalPadding + available * fraction
    }

    private func nearestEntry(toY y: CGFloat, height: CGFloat) -> ThreadUserMessageNavigationEntry? {
        guard !entries.isEmpty else {
            return nil
        }
        guard entries.count > 1 else {
            return entries.first
        }

        let available = max(height - verticalPadding * 2, 1)
        let clampedY = min(max(y, verticalPadding), height - verticalPadding)
        let fraction = (clampedY - verticalPadding) / available
        let index = Int((fraction * CGFloat(entries.count - 1)).rounded())
        return entries[min(max(index, 0), entries.count - 1)]
    }

    private func previewOffsetY(index: Int, count: Int, height: CGFloat) -> CGFloat {
        let y = yPosition(index: index, count: count, height: height) - previewHeight / 2
        return min(max(y, 0), max(height - previewHeight, 0))
    }
}

private struct ThreadUserMessageNavigationPreview: View {
    var entry: ThreadUserMessageNavigationEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(entry.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(entry.timestampText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Text(entry.userPreview)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(entry.responsePreview ?? "No assistant response loaded yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let artifactSummary = entry.artifactSummary {
                ThreadUserMessageNavigationArtifactSummaryView(summary: artifactSummary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
    }
}

private struct ThreadUserMessageNavigationArtifactSummaryView: View {
    var summary: ThreadUserMessageNavigationEntry.ArtifactSummary

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "doc.badge.plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(summary.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if summary.added > 0 || summary.removed > 0 {
                        HStack(spacing: 3) {
                            Text("+\(summary.added)")
                                .foregroundStyle(.green)
                            Text("-\(summary.removed)")
                                .foregroundStyle(.red)
                        }
                        .font(.caption2.weight(.semibold).monospacedDigit())
                    }
                }

                HStack(spacing: 6) {
                    ForEach(summary.fileNames, id: \.self) { fileName in
                        Text(fileName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if summary.extraCount > 0 {
                        Text("+\(summary.extraCount)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ThreadTurnSectionView: View {
    var turn: ThreadTurn
    var activeCategories: Set<TranscriptRowCategory>

    var body: some View {
        let visibleItems = turn.visibleTranscriptItems(for: activeCategories)
        let showsHeader = shouldShowHeader && activeCategories.contains(.system)

        if showsHeader || !visibleItems.isEmpty || (turn.items.isEmpty && activeCategories.contains(.system)) {
            VStack(alignment: .leading, spacing: 8) {
                if showsHeader {
                    turnHeader
                }

                if turn.items.isEmpty {
                    EmptyTurnDetailsView(turn: turn)
                } else {
                    ForEach(visibleItems) { item in
                        ThreadMessageRow(item: item)
                            .id(item.message.id)
                    }
                }
            }
        }
    }

    private var turnHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                TranscriptCategoryPill(category: .system, title: "Event")

                Image(systemName: iconName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)

                Text(headerTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(turn.itemsView.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.10), in: Capsule())

                if let duration = turn.duration {
                    Text(durationText(duration))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                Text(turn.startedAt, format: .dateTime.month(.abbreviated).day().hour().minute().second())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            if let completedAt = turn.completedAt {
                Text("Completed \(completedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            if let error = turn.error?.nilIfBlank {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 8)
    }

    private var shouldShowHeader: Bool {
        turn.shouldShowTranscriptHeader
    }

    private var headerTitle: String {
        switch turn.status {
        case .running:
            return "Turn running"
        case .needsInput:
            return "Turn needs you"
        case .failed:
            return "Turn failed"
        case .complete:
            return "Turn"
        case .idle:
            return "Thread context"
        case .unknown:
            return "Thread update"
        }
    }

    private var iconName: String {
        switch turn.status {
        case .running:
            return "arrow.triangle.2.circlepath"
        case .needsInput:
            return "hand.raised"
        case .failed:
            return "xmark.circle"
        case .complete:
            return "checkmark.circle"
        case .idle:
            return "text.bubble"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch turn.status {
        case .running:
            return .blue
        case .needsInput:
            return .orange
        case .failed:
            return .red
        case .complete:
            return .secondary
        case .idle:
            return .secondary
        case .unknown:
            return .secondary
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "\(Int(duration * 1000)) ms"
        }
        return String(format: "%.1fs", duration)
    }

}

private extension ThreadTurn {
    var shouldShowTranscriptHeader: Bool {
        items.isEmpty
            || itemsView != .full
            || error?.isEmpty == false
            || duration != nil
            || completedAt != nil
            || items.count > 2
            || items.contains { $0.kind == .tool || $0.kind.isArtifact }
    }

    func visibleTranscriptItems(for categories: Set<TranscriptRowCategory>) -> [ThreadTurnItem] {
        items.filter { $0.matchesTranscriptFilter(categories) }
    }
}

private struct EmptyTurnDetailsView: View {
    var turn: ThreadTurn

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: placeholderIcon)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(placeholderText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var placeholderIcon: String {
        switch turn.status {
        case .running:
            return "ellipsis.message"
        case .failed:
            return "exclamationmark.triangle"
        default:
            return "text.badge.xmark"
        }
    }

    private var placeholderText: String {
        switch turn.itemsView {
        case .notLoaded:
            return "Turn items are not loaded yet."
        case .summary:
            return "Only summary details are loaded for this turn."
        case .full:
            if turn.status == .running {
                return "Turn is running; no message items have arrived yet."
            }
            return "No message items were available for this turn."
        }
    }
}

private extension ThreadTurnItemsView {
    var displayName: String {
        switch self {
        case .notLoaded:
            return "not loaded"
        case .summary:
            return "summary"
        case .full:
            return "full"
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ThreadMessageRow: View {
    var item: ThreadTurnItem

    @State private var isExpanded = false

    init(item: ThreadTurnItem) {
        self.item = item
    }

    init(message: ThreadMessage) {
        self.item = ThreadTurnItem(
            id: message.id,
            kind: Self.kind(for: message),
            message: message,
            attachments: message.attachments
        )
    }

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: .leading, spacing: 4) {
                if message.role == .tool {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    TranscriptCategoryPill(category: rowCategory, title: toolCategoryTitle)

                                    Text(toolTitle)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(roleColor)
                                        .lineLimit(1)
                                }

                                Text(toolSummary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 10)

                            Text(timestampText)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .monospacedDigit()
                                .help(fullTimestampText)

                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        Divider()
                            .opacity(0.45)

                        Text(toolBody)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    artifactGroup
                } else if message.role == .reasoning {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TranscriptCategoryPill(category: .thoughts, title: "Thought")

                            Text("Reasoning summary")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 10)

                            Text(timestampText)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .monospacedDigit()
                                .help(fullTimestampText)
                        }

                        Text(messageText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)

                        if isLongMessage {
                            Button {
                                isExpanded.toggle()
                            } label: {
                                Text(isExpanded ? "Show less" : "Show full")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if rowCategory == .progress {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            TranscriptCategoryPill(category: .progress, title: "Progress")

                            Text("Assistant update")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 10)

                            if canCopyMessage {
                                Button {
                                    copyMessage()
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .frame(width: 18, height: 18)
                                }
                                .buttonStyle(.plain)
                                .help("Copy message")
                                .disabled(message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }

                            Text(timestampText)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .monospacedDigit()
                                .help(fullTimestampText)
                        }

                        Text(messageText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)

                        if isLongMessage {
                            Button {
                                isExpanded.toggle()
                            } label: {
                                Text(isExpanded ? "Show less" : "Show full")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                        }

                        artifactGroup
                    }
                } else {
                    HStack(spacing: 8) {
                        if rowCategory == .artifacts {
                            TranscriptCategoryPill(category: .artifacts, title: "Artifact")
                        } else if rowCategory == .system {
                            TranscriptCategoryPill(category: .system, title: "System")
                        } else {
                            Text(roleLabel)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(roleColor)
                        }

                        Spacer(minLength: 12)

                        if canCopyMessage {
                            Button {
                                copyMessage()
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                            .help("Copy message")
                            .disabled(message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        Text(timestampText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .monospacedDigit()
                            .help(fullTimestampText)
                    }

                    Text(messageText)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    if isLongMessage {
                        Button {
                            isExpanded.toggle()
                        } label: {
                            Text(isExpanded ? "Show less" : "Show full")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                    }

                    artifactGroup
                }
            }
            .padding(10)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))

            if message.role != .user {
                Spacer(minLength: 40)
            }
        }
    }

    private var messageText: String {
        guard isLongMessage, !isExpanded else {
            return message.text
        }
        return String(message.text.prefix(Self.previewCharacterLimit))
    }

    private var isLongMessage: Bool {
        message.text.count > Self.previewCharacterLimit
    }

    private static let previewCharacterLimit = 1_500

    private var imageAttachments: [ThreadMessageAttachment] {
        artifactAttachments.filter { $0.kind == .image }
    }

    private var artifactAttachments: [ThreadMessageAttachment] {
        item.effectiveAttachments
    }

    @ViewBuilder
    private var artifactGroup: some View {
        if artifactAttachments.count > 1 {
            ThreadArtifactGroupView(attachments: artifactAttachments)
        } else {
            ForEach(artifactAttachments) { attachment in
                ThreadArtifactAttachmentView(attachment: attachment)
            }
        }
    }

    private var toolTitle: String {
        message.text
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? "Tool"
    }

    private var toolBody: String {
        let lines = message.text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else {
            return message.text
        }
        return lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var toolSummary: String {
        if let imageAttachment = imageAttachments.first {
            if imageAttachment.cachedPath != nil {
                return "Status: completed"
            }
            if let status = imageAttachment.status, !status.isEmpty {
                return "Status: \(status)"
            }
        }

        guard !toolBody.isEmpty else {
            return "No details"
        }

        let compact = toolBody
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return compact.isEmpty ? "Details available" : compact
    }

    private var message: ThreadMessage {
        item.message
    }

    private var rowCategory: TranscriptRowCategory {
        item.primaryTranscriptRowCategory
    }

    private static func kind(for message: ThreadMessage) -> ThreadTurnItemKind {
        if let attachment = message.attachments.first {
            switch attachment.kind {
            case .image:
                return .imageArtifact
            case .file:
                return .fileArtifact
            case .diff:
                return .diffArtifact
            }
        }

        switch message.role {
        case .user:
            return .userMessage
        case .assistant:
            return .assistantMessage
        case .reasoning:
            return .reasoning
        case .tool:
            return .tool
        case .system:
            return .system
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user:
            return "You"
        case .assistant:
            return "Codex"
        case .reasoning:
            return "Thinking"
        case .tool:
            return "Tool"
        case .system:
            return "System"
        }
    }

    private var canCopyMessage: Bool {
        message.role == .user || message.role == .assistant
    }

    private func copyMessage() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = message.text
        #endif
    }

    private var timestampText: String {
        if Calendar.current.isDate(message.createdAt, equalTo: Date(), toGranularity: .year) {
            return message.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().second())
        }
        return fullTimestampText
    }

    private var fullTimestampText: String {
        message.createdAt.formatted(.dateTime.month(.abbreviated).day().year().hour().minute().second())
    }

    private var toolCategoryTitle: String {
        rowCategory == .artifacts ? "Artifact" : "Tool"
    }

    private var roleColor: Color {
        switch rowCategory {
        case .messages:
            switch message.role {
            case .user:
                return .blue
            case .assistant:
                return .green
            case .reasoning:
                return .purple
            case .tool:
                return .orange
            case .system:
                return .secondary
            }
        case .progress, .thoughts, .tools, .artifacts, .approvals, .system:
            return rowCategory.tint
        }
    }

    private var rowBackground: Color {
        switch rowCategory {
        case .messages:
            switch message.role {
            case .user:
                return Color.blue.opacity(0.10)
            case .assistant:
                return Color.green.opacity(0.10)
            case .reasoning:
                return Color.purple.opacity(0.09)
            case .tool:
                return Color.orange.opacity(0.09)
            case .system:
                return Color.secondary.opacity(0.08)
            }
        case .progress:
            return Color.teal.opacity(0.09)
        case .thoughts:
            return Color.purple.opacity(0.09)
        case .tools:
            return Color.orange.opacity(0.09)
        case .artifacts:
            return Color.blue.opacity(0.08)
        case .approvals:
            return Color.red.opacity(0.08)
        case .system:
            return Color.secondary.opacity(0.08)
        }
    }
}

private struct ThreadArtifactAttachmentView: View {
    var attachment: ThreadMessageAttachment

    var body: some View {
        switch attachment.kind {
        case .image:
            ThreadImageAttachmentView(attachment: attachment)
        case .file:
            ThreadFileAttachmentView(attachment: attachment)
        case .diff:
            ThreadDiffAttachmentView(attachment: attachment)
        }
    }
}

private struct ThreadArtifactGroupView: View {
    var attachments: [ThreadMessageAttachment]

    @State private var isExpanded = false
    @State private var selectedAttachment: ThreadMessageAttachment?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Artifacts")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(summaryText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], spacing: 8) {
                    ForEach(attachments) { attachment in
                        Button {
                            selectedAttachment = attachment
                        } label: {
                            ArtifactGalleryTile(attachment: attachment)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(attachments.prefix(5)) { attachment in
                        ArtifactKindPill(attachment: attachment)
                    }

                    if attachments.count > 5 {
                        Text("+\(attachments.count - 5)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.secondary.opacity(0.10), in: Capsule())
                    }
                }
            }
        }
        .padding(8)
        .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.14), lineWidth: 1)
        }
        .sheet(item: $selectedAttachment) { attachment in
            ThreadArtifactPreviewView(attachment: attachment)
        }
    }

    private var summaryText: String {
        let images = attachments.filter { $0.kind == .image }.count
        let files = attachments.filter { $0.kind == .file }.count
        let diffs = attachments.filter { $0.kind == .diff }.count
        return [
            images > 0 ? "\(images) image\(images == 1 ? "" : "s")" : nil,
            files > 0 ? "\(files) file\(files == 1 ? "" : "s")" : nil,
            diffs > 0 ? "\(diffs) diff\(diffs == 1 ? "" : "s")" : nil,
        ]
        .compactMap(\.self)
        .joined(separator: " - ")
    }
}

private struct ArtifactGalleryTile: View {
    var attachment: ThreadMessageAttachment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                Text(kindLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(iconColor)
                Spacer(minLength: 0)
            }

            Text(attachment.title ?? artifactFileName(attachment.sourcePath ?? attachment.cachedPath ?? kindLabel))
                .font(.caption.weight(.semibold))
                .lineLimit(2)

            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }

    private var kindLabel: String {
        switch attachment.kind {
        case .image:
            return "Image"
        case .file:
            return "File"
        case .diff:
            return "Diff"
        }
    }

    private var iconName: String {
        switch attachment.kind {
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .diff:
            return "plus.forwardslash.minus"
        }
    }

    private var iconColor: Color {
        switch attachment.kind {
        case .image:
            return .blue
        case .file:
            return .secondary
        case .diff:
            return .orange
        }
    }

    private var statusText: String {
        if let status = attachment.status, !status.isEmpty {
            return status
        }
        if let byteCount = attachment.byteCount {
            return formattedBytes(byteCount)
        }
        return attachment.sourcePath ?? "Ready"
    }
}

private struct ArtifactKindPill: View {
    var attachment: ThreadMessageAttachment

    var body: some View {
        Label(label, systemImage: iconName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.10), in: Capsule())
    }

    private var label: String {
        switch attachment.kind {
        case .image:
            return attachment.cachedPath == nil ? "image loading" : "image"
        case .file:
            return "file"
        case .diff:
            return "diff"
        }
    }

    private var iconName: String {
        switch attachment.kind {
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .diff:
            return "plus.forwardslash.minus"
        }
    }

    private var color: Color {
        switch attachment.kind {
        case .image:
            return .blue
        case .file:
            return .secondary
        case .diff:
            return .orange
        }
    }
}

private struct ThreadImageAttachmentView: View {
    var attachment: ThreadMessageAttachment

    @State private var isExpanded = false
    @State private var isPreviewPresented = false
    @State private var platformImage: PlatformImage?
    @State private var actionMessage: String?

    var body: some View {
        artifactContent
            .padding(8)
            .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .task(id: attachment.cachedPath ?? attachment.sourcePath ?? attachment.id) {
                loadImage()
            }
            .sheet(isPresented: $isPreviewPresented) {
                ThreadImagePreviewView(
                    attachment: attachment,
                    image: platformImage,
                    statusText: statusText,
                    displayPath: displayPath,
                    onCopyImage: copyImage,
                    onCopyPath: copyPath,
                    onSaveCopy: saveCopy
                )
            }
    }

    private var artifactContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerButton

            if let platformImage {
                thumbnailButton(image: platformImage)
                actionRow
            } else {
                unavailableRow
            }

            if isExpanded {
                expandedDetails
            }
        }
    }

    private var headerButton: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.title ?? "Image")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func thumbnailButton(image: PlatformImage) -> some View {
        Button {
            isPreviewPresented = true
        } label: {
            platformImageView(image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: isExpanded ? 420 : 220)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 24, height: 24)
                        .background(.regularMaterial, in: Circle())
                        .padding(8)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(.quaternary, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help("Open larger preview")
        .contextMenu {
            imageContextMenu
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            ImageActionButton(systemName: "arrow.up.left.and.arrow.down.right", help: "Open larger preview") {
                isPreviewPresented = true
            }

            ImageActionButton(systemName: "doc.on.doc", help: "Copy image") {
                copyImage()
            }

            ImageActionButton(
                systemName: "link",
                help: "Copy image path",
                unavailableReason: displayPath == nil ? "No image path is available yet." : nil
            ) {
                copyPath()
            }

            ImageActionButton(
                systemName: "square.and.arrow.down",
                help: "Save a copy",
                unavailableReason: resolvedURL == nil ? "The image has not been cached locally yet." : nil
            ) {
                saveCopy()
            }

            Spacer(minLength: 0)

            if let actionMessage {
                Text(actionMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var unavailableRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)

            Text("Image unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let revisedPrompt = attachment.revisedPrompt, !revisedPrompt.isEmpty {
                Text(revisedPrompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let displayPath {
                HStack(spacing: 6) {
                    Text(displayPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .textSelection(.enabled)

                    Button {
                        copyPath()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Copy path")
                }
            }
        }
    }

    @ViewBuilder
    private var imageContextMenu: some View {
        Button {
            isPreviewPresented = true
        } label: {
            Label("Open Preview", systemImage: "arrow.up.left.and.arrow.down.right")
        }

        Button {
            copyImage()
        } label: {
            Label("Copy Image", systemImage: "doc.on.doc")
        }

        if let displayPath {
            Button {
                copy(displayPath, message: "Copied path")
            } label: {
                Label("Copy Path", systemImage: "link")
            }
        }

        if resolvedURL != nil {
            Button {
                saveCopy()
            } label: {
                Label("Save Copy", systemImage: "square.and.arrow.down")
            }
        }
    }

    private var statusText: String {
        if attachment.cachedPath != nil {
            return "completed"
        }
        if let status = attachment.status, !status.isEmpty {
            return status
        }
        return "waiting for image"
    }

    private var displayPath: String? {
        attachment.cachedPath ?? attachment.sourcePath
    }

    private var resolvedURL: URL? {
        guard let cachedPath = attachment.cachedPath else { return nil }
        let url = URL(fileURLWithPath: cachedPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    private func loadImage() {
        guard let path = attachment.cachedPath else {
            platformImage = nil
            return
        }
        platformImage = PlatformImage(contentsOfFile: path)
    }

    private func copy(_ text: String, message: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
        actionMessage = message
    }

    private func copyPath() {
        guard let displayPath else { return }
        copy(displayPath, message: "Copied path")
    }

    private func copyImage() {
        #if os(macOS)
        guard let platformImage else {
            if let displayPath {
                copy(displayPath, message: "Copied path")
            }
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([platformImage])
        actionMessage = "Copied image"
        #elseif os(iOS)
        guard let platformImage else {
            if let displayPath {
                copy(displayPath, message: "Copied path")
            }
            return
        }
        UIPasteboard.general.image = platformImage
        actionMessage = "Copied image"
        #endif
    }

    private func saveCopy() {
        guard let sourceURL = resolvedURL else { return }

        do {
            let destinationDirectory = try destinationDirectory()
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            let destinationURL = uniqueDestinationURL(in: destinationDirectory, preferredName: sourceURL.lastPathComponent)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            actionMessage = "Saved \(destinationURL.lastPathComponent)"

            #if os(macOS)
            NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
            #endif
        } catch {
            actionMessage = "Save failed"
        }
    }

    private func destinationDirectory() throws -> URL {
        #if os(macOS)
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            return downloads
        }
        #endif

        return try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    private func uniqueDestinationURL(in directory: URL, preferredName: String) -> URL {
        let baseURL = directory.appendingPathComponent(preferredName.isEmpty ? "generated-image.png" : preferredName)
        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        let name = baseURL.deletingPathExtension().lastPathComponent
        let pathExtension = baseURL.pathExtension
        for index in 2...999 {
            let candidateName = pathExtension.isEmpty
                ? "\(name)-\(index)"
                : "\(name)-\(index).\(pathExtension)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(pathExtension.isEmpty ? "png" : pathExtension)
    }

    private func platformImageView(_ image: PlatformImage) -> Image {
        #if os(macOS)
        Image(nsImage: image)
        #elseif os(iOS)
        Image(uiImage: image)
        #else
        Image(systemName: "photo")
        #endif
    }
}

private struct ThreadFileAttachmentView: View {
    var attachment: ThreadMessageAttachment

    @State private var isExpanded = false
    @State private var isPreviewPresented = false
    @State private var actionMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerButton

            if isExpanded {
                artifactDetails
                actionRow
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $isPreviewPresented) {
            ThreadArtifactPreviewView(attachment: attachment)
        }
    }

    private var headerButton: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: fileIcon)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.title ?? fileName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(summaryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var artifactDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let sourcePath = attachment.sourcePath {
                Text(sourcePath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                if let changeType = attachment.changeType {
                    Label(changeType.rawValue, systemImage: "pencil.and.list.clipboard")
                }
                if let language = attachment.language {
                    Label(language, systemImage: "curlybraces")
                }
                if let byteCount = attachment.byteCount {
                    Text(formattedBytes(byteCount))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            ImageActionButton(
                systemName: "doc.text.magnifyingglass",
                help: "Preview file",
                unavailableReason: attachment.cachedPath == nil ? "The file is not cached locally yet." : nil
            ) {
                isPreviewPresented = true
            }

            ImageActionButton(
                systemName: "link",
                help: "Copy source path",
                unavailableReason: (attachment.sourcePath ?? attachment.cachedPath) == nil ? "No source path is available for this file." : nil
            ) {
                copy(attachment.sourcePath ?? attachment.cachedPath ?? "", message: "Copied path")
            }

            ImageActionButton(
                systemName: "square.and.arrow.down",
                help: "Save a copy",
                unavailableReason: attachment.cachedPath == nil ? "The file is not cached locally yet." : nil
            ) {
                saveCopy()
            }

            #if os(macOS)
            ImageActionButton(
                systemName: "arrow.up.forward.app",
                help: "Open externally",
                unavailableReason: attachment.cachedPath == nil ? "The file is not cached locally yet." : nil
            ) {
                openExternally()
            }
            #endif

            Spacer(minLength: 0)

            if let actionMessage {
                Text(actionMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var fileName: String {
        artifactFileName(attachment.sourcePath ?? attachment.cachedPath ?? "File")
    }

    private var fileIcon: String {
        switch artifactPathExtension(attachment.sourcePath ?? attachment.cachedPath ?? "") {
        case "swift", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "java", "kt", "sh", "zsh", "ps1":
            return "chevron.left.forwardslash.chevron.right"
        case "json", "yml", "yaml", "toml":
            return "curlybraces"
        case "md", "txt", "log":
            return "doc.text"
        case "pdf":
            return "doc.richtext"
        default:
            return "doc"
        }
    }

    private var summaryText: String {
        if let status = attachment.status, !status.isEmpty {
            if let byteCount = attachment.byteCount {
                return "\(status) - \(formattedBytes(byteCount))"
            }
            return status
        }
        return attachment.sourcePath ?? "File artifact"
    }

    private func copy(_ text: String, message: String) {
        guard !text.isEmpty else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
        actionMessage = message
    }

    private func saveCopy() {
        guard let cachedPath = attachment.cachedPath else { return }
        let sourceURL = URL(fileURLWithPath: cachedPath)

        do {
            let destinationDirectory = try artifactDestinationDirectory()
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            let destinationURL = uniqueArtifactDestinationURL(in: destinationDirectory, preferredName: fileName)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            actionMessage = "Saved \(destinationURL.lastPathComponent)"
            #if os(macOS)
            NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
            #endif
        } catch {
            actionMessage = "Save failed"
        }
    }

    #if os(macOS)
    private func openExternally() {
        guard let cachedPath = attachment.cachedPath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: cachedPath))
    }
    #endif
}

private struct ThreadDiffAttachmentView: View {
    var attachment: ThreadMessageAttachment

    @State private var isExpanded = false
    @State private var isPreviewPresented = false
    @State private var actionMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerButton

            if isExpanded {
                HStack(spacing: 8) {
                    Label(changeText, systemImage: "arrow.triangle.branch")
                    if let stats = diffStats {
                        Text("+\(stats.added) -\(stats.removed)")
                    }
                    if let path = attachment.sourcePath {
                        Text(path)
                            .lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                actionRow
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $isPreviewPresented) {
            ThreadArtifactPreviewView(attachment: attachment)
        }
    }

    private var headerButton: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.forwardslash.minus")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.title ?? "Code diff")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(diffSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            ImageActionButton(systemName: "doc.text.magnifyingglass", help: "View diff") {
                isPreviewPresented = true
            }

            ImageActionButton(
                systemName: "doc.on.doc",
                help: "Copy diff",
                unavailableReason: (attachment.diffText ?? "").isEmpty ? "No diff text is available to copy." : nil
            ) {
                copyDiff()
            }

            Spacer(minLength: 0)

            if let actionMessage {
                Text(actionMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var diffSummary: String {
        if let stats = diffStats {
            return "\(changeText) - +\(stats.added) -\(stats.removed)"
        }
        return changeText
    }

    private var changeText: String {
        attachment.changeType?.rawValue ?? "modified"
    }

    private var diffStats: DiffStats? {
        attachment.diffText.map(DiffStats.init(diffText:))
    }

    private func copyDiff() {
        guard let diffText = attachment.diffText, !diffText.isEmpty else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diffText, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = diffText
        #endif
        actionMessage = "Copied diff"
    }
}

private struct ThreadArtifactsListView: View {
    var attachments: [ThreadMessageAttachment]

    @Environment(\.dismiss) private var dismiss
    @State private var filter: ArtifactFilter = .all
    @State private var selectedAttachment: ThreadMessageAttachment?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.blue)

                Text("Artifacts")
                    .font(.headline)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(14)

            Picker("Artifact type", selection: $filter) {
                ForEach(ArtifactFilter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredAttachments) { attachment in
                        Button {
                            selectedAttachment = attachment
                        } label: {
                            ArtifactListRow(attachment: attachment)
                        }
                        .buttonStyle(.plain)
                    }

                    if filteredAttachments.isEmpty {
                        ContentUnavailableView("No artifacts", systemImage: "shippingbox")
                            .frame(maxWidth: .infinity, minHeight: 260)
                    }
                }
                .padding(14)
            }
        }
        .sheet(item: $selectedAttachment) { attachment in
            ThreadArtifactPreviewView(attachment: attachment)
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 420)
        #endif
    }

    private var filteredAttachments: [ThreadMessageAttachment] {
        attachments.filter { attachment in
            switch filter {
            case .all:
                return true
            case .images:
                return attachment.kind == .image
            case .files:
                return attachment.kind == .file
            case .diffs:
                return attachment.kind == .diff
            }
        }
    }
}

private enum ArtifactFilter: CaseIterable {
    case all
    case images
    case files
    case diffs

    var title: String {
        switch self {
        case .all:
            return "All"
        case .images:
            return "Images"
        case .files:
            return "Files"
        case .diffs:
            return "Diffs"
        }
    }
}

private struct ArtifactListRow: View {
    var attachment: ThreadMessageAttachment

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 24, height: 24)
                .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(attachment.title ?? titleFallback)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch attachment.kind {
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .diff:
            return "plus.forwardslash.minus"
        }
    }

    private var iconColor: Color {
        switch attachment.kind {
        case .image:
            return .blue
        case .file:
            return .secondary
        case .diff:
            return .orange
        }
    }

    private var titleFallback: String {
        artifactFileName(attachment.sourcePath ?? attachment.cachedPath ?? attachment.kind.rawValue)
    }

    private var subtitle: String {
        if let sourcePath = attachment.sourcePath {
            return sourcePath
        }
        if let status = attachment.status {
            return status
        }
        return attachment.kind.rawValue
    }
}

private struct ThreadArtifactPreviewView: View {
    var attachment: ThreadMessageAttachment

    @Environment(\.dismiss) private var dismiss
    @State private var textPreview: String?
    @State private var previewError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: previewIcon)
                    .foregroundStyle(previewColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.title ?? artifactFileName(attachment.sourcePath ?? attachment.cachedPath ?? "Artifact"))
                        .font(.headline)
                        .lineLimit(1)

                    Text(attachment.sourcePath ?? attachment.status ?? attachment.kind.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    copyPreview()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Copy")

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(14)

            Divider()

            previewContent
        }
        #if os(macOS)
        .frame(minWidth: 680, minHeight: 520)
        #endif
        .task(id: attachment.cachedPath ?? attachment.id) {
            await loadPreviewText()
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch attachment.kind {
        case .image:
            if let path = attachment.cachedPath ?? attachment.sourcePath,
               let image = PlatformImage(contentsOfFile: path) {
                ScrollView([.horizontal, .vertical]) {
                    platformImageView(image)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                }
                .background(Color.black.opacity(0.18))
            } else {
                ContentUnavailableView("Image unavailable", systemImage: "photo.badge.exclamationmark")
            }
        case .file:
            if let textPreview {
                ScrollView {
                    Text(textPreview)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            } else {
                ContentUnavailableView(previewError ?? "Preview unavailable", systemImage: "doc.text.magnifyingglass")
            }
        case .diff:
            if let diffText = attachment.diffText {
                UnifiedDiffView(diffText: diffText)
            } else {
                ContentUnavailableView("Diff unavailable", systemImage: "plus.forwardslash.minus")
            }
        }
    }

    private var previewIcon: String {
        switch attachment.kind {
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .diff:
            return "plus.forwardslash.minus"
        }
    }

    private var previewColor: Color {
        switch attachment.kind {
        case .image:
            return .blue
        case .file:
            return .secondary
        case .diff:
            return .orange
        }
    }

    private func loadPreviewText() async {
        guard attachment.kind == .file else { return }
        guard let cachedPath = attachment.cachedPath else {
            previewError = artifactUnavailableText
            return
        }

        let loaded = await Task.detached(priority: .utility) { () -> String? in
            let url = URL(fileURLWithPath: cachedPath)
            guard let data = try? Data(contentsOf: url) else {
                return nil
            }
            let maxBytes = 240_000
            let previewData = data.count > maxBytes ? data.prefix(maxBytes) : data[...]
            guard var text = String(data: Data(previewData), encoding: .utf8) else {
                return nil
            }
            if data.count > maxBytes {
                text += "\n\n... file truncated for preview ..."
            }
            return text
        }.value

        if let loaded {
            textPreview = loaded
            previewError = nil
        } else {
            previewError = artifactUnavailableText
        }
    }

    private var artifactUnavailableText: String {
        if attachment.status == "too-large" {
            return "File is too large to preview"
        }
        return "File preview unavailable"
    }

    private func copyPreview() {
        let text = attachment.diffText
            ?? textPreview
            ?? attachment.sourcePath
            ?? attachment.cachedPath
            ?? ""
        guard !text.isEmpty else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }

    private func platformImageView(_ image: PlatformImage) -> Image {
        #if os(macOS)
        Image(nsImage: image)
        #elseif os(iOS)
        Image(uiImage: image)
        #else
        Image(systemName: "photo")
        #endif
    }
}

private struct UnifiedDiffView: View {
    var diffText: String

    private var lines: [String] {
        diffText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    DiffLineRow(line: line)
                }
            }
            .padding(12)
        }
    }
}

private struct DiffLineRow: View {
    var line: String

    var body: some View {
        Text(line.isEmpty ? " " : line)
            .font(.caption.monospaced())
            .foregroundStyle(foreground)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(background)
    }

    private var foreground: Color {
        if line.hasPrefix("+"), !line.hasPrefix("+++") {
            return .green
        }
        if line.hasPrefix("-"), !line.hasPrefix("---") {
            return .red
        }
        if line.hasPrefix("@@") {
            return .blue
        }
        if line.hasPrefix("diff --git") || line.hasPrefix("---") || line.hasPrefix("+++") || line.hasPrefix("*** ") {
            return .secondary
        }
        return .primary
    }

    private var background: Color {
        if line.hasPrefix("+"), !line.hasPrefix("+++") {
            return Color.green.opacity(0.10)
        }
        if line.hasPrefix("-"), !line.hasPrefix("---") {
            return Color.red.opacity(0.10)
        }
        if line.hasPrefix("@@") {
            return Color.blue.opacity(0.08)
        }
        return Color.clear
    }
}

private struct DiffStats {
    var added: Int
    var removed: Int

    init(diffText: String) {
        var added = 0
        var removed = 0
        for line in diffText.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("+"), !line.hasPrefix("+++") {
                added += 1
            } else if line.hasPrefix("-"), !line.hasPrefix("---") {
                removed += 1
            }
        }
        self.added = added
        self.removed = removed
    }
}

private struct ImageActionButton: View {
    var systemName: String
    var help: String
    var unavailableReason: String? = nil
    var action: () -> Void

    var body: some View {
        FeedbackButton(
            unavailableReason: unavailableReason,
            action: action
        ) {
            Image(systemName: systemName)
                .font(.caption.weight(.semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(unavailableReason ?? help)
    }
}

private struct ThreadImagePreviewView: View {
    var attachment: ThreadMessageAttachment
    var image: PlatformImage?
    var statusText: String
    var displayPath: String?
    var onCopyImage: () -> Void
    var onCopyPath: () -> Void
    var onSaveCopy: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "photo")
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.title ?? "Image")
                        .font(.headline)
                        .lineLimit(1)

                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ImageActionButton(systemName: "doc.on.doc", help: "Copy image", action: onCopyImage)

                ImageActionButton(
                    systemName: "link",
                    help: "Copy image path",
                    unavailableReason: displayPath == nil ? "No image path is available yet." : nil,
                    action: onCopyPath
                )

                ImageActionButton(systemName: "square.and.arrow.down", help: "Save a copy", action: onSaveCopy)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(14)

            Divider()

            if let image {
                ScrollView([.horizontal, .vertical]) {
                    platformImageView(image)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color.black.opacity(0.18))
            } else {
                ContentUnavailableView("Image unavailable", systemImage: "photo.badge.exclamationmark")
                    .frame(minWidth: 520, minHeight: 360)
            }

            if let revisedPrompt = attachment.revisedPrompt, !revisedPrompt.isEmpty {
                Divider()
                Text(revisedPrompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 480)
        #endif
    }

    private func platformImageView(_ image: PlatformImage) -> Image {
        #if os(macOS)
        Image(nsImage: image)
        #elseif os(iOS)
        Image(uiImage: image)
        #else
        Image(systemName: "photo")
        #endif
    }
}

private func artifactFileName(_ path: String) -> String {
    path
        .split(whereSeparator: { $0 == "/" || $0 == "\\" })
        .last
        .map(String.init) ?? path
}

private func artifactPathExtension(_ path: String) -> String {
    let name = artifactFileName(path)
    guard let dotIndex = name.lastIndex(of: "."),
          dotIndex < name.index(before: name.endIndex)
    else {
        return ""
    }
    return String(name[name.index(after: dotIndex)...]).lowercased()
}

private func formattedBytes(_ byteCount: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
}

private func artifactDestinationDirectory() throws -> URL {
    #if os(macOS)
    if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
        return downloads
    }
    #endif

    return try FileManager.default.url(
        for: .documentDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
}

private func uniqueArtifactDestinationURL(in directory: URL, preferredName: String) -> URL {
    let baseURL = directory.appendingPathComponent(preferredName.isEmpty ? "artifact" : preferredName)
    guard FileManager.default.fileExists(atPath: baseURL.path) else {
        return baseURL
    }

    let name = baseURL.deletingPathExtension().lastPathComponent
    let pathExtension = baseURL.pathExtension
    for index in 2...999 {
        let candidateName = pathExtension.isEmpty
            ? "\(name)-\(index)"
            : "\(name)-\(index).\(pathExtension)"
        let candidateURL = directory.appendingPathComponent(candidateName)
        if !FileManager.default.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }
    }

    return directory.appendingPathComponent(UUID().uuidString)
}

#if os(macOS)
private typealias PlatformImage = NSImage
#elseif os(iOS)
private typealias PlatformImage = UIImage
#endif
