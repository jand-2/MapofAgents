import CoreGraphics
import MapofAgentsCore
import Observation

/// Owns transient canvas gesture state and coalesces viewport persistence.
///
/// `GraphCanvasView` remains responsible for attaching SwiftUI gestures, while
/// this model owns their state transitions. That keeps drag/zoom cancellation
/// and latest-write behavior testable without rendering the full canvas.
@MainActor
@Observable
final class CanvasViewportInteractionModel {
    private(set) var nodeDragOffsets: [NodeID: CGSize] = [:]
    private(set) var viewportDragOffset: CGSize = .zero
    private(set) var transientViewport: CanvasViewport?

    @ObservationIgnored private var magnificationStartViewport: CanvasViewport?
    @ObservationIgnored private var viewportCommitTask: Task<Void, Never>?

    func displayedViewport(base: CanvasViewport) -> CanvasViewport {
        let viewport = transientViewport ?? base
        return CanvasViewport(
            scale: viewport.scale,
            offset: viewport.offset.offsetBy(
                dx: viewportDragOffset.width,
                dy: viewportDragOffset.height
            )
        )
    }

    func updatePan(translation: CGSize) {
        viewportDragOffset = translation
    }

    func finishPan(translation: CGSize, base: CanvasViewport) -> CanvasViewport {
        let viewport = transientViewport ?? base
        let committed = CanvasViewport(
            scale: viewport.scale,
            offset: viewport.offset.offsetBy(dx: translation.width, dy: translation.height)
        )
        viewportDragOffset = .zero
        viewportCommitTask?.cancel()
        viewportCommitTask = nil
        transientViewport = nil
        return committed
    }

    func updateMagnification(_ magnification: Double, base: CanvasViewport) {
        let viewport: CanvasViewport
        if let magnificationStartViewport {
            viewport = magnificationStartViewport
        } else {
            viewport = transientViewport ?? base
            magnificationStartViewport = viewport
        }
        transientViewport = scaledViewport(viewport, magnification: magnification)
    }

    func finishMagnification(_ magnification: Double, base: CanvasViewport) -> CanvasViewport {
        let viewport = magnificationStartViewport ?? transientViewport ?? base
        let committed = scaledViewport(viewport, magnification: magnification)
        magnificationStartViewport = nil
        transientViewport = committed
        return committed
    }

    func scrollWheelViewport(delta: Double, base: CanvasViewport) -> CanvasViewport {
        let clampedDelta = min(80, max(-80, delta))
        let factor = pow(1.0028, clampedDelta)
        let next = scaledViewport(transientViewport ?? base, magnification: factor)
        transientViewport = next
        return next
    }

    func scheduleCommit(
        _ viewport: CanvasViewport,
        delay: Duration = .milliseconds(160),
        persist: @escaping @MainActor (CanvasViewport) async -> Void
    ) {
        viewportCommitTask?.cancel()
        transientViewport = viewport
        viewportCommitTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await persist(viewport)
            guard let self else { return }
            if self.transientViewport == viewport {
                self.transientViewport = nil
            }
            self.viewportCommitTask = nil
        }
    }

    func reconcilePersistedViewport(_ viewport: CanvasViewport) {
        if transientViewport == viewport {
            transientViewport = nil
        }
    }

    func updateNodeDrag(_ nodeID: NodeID, translation: CGSize, scale: Double) {
        nodeDragOffsets[nodeID] = graphTranslation(translation, scale: scale)
    }

    func finishNodeDrag(_ node: CanvasNode, translation: CGSize, scale: Double) -> CanvasPoint {
        nodeDragOffsets[node.id] = nil
        return node.position.translated(by: graphTranslation(translation, scale: scale))
    }

    func cancel() {
        viewportCommitTask?.cancel()
        viewportCommitTask = nil
        magnificationStartViewport = nil
        viewportDragOffset = .zero
        transientViewport = nil
        nodeDragOffsets.removeAll()
    }

    private func scaledViewport(_ viewport: CanvasViewport, magnification: Double) -> CanvasViewport {
        CanvasViewport(
            scale: min(1.8, max(0.45, viewport.scale * magnification)),
            offset: viewport.offset
        )
    }

    private func graphTranslation(_ translation: CGSize, scale: Double) -> CGSize {
        let safeScale = max(0.1, scale)
        return CGSize(
            width: translation.width / safeScale,
            height: translation.height / safeScale
        )
    }
}
