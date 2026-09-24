<h1 align="center">SwiftLocalStorage</h1>

<p align="center">
  <strong>Type-safe, concurrency-safe local persistence and caching for Swift.</strong><br />
  Persist your existing <code>Codable</code> DTOs with SwiftData — no <code>@Model</code> entities to write.<br />
  Zero external dependencies • Swift 6 strict concurrency • Actor-isolated SwiftData • Cache expiration
</p>

<p align="center">
  <a href="https://github.com/ihusnainalii/SwiftLocalStorage/actions/workflows/ci.yml"><img src="https://github.com/ihusnainalii/SwiftLocalStorage/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0-orange.svg" alt="Swift 6" /></a>
  <a href="https://swift.org/package-manager"><img src="https://img.shields.io/badge/SPM-compatible-brightgreen.svg" alt="SPM" /></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/platforms-iOS%2017%20%7C%20macOS%2014%20%7C%20tvOS%2017%20%7C%20watchOS%2010%20%7C%20visionOS%201-lightgrey.svg" alt="Platforms" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License" /></a>
</p>

- **Version:** 0.2.0 (pre-1.0: minor versions may contain breaking changes; see [Versioning](#versioning))
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
- [Architecture](#architecture)
- [Core concepts](#core-concepts)
- [Entity storage](#entity-storage)
- [Key-value storage](#key-value-storage)
- [Repositories](#repositories)
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
- [Using it with SwiftNetworkKit](#using-it-with-swiftnetworkkit)
- [Best practices](#best-practices)
- [Known limitations](#known-limitations)
- [FAQ](#faq)
- [Communication](#communication)
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
| **Cache expiration** | `.seconds`, `.minutes`, `.hours`, `.days`, `.date`, `.never`; expired records read as absent and are purged lazily; `removeExpired()` |
| **Metadata** | created/updated/expiry dates, payload size and expiry state per record |
| **Isolation** | Types sharing an ID never collide; entities and key-value entries live in separate namespaces |
| **Concurrency** | Swift 6 strict concurrency; SwiftData access confined to a `@ModelActor`; safe to call from any task |
| **Errors** | One `LocalStorageError` with a stable `Code`; no SwiftData error leaks out; missing data is `nil`, not an error |
| **Pluggable coding** | `StorageEncoder` / `StorageDecoder` protocols with JSON defaults |
| **Logging** | `StorageLogger` sink with level filtering and an `os.Logger` implementation; payloads are never logged |
| **Testability** | `.inMemory` configuration and an `InMemoryStorageEngine` test double |
| **Migration-ready** | The internal schema is a `VersionedSchema` opened with a `SchemaMigrationPlan` from day one |

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
    .package(url: "https://github.com/ihusnainalii/SwiftLocalStorage.git", from: "0.2.0"),
],
targets: [
    .target(name: "MyApp", dependencies: ["SwiftLocalStorage"]),
]
```

### Xcode

**File ▸ Add Package Dependencies…**, paste
`https://github.com/ihusnainalii/SwiftLocalStorage.git`, choose **Up to Next Minor Version** from
`0.2.0` (pre-1.0), and add the `SwiftLocalStorage` library to your target.

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

## Architecture

```text
 Your Codable DTOs
        │
        ▼
┌─────────────────────────┐   encode / decode (StorageEncoder / StorageDecoder)
│      LocalStorage       │   key building, expiry policy, error mapping, logging
│  LocalRepository<T>     │
└────────────┬────────────┘
             │  records: key + bytes + dates   (internal StorageEngine protocol)
             ▼
┌─────────────────────────┐        ┌──────────────────────────┐
│ SwiftDataEngine         │        │ InMemoryStorageEngine    │
│ (@ModelActor)           │        │ (test double, SPI)       │
└────────────┬────────────┘        └──────────────────────────┘
             ▼
  ModelContainer ── StoredRecord (@Model, schema V1)
```

- **One envelope table.** Every value is a `StoredRecord` row: a unique `key`, a `kind`, the type
  name, the encoded `payload`, a `schemaVersion`, and `createdAt` / `updatedAt` / `expiresAt`.
  Adding a new DTO type never changes the SwiftData schema.
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
into a feature so the feature only sees its own type.

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
    logLevel: .info
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
| Add a **required** property | ❌ Old records throw `LocalStorageError.decodingFailed` |
| Rename a property or change its type | ❌ Old records throw `decodingFailed` |
| Rename the type without `LocalStorageNaming` | ⚠️ Old records become unreachable |

If you make an incompatible change to cached data, the simplest fix is to catch `decodingFailed`,
delete the record, and refetch it. For user data, keep the change compatible or write a migration.
Built-in DTO migration hooks are on the [roadmap](ROADMAP.md).

---

## Error handling

Every failure is a `LocalStorageError`:

| Case | When |
|---|---|
| `encodingFailed(underlying:)` | The value could not be encoded. Nothing was written. |
| `decodingFailed(key:underlying:)` | Stored bytes do not decode into the requested type (DTO change or corrupt record) |
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

let engine = InMemoryStorageEngine()
let storage = LocalStorage(engine: engine, now: { fixedDate })   // injectable clock
await engine.insertRaw(Data("{ bad".utf8), typeName: "User", id: "1")
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
  double, so tests written against the double hold for production. Library line coverage is 96%, and CI
  fails below 90%.
- Encoding and decoding run on the caller's task, outside the actor, so they don't queue behind
  other storage work.
- Batch saves are atomic: the whole batch is stored, or none of it is.

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

- **No field queries yet.** You can fetch by ID or fetch all of a type, but you can't filter or sort
  on DTO fields. Filtering, sorting and pagination are planned for 0.3.
- **Fetch all loads every value of a type into memory.** For very large collections, split them
  into pages under different types or keys until pagination lands.
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

**Does it work with SwiftUI?**
Yes. Call it from `.task` or from your view models. Observation and `AsyncStream` change feeds are
planned for 0.4.

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

## Versioning

[Semantic Versioning](https://semver.org). Before 1.0.0, a **minor** version may contain breaking
changes and a **patch** version never does. From 1.0.0: **major** for breaking changes, **minor**
for additions, **patch** for fixes. Types behind `@_spi(SwiftLocalStorageTesting)` are never
covered.

Every release is tagged `vX.Y.Z`, has a GitHub Release, and has a section in
[CHANGELOG.md](CHANGELOG.md). Commits follow [Conventional Commits](https://www.conventionalcommits.org).

---

## Roadmap

See [ROADMAP.md](ROADMAP.md). Next up: queries and pagination (0.3), observation (0.4), DTO
migration hooks (0.5), then an API freeze for 1.0.

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
