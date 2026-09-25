# Roadmap

## Shipped

| Version | Highlights |
|---|---|
| **0.1.0** | SwiftData envelope store, entity CRUD, transactional batch save, key-value storage, `LocalRepository`, `LocalStorageError`, in-memory configuration, Swift Testing suite |
| **0.2.0** | `CacheExpiration`, lazy purge of expired records, `StorageMetadata`, `removeExpired()`, bulk delete, `StorageLogger` + `OSLogStorageLogger` |
| **0.2.1–0.2.3** | 96% coverage with a 90% floor, clean-architecture demo app, schema V2 (insertion sequence) with V1 migration |
| **0.3.0** | `FetchOptions` (sort, limit, offset in the store), `StorageSort`, 1-based `StoragePage`, closure filters on DTO fields |
| **0.4.0** | `changes(of:)` typed change feed, `updates(of:options:)` coalescing live query, `all(_:batchSize:)` batched iteration |
| **0.5.0** | `LocalStorageVersioned` DTOs, typed/raw `StorageMigration` steps, lazy write-back on read, `migrateAll`, `LocalStorageError.migrationFailed` |
| **0.6.0** | `LocalStorageIndexed` (up to 3 string/number indexes), in-store `matching:` filters, `orderedBy:`, counts and pages, automatic re-indexing, schema V3 |
| **1.0.0** | API freeze (CI breakage check), DocC catalog, benchmarks target, linear batch saves, multi-platform CI (iOS, macOS, tvOS, watchOS, visionOS) |

## Beyond 1.0 (candidates)

- A companion package with a generic cached repository (`cacheFirst`, `networkFirst`,
  `staleWhileRevalidate`) built on SwiftNetworkKit + SwiftLocalStorage.
- Alternative engines (SQLite, file-based). The engine protocol stays internal in 1.x, so a public
  engine is a 2.0 candidate.
- Optional encryption at rest.

Have feedback? Open a [Discussion](https://github.com/ihusnainalii/SwiftLocalStorage/discussions).
