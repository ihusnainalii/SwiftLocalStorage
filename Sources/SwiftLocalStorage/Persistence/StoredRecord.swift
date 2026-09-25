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

/// Version 2 (frozen — kept so existing stores can migrate) adds `sequence`: a per-store insertion counter that breaks
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

/// Version 3 adds three string and three number index slots plus the signature of the index
/// declaration they were computed with (see ``LocalStorageIndexed``). All nullable.
enum StorageSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredRecord.self] }

    @Model
    final class StoredRecord {
        /// `e|<typeName>|<id>` for entities, `kv|<key>` for key-value entries.
        @Attribute(.unique) var key: String
        /// ``RecordKind`` raw value.
        var kind: String
        var typeName: String
        var payload: Data
        /// The DTO version of `payload` (see ``LocalStorageVersioned``).
        var schemaVersion: Int
        var createdAt: Date
        var updatedAt: Date
        /// `nil` means the record never expires.
        var expiresAt: Date?
        /// Insertion order within the store; assigned once, kept on update.
        var sequence: Int = 0
        // Index slots: slot N of a type's declaration uses sN (string) or nN (number).
        var s0: String?
        var s1: String?
        var s2: String?
        var n0: Double?
        var n1: Double?
        var n2: Double?
        /// `name:kind|…` of the declaration the slots were filled with; `nil` = not indexed.
        var indexSignature: String?

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

        /// Stores `values` in the slots, or clears them for a non-indexed record.
        func apply(_ values: IndexValues?) {
            s0 = values?.strings[0]
            s1 = values?.strings[1]
            s2 = values?.strings[2]
            n0 = values?.numbers[0]
            n1 = values?.numbers[1]
            n2 = values?.numbers[2]
            indexSignature = values?.signature
        }
    }
}

/// The schema new containers are opened with. Bump this (and add a migration stage) together
/// with every new `VersionedSchema`; `StoredRecord` and the container both follow it.
typealias CurrentStorageSchema = StorageSchemaV3

/// The current schema's record type.
typealias StoredRecord = CurrentStorageSchema.StoredRecord

/// The migration plan every container is opened with.
enum StorageMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [StorageSchemaV1.self, StorageSchemaV2.self, StorageSchemaV3.self] }
    static var stages: [MigrationStage] { [v1ToV2, v2ToV3] }

    /// Adds the nullable index columns; existing records are re-indexed lazily on first query.
    static let v2ToV3 = MigrationStage.lightweight(fromVersion: StorageSchemaV2.self, toVersion: StorageSchemaV3.self)

    /// Adds `sequence` with its default value; no data transformation needed.
    static let v1ToV2 = MigrationStage.lightweight(fromVersion: StorageSchemaV1.self, toVersion: StorageSchemaV2.self)
}
