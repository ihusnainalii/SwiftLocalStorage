import Foundation

/// Declares the current version of a stored type's encoded shape. Bump it whenever the DTO changes
/// incompatibly, and register a ``StorageMigration`` from the previous version.
///
/// Types that don't conform are version 1 — which is what every record written before 0.5 is.
///
/// ```swift
/// extension User: LocalStorageVersioned {
///     static var storageVersion: Int { 2 }
/// }
/// ```
public protocol LocalStorageVersioned {
    static var storageVersion: Int { get }
}

/// One upgrade step for a stored type's payloads: version `fromVersion` → `fromVersion + 1`.
///
/// Register every step in ``LocalStorageConfiguration/migrations``. Reads of older records run the
/// steps in order, decode the result and write the upgraded payload back once.
public struct StorageMigration: Sendable {
    /// The storage name of the type being migrated.
    public let typeName: String
    /// The version this step upgrades from; it produces `fromVersion + 1`.
    public let fromVersion: Int

    let transform: @Sendable (Data, any StorageDecoder, any StorageEncoder) throws -> Data

    /// A typed step: decode the old payload as `Old`, return the new shape as `New`.
    ///
    /// ```swift
    /// StorageMigration(User.self, from: 1) { (old: UserV1) in
    ///     UserV2(id: old.id, fullName: old.name)
    /// }
    /// ```
    ///
    /// Uses the storage's configured encoder and decoder.
    public init<Stored, Old: Decodable & Sendable, New: Encodable & Sendable>(
        _ stored: Stored.Type, from version: Int,
        transform: @escaping @Sendable (Old) throws -> New
    ) {
        self.init(typeName: StorageKey.typeName(of: stored), fromVersion: version) { data, decoder, encoder in
            try encoder.encode(try transform(try decoder.decode(Old.self, from: data)))
        }
    }

    /// A raw step over the encoded bytes — for when the old type no longer exists in code.
    public init<Stored>(
        _ stored: Stored.Type, from version: Int,
        transformPayload: @escaping @Sendable (Data) throws -> Data
    ) {
        self.init(typeName: StorageKey.typeName(of: stored), fromVersion: version) { data, _, _ in
            try transformPayload(data)
        }
    }

    init(
        typeName: String, fromVersion: Int,
        transform: @escaping @Sendable (Data, any StorageDecoder, any StorageEncoder) throws -> Data
    ) {
        precondition(fromVersion >= 1, "StorageMigration versions start at 1")
        self.typeName = typeName
        self.fromVersion = fromVersion
        self.transform = transform
    }
}

/// Why a stored record could not be migrated; the `underlying` error of
/// ``LocalStorageError/migrationFailed(key:underlying:)`` when no step threw.
public enum StorageMigrationError: Error, Sendable, Equatable {
    /// No step is registered from `version` for `typeName`.
    case missingStep(typeName: String, from: Int)
    /// The record was written by a newer version of the app than the type now declares.
    case storedVersionNewer(stored: Int, current: Int)
}

extension StorageKey {
    static func version<T>(of type: T.Type) -> Int {
        (type as? any LocalStorageVersioned.Type)?.storageVersion ?? 1
    }
}
