/// Every stored value of a type, oldest first, fetched `batchSize` records at a time as iteration
/// advances — so a large type is never fully in memory. Created by ``LocalStorage/all(_:batchSize:)``.
///
/// Values inserted during iteration appear at the end. Values deleted during iteration can shift
/// the window by one batch position, so a value may be skipped.
public struct StorageSequence<Element: Identifiable & Codable & Sendable>: AsyncSequence, Sendable {
    let storage: LocalStorage
    let batchSize: Int

    public func makeAsyncIterator() -> Iterator {
        Iterator(storage: storage, batchSize: batchSize)
    }

    public struct Iterator: AsyncIteratorProtocol {
        let storage: LocalStorage
        let batchSize: Int
        private var offset = 0
        private var buffer: [Element] = []
        private var index = 0
        private var exhausted = false

        init(storage: LocalStorage, batchSize: Int) {
            self.storage = storage
            self.batchSize = batchSize
        }

        public mutating func next() async throws -> Element? {
            if index == buffer.count {
                guard !exhausted else { return nil }
                buffer = try await storage.fetch(Element.self, options: FetchOptions(limit: batchSize, offset: offset))
                offset += buffer.count
                index = 0
                exhausted = buffer.count < batchSize
                guard !buffer.isEmpty else { return nil }
            }
            defer { index += 1 }
            return buffer[index]
        }
    }
}
