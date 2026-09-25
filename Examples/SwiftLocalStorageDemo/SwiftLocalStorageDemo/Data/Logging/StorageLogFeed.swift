import Foundation
import Observation
import SwiftLocalStorage

/// A live, observable feed of storage log lines for the Inspector.
@MainActor @Observable
final class StorageLogFeed {
    enum Level: String, Sendable { case error = "ERROR", info = "INFO", debug = "DEBUG" }

    struct Entry: Identifiable, Sendable {
        let id = UUID()
        let date: Date
        let level: Level
        let message: String
    }

    private(set) var entries: [Entry] = []

    func append(_ message: String, level: Level) {
        entries.insert(Entry(date: .now, level: level, message: message), at: 0)
        if entries.count > 200 { entries.removeLast(entries.count - 200) }
    }

    func clear() { entries.removeAll() }

    /// A `StorageLogger` that forwards into this feed from any thread.
    nonisolated var logger: any StorageLogger { Forwarder(feed: self) }

    private struct Forwarder: StorageLogger {
        let feed: StorageLogFeed

        func log(_ line: String, level: StorageLogLevel) {
            let mapped: Level = switch level {
            case .error: .error
            case .info: .info
            case .debug, .none: .debug
            }
            let message = line.replacingOccurrences(of: "[SwiftLocalStorage] ", with: "")
            Task { @MainActor in feed.append(message, level: mapped) }
        }
    }
}
