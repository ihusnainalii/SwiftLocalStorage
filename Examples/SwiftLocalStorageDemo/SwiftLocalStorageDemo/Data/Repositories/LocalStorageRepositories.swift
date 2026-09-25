import Foundation
import SwiftLocalStorage

// The only layer that imports SwiftLocalStorage. Domain entities are persisted as-is — no
// `@Model` mirrors — with stable storage names pinned here, out of the Domain layer.

extension Product: LocalStorageNaming {
    static var storageTypeName: String { "Product" }
}

extension Note: LocalStorageNaming {
    static var storageTypeName: String { "Note" }
}

extension AppSettings.CacheLifetime {
    var expiration: CacheExpiration {
        seconds.map { .seconds(TimeInterval($0)) } ?? .never
    }
}

/// Cache-first products: `LocalStorage` in front of the remote API.
struct CachedProductRepository: ProductRepository {
    let storage: LocalStorage
    let api: any ProductAPI

    func catalog(forceRefresh: Bool, lifetime: AppSettings.CacheLifetime) async throws -> CatalogSnapshot {
        var source = CatalogSource.cache
        var products = forceRefresh ? [] : try await storage.fetch(Product.self)
        if products.isEmpty {
            products = try await api.fetchProducts()
            try await storage.deleteAll(Product.self)
            try await storage.save(products, expiration: lifetime.expiration)
            source = .network
        }
        var metadata: StorageMetadata?
        if let first = products.first {
            metadata = try await storage.metadata(Product.self, id: first.id)
        }
        return CatalogSnapshot(
            products: products, source: source,
            cachedAt: metadata?.createdAt, expiresAt: metadata?.expiresAt,
            payloadBytesPerItem: metadata?.size, networkRequestCount: await api.requestCount
        )
    }

    func cachedPage(_ page: Int, size: Int, category: String?) async throws -> ProductPage {
        guard let category else {
            let result = try await storage.page(Product.self, page: page, pageSize: size)
            return ProductPage(
                products: result.items, page: page, totalCount: result.totalCount, hasNextPage: result.hasNextPage
            )
        }
        // Category lives inside the DTO, so filter with a closure; slice the filtered result.
        let matching = try await storage.fetch(Product.self, where: { $0.category == category })
        let items = Array(matching.dropFirst((page - 1) * size).prefix(size))
        return ProductPage(
            products: items, page: page, totalCount: matching.count, hasNextPage: page * size < matching.count
        )
    }

    func delete(_ products: [Product]) async throws {
        try await storage.delete(products)
    }

    func clearCache() async throws {
        try await storage.deleteAll(Product.self)
    }
}

/// Notes through a typed `LocalRepository`; user data never expires.
struct LocalNoteRepository: NoteRepository {
    let notes: LocalRepository<Note>

    init(storage: LocalStorage) {
        notes = storage.repository(Note.self)
    }

    func all() async throws -> [Note] { try await notes.fetchAll() }
    func observeAll() -> AsyncThrowingStream<[Note], any Error> { notes.updates() }
    func save(_ note: Note) async throws { try await notes.save(note) }
    func delete(_ items: [Note]) async throws { try await notes.delete(items) }
}

/// Preferences and launch bookkeeping in key-value storage.
struct LocalSettingsRepository: SettingsRepository {
    let storage: LocalStorage

    private enum Key {
        static let settings = "settings"
        static let launchCount = "launchCount"
        static let lastLaunch = "lastLaunch"
    }

    func load() async throws -> AppSettings {
        try await storage.get(AppSettings.self, forKey: Key.settings) ?? AppSettings()
    }

    func save(_ settings: AppSettings) async throws {
        try await storage.set(settings, forKey: Key.settings)
    }

    func recordLaunch(at date: Date) async throws -> LaunchInfo {
        let previous = try await storage.get(Date.self, forKey: Key.lastLaunch)
        let count = (try await storage.get(Int.self, forKey: Key.launchCount) ?? 0) + 1
        try await storage.set(count, forKey: Key.launchCount)
        try await storage.set(date, forKey: Key.lastLaunch)
        return LaunchInfo(count: count, previousLaunch: previous)
    }
}

struct LocalMaintenanceRepository: MaintenanceRepository {
    let storage: LocalStorage

    func stats() async throws -> StorageStats {
        StorageStats(liveProducts: try await storage.count(Product.self), notes: try await storage.count(Note.self))
    }

    func removeExpired() async throws -> Int {
        try await storage.removeExpired()
    }

    func removeAll() async throws {
        try await storage.removeAll()
    }

    /// Merges the Product and Note change feeds into one activity stream.
    func activity() -> AsyncStream<StorageActivity> {
        let products = storage.changes(of: Product.self)
        let notes = storage.changes(of: Note.self)
        return AsyncStream { continuation in
            let productTask = Task {
                for await change in products {
                    continuation.yield(StorageActivity(entity: "Product", change: change) { $0.name })
                }
            }
            let noteTask = Task {
                for await change in notes {
                    continuation.yield(StorageActivity(entity: "Note", change: change) { $0.title })
                }
            }
            continuation.onTermination = { _ in
                productTask.cancel()
                noteTask.cancel()
            }
        }
    }
}

extension StorageActivity {
    init<T>(entity: String, change: StorageChange<T>, name: (T) -> String) {
        let (kind, value): (Kind, T?) = switch change {
        case .inserted(let value): (.inserted, value)
        case .updated(let value): (.updated, value)
        case .deleted(let value): (.deleted, value)
        case .cleared: (.cleared, nil)
        case .expired: (.expired, nil)
        }
        self.init(date: .now, entity: entity, kind: kind, detail: value.map(name))
    }
}
