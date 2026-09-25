import Foundation
import Observation

@MainActor @Observable
final class InspectorViewModel {
    private(set) var stats = StorageStats(liveProducts: 0, notes: 0)
    private(set) var statusMessage: String?
    /// Newest first, capped at 50.
    private(set) var activity: [StorageActivity] = []
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

    /// Follows the live change feed for as long as the calling task runs; counts refresh on every change.
    func observe() async {
        for await event in repository.activity() {
            activity.insert(event, at: 0)
            if activity.count > 50 { activity.removeLast() }
            await refresh()
        }
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
            statusMessage = "All data deleted."
        } catch {
            errorMessage = describe(error)
        }
        await refresh()
    }
}
