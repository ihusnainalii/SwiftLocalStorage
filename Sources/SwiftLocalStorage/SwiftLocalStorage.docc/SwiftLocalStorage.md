# ``SwiftLocalStorage``

Persist your existing `Codable` DTOs through SwiftData, with no `@Model` classes.

## Overview

SwiftLocalStorage stores any `Codable & Identifiable & Sendable` value in a SwiftData store that the
package owns. Your API models stay the single source of truth: no mirrored entity layer, no mapping
code, and no SwiftData types in your domain.

```swift
struct User: Codable, Identifiable, Sendable {
    let id: Int
    var name: String
}

let storage = try LocalStorage()
try await storage.save(User(id: 1, name: "Ada"), expiration: .hours(1))
let user = try await storage.fetch(User.self, id: 1)
```

On top of CRUD it gives you cache expiration, key-value entries, in-store sorting, paging and
indexed filters, typed change feeds and live queries, and migrations for DTOs whose shape changes
between app versions.

## Topics

### Essentials

- <doc:GettingStarted>
- ``LocalStorage``
- ``LocalRepository``
- ``LocalStorageConfiguration``
- ``LocalStorageError``

### Caching

- ``CacheExpiration``
- ``StorageMetadata``

### Querying

- <doc:Querying>
- ``FetchOptions``
- ``StorageSort``
- ``StoragePage``

### Indexed fields

- <doc:IndexedFields>
- ``LocalStorageIndexed``
- ``StorageIndex``
- ``StorageIndexNumber``
- ``StorageFilter``
- ``StorageIndexOrder``

### Observing changes

- <doc:ObservingChanges>
- ``StorageChange``
- ``StorageSequence``

### Migrating stored DTOs

- <doc:Migrations>
- ``LocalStorageVersioned``
- ``StorageMigration``
- ``StorageMigrationError``

### Naming and encoding

- ``LocalStorageNaming``
- ``StorageEncoder``
- ``StorageDecoder``
- ``JSONStorageEncoder``
- ``JSONStorageDecoder``

### Logging

- ``StorageLogger``
- ``StorageLogLevel``
- ``OSLogStorageLogger``
- ``NoopStorageLogger``

### Testing and stability

- <doc:Testing>
- <doc:APIStability>
