import Foundation
import Observation

@MainActor @Observable
final class CatalogViewModel {
    private(set) var snapshot: CatalogSnapshot?
    private(set) var isLoading = false
    var errorMessage: String?

    private let loadCatalog: LoadCatalogUseCase
    private let repository: any ProductRepository

    init(loadCatalog: LoadCatalogUseCase, repository: any ProductRepository) {
        self.loadCatalog = loadCatalog
        self.repository = repository
    }

    var products: [Product] { snapshot?.products ?? [] }

    /// Serves the cache when it is live; `forceRefresh` always goes to the network.
    func load(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await loadCatalog(forceRefresh: forceRefresh)
        } catch {
            errorMessage = describe(error)
        }
    }

    func delete(at offsets: IndexSet) async {
        let doomed = offsets.map { products[$0] }
        do {
            try await repository.delete(doomed)
            snapshot?.products.removeAll { product in doomed.contains { $0.id == product.id } }
        } catch {
            errorMessage = describe(error)
        }
    }

    func clearCache() async {
        do {
            try await repository.clearCache()
            snapshot = nil
        } catch {
            errorMessage = describe(error)
        }
    }
}
