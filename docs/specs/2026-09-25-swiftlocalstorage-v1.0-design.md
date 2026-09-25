# SwiftLocalStorage 1.0 — API Freeze Design Spec

**Status:** Approved (roadmap 1.0) · **Date:** 2026-09-25 · **Target:** `v1.0.0` · **Branch:** `feat/v1.0`

Builds on the earlier specs (v0.2 – v0.6 in this folder). No behaviour change: 1.0 promises that
the 0.6 API stays source-compatible for every 1.x release, and adds the documentation, benchmarks
and CI needed to keep that promise.

## 1. Goal

Declare the public API stable. Every later 1.x release is additive; anything that breaks source
compatibility waits for 2.0.

## 2. API freeze

The public surface is exactly what 0.6.0 exposes: `LocalStorage`, `LocalRepository`,
`LocalStorageConfiguration`, `LocalStorageError`, `CacheExpiration`, `StorageMetadata`,
`FetchOptions` / `StorageSort` / `StoragePage`, `StorageChange` / `StorageSequence`,
`LocalStorageVersioned` / `StorageMigration` / `StorageMigrationError`, `LocalStorageIndexed` /
`StorageIndex` / `StorageIndexNumber` / `StorageFilter` / `StorageIndexOrder`, `LocalStorageNaming`,
`StorageEncoder` / `StorageDecoder` and the JSON coders, `StorageLogger` / `StorageLogLevel` and
the two loggers.

| Question | Decision |
|---|---|
| Public `StorageEngine`? | **No.** The engine protocol carries index slots, rewrite and sequencing details that would freeze the storage format. It stays internal; alternative engines are a 2.0 candidate. |
| `@_spi(SwiftLocalStorageTesting)` (in-memory engine, clock injection) | Not covered by the promise; may change in a minor release. |
| New enum cases | Allowed in minor releases only for the error enums (`LocalStorageError`, `LocalStorageError.Code`, `StorageMigrationError`); callers handle them with a `default` branch. Every other public enum is frozen for 1.x, because without library evolution a new case breaks exhaustive switches. |
| On-disk format | Store schema migrations stay automatic and forward-only; a 1.x store opens in every later 1.x. |
| Minimum platforms and Swift tools version | Raised only in a minor release, never in a patch. |

**Enforcement:** CI runs `swift package diagnose-api-breaking-changes <latest tag>` on every pull
request, so an accidental break fails before merge.

## 3. Documentation catalog

`Sources/SwiftLocalStorage/SwiftLocalStorage.docc/`:

- `SwiftLocalStorage.md`: landing page with every public type grouped into topics.
- Articles: *Getting Started*, *Querying*, *Observing Changes*, *Migrating Stored DTOs*,
  *Indexed Fields*, *Testing*, *API Stability*.

The existing CI `docs` job (`xcodebuild docbuild`) builds the catalog, and the release workflow
attaches a static-hosting archive to each GitHub release.

## 4. Benchmarks

A `SwiftLocalStorageBenchmarks` executable target that uses only the public API and has no
dependencies. It is not a product, so apps never link it.

```bash
swift run -c release SwiftLocalStorageBenchmarks
```

It prints a Markdown table (median of 5 runs, against an on-disk store named
`SwiftLocalStorageBenchmarks` that it empties before and after) for:

- `save` batch, `fetch(options:)` all and `deleteAll` at 1, 100 and 1,000 records
- `save` + `fetch(id:)` of a 1 MB and a 10 MB payload
- filtering 1,000 records by an index (`matching:`) versus by a closure (`where:`)

The results are published in `docs/benchmarks.md` and summarised in the README. CI builds the
target on every run but does not time it, because shared runners are too noisy to gate on.

## 5. CI (multi-platform)

CI already covers lint, a `-warnings-as-errors` build, tests with a coverage floor, the thread and
address sanitizers, iOS (library and demo), tvOS / watchOS / visionOS builds and DocC. 1.0 adds
the API-breakage job (§2) and builds the benchmarks target in release mode.

## 6. Out of scope

A public engine protocol, encryption at rest, and a cached-repository companion package.

## 7. Release

`v1.0.0`: README (stability, benchmarks), ROADMAP, CHANGELOG, `version.txt` and the
release-please manifest go to `1.0.0`.
