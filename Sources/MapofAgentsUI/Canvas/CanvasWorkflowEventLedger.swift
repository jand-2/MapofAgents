import Foundation
import MapofAgentsCore
import Observation

struct CanvasWorkflowEventDelivery: Sendable {
    var event: WorkflowEvent
    var isLive: Bool
}

/// Owns canvas-specific workflow-event delivery and user-turn attribution.
///
/// The ledger makes event replay bounded and deterministic, and gives the
/// transcript presentation one source of truth for whether a user-started turn
/// is still awaiting a response.
@MainActor
@Observable
final class CanvasWorkflowEventLedger {
    private struct PendingUserTurnStart: Hashable {
        var hostID: HostID
        var threadID: String
        var createdAt: Date
    }

    private static let userTurnMarkerLeadWindow: TimeInterval = 5
    private static let userTurnMarkerFollowWindow: TimeInterval = 5 * 60
    private static let userTurnAttributionRetention: TimeInterval = 20 * 60

    private(set) var stateStartedAt: Date
    private(set) var awaitingResponseThreadKeys: Set<String> = []

    @ObservationIgnored private var handledEventIDs: Set<String> = []
    @ObservationIgnored private var handledEventIDOrder: [String] = []
    @ObservationIgnored private var pendingUserTurnStarts: [PendingUserTurnStart] = []
    @ObservationIgnored private var userStartedTurnKeys: [String: Date] = [:]

    init(now: Date = Date()) {
        stateStartedAt = now
    }

    func prime(_ events: [WorkflowEvent], now: Date = Date()) {
        stateStartedAt = now
        let primedEvents = events.reversed()
        handledEventIDs = Set(primedEvents.map(\.dedupeKey))
        handledEventIDOrder = Array(primedEvents.map(\.dedupeKey).suffix(80))
    }

    func deliveries(for events: [WorkflowEvent]) -> [CanvasWorkflowEventDelivery] {
        var deliveries: [CanvasWorkflowEventDelivery] = []
        for event in events.reversed() where !handledEventIDs.contains(event.dedupeKey) {
            handledEventIDs.insert(event.dedupeKey)
            handledEventIDOrder.append(event.dedupeKey)
            captureUserStartedTurnIfNeeded(for: event)
            pruneUserTurnAttribution(now: event.createdAt)
            deliveries.append(
                CanvasWorkflowEventDelivery(
                    event: event,
                    isLive: event.createdAt >= stateStartedAt
                )
            )
        }

        if handledEventIDs.count > 160 {
            handledEventIDOrder = Array(handledEventIDOrder.suffix(80))
            handledEventIDs = Set(handledEventIDOrder)
        }
        return deliveries
    }

    func shouldApplyToRunState(_ event: WorkflowEvent) -> Bool {
        guard event.kind != .threadCreated && event.kind != .folderCreated else {
            return false
        }
        return event.kind != .turnStarted || event.createdAt >= stateStartedAt
    }

    func isLive(_ event: WorkflowEvent) -> Bool {
        event.createdAt >= stateStartedAt
    }

    func markNextTurnStartedByUser(_ threadRef: ThreadRef, now: Date = Date()) {
        pendingUserTurnStarts.removeAll {
            now.timeIntervalSince($0.createdAt) > Self.userTurnMarkerFollowWindow
        }
        pendingUserTurnStarts.append(
            PendingUserTurnStart(
                hostID: threadRef.hostID,
                threadID: threadRef.threadID,
                createdAt: now
            )
        )
    }

    func hasPendingUserTurnStart(for threadRef: ThreadRef, now: Date = Date()) -> Bool {
        pendingUserTurnStarts.contains { marker in
            marker.threadID == threadRef.threadID
                && marker.hostID == threadRef.hostID
                && now.timeIntervalSince(marker.createdAt) <= Self.userTurnMarkerFollowWindow
        }
    }

    func isUserStartedTurn(_ event: WorkflowEvent, in events: [WorkflowEvent]) -> Bool {
        guard let basisEvent = userStartedBasisEvent(for: event, in: events),
              let key = userTurnKey(for: basisEvent) else {
            return false
        }
        return userStartedTurnKeys[key] != nil
    }

    func markAwaiting(_ threadRef: ThreadRef) {
        awaitingResponseThreadKeys.insert(threadRef.qualifiedID)
    }

    func clearAwaiting(_ threadRef: ThreadRef) {
        awaitingResponseThreadKeys.remove(threadRef.qualifiedID)
    }

    func clearAwaiting(key: String) {
        awaitingResponseThreadKeys.remove(key)
    }

    func isAwaiting(_ threadRef: ThreadRef, isRunning: Bool, now: Date = Date()) -> Bool {
        awaitingResponseThreadKeys.contains(threadRef.qualifiedID)
            && (isRunning || hasPendingUserTurnStart(for: threadRef, now: now))
    }

    private func captureUserStartedTurnIfNeeded(for event: WorkflowEvent) {
        guard event.kind == .turnStarted,
              let threadID = event.threadID,
              let key = userTurnKey(for: event) else {
            return
        }

        guard let index = pendingUserTurnStarts.firstIndex(where: { marker in
            marker.threadID == threadID
                && (event.hostID == nil || marker.hostID == event.hostID)
                && event.createdAt.timeIntervalSince(marker.createdAt) >= -Self.userTurnMarkerLeadWindow
                && event.createdAt.timeIntervalSince(marker.createdAt) <= Self.userTurnMarkerFollowWindow
        }) else {
            return
        }

        pendingUserTurnStarts.remove(at: index)
        userStartedTurnKeys[key] = event.createdAt
    }

    private func userStartedBasisEvent(
        for event: WorkflowEvent,
        in events: [WorkflowEvent]
    ) -> WorkflowEvent? {
        guard event.kind == .turnCompleted else {
            return event.kind == .turnStarted ? event : nil
        }

        return events
            .filter { candidate in
                candidate.kind == .turnStarted
                    && candidate.threadID == event.threadID
                    && (event.hostID == nil || candidate.hostID == nil || candidate.hostID == event.hostID)
                    && (event.turnID == nil || candidate.turnID == event.turnID)
                    && candidate.createdAt <= event.createdAt
            }
            .max { $0.createdAt < $1.createdAt }
    }

    private func userTurnKey(for event: WorkflowEvent) -> String? {
        guard let threadID = event.threadID else { return nil }
        let hostID = event.hostID?.rawValue ?? "unknown"
        if let turnID = event.turnID, !turnID.isEmpty {
            return "\(hostID)::\(threadID)::\(turnID)"
        }
        return "\(hostID)::\(threadID)::\(event.dedupeKey)"
    }

    private func pruneUserTurnAttribution(now: Date) {
        pendingUserTurnStarts.removeAll {
            now.timeIntervalSince($0.createdAt) > Self.userTurnMarkerFollowWindow
        }
        userStartedTurnKeys = userStartedTurnKeys.filter { _, createdAt in
            now.timeIntervalSince(createdAt) <= Self.userTurnAttributionRetention
        }
    }
}
