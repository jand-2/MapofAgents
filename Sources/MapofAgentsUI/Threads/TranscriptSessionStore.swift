import Foundation
import MapofAgentsCore
import Observation

enum TranscriptLoadPhase: Hashable {
    case idle
    case connectingHost
    case loadingHistory
    case hydratingArtifacts
    case refreshing
    case loadingOlder

    var title: String {
        switch self {
        case .idle:
            return "Ready"
        case .connectingHost:
            return "Checking host connection"
        case .loadingHistory:
            return "Loading message history"
        case .hydratingArtifacts:
            return "Hydrating artifacts"
        case .refreshing:
            return "Refreshing transcript"
        case .loadingOlder:
            return "Loading older messages"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            return ""
        case .connectingHost:
            return "Waiting on the owning machine or App Server route."
        case .loadingHistory:
            return "Waiting on thread history from Codex App Server."
        case .hydratingArtifacts:
            return "Reading generated files, diffs, or images."
        case .refreshing:
            return "Keeping the last loaded messages visible."
        case .loadingOlder:
            return "Prepending an older transcript page."
        }
    }

    var iconName: String {
        switch self {
        case .idle:
            return "checkmark.circle"
        case .connectingHost:
            return "antenna.radiowaves.left.and.right"
        case .loadingHistory:
            return "text.bubble"
        case .hydratingArtifacts:
            return "shippingbox"
        case .refreshing:
            return "arrow.clockwise"
        case .loadingOlder:
            return "clock.arrow.circlepath"
        }
    }
}

enum TranscriptSessionID: Hashable, Sendable {
    case popover
    case reader(NodeID)
}

struct TranscriptSessionState {
    var threadRef: ThreadRef?
    var transcript: ThreadTranscript?
    var loadPhase: TranscriptLoadPhase = .idle
    var errorMessage: String?
    var isLoading = false
    var isLoadingOlder = false
}

/// Owns transcript state and the tasks that are allowed to mutate it.
///
/// SwiftUI surfaces ask this store to load a session instead of retaining their
/// own task dictionaries and generation counters. A session has at most one
/// primary load, one older-page load, and one live refresh for a thread. Every
/// completion is generation checked before it can publish state.
@MainActor
@Observable
final class TranscriptSessionStore {
    typealias Preparation = @MainActor () async -> Void
    typealias Loader = @MainActor () async throws -> ThreadTranscript
    typealias ErrorFormatter = @MainActor (Error) -> String
    typealias LoadCallback = @MainActor (ThreadTranscript) async -> Void
    typealias FailureCallback = @MainActor (Error, String) async -> Void

    private(set) var popover = TranscriptSessionState()
    private(set) var readers: [NodeID: TranscriptSessionState] = [:]

    @ObservationIgnored private var primaryLoads: [TranscriptSessionID: LoadRegistration] = [:]
    @ObservationIgnored private var olderLoads: [TranscriptSessionID: LoadRegistration] = [:]
    @ObservationIgnored private var liveRefreshes: [String: LiveRefreshRegistration] = [:]
    @ObservationIgnored private var activeLiveRefreshPasses: Set<String> = []

    private struct LoadRegistration {
        var id: UUID
        var threadKey: String
        var task: Task<Void, Never>
    }

    private struct LiveRefreshRegistration {
        var id: UUID
        var task: Task<Void, Never>
    }

    func state(for sessionID: TranscriptSessionID) -> TranscriptSessionState {
        switch sessionID {
        case .popover:
            return popover
        case .reader(let nodeID):
            return readers[nodeID] ?? TranscriptSessionState()
        }
    }

    func readerState(for nodeID: NodeID) -> TranscriptSessionState {
        readers[nodeID] ?? TranscriptSessionState()
    }

