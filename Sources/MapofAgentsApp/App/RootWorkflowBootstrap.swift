#if os(macOS)
import AppKit
import MapofAgentsCore

enum RootOverlayFocusTarget: Hashable {
    case commandBar
    case newThread
    case workflowName
    case pairing
    case threadChat
    case reader

    var isPresentedInsideGraphCanvas: Bool {
        switch self {
        case .threadChat, .reader:
            return true
        case .commandBar, .newThread, .workflowName, .pairing:
            return false
        }
    }
}

enum RootModalPresentationPolicy {
    static func activeTarget(
        isNewThreadPresented: Bool,
        isWorkflowEditorPresented: Bool,
        isPairingPresented: Bool,
        isThreadChatPresented: Bool,
        isReaderPresented: Bool
    ) -> RootOverlayFocusTarget? {
        if isNewThreadPresented {
            return .newThread
        }
        if isWorkflowEditorPresented {
            return .workflowName
        }
        if isPairingPresented {
            return .pairing
        }
        if isReaderPresented {
            return .reader
        }
        if isThreadChatPresented {
            return .threadChat
        }
        return nil
    }

    static func blocksGraphCanvas(_ target: RootOverlayFocusTarget?) -> Bool {
        guard let target else { return false }
        return !target.isPresentedInsideGraphCanvas
    }

    static func blocksRootShell(_ target: RootOverlayFocusTarget?) -> Bool {
        target != nil
    }
}

/// Captures the pre-overlay AppKit responder and restores it after the final
/// custom overlay closes. Overlay-to-overlay transitions retain the original
/// target instead of capturing a control inside the outgoing overlay.
@MainActor
final class RootOverlayKeyboardFocusRestorer {
    private weak var window: NSWindow?
    private weak var responder: NSResponder?

    func transition(
        from previous: RootOverlayFocusTarget?,
        to current: RootOverlayFocusTarget?
    ) {
        if previous == nil, current != nil {
            window = NSApp.keyWindow
            responder = window?.firstResponder
            return
        }
        guard previous != nil, current == nil else { return }
        window?.makeFirstResponder(responder)
        window = nil
        responder = nil
    }
}

/// Defines the initial workflow bootstrap ordering shared by launch and later
/// workflow switches. Memberships are published before supervisor consumers
/// receive the active thread set.
@MainActor
enum RootWorkflowBootstrap {
    static func run(
        refreshWorkflowLibrary: () async -> Void,
        loadGraph: () async -> Void,
        loadSnapshot: () async throws -> WorkflowSnapshot,
        activeWorkflowID: () -> String?,
        workflowThreadRefs: () -> [ThreadRef],
        publishMemberships: ([String: [ThreadWorkflowMembership]]) -> Void,
        publishWorkflowThreads: ([ThreadRef]) async -> Void
    ) async throws {
        await refreshWorkflowLibrary()
        await loadGraph()
        let snapshot = try await loadSnapshot()
        let memberships = ThreadWorkflowMembership.map(
            workflows: snapshot.library.workflows,
            graphsByWorkflowID: snapshot.graphsByWorkflowID,
            activeWorkflowID: activeWorkflowID() ?? snapshot.library.activeWorkflowID
        )
        publishMemberships(memberships)
        await publishWorkflowThreads(workflowThreadRefs())
    }
}
#endif
