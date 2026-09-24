import Foundation

extension LocalStorage {
    /// Builds a storage over any engine with an injectable clock — for tests only.
    @_spi(SwiftLocalStorageTesting) public convenience init(
        configuration: LocalStorageConfiguration = .inMemory,
        engine: InMemoryStorageEngine,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(configuration: configuration, engine: engine as any StorageEngine, now: now)
    }

    /// Opens a SwiftData store with an injectable clock — for tests only.
    @_spi(SwiftLocalStorageTesting) public convenience init(
        configuration: LocalStorageConfiguration,
        now: @escaping @Sendable () -> Date
    ) throws {
        let engine: SwiftDataEngine
        do {
            engine = try SwiftDataEngine.make(configuration: configuration)
        } catch {
            throw LocalStorageError.containerInitializationFailed(underlying: error)
        }
        self.init(configuration: configuration, engine: engine, now: now)
    }
}
