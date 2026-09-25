# SwiftLocalStorage v0.3 — Queries Design Spec

**Status:** Approved (roadmap 0.3) · **Date:** 2026-09-25 · **Target:** `v0.3.0` · **Branch:** `feat/queries`

Builds on the [v0.1–v0.2 spec](2026-09-25-swiftlocalstorage-v0.2-design.md). Additive only: no
existing signature changes.

## 1. Goal

Let callers read a *slice* of a type instead of everything: sort, limit/offset, pages with
totals, and filtering on DTO fields — without a query language that could lock the API in.

## 2. Public API

```swift
// Sort + slice — pushed down to SwiftData (only the requested rows are read and decoded).
let latest = try await storage.fetch(User.self, options: FetchOptions(sort: .newestFirst, limit: 20))
let next   = try await storage.fetch(User.self, options: FetchOptions(limit: 20, offset: 20))

// Pages (1-based, like SwiftNetworkKit's PaginatedEndpoint).
let page: StoragePage<User> = try await storage.page(User.self, page: 1, pageSize: 50)
page.items; page.page; page.pageSize; page.totalCount; page.totalPages; page.hasNextPage

// Filter on any DTO field with a plain Swift closure; options apply after filtering.
let admins = try await storage.fetch(User.self, where: { $0.role == .admin },
                                     options: FetchOptions(sort: .recentlyUpdated, limit: 10))

// Repository equivalents
try await users.fetchAll(options:)
try await users.fetch(where:options:)
try await users.page(_:pageSize:)
```

### Types

```swift
public struct FetchOptions: Sendable, Hashable {
    public var sort: StorageSort       // default .oldestFirst (the existing fetch(_:) order)
    public var limit: Int?             // nil = no limit; must be >= 0
    public var offset: Int             // default 0; must be >= 0
    public static let `default`: FetchOptions
}

public enum StorageSort: Sendable, Hashable, CaseIterable {
    case oldestFirst            // createdAt ↑, then insertion sequence ↑
    case newestFirst            // createdAt ↓, then insertion sequence ↓
    case recentlyUpdated        // updatedAt ↓, then insertion sequence ↓
    case leastRecentlyUpdated   // updatedAt ↑, then insertion sequence ↑
}

public struct StoragePage<Element: Sendable>: Sendable {
    public let items: [Element]
    public let page: Int          // 1-based
    public let pageSize: Int
    public let totalCount: Int    // live records of the type
    public var totalPages: Int    // ceil(totalCount / pageSize), 0 when empty
    public var hasNextPage: Bool  // page < totalPages
}
extension StoragePage: Equatable where Element: Equatable
```

## 3. Semantics

| Situation | Behaviour |
|---|---|
| Expired records | never counted, sorted or returned; purged lazily as before |
| `limit: 0` | returns `[]` |
| `offset` ≥ live count | returns `[]` |
| Negative `limit` / `offset`, `page < 1`, `pageSize < 1` | precondition failure (programmer error), matching `Array` |
| Page past the end | `items == []`, `totalCount`/`totalPages` still correct, `hasNextPage == false` |
| Ties in the sort key | broken by insertion sequence, so order is total and stable |
| `fetch(_:where:options:)` | loads and decodes every live record of the type, filters, then sorts/slices in memory |

`fetch(_:)` keeps its behaviour and is now `fetch(_:options: .default)`.

### Why a closure filter and not a query DSL

DTO fields live inside an encoded payload, so SwiftData cannot index or query them. A closure is
type-checked, refactor-safe and supports every Swift expression; its cost (decode all live records
of the type) is documented. A stored-field index / pushed-down predicate can be added later without
breaking this API.

## 4. Architecture

`StorageEngine.records(kind:typeName:now:)` gains `sort`, `limit` and `offset`:

- **SwiftDataEngine:** purges the type's expired rows with one predicate delete, then fetches live
  rows with `FetchDescriptor.sortBy` (sort key + `sequence`), `fetchLimit`, `fetchOffset`.
- **InMemoryStorageEngine:** same order (sort key, then insertion sequence) and slicing.

The engine contract suite runs every new test against both engines.

## 5. Out of scope

Stored-field indexes, compound/predicate DSL, cursors, `AsyncSequence` streaming (0.4),
observation (0.4).

## 6. Testing

Both engines: each `StorageSort` order incl. ties; limit/offset edges (0, past end); expired rows
excluded from slices and totals; page math (exact multiple, remainder, empty store, past the end);
filter + options; repository forwarding; preconditions documented, not tested (they trap).

## 7. Release

`v0.3.0` (new public API, minor bump). Demo app: Catalog gains sort + paging via the new API.
