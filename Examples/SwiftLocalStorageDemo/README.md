# SwiftLocalStorageDemo

A complete SwiftUI iOS app that demonstrates **SwiftLocalStorage**, built with **Clean
Architecture + MVVM**. It depends on the package by local path (`../..`), so it always builds
against the code in this repository.

| Tab | Demonstrates |
|---|---|
| **Catalog** | Cache-first loading of `Codable` DTOs from a simulated API: `save(_:expiration:)`, lazy expiry, `metadata(_:id:)` (cached time, live expiry countdown, payload size), **paging** with `page(_:page:pageSize:)` (4 per page, **Load more**), a **category filter** with `fetch(_:where:)`, bulk `delete`, `deleteAll`. Pull to refresh forces the network; **Load** serves the cache while it is live. |
| **Notes** | User data through `LocalRepository<Note>`: create, edit, pin and swipe-delete, rendered from a **live query** (`updates()`), so no screen ever reloads by hand. `Note` is on **stored version 2** (a required `priority`); notes saved by pre-0.5 builds are upgraded on first read by the `StorageMigration` in `Data/Repositories`. Nothing expires, and notes survive relaunches. |
| **Settings** | Key-value storage: one `Codable` struct under `"settings"` (appearance, sort order, cache lifetime) plus a launch counter and last-launch `Date`. |
| **Inspector** | A **live change feed** merged from `changes(of: Product.self)` and `changes(of: Note.self)` (running for the app's lifetime, so it records changes made in other tabs), counts that refresh on every change, `removeExpired()`, `removeAll()`, and the storage log from a custom `StorageLogger`, showing that payloads are never logged. |

## Run

Open **`SwiftLocalStorageDemo.xcodeproj`**, pick the **SwiftLocalStorageDemo** scheme and an iOS 17+
simulator, and Run (⌘R). Run the tests with ⌘U.

From the command line:

```bash
cd Examples/SwiftLocalStorageDemo
xcodebuild -project SwiftLocalStorageDemo.xcodeproj -scheme SwiftLocalStorageDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The project is generated from [`project.yml`](project.yml) with [XcodeGen](https://github.com/yonaskolb/XcodeGen).
After you add or move files, regenerate it with `xcodegen`. The generated `.xcodeproj` is committed,
so running the demo does not require XcodeGen.

## Architecture

```text
Presentation ──depends on──▶ Domain ◀──implements── Data
(SwiftUI views +             (entities,             (repositories over
 @Observable view models)     repository protocols,  LocalStorage + a
                              use cases)             simulated API)
                    ▲
                    └── App/AppContainer: the composition root that wires concrete types
```

```text
SwiftLocalStorageDemo/
├── App/            SwiftLocalStorageDemoApp (entry point), AppContainer (dependency injection)
├── Domain/         Entities · Repositories (protocols) · UseCases      ← Foundation only
├── Data/           Remote/ProductAPI · Repositories/LocalStorageRepositories · Logging/StorageLogFeed
└── Presentation/   Root · Catalog · Notes · Settings · Inspector (View + ViewModel each)
```

- **Domain imports only Foundation.** Entities are plain `Codable` structs, the same DTOs that get
  persisted. No `@Model` mirrors exist anywhere.
- **Data is the only layer that imports SwiftLocalStorage.** It pins stable storage names with
  `LocalStorageNaming` and maps `CacheLifetime` to `CacheExpiration`.
- **The cache policy lives in `CachedProductRepository`:** serve live cached products, otherwise
  fetch, replace the cache, and save with the user's lifetime.
- **View models** depend on use cases or repository protocols, never on concrete storage.

## Tests

`SwiftLocalStorageDemoTests` (Swift Testing) runs the real repositories and view models against
`LocalStorage(configuration: .inMemory, now:)`, the package's SPI initializer with an injectable
clock, so cache expiry is tested deterministically without waiting:

- cache-first: network → cache hit → forced refresh
- expiry after the configured lifetime; the "never" lifetime keeps the cache indefinitely
- paging 4 at a time with no extra network calls, category filter
- sort preference, delete, clear cache
- notes rendered from a live query: saves, pins, deletes and writes from elsewhere appear without reloads
- a note stored by a pre-0.5 build migrates from v1 to v2 on read
- the Inspector's live change feed and count refresh
- settings round-trip through key-value storage, launch counting
- `removeExpired()` and delete-all via the Inspector view model

## Troubleshooting

If Xcode reports a missing package, use **File ▸ Packages ▸ Reset Package Caches**.
