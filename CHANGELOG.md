# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]


### Added
- Design spec for v0.6 indexed fields (`docs/specs/2026-09-25-swiftlocalstorage-v0.6-indexes-design.md`).

## [0.5.0] - 2026-09-25

### Added
- Design spec for v0.5 DTO migrations (`docs/specs/2026-09-25-swiftlocalstorage-v0.5-migrations-design.md`).
- `LocalStorageVersioned` to declare a DTO's current version (unversioned types are version 1) and `StorageMigration` steps (typed `Old → New`, or raw payload) registered in `LocalStorageConfiguration.migrations`.
- Reads upgrade older records through the step chain and write the upgraded payload back once, keeping timestamps and emitting no change events; `migrateAll(_:)` upgrades a whole type eagerly.
- `StorageMetadata.version` and `StorageMigrationError` (`missingStep`, `storedVersionNewer`).
- Migration tests on both engines: versions on save, typed + raw chains, once-only write-back with preserved timestamps, list/page/filter reads, no events, missing step, newer record, throwing step, wrong shape, key-value, `migrateAll`, legacy records.
- README "Migrating stored DTOs" section and `migrationFailed` in the error table; roadmap, security policy and demo README updated for 0.5.

### Changed
- **Breaking (pre-1.0):** `LocalStorageError` gains `migrationFailed(key:underlying:)` (and `Code.migrationFailed`); exhaustive switches need the new case.
- Internal: records now store their DTO version (the existing `schemaVersion` column) on insert and update; new engine `rewrite(key:payload:schemaVersion:)` for migration write-backs.
- Demo app: `Note` gains a required `priority` (stored version 2) with a v1 → v2 `StorageMigration`, so notes saved by earlier demo builds upgrade on first read; priority shows as a badge and is editable.

## [0.4.0] - 2026-09-25

### Added
- Design spec for v0.4 observation (`docs/specs/2026-09-25-swiftlocalstorage-v0.4-observation-design.md`).
- `changes(of:)` → `AsyncStream<StorageChange<T>>` with `.inserted`, `.updated`, `.deleted` (the stored value), `.cleared` and `.expired`, delivered after each write commits.
- `updates(of:options:)` → `AsyncThrowingStream<[T], Error>`: a live query that emits current results, then refetches after each change (bursts coalesced) — for SwiftUI `.task` loops.
- `all(_:batchSize:)` → `StorageSequence<T>`: iterate a large type oldest first, loading `batchSize` records per step.
- Repository equivalents: `changes()`, `updates(options:)`, `all(batchSize:)`.
- Observation tests on both engines: event kinds and order, stored values on delete, type isolation, no events on failure, unsubscribe on cancel/release, live-query re-emit and coalescing, batched iteration.
- README "Observation and SwiftUI" section (live query in `.task`, change-feed event table, batched iteration); roadmap, security policy and demo README updated for 0.4.

### Changed
- Internal: `StorageEngine.upsert` reports inserted keys so saves are classified as inserted/updated without extra reads; deletes read the stored value only when the type is observed.
- Demo app: Notes renders from a live query (`updates()`) with no manual reloads; the Inspector shows an app-lifetime live change feed merged from `changes(of:)` and refreshes counts on every change.

## [0.3.0] - 2026-09-25

### Added
- Design spec for v0.3 queries (`docs/specs/2026-09-25-swiftlocalstorage-v0.3-queries-design.md`).
- `FetchOptions` (`sort`, `limit`, `offset`) and `StorageSort` (`oldestFirst`, `newestFirst`, `recentlyUpdated`, `leastRecentlyUpdated`, ties broken by insertion order) via `fetch(_:options:)`; sorting and slicing run inside the store so only requested rows are decoded.
- `page(_:page:pageSize:sort:)` returning `StoragePage` (1-based `page`, `pageSize`, `totalCount`, `totalPages`, `hasNextPage`).
- `fetch(_:where:options:)` to filter on any DTO field with a Swift closure (in memory, after decoding), then sort and slice.
- Repository equivalents: `fetchAll(options:)`, `fetch(where:options:)`, `page(_:pageSize:sort:)`.
- Query tests on both engines (every sort, ties, limit/offset edges, expired exclusion, page math, filters, repository) and query logging tests.
- README "Queries: sorting, paging, filtering" section; roadmap, security policy and demo README updated for 0.3.

### Fixed
- SwiftData engine answers `limit: 0` with no rows (SwiftData treats `fetchLimit == 0` as unlimited).

### Changed
- Demo app: Catalog pages the cache 4 at a time with **Load more** (`page(_:page:pageSize:)`), filters by category (`fetch(_:where:)`), shows the empty state inside the list, and defaults the cache lifetime to 1 minute.

## [0.2.3] - 2026-09-25

### Fixed
- SwiftData engine: `fetch(_:)` returned records saved in the same batch (same `createdAt`) in random order. Records now carry an insertion `sequence` used as a tiebreaker, matching the in-memory engine and the documented insertion order.

