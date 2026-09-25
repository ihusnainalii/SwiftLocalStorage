<h1 align="center">SwiftLocalStorage</h1>

<p align="center">
  <strong>Type-safe, concurrency-safe local persistence and caching for Swift.</strong><br />
  Persist your existing <code>Codable</code> DTOs with SwiftData — no <code>@Model</code> entities to write.<br />
  Zero dependencies • Swift 6 strict concurrency • Cache expiration • Queries &amp; indexes • Live observation • DTO migrations
</p>

<p align="center">
  <a href="https://github.com/ihusnainalii/SwiftLocalStorage/actions/workflows/ci.yml"><img src="https://github.com/ihusnainalii/SwiftLocalStorage/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
  <a href="https://github.com/ihusnainalii/SwiftLocalStorage/releases"><img src="https://img.shields.io/github/v/release/ihusnainalii/SwiftLocalStorage" alt="Latest release" /></a>
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0-orange.svg" alt="Swift 6" /></a>
  <a href="https://swift.org/package-manager"><img src="https://img.shields.io/badge/SPM-compatible-brightgreen.svg" alt="SPM" /></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/platforms-iOS%2017%20%7C%20macOS%2014%20%7C%20tvOS%2017%20%7C%20watchOS%2010%20%7C%20visionOS%201-lightgrey.svg" alt="Platforms" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License" /></a>
</p>

