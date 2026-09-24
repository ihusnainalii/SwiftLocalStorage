import Foundation

/// Bookkeeping for one stored record — for debugging and cache strategies.
public struct StorageMetadata: Sendable, Hashable {
    public let createdAt: Date
    public let updatedAt: Date
    /// `nil` means the record never expires.
    public let expiresAt: Date?
    /// Encoded payload size in bytes.
    public let size: Int
    /// Whether the record had expired when this metadata was read.
    public let isExpired: Bool

    public init(createdAt: Date, updatedAt: Date, expiresAt: Date?, size: Int, isExpired: Bool) {
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.size = size
        self.isExpired = isExpired
    }
}
