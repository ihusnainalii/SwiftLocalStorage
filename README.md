# SwiftLocalStorage

Type-safe, concurrency-safe local persistence for Swift. Persist your existing `Codable` DTOs
with SwiftData — no `@Model` entities to write.

The persistence counterpart to [SwiftNetworkKit](https://github.com/ihusnainalii/SwiftNetworkKit):
Swift 6 strict concurrency, zero dependencies, one error type, Swift Testing.

## Requirements

iOS 17 · macOS 14 · tvOS 17 · watchOS 10 · visionOS 1 · Swift 6

## Installation

```swift
.package(url: "https://github.com/ihusnainalii/SwiftLocalStorage.git", from: "0.1.0")
```

## Usage

```swift
import SwiftLocalStorage

struct User: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
}

let storage = try LocalStorage()                 // on-disk store
// let storage = try LocalStorage(configuration: .inMemory)   // tests & previews

try await storage.save(user)                     // insert or replace
try await storage.save(users)                    // one transaction
let user  = try await storage.fetch(User.self, id: userID)   // User? — nil if missing
let users = try await storage.fetch(User.self)               // [User], oldest first
let n     = try await storage.count(User.self)
let has   = try await storage.exists(User.self, id: userID)
try await storage.delete(User.self, id: userID)
try await storage.deleteAll(User.self)
```

### Key-value

For any `Codable` value — preferences, flags, timestamps. **Not for secrets**; use the Keychain.

```swift
try await storage.set(settings, forKey: "settings")
let settings = try await storage.get(AppSettings.self, forKey: "settings")
try await storage.remove(forKey: "settings")
```

### Repository

```swift
let users = storage.repository(User.self)
try await users.save(user)
let all = try await users.fetchAll()
```

## Stable type names

Records are keyed by the type's module-qualified name, so renaming or moving a type orphans its
data. Pin a name before you ship:

```swift
extension User: LocalStorageNaming {
    static var storageTypeName: String { "User" }
}
```

## Evolving DTOs

DTOs are stored as encoded bytes, so they must stay `Codable`-compatible across app versions.
Adding an optional field is safe; adding a required one makes old records throw
`LocalStorageError.decodingFailed` — give it a default in `init(from:)` or delete the old data.

## Errors

Every failure is a `LocalStorageError` (`encodingFailed`, `decodingFailed`, `persistenceFailed`,
`containerInitializationFailed`, `cancelled`); switch on `error.code` for a stable discriminant.
A missing record is `nil`, not an error.

## Testing your code

```swift
@_spi(SwiftLocalStorageTesting) import SwiftLocalStorage

let storage = LocalStorage(engine: InMemoryStorageEngine())
```

## Roadmap

See the [design spec](docs/specs/2026-09-25-swiftlocalstorage-v0.2-design.md) and
[CHANGELOG](CHANGELOG.md).

## License

See [LICENSE](LICENSE).
