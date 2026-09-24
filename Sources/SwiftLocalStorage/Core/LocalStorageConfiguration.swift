/// How a ``LocalStorage`` is opened.
public struct LocalStorageConfiguration: Sendable {
    /// The store name; distinct names are distinct on-disk stores.
    public var name: String
    /// `true` keeps everything in memory — for tests and previews.
    public var isStoredInMemoryOnly: Bool
    public var encoder: any StorageEncoder
    public var decoder: any StorageDecoder

    public init(
        name: String = "SwiftLocalStorage",
        isStoredInMemoryOnly: Bool = false,
        encoder: any StorageEncoder = JSONStorageEncoder(),
        decoder: any StorageDecoder = JSONStorageDecoder()
    ) {
        self.name = name
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
        self.encoder = encoder
        self.decoder = decoder
    }

    /// An in-memory store; nothing touches the file system.
    public static var inMemory: Self { Self(isStoredInMemoryOnly: true) }
}
