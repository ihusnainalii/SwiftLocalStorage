# Testing

Use an in-memory store in unit tests and SwiftUI previews.

## In-memory configuration

``LocalStorageConfiguration/inMemory`` keeps everything in memory and needs no cleanup, so each
test can create its own storage:

```swift
@Test func savesUser() async throws {
    let storage = try LocalStorage(configuration: .inMemory)
    try await storage.save(User(id: 1, name: "Ada"))
    #expect(try await storage.fetch(User.self, id: 1)?.name == "Ada")
}
```

## Controlling time

To test expiration without waiting, the testing SPI lets you inject a clock:

```swift
@_spi(SwiftLocalStorageTesting) import SwiftLocalStorage

final class Clock: @unchecked Sendable { var now = Date() }

let clock = Clock()
let storage = try LocalStorage(configuration: .inMemory, now: { clock.now })
try await storage.save(user, expiration: .hours(1))
clock.now += 2 * 3_600                                   // two hours later
#expect(try await storage.fetch(User.self, id: user.id) == nil)
```

SPI declarations are for tests only and aren't covered by the stability promise in
<doc:APIStability>.