### Changed
- Internal SwiftData schema V2 (adds `StoredRecord.sequence`); existing V1 stores upgrade automatically through a lightweight migration stage. No public API change.

### Added
- Regression tests: 50-record batch ordering on both engines, and a migration test that writes a real V1 store to disk and reopens it with the current schema.

## [0.2.2] - 2026-09-25

### Added
- Demo app `Examples/SwiftLocalStorageDemo`: a SwiftUI iOS app built with Clean Architecture + MVVM (Domain / Data / Presentation, `AppContainer` composition root) with Catalog (cache-first with expiry countdown), Notes (repository CRUD), Settings (key-value) and Inspector (counts, `removeExpired`, live storage log) tabs.
- Demo unit tests (Swift Testing) running the real repositories and view models on an in-memory store with an injected clock: cache-first, expiry, sorting, notes, settings, maintenance.
- CI job that builds and tests the demo app on the iOS Simulator.
- Demo app README (tabs, architecture, tests) and a Demo app section in the main README.

## [0.2.1] - 2026-09-25

### Added
- Engine contract suite run against both the SwiftData and in-memory engines, plus store-failure (`persistenceFailed`) and repository metadata tests.
- `scripts/coverage.sh`: runs tests with coverage, writes lcov/summary reports and fails below a 90% line-coverage floor (`COVERAGE_FLOOR` to override); CI runs it and posts the summary.

### Changed
- Internal: removed an unreachable `LocalStorageError` re-throw branch in the error mapper (no API change).

## [0.2.0] - 2026-09-25

### Added
- `CacheExpiration` (`.never`, `.seconds`, `.minutes`, `.hours`, `.days`, `.date`) on `save`, batch `save`, `set` and repository `save`; expired records read as absent and are purged lazily.
- `StorageMetadata` via `metadata(_:id:)` / `repository.metadata(id:)` — created/updated/expiry dates, payload size, `isExpired`.
- `removeExpired()` to reclaim space from expired records; returns the number deleted.
- Bulk `delete(_ values: [T])` and `repository.delete(_:)`.
- `StorageLogger` sink with `StorageLogLevel` (`none`, `error`, `info`, `debug`), `NoopStorageLogger` (default) and `OSLogStorageLogger`; configured via `LocalStorageConfiguration.logger` / `.logLevel`. Lines carry operation, key and byte count — never payloads or error descriptions.
- CI runs the test suite under ThreadSanitizer.
- Full public README (overview, architecture, every API area, expiration semantics, DTO evolution, errors, logging, testing, thread safety, SwiftNetworkKit integration, FAQ, versioning).
- `CONTRIBUTING.md` (branch naming, Conventional Commits, per-change changelog, release process), `SECURITY.md` and `ROADMAP.md`.

## [0.1.0] - 2026-09-25

### Added
- Design spec for v0.1–v0.2 (`docs/specs/2026-09-25-swiftlocalstorage-v0.2-design.md`).
- Swift package manifest (Swift 6 language mode; iOS 17, macOS 14, tvOS 17, watchOS 10, visionOS 1; zero dependencies).
- `StoredRecord` SwiftData envelope (schema V1 + migration plan), internal `StorageEngine` port, `SwiftDataEngine` (`@ModelActor`) and SPI `InMemoryStorageEngine`.
- `LocalStorageConfiguration` (`.inMemory`), pluggable `StorageEncoder` / `StorageDecoder` with JSON defaults, `LocalStorageNaming` for stable type names.
- `LocalStorage` façade: entity `save` (single + transactional batch), `fetch(_:id:)`, `fetch(_:)`, `count`, `exists`, `delete`, `deleteAll`; key-value `set` / `get` / `remove`; `removeAll`.
- `LocalStorageError` with a stable `Code` discriminant; missing records return `nil`, cancellation maps to `.cancelled`.
- `LocalRepository<Entity>` via `storage.repository(User.self)`.
- Swift Testing suites: entity CRUD, key-value, encoding round-trips, DTO evolution, key isolation, errors, cancellation, concurrency (100 parallel ops), repository.
- GitHub Actions CI: build with warnings as errors and run tests on macOS.
- README with installation, usage, key-value, repository, type naming and DTO evolution guidance.

[Unreleased]: https://github.com/ihusnainalii/SwiftLocalStorage/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/ihusnainalii/SwiftLocalStorage/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/ihusnainalii/SwiftLocalStorage/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/ihusnainalii/SwiftLocalStorage/compare/v0.2.3...v0.3.0
[0.2.3]: https://github.com/ihusnainalii/SwiftLocalStorage/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/ihusnainalii/SwiftLocalStorage/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/ihusnainalii/SwiftLocalStorage/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/ihusnainalii/SwiftLocalStorage/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ihusnainalii/SwiftLocalStorage/releases/tag/v0.1.0
