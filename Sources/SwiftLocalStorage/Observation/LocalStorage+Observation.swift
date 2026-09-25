import Foundation

// MARK: - Observation

extension LocalStorage {
    /// Every change to stored values of `type` made through this storage, as it happens.
    ///
    /// ```swift
    /// for await change in storage.changes(of: User.self) { ... }
    /// ```
    ///
    /// Events arrive after each write commits. The stream buffers every event and ends when the
    /// consuming task is cancelled.
    public func changes<T: Identifiable & Codable & Sendable>(of type: T.Type) -> AsyncStream<StorageChange<T>> {
        changes(of: type, bufferingPolicy: .unbounded)
    }

    /// The current values of `type` (sorted and sliced by `options`), then the values again after
    /// every change to the type — a live query for SwiftUI:
    ///
    /// ```swift
    /// .task {
    ///     for try await users in storage.updates(of: User.self) { self.users = users }
    /// }
    /// ```
    ///
    /// Bursts of writes are coalesced into one refetch. If the consumer falls behind, it receives
    /// the newest result.
    public func updates<T: Identifiable & Codable & Sendable>(
        of type: T.Type, options: FetchOptions = .default
    ) -> AsyncThrowingStream<[T], any Error> {
        liveQuery(type) { try await self.fetch(type, options: options) }
    }

    /// The values of `type` matching every condition in `filters`, ordered and sliced like
    /// ``fetch(_:matching:orderedBy:options:)``, then again after every change to the type — a live
    /// query that filters, orders and slices in the store:
    ///
    /// ```swift
    /// for try await admins in storage.updates(of: User.self, matching: [.equals("role", "admin")]) { … }
    /// ```
    ///
    /// Bursts of writes are coalesced into one refetch, as for ``updates(of:options:)``.
    public func updates<T: Identifiable & Codable & Sendable & LocalStorageIndexed>(
        of type: T.Type, matching filters: [StorageFilter], orderedBy order: StorageIndexOrder? = nil,
        options: FetchOptions = .default
    ) -> AsyncThrowingStream<[T], any Error> {
        liveQuery(type) { try await self.fetch(type, matching: filters, orderedBy: order, options: options) }
    }

    /// Emits `fetch()` now, then once per burst of changes to `type`.
    private func liveQuery<T: Identifiable & Codable & Sendable>(
        _ type: T.Type, fetch: @escaping @Sendable () async throws -> [T]
    ) -> AsyncThrowingStream<[T], any Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            // Subscribe before the first fetch so no change can slip between the two.
            let changes = self.changes(of: type, bufferingPolicy: .bufferingNewest(1))
            let task = Task {
                do {
                    continuation.yield(try await fetch())
                    for await _ in changes {
                        continuation.yield(try await fetch())
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Every stored value of `type`, oldest first, loaded `batchSize` at a time as the loop
    /// advances, so large types are never fully in memory.
    public func all<T: Identifiable & Codable & Sendable>(_ type: T.Type, batchSize: Int = 100) -> StorageSequence<T> {
        precondition(batchSize >= 1, "batchSize must be at least 1")
        return StorageSequence(storage: self, batchSize: batchSize)
    }

    func changes<T: Identifiable & Codable & Sendable>(
        of type: T.Type, bufferingPolicy: AsyncStream<StorageChange<T>>.Continuation.BufferingPolicy
    ) -> AsyncStream<StorageChange<T>> {
        let typeName = StorageKey.typeName(of: type)
        let hub = hub
        return AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            let token = hub.subscribe(typeName: typeName) { raw in
                if let change = StorageChange<T>(raw) { continuation.yield(change) }
            }
            continuation.onTermination = { _ in hub.unsubscribe(typeName: typeName, token: token) }
        }
    }
}
