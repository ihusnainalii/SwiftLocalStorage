import Foundation

/// A type whose values expose up to three **indexed fields**, stored next to each record so
/// filters, ordering, counts and pages on them run inside the store:
///
/// ```swift
/// extension User: LocalStorageIndexed {
///     static var storageIndexes: [StorageIndex<User>] {
///         [.string("role") { $0.role.rawValue }, .number("age") { $0.age }]
///     }
/// }
/// let admins = try await storage.fetch(User.self, matching: [.equals("role", "admin")])
/// ```
///
/// Changing the declaration is safe: stale records are re-indexed on the next indexed query.
public protocol LocalStorageIndexed {
    static var storageIndexes: [StorageIndex<Self>] { get }
}

/// A value that can back a number index. `Int`, `Double`, `Float`, `Date` and `Bool` conform.
public protocol StorageIndexNumber: Sendable {
    var storageIndexValue: Double { get }
}

extension Int: StorageIndexNumber { public var storageIndexValue: Double { Double(self) } }
extension Int32: StorageIndexNumber { public var storageIndexValue: Double { Double(self) } }
extension Int64: StorageIndexNumber { public var storageIndexValue: Double { Double(self) } }
extension UInt: StorageIndexNumber { public var storageIndexValue: Double { Double(self) } }
extension Double: StorageIndexNumber { public var storageIndexValue: Double { self } }
extension Float: StorageIndexNumber { public var storageIndexValue: Double { Double(self) } }
extension Date: StorageIndexNumber { public var storageIndexValue: Double { timeIntervalSinceReferenceDate } }
extension Bool: StorageIndexNumber { public var storageIndexValue: Double { self ? 1 : 0 } }

/// One indexed field of `Root`: a name and how to compute its value.
public struct StorageIndex<Root>: Sendable {
    enum Kind: String, Sendable { case string = "s", number = "n" }

    public let name: String
    let kind: Kind
    let strings: (@Sendable (Root) -> String?)?
    let numbers: (@Sendable (Root) -> Double?)?

    /// A string index, e.g. `.string("email") { $0.email.lowercased() }`.
    public static func string(_ name: String, _ value: @escaping @Sendable (Root) -> String?) -> Self {
        Self(name: name, kind: .string, strings: value, numbers: nil)
    }

    /// A number index over `Int`, `Double`, `Date`, `Bool`, …, e.g. `.number("age") { $0.age }`.
    public static func number<V: StorageIndexNumber>(
        _ name: String, _ value: @escaping @Sendable (Root) -> V?
    ) -> Self {
        Self(name: name, kind: .number, strings: nil, numbers: { value($0)?.storageIndexValue })
    }
}

/// One condition on an indexed field; conditions passed together are ANDed.
public struct StorageFilter: Sendable, Hashable {
    enum Condition: Sendable, Hashable {
        case stringEquals(String)
        case numberRange(min: Double?, max: Double?)
    }

    let name: String
    let condition: Condition

    public static func equals(_ name: String, _ value: String) -> Self {
        Self(name: name, condition: .stringEquals(value))
    }

    public static func equals<V: StorageIndexNumber>(_ name: String, _ value: V) -> Self {
        Self(name: name, condition: .numberRange(min: value.storageIndexValue, max: value.storageIndexValue))
    }

    public static func atLeast<V: StorageIndexNumber>(_ name: String, _ value: V) -> Self {
        Self(name: name, condition: .numberRange(min: value.storageIndexValue, max: nil))
    }

    public static func atMost<V: StorageIndexNumber>(_ name: String, _ value: V) -> Self {
        Self(name: name, condition: .numberRange(min: nil, max: value.storageIndexValue))
    }

    public static func between<V: StorageIndexNumber & Comparable>(_ name: String, _ range: ClosedRange<V>) -> Self {
        Self(
            name: name,
            condition: .numberRange(min: range.lowerBound.storageIndexValue, max: range.upperBound.storageIndexValue))
    }
}

/// Order by an indexed field. Records without a value sort first ascending, last descending;
/// ties keep insertion order.
public enum StorageIndexOrder: Sendable, Hashable {
    case ascending(String)
    case descending(String)
}

// MARK: - Internals

/// The index values stored with one record.
struct IndexValues: Sendable, Equatable {
    static let slots = 3

    var strings: [String?] = Array(repeating: nil, count: slots)
    var numbers: [Double?] = Array(repeating: nil, count: slots)
    /// Identifies the declaration the values were computed with (`name:kind|…`).
    var signature: String
}

/// What an indexed query asks the engine for, by slot.
struct IndexQuery: Sendable, Equatable {
    struct Order: Sendable, Equatable {
        var slot: Int
        var isString: Bool
        var ascending: Bool
    }

