import Foundation
import Observation

enum ThreadTranscriptScrollTarget: Hashable {
    case userMessage(String)
    case bottom
}

/// Owns the transcript's fast-changing scroll state without invalidating the
/// full thread popover for every visible-target transition.
@MainActor
@Observable
final class ThreadTranscriptScrollSession {
    @ObservationIgnored private(set) var visibleTarget: ThreadTranscriptScrollTarget?
    @ObservationIgnored private(set) var isNearBottom = true
    @ObservationIgnored private(set) var pendingOlderAnchor: ThreadTranscriptScrollTarget?
    @ObservationIgnored private var manualNavigationStartedAt: Date?

    private(set) var currentUserMessageID: String?
    private(set) var hasUnseenLatestContent = false

    func reset() {
        visibleTarget = nil
        isNearBottom = true
        pendingOlderAnchor = nil
        manualNavigationStartedAt = nil
        currentUserMessageID = nil
        hasUnseenLatestContent = false
    }

    func reconcileNavigationEntryIDs(_ entryIDs: [String]) {
        guard !entryIDs.isEmpty else {
            currentUserMessageID = nil
            return
        }
        if currentUserMessageID.map(entryIDs.contains) != true {
            currentUserMessageID = entryIDs.first
        }
    }

    /// Receives ID-based SwiftUI scroll-position changes. Repeated updates for
    /// the same target are discarded before observable state is touched.
    func updateVisibleTarget(
        _ target: ThreadTranscriptScrollTarget?,
        updatesBottomProximity: Bool = true
    ) {
        guard visibleTarget != target else { return }
        visibleTarget = target

        switch target {
        case .userMessage(let messageID):
            if updatesBottomProximity {
                isNearBottom = false
            }
            if currentUserMessageID != messageID {
                currentUserMessageID = messageID
            }
        case .bottom:
            if updatesBottomProximity {
                updateIsNearBottom(true)
            }
        case nil:
            break
        }
    }

    func updateIsNearBottom(_ isNearBottom: Bool) {
        guard self.isNearBottom != isNearBottom else { return }
        self.isNearBottom = isNearBottom
        if isNearBottom, hasUnseenLatestContent {
            hasUnseenLatestContent = false
        }
    }

    func selectUserMessage(_ messageID: String, at date: Date = Date()) {
        currentUserMessageID = messageID
        isNearBottom = false
        pendingOlderAnchor = nil
        manualNavigationStartedAt = date
    }

    func beginLoadingOlder(anchor: ThreadTranscriptScrollTarget?) {
        pendingOlderAnchor = anchor
    }

    func takePendingOlderAnchor() -> ThreadTranscriptScrollTarget? {
        defer { pendingOlderAnchor = nil }
        return pendingOlderAnchor
    }

    func shouldAutoScrollForContentChange() -> Bool {
        guard isNearBottom else {
            if !hasUnseenLatestContent {
                hasUnseenLatestContent = true
            }
            return false
        }
        return true
    }

    func prepareToJumpToLatest() {
        manualNavigationStartedAt = nil
        isNearBottom = true
        hasUnseenLatestContent = false
    }

    func isManualNavigationActive(at date: Date = Date()) -> Bool {
        guard let manualNavigationStartedAt else { return false }
        return date.timeIntervalSince(manualNavigationStartedAt) < 2
    }
}
