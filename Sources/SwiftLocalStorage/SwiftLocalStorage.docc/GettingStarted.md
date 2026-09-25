# Getting Started

Store, read and delete your DTOs, with optional expiration.

## Create a storage

Create one ``LocalStorage`` per store and share it; it is `Sendable` and safe to use from any task.

```swift
let storage = try LocalStorage()                                   // on disk, named "SwiftLocalStorage"
let cache   = try LocalStorage(configuration: .init(name: "Cache"))
let preview = try LocalStorage(configuration: .inMemory)           // previews and tests
```

## Save and read entities

Any `Codable & Identifiable & Sendable` type can be stored. Saving a value whose `id` already
exists replaces it; a batch save runs in one transaction.

```swift
try await storage.save(user)
try await storage.save(users, expiration: .minutes(30))

let one    = try await storage.fetch(User.self, id: 1)             // nil if missing or expired
let all    = try await storage.fetch(User.self)
let total  = try await storage.count(User.self)
let exists = try await storage.exists(User.self, id: 1)

try await storage.delete(User.self, id: 1)
try await storage.deleteAll(User.self)
```

Expired values read as missing and are deleted lazily. Call ``LocalStorage/removeExpired()`` at
launch to purge them eagerly, and ``LocalStorage/metadata(_:id:)`` to see when a value was saved,
updated or expires.

## Key-value entries

For settings and single values that have no identity:

```swift
try await storage.set(Settings(theme: .dark), forKey: "settings")
let settings = try await storage.get(Settings.self, forKey: "settings")
try await storage.remove(forKey: "settings")
```

## Repositories

A ``LocalRepository`` binds a storage to one type, which reads well in a data layer:

```swift
let users = storage.repository(User.self)
try await users.save(user)
let admins = try await users.fetch(where: { $0.isAdmin })
```

## Errors

Every failure is a ``LocalStorageError``. Switch on ``LocalStorageError/code`` when you only care
about the category.
