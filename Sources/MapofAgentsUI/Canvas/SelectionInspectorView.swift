import MapofAgentsCore
import SwiftUI

struct SelectionInspectorView: View {
    @Bindable var graphStore: GraphStore

    var body: some View {
        Group {
            if let node = graphStore.selectedNode {
                NodeSelectionInspector(node: node, graphStore: graphStore)
            } else if let edge = selectedManualEdge {
                EdgeSelectionInspector(edge: edge, graphStore: graphStore)
            }
        }
    }

    private var selectedManualEdge: CanvasEdge? {
        guard case .edge(let id) = graphStore.selection else {
            return nil
        }
        return graphStore.graph.manualEdges[id]
    }
}

private struct NodeSelectionInspector: View {
    var node: CanvasNode
    @Bindable var graphStore: GraphStore

    @State private var draftTitle = ""
    @State private var draftPath = ""
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            TextField("Title", text: $draftTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveTitle)

            if node.kind == .folder {
                TextField("Folder path", text: $draftPath)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(savePath)
            } else if !node.subtitle.isEmpty {
                Text(node.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button {
                    saveTitle()
                    if node.kind == .folder {
                        savePath()
                    }
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete node")
            }
        }
        .padding(12)
        .frame(width: 310, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 8)
        .onAppear(perform: syncDrafts)
        .onChange(of: node.id) { _, _ in syncDrafts() }
        .confirmationDialog(
            "Delete Canvas Node?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete \(node.title)", role: .destructive) {
                Task { await graphStore.deleteNode(node.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes \"\(node.title)\" and its connected lines from this workflow map. It does not delete Codex thread history from disk.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(accentColor)
                .frame(width: 22, height: 22)
                .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            Text(node.kind == .machine ? "Machine" : node.kind == .folder ? "Folder" : "Thread")
                .font(.headline)

            Spacer()

            Button {
                graphStore.clearSelection()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    private var iconName: String {
        switch node.kind {
        case .machine:
            return "cpu"
        case .folder:
            return "folder"
        case .codexThread:
            return "bubble.left.and.bubble.right"
        }
    }

    private var accentColor: Color {
        switch node.kind {
        case .machine:
            return .green
        case .folder:
            return .yellow
        case .codexThread:
            return .blue
        }
    }

    private func syncDrafts() {
        draftTitle = node.title
        draftPath = node.metadata.folderPath ?? node.subtitle
    }

    private func saveTitle() {
        Task { await graphStore.updateNodeTitle(id: node.id, title: draftTitle) }
    }

    private func savePath() {
        Task { await graphStore.updateFolderPath(id: node.id, path: draftPath) }
    }
}

private struct EdgeSelectionInspector: View {
    var edge: CanvasEdge
    @Bindable var graphStore: GraphStore

    @State private var draftLabel = ""
    @State private var isConfirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: edge.kind == .threadMessage ? "paperplane" : "line.diagonal")
                    .foregroundStyle(.green)
                    .frame(width: 22, height: 22)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                Text("Line")
                    .font(.headline)

                Spacer()

                Button {
                    graphStore.clearSelection()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            TextField("Label", text: $draftLabel)
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveLabel)

            HStack(spacing: 8) {
                Button {
                    saveLabel()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete line")
            }
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 8)
        .onAppear(perform: syncDraft)
        .onChange(of: edge.id) { _, _ in syncDraft() }
        .confirmationDialog(
            "Delete Line?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Line", role: .destructive) {
                Task { await graphStore.deleteManualEdge(edge.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the selected manual line from this workflow map.")
        }
    }

    private func syncDraft() {
        draftLabel = edge.label ?? ""
    }

    private func saveLabel() {
        Task { await graphStore.updateManualEdgeLabel(id: edge.id, label: draftLabel) }
    }
}