    var strings: [String?] = Array(repeating: nil, count: IndexValues.slots)
    var minimums: [Double?] = Array(repeating: nil, count: IndexValues.slots)
    var maximums: [Double?] = Array(repeating: nil, count: IndexValues.slots)
    var order: Order?

    /// Whether `record` satisfies every condition — the in-memory engine's evaluator.
    func matches(_ values: IndexValues?) -> Bool {
        for slot in 0..<IndexValues.slots {
            if let string = strings[slot], values?.strings[slot] != string { return false }
            if minimums[slot] != nil || maximums[slot] != nil {
                guard let number = values?.numbers[slot] else { return false }
                if let min = minimums[slot], number < min { return false }
                if let max = maximums[slot], number > max { return false }
            }
        }
        return true
    }
}

/// A type's index declaration, validated and resolved to slots.
struct IndexLayout<Root> {
    let indexes: [StorageIndex<Root>]

    init(_ indexes: [StorageIndex<Root>]) {
        precondition(
            indexes.count <= IndexValues.slots, "LocalStorageIndexed supports at most \(IndexValues.slots) indexes")
        precondition(Set(indexes.map(\.name)).count == indexes.count, "LocalStorageIndexed index names must be unique")
        self.indexes = indexes
    }

    var signature: String {
        indexes.map { "\($0.name):\($0.kind.rawValue)" }.joined(separator: "|")
    }

    func values(for value: Root) -> IndexValues {
        var result = IndexValues(signature: signature)
        for (slot, index) in indexes.enumerated() {
            switch index.kind {
            case .string: result.strings[slot] = index.strings?(value)
            case .number: result.numbers[slot] = index.numbers?(value)
            }
        }
        return result
    }

    func query(filters: [StorageFilter], order: StorageIndexOrder?) -> IndexQuery {
        var query = IndexQuery()
        for filter in filters {
            let (slot, kind) = resolve(filter.name)
            switch filter.condition {
            case .stringEquals(let value):
                precondition(kind == .string, "\"\(filter.name)\" is a number index; filter it with a number")
                precondition(
                    query.strings[slot].map { $0 == value } ?? true, "Contradictory filters on \"\(filter.name)\"")
                query.strings[slot] = value
            case .numberRange(let min, let max):
                precondition(kind == .number, "\"\(filter.name)\" is a string index; filter it with a string")
                // Several conditions on one index narrow its range.
                if let min { query.minimums[slot] = Swift.max(query.minimums[slot] ?? min, min) }
                if let max { query.maximums[slot] = Swift.min(query.maximums[slot] ?? max, max) }
            }
        }
        if let order {
            let (name, ascending) =
                switch order {
                case .ascending(let name): (name, true)
                case .descending(let name): (name, false)
                }
            let (slot, kind) = resolve(name)
            query.order = IndexQuery.Order(slot: slot, isString: kind == .string, ascending: ascending)
        }
        return query
    }

    private func resolve(_ name: String) -> (Int, StorageIndex<Root>.Kind) {
        guard let slot = indexes.firstIndex(where: { $0.name == name }) else {
            preconditionFailure("\(Root.self) has no index named \"\(name)\"")
        }
        return (slot, indexes[slot].kind)
    }
}

extension IndexLayout where Root: LocalStorageIndexed {
    init(_ type: Root.Type) {
        self.init(Root.storageIndexes)
    }
}

/// The index values of `value` when its type is ``LocalStorageIndexed``; otherwise `nil`.
func indexValues<T>(for value: T) -> IndexValues? {
    func compute<I: LocalStorageIndexed>(_ value: I) -> IndexValues { IndexLayout(I.self).values(for: value) }
    guard let indexed = value as? any LocalStorageIndexed else { return nil }
    return compute(indexed)
}

/// Which index declaration (signature) each type's stored records are known to be indexed with.
final class IndexedSignatures: @unchecked Sendable {
    private let lock = NSLock()
    private var signatures: [String: String] = [:]

    func isCurrent(_ typeName: String, _ signature: String) -> Bool {
        lock.withLock { signatures[typeName] == signature }
    }

    func markCurrent(_ typeName: String, _ signature: String) {
        lock.withLock { signatures[typeName] = signature }
    }

    /// A write stored `signature` (or no index) for `typeName`: if that isn't the known
    /// declaration, the type must be re-checked before its next indexed query.
    func wrote(_ typeName: String, _ signature: String?) {
        lock.withLock {
            if signatures[typeName] != signature { signatures[typeName] = nil }
        }
    }
}
