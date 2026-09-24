import os

/// Verbosity of storage logging. Ordered from quietest to loudest.
public enum StorageLogLevel: Int, Sendable, Comparable, CaseIterable {
    /// Log nothing.
    case none = 0
    /// Failed operations only.
    case error
    /// Writes and deletes: operation, key, byte count.
    case info
    /// `info` plus reads.
    case debug

    public static func < (lhs: StorageLogLevel, rhs: StorageLogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The logging sink. ``LocalStorage`` builds each line and skips the call entirely when the
/// configured ``StorageLogLevel`` filters it out. Lines carry operation, key and byte count —
/// never payload contents.
///
/// Default: ``NoopStorageLogger``.
public protocol StorageLogger: Sendable {
    func log(_ line: String, level: StorageLogLevel)
}

/// Discards everything.
public struct NoopStorageLogger: StorageLogger {
    public init() {}
    public func log(_ line: String, level: StorageLogLevel) {}
}

/// Writes to the unified logging system (`os.Logger`).
public struct OSLogStorageLogger: StorageLogger {
    private let logger: Logger

    public init(subsystem: String = "SwiftLocalStorage", category: String = "storage") {
        logger = Logger(subsystem: subsystem, category: category)
    }

    public func log(_ line: String, level: StorageLogLevel) {
        switch level {
        case .none: break
        case .error: logger.error("\(line, privacy: .public)")
        case .info: logger.info("\(line, privacy: .public)")
        case .debug: logger.debug("\(line, privacy: .public)")
        }
    }
}
