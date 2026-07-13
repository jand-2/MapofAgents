import Foundation

public struct CodexAutomationSummary: Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: String
    public var name: String
    public var prompt: String
    public var status: String
    public var rrule: String
    public var targetThreadID: String?
    public var executionEnvironment: String?
    public var model: String?
    public var reasoningEffort: String?
    public var createdAt: Date?
    public var updatedAt: Date?
    public var lastRunAt: Date?
    public var configurationPath: String

    public init(
        id: String,
        kind: String,
        name: String,
        prompt: String,
        status: String,
        rrule: String,
        targetThreadID: String? = nil,
        executionEnvironment: String? = nil,
        model: String? = nil,
        reasoningEffort: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        lastRunAt: Date? = nil,
        configurationPath: String
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.prompt = prompt
        self.status = status
        self.rrule = rrule
        self.targetThreadID = targetThreadID
        self.executionEnvironment = executionEnvironment
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastRunAt = lastRunAt
        self.configurationPath = configurationPath
    }

    public var isActive: Bool {
        status.uppercased() == "ACTIVE"
    }

    public var isHeartbeat: Bool {
        kind.lowercased() == "heartbeat"
    }

    public var runsInDisplayName: String {
        if isHeartbeat {
            return "Chat"
        }
        if let executionEnvironment, !executionEnvironment.isEmpty {
            return executionEnvironment.capitalized
        }
        return "Workspace"
    }

    public var intervalDisplayName: String {
        CodexAutomationSchedule(rrule: rrule).displayName
    }

    public func nextRun(after referenceDate: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard isActive else { return nil }
        return CodexAutomationSchedule(rrule: rrule).nextRun(
            after: referenceDate,
            anchor: createdAt ?? updatedAt,
            calendar: calendar
        )
    }
}

public struct CodexAutomationEdit: Hashable, Sendable {
    public var id: String
    public var name: String
    public var prompt: String
    public var status: String
    public var rrule: String

    public init(id: String, name: String, prompt: String, status: String, rrule: String) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.status = status
        self.rrule = rrule
    }
}

public enum CodexAutomationStoreError: Error, LocalizedError, Sendable {
    case automationNotFound(String)
    case invalidAutomation(path: String)
    case invalidAutomationDirectory(String)
    case invalidAutomationID(String)
    case automationOutsideRoot(String)

    public var errorDescription: String? {
        switch self {
        case .automationNotFound(let id):
            return "Could not find Codex automation \(id)."
        case .invalidAutomation:
            return "Codex automation file is missing required fields."
        case .invalidAutomationDirectory:
            return "Codex automation directory is unavailable."
        case .invalidAutomationID(let id):
            return "Codex automation ID \(id.debugDescription) is not a safe directory name."
        case .automationOutsideRoot(let id):
            return "Codex automation \(id.debugDescription) resolves outside the automations directory."
        }
    }
}

public struct CodexAutomationStore: Sendable {
    public var codexHome: URL

    public init(codexHome: URL = Self.defaultCodexHome()) {
        self.codexHome = codexHome
    }

