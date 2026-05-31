import SwiftUI

public struct FeedbackButton<Label: View>: View {
    var unavailableReason: String?
    var action: () -> Void
    var label: () -> Label

    @State private var visibleReason: String?
    @State private var reasonToken = UUID()

    public init(
        unavailableReason: String?,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.unavailableReason = unavailableReason
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(action: perform) {
            label()
                .opacity(unavailableReason == nil ? 1 : 0.48)
        }
        .accessibilityHint(unavailableReason ?? "")
        .accessibilityValue(unavailableReason.map { "Unavailable: \($0)" } ?? "")
        .overlay(alignment: .top) {
            if let visibleReason {
                ControlFeedbackBubble(message: visibleReason)
                    .offset(y: -42)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                    .allowsHitTesting(false)
                    .zIndex(20)
            }
        }
    }

    private func perform() {
        guard let unavailableReason else {
            action()
            return
        }

        showReason(unavailableReason)
    }

    private func showReason(_ reason: String) {
        let token = UUID()
        reasonToken = token

        withAnimation(.snappy) {
            visibleReason = reason
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2200))
            guard reasonToken == token else { return }
            withAnimation(.snappy) {
                visibleReason = nil
            }
        }
    }
}

public struct ControlFeedbackBubble: View {
    var message: String

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        Text(message)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: 240)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 5)
    }
}
