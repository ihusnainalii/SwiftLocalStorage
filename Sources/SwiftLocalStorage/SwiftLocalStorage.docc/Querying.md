# Querying

Sort, limit and page in the store, or filter on any DTO field.

## Sort and slice

``FetchOptions`` sorts and slices inside SQLite, so only the returned rows are decoded:

```swift
let latest = try await storage.fetch(User.self, options: FetchOptions(sort: .newestFirst, limit: 20))
```

``StorageSort`` orders by insertion or by last update; ties keep insertion order.

## Pages

``LocalStorage/page(_:page:pageSize:sort:)`` returns a 1-based ``StoragePage`` with the total
count, so a list knows when to stop loading:

```swift
let page = try await storage.page(User.self, page: 1, pageSize: 50)
if page.hasNextPage { /* load page 2 */ }
```

## Filter on any field

A closure filter works on any property, but decodes every live value of the type first:

```swift
let admins = try await storage.fetch(User.self, where: { $0.role == .admin })
```

For large types or hot queries, declare the field as an index and filter in the store instead
(see <doc:IndexedFields>).

## Iterate in batches

``LocalStorage/all(_:batchSize:)`` returns a ``StorageSequence`` that fetches one batch at a time
as the loop advances:

```swift
for try await user in storage.all(User.self, batchSize: 200) {
    process(user)
}
```
