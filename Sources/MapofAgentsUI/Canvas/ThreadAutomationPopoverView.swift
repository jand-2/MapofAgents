import MapofAgentsCore
import SwiftUI

struct ThreadAutomationPopoverView: View {
    var automation: CodexAutomationSummary
    var threadTitle: String
    var threadID: String
    var onSave: (CodexAutomationEdit) async throws -> CodexAutomationSummary
    var onClose: () -> Void

    @State private var draftName = ""
    @State private var draftPrompt = ""
    @State private var draftStatus = "ACTIVE"
    @State private var draftRRule = ""
    @State private var draftScheduleFrequency: AutomationScheduleFrequency = .custom
    @State private var draftScheduleTime = Date()
    @State private var draftWeeklyDays = ""
    @State private var displayedAutomation: CodexAutomationSummary?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var currentAutomation: CodexAutomationSummary {
        displayedAutomation ?? automation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    editorSection
                    detailsSection
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }

            Divider()

            footer
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 14)
        .onAppear(perform: resetDraft)
        .onChange(of: automation) { _, _ in
            displayedAutomation = automation
            resetDraft()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: currentAutomation.isActive ? "alarm.fill" : "alarm")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(currentAutomation.isActive ? .orange : .secondary)
                .frame(width: 24, height: 24)
                .background((currentAutomation.isActive ? Color.orange : Color.secondary).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 7) {
                Text("Automations")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text(currentAutomation.name)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close automation details")
            .accessibilityLabel("Close automation details")
            .minimumAccessibleHitTarget()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Automation name", text: $draftName)
                .font(.title3.weight(.semibold))
                .textFieldStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                TextEditor(text: $draftPrompt)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 112, maxHeight: 132)
                    .padding(9)
                    .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    }
                    .accessibilityLabel("Automation prompt")
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Details")

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 18) {
                GridRow(alignment: .top) {
                    detailField("Status") {
                        statusPicker
                    }

                    detailField("Runs in") {
                        detailValue(currentAutomation.runsInDisplayName)
                    }

                    detailField("Next run") {
                        detailValue(nextRunText, secondary: true)
                    }

                    detailField("Last run") {
                        detailValue(lastRunText, secondary: true)
                    }
                }

                GridRow(alignment: .top) {
                    detailField("Chat") {
                        VStack(alignment: .leading, spacing: 1) {
                            detailValue(threadTitle)
                            Text(shortThreadID)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    scheduleEditor
                        .gridCellColumns(2)

                    detailField("Interval") {
                        detailValue(scheduleDisplayName)
                    }
                }
            }
            .padding(12)
            .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
        }
        .font(.subheadline)
    }

    private var scheduleEditor: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Schedule")

            HStack(spacing: 8) {
                Picker("Schedule frequency", selection: scheduleFrequencyBinding) {
                    ForEach(AutomationScheduleFrequency.allCases) { frequency in
                        Text(frequency.rawValue).tag(frequency)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 112, alignment: .leading)

                if draftScheduleFrequency == .custom {
                    TextField("RRULE", text: $draftRRule)
                        .font(.caption.monospaced())
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Automation RRULE")
                } else {
                    DatePicker(
                        "Schedule time",
                        selection: scheduleTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .controlSize(.small)
                    .frame(width: 116, alignment: .leading)

                    Spacer(minLength: 0)

                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statusPicker: some View {
        Picker("Status", selection: $draftStatus) {
            Text("Active").tag("ACTIVE")
            Text("Paused").tag("PAUSED")
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
    }

    private func detailField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
    }

    private func detailValue(_ value: String, secondary: Bool = false) -> some View {
        Text(value)
            .font(.callout.weight(.semibold))
            .foregroundStyle(secondary ? .secondary : .primary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Reset") {
                resetDraft()
            }
            .disabled(!hasChanges || isSaving)

            Spacer()

            Button("Cancel") {
                onClose()
            }
            .keyboardShortcut(.cancelAction)

            Button {
                save()
            } label: {
                if isSaving {
                    Label("Saving", systemImage: "arrow.triangle.2.circlepath")
                } else {
                    Label("Save", systemImage: "checkmark")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var hasChanges: Bool {
        draftName != currentAutomation.name ||
            draftPrompt != currentAutomation.prompt ||
            draftStatus != currentAutomation.status.uppercased() ||
            draftRRule != currentAutomation.rrule
    }

    private var canSave: Bool {
        !isSaving &&
            hasChanges &&
            !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !draftRRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var nextRunText: String {
        var automation = currentAutomation
        automation.status = draftStatus
        automation.rrule = draftRRule
        guard let date = automation.nextRun() else {
            return "-"
        }
        return Self.dateFormatter.string(from: date)
    }

    private var scheduleDisplayName: String {
        switch draftScheduleFrequency {
        case .daily:
            return "Daily at \(Self.timeFormatter.string(from: draftScheduleTime))"
        case .weekly:
            return "Weekly at \(Self.timeFormatter.string(from: draftScheduleTime))"
        case .custom:
            return CodexAutomationSchedule(rrule: draftRRule).displayName
        }
    }

    private var scheduleFrequencyBinding: Binding<AutomationScheduleFrequency> {
        Binding(
            get: { draftScheduleFrequency },
            set: { frequency in
                draftScheduleFrequency = frequency
                applyScheduleControls()
            }
        )
    }

    private var scheduleTimeBinding: Binding<Date> {
        Binding(
            get: { draftScheduleTime },
            set: { date in
                draftScheduleTime = date
                applyScheduleControls()
            }
        )
    }

    private var lastRunText: String {
        guard let date = currentAutomation.lastRunAt else {
            return "-"
        }
        return Self.dateFormatter.string(from: date)
    }

    private var shortThreadID: String {
        guard threadID.count > 14 else { return threadID }
        return "\(threadID.prefix(8))...\(threadID.suffix(4))"
    }

    private func resetDraft() {
        let source = currentAutomation
        let schedule = AutomationScheduleDraft(rrule: source.rrule)
        draftName = source.name
        draftPrompt = source.prompt
        draftStatus = source.status.uppercased()
        draftRRule = source.rrule
        draftScheduleFrequency = schedule.frequency
        draftScheduleTime = Self.timeDate(hour: schedule.hour, minute: schedule.minute)
        draftWeeklyDays = schedule.weeklyDays
        errorMessage = nil
    }

    private func applyScheduleControls() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: draftScheduleTime)
        let hour = min(max(components.hour ?? 9, 0), 23)
        let minute = min(max(components.minute ?? 0, 0), 59)
        switch draftScheduleFrequency {
        case .daily:
            draftRRule = "RRULE:FREQ=DAILY;BYHOUR=\(hour);BYMINUTE=\(minute)"
        case .weekly:
            let weeklyDays = draftWeeklyDays.trimmingCharacters(in: .whitespacesAndNewlines)
            let byDay = weeklyDays.isEmpty ? Self.weekdayCode(for: Date()) : weeklyDays
            draftRRule = "RRULE:FREQ=WEEKLY;BYHOUR=\(hour);BYMINUTE=\(minute);BYDAY=\(byDay)"
        case .custom:
            break
        }
    }

    private func save() {
        guard canSave else { return }
        let edit = CodexAutomationEdit(
            id: currentAutomation.id,
            name: draftName.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: draftPrompt,
            status: draftStatus,
            rrule: draftRRule.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let saved = try await onSave(edit)
                await MainActor.run {
                    displayedAutomation = saved
                    isSaving = false
                    resetDraft()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static func timeDate(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)
        components.second = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private static func weekdayCode(for date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1:
            return "SU"
        case 2:
            return "MO"
        case 3:
            return "TU"
        case 4:
            return "WE"
        case 5:
            return "TH"
        case 6:
            return "FR"
        case 7:
            return "SA"
        default:
            return "MO"
        }
    }
}

private enum AutomationScheduleFrequency: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    case custom = "Custom"

    var id: String { rawValue }
}

private struct AutomationScheduleDraft {
    var frequency: AutomationScheduleFrequency
    var hour: Int
    var minute: Int
    var weeklyDays: String

    init(rrule: String) {
        let parts = Self.components(from: rrule)
        hour = Self.clamped(parts["BYHOUR"], lowerBound: 0, upperBound: 23, fallback: 9)
        minute = Self.clamped(parts["BYMINUTE"], lowerBound: 0, upperBound: 59, fallback: 0)
        weeklyDays = parts["BYDAY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch parts["FREQ"]?.uppercased() {
        case "DAILY":
            frequency = .daily
        case "WEEKLY":
            frequency = .weekly
        default:
            frequency = .custom
        }
    }

    private static func components(from rrule: String) -> [String: String] {
        let normalizedRule = rrule.hasPrefix("RRULE:")
            ? String(rrule.dropFirst("RRULE:".count))
            : rrule
        return normalizedRule
            .split(separator: ";")
            .reduce(into: [String: String]()) { result, part in
                let pieces = part.split(separator: "=", maxSplits: 1)
                guard pieces.count == 2 else { return }
                result[String(pieces[0]).uppercased()] = String(pieces[1])
            }
    }

    private static func clamped(
        _ value: String?,
        lowerBound: Int,
        upperBound: Int,
        fallback: Int
    ) -> Int {
        let parsed = Int(value ?? "") ?? fallback
        return min(max(parsed, lowerBound), upperBound)
    }
}
