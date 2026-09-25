import Foundation

// Use cases: the app's business rules, each a small value type over repository protocols.

struct LoadCatalogUseCase: Sendable {
    let products: any ProductRepository
    let settings: any SettingsRepository

    /// Loads with the user's cache lifetime and returns products in the user's sort order.
    func callAsFunction(forceRefresh: Bool) async throws -> CatalogSnapshot {
        let preferences = try await settings.load()
        var snapshot = try await products.catalog(forceRefresh: forceRefresh, lifetime: preferences.cacheLifetime)
        snapshot.products = Self.sorted(snapshot.products, byPrice: preferences.sortByPrice)
        snapshot.isSortedByPrice = preferences.sortByPrice
        return snapshot
    }

    static func sorted(_ products: [Product], byPrice: Bool) -> [Product] {
        byPrice ? products.sorted { ($0.price, $0.id) < ($1.price, $1.id) } : products.sorted { $0.id < $1.id }
    }
}

struct ManageNotesUseCase: Sendable {
    let repository: any NoteRepository

    func list() async throws -> [Note] {
        Self.sorted(try await repository.all())
    }

    /// Live notes; sort each emission with ``sorted(_:)``.
    func observe() -> AsyncThrowingStream<[Note], any Error> {
        repository.observeAll()
    }

    /// Pinned first, then newest first.
    static func sorted(_ notes: [Note]) -> [Note] {
        notes.sorted { ($0.isPinned ? 0 : 1, $1.createdAt) < ($1.isPinned ? 0 : 1, $0.createdAt) }
    }

    enum ValidationError: Error, Equatable { case emptyTitle }

    func save(_ note: Note) async throws {
        var note = note
        note.title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.title.isEmpty else { throw ValidationError.emptyTitle }
        try await repository.save(note)
    }

    func togglePin(_ note: Note) async throws {
        var note = note
        note.isPinned.toggle()
        try await repository.save(note)
    }

    func delete(_ notes: [Note]) async throws {
        try await repository.delete(notes)
    }
}
