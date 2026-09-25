import Foundation

// Domain entities: plain value types. The Domain layer imports only Foundation — it knows nothing
// about SwiftLocalStorage, SwiftData or the network.

struct Product: Codable, Identifiable, Sendable, Hashable {
    let id: Int
    var name: String
    var category: String
    var price: Double
    var symbol: String
}

struct Note: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var title: String
    var body: String
    var isPinned: Bool
    var createdAt: Date

    init(id: UUID = UUID(), title: String = "", body: String = "", isPinned: Bool = false, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.body = body
        self.isPinned = isPinned
        self.createdAt = createdAt
    }
}

struct AppSettings: Codable, Sendable, Equatable {
    enum Appearance: String, Codable, Sendable, CaseIterable, Identifiable {
        case system, light, dark
        var id: Self { self }
    }

    /// How long fetched catalog data stays fresh. `seconds == nil` means it never expires.
    enum CacheLifetime: Int, Codable, Sendable, CaseIterable, Identifiable {
        case fifteenSeconds = 15, oneMinute = 60, fiveMinutes = 300, never = 0
        var id: Self { self }
        var seconds: Int? { self == .never ? nil : rawValue }
    }

    var appearance: Appearance = .system
    var cacheLifetime: CacheLifetime = .oneMinute
    var sortByPrice = false
}

/// Where a catalog result came from.
enum CatalogSource: Sendable, Equatable {
    case cache, network
}

/// A catalog result plus the cache bookkeeping the UI shows.
struct CatalogSnapshot: Sendable, Equatable {
    var products: [Product]
    var source: CatalogSource
    var cachedAt: Date?
    var expiresAt: Date?
    var payloadBytesPerItem: Int?
    var networkRequestCount: Int
    /// Whether `products` (and pages shown from them) follow the "sort by price" preference.
    var isSortedByPrice = false
}

/// One page of cached products.
struct ProductPage: Sendable, Equatable {
    var products: [Product]
    var page: Int
    var totalCount: Int
    var hasNextPage: Bool
}

/// Launch bookkeeping, persisted as simple key-value entries.
struct LaunchInfo: Sendable, Equatable {
    var count: Int
    var previousLaunch: Date?
}

/// What is currently stored.
struct StorageStats: Sendable, Equatable {
    var liveProducts: Int
    var notes: Int
}
