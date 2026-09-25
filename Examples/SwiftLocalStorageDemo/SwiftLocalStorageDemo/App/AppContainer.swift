import Foundation
import SwiftLocalStorage

/// Composition root: the one place that knows every concrete type and wires the layers together.
@MainActor
final class AppContainer {
    let logFeed: StorageLogFeed
    let settings: SettingsViewModel
    let catalog: CatalogViewModel
    let notes: NotesViewModel
    let inspector: InspectorViewModel
    /// The Inspector's activity feed lives as long as the app, not just while its tab is visible.
    private var activityTask: Task<Void, Never>?

    init(storage: LocalStorage, logFeed: StorageLogFeed, api: any ProductAPI = FakeProductAPI()) {
        let productRepository = CachedProductRepository(storage: storage, api: api)
        let settingsRepository = LocalSettingsRepository(storage: storage)
        let noteRepository = LocalNoteRepository(storage: storage)
        let maintenanceRepository = LocalMaintenanceRepository(storage: storage)

        self.logFeed = logFeed
        settings = SettingsViewModel(repository: settingsRepository)
        catalog = CatalogViewModel(
            loadCatalog: LoadCatalogUseCase(products: productRepository, settings: settingsRepository),
            repository: productRepository
        )
        notes = NotesViewModel(useCase: ManageNotesUseCase(repository: noteRepository))
        inspector = InspectorViewModel(repository: maintenanceRepository, logFeed: logFeed)
    }

    /// The real app: an on-disk store with debug logging routed into the Inspector.
    static func live() throws -> AppContainer {
        let logFeed = StorageLogFeed()
        let storage = try LocalStorage(configuration: .init(
            name: "SwiftLocalStorageDemo", logger: logFeed.logger, logLevel: .debug
        ))
        return AppContainer(storage: storage, logFeed: logFeed)
    }

    /// SwiftUI previews: an in-memory store and an instant fake API.
    static func preview() -> AppContainer {
        let logFeed = StorageLogFeed()
        // In-memory SwiftData never touches disk; opening it does not fail in practice.
        let storage = try! LocalStorage(configuration: .init(
            isStoredInMemoryOnly: true, logger: logFeed.logger, logLevel: .debug
        ))
        return AppContainer(storage: storage, logFeed: logFeed, api: FakeProductAPI(latency: .zero))
    }

    /// First-launch work: settings, launch bookkeeping, initial data.
    func start() async {
        activityTask = Task { [inspector] in await inspector.observe() }
        await settings.load()
        await catalog.load()
        await inspector.refresh()
    }
}
