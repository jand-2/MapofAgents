import Foundation
import Testing
@testable import MapofAgentsUI

@MainActor
@Test
func transcriptScrollSessionTracksStableTargetsWithoutGeometry() {
    let session = ThreadTranscriptScrollSession()

    session.reconcileNavigationEntryIDs(["first", "second"])
    #expect(session.currentUserMessageID == "first")

    session.updateVisibleTarget(.userMessage("second"))
    #expect(session.visibleTarget == .userMessage("second"))
    #expect(session.currentUserMessageID == "second")
    #expect(!session.isNearBottom)

    session.updateVisibleTarget(.bottom)
    #expect(session.visibleTarget == .bottom)
    #expect(session.isNearBottom)

    session.updateIsNearBottom(false)
    #expect(!session.isNearBottom)
    session.updateVisibleTarget(.userMessage("first"), updatesBottomProximity: false)
    #expect(!session.isNearBottom)
}

@MainActor
@Test
func transcriptScrollSessionPreservesManualPositionAndSurfacesNewContent() {
    let session = ThreadTranscriptScrollSession()
    let selectionTime = Date(timeIntervalSinceReferenceDate: 1_000)

    session.selectUserMessage("first", at: selectionTime)
    #expect(session.isManualNavigationActive(at: selectionTime.addingTimeInterval(1)))
    #expect(!session.isManualNavigationActive(at: selectionTime.addingTimeInterval(2)))
    #expect(!session.shouldAutoScrollForContentChange())
    #expect(session.hasUnseenLatestContent)

    session.prepareToJumpToLatest()
    #expect(session.isNearBottom)
    #expect(!session.hasUnseenLatestContent)
    #expect(session.shouldAutoScrollForContentChange())
}

@MainActor
@Test
func transcriptScrollSessionConsumesOlderMessageAnchorOnce() {
    let session = ThreadTranscriptScrollSession()

    session.beginLoadingOlder(anchor: .userMessage("oldest-visible"))
    #expect(session.pendingOlderAnchor == .userMessage("oldest-visible"))
    #expect(session.takePendingOlderAnchor() == .userMessage("oldest-visible"))
    #expect(session.takePendingOlderAnchor() == nil)
}
