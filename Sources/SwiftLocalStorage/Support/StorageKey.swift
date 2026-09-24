/// Opt in to a stable storage name for a type.
///
/// By default a type is stored under its module-qualified name (`String(reflecting:)`), so two
/// `User` types in different modules never collide — but renaming or moving the type orphans
/// its stored records. Conform and return a fixed string before shipping to keep them reachable:
///
/// ```swift
/// extension User: LocalStorageNaming {
///     static var storageTypeName: String { "User" }
/// }
/// ```
public protocol LocalStorageNaming {
    static var storageTypeName: String { get }
}

/// Builds record keys. Kinds are namespaced so an entity can never collide with a key-value entry.
enum StorageKey {
    static func typeName<T>(of type: T.Type) -> String {
        (type as? any LocalStorageNaming.Type)?.storageTypeName ?? String(reflecting: type)
    }

    static func entity(typeName: String, id: String) -> String {
        "e|\(typeName)|\(id)"
    }

    static func entity<T: Identifiable>(_ type: T.Type, id: T.ID) -> String {
        entity(typeName: typeName(of: type), id: String(describing: id))
    }

    static func keyValue(_ key: String) -> String {
        "kv|\(key)"
    }
}
