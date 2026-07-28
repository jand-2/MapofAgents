import MapofAgentsCore
import Testing
@testable import MapofAgentsUI

@Test
func newThreadsDefaultToWorkspaceWrite() {
    let request = NewThreadRequest(
        folderNodeID: NodeID(rawValue: "project"),
        name: "Safe thread",
        modelID: "model",
        reasoningEffort: "medium",
        initialPrompt: "Start"
    )

    #expect(NewThreadPermissionPolicy.defaultPermissions.approvalPolicy == .onRequest)
    #expect(NewThreadPermissionPolicy.defaultPermissions.sandboxMode == .workspaceWrite)
    #expect(request.permissions == NewThreadPermissionPolicy.defaultPermissions)
}

@Test
func codexFullAccessAlwaysRequiresExplicitConfirmation() {
    #expect(NewThreadPermissionPolicy.requiresFullAccessConfirmation(
        provider: .codex,
        sandboxMode: .dangerFullAccess
    ))
    #expect(!NewThreadPermissionPolicy.requiresFullAccessConfirmation(
        provider: .codex,
        sandboxMode: .workspaceWrite
    ))
    #expect(!NewThreadPermissionPolicy.requiresFullAccessConfirmation(
        provider: .gemini,
        sandboxMode: .dangerFullAccess
    ))
}

@Test
func mentionComposerReturnPolicyPreservesDesktopTextEditingConventions() {
    #expect(MentionComposerKeyboardPolicy.returnAction(
        shiftPressed: false,
        hasActiveMentionSuggestions: false
    ) == .submit)
    #expect(MentionComposerKeyboardPolicy.returnAction(
        shiftPressed: true,
        hasActiveMentionSuggestions: false
    ) == .insertNewline)
    #expect(MentionComposerKeyboardPolicy.returnAction(
        shiftPressed: false,
        hasActiveMentionSuggestions: true
    ) == .insertSelectedMention)
    #expect(MentionComposerKeyboardPolicy.returnAction(
        shiftPressed: true,
        hasActiveMentionSuggestions: true
    ) == .insertNewline)
}

@Test
func graphCanvasModalPolicyMakesChatBackgroundInertWithDedicatedDismissal() {
    let presentation = GraphCanvasModalPolicy.presentation(
        isReadingModePresented: false,
        activeThreadKey: "host::thread"
    )

    #expect(presentation == .threadChat)
    #expect(presentation.hidesBackgroundFromAccessibility)
    #expect(!presentation.allowsBackgroundInteraction)
    #expect(presentation.allowsClickOutsideDismissal)
    #expect(!presentation.showsCanvasChrome)
}

@Test
func graphCanvasModalPolicyMakesReaderBackgroundInertWithoutOutsideDismissal() {
    let presentation = GraphCanvasModalPolicy.presentation(
        isReadingModePresented: true,
        activeThreadKey: "host::thread"
    )

    #expect(presentation == .reader)
    #expect(presentation.hidesBackgroundFromAccessibility)
    #expect(!presentation.allowsBackgroundInteraction)
    #expect(!presentation.allowsClickOutsideDismissal)
    #expect(!presentation.showsCanvasChrome)
}

@Test
func graphCanvasModalPolicyLeavesBackgroundInteractiveWithoutModal() {
    let presentation = GraphCanvasModalPolicy.presentation(
        isReadingModePresented: false,
        activeThreadKey: nil
    )

    #expect(presentation == .none)
    #expect(!presentation.hidesBackgroundFromAccessibility)
    #expect(presentation.allowsBackgroundInteraction)
    #expect(!presentation.allowsClickOutsideDismissal)
    #expect(presentation.showsCanvasChrome)
}
