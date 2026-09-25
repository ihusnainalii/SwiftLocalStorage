import Foundation

// Repository contracts. Domain owns these; the Data layer implements them.

protocol ProductRepository: Sendable {
    /// Cache-first unless `forceRefresh`: live cached products win, otherwise fetch and cache.
    func catalog(forceRefresh: Bool, lifetime: AppSettings.CacheLifetime) async throws -> CatalogSnapshot
    func delete(_ products: [Product]) async throws
    func clearCache() async throws
}

protocol NoteRepository: Sendable {
    func all() async throws -> [Note]
    func save(_ note: Note) async throws
    func delete(_ notes: [Note]) async throws
}

protocol SettingsRepository: Sendable {
    func load() async throws -> AppSettings
    func save(_ settings: AppSettings) async throws
    /// Increments and returns the launch counter, remembering the previous launch date.
    func recordLaunch(at date: Date) async throws -> LaunchInfo
}

protocol MaintenanceRepository: Sendable {
    func stats() async throws -> StorageStats
    /// Returns how many records were removed.
    func removeExpired() async throws -> Int
    func removeAll() async throws
}
