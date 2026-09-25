// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SwiftLocalStorage",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "SwiftLocalStorage", targets: ["SwiftLocalStorage"]),
    ],
    targets: [
        .target(
            name: "SwiftLocalStorage",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Not a product: `swift run -c release SwiftLocalStorageBenchmarks`.
        .executableTarget(
            name: "SwiftLocalStorageBenchmarks",
            dependencies: ["SwiftLocalStorage"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwiftLocalStorageTests",
            dependencies: ["SwiftLocalStorage"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
