/// The single error type crossing SwiftLocalStorage's public boundary.
///
/// SwiftData, `EncodingError` and `DecodingError` failures are all mapped into one of these cases
/// before they reach a caller. A missing or expired record is not an error — reads return `nil`.
public enum LocalStorageError: Error, Sendable {
    /// The value could not be encoded; nothing was written.
    case encodingFailed(underlying: any Error & Sendable)
    /// The stored bytes for `key` could not be decoded into the requested type — usually an
    /// incompatible DTO change or a corrupt record.
    case decodingFailed(key: String, underlying: any Error & Sendable)
    /// The stored record for `key` could not be upgraded to the type's current version: a step is
    /// missing, a step threw, or the record is newer than the app (see ``StorageMigrationError``).
    case migrationFailed(key: String, underlying: any Error & Sendable)
    /// The underlying store failed to read or write.
    case persistenceFailed(underlying: any Error & Sendable)
    /// The store could not be opened.
    case containerInitializationFailed(underlying: any Error & Sendable)
    /// The calling task was cancelled before the operation started; nothing was written.
    case cancelled
}

extension LocalStorageError {
    /// A stable, `Equatable` discriminant, handy for `switch`ing and for tests.
    public enum Code: String, Sendable, Hashable, CaseIterable {
        case encodingFailed, decodingFailed, migrationFailed, persistenceFailed, containerInitializationFailed
        case cancelled
    }

    public var code: Code {
        switch self {
        case .encodingFailed: .encodingFailed
        case .decodingFailed: .decodingFailed
        case .migrationFailed: .migrationFailed
        case .persistenceFailed: .persistenceFailed
        case .containerInitializationFailed: .containerInitializationFailed
        case .cancelled: .cancelled
        }
    }
}
