import Foundation
import Observation

@MainActor @Observable
final class InspectorViewModel {
    private(set) var stats = StorageStats(liveProducts: 0, notes: 0)
    private(set) var statusMessage: String?
    var errorMessage: String?
    let logFeed: StorageLogFeed

    private let repository: any MaintenanceRepository

    init(repository: any MaintenanceRepository, logFeed: StorageLogFeed) {
        self.repository = repository
        self.logFeed = logFeed
    }

    func refresh() async {
        do { stats = try await repository.stats() } catch { errorMessage = describe(error) }
    }

    func removeExpired() async {
        do {
            let removed = try await repository.removeExpired()
            statusMessage = "Removed \(removed) expired record\(removed == 1 ? "" : "s")."
        } catch {
            errorMessage = describe(error)
        }
        await refresh()
    }

    func deleteAll() async {
        do {
            try await repository.removeAll()
            statusMessage = "All data deleted. Other tabs reload on their next action."
        } catch {
            errorMessage = describe(error)
        }
        await refresh()
    }
}