    public static func defaultCodexHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL? = nil
    ) -> URL {
        if let value = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        let resolvedHomeDirectory = homeDirectory
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return resolvedHomeDirectory.appendingPathComponent(".codex", isDirectory: true)
    }

    public func loadAutomations() throws -> [CodexAutomationSummary] {
        let automationsURL = codexHome.appendingPathComponent("automations", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: automationsURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return []
        }

        let directories = try FileManager.default.contentsOfDirectory(
            at: automationsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return try directories.compactMap { directory in
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { return nil }
            let fileURL = directory.appendingPathComponent("automation.toml", isDirectory: false)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            return try Self.loadAutomation(at: fileURL)
        }
        .sorted { lhs, rhs in
            if lhs.name.localizedCaseInsensitiveCompare(rhs.name) != .orderedSame {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    public func loadAutomationsByThreadID() throws -> [String: CodexAutomationSummary] {
        var result: [String: CodexAutomationSummary] = [:]
        for automation in try loadAutomations() {
            guard let threadID = automation.targetThreadID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !threadID.isEmpty else {
                continue
            }
            if let existing = result[threadID] {
                result[threadID] = Self.preferredAutomation(existing, automation)
            } else {
                result[threadID] = automation
            }
        }
        return result
    }

    public func save(_ edit: CodexAutomationEdit) throws -> CodexAutomationSummary {
        try Self.validateAutomationID(edit.id)
        let automationsURL = codexHome.appendingPathComponent("automations", isDirectory: true)
        let fileURL = automationsURL
            .appendingPathComponent(edit.id, isDirectory: true)
            .appendingPathComponent("automation.toml", isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CodexAutomationStoreError.automationNotFound(edit.id)
        }
        guard Self.isContained(fileURL, in: automationsURL) else {
            throw CodexAutomationStoreError.automationOutsideRoot(edit.id)
        }

        let original = try String(contentsOf: fileURL, encoding: .utf8)
        let updated = Self.updatingAutomationTOML(original, with: edit, updatedAt: Date())
        try updated.write(to: fileURL, atomically: true, encoding: .utf8)
        return try Self.loadAutomation(at: fileURL)
    }

    private static func validateAutomationID(_ id: String) throws {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty,
              id == trimmed,
              id != ".",
              id != "..",
              !id.contains("/"),
              !id.contains("\\"),
              !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw CodexAutomationStoreError.invalidAutomationID(id)
        }
    }

    private static func isContained(_ fileURL: URL, in rootURL: URL) -> Bool {
        let resolvedRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedFile = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = resolvedRoot.pathComponents
        let fileComponents = resolvedFile.pathComponents
        return fileComponents.count > rootComponents.count
            && fileComponents.starts(with: rootComponents)
    }

    private static func loadAutomation(at fileURL: URL) throws -> CodexAutomationSummary {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        let fields = CodexAutomationTOML.parse(text)
        guard let id = fields["id"]?.nilIfBlank,
              let name = fields["name"]?.nilIfBlank,
              let rrule = fields["rrule"]?.nilIfBlank else {
            throw CodexAutomationStoreError.invalidAutomation(path: fileURL.path)
        }
        let kind = fields["kind"]?.nilIfBlank ?? "cron"
        let status = fields["status"]?.nilIfBlank ?? "PAUSED"
        return CodexAutomationSummary(
            id: id,
            kind: kind,
            name: name,
            prompt: fields["prompt"] ?? "",
            status: status,
            rrule: rrule,
            targetThreadID: fields["target_thread_id"]?.nilIfBlank,
            executionEnvironment: fields["execution_environment"]?.nilIfBlank,
            model: fields["model"]?.nilIfBlank,
            reasoningEffort: fields["reasoning_effort"]?.nilIfBlank,
            createdAt: parseDate(fields["created_at"]),
            updatedAt: parseDate(fields["updated_at"]),
            lastRunAt: parseDate(fields["last_run_at"]),
            configurationPath: fileURL.path
        )
    }

    private static func preferredAutomation(
        _ lhs: CodexAutomationSummary,
        _ rhs: CodexAutomationSummary
    ) -> CodexAutomationSummary {
        if lhs.isActive != rhs.isActive {
            return rhs.isActive ? rhs : lhs
        }
        let lhsDate = lhs.updatedAt ?? lhs.createdAt ?? .distantPast
        let rhsDate = rhs.updatedAt ?? rhs.createdAt ?? .distantPast
        return rhsDate >= lhsDate ? rhs : lhs
    }

    private static func updatingAutomationTOML(
        _ toml: String,
        with edit: CodexAutomationEdit,
        updatedAt: Date
    ) -> String {
        let replacements: [String: String] = [
            "name": tomlValue(edit.name),
            "prompt": tomlValue(edit.prompt),
            "status": tomlValue(edit.status.uppercased()),
            "rrule": tomlValue(edit.rrule),
            "updated_at": tomlValue(iso8601Formatter(includeFractionalSeconds: true).string(from: updatedAt)),
        ]
        let existingKeys = Set(CodexAutomationTOML.parse(toml).keys)
        var output: [String] = []
        let lines = toml.components(separatedBy: .newlines)
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let parsed = CodexAutomationTOML.lineKeyAndValue(line)
            if let parsed,
               let replacement = replacements[parsed.key] {
                output.append("\(parsed.key) = \(replacement)")
                if parsed.value.trimmingCharacters(in: .whitespaces).hasPrefix("\"\"\""),
                   !parsed.value.dropFirst(3).contains("\"\"\"") {
                    index += 1
                    while index < lines.count {
                        let skipped = lines[index]
                        if skipped.contains("\"\"\"") {
                            break
                        }
                        index += 1
                    }
                }
            } else {
                output.append(line)
            }
            index += 1
        }

        for key in ["name", "prompt", "status", "rrule", "updated_at"] where !existingKeys.contains(key) {
            if let replacement = replacements[key] {
                output.append("\(key) = \(replacement)")
            }
        }

        return output.joined(separator: "\n")
    }

    private static func tomlValue(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\":
                result += "\\\\"
            case "\"":
                result += "\\\""
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        result += "\""
        return result
    }

    private static func iso8601Formatter(includeFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = includeFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value = value?.nilIfBlank else { return nil }
        return iso8601Formatter(includeFractionalSeconds: true).date(from: value)
            ?? iso8601Formatter(includeFractionalSeconds: false).date(from: value)
    }
}

public struct CodexAutomationSchedule: Hashable, Sendable {
    public var rrule: String

    public init(rrule: String) {
        self.rrule = rrule
    }

    public var displayName: String {
        let parts = components
        let interval = max(1, Int(parts["INTERVAL"] ?? "") ?? 1)
        switch parts["FREQ"]?.uppercased() {
        case "MINUTELY":
            return interval == 1 ? "Every minute" : "Every \(interval) minutes"
        case "HOURLY":
            return interval == 1 ? "Hourly" : "Every \(interval) hours"
        case "DAILY":
            return interval == 1 ? "Daily" : "Every \(interval) days"
        case "WEEKLY":
            return interval == 1 ? "Weekly" : "Every \(interval) weeks"
        case "MONTHLY":
            return interval == 1 ? "Monthly" : "Every \(interval) months"
        default:
            return "Custom"
        }
    }

    public func nextRun(
        after referenceDate: Date,
        anchor: Date?,
        calendar: Calendar = .current
    ) -> Date? {
        let parts = components
        let interval = max(1, Int(parts["INTERVAL"] ?? "") ?? 1)
        switch parts["FREQ"]?.uppercased() {
        case "MINUTELY":
            return nextIntervalDate(
                after: referenceDate,
                anchor: anchor,
                component: .minute,
                interval: interval,
                calendar: calendar
            )
        case "HOURLY":
            return nextIntervalDate(
                after: referenceDate,
                anchor: anchor,
                component: .hour,
                interval: interval,
                calendar: calendar
            )
        case "DAILY":
            return nextDailyDate(after: referenceDate, interval: interval, parts: parts, calendar: calendar)
        case "WEEKLY":
            return nextWeeklyDate(after: referenceDate, interval: interval, parts: parts, calendar: calendar)
        default:
            return nil
        }
    }

    private var components: [String: String] {
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

    private func nextIntervalDate(
        after referenceDate: Date,
        anchor: Date?,
        component: Calendar.Component,
        interval: Int,
        calendar: Calendar
    ) -> Date? {
        guard let anchor else {
            return calendar.date(byAdding: component, value: interval, to: referenceDate)
        }
        guard anchor <= referenceDate else {
            return anchor
        }
        let delta = calendar.dateComponents([component], from: anchor, to: referenceDate)
        let elapsed: Int
        switch component {
        case .minute:
            elapsed = delta.minute ?? 0
        case .hour:
            elapsed = delta.hour ?? 0
        default:
            elapsed = 0
        }
        let steps = (elapsed / interval) + 1
        return calendar.date(byAdding: component, value: steps * interval, to: anchor)
    }

    private func nextDailyDate(
        after referenceDate: Date,
        interval: Int,
        parts: [String: String],
        calendar: Calendar
    ) -> Date? {
        let hour = Int(parts["BYHOUR"] ?? "") ?? 9
        let minute = Int(parts["BYMINUTE"] ?? "") ?? 0
        var components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard var candidate = calendar.date(from: components) else { return nil }
        while candidate <= referenceDate {
            guard let next = calendar.date(byAdding: .day, value: interval, to: candidate) else {
                return nil
            }
            candidate = next
        }
        return candidate
    }

    private func nextWeeklyDate(
        after referenceDate: Date,
        interval: Int,
        parts: [String: String],
        calendar: Calendar
    ) -> Date? {
        let days = (parts["BYDAY"] ?? "")
            .split(separator: ",")
            .compactMap { weekdayNumber(for: String($0)) }
        let targetDays = days.isEmpty ? [calendar.component(.weekday, from: referenceDate)] : days
        let hour = Int(parts["BYHOUR"] ?? "") ?? 9
        let minute = Int(parts["BYMINUTE"] ?? "") ?? 0
        var best: Date?
        for dayOffset in 0..<(max(2, interval + 1) * 7) {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: referenceDate) else {
                continue
            }
            guard targetDays.contains(calendar.component(.weekday, from: day)) else {
                continue
            }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard let candidate = calendar.date(from: components), candidate > referenceDate else {
                continue
            }
            if best.map({ candidate < $0 }) ?? true {
                best = candidate
            }
        }
        return best
    }

    private func weekdayNumber(for value: String) -> Int? {
        switch value.uppercased() {
        case "SU":
            return 1
        case "MO":
            return 2
        case "TU":
            return 3
        case "WE":
            return 4
        case "TH":
            return 5
        case "FR":
            return 6
        case "SA":
            return 7
        default:
            return nil
        }
    }
}

enum CodexAutomationTOML {
    static func parse(_ text: String) -> [String: String] {
        let lines = text.components(separatedBy: .newlines)
        var result: [String: String] = [:]
        var index = 0
        while index < lines.count {
            guard let parsed = lineKeyAndValue(lines[index]) else {
                index += 1
                continue
            }
            let trimmedValue = parsed.value.trimmingCharacters(in: .whitespaces)
            if trimmedValue.hasPrefix("\"\"\"") {
                var value = String(trimmedValue.dropFirst(3))
                if let range = value.range(of: "\"\"\"") {
                    result[parsed.key] = String(value[..<range.lowerBound])
                } else {
                    index += 1
                    while index < lines.count {
                        let line = lines[index]
                        if let range = line.range(of: "\"\"\"") {
                            if !value.isEmpty {
                                value += "\n"
                            }
                            value += line[..<range.lowerBound]
                            break
                        }
                        if !value.isEmpty {
                            value += "\n"
                        }
                        value += line
                        index += 1
                    }
                    result[parsed.key] = value
                }
            } else {
                result[parsed.key] = parseValue(trimmedValue)
            }
            index += 1
        }
        return result
    }

    static func lineKeyAndValue(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("#"),
              !trimmed.hasPrefix("["),
              let equals = trimmed.firstIndex(of: "=") else {
            return nil
        }
        let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        let value = trimmed[trimmed.index(after: equals)...]
        return (String(key), String(value))
    }

    private static func parseValue(_ rawValue: String) -> String {
        if rawValue.hasPrefix("\"") {
            return parseBasicString(rawValue)
        }
        if rawValue.hasPrefix("'") {
            let value = rawValue.dropFirst()
            if let end = value.firstIndex(of: "'") {
                return String(value[..<end])
            }
            return String(value)
        }
        return rawValue
            .split(separator: "#", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func parseBasicString(_ rawValue: String) -> String {
        var escaped = false
        var result = ""
        for scalar in rawValue.dropFirst().unicodeScalars {
            if escaped {
                switch scalar {
                case "n":
                    result += "\n"
                case "r":
                    result += "\r"
                case "t":
                    result += "\t"
                case "\"":
                    result += "\""
                case "\\":
                    result += "\\"
                default:
                    result.unicodeScalars.append(scalar)
                }
                escaped = false
                continue
            }

            if scalar == "\\" {
                escaped = true
                continue
            }

            if scalar == "\"" {
                break
            }

            result.unicodeScalars.append(scalar)
        }
        return result
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
