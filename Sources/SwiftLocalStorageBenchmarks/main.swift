// Timings for the core SwiftLocalStorage operations against a real on-disk store.
// Run in release mode: swift run -c release SwiftLocalStorageBenchmarks
import Foundation
import SwiftLocalStorage

struct Record: Codable, Identifiable, Sendable, LocalStorageIndexed {
    let id: Int
    var category: String
    var score: Double
    var body: String

    static var storageIndexes: [StorageIndex<Record>] {
        [.string("category") { $0.category }]
    }
}

struct Blob: Codable, Identifiable, Sendable {
    let id: Int
    var bytes: Data
}

let runs = 5
let storage = try LocalStorage(configuration: .init(name: "SwiftLocalStorageBenchmarks"))
try await storage.removeAll()

func records(_ count: Int) -> [Record] {
    (0..<count).map {
        Record(id: $0, category: $0.isMultiple(of: 10) ? "hot" : "cold", score: Double($0), body: "record \($0)")
    }
}

/// Median wall time of `runs` runs of `body`, each after a fresh `setUp`.
func measure(
    setUp: () async throws -> Void = {}, _ body: () async throws -> Void
) async throws -> Duration {
    var samples: [Duration] = []
    for _ in 0..<runs {
        try await setUp()
        let clock = ContinuousClock()
        let start = clock.now
        try await body()
        samples.append(clock.now - start)
    }
    return samples.sorted()[runs / 2]
}

func milliseconds(_ duration: Duration) -> String {
    let (seconds, attoseconds) = duration.components
    return String(format: "%.2f ms", Double(seconds) * 1_000 + Double(attoseconds) / 1e15)
}

var rows: [(String, Duration)] = []
@MainActor func record(_ name: String, _ duration: Duration) { rows.append((name, duration)) }

for count in [1, 100, 1_000] {
    let values = records(count)
    record(
        "save \(count) (one batch)",
        try await measure(setUp: { try await storage.deleteAll(Record.self) }) { try await storage.save(values) })
    record("fetch all of \(count)", try await measure { _ = try await storage.fetch(Record.self) })
    record(
        "deleteAll of \(count)",
        try await measure(setUp: { try await storage.save(values) }) { try await storage.deleteAll(Record.self) })
}

for megabytes in [1, 10] {
    let blob = Blob(id: megabytes, bytes: Data(repeating: 7, count: megabytes * 1_048_576))
    record("save \(megabytes) MB payload", try await measure { try await storage.save(blob) })
    record(
        "fetch(id:) \(megabytes) MB payload",
        try await measure { _ = try await storage.fetch(Blob.self, id: blob.id) })
}

let isHot: @Sendable (Record) -> Bool = { $0.category == "hot" }
try await storage.save(records(1_000))
_ = try await storage.count(Record.self, matching: [.equals("category", "hot")])  // index once
record(
    "filter 1,000 by index (matching:)",
    try await measure { _ = try await storage.fetch(Record.self, matching: [.equals("category", "hot")]) })
record("filter 1,000 by closure (where:)", try await measure { _ = try await storage.fetch(Record.self, where: isHot) })

try await storage.removeAll()

print("| Operation | Median of \(runs) |")
print("|---|---:|")
for (name, duration) in rows { print("| \(name) | \(milliseconds(duration)) |") }
