# Observing Changes

React to writes with a typed change feed or a live query.

## Change feed

``LocalStorage/changes(of:)`` yields a ``StorageChange`` for every write to a type made through
this storage instance:

```swift
for await change in storage.changes(of: User.self) {
    switch change {
    case .inserted(let user), .updated(let user): show(user)
    case .deleted(let user): hide(user)
    case .cleared, .expired: reload()
    }
}
```

## Live query

``LocalStorage/updates(of:options:)`` yields the current results immediately, then again after
each burst of writes, coalesced into a single refetch:

```swift
.task {
    do {
        for try await users in storage.updates(of: User.self, options: FetchOptions(sort: .newestFirst)) {
            self.users = users
        }
    } catch {
        self.error = error
    }
}
```

Both streams end when the consuming task is cancelled.
