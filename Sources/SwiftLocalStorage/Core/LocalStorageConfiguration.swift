/// How a ``LocalStorage`` is opened.
public struct LocalStorageConfiguration: Sendable {
    /// The store name; distinct names are distinct on-disk stores.
    public var name: String
    /// `true` keeps everything in memory — for tests and previews.
    public var isStoredInMemoryOnly: Bool
    public var encoder: any StorageEncoder
    public var decoder: any StorageDecoder
    /// Where log lines go. Lines never contain payloads.
    public var logger: any StorageLogger
    /// The loudest level emitted; `.none` (the default) disables logging.
    public var logLevel: StorageLogLevel

    public init(
        name: String = "SwiftLocalStorage",
        isStoredInMemoryOnly: Bool = false,
        encoder: any StorageEncoder = JSONStorageEncoder(),
        decoder: any StorageDecoder = JSONStorageDecoder(),
        logger: any StorageLogger = NoopStorageLogger(),
        logLevel: StorageLogLevel = .none
    ) {
        self.name = name
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
        self.encoder = encoder
        self.decoder = decoder
        self.logger = logger
        self.logLevel = logLevel
    }

    /// An in-memory store; nothing touches the file system.
    public static var inMemory: Self { Self(isStoredInMemoryOnly: true) }
}
