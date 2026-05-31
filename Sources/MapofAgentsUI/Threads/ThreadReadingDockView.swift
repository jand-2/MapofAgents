import MapofAgentsCore
import SwiftUI

struct ThreadReadingItem: Identifiable {
    var id: NodeID { node.id }
    var node: CanvasNode
    var transcript: ThreadTranscript?
    var liveAssistantText: String
    var liveStateSummary: ThreadLiveStateSummary?
    var isLoading: Bool
    var isLoadingOlder: Bool
    var loadPhase: TranscriptLoadPhase
    var isAwaitingResponse: Bool
    var canStopTurn: Bool
    var isStoppingTurn: Bool
    var errorMessage: String?
    var threadMentionCandidates: [MentionCandidate]
    var attentionRequests: [RuntimeAttentionRequest]
}

struct ThreadReadingCandidate: Identifiable, Hashable {
    var id: NodeID
    var title: String
    var subtitle: String
    var isOpen: Bool
}

#if os(macOS)
struct ThreadReadingDockView: View {
    @Bindable var runtimeStore: CodexRuntimeStore
    var items: [ThreadReadingItem]
    var candidates: [ThreadReadingCandidate]
    var onCloseDock: () -> Void
    var onClear: () -> Void
    var onAddThread: (NodeID) -> Void
    var onRename: (NodeID, String) -> Void
    var onRefresh: (NodeID) -> Void
    var onLoadOlder: (NodeID) -> Void
    var onUseCachedTranscript: (NodeID) -> Void
    var onSend: (NodeID, String, [ChatInputAttachment]) async -> Bool
    var onStopTurn: (NodeID) -> Void
    var onFocusAttention: (RuntimeAttentionRequest) -> Void
    var onRespondToAttention: (RuntimeAttentionRequest, Bool) -> Void
    var onRespondToAttentionWithText: (RuntimeAttentionRequest, String) -> Void
    var onDeclineTypedAttention: (RuntimeAttentionRequest) -> Void
    var onCloseThread: (NodeID) -> Void
    var onMentionCatalogNeeded: (ThreadRef?) -> Void

    @State private var selectedCandidateID: NodeID?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if items.isEmpty {
                emptyState
            } else {
                GeometryReader { proxy in
                    let columns = gridColumns(in: proxy.size, count: items.count)
                    ScrollView(.vertical) {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                            ForEach(items) { item in
                                ThreadPopoverView(
                                    node: item.node,
                                    runtimeStore: runtimeStore,
                                    transcript: item.transcript,
                                    liveAssistantText: item.liveAssistantText,
                                    liveStateSummary: item.liveStateSummary,
                                    isLoading: item.isLoading,
                                    isLoadingOlder: item.isLoadingOlder,
                                    loadPhase: item.loadPhase,
                                    isAwaitingResponse: item.isAwaitingResponse,
                                    errorMessage: item.errorMessage,
                                    threadMentionCandidates: item.threadMentionCandidates,
                                    attentionRequests: item.attentionRequests,
                                    canStopTurn: item.canStopTurn,
                                    isStoppingTurn: item.isStoppingTurn,
                                    onRename: { onRename(item.node.id, $0) },
                                    onStopTurn: { onStopTurn(item.node.id) },
                                    onRefresh: { onRefresh(item.node.id) },
                                    onLoadOlder: { onLoadOlder(item.node.id) },
                                    onUseCachedTranscript: { onUseCachedTranscript(item.node.id) },
                                    onSend: { text, attachments in
                                        await onSend(item.node.id, text, attachments)
                                    },
                                    onFocusAttention: onFocusAttention,
                                    onRespondToAttention: onRespondToAttention,
                                    onRespondToAttentionWithText: onRespondToAttentionWithText,
                                    onDeclineTypedAttention: onDeclineTypedAttention,
                                    onClose: { onCloseThread(item.node.id) }
                                )
                                .id(item.node.metadata.threadRef?.qualifiedID ?? item.node.id.rawValue)
                                .frame(maxWidth: .infinity)
                                .frame(height: tileHeight(in: proxy.size, columnCount: columns.count))
                                .task(id: item.node.metadata.threadRef?.qualifiedID ?? item.node.id.rawValue) {
                                    onMentionCatalogNeeded(item.node.metadata.threadRef)
                                }
                            }
                        }
                        .padding(14)
                    }
                    .scrollIndicators(.visible)
                }
            }
        }
        .background {
            #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
                .opacity(0.96)
                .ignoresSafeArea()
            #else
            Color(.systemBackground)
                .ignoresSafeArea()
            #endif
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
        }
        .onAppear(perform: selectFirstAvailableCandidateIfNeeded)
        .onChange(of: candidates) { _, _ in
            selectFirstAvailableCandidateIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Reader", systemImage: "rectangle.split.3x1")
                .font(.headline)

            Text(items.isEmpty ? "Choose a workflow chat to start reading." : "\(items.count) chat\(items.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text("Add thread to reader")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Add thread to reader", selection: $selectedCandidateID) {
                Text("Select a workflow thread")
                    .tag(nil as NodeID?)
                ForEach(candidates) { candidate in
                    Text(candidateLabel(candidate))
                        .tag(Optional(candidate.id))
                        .disabled(candidate.isOpen)
                }
            }
            .labelsHidden()
            .frame(width: 260)
            .help("Choose another thread from this workflow")

            Button {
                guard let selectedCandidateID else { return }
                onAddThread(selectedCandidateID)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 20, height: 20)
            }
            .disabled(selectedCandidateID == nil || candidates.first(where: { $0.id == selectedCandidateID })?.isOpen == true)
            .help("Add selected chat to reader")

            Button {
                guard let last = items.last else { return }
                onCloseThread(last.node.id)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 20, height: 20)
            }
            .disabled(items.isEmpty)
            .help("Remove the last chat from reader")

            if !items.isEmpty {
                Button(action: onClear) {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button(action: onCloseDock) {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Close reading mode")
            .accessibilityLabel("Close reading mode")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Chats Selected",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("Use the thread picker above to open chats from the active workflow.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func gridColumns(in size: CGSize, count: Int) -> [GridItem] {
        let minColumnWidth: CGFloat = 430
        let maxColumnsByWidth = max(1, min(4, Int((size.width + 12) / (minColumnWidth + 12))))
        let columnCount = max(1, min(maxColumnsByWidth, max(count, 1)))
        return Array(
            repeating: GridItem(.flexible(minimum: minColumnWidth), spacing: 12, alignment: .top),
            count: columnCount
        )
    }

    private func tileHeight(in size: CGSize, columnCount: Int) -> CGFloat {
        let rowCount = max(1, Int(ceil(Double(max(items.count, 1)) / Double(max(columnCount, 1)))))
        let verticalPadding: CGFloat = 28
        let rowSpacing = CGFloat(max(rowCount - 1, 0)) * 12
        let available = size.height - verticalPadding - rowSpacing
        return max(430, floor(available / CGFloat(rowCount)))
    }

    private func candidateLabel(_ candidate: ThreadReadingCandidate) -> String {
        if candidate.isOpen {
            return "\(candidate.title) - open"
        }
        return candidate.title
    }

    private func selectFirstAvailableCandidateIfNeeded() {
        if let selectedCandidateID,
           candidates.contains(where: { $0.id == selectedCandidateID && !$0.isOpen }) {
            return
        }
        selectedCandidateID = candidates.first(where: { !$0.isOpen })?.id
    }
}
#endif
