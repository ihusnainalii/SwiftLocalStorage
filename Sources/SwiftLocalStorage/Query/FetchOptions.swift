/// The order records come back in. Ties are broken by insertion order, so every order is total
/// and stable.
public enum StorageSort: Sendable, Hashable, CaseIterable {
    /// First saved first (by `createdAt`). The default.
    case oldestFirst
    /// Last saved first (by `createdAt`).
    case newestFirst
    /// Most recently updated first (by `updatedAt`).
    case recentlyUpdated
    /// Least recently updated first (by `updatedAt`).
    case leastRecentlyUpdated
}

/// Sorting and slicing for a fetch.
///
/// ```swift
/// let latest = try await storage.fetch(User.self, options: FetchOptions(sort: .newestFirst, limit: 20))
/// ```
public struct FetchOptions: Sendable, Hashable {
    public var sort: StorageSort
    /// The maximum number of values to return; `nil` means no limit. Must not be negative.
    public var limit: Int?
    /// How many values to skip after sorting. Must not be negative.
    public var offset: Int

    public init(sort: StorageSort = .oldestFirst, limit: Int? = nil, offset: Int = 0) {
        precondition(limit.map { $0 >= 0 } ?? true, "FetchOptions.limit must not be negative")
        precondition(offset >= 0, "FetchOptions.offset must not be negative")
        self.sort = sort
        self.limit = limit
        self.offset = offset
    }

    /// Everything, oldest first — what `fetch(_:)` returns.
    public static let `default` = FetchOptions()
}

/// One page of values plus the totals needed to drive paging UI.
public struct StoragePage<Element: Sendable>: Sendable {
    public let items: [Element]
    /// 1-based page number.
    public let page: Int
    public let pageSize: Int
    /// Live values of the type across all pages.
    public let totalCount: Int

    public init(items: [Element], page: Int, pageSize: Int, totalCount: Int) {
        self.items = items
        self.page = page
        self.pageSize = pageSize
        self.totalCount = totalCount
    }

    /// `0` when there is nothing stored.
    public var totalPages: Int { (totalCount + pageSize - 1) / pageSize }

    public var hasNextPage: Bool { page < totalPages }
}

extension StoragePage: Equatable where Element: Equatable {}
