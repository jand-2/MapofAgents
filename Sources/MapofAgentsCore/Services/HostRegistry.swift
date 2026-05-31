import Foundation

public struct HostRegistryRecord: Codable, Hashable, Sendable {
    public var id: HostID
    public var displayName: String
    public var aliases: Set<String>
    public var updatedAt: Date

    public init(
        id: HostID,
        displayName: String,
        aliases: Set<String> = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.aliases = aliases
        self.updatedAt = updatedAt
    }
}

public actor HostRegistry {
    public static let shared = HostRegistry()

    private let url: URL?
    private var recordsByID: [HostID: HostRegistryRecord] = [:]
    private var aliases: [String: HostID] = [:]
    private var didLoad = false

    public init(url: URL? = nil, persistsToDefaultLocation: Bool = true) {
        if let url {
            self.url = url
        } else if persistsToDefaultLocation {
            self.url = try? ApplicationPaths.defaultPaths().hostRegistryURL
        } else {
            self.url = nil
        }
    }

    public static func inMemory() -> HostRegistry {
        HostRegistry(persistsToDefaultLocation: false)
    }

    public func hostID(explicitID: HostID?, name: String, endpointURL: URL) async -> HostID {
        await loadIfNeeded()
        let endpointAliases = Self.aliases(for: endpointURL)

        if let explicitID {
            await record(id: explicitID, name: name, aliases: endpointAliases)
            return explicitID
        }

        for alias in endpointAliases {
            if let existing = aliases[alias] {
                await record(id: existing, name: name, aliases: endpointAliases)
                return existing
            }
        }

        let id = HostID(rawValue: Self.generatedHostID(name: name, endpointURL: endpointURL))
        await record(id: id, name: name, aliases: endpointAliases)
        return id
    }

    public func record(id: HostID, name: String, endpointURL: URL) async {
        await loadIfNeeded()
        await record(id: id, name: name, aliases: Self.aliases(for: endpointURL))
    }

    private func record(id: HostID, name: String, aliases newAliases: Set<String>) async {
        var record = recordsByID[id] ?? HostRegistryRecord(
            id: id,
            displayName: name.nilIfBlank ?? id.rawValue
        )
        if let name = name.nilIfBlank {
            record.displayName = name
        }
        record.aliases.formUnion(newAliases)
        record.updatedAt = Date()
        recordsByID[id] = record
        for alias in newAliases {
            if let existingID = aliases[alias], existingID != id {
                recordsByID[existingID]?.aliases.remove(alias)
            }
        }
        for alias in record.aliases {
            aliases[alias] = id
        }
        await save()
    }

    private func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        guard let url, FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let records = try? decoder.decode([HostRegistryRecord].self, from: data) else {
            return
        }
        recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        aliases = records.reduce(into: [:]) { partial, record in
            for alias in record.aliases {
                partial[alias] = record.id
            }
        }
    }

    private func save() async {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let records = recordsByID.values.sorted { $0.id.rawValue < $1.id.rawValue }
            let data = try encoder.encode(records)
            try data.write(to: url, options: [.atomic])
        } catch {
            // The registry is a best-effort alias cache; connection should not fail if persistence does.
        }
    }

    private static func aliases(for url: URL) -> Set<String> {
        var result = Set<String>()
        result.insert("url:\(normalizedEndpoint(url))")
        return result
    }

    private static func generatedHostID(name: String, endpointURL: URL) -> String {
        let endpointPart = normalizedEndpoint(endpointURL)
        let base = [name.nilIfBlank, endpointPart]
            .compactMap { $0 }
            .joined(separator: "-")
        let safe = safeIdentifier(base)
        let prefix = safe.prefix(54)
        return "relay-\(prefix)-\(fnv1a64(endpointPart))"
    }

    private static func normalizedEndpoint(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }
        if let scheme = components.scheme {
            components.scheme = scheme.lowercased()
        }
        if let host = components.host {
            components.host = host.lowercased()
        }
        return components.url?.absoluteString.lowercased() ?? url.absoluteString.lowercased()
    }

    private static func safeIdentifier(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let compact = value.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let result = String(compact)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? "machine" : result
    }

    private static func fnv1a64(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
