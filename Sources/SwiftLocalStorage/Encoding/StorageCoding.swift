import Foundation

/// Turns a value into the bytes stored in a record. Default: ``JSONStorageEncoder``.
public protocol StorageEncoder: Sendable {
    func encode<T: Encodable>(_ value: T) throws -> Data
}

/// Turns stored bytes back into a value. Default: ``JSONStorageDecoder``.
public protocol StorageDecoder: Sendable {
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
}

/// JSON encoding with Foundation's default strategies (dates as seconds since reference date,
/// which round-trips exactly).
public struct JSONStorageEncoder: StorageEncoder {
    public init() {}

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        // A fresh encoder per call: JSONEncoder is a non-Sendable class.
        try JSONEncoder().encode(value)
    }
}

/// JSON decoding matching ``JSONStorageEncoder``.
public struct JSONStorageDecoder: StorageDecoder {
    public init() {}

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
