import Foundation
import Testing
@_spi(SwiftLocalStorageTesting) import SwiftLocalStorage
@testable import SwiftLocalStorageDemo

/// A controllable wall clock, so cache expiry is tested without waiting.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSinceReferenceDate: 800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(by seconds: TimeInterval) { lock.withLock { current += seconds } }
}

/// Real repositories over an in-memory store with an injected clock and an instant fake API.
@MainActor
struct Harness {
    let clock = TestClock()
    let storage: LocalStorage
    let api = FakeProductAPI(latency: .zero)

    init() throws {
        let clock = self.clock
        storage = try LocalStorage(configuration: .inMemory, now: { clock.now })
    }

    var products: CachedProductRepository { CachedProductRepository(storage: storage, api: api) }
    var settings: LocalSettingsRepository { LocalSettingsRepository(storage: storage) }
    var notes: LocalNoteRepository { LocalNoteRepository(storage: storage) }
    var maintenance: LocalMaintenanceRepository { LocalMaintenanceRepository(storage: storage) }

    func catalogViewModel() -> CatalogViewModel {
        CatalogViewModel(loadCatalog: LoadCatalogUseCase(products: products, settings: settings), repository: products)
    }
}

@MainActor
@Suite("Catalog: cache-first")
struct CatalogTests {

    @Test("first load hits the network, the next is a cache hit, refresh hits the network again")
    func cacheFirst() async throws {
        let harness = try Harness()
        let viewModel = harness.catalogViewModel()

        await viewModel.load()
        #expect(viewModel.snapshot?.source == .network)
        #expect(viewModel.products.count == CatalogViewModel.pageSize)
        #expect(viewModel.totalCount == 10)

        await viewModel.load()
        #expect(viewModel.snapshot?.source == .cache)
        #expect(await harness.api.requestCount == 1)

        await viewModel.load(forceRefresh: true)
        #expect(viewModel.snapshot?.source == .network)
        #expect(await harness.api.requestCount == 2)
    }

    @Test("an expired cache is refetched")
    func expiry() async throws {
        let harness = try Harness()
        let viewModel = harness.catalogViewModel()
        let lifetime = TimeInterval(try #require(AppSettings().cacheLifetime.seconds))
        await viewModel.load()
        #expect(viewModel.snapshot?.expiresAt == harness.clock.now + lifetime)

        harness.clock.advance(by: lifetime + 1)
        await viewModel.load()

        #expect(viewModel.snapshot?.source == .network)
        #expect(await harness.api.requestCount == 2)
    }

    @Test("\"never\" lifetime keeps the cache indefinitely")
    func neverExpires() async throws {
        let harness = try Harness()
        try await harness.settings.save(AppSettings(cacheLifetime: .never))
        let viewModel = harness.catalogViewModel()
        await viewModel.load()

        harness.clock.advance(by: 86_400 * 365)
        await viewModel.load()

        #expect(viewModel.snapshot?.source == .cache)
        #expect(viewModel.snapshot?.expiresAt == nil)
    }

    @Test("sort preference is applied")
    func sorting() async throws {
        let harness = try Harness()
        try await harness.settings.save(AppSettings(sortByPrice: true))
        let viewModel = harness.catalogViewModel()

        await viewModel.load()

        let prices = viewModel.products.map(\.price)
        #expect(prices == prices.sorted())
    }

    @Test("pages load 4 at a time until the end")
    func paging() async throws {
        let harness = try Harness()
        let viewModel = harness.catalogViewModel()
        await viewModel.load()
        #expect(viewModel.hasNextPage)

        await viewModel.loadNextPage()
        #expect(viewModel.products.count == 8)
        await viewModel.loadNextPage()
        #expect(viewModel.products.map(\.id) == Array(1...10))
        #expect(!viewModel.hasNextPage)

        await viewModel.loadNextPage()                             // no-op at the end
        #expect(viewModel.products.count == 10)
        #expect(await harness.api.requestCount == 1)               // paging never hits the network
    }

    @Test("category filter narrows the pages")
    func categoryFilter() async throws {
        let harness = try Harness()
        let viewModel = harness.catalogViewModel()
        await viewModel.load()
        #expect(viewModel.categories.contains("Audio"))

        await viewModel.select(category: "Accessories")
        #expect(viewModel.products.map(\.name) == ["Mechanical Keyboard", "Wireless Mouse"])
        #expect(viewModel.totalCount == 2)
        #expect(!viewModel.hasNextPage)

        await viewModel.select(category: nil)
        #expect(viewModel.totalCount == 10)
    }

    @Test("deleting and clearing the cache")
    func deletion() async throws {
        let harness = try Harness()
        let viewModel = harness.catalogViewModel()
        await viewModel.load()

        await viewModel.delete(at: [0, 1])
        #expect(viewModel.products.count == 2)
        #expect(viewModel.totalCount == 8)
        #expect(try await harness.maintenance.stats().liveProducts == 8)

        await viewModel.clearCache()
        #expect(viewModel.snapshot == nil)
        #expect(try await harness.maintenance.stats().liveProducts == 0)
    }
}

/// Waits (up to 2 s) for main-actor state driven by a live stream to satisfy `condition`.
@MainActor
func eventually(_ condition: @MainActor () -> Bool) async throws {
    for _ in 0..<200 where !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}

@MainActor
@Suite("Notes (live query)")
struct NotesTests {

