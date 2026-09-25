# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]


### Added
- Demo app `Examples/SwiftLocalStorageDemo`: a SwiftUI iOS app built with Clean Architecture + MVVM (Domain / Data / Presentation, `AppContainer` composition root) with Catalog (cache-first with expiry countdown), Notes (repository CRUD), Settings (key-value) and Inspector (counts, `removeExpired`, live storage log) tabs.
- Demo unit tests (Swift Testing) running the real repositories and view models on an in-memory store with an injected clock: cache-first, expiry, sorting, notes, settings, maintenance.

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

[Unreleased]: https://github.com/ihusnainalii/SwiftLocalStorage/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/ihusnainalii/SwiftLocalStorage/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/ihusnainalii/SwiftLocalStorage/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ihusnainalii/SwiftLocalStorage/releases/tag/v0.1.0
