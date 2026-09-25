# SwiftLocalStorage v0.1–v0.2 Design Spec

**Status:** Approved · **Date:** 2026-09-25 · **Targets:** `v0.1.0` (foundation), `v0.2.0` (cache)

## 1. Goal

Persist existing `Codable` DTOs locally with SwiftData, without the consumer writing `@Model`
entities. SwiftData is an implementation detail; the public boundary is `Codable & Sendable`.

Sibling of [SwiftNetworkKit](https://github.com/ihusnainalii/SwiftNetworkKit): same conventions
(Swift 6 language mode, zero dependencies, one public error enum with a `Code` discriminant,
`Logger` sink protocol, test doubles behind `@_spi(...Testing)`, Swift Testing).

## 2. Platforms & toolchain

- `swift-tools-version:6.0`, `.swiftLanguageMode(.v6)` on every target.
- iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1 (SwiftData minimums).
- No external dependencies.

## 3. Public API

```swift
let storage = try LocalStorage()                          // on-disk store named "SwiftLocalStorage"
let storage = try LocalStorage(configuration: .inMemory)  // tests & previews

// Entities — T: Identifiable & Codable & Sendable, T.ID: Sendable
try await storage.save(user)                              // upsert, expiration .never
try await storage.save(user, expiration: .hours(1))
try await storage.save(users, expiration: .never)         // single transaction
let user: User?  = try await storage.fetch(User.self, id: id)
let users: [User] = try await storage.fetch(User.self)
let n: Int       = try await storage.count(User.self)
let ok: Bool     = try await storage.exists(User.self, id: id)
try await storage.delete(User.self, id: id)
try await storage.delete(users)
try await storage.deleteAll(User.self)
let meta: StorageMetadata? = try await storage.metadata(User.self, id: id)

// Key-value — V: Codable & Sendable
try await storage.set(settings, forKey: "settings", expiration: .never)
let s: AppSettings? = try await storage.get(AppSettings.self, forKey: "settings")
try await storage.remove(forKey: "settings")

// Maintenance
let purged: Int = try await storage.removeExpired()
try await storage.removeAll()

// Repository
let repo = storage.repository(User.self)                  // LocalRepository<User>
try await repo.save(user); try await repo.fetch(id: id); try await repo.fetchAll()
```

### Semantics

| Situation | Behaviour |
|---|---|
| Missing ID / key | returns `nil` (not an error) |
| Expired record | treated as absent: `fetch`/`get` → `nil`, `fetchAll`/`count`/`exists` skip it; the row is deleted lazily on read |
| `save` of existing ID | upsert: payload, `updatedAt`, `expiresAt` replaced; `createdAt` preserved |
| `save([T])` | one SwiftData transaction; all-or-nothing |
| `delete` of missing ID | no-op |
| Corrupt payload | throws `LocalStorageError.decodingFailed(key:underlying:)` |
| Task cancelled before an operation | throws `LocalStorageError.cancelled`, nothing written |

`fetch(T.self)` ordering: `createdAt` ascending (insertion order).

## 4. Record key & type name

- Entity key: `e|<typeName>|<String(describing: id)>`
- Key-value key: `kv|<key>`
- `typeName` defaults to `String(reflecting: T.self)` (module-qualified → no cross-module
  collisions). Renaming a type orphans its rows; types can opt into a stable name:

```swift
public protocol LocalStorageNaming { static var storageTypeName: String { get } }
```

## 5. Architecture

```text
LocalStorage (public, Sendable final class)
   │  encode/decode via StorageEncoder / StorageDecoder (JSON default)
   ▼
StorageEngine (internal protocol, record-level: key + bytes + dates)
   ├── SwiftDataEngine (@ModelActor)  ── ModelContainer ── StoredRecord (@Model)
   └── InMemoryStorageEngine (@_spi(SwiftLocalStorageTesting))
```

Encoding happens in `LocalStorage`, outside the actor, so the engine never sees generic types.

### `StoredRecord` (`@Model`, schema V1)

| Column | Type | Notes |
|---|---|---|
| `key` | `String` | `@Attribute(.unique)` |
| `kind` | `String` | `"entity"` / `"kv"` |
| `typeName` | `String` | filtered by `fetchAll`/`count`/`deleteAll` |
| `payload` | `Data` | encoded DTO |
| `schemaVersion` | `Int` | `1` |
| `createdAt` / `updatedAt` | `Date` | |
| `expiresAt` | `Date?` | `nil` = never |

Registered through `StorageSchemaV1: VersionedSchema` and `StorageMigrationPlan` (no stages yet),
so future stored-record changes are migrations, not breaking changes.

> **Amendment (v0.2.3):** schema V2 adds `sequence: Int` (insertion counter, default `0`) so records
> saved in one batch, which share a `createdAt`, keep insertion order. V1 stores upgrade through a
> lightweight `MigrationStage` (V1 → V2).

## 6. Configuration

```swift
public struct LocalStorageConfiguration: Sendable {
    public var name: String                     // default "SwiftLocalStorage"
    public var isStoredInMemoryOnly: Bool       // default false
    public var encoder: any StorageEncoder      // default JSONStorageEncoder()
    public var decoder: any StorageDecoder      // default JSONStorageDecoder()
    public var logger: any StorageLogger        // default NoopStorageLogger()
    public var logLevel: StorageLogLevel        // default .none
    public static var inMemory: Self
}
```

The clock is injected via an `@_spi(SwiftLocalStorageTesting)` initializer only.

## 7. Errors

```swift
public enum LocalStorageError: Error, Sendable {
    case encodingFailed(underlying: any Error & Sendable)
    case decodingFailed(key: String, underlying: any Error & Sendable)
    case persistenceFailed(underlying: any Error & Sendable)
    case containerInitializationFailed(underlying: any Error & Sendable)
    case cancelled
}
```

Plus `LocalStorageError.Code` (`Equatable`, `CaseIterable`) and `var code`. No SwiftData error
crosses the public boundary.

## 8. Cache (v0.2)

- `CacheExpiration`: `.never`, `.seconds(TimeInterval)`, `.minutes(Int)`, `.hours(Int)`,
  `.days(Int)`, `.date(Date)`; `func expiresAt(from now: Date) -> Date?`.
- `StorageMetadata`: `createdAt`, `updatedAt`, `expiresAt`, `size` (payload bytes),
  `isExpired`. `metadata(_:id:)` returns metadata for expired rows too (debugging).
- `removeExpired()` deletes all rows with `expiresAt <= now`, returns the count.

## 9. Logging (v0.2)

- `StorageLogger: Sendable { func log(_ line: String, level: StorageLogLevel) }`
- `StorageLogLevel: Int, Comparable` — `none, error, info, debug`.
- `NoopStorageLogger` (default), `OSLogStorageLogger(subsystem:category:)`.
- Lines contain operation, key and byte count, **never the payload**.

## 10. Out of scope

Field queries / sorting / pagination (v0.3), observation & `AsyncStream` (v0.4), DTO migration
hooks (v0.5), `CachePolicy` / network integration (separate package), Keychain / secrets,
benchmarks target (v1.0), Linux support (SwiftData is Apple-only).

## 11. Testing

Swift Testing, every test on `.inMemory` (or `InMemoryStorageEngine`), `TestClock` for time.
Suites: configuration, entity CRUD, key-value, encoding round-trips (nested, dates, URLs, enums,
optionals, custom Codable), key isolation across types, expiration & metadata, removeExpired,
corrupt payload, DTO evolution V1→V2, 100 concurrent saves/reads/mixed, cancellation,
repository, logging (payload never logged), errors.

## 12. Release plan

| Version | Branch | Contents |
|---|---|---|
| `v0.1.0` | `feat/core-storage` | package, record, engines, entity CRUD, key-value, errors, config, repository |
| `v0.2.0` | `feat/cache-layer` | expiration, metadata, removeExpired, bulk delete, logging |

Conventional Commits; every commit updates `CHANGELOG.md` (Keep a Changelog); tags `vX.Y.Z`
with GitHub releases.
