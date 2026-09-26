import Foundation

// Codable envelope for the existing JSON signaling protocol, including RTP/ICE payloads.
enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let item = try? value.decode(Bool.self) {
            self = .bool(item)
        } else if let item = try? value.decode(String.self) {
            self = .string(item)
        } else if let item = try? value.decode(Double.self) {
            self = .number(item)
        } else if let item = try? value.decode([String: JSONValue].self) {
            self = .object(item)
        } else {
            self = .array(try value.decode([JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let item): try value.encode(item)
        case .array(let item): try value.encode(item)
        case .string(let item): try value.encode(item)
        case .number(let item): try value.encode(item)
        case .bool(let item): try value.encode(item)
        case .null: try value.encodeNil()
        }
    }

    subscript(_ key: String) -> JSONValue {
        if case .object(let values) = self { return values[key] ?? .null }
        return .null
    }
    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }
    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
    func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }
    func json() throws -> String { String(decoding: try JSONEncoder().encode(self), as: UTF8.self) }
    static func parse(_ json: String) throws -> JSONValue { try JSONDecoder().decode(Self.self, from: Data(json.utf8)) }
}
