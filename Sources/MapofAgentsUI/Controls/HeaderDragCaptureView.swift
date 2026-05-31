import SwiftUI

#if os(macOS)
import AppKit

struct HeaderDragCaptureView: NSViewRepresentable {
    var onChanged: (CGSize) -> Void
    var onEnded: (CGSize) -> Void

    func makeNSView(context: Context) -> DragCaptureNSView {
        let view = DragCaptureNSView()
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateNSView(_ nsView: DragCaptureNSView, context: Context) {
        nsView.onChanged = onChanged
        nsView.onEnded = onEnded
    }

    final class DragCaptureNSView: NSView {
        var onChanged: ((CGSize) -> Void)?
        var onEnded: ((CGSize) -> Void)?

        private var startLocation: CGPoint?
        private var latestTranslation: CGSize = .zero

        override var acceptsFirstResponder: Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            startLocation = event.locationInWindow
            latestTranslation = .zero
        }

        override func mouseDragged(with event: NSEvent) {
            guard let startLocation else { return }
            latestTranslation = CGSize(
                width: event.locationInWindow.x - startLocation.x,
                height: startLocation.y - event.locationInWindow.y
            )
            onChanged?(latestTranslation)
        }

        override func mouseUp(with event: NSEvent) {
            if let startLocation {
                latestTranslation = CGSize(
                    width: event.locationInWindow.x - startLocation.x,
                    height: startLocation.y - event.locationInWindow.y
                )
            }
            onEnded?(latestTranslation)
            startLocation = nil
            latestTranslation = .zero
        }
    }
}
#else
struct HeaderDragCaptureView: View {
    var onChanged: (CGSize) -> Void
    var onEnded: (CGSize) -> Void

    var body: some View {
        Color.clear
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        onChanged(value.translation)
                    }
                    .onEnded { value in
                        onEnded(value.translation)
                    }
            )
    }
}
#endif
