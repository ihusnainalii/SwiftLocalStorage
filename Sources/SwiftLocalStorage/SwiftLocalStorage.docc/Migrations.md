# Migrating Stored DTOs

Read records saved by older app versions after your DTO changes shape.

## Version the type

Conform to ``LocalStorageVersioned``. Types that don't conform are version 1, so records saved
before you added versioning are version 1 too:

```swift
struct User: Codable, Identifiable, Sendable, LocalStorageVersioned {
    static var storageVersion: Int { 2 }
    let id: Int
    var fullName: String            // was `name` in version 1
}
```

## Register the steps

Give each step the version it upgrades *from*. A typed step decodes the old shape; a raw step
edits the stored JSON:

```swift
struct UserV1: Decodable, Sendable { let id: Int; let name: String }

let storage = try LocalStorage(configuration: .init(migrations: [
    StorageMigration(User.self, from: 1) { (old: UserV1) in
        User(id: old.id, fullName: old.name)
    },
]))
```

Reads upgrade old records through the whole chain once, then write the result back, keeping the
record's timestamps and emitting no change events. ``LocalStorage/migrateAll(_:)`` upgrades every
outdated record of a type eagerly.

## Failures

A missing step, a record newer than the app, or a throwing step surfaces as
``LocalStorageError/migrationFailed(key:underlying:)``, whose underlying error is a
``StorageMigrationError`` or your own. The stored record is left untouched.
