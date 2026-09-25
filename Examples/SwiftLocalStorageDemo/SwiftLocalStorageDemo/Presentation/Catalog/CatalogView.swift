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
                if !viewModel.categories.isEmpty {
                    Section {
                        CategoryChips(categories: viewModel.categories, selected: viewModel.category) { category in
                            Task { await viewModel.select(category: category) }
                        }
                    } footer: {
                        Text("Filtered and sorted on indexed fields inside the store: page(_:matching:orderedBy:).")
                    }
                }
                Section {
                    if viewModel.products.isEmpty, !viewModel.isLoading {
                        ContentUnavailableView(
                            "No cached products", systemImage: "bag",
                            description: Text("The cache is empty or has expired. Tap Load to fetch again, or pull to refresh.")
                        )
                    }
                    ForEach(viewModel.products) { ProductRow(product: $0) }
                        .onDelete { offsets in Task { await viewModel.delete(at: offsets) } }
                    if viewModel.hasNextPage {
                        Button("Load more (\(viewModel.products.count) of \(viewModel.totalCount))", systemImage: "chevron.down") {
                            Task { await viewModel.loadNextPage() }
                        }
                    }
                } header: {
                    Text("Products")
                } footer: {
                    if viewModel.totalCount > 0 {
                        Text("Showing \(viewModel.products.count) of \(viewModel.totalCount), \(CatalogViewModel.pageSize) per page.")
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Fetching…")
                        .padding()
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
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

private struct CategoryChips: View {
    let categories: [String]
    let selected: String?
    let onSelect: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", isOn: selected == nil) { onSelect(nil) }
                ForEach(categories, id: \.self) { category in
                    chip(category, isOn: selected == category) { onSelect(category) }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .tint(isOn ? .accentColor : .secondary)
            .accessibilityAddTraits(isOn ? .isSelected : [])
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
