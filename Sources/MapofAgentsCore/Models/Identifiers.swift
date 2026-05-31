import Foundation

public struct WorkspaceID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    public var rawValue: String
    public var id: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func fresh() -> WorkspaceID {
        WorkspaceID(rawValue: UUID().uuidString)
    }
}

public struct NodeID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    public var rawValue: String
    public var id: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func fresh() -> NodeID {
        NodeID(rawValue: UUID().uuidString)
    }
}

public struct EdgeID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    public var rawValue: String
    public var id: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func fresh() -> EdgeID {
        EdgeID(rawValue: UUID().uuidString)
    }
}

public struct HostID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    public var rawValue: String
    public var id: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func fresh() -> HostID {
        HostID(rawValue: UUID().uuidString)
    }
}

public struct RunID: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    public var rawValue: String
    public var id: String { rawValue }

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func fresh() -> RunID {
        RunID(rawValue: UUID().uuidString)
    }
}
