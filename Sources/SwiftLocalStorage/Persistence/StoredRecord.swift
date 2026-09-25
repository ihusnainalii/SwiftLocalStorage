import Foundation
import SwiftData

/// Version 1 of the package's own SwiftData schema: a single envelope table. Frozen — kept only
/// so existing stores can migrate.
///
/// Consumer DTOs never become `@Model`s — they are encoded into ``StoredRecord/payload``.
/// Any change to this table ships as a new `VersionedSchema` plus a stage in
/// ``StorageMigrationPlan``, never as an edit to this type.
enum StorageSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredRecord.self] }

    @Model
    final class StoredRecord {
        /// `e|<typeName>|<id>` for entities, `kv|<key>` for key-value entries.
        @Attribute(.unique) var key: String
        /// ``RecordKind`` raw value.
        var kind: String
        var typeName: String
        var payload: Data
        var schemaVersion: Int
        var createdAt: Date
        var updatedAt: Date
        /// `nil` means the record never expires.
        var expiresAt: Date?

        init(
            key: String, kind: String, typeName: String, payload: Data,
            schemaVersion: Int, createdAt: Date, updatedAt: Date, expiresAt: Date?
        ) {
            self.key = key
            self.kind = kind
            self.typeName = typeName
            self.payload = payload
            self.schemaVersion = schemaVersion
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.expiresAt = expiresAt
        }
    }
}

/// Version 2 adds ``StoredRecord/sequence``: a per-store insertion counter that breaks
/// `createdAt` ties, so records saved in one batch keep their insertion order.
enum StorageSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredRecord.self] }

    @Model
    final class StoredRecord {
        /// `e|<typeName>|<id>` for entities, `kv|<key>` for key-value entries.
        @Attribute(.unique) var key: String
        /// ``RecordKind`` raw value.
        var kind: String
        var typeName: String
        var payload: Data
        var schemaVersion: Int
        var createdAt: Date
        var updatedAt: Date
        /// `nil` means the record never expires.
        var expiresAt: Date?
        /// Insertion order within the store; assigned once, kept on update. Rows migrated from V1
        /// get `0` and fall back to `createdAt` order.
        var sequence: Int = 0

        init(
            key: String, kind: String, typeName: String, payload: Data,
            schemaVersion: Int, createdAt: Date, updatedAt: Date, expiresAt: Date?, sequence: Int
        ) {
            self.key = key
            self.kind = kind
            self.typeName = typeName
            self.payload = payload
            self.schemaVersion = schemaVersion
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.expiresAt = expiresAt
            self.sequence = sequence
        }
    }
}

/// The current schema's record type.
typealias StoredRecord = StorageSchemaV2.StoredRecord

/// The migration plan every container is opened with.
enum StorageMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [StorageSchemaV1.self, StorageSchemaV2.self] }
    static var stages: [MigrationStage] { [v1ToV2] }

    /// Adds `sequence` with its default value; no data transformation needed.
    static let v1ToV2 = MigrationStage.lightweight(fromVersion: StorageSchemaV1.self, toVersion: StorageSchemaV2.self)
}