    @discardableResult
    func load(
        _ sessionID: TranscriptSessionID,
        threadRef: ThreadRef,
        force: Bool,
        prepare: @escaping Preparation = {},
        loader: @escaping Loader,
        errorMessage: @escaping ErrorFormatter,
        onLoaded: @escaping LoadCallback = { _ in },
        onFailure: @escaping FailureCallback = { _, _ in }
    ) -> Task<Void, Never> {
        let currentState = state(for: sessionID)
        if !force, currentState.threadRef == threadRef, currentState.transcript != nil {
            return Task {}
        }

        if !force,
           let registration = primaryLoads[sessionID],
           registration.threadKey == threadRef.qualifiedID {
            return registration.task
        }

        cancelPrimaryLoad(for: sessionID)
        cancelOlderLoad(for: sessionID)
        if currentState.threadRef != threadRef {
            replaceState(for: sessionID, with: TranscriptSessionState(threadRef: threadRef))
        }

        updateState(for: sessionID) { state in
            state.threadRef = threadRef
            state.isLoading = true
            state.isLoadingOlder = false
            state.loadPhase = state.transcript?.messages.isEmpty == false ? .refreshing : .connectingHost
            state.errorMessage = nil
        }

        let loadID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.waitForLiveRefreshPassToFinish(threadKey: threadRef.qualifiedID)
            guard !Task.isCancelled,
                  self.isCurrentPrimaryLoad(loadID, for: sessionID, threadRef: threadRef) else {
                return
            }
            await prepare()
            guard !Task.isCancelled, self.isCurrentPrimaryLoad(loadID, for: sessionID, threadRef: threadRef) else {
                return
            }

            self.updateState(for: sessionID) { $0.loadPhase = .loadingHistory }
            do {
                let transcript = try await loader()
                guard !Task.isCancelled,
                      self.isCurrentPrimaryLoad(loadID, for: sessionID, threadRef: threadRef) else {
                    return
                }
                self.updateState(for: sessionID) { state in
                    state.loadPhase = .hydratingArtifacts
                    state.transcript = transcript
                    state.errorMessage = nil
                }
                await onLoaded(transcript)
            } catch {
                guard !Task.isCancelled,
                      self.isCurrentPrimaryLoad(loadID, for: sessionID, threadRef: threadRef) else {
                    return
                }
                let message = errorMessage(error)
                self.updateState(for: sessionID) { state in
                    state.errorMessage = message
                    if state.transcript?.threadRef != threadRef || state.transcript?.messages.isEmpty != false {
                        state.transcript = ThreadTranscript(threadRef: threadRef)
                    }
                }
                await onFailure(error, message)
            }

            self.finishPrimaryLoad(loadID, for: sessionID, threadRef: threadRef)
        }
        primaryLoads[sessionID] = LoadRegistration(
            id: loadID,
            threadKey: threadRef.qualifiedID,
            task: task
        )
        return task
    }

    @discardableResult
    func loadOlder(
        _ sessionID: TranscriptSessionID,
        threadRef: ThreadRef,
        loader: @escaping @MainActor (_ cursor: String) async throws -> ThreadTranscript,
        errorMessage: @escaping ErrorFormatter
    ) -> Task<Void, Never>? {
        guard primaryLoads[sessionID] == nil,
              olderLoads[sessionID] == nil,
              let cursor = state(for: sessionID).transcript?.nextCursor,
              !cursor.isEmpty,
              state(for: sessionID).threadRef == threadRef,
              !activeLiveRefreshPasses.contains(threadRef.qualifiedID) else {
            return olderLoads[sessionID]?.task
        }

        updateState(for: sessionID) { state in
            state.isLoadingOlder = true
            state.loadPhase = .loadingOlder
        }

        let loadID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let olderPage = try await loader(cursor)
                guard !Task.isCancelled,
                      self.isCurrentOlderLoad(loadID, for: sessionID, threadRef: threadRef) else {
                    return
                }
                self.updateState(for: sessionID) { state in
                    state.transcript = state.transcript?.prependingOlderPage(olderPage) ?? olderPage
                    state.errorMessage = nil
                }
            } catch {
                guard !Task.isCancelled,
                      self.isCurrentOlderLoad(loadID, for: sessionID, threadRef: threadRef) else {
                    return
                }
                let message = errorMessage(error)
                self.updateState(for: sessionID) { $0.errorMessage = message }
            }
            self.finishOlderLoad(loadID, for: sessionID, threadRef: threadRef)
        }
        olderLoads[sessionID] = LoadRegistration(
            id: loadID,
            threadKey: threadRef.qualifiedID,
            task: task
        )
        return task
    }

    func resetPopover() {
        cancelLoads(for: .popover)
        popover = TranscriptSessionState()
    }

    func cancelPopoverLoad() {
        cancelLoads(for: .popover)
    }

    func removeReader(_ nodeID: NodeID) {
        let sessionID = TranscriptSessionID.reader(nodeID)
        cancelLoads(for: sessionID)
        readers[nodeID] = nil
    }

    func removeReaders<S: Sequence>(_ nodeIDs: S) where S.Element == NodeID {
        for nodeID in nodeIDs {
            removeReader(nodeID)
        }
    }

    func removeAllReaders() {
        removeReaders(Array(readers.keys))
    }

    func cancelAll() {
        for registration in primaryLoads.values {
            registration.task.cancel()
        }
        for registration in olderLoads.values {
            registration.task.cancel()
        }
        for registration in liveRefreshes.values {
            registration.task.cancel()
        }
        primaryLoads.removeAll()
        olderLoads.removeAll()
        liveRefreshes.removeAll()
        activeLiveRefreshPasses.removeAll()
    }

    func clearError(for sessionID: TranscriptSessionID) {
        updateState(for: sessionID) { $0.errorMessage = nil }
    }

    func setError(_ message: String?, for sessionID: TranscriptSessionID) {
        updateState(for: sessionID) { $0.errorMessage = message }
    }

    func appendLocalMessage(_ message: ThreadMessage, to sessionID: TranscriptSessionID, threadRef: ThreadRef) {
        updateState(for: sessionID) { state in
            var transcript = state.transcript ?? ThreadTranscript(threadRef: threadRef)
            transcript.messages.append(message)
            state.threadRef = threadRef
            state.transcript = transcript
        }
    }

    func removeLocalMessage(id: String, from sessionID: TranscriptSessionID, threadRef: ThreadRef) {
        updateState(for: sessionID) { state in
            guard state.transcript?.threadRef == threadRef else { return }
            state.transcript?.messages.removeAll { $0.id == id }
        }
    }

    func merge(_ serverTranscript: ThreadTranscript, into sessionID: TranscriptSessionID) {
        updateState(for: sessionID) { state in
            state.threadRef = serverTranscript.threadRef
            state.transcript = Self.merging(state.transcript, with: serverTranscript)
            state.errorMessage = nil
        }
    }

    @discardableResult
    func startLiveRefresh(
        for threadRef: ThreadRef,
        interval: Duration = .milliseconds(900),
        maximumIterations: Int = 240,
        isOpen: @escaping @MainActor () -> Bool,
        refresh: @escaping @MainActor () async -> Void,
        shouldContinue: @escaping @MainActor () -> Bool,
        onFinished: @escaping @MainActor () -> Void
    ) -> Bool {
        let key = threadRef.qualifiedID
        guard isOpen(), liveRefreshes[key] == nil else { return false }

        let refreshID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.finishLiveRefresh(refreshID, key: key) }

            for _ in 0..<maximumIterations {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard !Task.isCancelled, isOpen() else { return }
                guard !self.hasActiveLoad(threadKey: key),
                      !self.activeLiveRefreshPasses.contains(key) else {
                    continue
                }
                self.activeLiveRefreshPasses.insert(key)
                await refresh()
                self.activeLiveRefreshPasses.remove(key)
                guard shouldContinue() else {
                    onFinished()
                    return
                }
            }
            onFinished()
        }
        liveRefreshes[key] = LiveRefreshRegistration(id: refreshID, task: task)
        return true
    }

    func cancelLiveRefresh(for key: String) {
        liveRefreshes.removeValue(forKey: key)?.task.cancel()
    }

    func waitForLiveRefresh(for threadRef: ThreadRef) async {
        await liveRefreshes[threadRef.qualifiedID]?.task.value
    }

    var liveRefreshCount: Int {
        liveRefreshes.count
    }

    private func replaceState(for sessionID: TranscriptSessionID, with state: TranscriptSessionState) {
        switch sessionID {
        case .popover:
            popover = state
        case .reader(let nodeID):
            readers[nodeID] = state
        }
    }

    private func updateState(
        for sessionID: TranscriptSessionID,
        _ update: (inout TranscriptSessionState) -> Void
    ) {
        var state = state(for: sessionID)
        update(&state)
        replaceState(for: sessionID, with: state)
    }

    private func cancelLoads(for sessionID: TranscriptSessionID) {
        cancelPrimaryLoad(for: sessionID)
        cancelOlderLoad(for: sessionID)
    }

    private func cancelPrimaryLoad(for sessionID: TranscriptSessionID) {
        primaryLoads.removeValue(forKey: sessionID)?.task.cancel()
    }

    private func cancelOlderLoad(for sessionID: TranscriptSessionID) {
        olderLoads.removeValue(forKey: sessionID)?.task.cancel()
    }

    private func hasActiveLoad(threadKey: String) -> Bool {
        primaryLoads.values.contains { $0.threadKey == threadKey }
            || olderLoads.values.contains { $0.threadKey == threadKey }
    }

    private func waitForLiveRefreshPassToFinish(threadKey: String) async {
        while activeLiveRefreshPasses.contains(threadKey), !Task.isCancelled {
            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                return
            }
        }
    }

    private func isCurrentPrimaryLoad(
        _ id: UUID,
        for sessionID: TranscriptSessionID,
        threadRef: ThreadRef
    ) -> Bool {
        primaryLoads[sessionID]?.id == id && state(for: sessionID).threadRef == threadRef
    }

    private func isCurrentOlderLoad(
        _ id: UUID,
        for sessionID: TranscriptSessionID,
        threadRef: ThreadRef
    ) -> Bool {
        olderLoads[sessionID]?.id == id && state(for: sessionID).threadRef == threadRef
    }

    private func finishPrimaryLoad(_ id: UUID, for sessionID: TranscriptSessionID, threadRef: ThreadRef) {
        guard isCurrentPrimaryLoad(id, for: sessionID, threadRef: threadRef) else { return }
        primaryLoads[sessionID] = nil
        updateState(for: sessionID) { state in
            state.isLoading = false
            state.loadPhase = .idle
        }
    }

    private func finishOlderLoad(_ id: UUID, for sessionID: TranscriptSessionID, threadRef: ThreadRef) {
        guard isCurrentOlderLoad(id, for: sessionID, threadRef: threadRef) else { return }
        olderLoads[sessionID] = nil
        updateState(for: sessionID) { state in
            state.isLoadingOlder = false
            state.loadPhase = .idle
        }
    }

    private func finishLiveRefresh(_ id: UUID, key: String) {
        guard liveRefreshes[key]?.id == id else { return }
        liveRefreshes[key] = nil
        activeLiveRefreshPasses.remove(key)
    }

    static func merging(_ existing: ThreadTranscript?, with serverTranscript: ThreadTranscript) -> ThreadTranscript {
        guard existing?.threadRef == serverTranscript.threadRef else {
            return serverTranscript
        }

        var mergedTranscript = serverTranscript
        var seenIDs = Set(serverTranscript.messages.map(\.id))
        let existingLoadedMessages = existing?.messages.filter { message in
            !message.id.hasPrefix("local-") && seenIDs.insert(message.id).inserted
        } ?? []
        let localOnlyMessages = existing?.messages.filter { message in
            message.id.hasPrefix("local-")
                && !serverTranscript.messages.contains { serverMessage in
                    serverMessageRepresentsLocalMessage(serverMessage, localMessage: message)
                }
        } ?? []
        mergedTranscript.messages = (existingLoadedMessages + serverTranscript.messages + localOnlyMessages)
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.createdAt == rhs.element.createdAt {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.createdAt < rhs.element.createdAt
            }
            .map(\.element)
        if (existing?.messages.count ?? 0) > serverTranscript.messages.count {
            mergedTranscript.nextCursor = existing?.nextCursor
        }
        return mergedTranscript
    }

    private static func serverMessageRepresentsLocalMessage(
        _ serverMessage: ThreadMessage,
        localMessage: ThreadMessage
    ) -> Bool {
        guard serverMessage.role == localMessage.role else { return false }
        if serverMessage.text == localMessage.text { return true }
        guard localMessage.role == .user else {
            return false
        }
        let serverPresentation = WorkflowPromptEnvelope.presentation(for: serverMessage.text)
        let localPresentation = WorkflowPromptEnvelope.presentation(for: localMessage.text)
        return serverPresentation.visibleText == localPresentation.visibleText
            && (
                serverPresentation.visibleText != serverMessage.text
                    || localPresentation.visibleText != localMessage.text
            )
    }
}
