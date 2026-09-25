import SwiftUI

/// Preferences stored as one key-value entry, plus launch bookkeeping stored as primitives.
struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Appearance", selection: $viewModel.settings.appearance) {
                        ForEach(AppSettings.Appearance.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Toggle("Sort catalog by price", isOn: $viewModel.settings.sortByPrice)
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("Saved instantly as one Codable struct under the key \"settings\".")
                }

                Section {
                    Picker("Catalog cache lifetime", selection: $viewModel.settings.cacheLifetime) {
                        ForEach(AppSettings.CacheLifetime.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Cache")
                } footer: {
                    Text("Applies to the next catalog fetch from the network. Sorting applies on the next Load.")
                }

                Section("Launches") {
                    LabeledContent("Launch count", value: "\(viewModel.launch?.count ?? 0)")
                    LabeledContent("Previous launch") {
                        if let date = viewModel.launch?.previousLaunch {
                            Text(date, format: .dateTime.day().month().hour().minute())
                        } else {
                            Text("First launch")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .errorAlert($viewModel.errorMessage)
        }
    }
}

extension AppSettings.CacheLifetime {
    var label: String {
        switch self {
        case .fifteenSeconds: "15 seconds"
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .never: "Never expires"
        }
    }
}

#Preview {
    let container = AppContainer.preview()
    SettingsView(viewModel: container.settings).task { await container.settings.load() }
}
