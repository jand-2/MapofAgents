import MapofAgentsCore
import Foundation
import Observation

enum WorkflowEditorMode {
    case create
    case rename
    case duplicate

    var title: String {
        switch self {
        case .create:
            return "New Workflow"
        case .rename:
            return "Rename Workflow"
        case .duplicate:
            return "Save Workflow Copy"
        }
    }

    var actionTitle: String {
        switch self {
        case .create:
            return "Create"
        case .rename:
            return "Rename"
        case .duplicate:
            return "Save Copy"
        }
    }

    var systemImage: String {
        switch self {
        case .create:
            return "plus.rectangle.on.rectangle"
        case .rename:
            return "pencil"
        case .duplicate:
            return "doc.on.doc"
        }
    }
}

@MainActor
@Observable
final class WorkflowLibraryCoordinator {
    private let repository: LocalControlRoomStore

    var workflows: [WorkflowRecord] = []
    var activeWorkflowID: String?
    var editorMode: WorkflowEditorMode?
    var nameDraft = ""
    var workflowToDelete: WorkflowRecord?
    var errorMessage: String?

    init(repository: LocalControlRoomStore) {
        self.repository = repository
    }

    var activeWorkflow: WorkflowRecord? {
        workflows.first { $0.id == activeWorkflowID }
    }

    var activeWorkflowName: String {
        activeWorkflow?.name ?? "mapofagents"
    }

    func refreshState() async {
        do {
            workflows = try await repository.loadWorkflows()
            activeWorkflowID = try await repository.activeWorkflowID()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginCreateWorkflow() {
        nameDraft = nextWorkflowName()
        editorMode = .create
    }

    func beginDuplicateWorkflow() {
        let baseName = activeWorkflow?.name ?? "Workflow"
        nameDraft = "\(baseName) Copy"
        editorMode = .duplicate
    }

    func beginRenameWorkflow() {
        guard let activeWorkflow else { return }
        nameDraft = activeWorkflow.name
        editorMode = .rename
    }

    func beginDeleteActiveWorkflow() {
        guard workflows.count > 1, let activeWorkflow else { return }
        workflowToDelete = activeWorkflow
    }

    func submitWorkflowName() async -> Bool {
        guard let editorMode else { return false }
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }

        errorMessage = nil
        do {
            switch editorMode {
            case .create:
                _ = try await repository.createWorkflow(name: name)
            case .rename:
                guard let activeWorkflowID else { return false }
                _ = try await repository.renameWorkflow(id: activeWorkflowID, name: name)
            case .duplicate:
                _ = try await repository.duplicateActiveWorkflow(name: name)
            }

            self.editorMode = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func selectWorkflow(_ workflowID: String) async -> Bool {
        guard workflowID != activeWorkflowID else { return false }
        errorMessage = nil
        editorMode = nil

        do {
            try await repository.selectWorkflow(id: workflowID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteWorkflow(_ workflow: WorkflowRecord) async -> Bool {
        errorMessage = nil
        workflowToDelete = nil
        editorMode = nil

        do {
            _ = try await repository.deleteWorkflow(id: workflow.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func nextWorkflowName() -> String {
        let existingNames = Set(workflows.map(\.name))
        if !existingNames.contains("New Workflow") {
            return "New Workflow"
        }

        var index = 2
        while existingNames.contains("New Workflow \(index)") {
            index += 1
        }
        return "New Workflow \(index)"
    }
}
