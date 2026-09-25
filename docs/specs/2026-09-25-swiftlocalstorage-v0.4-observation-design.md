# SwiftLocalStorage v0.4 — Observation Design Spec

**Status:** Approved (roadmap 0.4) · **Date:** 2026-09-25 · **Target:** `v0.4.0` · **Branch:** `feat/observation`

Builds on the [v0.1–v0.2](2026-09-25-swiftlocalstorage-v0.2-design.md) and
[v0.3](2026-09-25-swiftlocalstorage-v0.3-queries-design.md) specs. Additive only.

## 1. Goal

React to storage changes without polling: a typed change feed, a live query that re-emits
results for SwiftUI, and a memory-bounded way to iterate large types.

## 2. Public API

```swift
// 1. Change feed for one entity type.
for await change in storage.changes(of: User.self) {
    switch change {
    case .inserted(let user), .updated(let user): ...
    case .deleted(let user): ...
    case .cleared: ...            // deleteAll(User.self) or removeAll()
    case .expired: ...            // removeExpired() purged records; refetch if needed
    }
}

// 2. Live query: current results now, then again after every change to the type.
.task {
    for try await users in storage.updates(of: User.self, options: FetchOptions(sort: .newestFirst)) {
        self.users = users
    }
}

// 3. Iterate a large type in batches without loading it all.
for try await user in storage.all(User.self, batchSize: 200) { ... }

// Repository equivalents
users.changes(); users.updates(options:); users.all(batchSize:)
```

### Types

```swift
public enum StorageChange<Entity: Sendable>: Sendable {
    case inserted(Entity)
    case updated(Entity)
    case deleted(Entity)
    case cleared
    case expired
}
extension StorageChange: Equatable where Entity: Equatable

public struct StorageSequence<Element>: AsyncSequence   // pull-based; Element: Identifiable & Codable & Sendable
```

## 3. Semantics

| Situation | Event(s) for observers of `T` |
|---|---|
| `save(value)` of a new ID / existing ID | `.inserted(value)` / `.updated(value)` |
| `save([T])` | one event per value, in array order, after the transaction commits |
| `delete(T.self, id:)`, `delete([T])` | `.deleted(stored value)` for each record that existed; nothing for missing IDs |
| `deleteAll(T.self)` | `.cleared` |
| `removeAll()` | `.cleared` to observers of every type |
| `removeExpired()` removing ≥ 1 record | `.expired` to observers of every type |
| Lazy purge on read, time passing | no event (expiry is time-based, not an action) |
| Failed or cancelled write | no event |
| Key-value `set` / `remove` | no event (out of scope for 0.4) |

- Events are delivered after the write commits, in the order writes complete.
- A storage instance only sees its own writes; two `LocalStorage` instances on one store do not
  notify each other.
- Streams end when the consuming task is cancelled or the iterator is released; the subscription
  is removed then.
- `changes(of:)` buffers every event. `updates(of:options:)` coalesces bursts: it keeps only the
  newest pending change, so it refetches once per burst, not once per write.
- `delete` only reads the stored value first when someone observes `T`, so unobserved deletes cost
  nothing extra.
- `all(_:batchSize:)` pulls `batchSize` records at a time (oldest first) as the loop advances.
  Records inserted meanwhile appear at the end; records deleted meanwhile may shift the window
  and cause a record to be skipped.

## 4. Architecture

- `ChangeHub` (internal, lock-protected): `typeName → [token: @Sendable (RawChange) -> Void]`.
  `publish(_:to:)` for one type, `publishToAll(_:)` for `cleared` / `expired`.
- `StorageEngine.upsert` returns the keys it inserted (vs. updated), so events are classified
  without an extra read.
- `LocalStorage` publishes from `save` / `delete` / `deleteAll` / `removeAll` / `removeExpired`
  after the engine call succeeds.

## 5. Out of scope

Key-value observation, cross-instance/cross-process notifications, SwiftData history tracking,
time-driven expiry events.

## 6. Testing

Both engines: inserted vs updated, batch order, deleted carries the stored value, missing-ID delete
emits nothing, cleared (type and global), expired, no event on failure, streams stop on
cancellation and unsubscribe, live query initial + re-emit + coalescing, `all` batches, sizes and
early exit, repository forwarding.

## 7. Release

`v0.4.0`. Demo: Notes tab driven by a live query (no manual reloads); Inspector shows a live
change feed.
