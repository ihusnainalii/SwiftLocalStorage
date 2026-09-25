import SwiftUI

@main
struct SwiftLocalStorageDemoApp: App {
    @State private var container: AppContainer?
    @State private var openError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootView(container: container)
                } else if let openError {
                    ContentUnavailableView(
                        "Couldn't open storage", systemImage: "externaldrive.badge.xmark",
                        description: Text(openError)
                    )
                } else {
                    ProgressView()
                }
            }
            .task {
                guard container == nil, !Self.isRunningTests else { return }
                do {
                    let live = try AppContainer.live()
                    container = live
                    await live.start()
                } catch {
                    openError = String(describing: error)
                }
            }
        }
    }

    /// Unit tests host inside the app; don't open the on-disk store for them.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
