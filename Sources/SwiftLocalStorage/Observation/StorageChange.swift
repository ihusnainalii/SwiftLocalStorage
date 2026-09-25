import Foundation

/// One change to stored values of an entity type, delivered by ``LocalStorage/changes(of:)``.
public enum StorageChange<Entity: Sendable>: Sendable {
    /// A value with a new ID was saved.
    case inserted(Entity)
    /// A value replaced the stored value with the same ID.
    case updated(Entity)
    /// A stored value was deleted; carries the value as it was stored.
    case deleted(Entity)
    /// Every value of the type was deleted (`deleteAll(_:)` or `removeAll()`).
    case cleared
    /// `removeExpired()` purged expired records; refetch if you show this type.
    case expired
}

extension StorageChange: Equatable where Entity: Equatable {}

extension StorageChange {
    init?(_ raw: RawChange) {
        switch raw {
        case .inserted(let value):
            guard let value = value as? Entity else { return nil }
            self = .inserted(value)
        case .updated(let value):
            guard let value = value as? Entity else { return nil }
            self = .updated(value)
        case .deleted(let value):
            guard let value = value as? Entity else { return nil }
            self = .deleted(value)
        case .cleared: self = .cleared
        case .expired: self = .expired
        }
    }
}

/// A type-erased change, as published through ``ChangeHub``.
enum RawChange: Sendable {
    case inserted(any Sendable)
    case updated(any Sendable)
    case deleted(any Sendable)
    case cleared
    case expired
}

/// Fans changes out to observers, keyed by storage type name.
final class ChangeHub: @unchecked Sendable {
    typealias Handler = @Sendable (RawChange) -> Void

    // ponytail: one lock for all types; per-type locks if observer counts get large.
    private let lock = NSLock()
    private var observers: [String: [UUID: Handler]] = [:]

    func subscribe(typeName: String, _ handler: @escaping Handler) -> UUID {
        let token = UUID()
        lock.withLock { observers[typeName, default: [:]][token] = handler }
        return token
    }

    func unsubscribe(typeName: String, token: UUID) {
        lock.withLock {
            observers[typeName]?[token] = nil
            if observers[typeName]?.isEmpty == true { observers[typeName] = nil }
        }
    }

    func hasObservers(_ typeName: String) -> Bool {
        lock.withLock { observers[typeName] != nil }
    }

    /// Delivers `changes` in order to every observer of `typeName`.
    func publish(_ changes: [RawChange], to typeName: String) {
        guard !changes.isEmpty else { return }
        // Handlers run outside the lock so they can subscribe/unsubscribe freely.
        let handlers = lock.withLock { observers[typeName].map { Array($0.values) } ?? [] }
        for change in changes {
            handlers.forEach { $0(change) }
        }
    }

    /// Delivers `change` to observers of every type.
    func publishToAll(_ change: RawChange) {
        let handlers = lock.withLock { observers.values.flatMap(\.values) }
        handlers.forEach { $0(change) }
    }
}
