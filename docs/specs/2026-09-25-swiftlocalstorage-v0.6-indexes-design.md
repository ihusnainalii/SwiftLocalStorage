# SwiftLocalStorage v0.6 — Indexed Fields Design Spec

**Status:** Approved (roadmap 0.6) · **Date:** 2026-09-25 · **Target:** `v0.6.0` · **Branch:** `feat/indexed-fields`

Builds on the earlier specs (v0.2 – v0.5 in this folder). Additive for callers; the store
schema moves to V3 through a lightweight migration.

## 1. Goal

`fetch(_:where:)` (0.3) filters in memory after decoding every record of a type. For hot queries
("admins", "products in a category", "sorted by price"), let a type declare a few **indexed
fields** whose values are stored next to the payload, so SwiftData filters, sorts, counts and pages
on them without decoding anything it doesn't return.

## 2. Public API

```swift
// 1. Declare up to three indexes (closures, so computed values like lowercased emails work).
extension User: LocalStorageIndexed {
    static var storageIndexes: [StorageIndex<User>] {
        [
            .string("role") { $0.role.rawValue },
            .number("age") { $0.age },               // Int, Double, Date or Bool
            .number("lastSeen") { $0.lastSeen },    // optional values are allowed (nil = not indexed)
        ]
    }
}

// 2. Query: conditions are ANDed; everything runs in the store.
let admins = try await storage.fetch(
    User.self,
    matching: [.equals("role", "admin"), .atLeast("age", 18)],
    orderedBy: .descending("lastSeen"),
    options: FetchOptions(limit: 20)
)
let count = try await storage.count(User.self, matching: [.equals("role", "admin")])
let page  = try await storage.page(User.self, matching: [.between("age", 18...30)], orderedBy: .ascending("age"),
                                   page: 1, pageSize: 50)

// Repository equivalents when Entity: LocalStorageIndexed
users.fetch(matching:orderedBy:options:); users.count(matching:); users.page(matching:orderedBy:page:pageSize:)
```

### Types

```swift
public protocol LocalStorageIndexed {
    static var storageIndexes: [StorageIndex<Self>] { get }         // at most 3, unique names
}

public protocol StorageIndexNumber: Comparable, Sendable {           // Int, Double, Date, Bool conform
    var storageIndexValue: Double { get }
}

public struct StorageIndex<Root>: Sendable {
    public let name: String
    public static func string(_ name: String, _ value: @escaping @Sendable (Root) -> String?) -> Self
    public static func number<V: StorageIndexNumber>(_ name: String, _ value: @escaping @Sendable (Root) -> V?) -> Self
}

public struct StorageFilter: Sendable, Hashable {
    public static func equals(_ name: String, _ value: String) -> Self
    public static func equals<V: StorageIndexNumber>(_ name: String, _ value: V) -> Self
    public static func atLeast<V: StorageIndexNumber>(_ name: String, _ value: V) -> Self
    public static func atMost<V: StorageIndexNumber>(_ name: String, _ value: V) -> Self
    public static func between<V: StorageIndexNumber>(_ name: String, _ range: ClosedRange<V>) -> Self
}

public enum StorageIndexOrder: Sendable, Hashable {
    case ascending(String), descending(String)
}
```

## 3. Semantics

| Situation | Behaviour |
|---|---|
| `save` of an indexed type | index values computed from the value and stored with it |
| Several conditions | ANDed; two conditions on one number index narrow its range |
| Record whose index value is `nil` | never matches a condition on that index; sorts first ascending, last descending |
| `orderedBy` | replaces `options.sort`; ties broken by insertion order; `options.limit` / `offset` still apply |
| Expired records | excluded from results, counts and page totals, as everywhere |
| Unknown index name, string filter on a number index (or vice versa), > 3 indexes, duplicate names | precondition failure (programmer error) |
| Index declaration changed, or records saved before the type was indexed | detected by an index signature stored per record; the first indexed query of the type per `LocalStorage` instance re-indexes stale records (decode → compute → store), then runs |
| DTO migration write-back (0.5) | recomputes the index values of the upgraded record |
| Non-indexed types, key-value entries | unaffected |

## 4. Architecture

- **Schema V3** adds nullable columns `s0 s1 s2: String?`, `n0 n1 n2: Double?` and
  `indexSignature: String?` to `StoredRecord`, via a lightweight V2 → V3 stage. Each declared index
  takes the next slot; string indexes use `sN`, number indexes `nN`.
- The signature is `name:kind` pairs joined in slot order (e.g. `role:s|age:n|lastSeen:n`).
- `RecordWrite` / `rewrite` carry optional index values. New engine calls:
  `staleIndexKeys(typeName:signature:)` and `setIndex(key:values:)`.
- `records` / `count` take an internal `IndexQuery` (per-slot string equality, per-slot number
  bounds, optional slot ordering). SwiftDataEngine turns it into one `#Predicate` with captured
  flags and `SortDescriptor`s; the in-memory engine evaluates the same rules in Swift.

## 5. Out of scope

OR / NOT conditions, string prefix/contains, more than 3 indexes, index-backed live queries.

## 6. Testing

Both engines: equality (string, Int, Double, Bool, Date), ranges, ANDed conditions, nil values,
ascending/descending order with ties and nils, limit/offset, count and page totals with filters,
expired exclusion, auto re-index of pre-index records and after a declaration change, index update
on DTO migration; schema V2 → V3 on-disk migration.

## 7. Release

`v0.6.0`. Demo: the Catalog's category filter and "sort by price" run on indexes (`category`,
`price`), paging through filtered, price-sorted results in the store.
