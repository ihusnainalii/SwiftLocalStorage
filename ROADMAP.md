# Roadmap

## Shipped

| Version | Highlights |
|---|---|
| **0.1.0** | SwiftData envelope store, entity CRUD, transactional batch save, key-value storage, `LocalRepository`, `LocalStorageError`, in-memory configuration, Swift Testing suite |
| **0.2.0** | `CacheExpiration`, lazy purge of expired records, `StorageMetadata`, `removeExpired()`, bulk delete, `StorageLogger` + `OSLogStorageLogger` |

## Next

| Version | Track | Scope |
|---|---|---|
| **0.3** | Queries | Pagination (`StoragePage`), limit/offset, sort by metadata (`createdAt`, `updatedAt`), then a robust field-filter abstraction |
| **0.4** | Observation | `observe(User.self) -> AsyncStream<StorageChange<User>>`, streaming large result sets, SwiftUI integration |
| **0.5** | Migration | Per-record DTO `schemaVersion`, consumer migration hooks (V1 → V2 payload transforms), documented schema migrations for `StoredRecord` |
| **1.0** | API freeze | DocC catalog, benchmarks target (save/fetch/delete at 1, 100 and 1,000 records; 1 MB and 10 MB payloads), coverage floor, multi-platform CI, public `StorageEngine` decision |

## Beyond 1.0 (candidates)

- A companion package with a generic cached repository (`cacheFirst`, `networkFirst`,
  `staleWhileRevalidate`) built on SwiftNetworkKit + SwiftLocalStorage.
- Alternative engines (SQLite, file-based) behind the engine seam.
- Optional encryption at rest.

Have feedback? Open a [Discussion](https://github.com/ihusnainalii/SwiftLocalStorage/discussions).
