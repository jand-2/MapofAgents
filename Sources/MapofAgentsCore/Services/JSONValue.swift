import Foundation

public enum JSONValue: Codable, Hashable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let object):
            try container.encode(object)
        case .array(let array):
            try container.encode(array)
        case .string(let string):
            try container.encode(string)
        case .number(let number):
            try container.encode(number)
        case .bool(let bool):
            try container.encode(bool)
        case .null:
            try container.encodeNil()
        }
    }

    public subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        guard let doubleValue else { return nil }
        guard doubleValue.isFinite,
              doubleValue.rounded(.towardZero) == doubleValue,
              doubleValue >= Double(Int.min),
              doubleValue <= Double(Int.max)
        else {
            return nil
        }
        return Int(doubleValue)
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

public extension JSONValue {
    static func objectFrom(_ pairs: (String, JSONValue?)...) -> JSONValue {
        var object: [String: JSONValue] = [:]
        for (key, value) in pairs {
            if let value {
                object[key] = value
            }
        }
        return .object(object)
    }

    static func stringOrNull(_ value: String?) -> JSONValue {
        value.map(JSONValue.string) ?? .null
    }
}

public enum JSONRPCRequestID: Codable, Hashable, Sendable, CustomStringConvertible {
    case string(String)
    case int(Int)

    public init?(_ value: JSONValue?) {
        guard let value else { return nil }
        if let string = value.stringValue {
            self = .string(string)
            return
        }
        if let int = value.intValue {
            self = .int(int)
            return
        }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let string):
            try container.encode(string)
        case .int(let int):
            try container.encode(int)
        }
    }

    public var jsonValue: JSONValue {
        switch self {
        case .string(let string):
            return .string(string)
        case .int(let int):
            return .number(Double(int))
        }
    }

    public var stringValue: String {
        switch self {
        case .string(let string):
            return string
        case .int(let int):
            return String(int)
        }
    }

    public var description: String {
        stringValue
    }
}
