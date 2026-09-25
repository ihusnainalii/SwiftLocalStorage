import Foundation
import Observation

@MainActor @Observable
final class SettingsViewModel {
    /// Every change is persisted immediately.
    var settings = AppSettings() {
        didSet {
            guard settings != oldValue, isLoaded else { return }
            let snapshot = settings
            // Chain saves so they land in order: a later change can never be overwritten by an
            // earlier save that happened to finish last.
            pendingSave = Task { [previous = pendingSave] in
                await previous?.value
                await persist(snapshot)
            }
        }
    }
    private(set) var launch: LaunchInfo?
    var errorMessage: String?

    private let repository: any SettingsRepository
    private var isLoaded = false
    private var pendingSave: Task<Void, Never>?

    init(repository: any SettingsRepository) {
        self.repository = repository
    }

    func load() async {
        do {
            settings = try await repository.load()
            launch = try await repository.recordLaunch(at: .now)
        } catch {
            errorMessage = describe(error)
        }
        isLoaded = true
    }

    /// Waits until every queued save has been written.
    func flush() async {
        await pendingSave?.value
    }

    private func persist(_ settings: AppSettings) async {
        do { try await repository.save(settings) } catch { errorMessage = describe(error) }
    }
}
