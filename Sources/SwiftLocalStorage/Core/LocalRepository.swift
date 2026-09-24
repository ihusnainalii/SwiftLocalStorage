/// A ``LocalStorage`` scoped to one entity type, so call sites drop the `T.self` argument.
///
/// ```swift
/// let users = storage.repository(User.self)
/// try await users.save(user)
/// let all = try await users.fetchAll()
/// ```
public struct LocalRepository<Entity: Identifiable & Codable & Sendable>: Sendable {
    public let storage: LocalStorage

    public init(storage: LocalStorage) {
        self.storage = storage
    }

    public func save(_ entity: Entity, expiration: CacheExpiration = .never) async throws {
        try await storage.save(entity, expiration: expiration)
    }

    public func save(_ entities: [Entity], expiration: CacheExpiration = .never) async throws {
        try await storage.save(entities, expiration: expiration)
    }

    public func fetch(id: Entity.ID) async throws -> Entity? {
        try await storage.fetch(Entity.self, id: id)
    }

    public func fetchAll() async throws -> [Entity] {
        try await storage.fetch(Entity.self)
    }

    public func count() async throws -> Int {
        try await storage.count(Entity.self)
    }

    public func exists(id: Entity.ID) async throws -> Bool {
        try await storage.exists(Entity.self, id: id)
    }

    public func metadata(id: Entity.ID) async throws -> StorageMetadata? {
        try await storage.metadata(Entity.self, id: id)
    }

    public func delete(id: Entity.ID) async throws {
        try await storage.delete(Entity.self, id: id)
    }

    public func delete(_ entities: [Entity]) async throws {
        try await storage.delete(entities)
    }

    public func deleteAll() async throws {
        try await storage.deleteAll(Entity.self)
    }
}

extension LocalStorage {
    /// A repository for `type` backed by this storage.
    public func repository<Entity: Identifiable & Codable & Sendable>(
        _ type: Entity.Type
    ) -> LocalRepository<Entity> {
        LocalRepository(storage: self)
    }
}
