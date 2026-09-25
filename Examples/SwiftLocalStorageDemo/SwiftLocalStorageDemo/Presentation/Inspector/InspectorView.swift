import SwiftUI

/// Looks inside the store: record counts, maintenance actions and the live storage log.
struct InspectorView: View {
    @Bindable var viewModel: InspectorViewModel
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationStack {
            List {
                Section("Records") {
                    LabeledContent("Products (live)", value: "\(viewModel.stats.liveProducts)")
                    LabeledContent("Notes", value: "\(viewModel.stats.notes)")
                }

                Section {
                    Button("Remove expired records", systemImage: "clock.badge.xmark") {
                        Task { await viewModel.removeExpired() }
                    }
                    Button("Delete all data", systemImage: "trash", role: .destructive) {
                        confirmDeleteAll = true
                    }
                } header: {
                    Text("Maintenance")
                } footer: {
                    if let message = viewModel.statusMessage { Text(message) }
                }

                Section {
                    if viewModel.activity.isEmpty {
                        Text("Save, edit or delete something in another tab.").foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.activity.prefix(10)) { ActivityRow(event: $0) }
                } header: {
                    Text("Live changes")
                } footer: {
                    Text("From changes(of:), delivered after each write commits.")
                }

                Section {
                    if viewModel.logFeed.entries.isEmpty {
                        Text("No log lines yet.").foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.logFeed.entries) { LogRow(entry: $0) }
                } header: {
                    HStack {
                        Text("Storage log")
                        Spacer()
                        Button("Clear") { viewModel.logFeed.clear() }.font(.caption)
                    }
                } footer: {
                    Text("Operation, key and byte count only. Payloads are never logged.")
                }
            }
            .navigationTitle("Inspector")
            .refreshable { await viewModel.refresh() }
            .task { await viewModel.refresh() }
            .confirmationDialog("Delete every record in the store?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete all data", role: .destructive) { Task { await viewModel.deleteAll() } }
            }
            .errorAlert($viewModel.errorMessage)
        }
    }
}

private struct ActivityRow: View {
    let event: StorageActivity

    var body: some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 24)
            VStack(alignment: .leading) {
                Text("\(event.entity) \(event.kind.rawValue)").font(.subheadline.bold())
                if let detail = event.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(event.date, format: .dateTime.hour().minute().second())
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch event.kind {
        case .inserted: "plus.circle.fill"
        case .updated: "pencil.circle.fill"
        case .deleted: "minus.circle.fill"
        case .cleared: "trash.circle.fill"
        case .expired: "clock.badge.xmark"
        }
    }

    private var color: Color {
        switch event.kind {
        case .inserted: .green
        case .updated: .blue
        case .deleted, .cleared: .red
        case .expired: .orange
        }
    }
}

private struct LogRow: View {
    let entry: StorageLogFeed.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.level.rawValue).font(.caption2.bold()).foregroundStyle(color)
                Text(entry.date, format: .dateTime.hour().minute().second())
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(entry.message).font(.caption.monospaced()).lineLimit(3)
        }
    }

    private var color: Color {
        switch entry.level {
        case .error: .red
        case .info: .blue
        case .debug: .secondary
        }
    }
}

#Preview {
    let container = AppContainer.preview()
    InspectorView(viewModel: container.inspector)
}
