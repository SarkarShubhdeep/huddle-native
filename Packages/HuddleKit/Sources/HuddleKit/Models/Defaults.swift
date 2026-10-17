import Foundation

/// The backend leaves out fields it has no value for (JS `undefined` never reaches
/// the JSON). These wrappers let a synthesized `Decodable` treat a missing or
/// `null` key as an empty collection, `false` or zero instead of failing.

@propertyWrapper
public struct DefaultEmpty<Value: Codable & Sendable & Hashable & RangeReplaceableCollection>: Codable, Sendable, Hashable {
    public var wrappedValue: Value
    public init(wrappedValue: Value = Value()) { self.wrappedValue = wrappedValue }
    public init(from decoder: any Decoder) throws { wrappedValue = try decoder.singleValueContainer().decode(Value.self) }
    public func encode(to encoder: any Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(wrappedValue) }
}

@propertyWrapper
public struct DefaultFalse: Codable, Sendable, Hashable {
    public var wrappedValue: Bool
    public init(wrappedValue: Bool = false) { self.wrappedValue = wrappedValue }
    public init(from decoder: any Decoder) throws { wrappedValue = try decoder.singleValueContainer().decode(Bool.self) }
    public func encode(to encoder: any Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(wrappedValue) }
}

@propertyWrapper
public struct DefaultZero: Codable, Sendable, Hashable {
    public var wrappedValue: Int
    public init(wrappedValue: Int = 0) { self.wrappedValue = wrappedValue }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Some counters arrive as doubles (e.g. 3.0); keep the integer part.
        if let whole = try? container.decode(Int.self) {
            wrappedValue = whole
        } else {
            wrappedValue = Int(try container.decode(Double.self))
        }
    }
    public func encode(to encoder: any Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(wrappedValue) }
}

extension KeyedDecodingContainer {
    public func decode<V>(_ type: DefaultEmpty<V>.Type, forKey key: Key) throws -> DefaultEmpty<V> {
        try decodeIfPresent(type, forKey: key) ?? DefaultEmpty()
    }

    public func decode(_ type: DefaultFalse.Type, forKey key: Key) throws -> DefaultFalse {
        try decodeIfPresent(type, forKey: key) ?? DefaultFalse()
    }

    public func decode(_ type: DefaultZero.Type, forKey key: Key) throws -> DefaultZero {
        try decodeIfPresent(type, forKey: key) ?? DefaultZero()
    }
}

/// Free-form JSON, for payloads like a notification's `data`.
public enum JSONValue: Codable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case let .object(object) = self { return object[key] }
        return nil
    }

    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }
}
