import Foundation
import SwiftData

/// Version 1 of the package's own SwiftData schema: a single envelope table.
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

typealias StoredRecord = StorageSchemaV1.StoredRecord

/// The migration plan the container is always opened with, so adding a V2 later is a stage,
/// not a breaking change.
enum StorageMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [StorageSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
