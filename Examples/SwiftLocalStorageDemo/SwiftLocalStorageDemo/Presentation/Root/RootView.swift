import SwiftUI

struct RootView: View {
    let container: AppContainer

    var body: some View {
        TabView {
            CatalogView(viewModel: container.catalog)
                .tabItem { Label("Catalog", systemImage: "bag") }
            NotesView(viewModel: container.notes)
                .tabItem { Label("Notes", systemImage: "note.text") }
            SettingsView(viewModel: container.settings)
                .tabItem { Label("Settings", systemImage: "gearshape") }
            InspectorView(viewModel: container.inspector)
                .tabItem { Label("Inspector", systemImage: "cylinder.split.1x2") }
        }
        .preferredColorScheme(container.settings.settings.appearance.colorScheme)
    }
}

extension AppSettings.Appearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Shows a view model's latest error as an alert.
struct ErrorAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert("Something went wrong", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}

extension View {
    func errorAlert(_ message: Binding<String?>) -> some View {
        modifier(ErrorAlert(message: message))
    }
}

/// Human-readable text for any error the view models surface.
func describe(_ error: any Error) -> String {
    if let error = error as? ManageNotesUseCase.ValidationError, error == .emptyTitle {
        return "A note needs a title."
    }
    return String(describing: error)
}

#Preview {
    let container = AppContainer.preview()
    RootView(container: container).task { await container.start() }
}