    /// A view model with `observe()` running, as the Notes tab's `.task` does.
    private func observed(_ harness: Harness) -> (NotesViewModel, Task<Void, Never>) {
        let viewModel = NotesViewModel(useCase: ManageNotesUseCase(repository: harness.notes))
        return (viewModel, Task { await viewModel.observe() })
    }

    @Test("saves, pins and deletes appear without reloading; pinned first, then newest")
    func liveOrdering() async throws {
        let harness = try Harness()
        let (viewModel, observation) = observed(harness)
        defer { observation.cancel() }
        let old = Note(title: "Old", createdAt: .distantPast)
        let new = Note(title: "New", createdAt: .now)

        await viewModel.save(old)
        await viewModel.save(new)
        try await eventually { viewModel.notes.map(\.title) == ["New", "Old"] }

        await viewModel.togglePin(old)
        try await eventually { viewModel.notes.map(\.title) == ["Old", "New"] }

        await viewModel.delete(at: [0])
        try await eventually { viewModel.notes.map(\.title) == ["New"] }
    }

    @Test("writes from elsewhere show up too")
    func externalWrites() async throws {
        let harness = try Harness()
        let (viewModel, observation) = observed(harness)
        defer { observation.cancel() }

        try await harness.notes.save(Note(title: "From another screen"))

        try await eventually { viewModel.notes.map(\.title) == ["From another screen"] }
    }

    @Test("an empty title is rejected and nothing is saved")
    func validation() async throws {
        let harness = try Harness()
        let viewModel = NotesViewModel(useCase: ManageNotesUseCase(repository: harness.notes))

        await viewModel.save(Note(title: "   "))

        #expect(viewModel.errorMessage == "A note needs a title.")
        #expect(try await harness.notes.all().isEmpty)
    }
}

@MainActor
@Suite("Settings & maintenance")
struct SettingsTests {

    @Test("settings round-trip through key-value storage")
    func persistence() async throws {
        let harness = try Harness()
        let viewModel = SettingsViewModel(repository: harness.settings)
        await viewModel.load()

        viewModel.settings.appearance = .dark
        viewModel.settings.cacheLifetime = .fiveMinutes
        await viewModel.flush()

        #expect(try await harness.settings.load() == AppSettings(appearance: .dark, cacheLifetime: .fiveMinutes))
    }

    @Test("launches are counted and the previous launch remembered")
    func launches() async throws {
        let harness = try Harness()
        let first = try await harness.settings.recordLaunch(at: Date(timeIntervalSince1970: 100))
        let second = try await harness.settings.recordLaunch(at: Date(timeIntervalSince1970: 200))

        #expect(first == LaunchInfo(count: 1, previousLaunch: nil))
        #expect(second == LaunchInfo(count: 2, previousLaunch: Date(timeIntervalSince1970: 100)))
    }

    @Test("the Inspector follows live changes and refreshes counts")
    func activityFeed() async throws {
        let harness = try Harness()
        let viewModel = InspectorViewModel(repository: harness.maintenance, logFeed: StorageLogFeed())
        let observation = Task { await viewModel.observe() }
        defer { observation.cancel() }
        // The feed subscribes inside the task; write warm-ups until it has demonstrably started.
        let warmUp = Note(title: "warm-up")
        while viewModel.activity.isEmpty {
            try await harness.notes.save(warmUp)
            try await Task.sleep(for: .milliseconds(10))
        }
        try await harness.notes.delete([warmUp])
        try await eventually { viewModel.activity.first?.kind == .deleted }

        let note = Note(title: "Hello")
        try await harness.notes.save(note)
        try await harness.notes.delete([note])

        try await eventually { viewModel.activity.first?.detail == "Hello" && viewModel.activity.first?.kind == .deleted }
        #expect(viewModel.activity.prefix(2).map(\.kind) == [.deleted, .inserted])
        #expect(viewModel.activity.prefix(2).map(\.detail) == ["Hello", "Hello"])
        try await eventually { viewModel.stats.notes == 0 }
    }

    @Test("remove expired and delete all")
    func maintenance() async throws {
        let harness = try Harness()
        let viewModel = InspectorViewModel(repository: harness.maintenance, logFeed: StorageLogFeed())
        await harness.catalogViewModel().load()
        try await harness.notes.save(Note(title: "Keep"))

        harness.clock.advance(by: 3_600)
        await viewModel.removeExpired()
        #expect(viewModel.statusMessage == "Removed 10 expired records.")
        #expect(viewModel.stats == StorageStats(liveProducts: 0, notes: 1))

        await viewModel.deleteAll()
        #expect(viewModel.stats == StorageStats(liveProducts: 0, notes: 0))
    }
}
