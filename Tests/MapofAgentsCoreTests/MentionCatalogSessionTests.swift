import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func mentionCatalogSessionSingleFlightsMatchingContexts() async {
    let session = MentionCatalogSession()
    let probe = MentionCatalogLoaderProbe()
    let key = MentionCatalogSession.Key(
        scope: "local-host",
        rootPath: "/Users/example/project"
    )

    let first = Task {
        await session.candidates(for: key) { await probe.load() }
    }
    let second = Task {
        await session.candidates(for: key) { await probe.load() }
    }

    await waitUntil { await probe.callCount == 1 }
    #expect(await probe.callCount == 1)
    await probe.release()

    let firstResult = await first.value
    let secondResult = await second.value
    #expect(firstResult == MentionCatalogLoaderProbe.result)
    #expect(secondResult == MentionCatalogLoaderProbe.result)
    #expect(await session.activeLoadCount() == 0)
}

@Test
func mentionCatalogSessionCancelsAnUnobservedLoad() async {
    let session = MentionCatalogSession()
    let probe = MentionCatalogLoaderProbe()
    let key = MentionCatalogSession.Key(
        scope: "local-host",
        rootPath: "/Users/example/other-project"
    )
    let request = Task {
        await session.candidates(for: key) { await probe.load() }
    }

    await waitUntil { await probe.callCount == 1 }
    request.cancel()

    #expect(await request.value.isEmpty)
    await waitUntil {
        let hasNoActiveLoad = await session.activeLoadCount() == 0
        let wasCancelled = await probe.wasCancelled
        return hasNoActiveLoad && wasCancelled
    }
    #expect(await probe.wasCancelled)
    #expect(await session.activeLoadCount() == 0)
}

@Test
func mentionCatalogPublicationRejectsStaleGenerations() {
    var generations = MentionCatalogPublicationGeneration()
    let first = generations.begin()
    let second = generations.begin()

    #expect(!generations.accepts(first))
    #expect(generations.accepts(second))
}

private actor MentionCatalogLoaderProbe {
    static let result = [
        MentionCandidate(
            id: "file:readme",
            kind: .file,
            trigger: "@README.md",
            label: "README.md",
            title: "README.md",
            subtitle: "File",
            insertionText: "@README.md"
        )
    ]

    private(set) var callCount = 0
    private(set) var wasCancelled = false
    private var isReleased = false

    func load() async -> [MentionCandidate] {
        callCount += 1
        do {
            while !isReleased {
                try await Task.sleep(for: .milliseconds(5))
            }
        } catch is CancellationError {
            wasCancelled = true
            return []
        } catch {
            return []
        }
        return Self.result
    }

    func release() {
        isReleased = true
    }
}

private func waitUntil(
    maximumYields: Int = 2_000,
    _ condition: @escaping @Sendable () async -> Bool
) async {
    for _ in 0..<maximumYields {
        if await condition() {
            return
        }
        await Task.yield()
    }
}
