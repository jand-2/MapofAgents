import MapofAgentsCore
import SwiftUI

struct ThreadInboxPanelView: View {
    @Bindable var catalogStore: ThreadCatalogStore
    var onRefresh: () -> Void
    var onSearch: () -> Void
    var onOpen: (ThreadCatalogEntry) -> Void
    var onAddToCanvas: (ThreadCatalogEntry) -> Void
    var onArchive: (ThreadCatalogEntry) -> Void
    var onMarkRead: (ThreadCatalogEntry, Bool) -> Void
    var onHoverNode: (NodeID?) -> Void = { _ in }
    var attentionRequests: [RuntimeAttentionRequest] = []
    var onFocusAttention: (RuntimeAttentionRequest) -> Void = { _ in }
    var onRespondToAttention: (RuntimeAttentionRequest, Bool) -> Void = { _, _ in }
    var onRespondToAttentionWithText: (RuntimeAttentionRequest, String) -> Void = { _, _ in }
    var onDeclineTypedAttention: (RuntimeAttentionRequest) -> Void = { _ in }

    @State private var pendingArchiveEntry: ThreadCatalogEntry?
    @State private var searchTask: Task<Void, Never>?
    @State private var searchGeneration = 0
    @AppStorage("mapofagents.panel.threadInbox.collapsed") private var isCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !isCollapsed {
                modePicker
                workflowFilterPicker

                if catalogStore.selectedMode == .search {
                    TextField("Search threads", text: $catalogStore.searchText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }

                if let errorMessage = catalogStore.errorMessage {
                    Label("Some inbox hosts may be stale: \(errorMessage)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }

                if catalogStore.selectedMode == .needsYou {
                    needsYouContent
                } else if catalogStore.visibleEntries.isEmpty {
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    let entries = catalogStore.visibleEntries
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(entries.count) thread\(entries.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(entries) { entry in
                                    ThreadInboxRowView(
                                        entry: entry,
                                        onOpen: { onOpen(entry) },
                                        onAddToCanvas: entry.materializedNodeID == nil ? { onAddToCanvas(entry) } : nil,
                                        onArchive: entry.archived ? nil : { pendingArchiveEntry = entry },
                                        onMarkRead: { isRead in onMarkRead(entry, isRead) },
                                        onHoverNode: onHoverNode
                                    )
                                    .transition(rowTransition)
                                }
                            }
                            .animation(.snappy(duration: 0.28), value: entries.map(\.id))
                        }
                        .frame(maxHeight: 360)
                        .scrollIndicators(.visible)
                    }
                }
            }
        }
        .onChange(of: catalogStore.searchText) { _, _ in
            scheduleSearchIfNeeded()
        }
        .onChange(of: catalogStore.selectedMode) { _, mode in
            if mode == .search {
                scheduleSearchIfNeeded(immediate: true)
            } else {
                cancelSearch()
            }
        }
        .onDisappear {
            cancelSearch()
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
        .confirmationDialog(
            "Archive Thread?",
            isPresented: Binding(
                get: { pendingArchiveEntry != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingArchiveEntry = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingArchiveEntry
        ) { entry in
            Button("Archive \(entry.title)", role: .destructive) {
                onArchive(entry)
                pendingArchiveEntry = nil
            }
            Button("Cancel", role: .cancel) {
                pendingArchiveEntry = nil
            }
        } message: { entry in
            Text("This archives the Codex thread on \(entry.hostName). Canvas nodes are left alone unless you remove them separately.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Thread Inbox", systemImage: "tray.full")
                .font(.headline)

            Spacer()

            if catalogStore.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Refresh thread inbox")
            .accessibilityLabel("Refresh thread inbox")

            Button {
                withAnimation(.snappy) {
                    isCollapsed.toggle()
                }
            } label: {
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Expand" : "Minimize")
            .accessibilityLabel(isCollapsed ? "Expand thread inbox" : "Minimize thread inbox")
        }
    }

    @ViewBuilder
    private var needsYouContent: some View {
        let sortedRequests = attentionRequests.sorted { $0.createdAt < $1.createdAt }
        let entries = catalogStore.visibleEntries
        if sortedRequests.isEmpty, entries.isEmpty {
            Text(emptyMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if !sortedRequests.isEmpty {
                    Text("\(sortedRequests.count) request\(sortedRequests.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(sortedRequests) { request in
                                AttentionRequestCardView(
                                    request: request,
                                    onFocus: onFocusAttention,
                                    onRespond: onRespondToAttention,
                                    onRespondWithText: onRespondToAttentionWithText,
                                    onDeclineTyped: onDeclineTypedAttention
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 360)
                    .scrollIndicators(.visible)
                }

                if !entries.isEmpty {
                    Text("\(entries.count) thread\(entries.count == 1 ? "" : "s") with attention")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(entries) { entry in
                                ThreadInboxRowView(
                                    entry: entry,
                                    onOpen: { onOpen(entry) },
                                    onAddToCanvas: entry.materializedNodeID == nil ? { onAddToCanvas(entry) } : nil,
                                    onArchive: entry.archived ? nil : { pendingArchiveEntry = entry },
                                    onMarkRead: { isRead in onMarkRead(entry, isRead) },
                                    onHoverNode: onHoverNode
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                    .scrollIndicators(.visible)
                }
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(ThreadInboxMode.primaryModes) { mode in
                Button {
                    withAnimation(.snappy(duration: 0.24)) {
                        catalogStore.selectedMode = mode
                    }
                } label: {
                    Text(shortTitle(for: mode))
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(catalogStore.selectedMode == mode ? .accentColor : .secondary)
            }
        }
    }

    private var workflowFilterPicker: some View {
        Picker("Workflow", selection: $catalogStore.selectedWorkflowFilter) {
            Label("All threads", systemImage: "tray.full")
                .tag(ThreadInboxWorkflowFilter.all)
            Label("On workflows", systemImage: "rectangle.3.group")
                .tag(ThreadInboxWorkflowFilter.onAnyWorkflow)
            Label("Not on workflows", systemImage: "rectangle.dashed")
                .tag(ThreadInboxWorkflowFilter.notOnWorkflow)

            if !catalogStore.workflowFilterOptions.isEmpty {
                Divider()

                ForEach(catalogStore.workflowFilterOptions) { option in
                    Label(workflowFilterTitle(option), systemImage: option.isActiveWorkflow ? "checkmark.rectangle.stack" : "rectangle.stack")
                        .tag(ThreadInboxWorkflowFilter.workflow(option.workflowID))
                }
            }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyMessage: String {
        switch catalogStore.selectedMode {
        case .active:
            return "No active threads found."
        case .finished:
            return "No finished threads found."
        case .needsYou:
            return "Nothing needs you right now."
        case .unread:
            return "No unread thread changes."
        case .recent:
            return "No known threads yet."
        case .search:
            return catalogStore.searchText.isEmpty ? "Type to search known threads." : "No matching threads."
        case .archived:
            return "No archived threads loaded."
        }
    }

    private func shortTitle(for mode: ThreadInboxMode) -> String {
        switch mode {
        case .active:
            return "Active"
        case .finished:
            return "Finished"
        case .needsYou:
            return "Needs"
        case .unread:
            return "Unread"
        case .recent:
            return "Recent"
        case .search:
            return "Search"
        case .archived:
            return "Archive"
        }
    }

    private func workflowFilterTitle(_ option: ThreadInboxWorkflowFilterOption) -> String {
        "\(option.workflowName) (\(option.count))"
    }

    private var rowTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }

    private func scheduleSearchIfNeeded(immediate: Bool = false) {
        cancelSearch()
        guard catalogStore.selectedMode == .search else { return }
        searchGeneration += 1
        let generation = searchGeneration
        let query = catalogStore.searchText
        searchTask = Task {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(350))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard generation == searchGeneration,
                      catalogStore.selectedMode == .search,
                      catalogStore.searchText == query else {
                    return
                }
                onSearch()
            }
        }
    }

    private func cancelSearch() {
        searchGeneration += 1
        searchTask?.cancel()
        searchTask = nil
    }
}

private struct ThreadInboxRowView: View {
    var entry: ThreadCatalogEntry
    var onOpen: () -> Void
    var onAddToCanvas: (() -> Void)?
    var onArchive: (() -> Void)?
    var onMarkRead: (Bool) -> Void
    var onHoverNode: (NodeID?) -> Void = { _ in }

    var body: some View {
        hoverable(VStack(alignment: .leading, spacing: 7) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(entry.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)

                            if entry.unread {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 6, height: 6)
                            }

                            if entry.pendingRequestCount > 0 {
                                Text("\(entry.pendingRequestCount)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.14), in: Capsule())
                            }
                        }

                        Text(entry.hostName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Label(threadKindLabel, systemImage: threadKindIcon)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(threadKindColor)
                            .lineLimit(1)

                        Label(entry.workflowContextLabel, systemImage: workflowIcon)
                            .font(.caption2)
                            .foregroundStyle(entry.hasActiveWorkflowMembership ? Color.blue : Color.secondary)
                            .lineLimit(1)

                        ThreadInboxLiveStateLine(summary: entry.liveStateSummary)

                        if !entry.preview.isEmpty {
                            Text(entry.preview)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 6)

                    Text(statusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.12), in: Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(entry.title)")

            HStack(spacing: 8) {
                Text(activityTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer()

                if let onAddToCanvas {
                    Button(action: onAddToCanvas) {
                        Image(systemName: "plus.square.on.square")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Add to canvas")
                    .accessibilityLabel("Add \(entry.title) to canvas")
                }

                Button {
                    onMarkRead(!entry.unread)
                } label: {
                    Image(systemName: entry.unread ? "envelope.open" : "envelope.badge")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(entry.unread ? "Mark read" : "Mark unread")
                .accessibilityLabel(entry.unread ? "Mark \(entry.title) read" : "Mark \(entry.title) unread")

                if let onArchive {
                    Button(role: .destructive, action: onArchive) {
                        Image(systemName: "archivebox")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Archive")
                    .accessibilityLabel("Archive \(entry.title)")
                }
            }
        })
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(.background.opacity(0.30), in: RoundedRectangle(cornerRadius: 8))
    }

    private func hoverable<Content: View>(_ content: Content) -> some View {
        #if os(macOS)
        content.onHover { isHovering in
            onHoverNode(isHovering ? entry.activeWorkflowNodeID : nil)
        }
        #else
        content
        #endif
    }

    private var workflowIcon: String {
        if entry.hasActiveWorkflowMembership {
            return "rectangle.3.group"
        }
        if entry.workflowMemberships.count > 1 {
            return "square.stack.3d.up"
        }
        if entry.workflowMemberships.isEmpty {
            return "rectangle.dashed"
        }
        return "rectangle.2.swap"
    }

    private var statusText: String {
        switch entry.loadedStatus {
        case .idle:
            return "idle"
        case .running:
            return "running"
        case .needsInput:
            return "needs"
        case .failed:
            return "failed"
        case .complete:
            return "finished"
        case .unknown:
            return "unknown"
        }
    }

    private var activityTimestamp: String {
        let date = entry.lastActivityAt.formatted(
            .dateTime
                .month(.abbreviated)
                .day()
                .year()
        )
        let time = entry.lastActivityAt.formatted(
            .dateTime
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits)
                .second(.twoDigits)
        )
        return "\(date) at \(time)"
    }

    private var icon: String {
        switch entry.loadedStatus {
        case .running:
            return "arrow.triangle.2.circlepath"
        case .needsInput:
            return "exclamationmark.bubble"
        case .failed:
            return "xmark.octagon"
        default:
            return entry.threadKind == .subagent ? "person.2" : "bubble.left.and.bubble.right"
        }
    }

    private var threadKindLabel: String {
        (entry.threadKind ?? .thread).displayName
    }

    private var threadKindIcon: String {
        entry.threadKind == .subagent ? "person.2" : "bubble.left"
    }

    private var threadKindColor: Color {
        entry.threadKind == .subagent ? .purple : .secondary
    }

    private var color: Color {
        switch entry.loadedStatus {
        case .running:
            return .blue
        case .needsInput:
            return .orange
        case .failed:
            return .red
        case .complete:
            return .green
        default:
            return .secondary
        }
    }
}

private struct ThreadInboxLiveStateLine: View {
    var summary: ThreadLiveStateSummary

    var body: some View {
        Label {
            HStack(spacing: 4) {
                Text(summary.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)

                if let detail = summary.detail, !detail.isEmpty, detail != summary.title {
                    Text("· \(detail)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: iconName)
        }
        .foregroundStyle(color)
        .help(helpText)
    }

    private var helpText: String {
        if let detail = summary.detail, !detail.isEmpty {
            return "\(summary.title): \(detail)"
        }
        return summary.title
    }

    private var iconName: String {
        switch summary.tone {
        case .idle:
            return "clock"
        case .working:
            return "arrow.triangle.2.circlepath"
        case .waiting:
            return "hand.raised"
        case .finished:
            return "checkmark.circle"
        case .failed:
            return "xmark.octagon"
        }
    }

    private var color: Color {
        switch summary.tone {
        case .idle:
            return .secondary
        case .working:
            return .blue
        case .waiting:
            return .orange
        case .finished:
            return .green
        case .failed:
            return .red
        }
    }
}
