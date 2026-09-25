# SwiftLocalStorage v0.5 — DTO Migrations Design Spec

**Status:** Approved (roadmap 0.5) · **Date:** 2026-09-25 · **Target:** `v0.5.0` · **Branch:** `feat/dto-migrations`

Builds on the earlier specs ([v0.2](2026-09-25-swiftlocalstorage-v0.2-design.md),
[v0.3](2026-09-25-swiftlocalstorage-v0.3-queries-design.md),
[v0.4](2026-09-25-swiftlocalstorage-v0.4-observation-design.md)).

## 1. Goal

A DTO can change incompatibly (a new required field, a renamed or retyped property) without
stranding data already on users' devices. Today such records throw `decodingFailed`; after 0.5 the
app declares the DTO's version and registers migration steps that upgrade old payloads.

## 2. Public API

```swift
// 1. Declare the DTO's current version (types that don't conform are version 1).
struct User: Codable, Identifiable, Sendable, LocalStorageNaming, LocalStorageVersioned {
    static var storageTypeName: String { "User" }
    static var storageVersion: Int { 3 }
    let id: UUID
    var fullName: String
    var role: Role
}

// 2. Register one step per version bump, typed…
let storage = try LocalStorage(configuration: .init(migrations: [
    StorageMigration(User.self, from: 1) { (old: UserV1) in
        UserV2(id: old.id, fullName: old.name)                    // v1 → v2
    },
    // …or on the raw payload, when the old type no longer exists in code:
    StorageMigration(User.self, from: 2) { json in                   // v2 → v3
        var object = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        object["role"] = "member"
        return try JSONSerialization.data(withJSONObject: object)
    },
]))

// 3. Reads migrate transparently and write the upgraded payload back once.
let user = try await storage.fetch(User.self, id: id)

// 4. Or upgrade every stored record of a type eagerly (e.g. at launch); returns how many changed.
let upgraded = try await storage.migrateAll(User.self)

try await storage.metadata(User.self, id: id)?.version            // 3
```

### Types

```swift
public protocol LocalStorageVersioned {
    static var storageVersion: Int { get }   // >= 1
}

public struct StorageMigration: Sendable {
    public let typeName: String              // the stored type's storage name
    public let fromVersion: Int              // migrates fromVersion → fromVersion + 1
    public init<Stored, Old: Decodable, New: Encodable>(
        _ stored: Stored.Type, from version: Int,
        transform: @escaping @Sendable (Old) throws -> New)            // uses the configured encoder/decoder
    public init<Stored>(_ stored: Stored.Type, from version: Int,
        transformPayload: @escaping @Sendable (Data) throws -> Data)   // raw bytes
}

LocalStorageConfiguration.migrations: [StorageMigration]   // default []
StorageMetadata.version: Int                               // the stored payload's version
LocalStorageError.migrationFailed(key: String, underlying: any Error & Sendable)   // + Code.migrationFailed
```

## 3. Semantics

| Situation | Behaviour |
|---|---|
| `save` | stores the payload with `T.storageVersion` (1 when not `LocalStorageVersioned`) |
| Read of a record at the current version | decoded as before, no migration |
| Read of an older record | steps `v → v+1 → … → current` run in memory; the result is decoded, then written back (payload + version) **without touching `createdAt` / `updatedAt` / `expiresAt` or emitting change events** |
| Missing step in the chain | `migrationFailed(key, MigrationError.missingStep(from:))`; record untouched |
| Stored version newer than the type's (app downgrade) | `migrationFailed(key, MigrationError.storedVersionNewer(stored:current:))`; record untouched |
| A step throws | `migrationFailed(key, <thrown error>)`; record untouched |
| Migrated payload doesn't decode as `T` | `decodingFailed(key, …)`; record untouched |
| `migrateAll(T.self)` | upgrades every live outdated record of `T`; returns the count; stops at the first failure |
| Duplicate registration of the same `(typeName, fromVersion)` | precondition failure at `LocalStorage` init |
| Key-value entries | same rules; the value type's storage name keys the migrations |

Records written before 0.5 are version 1, which is what every type was until now.

**Breaking change (pre-1.0 minor):** `LocalStorageError` gains `migrationFailed`, so exhaustive
`switch` statements over it (or over `Code`) need a new case.

## 4. Architecture

- `RecordWrite.schemaVersion` is written on insert **and** update (previously always 1).
- New engine call `rewrite(key:payload:schemaVersion:)` replaces only payload + version.
- `LocalStorage` builds a `[typeName: [fromVersion: StorageMigration]]` table at init; all decoding
  goes through one async `decode` that migrates when needed.

## 5. Out of scope

Downgrade migrations, cross-type migrations (renaming a type — use `LocalStorageNaming`),
background/batched migration scheduling.

## 6. Testing

Both engines: version stored on save/update; typed and raw steps; multi-step chains; write-back
preserves timestamps and emits no events; runs once; missing step / newer stored version / throwing
step / undecodable result; key-value migration; `migrateAll` count and idempotency; metadata version.

## 7. Release

`v0.5.0`. Demo: `Note` gains a required `priority` (version 2) with a 1 → 2 migration, so notes saved
by earlier demo builds upgrade on first read.
