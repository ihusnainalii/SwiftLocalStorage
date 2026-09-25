import SwiftUI

/// Cache-first catalog: where the data came from, when it was cached, when it expires.
struct CatalogView: View {
    @Bindable var viewModel: CatalogViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CacheStatusCard(snapshot: viewModel.snapshot)
                }
                Section("Products") {
                    ForEach(viewModel.products) { ProductRow(product: $0) }
                        .onDelete { offsets in Task { await viewModel.delete(at: offsets) } }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Fetching…")
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                } else if viewModel.products.isEmpty {
                    ContentUnavailableView(
                        "No cached products", systemImage: "bag",
                        description: Text("Tap Load, or pull to refresh from the network.")
                    )
                }
            }
            .navigationTitle("Catalog")
            .refreshable { await viewModel.load(forceRefresh: true) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Load", systemImage: "arrow.down.circle") {
                        Task { await viewModel.load() }
                    }
                    .disabled(viewModel.isLoading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear cache", systemImage: "trash", role: .destructive) {
                        Task { await viewModel.clearCache() }
                    }
                }
            }
            .errorAlert($viewModel.errorMessage)
        }
    }
}

private struct CacheStatusCard: View {
    let snapshot: CatalogSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sourceBadge
                Spacer()
                Text("API calls: \(snapshot?.networkRequestCount ?? 0)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let snapshot, let cachedAt = snapshot.cachedAt {
                LabeledContent("Cached", value: cachedAt, format: .dateTime.hour().minute().second())
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    LabeledContent("Expires") {
                        Text(expiryText(snapshot.expiresAt, now: context.date))
                            .monospacedDigit()
                            .foregroundStyle(isExpired(snapshot.expiresAt, now: context.date) ? .red : .primary)
                    }
                }
                if let bytes = snapshot.payloadBytesPerItem {
                    LabeledContent("Payload per item", value: "\(bytes) bytes")
                }
            }
            Text("Load serves the live cache first. Pull to refresh always hits the network. Set the cache lifetime in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var sourceBadge: some View {
        switch snapshot?.source {
        case .cache?: Label("Cache hit", systemImage: "bolt.fill").foregroundStyle(.green)
        case .network?: Label("From network", systemImage: "network").foregroundStyle(.blue)
        case nil: Label("Not loaded", systemImage: "circle.dashed").foregroundStyle(.secondary)
        }
    }

    private func isExpired(_ date: Date?, now: Date) -> Bool {
        date.map { $0 <= now } ?? false
    }

    private func expiryText(_ date: Date?, now: Date) -> String {
        guard let date else { return "Never" }
        let remaining = Int(date.timeIntervalSince(now).rounded(.up))
        return remaining > 0 ? "in \(remaining)s" : "Expired, next Load refetches"
    }
}

private struct ProductRow: View {
    let product: Product

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: product.symbol)
                .font(.title2)
                .frame(width: 40, height: 40)
                .background(.tint.opacity(0.12), in: .rect(cornerRadius: 8))
            VStack(alignment: .leading) {
                Text(product.name).font(.headline)
                Text(product.category).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(product.price, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.body.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let container = AppContainer.preview()
    CatalogView(viewModel: container.catalog).task { await container.catalog.load() }
}
