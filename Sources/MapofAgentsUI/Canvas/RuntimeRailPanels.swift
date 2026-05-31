import MapofAgentsCore
import SwiftUI

struct RuntimeDiagnosticsRailView: View {
    var steps: [RuntimeDiagnosticStep]
    @AppStorage("mapofagents.panel.runtimeDiagnostics.collapsed") private var isCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Runtime Diagnostic", systemImage: "stethoscope")
                    .font(.headline)

                Spacer()

                Button {
                    withAnimation(.snappy) {
                        isCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Expand" : "Minimize")
                .accessibilityLabel(isCollapsed ? "Expand runtime diagnostics" : "Minimize runtime diagnostics")
            }

            if !isCollapsed {
                ForEach(steps) { step in
                    HStack(spacing: 8) {
                        Image(systemName: icon(for: step.status))
                            .foregroundStyle(color(for: step.status))
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.title)
                                .font(.caption.weight(.semibold))
                            if !step.detail.isEmpty {
                                Text(step.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 8)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
    }

    private func icon(for status: RuntimeDiagnosticStatus) -> String {
        switch status {
        case .pending:
            return "circle"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .passed:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private func color(for status: RuntimeDiagnosticStatus) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .running:
            return .blue
        case .passed:
            return .green
        case .warning:
            return .orange
        case .failed:
            return .red
        }
    }
}

struct AttentionRequestsRailView: View {
    var requests: [RuntimeAttentionRequest]
    var onFocus: (RuntimeAttentionRequest) -> Void = { _ in }
    var onRespond: (RuntimeAttentionRequest, Bool) -> Void = { _, _ in }
    var onRespondWithText: (RuntimeAttentionRequest, String) -> Void = { _, _ in }
    var onDeclineTyped: (RuntimeAttentionRequest) -> Void = { _ in }
    @AppStorage("mapofagents.panel.attention.collapsed") private var isCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Needs Attention", systemImage: "exclamationmark.bubble")
                    .font(.headline)

                Spacer()

                Button {
                    withAnimation(.snappy) {
                        isCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Expand" : "Minimize")
                .accessibilityLabel(isCollapsed ? "Expand needs attention" : "Minimize needs attention")
            }

            if !isCollapsed {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(requests.sorted(by: { $0.createdAt < $1.createdAt })) { request in
                            AttentionRequestCardView(
                                request: request,
                                onFocus: onFocus,
                                onRespond: onRespond,
                                onRespondWithText: onRespondWithText,
                                onDeclineTyped: onDeclineTyped
                            )
                        }
                    }
                }
                .frame(maxHeight: 360)
                .scrollIndicators(.visible)
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
    }
}

struct AttentionRequestCardView: View {
    var request: RuntimeAttentionRequest
    var onFocus: (RuntimeAttentionRequest) -> Void = { _ in }
    var onRespond: (RuntimeAttentionRequest, Bool) -> Void
    var onRespondWithText: (RuntimeAttentionRequest, String) -> Void
    var onDeclineTyped: (RuntimeAttentionRequest) -> Void

    @State private var responseText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(request.method)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button {
                    onFocus(request)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Open owning thread")
                .accessibilityLabel("Open owning thread")
            }

            Text(request.promptText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if request.supportsApprovalDecision {
                HStack(spacing: 8) {
                    Button("Deny") {
                        onRespond(request, false)
                    }
                    .controlSize(.small)

                    Button("Allow") {
                        onRespond(request, true)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else if request.supportsTypedResponse {
                let choices = request.typedResponseChoices
                if !choices.isEmpty {
                    Picker("Response", selection: $responseText) {
                        ForEach(choices) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .onAppear {
                        if responseText.isEmpty {
                            responseText = request.initialTypedResponseValue
                        }
                    }
                } else {
                    TextField("Response", text: $responseText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }

                HStack(spacing: 8) {
                    Button("Decline") {
                        onDeclineTyped(request)
                    }
                    .controlSize(.small)

                    Button("Send") {
                        onRespondWithText(request, responseText)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}
