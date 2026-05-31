import MapofAgentsCore
import SwiftUI

struct WorkflowActivityRailView: View {
    var events: [WorkflowEvent]
    @Binding var notificationPreferences: WorkflowNotificationPreferences
    var threadTitle: (WorkflowEvent) -> String
    var turnOriginTitle: (WorkflowEvent) -> String?
    var onSelect: (WorkflowEvent) -> Void
    @AppStorage("mapofagents.panel.activity.collapsed") private var isCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Activity", systemImage: "waveform.path.ecg")
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
                .accessibilityLabel(isCollapsed ? "Expand activity" : "Minimize activity")

                Menu {
                    Toggle("Completed", isOn: $notificationPreferences.notifyOnCompleted)
                    Toggle("Needs Input", isOn: $notificationPreferences.notifyOnNeedsInput)
                    Toggle("Failed", isOn: $notificationPreferences.notifyOnFailed)
                } label: {
                    Image(systemName: "bell.badge")
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.button)
                .help("Notification preferences")
                .accessibilityLabel("Notification preferences")
            }

            if !isCollapsed {
                if events.isEmpty {
                    Text("No workflow activity yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    Text("\(events.count) event\(events.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(events) { event in
                                Button {
                                    onSelect(event)
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: icon(for: event.kind))
                                            .foregroundStyle(color(for: event.kind))
                                            .frame(width: 16)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(title(for: event))
                                                .font(.caption.weight(.semibold))
                                                .lineLimit(1)

                                            Text(detail(for: event))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }

                                        Spacer(minLength: 8)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(title(for: event))
                                .accessibilityValue(detail(for: event))
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                    .scrollIndicators(.visible)
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

    private func title(for event: WorkflowEvent) -> String {
        let name = threadTitle(event)
        switch event.kind {
        case .turnStarted:
            return "\(name) started"
        case .turnCompleted:
            return "\(name) finished"
        case .threadCreated:
            if let title = event.childTitle, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "\(name) created \(title)"
            }
            return "\(name) created a thread"
        case .needsInput:
            return "\(name) needs input"
        case .failed:
            return "\(name) failed"
        }
    }

    private func detail(for event: WorkflowEvent) -> String {
        let summary = event.summary.isEmpty ? event.method : event.summary
        if let origin = turnOriginTitle(event) {
            switch event.kind {
            case .turnStarted:
                return "\(event.createdAt.formatted(date: .omitted, time: .shortened)) - Started by \(origin)"
            case .turnCompleted:
                return "\(event.createdAt.formatted(date: .omitted, time: .shortened)) - Triggered by \(origin)"
            case .threadCreated, .needsInput, .failed:
                break
            }
        }
        return "\(event.createdAt.formatted(date: .omitted, time: .shortened)) - \(summary)"
    }

    private func icon(for kind: WorkflowEventKind) -> String {
        switch kind {
        case .turnStarted:
            return "arrow.triangle.2.circlepath"
        case .turnCompleted:
            return "checkmark.circle"
        case .threadCreated:
            return "plus.circle"
        case .needsInput:
            return "exclamationmark.bubble"
        case .failed:
            return "xmark.octagon"
        }
    }

    private func color(for kind: WorkflowEventKind) -> Color {
        switch kind {
        case .turnStarted:
            return .blue
        case .turnCompleted:
            return .green
        case .threadCreated:
            return .orange
        case .needsInput:
            return .orange
        case .failed:
            return .red
        }
    }
}
