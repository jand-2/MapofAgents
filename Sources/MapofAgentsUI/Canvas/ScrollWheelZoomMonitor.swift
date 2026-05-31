import SwiftUI

#if os(macOS)
import AppKit

struct ScrollWheelZoomMonitor: NSViewRepresentable {
    var ignoredRects: [CGRect] = []
    var onScroll: (Double) -> Void

    @MainActor
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(for: view, onScroll: onScroll)
        return view
    }

    @MainActor
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.ignoredRects = ignoredRects
        context.coordinator.updateGeometry(for: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: @unchecked Sendable {
        weak var view: NSView?
        var onScroll: ((Double) -> Void)?
        var ignoredRects: [CGRect] = []
        private var windowNumber: Int?
        private var frameInWindow: CGRect = .zero
        private var monitor: Any?

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        @MainActor
        func install(for view: NSView, onScroll: @escaping (Double) -> Void) {
            self.view = view
            self.onScroll = onScroll
            updateGeometry(for: view)
            DispatchQueue.main.async { [weak self, weak view] in
                guard let view else { return }
                self?.updateGeometry(for: view)
            }
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.contains(event), !self.ignores(event) else {
                    return event
                }

                let delta = event.scrollingDeltaY
                guard abs(delta) > 0.1 else {
                    return event
                }

                self.onScroll?(Double(delta))
                return nil
            }
        }

        @MainActor
        func updateGeometry(for view: NSView) {
            guard let window = view.window else {
                windowNumber = nil
                frameInWindow = .zero
                return
            }

            windowNumber = window.windowNumber
            frameInWindow = view.convert(view.bounds, to: nil)
        }

        private func contains(_ event: NSEvent) -> Bool {
            guard event.windowNumber == windowNumber else {
                return false
            }
            return frameInWindow.contains(event.locationInWindow)
        }

        private func ignores(_ event: NSEvent) -> Bool {
            guard !ignoredRects.isEmpty else {
                return false
            }

            let pointInView = CGPoint(
                x: event.locationInWindow.x - frameInWindow.minX,
                y: frameInWindow.height - (event.locationInWindow.y - frameInWindow.minY)
            )
            return ignoredRects.contains { rect in
                rect.contains(pointInView)
            }
        }
    }
}
#else
struct ScrollWheelZoomMonitor: View {
    var ignoredRects: [CGRect] = []
    var onScroll: (Double) -> Void

    var body: some View {
        Color.clear
    }
}
#endif
