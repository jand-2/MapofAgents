import MapofAgentsCore
import SwiftUI

struct RemoteFolderPickerView: View {
    enum Mode: Hashable {
        case chooseProject
        case showContents
    }

    var remote: CodexDesktopRemote
    var initialPath: String
    var mode: Mode
    var onCancel: () -> Void
    var onSelect: (String) -> Void

    @State private var currentPath: String
    @State private var draftPath: String
    @State private var listing: RemoteFolderListing?
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(
        remote: CodexDesktopRemote,
        initialPath: String,
        mode: Mode = .chooseProject,
        onCancel: @escaping () -> Void,
        onSelect: @escaping (String) -> Void
    ) {
        let trimmedPath = initialPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let startPath = trimmedPath.isEmpty ? "~" : trimmedPath
        self.remote = remote
        self.initialPath = startPath
        self.mode = mode
        self.onCancel = onCancel
        self.onSelect = onSelect
        _currentPath = State(initialValue: startPath)
        _draftPath = State(initialValue: startPath)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            pathBar
                .padding(12)

            Divider()

            folderList

            Divider()

            footer
                .padding(12)
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 430, idealHeight: 520)
        .task {
            await load(path: currentPath)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text(mode == .showContents ? "Folder Contents" : "Choose Project Folder")
                    .font(.headline)
                Text(remote.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(12)
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            Button {
                guard let parentPath = listing?.parentPath else { return }
                Task { await load(path: parentPath) }
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isLoading || listing?.parentPath == nil)
            .help("Parent folder")
            .accessibilityLabel("Parent folder")
            .minimumAccessibleHitTarget()

            Button {
                Task { await load(path: initialPath) }
            } label: {
                Image(systemName: "house")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isLoading)
            .help("Home folder")
            .accessibilityLabel("Home folder")
            .minimumAccessibleHitTarget()

            TextField("Folder path", text: $draftPath)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit {
                    Task { await load(path: draftPath) }
                }

            Button {
                Task { await load(path: draftPath) }
            } label: {
                Image(systemName: "arrow.forward")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isLoading || draftPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Open path")
            .accessibilityLabel("Open path")
            .minimumAccessibleHitTarget()

            Button {
                Task { await load(path: currentPath) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isLoading)
            .help("Refresh")
            .accessibilityLabel("Refresh")
            .minimumAccessibleHitTarget()
        }
    }

    private var folderList: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let errorMessage {
                        statusRow(
                            icon: "exclamationmark.triangle.fill",
                            title: errorMessage,
                            color: .orange
                        )
                    } else if !isLoading, listing?.entries.isEmpty == true {
                        statusRow(
                            icon: "folder",
                            title: "No folders in this location.",
                            color: .secondary
                        )
                    }

                    ForEach(listing?.entries ?? []) { entry in
                        folderRow(entry)
                    }
                }
                .padding(.vertical, 6)
            }

            if isLoading {
                ProgressView()
                    .controlSize(.regular)
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let path = listing?.path {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(mode == .showContents ? "Close" : "Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            if mode == .chooseProject {
                FeedbackButton(
                    unavailableReason: selectedCurrentPath.isEmpty ? "Choose a folder before adding it." : nil,
                    action: {
                        onSelect(selectedCurrentPath)
                    }
                ) {
                    Label("Add", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func folderRow(_ entry: RemoteFolderEntry) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await load(path: entry.path) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(.yellow)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.body)
                            .lineLimit(1)
                        Text(entry.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if mode == .chooseProject {
                Button {
                    onSelect(entry.path)
                } label: {
                    Image(systemName: "checkmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Add this folder")
                .accessibilityLabel("Add this folder")
                .minimumAccessibleHitTarget()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func statusRow(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 18)
            Text(title)
                .font(.caption)
                .lineLimit(2)
            Spacer()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var selectedCurrentPath: String {
        (listing?.path ?? draftPath).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func load(path: String) async {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        do {
            let nextListing = try await CodexRemoteTunnelService.listRemoteFolders(
                on: remote,
                path: trimmedPath
            )
            listing = nextListing
            currentPath = nextListing.path
            draftPath = nextListing.path
        } catch {
            errorMessage = error.localizedDescription
            draftPath = trimmedPath
        }
        isLoading = false
    }
}
