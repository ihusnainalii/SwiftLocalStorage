# Indexed Fields

Filter, order, count and page on DTO fields inside the store.

## Declare indexes

Conform to ``LocalStorageIndexed`` and declare up to three indexes. Each one is a closure, so
computed values work:

```swift
extension User: LocalStorageIndexed {
    static var storageIndexes: [StorageIndex<User>] {
        [
            .string("role") { $0.role.rawValue },
            .number("age") { $0.age },
            .number("lastSeen") { $0.lastSeen },
        ]
    }
}
```

Number indexes accept any ``StorageIndexNumber``: `Int`, `Int32`, `Int64`, `UInt`, `Double`,
`Float`, `Date` and `Bool`. A `nil` value means the record isn't indexed on that field.

## Query

Conditions are ANDed; everything runs in the store and only returned rows are decoded:

```swift
let admins = try await storage.fetch(
    User.self,
    matching: [.equals("role", "admin"), .atLeast("age", 18)],
    orderedBy: .descending("lastSeen"),
    options: FetchOptions(limit: 20)
)
let count = try await storage.count(User.self, matching: [.equals("role", "admin")])
let page  = try await storage.page(User.self, matching: [.between("age", 18...30)],
                                   orderedBy: .ascending("age"), page: 1, pageSize: 50)
```

String indexes also take a prefix or a list of values:

```swift
let staff = try await storage.fetch(User.self, matching: [.hasPrefix("email", "ops."), .oneOf("role", ["admin", "editor"])])
```

Several conditions on one string index intersect, so two different `equals` match nothing.
Records without a value never match a condition on that index. They sort first when ascending
and last when descending.

## Live indexed queries

``LocalStorage/updates(of:matching:orderedBy:options:)`` emits the matching values now, then reruns
the query in the store after each burst of writes to the type:

```swift
for try await admins in storage.updates(of: User.self, matching: [.equals("role", "admin")]) {
    self.admins = admins
}
```

## Changing the declaration

Each record stores a signature of the declaration it was indexed with. After you add, remove or
reorder indexes, the first indexed query of the type re-indexes the stale records, then runs.
