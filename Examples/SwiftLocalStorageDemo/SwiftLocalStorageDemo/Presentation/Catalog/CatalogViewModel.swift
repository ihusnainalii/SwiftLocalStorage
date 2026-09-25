import Foundation
import Observation

@MainActor @Observable
final class CatalogViewModel {
    static let pageSize = 4

    /// Cache status of the last load (source, cached time, expiry).
    private(set) var snapshot: CatalogSnapshot?
    /// The pages loaded so far from the cache, in the user's sort order.
    private(set) var products: [Product] = []
    private(set) var categories: [String] = []
    private(set) var totalCount = 0
    private(set) var hasNextPage = false
    private(set) var isLoading = false
    var errorMessage: String?

    /// `nil` shows every category.
    private(set) var category: String?

    private let loadCatalog: LoadCatalogUseCase
    private let repository: any ProductRepository
    private var loadedPage = 0
    private var sortByPrice = false

    init(loadCatalog: LoadCatalogUseCase, repository: any ProductRepository) {
        self.loadCatalog = loadCatalog
        self.repository = repository
    }

    /// Makes sure the cache is warm (cache-first; `forceRefresh` always hits the network), then
    /// shows the first page.
    func load(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snapshot = try await loadCatalog(forceRefresh: forceRefresh)
            self.snapshot = snapshot
            sortByPrice = snapshot.isSortedByPrice
            categories = Array(Set(snapshot.products.map(\.category))).sorted()
            if let category, !categories.contains(category) { self.category = nil }
            try await reloadPages()
        } catch {
            errorMessage = describe(error)
        }
    }

    /// Appends the next page from the cache.
    func loadNextPage() async {
        guard hasNextPage else { return }
        do {
            try await append(page: loadedPage + 1)
        } catch {
            errorMessage = describe(error)
        }
    }

    func select(category: String?) async {
        self.category = category
        do { try await reloadPages() } catch { errorMessage = describe(error) }
    }

    func delete(at offsets: IndexSet) async {
        let doomed = offsets.map { products[$0] }
        do {
            try await repository.delete(doomed)
            products.removeAll { product in doomed.contains { $0.id == product.id } }
            totalCount -= doomed.count
        } catch {
            errorMessage = describe(error)
        }
    }

    func clearCache() async {
        do {
            try await repository.clearCache()
            snapshot = nil
            products = []
            categories = []
            category = nil
            totalCount = 0
            hasNextPage = false
            loadedPage = 0
        } catch {
            errorMessage = describe(error)
        }
    }

    private func reloadPages() async throws {
        products = []
        loadedPage = 0
        try await append(page: 1)
    }

    private func append(page: Int) async throws {
        let result = try await repository.cachedPage(page, size: Self.pageSize, category: category, sortedByPrice: sortByPrice)
        products += result.products
        loadedPage = page
        totalCount = result.totalCount
        hasNextPage = result.hasNextPage
    }
}
