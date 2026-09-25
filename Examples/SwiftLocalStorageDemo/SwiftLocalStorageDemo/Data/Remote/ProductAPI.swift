import Foundation

/// The remote data source. In a real app this would be a SwiftNetworkKit endpoint.
protocol ProductAPI: Sendable {
    func fetchProducts() async throws -> [Product]
    var requestCount: Int { get async }
}

/// Simulated network: slow, and returns slightly different prices on each call so a refresh is
/// visibly different from a cache hit.
actor FakeProductAPI: ProductAPI {
    private(set) var requestCount = 0
    private let latency: Duration

    init(latency: Duration = .milliseconds(900)) {
        self.latency = latency
    }

    func fetchProducts() async throws -> [Product] {
        requestCount += 1
        try await Task.sleep(for: latency)
        let catalog: [(String, String, Double, String)] = [
            ("Studio Headphones", "Audio", 199, "headphones"),
            ("Mechanical Keyboard", "Accessories", 129, "keyboard"),
            ("4K Monitor", "Displays", 449, "display"),
            ("Wireless Mouse", "Accessories", 59, "computermouse"),
            ("Smart Speaker", "Audio", 99, "hifispeaker"),
            ("Action Camera", "Cameras", 329, "camera"),
            ("E-Reader", "Tablets", 139, "book.closed"),
            ("Smart Watch", "Wearables", 249, "applewatch"),
            ("Game Controller", "Gaming", 69, "gamecontroller"),
            ("Portable SSD", "Storage", 119, "externaldrive"),
        ]
        return catalog.enumerated().map { index, item in
            Product(
                id: index + 1, name: item.0, category: item.1,
                price: (item.2 * Double.random(in: 0.9...1.1)).rounded(), symbol: item.3
            )
        }
    }
}
