#if os(macOS)
import Testing
@testable import MapofAgentsApp

@Test
func rootModalPolicyBlocksShellButKeepsCanvasOwnedModalReachable() {
    let chat = RootModalPresentationPolicy.activeTarget(
        isNewThreadPresented: false,
        isWorkflowEditorPresented: false,
        isPairingPresented: false,
        isThreadChatPresented: true,
        isReaderPresented: false
    )
    let reader = RootModalPresentationPolicy.activeTarget(
        isNewThreadPresented: false,
        isWorkflowEditorPresented: false,
        isPairingPresented: false,
        isThreadChatPresented: true,
        isReaderPresented: true
    )

    #expect(chat == .threadChat)
    #expect(RootModalPresentationPolicy.blocksRootShell(chat))
    #expect(!RootModalPresentationPolicy.blocksGraphCanvas(chat))

    #expect(reader == .reader)
    #expect(RootModalPresentationPolicy.blocksRootShell(reader))
    #expect(!RootModalPresentationPolicy.blocksGraphCanvas(reader))
}

@Test
func rootModalPolicyBlocksGraphForRootOwnedOverlays() {
    let newThread = RootModalPresentationPolicy.activeTarget(
        isNewThreadPresented: true,
        isWorkflowEditorPresented: true,
        isPairingPresented: true,
        isThreadChatPresented: true,
        isReaderPresented: true
    )

    #expect(newThread == .newThread)
    #expect(RootModalPresentationPolicy.blocksRootShell(newThread))
    #expect(RootModalPresentationPolicy.blocksGraphCanvas(newThread))
}

@Test
func rootModalPolicyLeavesShellAndCanvasActiveWithoutModal() {
    let target = RootModalPresentationPolicy.activeTarget(
        isNewThreadPresented: false,
        isWorkflowEditorPresented: false,
        isPairingPresented: false,
        isThreadChatPresented: false,
        isReaderPresented: false
    )

    #expect(target == nil)
    #expect(!RootModalPresentationPolicy.blocksRootShell(target))
    #expect(!RootModalPresentationPolicy.blocksGraphCanvas(target))
}
#endif