- **Version:** 0.6.0 (pre-1.0: minor versions may contain breaking changes; see [Versioning](#versioning))
- **Swift:** 6.0 (`swift-tools-version:6.0`, Swift 6 language mode)
- **Platforms:** iOS 17+, macOS 14+, tvOS 17+, watchOS 10+, visionOS 1+
- **Distribution:** Swift Package Manager
- **License:** [Apache 2.0](LICENSE)

---

## Table of contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [API at a glance](#api-at-a-glance)
- [Architecture](#architecture)
- [Core concepts](#core-concepts)
- [Entity storage](#entity-storage)
- [Key-value storage](#key-value-storage)
- [Repositories](#repositories)
- [Queries: sorting, paging, filtering](#queries-sorting-paging-filtering)
- [Indexed fields](#indexed-fields)
- [Observation and SwiftUI](#observation-and-swiftui)
- [Cache expiration](#cache-expiration)
- [Metadata](#metadata)
- [Configuration](#configuration)
- [Custom encoding](#custom-encoding)
- [Stable type names](#stable-type-names)
- [Evolving your DTOs](#evolving-your-dtos)
- [Error handling](#error-handling)
- [Logging](#logging)
- [Testing and mocking](#testing-and-mocking)
- [Thread safety](#thread-safety)
- [Performance](#performance)
- [Using it with SwiftNetworkKit](#using-it-with-swiftnetworkkit)
- [Complete example](#complete-example)
- [Demo app](#demo-app)
- [Best practices](#best-practices)
- [Known limitations](#known-limitations)
- [FAQ](#faq)
- [Communication](#communication)
- [Upgrading](#upgrading)
- [Versioning](#versioning)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [Security policy](#security-policy)
- [License](#license)
- [Author](#author)

---

## Overview

SwiftData is a great persistence engine, but it asks you to model your data as `@Model` classes.
Most apps already have a perfectly good model: the `Codable` structs their API returns. Mirroring
every DTO as a `@Model` entity doubles the model layer and couples it to SwiftData.

SwiftLocalStorage keeps your DTO as the single source of truth:

```swift
struct User: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
}

let storage = try LocalStorage()
try await storage.save(user, expiration: .hours(1))
let cached = try await storage.fetch(User.self, id: user.id)   // User?
```

SwiftData stays an implementation detail. Your app never touches a `ModelContainer`, a
`ModelContext` or a `@Model` type, and the public API does not depend on SwiftData, so the storage
engine can change without breaking you.

It is the persistence counterpart to
[SwiftNetworkKit](https://github.com/ihusnainalii/SwiftNetworkKit): the same conventions, and a
natural fit for caching the DTOs that SwiftNetworkKit decodes.

---

## Features

| Area | What you get |
|---|---|
| **Entity storage** | `save`, batch `save` (single transaction), `fetch` by ID, fetch all, `count`, `exists`, `delete`, bulk `delete`, `deleteAll` for any `Identifiable & Codable` type |
| **Key-value storage** | `set` / `get` / `remove` for any `Codable` value under a string key |
| **Repositories** | `storage.repository(User.self)` — a typed handle without the `T.self` noise |
| **Queries** | Four sort orders, `limit` / `offset` pushed down to SwiftData, 1-based pages with totals, and closure filters on any DTO field |
| **Indexed fields** | Declare up to three fields per type; `matching:` filters, `orderedBy:`, counts and pages on them run inside SwiftData |
| **Observation** | Typed change feeds (`AsyncStream`), coalescing live queries for SwiftUI, and batched iteration of large types |
| **Cache expiration** | `.seconds`, `.minutes`, `.hours`, `.days`, `.date`, `.never`; expired records read as absent and are purged lazily; `removeExpired()` |
| **Metadata** | created/updated/expiry dates, payload size, stored DTO version and expiry state per record |
| **Isolation** | Types sharing an ID never collide; entities and key-value entries live in separate namespaces |
| **Concurrency** | Swift 6 strict concurrency; SwiftData access confined to a `@ModelActor`; safe to call from any task |
| **Errors** | One `LocalStorageError` with a stable `Code`; no SwiftData error leaks out; missing data is `nil`, not an error |
| **Pluggable coding** | `StorageEncoder` / `StorageDecoder` protocols with JSON defaults |
| **Logging** | `StorageLogger` sink with level filtering and an `os.Logger` implementation; payloads are never logged |
| **Testability** | `.inMemory` configuration and an `InMemoryStorageEngine` test double |
| **Migrations** | Versioned DTOs with typed or raw upgrade steps, applied lazily on read or eagerly with `migrateAll`; the internal store schema migrates through a `SchemaMigrationPlan` |

---

## Requirements

| | Minimum |
|---|---|
| Swift | 6.0 |
| Xcode | 16.0 |
| iOS / iPadOS | 17.0 |
| macOS | 14.0 |
| tvOS | 17.0 |
| watchOS | 10.0 |
| visionOS | 1.0 |

These are SwiftData's minimum platforms. Linux and Windows are not supported because SwiftData is
Apple-only.

---

## Installation

### Swift Package Manager (Package.swift)

```swift
dependencies: [
    .package(url: "https://github.com/ihusnainalii/SwiftLocalStorage.git", from: "0.6.0"),
],
targets: [
    .target(name: "MyApp", dependencies: ["SwiftLocalStorage"]),
]
```

### Xcode

**File ▸ Add Package Dependencies…**, paste
`https://github.com/ihusnainalii/SwiftLocalStorage.git`, choose **Up to Next Minor Version** from
`0.6.0` (pre-1.0), and add the `SwiftLocalStorage` library to your target.

---

## Quick start

```swift
import SwiftLocalStorage

struct Product: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let price: Double
}

// 1. Open a store (once, e.g. in your app's composition root).
let storage = try LocalStorage()

// 2. Save.
try await storage.save(product)
try await storage.save(products)                           // one transaction
try await storage.save(product, expiration: .minutes(10))  // cache entry

// 3. Read.
let product  = try await storage.fetch(Product.self, id: 42)   // Product?
let products = try await storage.fetch(Product.self)           // [Product]

// 4. Delete.
try await storage.delete(Product.self, id: 42)
```

---

## API at a glance

Every call is `async`, and every call except the streaming ones `throws` a `LocalStorageError`.

| Task | `LocalStorage` | `LocalRepository<T>` |
|---|---|---|
| Save (insert or replace) | `save(value, expiration:)`, `save([values], expiration:)` | `save(_:expiration:)` |
| Read one | `fetch(T.self, id:)` → `T?` | `fetch(id:)` |
| Read all | `fetch(T.self)`, `fetch(T.self, options:)` | `fetchAll()`, `fetchAll(options:)` |
| Filter (closure, in memory) | `fetch(T.self, where:options:)` | `fetch(where:options:)` |
| Filter / order (indexed, in store) | `fetch(T.self, matching:orderedBy:options:)` | `fetch(matching:orderedBy:options:)` |
| Page | `page(T.self, page:pageSize:sort:)`, `page(T.self, matching:orderedBy:page:pageSize:)` | `page(_:pageSize:sort:)`, `page(matching:…)` |
| Count / exists | `count(T.self)`, `count(T.self, matching:)`, `exists(T.self, id:)` | `count()`, `count(matching:)`, `exists(id:)` |
| Delete | `delete(T.self, id:)`, `delete([values])`, `deleteAll(T.self)` | `delete(id:)`, `delete(_:)`, `deleteAll()` |
| Metadata | `metadata(T.self, id:)` → `StorageMetadata?` | `metadata(id:)` |
| Observe | `changes(of:)`, `updates(of:options:)`, `all(_:batchSize:)` | `changes()`, `updates(options:)`, `all(batchSize:)` |
| Key-value | `set(_:forKey:expiration:)`, `get(_:forKey:)`, `remove(forKey:)` | — |
| Maintenance | `removeExpired()`, `removeAll()`, `migrateAll(T.self)` | — |

| Protocol your type can adopt | Purpose |
|---|---|
| `LocalStorageNaming` | Pin a stable storage name (`static var storageTypeName`) |
| `LocalStorageVersioned` | Declare the DTO's stored version (`static var storageVersion`) for [migrations](#migrating-stored-dtos) |
| `LocalStorageIndexed` | Declare up to three [indexed fields](#indexed-fields) (`static var storageIndexes`) |

---

## Architecture

```text
 Your Codable DTOs
        │
        ▼
┌─────────────────────────┐   encode / decode (StorageEncoder / StorageDecoder)
│      LocalStorage       │   key building, expiry policy, error mapping, logging
│  LocalRepository<T>     │
└────────────┬────────────┘
             │  records: key + bytes + dates + index values   (internal StorageEngine protocol)
             ▼
┌─────────────────────────┐        ┌──────────────────────────┐
│ SwiftDataEngine         │        │ InMemoryStorageEngine    │
│ (@ModelActor)           │        │ (test double, SPI)       │
└────────────┬────────────┘        └──────────────────────────┘
             ▼
  ModelContainer ── StoredRecord (@Model, schema V3; V1 and V2 stores upgrade in place)
```

- **One envelope table.** Every value is a `StoredRecord` row: a unique `key`, a `kind`, the type
  name, the encoded `payload`, the payload's DTO `schemaVersion`, `createdAt` / `updatedAt` /
  `expiresAt`, an insertion `sequence` that keeps same-instant records in the order they were saved,
  and three string plus three number **index slots** with the signature of the index declaration
  that filled them. Adding a new DTO type never changes the SwiftData schema.
- **Two kinds of versioning.** The *store* schema (V1 → V2 → V3) migrates through a SwiftData
  `SchemaMigrationPlan` when the store opens. *Your DTOs* migrate record by record through
  `StorageMigration` steps when they are read.
- **Encoding happens outside the actor.** `LocalStorage` encodes and decodes; the engine only moves
  bytes. That keeps the actor's critical section short and the engine free of generics.
- **Only value snapshots leave the actor.** Live `@Model` objects never cross an isolation boundary.

---

## Core concepts

| Concept | Meaning |
|---|---|
| **Entity** | An `Identifiable & Codable & Sendable` value, addressed by its type and `id` |
| **Key-value entry** | Any `Codable & Sendable` value, addressed by a string key |
| **Record key** | `e\|<type name>\|<id>` for entities, `kv\|<key>` for key-value entries |
| **Type name** | `String(reflecting: T.self)` (module-qualified) unless the type adopts `LocalStorageNaming` |
| **Live record** | A record that has no expiry, or whose expiry is still in the future |
| **DTO version** | The version a payload was written with: `T.storageVersion`, or 1 when `T` isn't `LocalStorageVersioned` |
| **Index signature** | The `name:kind` list of a type's index declaration, stored per record to detect stale index values |

---

## Entity storage

Any `Identifiable & Codable & Sendable` type works. The `id` can be any type whose
`String(describing:)` is unique per value: `UUID`, `Int`, `String`, and so on.

```swift
try await storage.save(user)                    // insert, or replace the same ID
try await storage.save([alice, bob])            // all-or-nothing transaction

let user   = try await storage.fetch(User.self, id: id)   // nil when missing or expired
let users  = try await storage.fetch(User.self)           // oldest first
let count  = try await storage.count(User.self)
let exists = try await storage.exists(User.self, id: id)

try await storage.delete(User.self, id: id)     // no-op when missing
try await storage.delete([alice, bob])          // bulk delete by ID
try await storage.deleteAll(User.self)          // one type only
try await storage.removeAll()                   // everything in the store
```

Saving an existing ID replaces its payload and expiry and bumps `updatedAt`. `createdAt` is kept.

---

## Key-value storage

For preferences, feature flags, timestamps, onboarding state and other small values:

```swift
struct AppSettings: Codable, Sendable {
    var darkMode: Bool
    var fontSize: Int
}

try await storage.set(AppSettings(darkMode: true, fontSize: 14), forKey: "settings")
let settings = try await storage.get(AppSettings.self, forKey: "settings")   // AppSettings?
try await storage.set(Date(), forKey: "lastSync")
try await storage.remove(forKey: "settings")
```

> [!WARNING]
> Key-value storage is **not** a secret store. Records are stored unencrypted in the app's
> container. Keep access tokens, passwords and keys in the Keychain.

---

## Repositories

A repository is a `LocalStorage` scoped to one type:

```swift
let users = storage.repository(User.self)

try await users.save(user)
try await users.save([alice, bob], expiration: .hours(1))
let one  = try await users.fetch(id: id)
let all  = try await users.fetchAll()
let meta = try await users.metadata(id: id)
try await users.delete(id: id)
try await users.deleteAll()
```

`LocalRepository` is a lightweight `Sendable` struct. Create it wherever you need it, or inject it
into a feature so the feature only sees its own type. It mirrors every entity call on
`LocalStorage`, including queries, indexed queries and observation. See
[API at a glance](#api-at-a-glance).

---

## Queries: sorting, paging, filtering

```swift
// Sort and slice inside the store: only the requested rows are loaded and decoded.
let latest = try await storage.fetch(User.self, options: FetchOptions(sort: .newestFirst, limit: 20))
let next   = try await storage.fetch(User.self, options: FetchOptions(limit: 20, offset: 20))

// Pages are 1-based and carry totals for paging UI.
let page = try await storage.page(User.self, page: 1, pageSize: 50)
page.items        // [User]
page.totalCount   // live users across all pages
page.totalPages
page.hasNextPage

// Filter on any DTO field with a Swift closure, then sort and slice.
let admins = try await storage.fetch(
    User.self, where: { $0.role == .admin },
    options: FetchOptions(sort: .recentlyUpdated, limit: 10)
)
```

| `StorageSort` | Order |
|---|---|
| `.oldestFirst` (default) | first saved first |
| `.newestFirst` | last saved first |
| `.recentlyUpdated` | most recently saved or updated first |
| `.leastRecentlyUpdated` | least recently updated first |

Ties, such as records saved in the same batch, are broken by insertion order, so every order is
stable. Expired records never appear in results, counts or page totals.

> [!NOTE]
> DTO fields live inside encoded payloads, so `fetch(_:where:)` loads and decodes every live value
> of the type before filtering. Sorting, `limit`, `offset` and `page` run inside the store and load
> only the requested rows. For hot filters and sorts on DTO fields, use
> [indexed fields](#indexed-fields).

Repositories have the same calls: `fetchAll(options:)`, `fetch(where:options:)` and
`page(_:pageSize:sort:)`.

---

## Indexed fields

Declare up to three fields per type. Their values are stored next to each record, so filters,
ordering, counts and pages on them run inside SwiftData, and only the rows you get back are decoded.

```swift
extension User: LocalStorageIndexed {
    static var storageIndexes: [StorageIndex<User>] {
        [
            .string("role") { $0.role.rawValue },
            .number("age") { $0.age },              // Int, Double, Float, Date or Bool
            .number("lastSeen") { $0.lastSeen },   // optional: nil means "no value"
        ]
    }
}

let admins = try await storage.fetch(
    User.self,
    matching: [.equals("role", "admin"), .atLeast("age", 18)],   // conditions are ANDed
    orderedBy: .descending("lastSeen"),
    options: FetchOptions(limit: 20)
)
let adults = try await storage.count(User.self, matching: [.atLeast("age", 18)])
let page   = try await storage.page(User.self, matching: [.between("age", 18...30)],
                                    orderedBy: .ascending("age"), page: 1, pageSize: 50)
```

| Filter | Matches |
|---|---|
| `.equals(name, "text")` | string index equal to the value |
| `.equals(name, 42)` / `true` / a `Date` | number index equal to the value |
| `.atLeast(name, value)` / `.atMost(name, value)` | number index ≥ / ≤ the value |
| `.between(name, lower...upper)` | number index within the range |

- **Missing values:** a record whose indexed value is `nil` never matches a condition on that
  index. It sorts first ascending and last descending, and ties keep insertion order.
- **Adding or changing indexes is safe.** Records saved before the type was indexed, or under a
  different declaration, are re-indexed automatically on the next indexed query. DTO migrations
  refresh index values too.
- Closures make computed indexes easy, for example `.string("email") { $0.email.lowercased() }`.
- Repositories have the same calls: `fetch(matching:orderedBy:options:)`, `count(matching:)` and
  `page(matching:orderedBy:page:pageSize:)`.

---

## Observation and SwiftUI

**Live query:** the current results, then the results again after every change to the type. This is
the simplest way to keep a SwiftUI list in sync:

```swift
struct UsersView: View {
    let storage: LocalStorage
    @State private var users: [User] = []

    var body: some View {
        List(users) { Text($0.name) }
            .task {
                do {
                    for try await latest in storage.updates(of: User.self, options: FetchOptions(sort: .newestFirst)) {
                        users = latest
                    }
                } catch {
                    // LocalStorageError, e.g. a record that no longer decodes
                }
            }
    }
}
```

The loop ends when the view disappears, because SwiftUI cancels `.task`. Bursts of writes
are coalesced into one refetch.

**Change feed:** each change as a typed event:

```swift
for await change in storage.changes(of: User.self) {
    switch change {
    case .inserted(let user):  print("new", user.name)
    case .updated(let user):   print("changed", user.name)
    case .deleted(let user):   print("removed", user.name)   // the value as it was stored
    case .cleared:             print("deleteAll or removeAll")
    case .expired:             print("removeExpired purged records")
    }
}
```

| Write | Event |
|---|---|
| `save` of a new / existing ID | `.inserted` / `.updated` (one per value, in order, for batches) |
| `delete(_:id:)`, `delete([T])` | `.deleted(storedValue)` for each record that existed |
| `deleteAll(T.self)` | `.cleared` for `T` |
| `removeAll()` | `.cleared` for every observed type |
| `removeExpired()` removing records | `.expired` for every observed type |

Events are delivered after the write commits. Failed writes, key-value entries, lazy expiry on read,
and writes made by *another* `LocalStorage` instance don't produce events.

**Large types:** `all(_:batchSize:)` loads one batch per step instead of everything at once:

```swift
for try await user in storage.all(User.self, batchSize: 200) {
    try await export(user)
}
```

Repositories have `changes()`, `updates(options:)` and `all(batchSize:)`.

---

## Cache expiration

Pass an expiration to any save:

```swift
try await storage.save(user, expiration: .minutes(10))
try await storage.save(feed, expiration: .hours(1))
try await storage.set(config, forKey: "remoteConfig", expiration: .days(1))
try await storage.save(banner, expiration: .date(campaignEnd))
try await storage.save(profile)                           // .never (the default)
```

| Operation | Behavior with an expired record |
|---|---|
| `fetch(_:id:)`, `get(_:forKey:)` | returns `nil`, and deletes the record |
| `fetch(_:)` | skips it, and deletes it |
| `count(_:)`, `exists(_:id:)` | does not count it |
| `metadata(_:id:)` | still returns it, with `isExpired == true` |
| `removeExpired()` | deletes every expired record and returns how many |

Re-saving a value replaces its expiry, so saving a fresh network response renews the cache entry.
Reads already purge the expired records they touch, so `removeExpired()` is only needed to reclaim
space, for example on launch or when the app moves to the background:

```swift
let purged = try await storage.removeExpired()
```

---

## Metadata

```swift
if let meta = try await storage.metadata(User.self, id: id) {
    meta.createdAt   // first save
    meta.updatedAt   // last save
    meta.expiresAt   // nil = never
    meta.size        // encoded payload size in bytes
    meta.version     // DTO version the payload was stored with
    meta.isExpired
}
```

This is useful for "last updated" labels, refresh decisions, and debugging cache behavior.

---

## Configuration

```swift
let storage = try LocalStorage(configuration: .init(
    name: "MyApp",                        // distinct names are distinct stores
    isStoredInMemoryOnly: false,
    encoder: JSONStorageEncoder(),
    decoder: JSONStorageDecoder(),
    logger: OSLogStorageLogger(subsystem: "com.example.myapp"),
    logLevel: .info,
    migrations: []                        // StorageMigration steps, see "Migrating stored DTOs"
))

// Tests and SwiftUI previews: nothing touches the file system.
let preview = try LocalStorage(configuration: .inMemory)
```

Open **one** `LocalStorage` per store name and share it. It is `Sendable`, so you can pass it
anywhere, including across actors.

---

## Custom encoding

Encoding is pluggable. Conform to `StorageEncoder` / `StorageDecoder`, for example to use a custom
date strategy or a binary format:

```swift
struct ISO8601Encoder: StorageEncoder {
    func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
}

struct ISO8601Decoder: StorageDecoder {
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

let storage = try LocalStorage(configuration: .init(encoder: ISO8601Encoder(), decoder: ISO8601Decoder()))
```

Changing the encoding of an existing store makes older records undecodable, so choose a format
before you ship.

---

## Stable type names

Records are keyed by the type's module-qualified name, such as `MyApp.User`. This prevents two
`User` types in different modules from colliding. The downside is that **renaming or moving a type
orphans its stored records**. Pin a name before you ship:

```swift
extension User: LocalStorageNaming {
    static var storageTypeName: String { "User" }
}
```

---

## Evolving your DTOs

Your DTOs are stored as encoded bytes, so they must stay `Codable`-compatible across app versions.

| Change | Result |
|---|---|
| Add an **optional** property | ✅ Old records decode; the new property is `nil` |
| Add a property with a default in a custom `init(from:)` | ✅ Old records decode |
| Remove a property | ✅ The extra key is ignored |
| Add a **required** property | ❌ Old records throw `decodingFailed`, unless you add a [migration](#migrating-stored-dtos) |
| Rename a property or change its type | ❌ Old records throw `decodingFailed`, unless you add a migration |
| Rename the type without `LocalStorageNaming` | ⚠️ Old records become unreachable |

For cached data, the simplest fix is often to catch `decodingFailed`, delete the record, and
refetch. For user data, use a migration.

### Migrating stored DTOs

Declare the DTO's version, and register one step per version bump. Types that don't adopt
`LocalStorageVersioned` are version 1, and so is every record written before 0.5.

```swift
struct User: Codable, Identifiable, Sendable, LocalStorageNaming, LocalStorageVersioned {
    static var storageTypeName: String { "User" }
    static var storageVersion: Int { 3 }
    let id: UUID
    var fullName: String
    var role: String
}

let storage = try LocalStorage(configuration: .init(migrations: [
    // Typed step: decode the old shape, return the next one.
    StorageMigration(User.self, from: 1) { (old: UserV1) in
        UserV2(id: old.id, fullName: old.name)
    },
    // Raw step: edit the encoded payload when the old type no longer exists in code.
    StorageMigration(User.self, from: 2) { json in
        var object = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        object["role"] = "member"
        return try JSONSerialization.data(withJSONObject: object)
    },
]))
```

- **Reads migrate lazily.** Reading an older record runs the steps `v → v+1 → … → current`, decodes
  the result, and writes the upgraded payload back once. The write-back keeps `createdAt`,
  `updatedAt` and expiry, and it doesn't emit change events.
- **Or migrate eagerly** with `try await storage.migrateAll(User.self)`, for example at launch after
  a release. It returns how many records it upgraded.
- **Failures leave the record untouched** and throw `LocalStorageError.migrationFailed(key:underlying:)`.
  `underlying` is `StorageMigrationError.missingStep`, `StorageMigrationError.storedVersionNewer`
  (an older app reading data from a newer one), or whatever the step threw.
- Key-value values migrate the same way, keyed by their value type.
- `metadata(_:id:)?.version` reports a record's stored version.

---

## Error handling

Every failure is a `LocalStorageError`:

| Case | When |
|---|---|
| `encodingFailed(underlying:)` | The value could not be encoded. Nothing was written. |
| `decodingFailed(key:underlying:)` | Stored bytes do not decode into the requested type (DTO change or corrupt record) |
| `migrationFailed(key:underlying:)` | An older record couldn't be upgraded to the type's current version (see [Migrating stored DTOs](#migrating-stored-dtos)) |
| `persistenceFailed(underlying:)` | The underlying store failed to read or write |
| `containerInitializationFailed(underlying:)` | The store could not be opened |
| `cancelled` | The calling task was cancelled before the operation started. Nothing was written. |

A missing or expired record is **not** an error; reads return `nil`.

```swift
do {
    let user = try await storage.fetch(User.self, id: id)
} catch let error as LocalStorageError {
    switch error.code {
    case .decodingFailed:
        try await storage.delete(User.self, id: id)     // stale shape: drop and refetch
    case .cancelled:
        break
    default:
        logger.error("storage failed: \(error)")
    }
}
```

`error.code` is a stable, `Equatable` discriminant you can use in `switch` statements and tests.

---

## Logging

Logging is off by default. Turn it on with a sink and a level:

```swift
let storage = try LocalStorage(configuration: .init(
    logger: OSLogStorageLogger(subsystem: "com.example.myapp", category: "storage"),
    logLevel: .info
))
```

| Level | Emits |
|---|---|
| `.none` | nothing (default) |
| `.error` | failed operations |
| `.info` | plus writes and deletes (operation, key, byte count) |
| `.debug` | plus reads |

Log lines never contain payloads or error descriptions, only the operation, the key, byte counts
and the error's type. To route lines elsewhere, conform to `StorageLogger`:

```swift
struct PrintLogger: StorageLogger {
    func log(_ line: String, level: StorageLogLevel) { print(line) }
}
```

---

## Testing and mocking

Use an in-memory store in unit tests and SwiftUI previews:

```swift
import Testing
import SwiftLocalStorage

@Test func cachesProfile() async throws {
    let storage = try LocalStorage(configuration: .inMemory)
    let sut = ProfileService(storage: storage)
    ...
}
```

For tests that need no SwiftData at all, or that need to seed raw bytes (for example a corrupt
record), use the test double behind the `SwiftLocalStorageTesting` SPI:

```swift
@_spi(SwiftLocalStorageTesting) import SwiftLocalStorage

// SwiftData-backed, in memory, with a controllable clock: test expiry without waiting.
let storage = try LocalStorage(configuration: .inMemory, now: { clock.now })

// No SwiftData at all; seed raw or old-version records directly.
let engine = InMemoryStorageEngine()
let double = LocalStorage(engine: engine, now: { fixedDate })
await engine.insertRaw(Data("{ bad".utf8), typeName: "User", id: "1")
await engine.insertRaw(oldPayload, typeName: "User", id: "2", version: 1)
```

SPI types are for tests. They are not covered by the semantic-versioning guarantee.

---

## Thread safety

- `LocalStorage`, `LocalRepository`, `LocalStorageConfiguration` and every public value type are
  `Sendable`.
- All SwiftData work runs on one `@ModelActor`, so there is no shared `ModelContext` and no data
  race. The test suite runs 100 concurrent saves, reads and mixed operations, and passes under
  ThreadSanitizer.
- The same behavioral contract suite runs against both the SwiftData engine and the in-memory test
  double, so tests written against the double hold for production. Library line coverage is about
  95%, and CI fails below 90%.
- Encoding and decoding run on the caller's task, outside the actor, so they don't queue behind
  other storage work.
- Batch saves are atomic: the whole batch is stored, or none of it is.

---

## Performance

What each call costs, so you can pick the right one for large types:

| Call | Work done |
|---|---|
| `fetch(_:id:)`, `exists`, `metadata` | one indexed lookup by key, one decode |
| `fetch(_:options:)`, `page(_:page:pageSize:)` | sort and slice in SQLite; decodes only the rows returned |
| `fetch(_:matching:orderedBy:options:)`, `count(_:matching:)`, `page(_:matching:…)` | filter, sort and slice in SQLite on index slots; decodes only the rows returned |
| `count(_:)` | a `COUNT` in SQLite; decodes nothing |
| `fetch(_:where:options:)` | loads and decodes **every** live value of the type, then filters in memory |
| `all(_:batchSize:)` | one `limit`/`offset` fetch per batch as the loop advances |
| `save([values])` | encodes on the caller's task, then one transaction |
| `updates(of:)` | one refetch per burst of writes, not one per write |
| First indexed query of a type | re-indexes stale records once per declaration per `LocalStorage` instance |
| First read of an old-version record | runs its migration steps once and writes the result back |
| `migrateAll(_:)` | loads every live record of the type in one pass |

Encoding and decoding run on the calling task, outside the storage actor, so a large decode
doesn't block other storage calls. Logging is off by default, and log lines are built only when
their level is enabled.

---

## Using it with SwiftNetworkKit

A cache-first repository in a few lines:

```swift
import SwiftNetworkKit
import SwiftLocalStorage

struct UserRepository: Sendable {
    let client: NetworkClient
    let users: LocalRepository<User>

    func user(id: UUID) async throws -> User {
        if let cached = try await users.fetch(id: id) {
            return cached                                     // fresh cache hit
        }
        let user: User = try await client.request(GetUser(id: id))
        try await users.save(user, expiration: .minutes(15))
        return user
    }
}
```

Network-first, stale-while-revalidate and other policies follow the same shape. A generic cached
repository is a candidate for a future companion package; see the [roadmap](ROADMAP.md).

---

## Complete example

One feature, using most of the package: a versioned, indexed DTO cached from the network, a
migration for its previous shape, a live SwiftUI list, and maintenance at launch.

```swift
import SwiftLocalStorage
import SwiftUI

// MARK: Model

struct Article: Codable, Identifiable, Sendable {
    let id: Int
    var title: String
    var topic: String
    var publishedAt: Date
    var isRead: Bool            // added in version 2
}

extension Article: LocalStorageNaming, LocalStorageVersioned, LocalStorageIndexed {
    static var storageTypeName: String { "Article" }
    static var storageVersion: Int { 2 }
    static var storageIndexes: [StorageIndex<Article>] {
        [.string("topic") { $0.topic }, .number("publishedAt") { $0.publishedAt }, .number("isRead") { $0.isRead }]
    }
}

/// How version 1 was stored, before `isRead` existed.
private struct ArticleV1: Codable, Sendable {
    let id: Int
    var title: String
    var topic: String
    var publishedAt: Date
}

// MARK: Storage

enum AppStorage {
    static func open() throws -> LocalStorage {
        try LocalStorage(configuration: .init(
            name: "News",
            logger: OSLogStorageLogger(subsystem: "com.example.news"),
            logLevel: .error,
            migrations: [
                StorageMigration(Article.self, from: 1) { (old: ArticleV1) in
                    Article(id: old.id, title: old.title, topic: old.topic, publishedAt: old.publishedAt, isRead: false)
                },
            ]
        ))
    }

    /// Launch maintenance: upgrade old records up front and reclaim expired cache space.
    static func maintain(_ storage: LocalStorage) async {
        _ = try? await storage.migrateAll(Article.self)
        _ = try? await storage.removeExpired()
    }
}

// MARK: Repository

struct ArticleRepository: Sendable {
    let articles: LocalRepository<Article>
    let fetchRemote: @Sendable () async throws -> [Article]      // e.g. a SwiftNetworkKit call

    /// Serve the cache while it's fresh (expired records don't count); otherwise refresh it.
    func refreshIfNeeded() async throws {
        guard try await articles.count() == 0 else { return }
        try await articles.save(try await fetchRemote(), expiration: .minutes(30))
    }

    /// Unread articles in a topic, newest first, filtered and sorted in the store.
    func unread(topic: String) -> AsyncThrowingStream<[Article], any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await _ in articles.updates() {           // re-run on every change
                        continuation.yield(try await articles.fetch(
                            matching: [.equals("topic", topic), .equals("isRead", false)],
                            orderedBy: .descending("publishedAt")
                        ))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func markRead(_ article: Article) async throws {
        var read = article
        read.isRead = true
        try await articles.save(read, expiration: .minutes(30))
    }
}

// MARK: UI

struct UnreadView: View {
    let repository: ArticleRepository
    let topic: String
    @State private var articles: [Article] = []

    var body: some View {
        List(articles) { article in
            Button(article.title) { Task { try? await repository.markRead(article) } }
        }
        .task {
            try? await repository.refreshIfNeeded()
            do {
                for try await unread in repository.unread(topic: topic) { articles = unread }
            } catch {
                // LocalStorageError: show an error state
            }
        }
    }
}
```

> [!NOTE]
> Keeping `isRead` inside a cached DTO is shown for brevity. For state the user owns, a separate
> non-expiring type is usually better, so a cache expiry can't drop it.

---

## Demo app

[`Examples/SwiftLocalStorageDemo`](Examples/SwiftLocalStorageDemo) is a complete SwiftUI iOS app
built with Clean Architecture + MVVM:

| Tab | Shows |
|---|---|
| **Catalog** | cache-first loading with a live expiry countdown, paging, and a category filter and price sort on indexed fields |
| **Notes** | a CRUD repository rendered from a live query; `Note` is on version 2 with a migration |
| **Settings** | key-value storage for preferences and launch bookkeeping |
| **Inspector** | a live change feed, record counts, `removeExpired()`, delete-all and the storage log |

The Domain layer never imports the package, and the demo's tests run its real repositories and
view models on an in-memory store with an injected clock.

```bash
open Examples/SwiftLocalStorageDemo/SwiftLocalStorageDemo.xcodeproj
```

---

## Best practices

- Create one `LocalStorage` per store and inject it. Don't open a new one per call.
- Adopt `LocalStorageNaming` on every type you persist before your first release.
- Keep persisted DTOs backward-compatible. Prefer optional additions.
- Use expirations for anything that came from the network, and `.never` for user-created data.
- Call `removeExpired()` occasionally, for example on launch or on background, if you cache a lot
  of data.
- Use `.inMemory` in tests and previews.
- Never store secrets here. Use the Keychain.

---

## Known limitations

- **Closure filters run in memory.** `fetch(_:where:)` decodes every live value of the type before
  filtering. Use [indexed fields](#indexed-fields) for filters and sorts that must scale. Indexed
  queries support AND only, with up to three indexes per type and no string prefix search.
- **Change events are per instance.** Only writes made through the same `LocalStorage` instance are
  observed. Share one instance per store.
- **Key-value entries aren't observable**, and `updates(of:)` re-runs a plain `fetch(_:options:)`.
  For a live indexed query, re-run your indexed fetch on each `changes(of:)` event (see the
  [complete example](#complete-example)).
- **Migrations go forward only.** An older app build reading a newer record gets `migrationFailed`
  with `storedVersionNewer`.
- **Apple platforms only**, because SwiftData is Apple-only.
- **No encryption at rest** beyond the platform's data protection.

---

## FAQ

**Why not just use SwiftData directly?**
Do that if you're happy modeling your data as `@Model` classes. SwiftLocalStorage is for apps whose
model is already a set of `Codable` DTOs and who want caching semantics (expiration, metadata)
without a parallel entity layer.

**Why not `UserDefaults` or files?**
`UserDefaults` is meant for small preferences, and hand-rolled file caches need their own
indexing, expiry and concurrency control. SwiftLocalStorage gives you both entity and key-value
storage behind one API, with transactions and concurrency safety.

**Why does `fetch` return an optional instead of throwing `notFound`?**
For a cache, a miss is normal control flow. Errors are reserved for things that actually went
wrong.

**Can I use my own storage engine?**
Not yet. The engine protocol is internal while its shape settles. It will be considered for public
API before 1.0.

**What happens to data already on devices when I update the package?**
It's kept. The store schema upgrades itself when the store opens: stores from 0.1–0.2.2 (V1) and
0.2.3–0.5 (V2) move to the current V3 in place. Records written before indexes existed are
re-indexed on the first indexed query. Your *DTO* changes are yours to migrate, see
[Migrating stored DTOs](#migrating-stored-dtos).

**Does it work with SwiftUI?**
Yes. `updates(of:)` is a live query built for `.task { for try await ... }`, and `changes(of:)`
gives typed events for view models. See [Observation and SwiftUI](#observation-and-swiftui).

---

## Communication

| If you want to | Then |
|---|---|
| Ask how to do something, or discuss an idea | Open a thread in [GitHub Discussions](https://github.com/ihusnainalii/SwiftLocalStorage/discussions) |
| Report a bug | Open a [GitHub issue](https://github.com/ihusnainalii/SwiftLocalStorage/issues) with your OS/Xcode versions and a minimal reproduction |
| Request a feature | Start a Discussion first, then open an issue if there is agreement |
| Report a security vulnerability | Do **not** open a public issue. Follow [SECURITY.md](SECURITY.md) |
| Contribute code | Read [CONTRIBUTING.md](CONTRIBUTING.md) first |

---

## Upgrading

Stored data carries over across every release. Only these releases need code changes:

| From → to | What to change |
|---|---|
| any → 0.6 | Nothing required. To use indexed fields, adopt `LocalStorageIndexed`; existing records are indexed automatically. |
| ≤ 0.4 → 0.5 | `LocalStorageError` gained `migrationFailed(key:underlying:)` (and `Code.migrationFailed`). Add a case to exhaustive `switch` statements. |
| ≤ 0.2 → 0.3+ | Nothing required. New parameters all have defaults. |

See [CHANGELOG.md](CHANGELOG.md) for every change by version.

---

## Versioning

[Semantic Versioning](https://semver.org). Before 1.0.0, a **minor** version may contain breaking
changes and a **patch** version never does. From 1.0.0: **major** for breaking changes, **minor**
for additions, **patch** for fixes. Types behind `@_spi(SwiftLocalStorageTesting)` are never
covered.

Every release is tagged `vX.Y.Z`, has a GitHub Release, and has a section in
[CHANGELOG.md](CHANGELOG.md). Commits follow [Conventional Commits](https://www.conventionalcommits.org).

---

## Roadmap

See [ROADMAP.md](ROADMAP.md). Queries shipped in 0.3, observation in 0.4, DTO migrations in 0.5 and
indexed fields in 0.6. Next up: the 1.0 API freeze.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). In short: zero dependencies, Swift 6 strict concurrency,
Conventional Commits, a `CHANGELOG.md` entry with every change, and green checks:

```bash
swift build --build-tests -Xswiftc -warnings-as-errors
swift test --parallel
swift test --sanitize=thread
bash scripts/coverage.sh          # line coverage floor: 90%
```

---

## Security policy

See [SECURITY.md](SECURITY.md) for supported versions and how to privately report a
vulnerability.

---

## License

SwiftLocalStorage is released under the [Apache License 2.0](LICENSE).

---

## Author

**Husnain Ali** ([GitHub @ihusnainalii](https://github.com/ihusnainalii))
