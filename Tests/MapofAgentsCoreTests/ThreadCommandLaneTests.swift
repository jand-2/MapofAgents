import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func threadCommandLaneSerializesCommandsForTheSameThread() async throws {
    let lane = ThreadCommandLane()
    let identity = "codex::host-a::thread-1"
    let first = try await lane.acquire(for: identity)

    let secondTask = Task {
        try await lane.acquire(for: identity)
    }

    #expect(await waitForQueuedCommand(on: lane, identity: identity))
    #expect(await lane.activeIdentityCount() == 1)

    await lane.release(first)
    let second = try await secondTask.value

    #expect(await lane.waitingCommandCount(for: identity) == 0)
    #expect(await lane.activeIdentityCount() == 1)

    await lane.release(second)
    #expect(await lane.activeIdentityCount() == 0)
}

@Test
func threadCommandLaneAllowsDifferentThreadsToProceedIndependently() async throws {
    let lane = ThreadCommandLane()
    let first = try await lane.acquire(for: "codex::host-a::thread-1")
    let second = try await lane.acquire(for: "codex::host-a::thread-2")

    #expect(await lane.activeIdentityCount() == 2)
    #expect(await lane.waitingCommandCount(for: "codex::host-a::thread-1") == 0)
    #expect(await lane.waitingCommandCount(for: "codex::host-a::thread-2") == 0)

    await lane.release(first)
    await lane.release(second)
    #expect(await lane.activeIdentityCount() == 0)
}

@Test
func cancellingQueuedThreadCommandRemovesItWithoutBlockingTheLane() async throws {
    let lane = ThreadCommandLane()
    let identity = "codex::host-a::thread-cancel"
    let first = try await lane.acquire(for: identity)
    let cancelledTask = Task {
        try await lane.acquire(for: identity)
    }

    #expect(await waitForQueuedCommand(on: lane, identity: identity))
    cancelledTask.cancel()
    do {
        _ = try await cancelledTask.value
        Issue.record("Cancelled acquisition unexpectedly returned a permit")
    } catch is CancellationError {
        // Expected.
    } catch {
        Issue.record("Cancelled acquisition failed with \(error)")
    }

    #expect(await lane.waitingCommandCount(for: identity) == 0)
    #expect(await lane.activeIdentityCount() == 1)
    await lane.release(first)
    #expect(await lane.activeIdentityCount() == 0)
}

@Test
func cancellingMiddleWaiterPreservesFIFOForRemainingCommands() async throws {
    let lane = ThreadCommandLane()
    let identity = "codex::host-a::thread-fifo-cancel"
    let first = try await lane.acquire(for: identity)
    let secondTask = Task { try await lane.acquire(for: identity) }
    let thirdTask = Task { try await lane.acquire(for: identity) }

    #expect(await waitForQueuedCommandCount(2, on: lane, identity: identity))
    secondTask.cancel()
    _ = try? await secondTask.value
    #expect(await waitForQueuedCommandCount(1, on: lane, identity: identity))

    await lane.release(first)
    let third = try await thirdTask.value
    #expect(await lane.waitingCommandCount(for: identity) == 0)
    await lane.release(third)
    #expect(await lane.activeIdentityCount() == 0)
}

@Test
func cancelAllDrainsQueuedCommandsAndLetsActivePermitFinish() async throws {
    let lane = ThreadCommandLane()
    let identity = "codex::host-a::thread-stop"
    let active = try await lane.acquire(for: identity)
    let queuedTask = Task { try await lane.acquire(for: identity) }

    #expect(await waitForQueuedCommand(on: lane, identity: identity))
    await lane.cancelAll()
    _ = try? await queuedTask.value

    #expect(await lane.waitingCommandCount(for: identity) == 0)
    #expect(await lane.activeIdentityCount() == 1)
    await lane.release(active)
    #expect(await lane.activeIdentityCount() == 0)
}

private func waitForQueuedCommand(
    on lane: ThreadCommandLane,
    identity: String
) async -> Bool {
    for _ in 0..<1_000 {
        if await lane.waitingCommandCount(for: identity) == 1 {
            return true
        }
        await Task.yield()
    }
    return false
}

private func waitForQueuedCommandCount(
    _ expectedCount: Int,
    on lane: ThreadCommandLane,
    identity: String
) async -> Bool {
    for _ in 0..<1_000 {
        if await lane.waitingCommandCount(for: identity) == expectedCount {
            return true
        }
        await Task.yield()
    }
    return false
}
